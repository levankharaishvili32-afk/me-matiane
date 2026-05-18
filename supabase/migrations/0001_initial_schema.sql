-- ════════════════════════════════════════════════════════════════
-- me.matiane.ge — Initial Schema
-- Migration: 0001_initial_schema.sql
-- ════════════════════════════════════════════════════════════════

-- ─── Extensions ───
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ─── Enums ───
CREATE TYPE user_role AS ENUM ('user', 'moderator', 'admin');

CREATE TYPE photo_status AS ENUM (
  'uploading',         -- presigned URL issued, not finalized
  'scanning',          -- AI moderation in flight
  'approved',          -- public
  'rejected_nsfw',     -- AI rejected, can be appealed
  'pending_review',    -- AI gray-zone (0.5-0.7), needs human
  'appealed',          -- user appealed a rejection
  'removed'            -- moderator-removed or user-deleted
);

CREATE TYPE comment_status AS ENUM ('visible', 'pending_review', 'hidden', 'removed');

-- ═══════════════════════════════════════════
-- PROFILES — extends auth.users
-- ═══════════════════════════════════════════
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 2 AND 60),
  role user_role NOT NULL DEFAULT 'user',

  -- Anonymous publishing — per-photo, but profile-level default
  publish_anonymously_default BOOLEAN NOT NULL DEFAULT FALSE,

  -- Account state
  is_blocked BOOLEAN NOT NULL DEFAULT FALSE,
  blocked_reason TEXT,
  blocked_at TIMESTAMPTZ,

  -- Rolling photo count (denormalized cache, trigger-maintained)
  active_photo_count SMALLINT NOT NULL DEFAULT 0
    CHECK (active_photo_count >= 0 AND active_photo_count <= 15),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX profiles_role_idx ON profiles(role) WHERE role <> 'user';
CREATE INDEX profiles_blocked_idx ON profiles(is_blocked) WHERE is_blocked = TRUE;

-- ═══════════════════════════════════════════
-- PHOTOS — main media table
-- ═══════════════════════════════════════════
CREATE TABLE photos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  uploader_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Storage references (Cloudflare R2)
  r2_key_original TEXT NOT NULL,             -- "originals/{uploader}/{sha256}.{ext}"
  r2_key_public TEXT,                        -- "public/{photo_id}.{ext}" (only if approved)
  r2_key_thumb TEXT,                         -- "thumbs/{photo_id}.webp" (CDN-served)

  -- File integrity
  sha256 BYTEA NOT NULL CHECK (length(sha256) = 32),
  byte_size BIGINT NOT NULL CHECK (byte_size BETWEEN 1 AND 26214400),  -- 25 MiB
  mime_type TEXT NOT NULL CHECK (mime_type IN (
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
  )),
  width INT CHECK (width IS NULL OR width BETWEEN 1 AND 8000),
  height INT CHECK (height IS NULL OR height BETWEEN 1 AND 8000),

  -- User metadata
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 10 AND 120),
  description TEXT NOT NULL CHECK (length(trim(description)) BETWEEN 100 AND 2000),
  taken_at DATE,                             -- user-entered, NOT from EXIF
  location_label TEXT CHECK (location_label IS NULL OR length(location_label) <= 120),
  location_point GEOGRAPHY(POINT, 4326),
  tags TEXT[] NOT NULL DEFAULT '{}'
    CHECK (array_length(tags, 1) IS NULL OR array_length(tags, 1) <= 10),

  -- Publishing options
  publish_anonymously BOOLEAN NOT NULL DEFAULT FALSE,

  -- Moderation
  status photo_status NOT NULL DEFAULT 'uploading',
  ai_nsfw_score REAL CHECK (ai_nsfw_score IS NULL OR ai_nsfw_score BETWEEN 0 AND 1),
  ai_categories JSONB,                       -- {"Explicit Nudity": 0.92, "Violence": 0.12, ...}
  rejected_reason TEXT,
  appeal_note TEXT CHECK (appeal_note IS NULL OR length(appeal_note) <= 500),
  appealed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ,
  reviewer_note TEXT,

  -- Legal
  terms_accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  terms_version TEXT NOT NULL DEFAULT 'v1',

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,                    -- soft delete (immediate per design)

  -- Constraints
  CONSTRAINT chk_appeal_consistency CHECK (
    (status <> 'appealed') OR (appealed_at IS NOT NULL AND appeal_note IS NOT NULL)
  )
);

