# Business Logic Specification — me.matiane.com.ge

**ვერსია:** 2.0 (19 მაისი 2026)
**კლიენტი:** Alta.Ge
**პროექტი:** me.matiane.com.ge — საქართველოს ფოტო ისტორიული არქივი
**Launch:** 26 მაისი 2026 (დამოუკიდებლობის დღე)
**Adresat:** Backend/Frontend developer (handoff)

---

## სარჩევი

1. [პროექტის მიმოხილვა](#1-პროექტის-მიმოხილვა)
2. [Tech Stack](#2-tech-stack)
3. [Site Pages](#3-site-pages)
4. [User Roles & Auth](#4-user-roles--auth)
5. [Registration Flow](#5-registration-flow)
6. [Login Flow](#6-login-flow)
7. [Password Reset Flow](#7-password-reset-flow)
8. [Photo Upload Flow](#8-photo-upload-flow)
9. [Gallery / Archive](#9-gallery--archive)
10. [Profile Page](#10-profile-page)
11. [Share Card Generator](#11-share-card-generator)
12. [AI Moderation](#12-ai-moderation)
13. [Email System (OTP)](#13-email-system-otp)
14. [Restrictions Table](#14-restrictions-table)
15. [API Endpoints (Required)](#15-api-endpoints-required)
16. [Open Items / Pending Decisions](#16-open-items--pending-decisions)

---

## 1. პროექტის მიმოხილვა

**me.matiane.com.ge** არის საქართველოს კოლექტიური ფოტო ისტორიული არქივი — PR კამპანია 26 მაისის (დამოუკიდებლობის დღე) აღსანიშნავად.

**Tagline:** "არ წაშალო ისტორია"

**მისია:** მომხმარებლები ტვირთავენ მობილური ტელეფონის ფოტოებს — შექმნა ცოცხალი ციფრული არქივი, რომელიც დაიცავს მნიშვნელოვან მომენტებს დავიწყებისგან.

**მთავარი ფუნქციები:**
- ფოტოს ატვირთვა (max 15 per user, max 25MB per photo)
- საჯარო გალერეა (browse without login)
- Personal profile (user's own photos)
- Instagram Story ბარათების გენერატორი (4 ფერი)
- AI NSFW მოდერაცია (automatic)

**პრიორიტეტი:** Alta.Ge brand reputation > feature completeness. ერთი ცუდი ფოტო public-ად = PR catastrophe.

---

## 2. Tech Stack

### Frontend (already built)
- HTML/CSS/Vanilla JS (zero frameworks, zero build)
- Hosting: **GitHub Pages** → mighration target: **Cloudflare Pages**
- Fonts: Google Fonts (Noto Sans Georgian 300-900, Ubuntu 300-700)
- Logo + hero photo + flag: inline base64 in HTML and external `assets/`

### Backend (to be built)

რეკომენდირებული stack (იხ. დეტალურად `DEPLOYMENT.md`):

| ფენა | ინსტრუმენტი |
|---|---|
| Auth | Supabase Auth (GoTrue) |
| Database | Supabase Postgres |
| File Storage | Cloudflare R2 (S3-compatible) |
| Email | Resend |
| AI Moderation | AWS Rekognition Content Moderation |
| Bot Protection | Cloudflare Turnstile + Honeypot |
| WAF / CDN | Cloudflare |
| Monitoring | Sentry + Better Stack |

---

## 3. Site Pages

| ფაილი | URL | Role | Auth |
|---|---|---|---|
| `index.html` | `/` | მთავარი (Hero + Challenge section) | Public |
| `gallery.html` | `/gallery.html` | არქივი — public ფოტოები | Public |
| `share-card.html` | `/share-card.html` | Story ბარათის გენერატორი | Public |
| `how-it-works.html` | `/how-it-works.html` | 4-ნაბიჯიანი timeline | Public |
| `profile.html` | `/profile.html` | მომხმარებლის profile + photos | **Auth required** |
| `reset-password.html` | `/reset-password.html` | Password reset (3-step) | Public |
| `privacy-policy.html` | `/privacy-policy.html` | Privacy Policy (placeholder) | Public |
| `me-matiane.html` | `/me-matiane.html` | Redirect → index.html (legacy) | — |

---

## 4. User Roles & Auth

### Roles

| Role | Description |
|---|---|
| `guest` | Unauthenticated — can browse gallery, view profiles, see share-card landing |
| `user` | Registered + email confirmed — can upload, like, comment, manage own profile |
| `moderator` | Alta.Ge marketing team member — can approve/reject pending photos, view appeals |
| `admin` | Alta.Ge IT/owner — full access including user management |

### Mandatory 2FA

- **Admin:** TOTP 2FA required ✓
- **Moderator:** TOTP 2FA required ✓
- **Regular user:** Optional (Phase 2)

### Public Browse (no login)
ნებისმიერი visitor-ი ხედავს:
- ✅ Public gallery (`gallery.html`)
- ✅ Public photo details
- ✅ Share-card landing (`share-card.html`)
- ✅ How it works (`how-it-works.html`)
- ✅ Privacy policy

### Auth-required actions
- ✅ Photo upload
- ✅ Profile page (own photos)
- ✅ Like / comment (Phase 2)
- ✅ Report abuse
- ✅ Account deletion

---

## 5. Registration Flow

### 5.1 ფორმის ველები (Upload modal-ის ნაცვლად — auth modal)

| ველი | სავალდებულო | Validation |
|---|---|---|
| `name` (display name) | ✅ | 2-60 chars, trim, no URLs |
| `email` | ✅ | RFC 5322, 6-254 chars, lowercase normalize |
| `password` | ✅ | 10-128 chars, no character class requirement |
| `terms_accepted` | ✅ | checkbox required |
| `honeypot` (hidden) | — | must be empty (bot detection) |
| `form_loaded_at` (hidden) | — | timestamp; require >2s elapsed |
| `turnstile_token` | ✅ | Cloudflare Turnstile token |

### 5.2 ფლოუ

1. User opens auth modal (from hero "შესვლა" or upload CTA)
2. Switches to "რეგისტრაცია" tab
3. Fills form, clicks submit
4. **Frontend validation:**
   - Email regex
   - Password 10+ chars
   - Name 2-60 chars
   - Terms checked
5. **Backend `POST /auth/register-start`:**
   - Server-side validation (mirror)
   - Disposable email check → 400 "ერთჯერადი ემაილი არ მიიღება"
   - Rate limit (3/hour per email, 5/10min per IP) → 429
   - Turnstile verify → 400 if invalid
   - Honeypot check → silent fake success
   - Form age <2s → silent fake success
   - Create user (email_confirm=false), generate 6-digit OTP
   - Send email via Resend
   - Return `{ verification_id, sent: true }`
6. UI: shows OTP input screen
7. **`POST /auth/verify-otp`** with code:
   - Atomic claim attempt (`claim_verification_attempt` RPC)
   - HMAC-SHA256 compare (timing-safe)
   - Max 5 attempts → 429
   - TTL 10 min → 410 expired
   - On success: mark user `email_confirmed`, issue session
8. UI: success → redirect to profile or upload

### 5.3 Email Enumeration Prevention
❗ **არასოდეს** არ ვაჩვენოთ "ეს email უკვე გამოყენებულია".
ფლოუ existing email-ისთვის: ვბრუნდებით fake `verification_id`, ემაილს არ ვაგზავნით (ან ვაგზავნით "if you didn't register, ignore" ტექსტს).

---

## 6. Login Flow

### 6.1 ფლოუ

1. User opens auth modal → Login tab
2. Enters email + password
3. **`POST /auth/login`:**
   - Rate limit: 10 attempts/min per IP, 5 fails/15min per email
   - **Account lockout:** 5 fails in 15min → 423 "ანგარიში დაბლოკილია 15 წუთით"
   - Argon2id password compare
   - Verify `email_confirmed_at IS NOT NULL` → 403 "გთხოვ დაადასტურე ემაილი"
   - Verify `profiles.is_blocked = FALSE` → 403 "ანგარიში დაბლოკილია"
   - Issue access JWT (1h TTL) + refresh cookie (7 days, HttpOnly, Secure, SameSite=Lax)
   - audit_log: `auth.login.success` / `auth.login.failed`

### 6.2 Failed Login Response
⚠️ **Generic error** — არ ვამცნოთ "ემაილი არ არსებობს" vs "პაროლი არასწორია":
- ✅ "ემაილი ან პაროლი არასწორია"
- ❌ "ეს ემაილით user-ი არ მოიძებნა"

### 6.3 Session
- Access token: 1h TTL
- Refresh token: 7 days, **rotating** (one-time use)
- **Reuse detection:** same refresh used 2x → all sessions terminated + alert

---

## 7. Password Reset Flow

URL: `reset-password.html`

### 7.1 Step 1 — Request
1. User enters email
2. **`POST /password-reset-start`:**
   - **Always return 200** (enumeration prevention)
   - Rate limit: 3/hour per email, 5/10min per IP
   - If user exists & confirmed: generate OTP, send via Resend

### 7.2 Step 2 — Code
User enters 6-digit code on next screen.

### 7.3 Step 3 — New Password
1. User enters new password (10-128 chars, confirm match)
2. **`POST /password-reset-confirm`:**
   - Verify OTP (same logic as registration)
   - Password validation
   - Hash + update (Argon2id)
   - **Invalidate all existing sessions**
   - audit_log: `auth.password_reset.success`
3. Redirect to login

---

## 8. Photo Upload Flow

### 8.1 Preconditions
- User authenticated
- `email_confirmed_at IS NOT NULL`
- `profiles.is_blocked = FALSE`
- `profiles.active_photo_count < 15`

### 8.2 Upload Modal Fields

| ველი | სავალდებულო | Validation |
|---|---|---|
| ფაილი | ✅ | image/jpeg, png, webp, heic; ≤ 25MB; ≤ 8000×8000 |
| სათაური | ✅ | min 10 chars, max 120 |
| დახასიათება | ❌ **ნებაყოფლობითი** | 0 ან 100-2000 chars (validate only if non-empty) |
| თარიღი (`taken_at`) | ❌ **ნებაყოფლობითი** | YYYY-MM-DD, ≤ today, ≥ 1900-01-01 |
| ლოკაცია (`location_label`) | ❌ **ნებაყოფლობითი** | 0-120 chars |
| **Terms checkbox** | ✅ | Must be checked |

**მნიშვნელოვანი:**
- ❌ **არ არსებობს** Private/Public toggle — **მხოლოდ public** გასაჯაროება
- ❌ **არ არსებობს** Tags section (removed from UI)
- ❌ **არ არსებობს** Multiple file selection in modal (single photo per upload)

### 8.3 ფლოუ

**Step 1: Upload Init**
1. Frontend client-side validation (size, type, dimensions)
2. **`POST /upload-init`** `{ byte_size, mime_type, sha256_hex }`:
   - Auth check
   - **Rolling 15-photo limit check:** `profiles.active_photo_count < 15`
   - Rate limit: 30 uploads/hour per user, 100/day
   - Per-user dedup: `SELECT id FROM photos WHERE uploader_id=? AND sha256=? AND deleted_at IS NULL` → 409 if exists
   - **15th-photo flag:** if `active_photo_count == 14` → response includes `is_last_slot: true`
   - Issue Cloudflare R2 presigned PUT URL (TTL: 5 min)
   - Create `photos` record with status='uploading'
   - Returns: `{ photo_id, upload_url, is_last_slot }`

**Step 2: Direct R2 Upload**
1. Frontend PUTs file bytes directly to R2 (with progress bar)

**Step 3: Finalize**
1. **`POST /upload-finalize`** `{ photo_id, title, description?, taken_at?, location_label?, terms_accepted, turnstile_token }`:
   - Verify R2 object exists; verify size
   - Fetch object → verify magic bytes
   - Compute SHA-256 (server-side) → match client
   - **EXIF strip** (ALL metadata) → re-store
   - Validate fields server-side:
     - title 10-120 ✅ required
     - description 0 OR 100-2000 (optional)
     - taken_at YYYY-MM-DD (optional)
     - location_label 0-120 (optional)
     - terms_accepted = true ✅ required
   - `status = 'scanning'`
   - **AWS Rekognition** call
   - Decision (see Section 12):
     - score < 0.5 → `status = 'approved'` + copy to public bucket
     - 0.5-0.7 → `status = 'pending_review'`
     - ≥ 0.7 → `status = 'rejected_nsfw'`
   - audit_log: `photo.uploaded`, `photo.auto_approved`/`rejected_nsfw`/`pending_review`
2. Frontend:
   - If `is_last_slot == true && success` → modal "შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!"

### 8.4 Error Responses

| შემთხვევა | Status | Message |
|---|---|---|
| File > 25MB | 413 | "ფაილი 25MB-ს აღემატება" |
| Wrong MIME | 415 | "ფაილის ფორმატი დაუშვებელია" |
| Dimensions > 8000×8000 | 413 | "გამოსახულება ძალიან დიდია" |
| Same SHA-256 | 409 | "ეს ფოტო თქვენ უკვე გაქვთ ატვირთული" |
| `active_photo_count >= 15` | 429 | "შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!" |
| Title < 10 | 400 | "სათაური მინ. 10 სიმბოლო" |
| Terms not accepted | 400 | "გთხოვ მიიღო პირობები" |
| Rate limit | 429 | "ძალიან ბევრი ცდა" |

### 8.5 Rolling 15-Photo Limit Rules

**Counter რომელი ფოტოები ითვლება:**
- ✅ `approved`, `scanning`, `pending_review`, `uploading`, `appealed`
- ❌ `rejected_nsfw` (user can retry)
- ❌ `removed`
- ❌ `deleted_at IS NOT NULL`

**UI:**
- "X / 15" counter **არ ჩანს** upload-მდე
- მე-15 ფოტოს წარმატებული ატვირთვის შემდეგ — friendly modal გამოდის

---

## 9. Gallery / Archive

URL: `gallery.html`

### 9.1 Default View
- Sort: `created_at DESC` (newest first)
- Filter: "ყველა" (all)
- Layout: 3-col grid (desktop), 2-col (tablet), 1-col (small phone <480px)

### 9.2 Filter Chips
- ყველა (default)
- ქუჩა
- პროტესტი
- მოდა
- შავ-თეთრი

### 9.3 Sort Options
Dropdown:
- უახლესი პირველი (default)
- ძველი პირველი
- პოპულარული (Phase 2)

### 9.4 View Toggle
- Grid view (default, active orange)
- List view

### 9.5 Photo Card

**Default state:** მხოლოდ ფოტო (clean, no labels)

**Hover/Tap:** overlay shows:
- ფოტოგრაფი (display_name)
- ფოტოს დახასიათება (description) ან ლოკაცია

⚠️ ანონიმური უფლება — ფოტოგრაფი თვითონ აარჩევს anonymous toggle-ით.

### 9.6 Photo Detail Page (Phase 2)
- სრული რეზოლუცია
- სათაური + description
- ფოტოგრაფი
- ლოკაცია + თარიღი
- Like + Comment (Phase 2)
- Share buttons (FB, WA)
- Report button

---

## 10. Profile Page

URL: `profile.html`

### 10.1 Hero
- Avatar (placeholder OR first letter of display_name)
- "გამარჯობა," eyebrow
- Display name
- წევრობის თარიღი ("წევრი 2026 წლის მაისიდან")

### 10.2 Stats
3 blocks:
- ფოტოები (count of user's active photos, max 15)
- ნახვა (sum of views across all user's photos — Phase 2)
- გული (sum of likes — Phase 2)

### 10.3 Actions
- "ახალი ფოტოს ატვირთვა" button (purple gradient) → opens upload modal on `index.html`

### 10.4 Photo Grid
- 3-col (desktop), 2-col (mobile)
- Only user's own photos
- Hover/tap reveals:
  - სათაური
  - თარიღი (created_at OR taken_at)
  - ნახვების რაოდენობა (Phase 2)
- Action buttons (top-right of each card):
  - ✏️ რედაქტირება (Phase 2)
  - 🗑️ წაშლა → confirmation modal

### 10.5 Delete Photo

⚠️ **მაშინვე და სამუდამოდ**

1. User clicks delete icon
2. **Confirmation modal:** "ნამდვილად გსურს ფოტოს წაშლა? ეს ვერ დაბრუნდება."
3. User: "დიახ, წაშალე"
4. **`DELETE /photos/{id}`:**
   - Verify ownership
   - Hard delete: R2 object + DB row (`deleted_at = now()`, `status = 'removed'`)
   - Trigger decrements `profiles.active_photo_count`
   - audit_log: `photo.deleted` actor_id=user

---

## 11. Share Card Generator

URL: `share-card.html`

### 11.1 Page Layout
- **Left:** title + 4 numbered steps + 2 CTAs
- **Right:** 3 stacked phone card mockups (decorative)
- **Below CTAs:** template picker (4 colors) + photo upload + canvas preview

### 11.2 Title
"გააზიარე შენი მობილური ისტორია"

### 11.3 4 Numbered Steps
1. ატვირთე შენი ფოტო
2. აირჩიე სტილი — 4 ვარიანტი
3. გადმოწერე 1080×1920px Story ბარათი
4. გაუზიარე Instagram-ზე, WhatsApp-ზე

### 11.4 4 Card Templates (per PDF design)

| # | Gradient |
|---|---|
| 0 | Orange (`#F5A623`) → Teal (`#5DD3D6`) |
| 1 | Orange (`#F5A623`) → Purple (`#7B44C8`) |
| 2 | Purple (`#7B44C8`) → Magenta (`#CC2366`) → Red (`#E53A2F`) |
| 3 | Purple (`#7B44C8`) → Deep Purple (`#3D1F8C`) |

⚠️ **არ არსებობს** labels ("მუქი", "ცეცხლი", etc.) — მხოლოდ ფერი ხილული.

### 11.5 Card Design (Canvas 1080×1920)
- **Top:** "ალტა ALTA" logo (dark navy, bold, centered)
- **Photo:** 88% width, rounded corners 4%, 50% height
- **Photo overlay icons:**
  - Bottom-left: dark pill with camera + search icons
  - Bottom-right: dark circle with heart icon
- **Title:** "ჩემი მობილური / ისტორია" (2 lines, weight 900, white, centered)
- **Bottom pill:** ME.MATIANE.COM.GE on dark navy + Georgian flag
- **Footer:** "POWERED BY ALTA.GE" (tiny, dark)

### 11.6 Export
- Format: PNG, 1080×1920px
- Instagram Story ready
- Download via canvas.toDataURL()

---

## 12. AI Moderation

### 12.1 Provider
**AWS Rekognition Content Moderation**

### 12.2 Categories Tracked
- Explicit Nudity, Nudity
- Graphic Violence Or Gore
- Hate Symbols
- Visually Disturbing

`ai_nsfw_score` = max(score) across categories.

### 12.3 Decision Thresholds

| Score | Decision | Status | User sees |
|---|---|---|---|
| < 0.50 | Auto-approve | `approved` | Photo public |
| 0.50–0.70 | Human review | `pending_review` | "თქვენი ფოტო შემოწმდება" message |
| ≥ 0.70 | Auto-reject | `rejected_nsfw` | "ფოტო ვერ მოხვდა საიტზე. გასაჩივრება შესაძლებელია." |

### 12.4 Failure Handling
Retry 3× with exponential backoff (1s, 2s, 4s). If still fails → `status = 'pending_review'`.

### 12.5 Appeal Flow
- User clicks "გასაჩივრება" on rejected photo
- Modal: textarea for reason
- `status = 'appealed'`, moderator reviews within 24h
- Moderator approve → `status = 'approved'`, photo public
- Moderator final reject → user notified, no re-appeal

### 12.6 Moderator Schedule
- **Person:** Alta.Ge Marketing team (specific person TBD pre-launch)
- **Hours:** 9:30 – 18:30 (working days)
- **Cadence:** 2× per day check (morning + evening), 24h SLA per appeal

---

## 13. Email System (OTP)

### 13.1 Provider
**Resend** (transactional email)

### 13.2 OTP Parameters

| Parameter | Value |
|---|---|
| Code length | 6 digits |
| Generation | `crypto.randomInt(100000, 1000000)` |
| Storage | HMAC-SHA256(code, `OTP_PEPPER`) |
| TTL | 10 minutes |
| Max verify attempts | 5 |
| Resend cooldown | 60 seconds |
| Max resend per code | 3 in 15 min |

### 13.3 Email Templates

| Trigger | Subject |
|---|---|
| Registration | `{code} — დადასტურების კოდი` |
| Password reset | `{code} — პაროლის აღდგენა` |
| Photo approved | "თქვენი ფოტო გასაჯაროვდა" |
| Photo rejected | "ფოტო არ მოხვდა საიტზე" |
| Appeal approved | "თქვენი ფოტო დადასტურდა" |
| Account blocked | "ანგარიში დაბლოკილია" |
| Moderator digest | "ახალი ფოტოები მოდერაციისთვის" (2h batch) |

### 13.4 DNS Setup (Resend)
- SPF: `v=spf1 include:resend.com ~all`
- DKIM: provided by Resend
- DMARC: `v=DMARC1; p=quarantine; rua=mailto:dmarc@me.matiane.com.ge`

⚠️ **DNS propagation 24-72h.** Setup დღევანდელივე.

---

## 14. Restrictions Table

### Frontend (UX layer)

| Restriction | Value | Behavior |
|---|---|---|
| File type | JPEG, PNG, WebP, HEIC | Auto-reject in input |
| File size | 25 MB | Show error message |
| Image dimensions | ≤ 8000×8000 | Show error |
| Title min | 10 chars | Show counter, disable submit |
| Email format | RFC 5322 regex | Inline validation |
| Password min | 10 chars | Strength meter |
| Terms checkbox | required | Disable submit |

### Backend (Security layer)

| Restriction | Value | Tool |
|---|---|---|
| **File size hard cap** | 25 MB | Cloudflare WAF + Edge Function + R2 bucket config |
| **MIME magic bytes** | Verify, not trust header | Server-side check |
| **EXIF strip** | All metadata removed | Server-side before R2 store |
| **15 photos per user** | Rolling (delete frees slot) | DB trigger + RLS policy |
| **Per-user storage cap** | 375 MB (15 × 25MB) | Derived from photo count |
| **Per-user upload rate** | 30/hour, 100/day | DB count |
| **Login attempts** | 5 fails/15min per email | Postgres + lockout |
| **Registration rate** | 3/hour per email, 5/10min per IP | DB query |
| **OTP attempts** | 5 per code | Atomic increment RPC |
| **OTP TTL** | 10 minutes | `expires_at` column |
| **Password Argon2id** | memlimit=64MB, t=3, p=4 | Supabase default |
| **Disposable email block** | Block list (~50 domains) | DB lookup |
| **Honeypot** | Hidden field, must be empty | Silent fake success |
| **Form age** | >2s, <24h | Hidden timestamp |
| **Turnstile** | Required on register/login/upload | Cloudflare |
| **SHA-256 dedup** | Per-user unique | DB unique index |
| **NSFW threshold** | 0.7 auto-reject, 0.5 review | AWS Rekognition |
| **Cloudflare WAF body** | 28 MB max | Block at edge |
| **API rate (anon)** | 60/min per IP | Cloudflare |
| **API rate (auth)** | 300/min per user | Cloudflare + JWT |

---

## 15. API Endpoints (Required)

რეკომენდირებული Edge Functions (Supabase) / serverless functions:

### Auth
- `POST /register-start` → user_id + verification_id + send OTP
- `POST /verify-otp` → confirm email, issue session
- `POST /resend-otp` → resend code (cooldown 60s)
- `POST /login` → access + refresh tokens
- `POST /logout` → revoke refresh
- `POST /password-reset-start` → send OTP
- `POST /password-reset-confirm` → update password + invalidate sessions

### Upload
- `POST /upload-init` → presigned R2 URL + photo_id
- `POST /upload-finalize` → EXIF strip + Rekognition + status
- `DELETE /photos/{id}` → hard delete (own photo)

### Gallery
- `GET /photos` → public approved photos (paginated, filtered)
- `GET /photos/{id}` → single photo (RLS)

### Profile
- `GET /profile/me` → own profile + photos
- `PATCH /profile/me` → update display_name, etc.

### Moderation (admin)
- `GET /admin/pending` → queue
- `POST /admin/photos/{id}/approve`
- `POST /admin/photos/{id}/reject`

### Reports (Phase 2)
- `POST /reports` → submit abuse report
- `GET /admin/reports` → moderator queue

### Account
- `DELETE /account` → GDPR right to erasure (24h grace)
- `GET /account/export` → JSON+ZIP data export (GDPR)

---

## 16. Open Items / Pending Decisions

### 🔴 Critical Pre-Launch

| # | Item | Owner | Deadline |
|---|---|---|---|
| 1 | Content license text — Alta.Ge usage scope (PR, billboard, social) | Alta.Ge legal | 22 May |
| 2 | Privacy policy text → drop into `privacy-policy.html` | Alta.Ge legal | 22 May |
| 3 | Terms of Service text | Alta.Ge legal | 22 May |
| 4 | Moderator name + email + assignment | Alta.Ge Marketing | 21 May |
| 5 | Corporate account credentials (Cloudflare, Supabase, AWS, Resend, Domain) | Alta.Ge IT | 16-17 May (DNS prop 24-72h!) |
| 6 | DPO assignment | Alta.Ge | 22 May |
| 7 | Anonymous publish policy: per-photo toggle on/off? | Alta.Ge product owner | confirmed: YES, per-photo |

### 🟡 Phase 1 Polish (post-launch)

- Like + comment functionality (schema ready, UI to wire)
- Real photo data (replace base64 mocks in gallery/feed/profile)
- Real backend auth integration
- Moderator dashboard UI
- Appeal flow UI

### 🟢 Phase 2 (June+)

- 2FA TOTP (admin/moderator)
- HIBP password breach check
- Trusted user auto-approve (after X approved uploads)
- Perceptual hash dedup (pHash for near-duplicates)
- Penetration test (3rd party, ~$5-15k)
- Photo edit UI
- View count tracking
- Search (pg_trgm)
- Location point map view

### 🔵 Phase 3 (Q3+)

- Multi-language (en, ru)
- Mobile native app (PWA → wrapper?)
- ISO 27001 if enterprise interest
- SIEM / advanced monitoring
- Video uploads (currently photo-only)

---

## 17. Configuration / Feature Flags

Editable WITHOUT code deploy (env vars OR `app_settings` DB table):

| Setting | Default | Where |
|---|---|---|
| `PHOTO_LIMIT_PER_USER` | 15 | env |
| `PHOTO_LIMIT_REACHED_MSG` | "შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!" | env or DB |
| `MAX_FILE_SIZE_MB` | 25 | env |
| `OTP_TTL_MIN` | 10 | env |
| `OTP_RESEND_COOLDOWN_SEC` | 60 | env |
| `LOGIN_LOCKOUT_FAILS` | 5 | env |
| `LOGIN_LOCKOUT_WINDOW_MIN` | 15 | env |
| `NSFW_AUTO_REJECT_THRESHOLD` | 0.70 | env |
| `NSFW_REVIEW_THRESHOLD` | 0.50 | env |
| `TERMS_VERSION` | "v1" | env |
| `MODERATION_SLA_HOURS` | 24 | env |

---

## 18. Domain & Branding Constants

- **Domain:** `me.matiane.com.ge`
- **Owner:** Alta.Ge
- **Powered by:** Alta.Ge
- **Brand colors:**
  - Deep purple: `#0D0520` (bg), `#1A0F2E`, `#1E0A45`, `#2D1265`
  - Purple: `#5B2DAA`, `#7B44C8`, `#3D1F8C`
  - Magenta: `#CC2366`
  - Red: `#E53A2F`
  - Orange: `#F5A623` (primary accent)
  - Teal: `#5DD3D6` (gradient endpoint)
- **Typography:**
  - Headings: Noto Sans Georgian, weight 700-900
  - Body: Noto Sans Georgian, weight 400-500
  - Latin: Ubuntu (fallback)

---

## 19. Audit Log Events

| Action | Actor | Metadata |
|---|---|---|
| `auth.register.started` | new user_id | ip, ua, name |
| `auth.email_verified` | user_id | — |
| `auth.login.success` | user_id | ip, ua |
| `auth.login.failed` | NULL | email, ip |
| `auth.logout` | user_id | — |
| `auth.password_reset.success` | user_id | ip |
| `photo.uploaded` | user_id | photo_id, byte_size |
| `photo.auto_approved` | NULL (system) | photo_id, score |
| `photo.auto_rejected_nsfw` | NULL | photo_id, score, categories |
| `photo.pending_review` | NULL | photo_id, score |
| `photo.appealed` | user_id | photo_id, note |
| `photo.appeal.approved` | mod_id | photo_id |
| `photo.appeal.rejected` | mod_id | photo_id |
| `photo.deleted` | user_id | photo_id |
| `photo.moderator_removed` | mod_id | photo_id, reason |
| `honeypot.triggered` | NULL | ip, field, value |
| `honeypot.too_fast` | NULL | ip, age_ms |
| `user.blocked` | admin_id | target, reason |
| `account.deleted_request` | user_id | — |
| `account.deleted_executed` | NULL | user_id |

**Retention:** 2 წელი (proof of consent, abuse forensics).

---

## 20. Risk Matrix (Top 10)

| Risk | P (1-5) | I (1-5) | Score | Mitigation | Priority |
|---|---|---|---|---|---|
| Sensitive photo wrongly auto-approved | 2 | 5 | **10** | Conservative threshold + report-flag auto-hide | P0 |
| Sensitive photo wrongly auto-rejected | 4 | 4 | **16** | Appeal mechanism + moderator review | P0 |
| Email deliverability fail | 3 | 5 | **15** | Resend + DKIM/SPF/DMARC 72h prior | P0 |
| Photographer copyright claim | 3 | 4 | **12** | T&S explicit license + checkbox | P0 |
| DDoS during PR pulse | 2 | 4 | 8 | Cloudflare Pro + rate limits | P1 |
| Bot mass-registration | 3 | 3 | 9 | Honeypot + timestamp + Turnstile + email confirm | P1 |
| Account takeover via leaked password | 2 | 4 | 8 | Argon2 + 2FA admin + HIBP (Phase 2) | P1 |
| Postgres slow under load | 2 | 3 | 6 | Index audit, EXPLAIN, BRIN time-series | P2 |
| GDPR complaint | 2 | 4 | 8 | Privacy + delete + export + cookie banner | P1 |
| Photo dedup spam (same photo) | 3 | 2 | 6 | sha256 unique per user + pHash Phase 2 | P2 |

---

## 21. Site Hierarchy (Post-Refactor)

```
me.matiane.com.ge/
├── index.html               ← Hero (split text+photo) → "გააზიარე შენი მობილური ისტორია" section
├── gallery.html             ← "არქივი" with filters + 3-col grid
├── share-card.html          ← 4 PDF templates + canvas generator
├── how-it-works.html        ← 4-step timeline (only)
├── profile.html             ← User dashboard (auth)
├── reset-password.html      ← 3-step OTP password recovery
├── privacy-policy.html      ← (placeholder; legal text TBD)
├── me-matiane.html          ← Legacy redirect → index.html
└── assets/
    ├── hero.jpg             ← Hero photo (1200×1799, 464KB)
    ├── alta-logo.jpg        ← Floating Alta logo (49KB)
    └── font.ttc             ← (deprecated — not loaded; kept for ref)
```

**Removed sections from index.html (per user feedback):**
- ❌ Mosaic section + entire mosaic.html
- ❌ Mobile Historian Kit section
- ❌ BIG IDEA section ("ალტა ქმნის კოლექტიურ ისტორიას")
- ❌ INSIGHT section (95%/4.7B/∞ stats)
- ❌ FEED section ("ახლახანს დამატებული" photo grid + see-all)
- ❌ HOW section ("მარტივი. სწრაფი. სამუდამოდ." 3 cards)
- ❌ First CHALLENGE section (4 cards + mini canvas generator)

---

## 22. Implementation Roadmap (12 days, May 14-26)

### Day 1-2 (May 14-15) — Foundation ✅ DONE
- Frontend mockups complete (all 8 pages live on GitHub Pages)
- Domain `me.matiane.com.ge` configured

### Day 3-5 (May 16-18) — Backend Foundation
- Supabase project + Postgres schema (`supabase/migrations/0001_initial_schema.sql`)
- Resend account + DKIM/SPF/DMARC DNS (**24-72h propagation — DAY 1 priority**)
- Cloudflare zone setup (DNS, WAF, R2 buckets)
- AWS account + Rekognition IAM
- Env vars + secrets in Supabase Vault

### Day 6-8 (May 19-21) — Auth + OTP
- Edge Functions: register-start, verify-otp, resend-otp, login, password-reset-*
- Frontend wiring: auth modal → real API calls
- Turnstile integration
- Profile auto-create trigger

### Day 9-10 (May 22-23) — Upload + Moderation
- Upload-init + upload-finalize Edge Functions
- R2 presigned URL flow
- EXIF strip pipeline
- AWS Rekognition integration
- Admin queue page (pending review + appeals)

### Day 11 (May 24) — Polish + Hardening
- Real gallery query (RLS)
- Real profile data
- Privacy policy text from Alta.Ge legal
- Load test (k6: 1000 concurrent users, 100 uploads/min)
- RLS audit
- Smoke test full user journey

### Day 12 (May 25) — Pre-launch
- Backup restore drill
- Monitoring dashboards (Sentry, CF Analytics, Better Stack)
- Moderator team briefing
- Final stress test

### May 26 — Launch
- On-call rotation
- Real-time mod queue watching
- Hourly metrics review

---

**Author:** Frontend handoff document
**Last updated:** 19 May 2026
**Version:** 2.0 (reflects full UI redesign + content restructure)

---

> **შენიშვნა დეველოპერისთვის:**
> 1. ფრონტენდი 100% მზადაა (ხილვადობა, responsiveness, კონტენტი)
> 2. ჯერ აუთიდან დაიწყე — ეს არის dependency ყველაფერისთვის
> 3. Upload modal-ის JS-ი (`submitUpload`, `handleFiles`, `handleDrop`) — replace mock setTimeout with real API calls
> 4. Privacy policy ტექსტი ცარიელია — Alta.Ge იურისტი მოგვცემს, შემდეგ paste-ი `privacy-policy.html`-ში
> 5. რეფერენსი: `BUSINESS_LOGIC.md` (this), `supabase/migrations/0001_initial_schema.sql`, `DEPLOYMENT.md`, `CLAUDE.md`
