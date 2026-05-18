# Business Logic Specification — me.matiane.ge

**Adresat:** Backend/Frontend developer
**ვერსია:** 1.0 (14 მაისი 2026)
**პროექტი:** me.matiane.ge — Alta.Ge-ს კოლექტიური ფოტო ისტორიული არქივი

ეს დოკუმენტი აღწერს **რა უნდა აკეთოს სისტემამ** — არა *როგორ* (ეს technical detail-ია). თითო წესი — ცალკე testable item-ი.

---

## სარჩევი

1. [Registration & Authentication](#1-registration--authentication)
2. [Email OTP Verification](#2-email-otp-verification)
3. [Login & Session](#3-login--session)
4. [Password Reset](#4-password-reset)
5. [Profile](#5-profile)
6. [Photo Upload](#6-photo-upload)
7. [Photo Moderation (AI)](#7-photo-moderation-ai)
8. [Appeal Flow](#8-appeal-flow)
9. [Gallery Display](#9-gallery-display)
10. [Photo Deletion](#10-photo-deletion)
11. [Likes](#11-likes)
12. [Comments](#12-comments)
13. [Abuse Reports](#13-abuse-reports)
14. [Admin / Moderator Panel](#14-admin--moderator-panel)
15. [Anonymous Publishing](#15-anonymous-publishing)
16. [Draft Autosave](#16-draft-autosave)
17. [Bot Prevention](#17-bot-prevention)
18. [Rate Limiting](#18-rate-limiting)
19. [Email Notifications](#19-email-notifications)
20. [GDPR / Account Deletion](#20-gdpr--account-deletion)
21. [Audit Log](#21-audit-log)

---

## 1. Registration & Authentication

### 1.1 ვინ
ნებისმიერი ვიზიტორი (unauthenticated).

### 1.2 რა მონაცემები გვჭირდება
| ველი | სავალდებულო | წესი |
|---|---|---|
| `display_name` | ✅ | 2-60 სიმბოლო, trim, არ შეიცავს URL-ს |
| `email` | ✅ | RFC 5322 format, 6-254 სიმბოლო, lowercase normalized |
| `password` | ✅ | min 10 სიმბოლო, max 128 |
| `honeypot` (hidden field) | — | უნდა იყოს **ცარიელი** (bot detection) |
| `form_loaded_at` (timestamp) | — | form-ის ჩატვირთვის დროზე 2 წამზე მეტი უნდა იყოს |
| `turnstile_token` | ✅ | Cloudflare Turnstile-ის ვალიდური token |
| `terms_accepted` | ✅ | checkbox-ი ჩართული |

### 1.3 ფლოუ

1. ვიზიტორი ხსნის `index.html` (ან ნებისმიერ გვერდს)
2. დააწექი "რეგისტრაცია" — ხსნის modal-ს
3. ავსებს ფორმას, აქცევს checkbox-ს, აწექი "გაგრძელება"
4. ფრონტენდი ვალიდაცია:
   - email-ის ფორმატი (regex)
   - password-ის სიგრძე
   - display_name 2-60 სიმბოლო
   - terms checkbox ჩართულია
5. ფრონტენდი აგზავნის request-ს `POST /register-start`
6. ბექენდი ვალიდაცია (იხ. 1.4)
7. ბექენდი:
   - ქმნის `auth.users` record-ს (email_confirm=false)
   - ქმნის `profiles` record-ს
   - გენერირებს 6-ნიშნა OTP კოდს
   - ინახავს HMAC-SHA256(კოდი, server_pepper) `email_verifications`-ში
   - აგზავნის email-ს Resend-ით
   - ბრუნდება `{ verification_id, sent: true }`
8. ფრონტენდი გადადის OTP შესაყვან ეკრანზე

### 1.4 ბექენდის ვალიდაცია (server-side, არასოდეს არ უნდა გაიქცეს)

| შემოწმება | ლიმიტი | შეცდომა |
|---|---|---|
| email format | regex | 400 "ემაილი არასწორია" |
| email length | 6-254 | 400 |
| email domain disposable? | DB check `is_disposable_email()` | 400 "ერთჯერადი ემაილი არ მიიღება" |
| password length | 10-128 | 400 "პაროლი მინ. 10 სიმბოლო" |
| display_name | 2-60 chars | 400 |
| honeypot field empty? | empty | **silent fake success** (don't tell bot) |
| form age > 2 sec? | yes | silent fake success |
| form age < 24 hours? | yes | 400 "გვერდი მოძველდა" |
| Turnstile token valid? | CF verify API | 400 "verification failed" |
| Rate limit: email | max 3/hour | 429 |
| Rate limit: IP | max 5/10min | 429 |

### 1.5 Email Enumeration Prevention

❗ **არასოდეს არ ვაჩვენებთ "ეს email უკვე გამოყენებულია".**

ფლოუ existing email-ისთვის:
1. ვერ ვამცნობთ რომ user არსებობს
2. ვაგზავნით fake `verification_id`-ს
3. ემაილს არ ვაგზავნით (ან ვაგზავნით "if you didn't register, ignore" ტექსტს)
4. UX-ის თვალსაზრისით — user-ი ფიქრობს რომ წარმატებით დარეგისტრდა, შემდეგ OTP ვერ მიდის → ცდილობს reset password-ს

### 1.6 Audit Log Entries
- `auth.register.started` — actor_id=user_id, metadata={ip, ua}
- `auth.register.disposable_email_blocked` — metadata={email_domain}
- `honeypot.triggered` — metadata={field, value_preview}
- `honeypot.too_fast` — metadata={age_ms}

---

## 2. Email OTP Verification

### 2.1 OTP Generation Rules

| პარამეტრი | მნიშვნელობა |
|---|---|
| სიგრძე | 6 ნიშნა (numeric) |
| Generation | CSPRNG (`crypto.randomInt(100000, 1000000)`) — NEVER `Math.random()` |
| Storage | HMAC-SHA256(code, `OTP_PEPPER`) — 32 bytes |
| TTL | **10 წუთი** |
| Max verify attempts | **5** per code (then code invalidated) |
| Max resend per code | **3** in 15 min |
| Resend cooldown | **60 წამი** |

### 2.2 OTP Email Template

Subject: `{code} — დადასტურების კოდი`
Body: HTML email containing:
- სალამი user-ის სახელით
- 6-ნიშნა კოდი დიდი ფონტით, monospace
- "10 წუთის განმავლობაში ვალიდურია" შენიშვნა
- "თუ ეს თქვენ არ მოგითხოვიათ — უგულებელყავით" footer

### 2.3 Verify Flow

1. User შეჰყავს 6 ნიშანი
2. Frontend: `POST /verify-otp { verification_id, code }`
3. Backend:
   - `claim_verification_attempt(verification_id)` RPC — atomic increment
   - თუ row not found OR `consumed_at != null` → **401 "კოდი არასწორია ან ვადაგასულია"**
   - თუ `attempts >= 5` → **429 "ცდები ამოწურულია, გადადით ხელახლა რეგისტრაციაზე"**
   - თუ `expires_at < now()` → **410 "კოდს ვადა გაუვიდა"**
   - HMAC compare (timing-safe) — თუ არ ემთხვევა → **401 "კოდი არასწორია"** + remaining attempts
   - წარმატება:
     - `consumed_at = now()` UPDATE
     - `auth.users.email_confirmed_at = now()` UPDATE (via admin API)
     - audit_log: `auth.email_verified`
     - Generate session JWT
4. Frontend redirect to `/index.html` (or original referrer)

### 2.4 Resend Flow

1. User აწექს "გადაგზავნა"
2. Frontend: `POST /resend-otp { verification_id }`
3. Backend:
   - Check resent_count < 3 — else 429
   - Check last sent > 60 sec ago — else 429 with remaining cooldown
   - Generate new code (replaces old hash; resets attempts to 0)
   - `resent_count++`
   - Update `expires_at = now() + 10min`
   - Resend email
4. Frontend: restart 60sec cooldown timer

---

## 3. Login & Session

### 3.1 Login Flow

1. User ფორმაში: email + password
2. Frontend: `POST /login`
3. Backend:
   - Rate limit: 10 attempts/min per IP, 5 fails/15min per email
   - **Account lockout:** თუ 5 fails in 15min → **423 "ანგარიში დაბლოკილია 15 წუთით"**
   - Verify password (Argon2 compare)
   - Verify `email_confirmed_at IS NOT NULL` — თუ NULL → **403 "გთხოვ დაადასტურე ემაილი"**
   - Verify `profiles.is_blocked = FALSE` — თუ TRUE → **403 "ანგარიში დაბლოკილია"**
   - Issue access JWT (1h TTL) + refresh cookie (7 days, HttpOnly, Secure, SameSite=Lax)
   - audit_log: `auth.login.success` ან `auth.login.failed`
   - Log to `login_attempts` table

### 3.2 Failed Login Response

⚠️ **Generic error** — არ ვამცნოთ "ემაილი არ არსებობს" vs "პაროლი არასწორია":
- ✅ "ემაილი ან პაროლი არასწორია"
- ❌ "ეს ემაილით user-ი არ მოიძებნა"

### 3.3 Session Refresh

- Access token expire-ი 1h-ში
- Refresh token-ი 7 დღე
- **Rotation:** ყოველი refresh ანულირებს ძველს და გასცემს ახალს
- **Reuse detection:** თუ ერთი და იგივე refresh-ი 2-ჯერ გამოიყენება → ყველა session ლიკვიდდება + alert audit_log-ში

### 3.4 Logout

1. Frontend: `POST /logout`
2. Backend: refresh token ლიკვიდდება, cookie ცარიელდება
3. audit_log: `auth.logout`

---

## 4. Password Reset

### 4.1 Request Reset

1. User: `reset-password.html` ფორმაში email
2. Frontend: `POST /password-reset-start`
3. Backend:
   - **Always return 200** (enumeration prevention)
   - Rate limit: 3/hour per email, 5/10min per IP
   - თუ user არსებობს და confirmed: გენერირებს 6-ნიშნა OTP-ს, აგზავნის email-ით
4. Frontend: "კოდი გავგზავნეთ" message

### 4.2 Confirm Reset

1. User: კოდი + ახალი პაროლი
2. Frontend: `POST /password-reset-confirm`
3. Backend:
   - Verify OTP (same flow as registration verify)
   - Password validation (10-128 chars)
   - Hash + update (Argon2id)
   - **Invalidate all existing sessions** (security: assume password was compromised)
   - audit_log: `auth.password_reset.success`
4. Frontend: redirect to login

---

## 5. Profile

### 5.1 Profile Fields

| ველი | Editable | Validation |
|---|---|---|
| `display_name` | ✅ | 2-60 chars, no URLs |
| `publish_anonymously_default` | ✅ | boolean |
| `email` | ✅ via flow | requires re-verification |
| `password` | ✅ via flow | invalidates all sessions |
| `role` | ❌ (admin only) | enum |

### 5.2 Profile View (Public)

ნებისმიერი visitor-ი ხედავს:
- `display_name` (თუ user-ი არ არის anonymous გასაჯაროვებაში)
- `active_photo_count`
- ფოტოების gallery (filtered: status='approved')

ვერ ხედავს:
- email, თარიღი დაბადებისა, IP, login history

### 5.3 Email Change Flow

1. User Settings → Change Email
2. შეჰყავს ახალი email + current password
3. Backend: OTP გაიგზავნება ახალ email-ზე
4. User შეჰყავს OTP-ს
5. Email updated, old email-ი იღებს notification "თქვენი email შეიცვალა"
6. All sessions invalidated

---

## 6. Photo Upload

### 6.1 Preconditions

- User authenticated
- `email_confirmed_at IS NOT NULL`
- `profiles.is_blocked = FALSE`
- `profiles.active_photo_count < 15`

### 6.2 Upload Form Fields

| ველი | სავალდებულო | წესი | UI Validation |
|---|---|---|---|
| ფაილი | ✅ | image/jpeg, png, webp, heic; ≤ 25MB; ≤ 8000×8000 | live |
| სათაური | ✅ | 10-120 სიმბოლო | live char counter |
| დახასიათება | ✅ | 100-2000 სიმბოლო | live char counter |
| თარიღი (`taken_at`) | ❌ | YYYY-MM-DD, ≤ today, ≥ 1900-01-01 | date picker |
| ლოკაცია (`location_label`) | ❌ | text 0-120 chars | — |
| tags | ❌ | 0-10 tags, each 2-30 chars `[\p{L}\p{N}-]` | tag input |
| `publish_anonymously` | ❌ | checkbox, default = profile.publish_anonymously_default | — |
| `terms_accepted` | ✅ | checkbox, required | — |

### 6.3 Character Counter Behavior

ფორმის ქვეშ ცოცხალი counter:

- **სათაური:** `"32 / 10 სიმბოლო"`
  - წითელი (`#E53A2F`) როცა < 10
  - მწვანე (`#4CAF50`) როცა ≥ 10
- **დახასიათება:** იგივე ლოგიკა, threshold 100

### 6.4 Upload Flow

**Step 1: Init**
1. Frontend: ფაილის არჩევა → client-side ვალიდაცია (size, type, dimensions)
2. Frontend: `POST /upload-init { byte_size, mime_type, sha256_hex }`
3. Backend:
   - Auth check
   - Rolling limit check: `profiles.active_photo_count < 15`
   - Rate limit: 30 uploads/hour per user, 100/day
   - Per-user dedup: `SELECT id FROM photos WHERE uploader_id=? AND sha256=? AND deleted_at IS NULL` → თუ არსებობს → **409 "ეს ფოტო თქვენ უკვე ატვირთული გაქვთ"**
   - **15-ე ფოტოს ფლეგი:** თუ `active_photo_count == 14` → response includes `is_last_slot: true`
   - გასცემს R2 presigned PUT URL (TTL: 5 min)
   - ქმნის `photos` record (status='uploading')
   - Returns: `{ photo_id, upload_url, is_last_slot }`

**Step 2: Direct Upload to R2**
1. Frontend: `PUT {upload_url}` with file bytes (with progress bar)
2. R2 returns 200

**Step 3: Finalize**
1. Frontend: `POST /upload-finalize { photo_id, title, description, taken_at?, location_label?, tags?, publish_anonymously, terms_accepted, turnstile_token }`
2. Backend:
   - Verify R2 object exists; verify size matches `byte_size`
   - Fetch object → verify magic bytes match `mime_type` (NOT trust user's claim)
   - Compute SHA-256 → must match what client sent (anti-tampering)
   - **EXIF strip** (ALL metadata, including orientation applied) → re-store stripped version
   - Validate fields (server-side mirror of frontend):
     - title 10-120
     - description 100-2000
     - tags count + length
   - `status = 'scanning'` UPDATE
   - **AWS Rekognition** call (async or sync depending on architecture)
   - Decision (see Section 7):
     - score < 0.5 → `status = 'approved'` + copy to public bucket
     - 0.5-0.7 → `status = 'pending_review'`
     - ≥ 0.7 → `status = 'rejected_nsfw'`
   - audit_log: `photo.uploaded`, optionally `photo.auto_approved`/`rejected_nsfw`/`pending_review`
3. Frontend:
   - თუ `is_last_slot == true && success` → show "შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!" modal
   - სხვა შემთხვევებში → redirect to gallery or photo detail

### 6.5 Error Scenarios

| შემთხვევა | Status code | Message |
|---|---|---|
| File > 25MB | 413 | `"ფაილი 25MB-ს აღემატება"` |
| Wrong MIME (magic bytes) | 415 | `"ფაილის ფორმატი დაუშვებელია"` |
| Dimensions > 8000×8000 | 413 | `"გამოსახულება ძალიან დიდია (max 8000×8000)"` |
| Same SHA-256 by same user | 409 | `"ეს ფოტო თქვენ უკვე გაქვთ ატვირთული"` |
| `active_photo_count >= 15` | 429 | `"შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!"` |
| Title < 10 chars | 400 | `"სათაური მინ. 10 სიმბოლო"` |
| Description < 100 chars | 400 | `"დახასიათება მინ. 100 სიმბოლო"` |
| Rate limit hit | 429 | `"ძალიან ბევრი ცდა, სცადეთ მოგვიანებით"` |
| Terms not accepted | 400 | `"გთხოვთ მიიღოთ პირობები"` |
| Turnstile fail | 400 | `"ვერიფიკაცია ვერ შესრულდა"` |

### 6.6 Rolling 15-Photo Limit Logic

**მნიშვნელოვანი:**
- **UI-ში არ ვაჩვენებთ "X/15"-ს upload-მდე**
- მე-15 ფოტოს წარმატებული ატვირთვის შემდეგ → **მეგობრული modal** ტექსტით:
  > "შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!"
  >
  > (ეს ტექსტი მოდიფიცირებადია env var-ით ან DB `app_settings`-ში)
- ფოტოს წაშლის შემდეგ user-ს შეუძლია ხელახლა ატვირთოს

**Counter რომელი ფოტოები ითვლება:**
- ✅ `approved`
- ✅ `scanning`, `pending_review`, `uploading`, `appealed`
- ❌ `rejected_nsfw` (არ ითვლება — user-მა შეიძლება ხელახლა სცადოს)
- ❌ `removed`
- ❌ `deleted_at IS NOT NULL`

Trigger `trg_photo_count` ავტომატურად ანახლებს `profiles.active_photo_count`.

---

## 7. Photo Moderation (AI)

### 7.1 NSFW Categories Tracked

AWS Rekognition `DetectModerationLabels` ბრუნდება ლეიბლების სიას. ჩვენ ვადევნოთ თვალყურს:

- `Explicit Nudity`, `Nudity`
- `Graphic Violence Or Gore`
- `Hate Symbols`
- `Visually Disturbing`

`ai_nsfw_score` = max(score) ამ კატეგორიებიდან.

### 7.2 Decision Thresholds

| Score | Decision | Photo Status | User Sees |
|---|---|---|---|
| < 0.50 | Auto-approve | `approved` | ფოტო public გალერეაში |
| 0.50–0.70 | Human review | `pending_review` | "თქვენი ფოტო შემოწმდება" შეტყობინება |
| ≥ 0.70 | Auto-reject | `rejected_nsfw` | "ფოტო ვერ მოხვდა საიტზე. გასაჩივრება შესაძლებელია." |

⚠️ **Thresholds კონფიგურირებადია** — საჭიროა env vars ან DB settings ცხრილში.

### 7.3 Rekognition Failure Handling

თუ Rekognition API-ი 5xx ბრუნდება ან timeout:
- **Retry 3-ჯერ** exponential backoff (1s, 2s, 4s)
- თუ მაინც ვერ ხერხდება → `status = 'pending_review'`, admin queue-ში მოდის
- audit_log: `photo.moderation.failed`

### 7.4 Rejected Photo User Flow

User ხედავს თავის profile-ში:
1. ფოტოს თამბნაილი blur-ით
2. წითელი badge: "უარყოფილია"
3. ღილაკი "გასაჩივრება"

---

## 8. Appeal Flow

### 8.1 User Submits Appeal

1. User თავის dashboard-ში ხედავს `rejected_nsfw` ფოტოს
2. აწექს "გასაჩივრება"
3. Modal იხსნება — text area "რატომ ფიქრობთ რომ ფოტო კარგია?"
4. Frontend: `POST /appeal-photo { photo_id, appeal_note }`
5. Backend:
   - Verify ownership
   - Verify `status = 'rejected_nsfw'`
   - **Rate limit:** 1 appeal per photo, max 3 appeals/day per user
   - UPDATE: `status = 'appealed'`, `appealed_at = now()`, `appeal_note = ?`
   - audit_log: `photo.appealed`
6. User ხედავს: "თქვენი გასაჩივრება მიღებულია. 24 საათში პასუხს მიიღებთ."

### 8.2 Moderator Reviews Appeal

1. Moderator dashboard-ში ხედავს queue-ს (status='appealed' OR 'pending_review')
2. Sort by `appealed_at ASC` (FIFO)
3. ხედავს ფოტოს + appeal_note + ai_nsfw_score + ai_categories
4. ორი ღილაკი: "დადასტურება" / "უარყოფა"

### 8.3 Approve Decision

- UPDATE: `status = 'approved'`, `reviewed_by = mod_id`, `reviewed_at = now()`
- Copy R2 object to public bucket
- Email user: "თქვენი ფოტო დადასტურდა"
- audit_log: `photo.appeal.approved`

### 8.4 Final Reject Decision

- UPDATE: `status = 'rejected_nsfw'`, `reviewer_note = ?`
- Email user: "სამწუხაროდ, ფოტო არ შეესაბამება საიტის წესებს"
- **Cannot appeal again** — flag `appeal_used` (or check if `appeal_note IS NOT NULL`)
- audit_log: `photo.appeal.rejected`

### 8.5 Appeal SLA

- **24 საათი** moderator-ის პასუხისთვის
- Moderator working hours: 09:30 - 18:30 (დილით ერთხელ + საღამოს ერთხელ queue შემოწმება)
- თუ queue 24 საათში არ პასუხდება → admin notification

---

## 9. Gallery Display

### 9.1 Public Gallery

URL: `gallery.html`

ნებისმიერი visitor-ი ხედავს ფოტოებს რომელთა:
- `status = 'approved'`
- `deleted_at IS NULL`

### 9.2 Default Sort

`created_at DESC` (newest first).

### 9.3 Filters

User-ი ფილტრავს:
- **ტეგი:** `tags @> ARRAY[?]`
- **თარიღი (taken_at):** range from/to
- **ლოკაცია:** text search `location_label ILIKE %?%`
- **ფოტოგრაფი (uploader):** `uploader_id = ?` (თუ public profile)

### 9.4 Sort Options

- უახლესი პირველი (`created_at DESC`)
- ძველი პირველი (`created_at ASC`)
- ფოტოს თარიღი ახალი (`taken_at DESC NULLS LAST`)
- პოპულარული (`like_count DESC`)

### 9.5 Pagination

Cursor-based:
- First page: `created_at < now() ORDER BY created_at DESC LIMIT 24`
- Next page: `created_at < ?last_seen_created_at ORDER BY ... LIMIT 24`

### 9.6 Photo Card Shows

- Thumbnail (R2 derivative)
- სათაური
- ფოტოგრაფი: `display_name` ან `"ანონიმური მოქალაქე"` (თუ `publish_anonymously = TRUE`)
- `like_count`
- `comment_count` (denormalized recommended)
- ფოტოს თარიღი (`taken_at`) თუ მითითებულია

### 9.7 Photo Detail Page

URL: `photo/{id}.html` (ან SPA route)

ნახულობს:
- სრული რეზოლუცია (R2 public derivative)
- სათაური + description
- ფოტოგრაფი (ან ანონიმური)
- ლოკაცია (თუ აქვს)
- თარიღი (`taken_at` and `created_at`)
- ტეგები
- like ღილაკი
- კომენტარების სია
- "Report" ღილაკი
- "Share" ღილაკები (Facebook, WhatsApp)

---

## 10. Photo Deletion

### 10.1 User Deletes Own Photo

⚠️ **მაშინვე და სამუდამოდ** — recovery არ არსებობს.

1. User თავის dashboard-ში → ფოტოს კონტექსტ მენიუ → "წაშლა"
2. **Confirmation modal:** "ნამდვილად გინდა წაშლა? ეს ვერ დაბრუნდება."
3. User: "დიახ, წაშალე"
4. Frontend: `DELETE /photos/{id}`
5. Backend:
   - Verify ownership
   - **Hard delete:**
     - DELETE R2 object (original + public + thumb)
     - UPDATE: `deleted_at = now()`, `status = 'removed'`
     - Trigger decrements `profiles.active_photo_count`
   - audit_log: `photo.deleted` actor_id=user

### 10.2 Moderator Removes Photo

1. Admin panel-ში moderator აწექს "წაშლა"
2. შეჰყავს მიზეზი (`reviewer_note`)
3. Backend:
   - `deleted_at = now()`, `status = 'removed'`, `reviewer_note = ?`
   - **გადადება R2-დან საბოლოოდ: 7 დღე** (admin-ს რომ შეცდომის გასწორება შეუძლოს)
   - Email user: "თქვენი ფოტო წაშლილია მოდერატორის მიერ. მიზეზი: ..."
   - audit_log: `photo.moderator_removed`

---

## 11. Likes

### 11.1 Like a Photo

1. Authenticated user აწექს გულის ხატულას
2. Frontend: `POST /photos/{id}/like`
3. Backend:
   - INSERT `photo_likes (user_id, photo_id)` — ON CONFLICT DO NOTHING
   - Trigger increments `photos.like_count`
   - Returns: `{ liked: true, total: N }`

### 11.2 Unlike

1. Frontend: `DELETE /photos/{id}/like`
2. Backend:
   - DELETE row
   - Trigger decrements
   - Returns: `{ liked: false, total: N-1 }`

### 11.3 Rate Limit

- 60 likes/min per user (sanity check, but generous)

---

## 12. Comments

### 12.1 Create Comment

1. Authenticated user ფოტოს detail page-ზე
2. Form: textarea + submit
3. Frontend: `POST /photos/{id}/comments { body }`
4. Backend:
   - Validate: 1-1000 chars, trimmed
   - **Rate limit:** 5 comments/min per user
   - Check `profiles.is_blocked = FALSE`
   - INSERT `comments` (status='visible' default)
   - **Light auto-moderation:** spam keyword filter (Phase 2 — flag for review)
   - Returns comment object

### 12.2 Comment Display

- Default sort: `created_at ASC` (chronological)
- ფოტოგრაფი: `display_name` (comments არ არიან ანონიმური)
- Edit window: 5 წუთი after creation
- Delete: ნებისმიერ დროს მფლობელის მიერ

### 12.3 Comment Moderation

- 3+ reports → `status = 'pending_review'` (trigger)
- Moderator queue-ში მოდის
- Approved → `status = 'visible'`
- Rejected → `status = 'hidden'` (user-ი ხედავს, public არა) ან `'removed'`

---

## 13. Abuse Reports

### 13.1 Report a Photo

1. User აწექს "Report" detail page-ზე
2. Modal: dropdown "მიზეზი" + textarea "დეტალები"
3. Reasons enum:
   - `nsfw` — პორნოგრაფია/ნუდიზმი
   - `violence` — ძალადობა/ძარცვა
   - `hate_speech` — შეურაცხყოფა/სიძულვილის ენა
   - `spam` — სპამი
   - `copyright` — copyright დარღვევა
   - `privacy` — პერსონალური მონაცემები
   - `other` — სხვა (details required)
4. Frontend: `POST /reports { photo_id, reason, details }`
5. Backend:
   - Rate limit: 10 reports/day per user
   - INSERT `reports`
   - Trigger `check_report_threshold` — თუ 3+ open reports → `photos.status = 'pending_review'`
   - audit_log: `report.created`

### 13.2 Auto-hide on Threshold

3 unique reports (different reporter_ids) → photo moves to `pending_review` queue.

---

## 14. Admin / Moderator Panel

### 14.1 Access

URL: `/admin` (separate page or route-protected)

Allowed roles: `moderator`, `admin`.

Authentication: same session JWT + role check.

⚠️ **2FA mandatory** for moderator/admin accounts.

### 14.2 Dashboards

**Moderation Queue:**
- `status IN ('pending_review', 'appealed')`
- Sort by appealed_at ASC, then created_at ASC
- Actions: Approve / Reject

**Reports Queue:**
- `reports.status = 'open'`
- Group by photo_id
- Actions: Resolve (hide photo) / Dismiss

**User Management (admin only):**
- Search by email/display_name
- Block/unblock account
- Force password reset
- Delete account (GDPR)

### 14.3 Moderator Actions Logged

Every action → `audit_log`:
- `photo.approved` actor=mod_id, target=photo_id
- `photo.rejected`
- `comment.removed`
- `user.blocked`
- `report.resolved`

### 14.4 Moderator Email Notifications

- ყოველი ახალი `pending_review` ან `appealed` photo → email-ი (digest, ყოველ 2 საათში)
- ყოველი ახალი report → immediate email

---

## 15. Anonymous Publishing

### 15.1 Per-Photo Toggle

ფოტოს ატვირთვისას:

```
☐ ანონიმური გასაჯაროვება — ჩემი სახელი არ ჩანს ფოტოს გვერდით
```

Default = `profiles.publish_anonymously_default` (user-ის profile-ში წინასწარ მითითებული).

### 15.2 Display Logic

თუ `photos.publish_anonymously = TRUE`:
- Public views: `display_name` ჩანაცვლდება "ანონიმური მოქალაქე"-თ
- ფოტოს detail-ში: არ ჩანს ლინკი profile-ზე
- Likes/comments user-ის სახელით ხდება (separate from anonymous photo)

### 15.3 Server Knows

⚠️ **Alta.Ge-ის შიდა მონაცემები (`audit_log`, admin queries, court orders) ცნობს ვინ ატვირთა.** ეს არ არის ფაქტობრივი ანონიმობა — ეს არის *display* anonymity.

---

## 16. Draft Autosave

### 16.1 What's Saved

`localStorage` key: `memat:upload-draft:v1`

Fields stored (NOT photo file):
- title
- description
- location_label
- taken_at
- publish_anonymously
- timestamp `saved_at`

### 16.2 Save Trigger

- ნებისმიერი ფორმის ველის `input` event → debounced 500ms → save

### 16.3 Restore Trigger

- Page load → check localStorage
- If exists AND not expired AND fields non-empty → show modal "ნახაზი ნაპოვნია. აღვადგინო?"
- User accepts → populate fields, fire `input` events (for char counters)
- User declines → clearDraft()

### 16.4 TTL

- 7 days
- ხანდახან expired → silent delete

### 16.5 Clear

- Successful upload → `clearDraft()`
- Explicit "Cancel" button → optional clear (or keep for later)

---

## 17. Bot Prevention

### 17.1 Honeypot Field

Hidden via:
```css
position: absolute; left: -9999px;
width: 1px; height: 1px; opacity: 0;
pointer-events: none;
```
+ `aria-hidden="true"` + `tabindex="-1"`.

If filled → silent fake success on server.

### 17.2 Form Timestamp

Hidden input `form_loaded_at` set to `Date.now()` on page load.

Server checks:
- `now() - form_loaded_at < 2000ms` → bot, silent fake
- `now() - form_loaded_at > 24h` → stale, "refresh page" error

### 17.3 Cloudflare Turnstile

- Site key in frontend, secret on backend
- Invisible mode — only challenges if suspicious
- Token required on: register, login, password reset, upload-finalize
- If invalid → 400 "verification failed"

---

## 18. Rate Limiting

| Endpoint | Limit | Counter Source |
|---|---|---|
| `/login` | 10/min per IP, 5 fails/15min per email | DB `login_attempts` |
| `/register-start` | 3/hour per email, 5/10min per IP | DB `email_verifications` |
| `/verify-otp` | (handled by attempts counter) | per-code |
| `/resend-otp` | 3/code lifetime, 60s cooldown | row counter |
| `/password-reset-start` | 3/hour per email, 5/10min per IP | DB |
| `/upload-init` | 30/hour, 100/day per user | DB count |
| `/photos/*/like` | 60/min per user | in-memory or Redis |
| `/photos/*/comments` | 5/min per user | in-memory or Redis |
| `/reports` | 10/day per user | DB count |
| **Cloudflare WAF — global** | 60/min anon, 300/min auth | CF |

Response: 429 with `Retry-After` header in seconds.

---

## 19. Email Notifications

### 19.1 Triggered Emails

| Event | To | Template |
|---|---|---|
| Registration | new user | OTP code |
| OTP resend | user | new OTP code |
| Password reset request | user | OTP code |
| Email change | user (new email) | OTP code |
| Email change | user (old email) | "your email was changed" notification |
| Photo auto-approved | uploader | "თქვენი ფოტო გასაჯაროვდა" + link |
| Photo rejected (NSFW) | uploader | "ფოტო არ მოხვდა საიტზე" + appeal info |
| Appeal approved | uploader | "თქვენი ფოტო დადასტურდა" |
| Appeal rejected | uploader | "სამწუხაროდ, ფოტო არ შეესაბამება წესებს" |
| Moderator removed | uploader | "თქვენი ფოტო წაშლილია მოდერატორის მიერ" |
| Account blocked | user | "თქვენი ანგარიში დაბლოკილია" |
| Moderation queue digest | moderator | every 2h if non-empty |
| New report | moderator | immediate |

### 19.2 Email Throttling

- Same user same template — max 5/day
- Digest emails — never more than 1/hour to same recipient

---

## 20. GDPR / Account Deletion

### 20.1 Right to Erasure

User-ის request:
1. Settings → "ანგარიშის წაშლა"
2. Confirmation modal: "ეს მოქმედება სამუდამოა. დარწმუნებული ხართ?"
3. Re-authenticate (re-enter password)
4. Backend:
   - Soft-delete period: **24 საათი** ("რა მოხდება თუ გადავიფიქრე?")
   - Email sent: "თქვენი ანგარიში 24 საათში სრულად წაიშლება. გადახედვა შესაძლებელია მხოლოდ ახლა."
   - After 24h cron:
     - `auth.users` DELETE (cascade → profiles, photos, comments, likes, reports)
     - R2 objects DELETE (originals + public + thumbs)
     - `audit_log` retained (GDPR allows for legitimate interest — security forensics)
5. audit_log: `account.deleted_request`, `account.deleted_executed`

### 20.2 Right to Portability

User-ის request:
1. Settings → "მონაცემების ექსპორტი"
2. Backend asynchronously builds:
   - JSON: profile, photos metadata, comments, likes, reports
   - ZIP: all photos (originals from R2)
3. Email-ი with download link (signed, 7 day TTL)

### 20.3 Right of Access

Same as Right to Portability — JSON-ი იგზავნება email-ით.

### 20.4 Cookie Consent

First-visit banner:
```
ვიყენებთ cookies-ს რომ საიტი იმუშაოს და გავაუმჯობესოთ მომსახურება.
Essential cookies სავალდებულოა. Analytics — შენი არჩევანი.

[ ყველას მიღება ] [ მხოლოდ აუცილებელი ] [ პერსონალიზაცია ]
```

- Choice stored in localStorage `memat:cookie-consent` + cookie
- Analytics scripts load only if user opted in
- Essential cookies (auth) always allowed

---

## 21. Audit Log

### 21.1 Events Logged

| Action | Actor | Metadata |
|---|---|---|
| `auth.register.started` | user_id (new) | ip, ua |
| `auth.email_verified` | user_id | — |
| `auth.login.success` | user_id | ip, ua |
| `auth.login.failed` | NULL | email, ip, ua |
| `auth.logout` | user_id | — |
| `auth.password_reset.success` | user_id | ip |
| `auth.email_changed` | user_id | old_email, new_email |
| `photo.uploaded` | user_id | photo_id, byte_size |
| `photo.auto_approved` | NULL (system) | photo_id, score |
| `photo.auto_rejected_nsfw` | NULL | photo_id, score, categories |
| `photo.pending_review` | NULL | photo_id, score |
| `photo.appealed` | user_id | photo_id |
| `photo.appeal.approved` | mod_id | photo_id |
| `photo.appeal.rejected` | mod_id | photo_id, note |
| `photo.moderator_removed` | mod_id | photo_id, note |
| `photo.deleted` | user_id | photo_id |
| `comment.created` | user_id | comment_id, photo_id |
| `comment.removed` | mod_id or user_id | comment_id |
| `report.created` | reporter_id | photo_id or comment_id, reason |
| `report.resolved` | mod_id | report_id, action |
| `user.blocked` | admin_id | target_user_id, reason |
| `user.unblocked` | admin_id | target_user_id |
| `account.deleted_request` | user_id | — |
| `account.deleted_executed` | NULL | user_id |
| `honeypot.triggered` | NULL | ip, field, value_preview |
| `honeypot.too_fast` | NULL | ip, age_ms |
| `photo.moderation.failed` | NULL | photo_id, error |

### 21.2 Retention

- 2 წელი (proof of consent, abuse forensics)
- Partitioning by month recommended Phase 2

### 21.3 Read Access

`audit_log` table → admin only (RLS enforced).

---

## 22. Configuration / Feature Flags

### 22.1 Editable Without Code Deploy

ეს ცვლადები უნდა იყოს env vars-ში ან `app_settings` DB ცხრილში — non-developer can change:

| Setting | Default | Where |
|---|---|---|
| Photo limit per user | 15 | env: `PHOTO_LIMIT_PER_USER` |
| Photo limit reached message | "შენ შენი წვლილი შეიტანე — 15 ფოტო ატვირთე. მადლობა!" | env or DB |
| Max file size MB | 25 | env: `MAX_FILE_SIZE_MB` |
| OTP TTL minutes | 10 | env |
| OTP resend cooldown sec | 60 | env |
| Login lockout fails | 5 | env |
| Login lockout window min | 15 | env |
| NSFW auto-reject threshold | 0.70 | env: `NSFW_AUTO_REJECT_THRESHOLD` |
| NSFW review threshold | 0.50 | env: `NSFW_REVIEW_THRESHOLD` |
| Report threshold for auto-hide | 3 | env |
| Account deletion grace period hours | 24 | env |
| Terms version | "v1" | env: `TERMS_VERSION` |

---

## 23. Open Questions / Decisions Pending

| # | Question | Owner | Deadline |
|---|---|---|---|
| 1 | Content license — granular per-use ან general? | Alta.Ge legal | 22 May |
| 2 | Account deletion — fully delete or anonymize photos? | Alta.Ge legal | 22 May |
| 3 | Minor users (under 18) — allowed? | Alta.Ge legal | 22 May |
| 4 | DPO appointment | Alta.Ge | 22 May |
| 5 | Moderator name + email + schedule confirmation | Alta.Ge PR | 21 May |
| 6 | Corporate account credentials | Alta.Ge IT | 16 May |
| 7 | DKIM/SPF/DMARC DNS records propagation | Alta.Ge DNS | 17 May (72h before launch buffer) |

---

## დასასრული

ეს დოკუმენტი = ერთი source of truth ბიზნეს ლოგიკისთვის.

თუ რამე გაუგებარია / დაკარგულია — ღია issue GitHub-ში: github.com/levankharaishvili32-afk/me-matiane/issues

---

**Author:** Architecture conversation — Senior Full-Stack Engineer review
**Last updated:** 14 მაისი 2026
**Version:** 1.0