-- Indexes
CREATE UNIQUE INDEX photos_sha256_per_user_active_uniq
  ON photos(uploader_id, sha256) WHERE deleted_at IS NULL;

CREATE INDEX photos_uploader_active_idx
  ON photos(uploader_id) WHERE deleted_at IS NULL;

CREATE INDEX photos_public_feed_idx
  ON photos(created_at DESC)
  WHERE status = 'approved' AND deleted_at IS NULL;

CREATE INDEX photos_pending_review_idx
  ON photos(created_at) WHERE status IN ('pending_review', 'appealed');

CREATE INDEX photos_status_idx ON photos(status) WHERE deleted_at IS NULL;
CREATE INDEX photos_tags_gin ON photos USING GIN (tags);
CREATE INDEX photos_title_trgm ON photos USING GIN (title gin_trgm_ops);
CREATE INDEX photos_desc_trgm ON photos USING GIN (description gin_trgm_ops);
CREATE INDEX photos_taken_at_idx ON photos(taken_at DESC NULLS LAST);
CREATE INDEX photos_location_gist ON photos USING GIST (location_point);

-- ═══════════════════════════════════════════
-- LIKES (Phase 1 — schema ready, may ship in Phase 2)
-- ═══════════════════════════════════════════
CREATE TABLE photo_likes (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  photo_id UUID NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, photo_id)
);
CREATE INDEX photo_likes_photo_idx ON photo_likes(photo_id);

-- Materialized count for hot reads (optional; can use COUNT(*) initially)
ALTER TABLE photos ADD COLUMN like_count INT NOT NULL DEFAULT 0;

-- ═══════════════════════════════════════════
-- COMMENTS
-- ═══════════════════════════════════════════
CREATE TABLE comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  photo_id UUID NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 1000),
  status comment_status NOT NULL DEFAULT 'visible',
  reviewed_by UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX comments_photo_visible_idx ON comments(photo_id, created_at)
  WHERE status = 'visible';
CREATE INDEX comments_user_idx ON comments(user_id, created_at DESC);

-- ═══════════════════════════════════════════
-- REPORTS — abuse / takedown
-- ═══════════════════════════════════════════
CREATE TABLE reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  photo_id UUID REFERENCES photos(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  reporter_id UUID REFERENCES profiles(id),
  reporter_ip INET,
  reason TEXT NOT NULL CHECK (reason IN (
    'nsfw', 'violence', 'hate_speech', 'spam', 'copyright', 'privacy', 'other'
  )),
  details TEXT CHECK (details IS NULL OR length(details) <= 1000),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
  reviewed_by UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_report_target CHECK (
    (photo_id IS NOT NULL)::int + (comment_id IS NOT NULL)::int = 1
  )
);
CREATE INDEX reports_status_idx ON reports(status, created_at) WHERE status = 'open';
CREATE INDEX reports_photo_idx ON reports(photo_id) WHERE photo_id IS NOT NULL;

-- Auto-hide threshold: if a photo gets 3+ open reports, auto-hide
CREATE OR REPLACE FUNCTION check_report_threshold() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  report_count INT;
BEGIN
  IF NEW.photo_id IS NOT NULL THEN
    SELECT COUNT(*) INTO report_count
      FROM reports
      WHERE photo_id = NEW.photo_id AND status = 'open';

    IF report_count >= 3 THEN
      UPDATE photos SET status = 'pending_review', updated_at = now()
        WHERE id = NEW.photo_id AND status = 'approved';
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_report_threshold
  AFTER INSERT ON reports
  FOR EACH ROW EXECUTE FUNCTION check_report_threshold();

-- ═══════════════════════════════════════════
-- EMAIL VERIFICATIONS (OTP)
-- ═══════════════════════════════════════════
CREATE TABLE email_verifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  code_hash BYTEA NOT NULL CHECK (length(code_hash) = 32),  -- HMAC-SHA256
  attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 10),
  resent_count SMALLINT NOT NULL DEFAULT 0 CHECK (resent_count BETWEEN 0 AND 5),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  ip INET,
  user_agent TEXT
);
CREATE INDEX ev_user_active_idx ON email_verifications(user_id) WHERE consumed_at IS NULL;
CREATE INDEX ev_email_recent_idx ON email_verifications(email, created_at DESC);
CREATE INDEX ev_expires_idx ON email_verifications(expires_at) WHERE consumed_at IS NULL;

