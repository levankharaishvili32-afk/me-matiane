# CLAUDE.md

ეს ფაილი Claude Code-ისთვის (და სხვა AI/dev-ისთვის) საცნობარო დოკუმენტია. აქ წერია — რა არის პროექტი, რა გადაწყვეტილებები მიღებულია, რა conventions-ი იცავთ.

---

## პროექტი: me.matiane.ge

საქართველოს კოლექტიური ფოტო ისტორიული არქივი. Alta.Ge-ს 26 მაისის (დამოუკიდებლობის დღე 2026) PR კამპანია.

Tagline: **"ისტორია არ უნდა წაიშალოს"**

მომხმარებლები:
- ატვირთავენ ფოტოებს (მაქს. 15 ფოტო per user, 25MB per ფოტო)
- ხედავენ public გალერეას
- like/comment-ი ფოტოებზე
- ფოტოს ანონიმური გასაჯაროვება შესაძლებელია (per-photo toggle)

---

## ფინალური გადაწყვეტილებები (14 მაისი 2026)

| # | გადაწყვეტილება |
|---|---|
| 1 | **Admin queue + appeal mechanism** — AI auto-rejected ფოტოები გასაჩივრდება |
| 2 | **Public browse, login მხოლოდ ატვირთვისთვის** |
| 3 | **"ანონიმური გასაჯაროვება" ღილაკი** (per-photo toggle, default = OFF) |
| 4 | **Likes + Comments Phase 1-ში** |
| 5 | **წაშლა მაშინვე და სამუდამოდ** + confirmation modal |
| 6 | **EXIF data-დან არაფერი არ ვიკითხავთ** — strip ყველაფერი, user-ი ხელით შეიყვანს თარიღს/ლოკაციას |
| 7 | **NSFW thresholds:** auto-reject 0.7+, review 0.5-0.7, auto-approve <0.5 |
| 8 | **Disposable email block-list** active |
| 9 | **Honeypot + Cloudflare Turnstile** (ყოველთვის, არა adaptive) |
| 10 | **Mobile + desktop responsive** |
| 11 | **ატვირთვა გრძელდება სამუდამოდ** post-campaign |
| 12 | **Content license checkbox** ფოტოს ატვირთვისას — texte from Alta.Ge legal |

---

## Architecture

### Stack

| ფენა | ინსტრუმენტი |
|---|---|
| Frontend | Vanilla HTML/CSS/JS (no framework) |
| Frontend hosting | GitHub Pages → Cloudflare Pages |
| Backend | Supabase Edge Functions (Deno) |
| Database | Postgres 15 (Supabase managed) |
| Auth | Supabase Auth (GoTrue) — email/password + Google OAuth |
| File storage | Cloudflare R2 (S3-compatible, zero egress) |
| Email | Resend |
| NSFW AI | AWS Rekognition Content Moderation |
| WAF / CDN / Bot | Cloudflare (Pro $20/mo) |
| Bot protection | Honeypot + Cloudflare Turnstile |
| Monitoring | Sentry + Better Stack + Cloudflare Analytics |

### Repo structure

```
me-matiane/
├── *.html                          # Static frontend (existing)
├── supabase/
│   ├── config.toml                 # Supabase project config
│   ├── migrations/
│   │   ├── 0001_initial_schema.sql # Tables, indexes, RLS, triggers
│   │   └── 0002_seed_disposable_emails.sql
│   └── functions/                  # Edge Functions (Phase 1b+)
│       ├── _shared/
│       ├── register-start/
│       ├── verify-otp/
│       ├── upload-init/
│       ├── upload-finalize/
│       └── ...
├── CLAUDE.md                       # ეს ფაილი
├── DEPLOYMENT.md                   # Deploy guide
├── LEGAL_CHECKLIST.md              # იურისტისთვის
├── .env.example                    # ENV ცვლადების template
└── .gitignore
```

---

## Data Model (high-level)

