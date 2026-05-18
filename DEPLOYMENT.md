# Deployment Guide — me.matiane.ge

გაიდი, თუ როგორ გადააქციო ეს repo ცოცხალ პროდუქცი საიტად.

## Prerequisites — ანგარიშები

ყველა ანგარიში Alta.Ge-ს corporate email-ით (`*@alta.ge`) უნდა შეიქმნას.

| სერვისი | URL | რა გვჭირდება |
|---|---|---|
| GitHub | github.com | Repo უკვე არსებობს |
| Cloudflare | cloudflare.com | DNS, R2, WAF, Pages, Turnstile |
| Supabase | supabase.com | Postgres, Auth, Edge Functions |
| AWS | aws.amazon.com | Rekognition |
| Resend | resend.com | Email |
| Domain | (registrar) | `me.matiane.ge` registered |

---

## Setup Steps

### 1. Cloudflare (15 min)

```bash
# A. Add domain
#    Cloudflare → Add Site → me.matiane.ge → Free plan (upgrade to Pro before launch)
#    Update nameservers at domain registrar

# B. Create R2 buckets
#    R2 → Create bucket:
#      - "memat-originals" (private)
#      - "memat-public" (public — custom domain: media.me.matiane.ge)

# C. Generate R2 API tokens
#    R2 → Manage API Tokens → Create:
#      Permission: Object Read & Write
#      Buckets: both
#    Save: Access Key ID, Secret Access Key

# D. Turnstile site key
#    Turnstile → Add Site → me.matiane.ge → Invisible mode
#    Save: Site Key, Secret Key
```

### 2. Supabase (15 min)

```bash
# A. Create project (Pro tier $25/mo)
#    Database password — strong, save in 1Password
#    Region: eu-central-1 (Frankfurt)

# B. Run migrations
#    Local: install Supabase CLI
npm install -g supabase
supabase login
supabase link --project-ref <project-ref>
supabase db push  # applies supabase/migrations/*.sql

# C. Configure Auth
#    Authentication → Providers:
#      Email: enable, disable "Confirm email" (we use custom OTP)
#      Google: enable, add OAuth client (Google Cloud Console)
#    Authentication → URL Configuration:
#      Site URL: https://me.matiane.ge
#      Redirect URLs: https://me.matiane.ge/auth/callback

# D. Set Edge Function secrets (after deploying functions)
supabase secrets set \
  RESEND_API_KEY=re_... \
  OTP_PEPPER=$(openssl rand -hex 32) \
  AWS_ACCESS_KEY_ID=... \
  AWS_SECRET_ACCESS_KEY=... \
  AWS_REGION=eu-west-1 \
  CF_R2_ACCESS_KEY_ID=... \
  CF_R2_SECRET_ACCESS_KEY=... \
  CF_R2_BUCKET_PRIVATE=memat-originals \
  CF_R2_BUCKET_PUBLIC=memat-public \
  CF_R2_PUBLIC_DOMAIN=https://media.me.matiane.ge \
  TURNSTILE_SECRET_KEY=...
```

### 3. AWS Rekognition (10 min)

```bash
# A. Create IAM user "memat-rekognition"
#    Permissions: AmazonRekognitionReadOnlyAccess (or custom policy below)

# B. Custom policy (least privilege):
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "rekognition:DetectModerationLabels",
    "Resource": "*"
  }]
}

# C. Generate access key — save to Supabase secrets
```

### 4. Resend (10 min)

```bash
# A. Sign up, verify domain me.matiane.ge
#    Add DNS records (DKIM, SPF, DMARC) — Cloudflare DNS

# B. Create sending domain
#    From: noreply@me.matiane.ge

# C. Generate API key — save to Supabase secrets

# ⚠️ DNS propagation 24-72h. DO THIS FIRST DAY.
```

### 5. DNS records (Cloudflare → DNS)

```
# Resend (DKIM + SPF + DMARC) — provided by Resend dashboard
TXT  me.matiane.ge        v=spf1 include:resend.com ~all
TXT  resend._domainkey    <provided by Resend>
TXT  _dmarc                v=DMARC1; p=quarantine; rua=mailto:dmarc@me.matiane.ge

# Frontend
CNAME me.matiane.ge       cname.cloudflare.pages.dev  (or GitHub Pages)
CNAME www                 me.matiane.ge

# Media subdomain
CNAME media               <r2-public-bucket-domain>.r2.dev
```

### 6. Edge Functions deploy

```bash
# In repo root
supabase functions deploy register-start
supabase functions deploy verify-otp
supabase functions deploy resend-otp
supabase functions deploy upload-init
supabase functions deploy upload-finalize
supabase functions deploy delete-photo
supabase functions deploy appeal-photo
supabase functions deploy admin-list-pending
supabase functions deploy admin-approve
supabase functions deploy admin-reject
```

### 7. Frontend deploy

GitHub Pages აქტიური უკვე — push-ი main-ში auto-deploys.

ალტერნატივა Cloudflare Pages-ად:
```bash
# Cloudflare → Pages → Connect to Git → me-matiane
#   Build command: (empty)
#   Output directory: /
#   Environment: production
```

---

## Smoke Test Checklist (post-deploy)

- [ ] `https://me.matiane.ge` loads
- [ ] Register flow: email arrives within 30s
- [ ] OTP code verifies → user logged in
- [ ] Upload 1MB JPG → appears in gallery within 1 min (if NSFW clean)
- [ ] Upload 26MB file → rejected with friendly error
- [ ] Upload .exe renamed to .jpg → rejected (magic bytes)
- [ ] Upload 16th photo → friendly limit message
- [ ] Delete photo → photo gone, count decremented
- [ ] Re-upload same SHA-256 → rejected with "already uploaded"
- [ ] Comment → appears
- [ ] Like → counter increments
- [ ] Report → triggers admin queue
- [ ] Admin approves pending → photo public
- [ ] Admin rejects → user can appeal
- [ ] Logout → re-login works

---

## Monitoring URLs

- Sentry: <project URL>
- Better Stack: <status page URL>
- Cloudflare Analytics: dash.cloudflare.com → me.matiane.ge → Analytics
- Supabase Logs: app.supabase.com → project → Logs

---

## On-call rotation (Launch day, 26 May 2026)

| საათი | მოვალე | რა აქვს გაკეთებული |
|---|---|---|
| 09:00 | Levan | Final pre-flight check |
| 10:00 | Marketing mod | Queue baseline |
| 12:00 | DevOps + Mod | Traffic burst monitoring |
| 14:00 | Mod | Mid-day queue review |
| 18:00 | Mod | EOD queue clear |
| 23:00 | Levan | Day 1 post-mortem |

---

## Rollback plan

თუ launch-ის შემდეგ critical bug:

1. Cloudflare → "Maintenance" page rule (return 503 with friendly message)
2. GitHub: `git revert <bad-commit>` + push (frontend rollback)
3. Supabase: migration rollback ფიქრობდი ხელით (no auto-revert)
4. R2: ფაილების წაშლა მხოლოდ ხელით, არასოდეს ავტომატურად