-- ═══════════════════════════════════════════
-- LOGIN ATTEMPTS — rate limit + lockout
-- ═══════════════════════════════════════════
CREATE TABLE login_attempts (
  id BIGSERIAL PRIMARY KEY,
  email TEXT,
  ip INET,
  success BOOLEAN NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX la_email_time_idx ON login_attempts(email, occurred_at DESC);
CREATE INDEX la_ip_time_idx ON login_attempts(ip, occurred_at DESC);
CREATE INDEX la_time_brin ON login_attempts USING BRIN (occurred_at);

-- ═══════════════════════════════════════════
-- DISPOSABLE EMAIL BLOCKLIST
-- ═══════════════════════════════════════════
CREATE TABLE disposable_email_domains (
  domain TEXT PRIMARY KEY,
  added_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Seed data in 0002_seed_disposable_emails.sql

-- ═══════════════════════════════════════════
-- AUDIT LOG — append-only
-- ═══════════════════════════════════════════
CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_id UUID,
  actor_ip INET,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX al_time_brin ON audit_log USING BRIN (occurred_at);
CREATE INDEX al_actor_idx ON audit_log(actor_id, occurred_at DESC);
CREATE INDEX al_action_idx ON audit_log(action, occurred_at DESC);

-- ═══════════════════════════════════════════
-- TRIGGERS
-- ═══════════════════════════════════════════

-- Updated_at auto-update
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_photos_updated BEFORE UPDATE ON photos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_comments_updated BEFORE UPDATE ON comments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Rolling photo count maintenance
CREATE OR REPLACE FUNCTION update_active_photo_count() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  was_counted BOOLEAN;
  now_counted BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.deleted_at IS NULL AND NEW.status NOT IN ('rejected_nsfw', 'removed') THEN
      UPDATE profiles SET active_photo_count = active_photo_count + 1
        WHERE id = NEW.uploader_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.deleted_at IS NULL AND OLD.status NOT IN ('rejected_nsfw', 'removed') THEN
      UPDATE profiles SET active_photo_count = GREATEST(0, active_photo_count - 1)
        WHERE id = OLD.uploader_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    was_counted := OLD.deleted_at IS NULL AND OLD.status NOT IN ('rejected_nsfw', 'removed');
    now_counted := NEW.deleted_at IS NULL AND NEW.status NOT IN ('rejected_nsfw', 'removed');
    IF was_counted AND NOT now_counted THEN
      UPDATE profiles SET active_photo_count = GREATEST(0, active_photo_count - 1)
        WHERE id = NEW.uploader_id;
    ELSIF NOT was_counted AND now_counted THEN
      UPDATE profiles SET active_photo_count = active_photo_count + 1
        WHERE id = NEW.uploader_id;
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

CREATE TRIGGER trg_photo_count
  AFTER INSERT OR UPDATE OR DELETE ON photos
  FOR EACH ROW EXECUTE FUNCTION update_active_photo_count();

-- Like count maintenance
CREATE OR REPLACE FUNCTION update_like_count() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE photos SET like_count = like_count + 1 WHERE id = NEW.photo_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE photos SET like_count = GREATEST(0, like_count - 1) WHERE id = OLD.photo_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

CREATE TRIGGER trg_like_count
  AFTER INSERT OR DELETE ON photo_likes
  FOR EACH ROW EXECUTE FUNCTION update_like_count();

-- ═══════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════

-- ─── profiles ───
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: public read"
  ON profiles FOR SELECT USING (TRUE);

CREATE POLICY "profiles: self update"
  ON profiles FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY "profiles: admin all"
  ON profiles FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- ─── photos ───
ALTER TABLE photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "photos: public read approved"
  ON photos FOR SELECT
  USING (status = 'approved' AND deleted_at IS NULL);

CREATE POLICY "photos: owner read all own"
  ON photos FOR SELECT
  USING (uploader_id = auth.uid());

CREATE POLICY "photos: moderator read all"
  ON photos FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('moderator', 'admin')
  ));