- **`profiles`** — extends `auth.users`. `display_name`, `role` (user/moderator/admin), `active_photo_count` (denormalized, trigger-maintained), `is_blocked`.
- **`photos`** — main media. `sha256` for per-user dedup. `status` (uploading/scanning/approved/rejected_nsfw/pending_review/appealed/removed). `publish_anonymously` per-photo. `ai_nsfw_score`, `terms_version`.
- **`photo_likes`** — composite PK `(user_id, photo_id)`.
- **`comments`** — moderation-aware (`status` enum).
- **`reports`** — abuse reports; 3 reports → auto-hide photo (trigger).
- **`email_verifications`** — OTP store. `code_hash` = HMAC-SHA256.
- **`login_attempts`** — rate-limit + lockout source.
- **`disposable_email_domains`** — blocklist.
- **`audit_log`** — append-only security events.

---

## Conventions

### Code style

- **Frontend:** Vanilla JS, inline `onclick="..."` (matches existing style). State in DOM (`classList`, `style`, `innerHTML`).
- **Backend:** Supabase Edge Functions in TypeScript (Deno runtime). One function per directory.
- **SQL:** snake_case. Constraints inline where possible. Comments on non-obvious decisions.
- **Strings:** UI is Georgian. Variable names English. Error messages from server in Georgian.

### Security

- **Never trust `file.type`** — always verify magic bytes
- **Never use `innerHTML` with user content** — `textContent` or DOMPurify
- **Always validate server-side** even if validated client-side
- **`service_role` key SERVER-ONLY** — never expose to frontend
- **All photos default `pending_review`** — RLS strictly enforced
- **Email enumeration prevention** — register/reset endpoints always return success
- **HMAC OTP codes with server pepper** — never plain
- **EXIF strip ALL metadata** before R2 store (privacy + dedup correctness)

### Conventions

- **CSS variables in `:root`** for colors/sizes (duplicated per HTML file currently — be aware)
- **Buttons:** `.btn-orange` (primary), `.btn-outline`, `.btn-white`
- **Animations:** prefer CSS `@keyframes` over JS
- **Date format:** ISO-8601 in DB; display localized in frontend
- **Money:** N/A — no payments in MVP

---

## Critical paths (test these first)

1. Register → OTP email → verify → upload first photo → see it in gallery
2. 16th photo upload → friendly limit modal
3. Same photo (same SHA-256) twice → "you already uploaded this"
4. Upload `.exe` renamed `.jpg` → rejected (magic bytes)
5. NSFW photo → auto-rejected
6. User appeals → moderator queue → approve → photo public
7. Delete account → all photos gone from R2 + DB

---

## Known limitations / Phase 2 work

- 2FA for admin/moderator (Supabase MFA TOTP)
- Perceptual hash dedup (currently exact-bytes only)
- Trusted user auto-approve
- Redis-backed rate limits (Upstash) — currently Postgres
- HIBP password breach check
- ClamAV virus scan (async pipeline)
- Penetration test by 3rd party

---

## Running locally (dev)

ცოცხალი საიტი (frontend mockup): https://levankharaishvili32-afk.github.io/me-matiane/

Local dev:
```bash
# Frontend only (no backend calls work)
# Open any *.html in browser

# With Supabase backend
supabase start                    # local Postgres + Auth + Storage
supabase db reset                 # apply migrations
supabase functions serve          # Edge Functions on localhost
```

ლოკალური HTTP სერვერი ფაილებისთვის (Windows):
```powershell
# Python (თუ გაქვს)
python -m http.server 8000

# Node (თუ გაქვს)
npx serve -p 8000
```

---

## Deadline

**Launch: 26 მაისი 2026** (დამოუკიდებლობის დღე)

Phase 1: 14-25 მაისი
Phase 2: ივნისი 2026
Phase 3: ივლისი 2026+

დეტალური roadmap — `DEPLOYMENT.md`-ში.