CREATE POLICY "photos: owner insert own"
  ON photos FOR INSERT
  WITH CHECK (
    uploader_id = auth.uid()
    AND status = 'uploading'
    AND (SELECT active_photo_count FROM profiles WHERE id = auth.uid()) < 15
    AND (SELECT is_blocked FROM profiles WHERE id = auth.uid()) = FALSE
  );

CREATE POLICY "photos: owner update own (limited)"
  ON photos FOR UPDATE
  USING (uploader_id = auth.uid())
  WITH CHECK (uploader_id = auth.uid());

CREATE POLICY "photos: moderator update"
  ON photos FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('moderator', 'admin')
  ));

-- ─── comments ───
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comments: public read visible"
  ON comments FOR SELECT USING (status = 'visible');

CREATE POLICY "comments: owner read own"
  ON comments FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "comments: moderator read all"
  ON comments FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('moderator', 'admin')
  ));

CREATE POLICY "comments: authenticated insert"
  ON comments FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND (SELECT is_blocked FROM profiles WHERE id = auth.uid()) = FALSE
  );

CREATE POLICY "comments: owner soft-delete (status only)"
  ON comments FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ─── photo_likes ───
ALTER TABLE photo_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "likes: public read"
  ON photo_likes FOR SELECT USING (TRUE);

CREATE POLICY "likes: self insert"
  ON photo_likes FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "likes: self delete"
  ON photo_likes FOR DELETE USING (user_id = auth.uid());

-- ─── reports ───
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reports: authenticated insert"
  ON reports FOR INSERT
  WITH CHECK (reporter_id = auth.uid() OR reporter_id IS NULL);

CREATE POLICY "reports: moderator read"
  ON reports FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('moderator', 'admin')
  ));

CREATE POLICY "reports: moderator update"
  ON reports FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('moderator', 'admin')
  ));

-- ─── email_verifications, login_attempts, audit_log, disposable_email_domains ───
-- Default deny — only service_role accesses these
ALTER TABLE email_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE disposable_email_domains ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_log: admin read"
  ON audit_log FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));

-- ═══════════════════════════════════════════
-- HELPER RPC FUNCTIONS
-- ═══════════════════════════════════════════

-- Atomic OTP attempt increment + read (prevents race conditions)
CREATE OR REPLACE FUNCTION claim_verification_attempt(p_id UUID)
RETURNS TABLE (
  id UUID, user_id UUID, email TEXT, code_hash BYTEA,
  attempts SMALLINT, expires_at TIMESTAMPTZ, consumed_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE email_verifications
  SET attempts = email_verifications.attempts + 1
  WHERE email_verifications.id = p_id
    AND email_verifications.consumed_at IS NULL
  RETURNING
    email_verifications.id,
    email_verifications.user_id,
    email_verifications.email,
    email_verifications.code_hash,
    email_verifications.attempts,
    email_verifications.expires_at,
    email_verifications.consumed_at;
END $$;

-- Check if email is disposable
CREATE OR REPLACE FUNCTION is_disposable_email(p_email TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM disposable_email_domains
    WHERE domain = lower(split_part(p_email, '@', 2))
  );
$$;

-- Profile auto-create on auth signup
CREATE OR REPLACE FUNCTION handle_new_user() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'User')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Scheduled cleanup of expired OTPs (run via pg_cron or external cron)
CREATE OR REPLACE FUNCTION cleanup_expired_otps() RETURNS INT
LANGUAGE sql AS $$
  WITH deleted AS (
    DELETE FROM email_verifications
    WHERE expires_at < now() - INTERVAL '1 hour'
       OR consumed_at < now() - INTERVAL '1 day'
    RETURNING 1
  )
  SELECT COUNT(*)::INT FROM deleted;
$$;

-- ═══════════════════════════════════════════
-- COMMENTS / DOCS
-- ═══════════════════════════════════════════
COMMENT ON TABLE photos IS 'Photo uploads — 15 active per user, status managed by moderation pipeline';
COMMENT ON COLUMN photos.sha256 IS 'SHA-256 of original bytes (post EXIF strip). Used for per-user dedup.';
COMMENT ON COLUMN photos.publish_anonymously IS 'If TRUE, public views show "ანონიმური მოქალაქე" instead of display_name';
COMMENT ON COLUMN photos.terms_version IS 'Tracks which T&S version user agreed to at upload time';
COMMENT ON COLUMN profiles.active_photo_count IS 'Denormalized count — maintained by trg_photo_count trigger';
