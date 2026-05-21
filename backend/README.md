# FastAPI <-> ORDS integration notes

FastAPI expects these ORDS endpoints under `{ORDS_BASE_URL}`:
- POST `/auth/google/upsert`
- POST `/auth/dev/resolve-user` (dev-only login helper)
- POST `/competitions/register`
- POST `/submissions`
- GET `/competitor/competitions?user_id=...`
- GET `/competitor/open-checkpoints?competition_id=...&user_id=...`
- GET `/results/score?competition_id=...&user_id=...`
- GET `/organizer/leaderboard?competition_id=...`
- GET `/i18n/translations?lang=...&default_lang=...`

Expected ORDS JSON responses:
- `auth/google/upsert` -> `{ "user_id": 123 }`
- `competitions/register` -> `{ "competition_id": 456 }`
- `submissions` -> `{ "submission_id": 789, "is_correct": "Y|N", "awarded_points": 0, "total_score": 42 }`
- `competitor/competitions` -> `{ "items": [{ "competition_id": 1, "name": "..." }] }`
- `competitor/open-checkpoints` -> `{ "items": [...] }`
- `results/score` -> `{ "score": 42 }`
- `organizer/leaderboard` -> standard ORDS query JSON (`items` array), for example:
  `{ "items": [{ "user_id": 1, "score": 100 }] }`
- `i18n/translations` -> `{ "lang":"et","default_lang":"et","items":{"competitor.heading":"..."}}`

Session cookie flow:
- `POST /api/auth/google` now sets an HttpOnly session cookie (`SESSION_COOKIE_NAME`, default `funo_session`).
- `POST /api/dev/login` can set the same cookie in dev mode (`APP_ENV=dev`) without Google token.
- Protected endpoints resolve user from session cookie first.
- `user_id` in payload and `x-user-id` header are optional guards; if sent, they must match session user.

Required backend env:
- `ORDS_BASE_URL`
- `SESSION_SECRET` (required for cookie signing)
- Optional: `SESSION_COOKIE_NAME`, `SESSION_COOKIE_SECURE`, `ORDS_USERNAME`, `ORDS_PASSWORD`, `GOOGLE_CLIENT_ID`, `APP_ENV`
- Optional map-provider keys: `MAPYCZ_API_KEY`, `MAPTILER_API_KEY`
- Optional i18n config: `LANG_AVAILABLE` (for example `et,en`), `LANG_DEFAULT` (for example `et`)
- FastAPI loads i18n translations to in-memory cache on startup for every `LANG_AVAILABLE` language.
- You can reload i18n cache without restarting backend: `POST /api/i18n/reload`

Map layer config (admin "Näita kaardil"):
- File: `backend/app/map_layers.json`
- Endpoint: `GET /api/map-layers`
- Config is cached in backend memory (`MAP_LAYERS_CACHE_TTL_SECONDS`, currently 900s).
- If a layer has `"enabled": false`, it is hidden from UI.
- If a layer URL contains `{MAPYCZ_API_KEY}` or `{MAPTILER_API_KEY}`, the backend injects key from `.env`.
  If key is missing, that layer is automatically omitted from API response.
- Supported layer types:
  - `layer_type: "xyz"` (default) -> Leaflet `L.tileLayer(...)`
  - `layer_type: "wms"` -> Leaflet `L.tileLayer.wms(...)` with optional
    `wms_layers`, `wms_format`, `wms_transparent`, `wms_version`
- Optional CRS override per layer: `crs` (for example `EPSG:3301`).
- Current optional providers:
  - `mapycz_outdoor` (Mapy.cz Outdoor)
  - `maptiler_outdoor` (MapTiler Outdoor)

Ubuntu smoke test without Google (dev mode):
1. Set `APP_ENV=dev` and restart backend.
2. Login and store cookie:
   `curl -sS -c cookies.txt -H "Content-Type: application/json" -d '{"email":"test@funo.local"}' http://localhost/api/dev/login`
3. Register:
   `curl -sS -b cookies.txt -H "Content-Type: application/json" -d '{"access_code":"TEST123"}' http://localhost/api/competitions/register`

Error mapping:
- ORA-20031 -> INVALID_ACCESS_CODE
- ORA-20032 -> ACCESS_CODE_LIMIT_REACHED
- ORA-20033 -> ALREADY_REGISTERED
- ORA-20060 -> INVALID_SUBMISSION
- ORA-20061 -> NOT_PARTICIPANT
- ORA-20010 -> INVALID_GOOGLE_PROFILE

I18n cache reload:
- Endpoint: `POST /api/i18n/reload`
- Example:
  `curl -sS -X POST "http://localhost:8080/api/i18n/reload"`

Database scripts added:
- ORDS handlers: `db/oracle/ords/07_ords_handlers.sql`
- App packages with active-record business checks: `db/oracle/api/05_api_packages_stub.sql`

## Timezone and datetime rules (UTC in DB, local time in UI)

Authoritative rule:
- Database timezone stays UTC.
- Backend/API stores and returns UTC timestamps.
- Frontend displays timestamps in browser local timezone.

Practical implementation in this project:
- Oracle DB runs with `DBTIMEZONE = +00:00` (UTC); this is intentional.
- Admin date input (`dd.mm.yyyy hh:mm`) is interpreted as browser-local time.
- Before sending to API, admin UI converts local input to UTC ISO string (`YYYY-MM-DDTHH:MI:SSZ`).
- ORDS date handler for `/admin/competitions/dates` parses the incoming ISO datetime and stores UTC `timestamp` into `competitions.starts_at` / `competitions.ends_at`.
- FastAPI normalizes ORDS datetime fields by appending `Z` for UTC-like values (keys such as `starts_at`, `ends_at`, `submitted_at`, `created_at`, `updated_at`, `expires_at`, etc.), so frontend parsing is unambiguous.
- Frontend date formatting functions parse API timestamps as UTC and render them in local browser time.
- For soft-delete interval rows where `start_date`/`end_date` are used (for example `competition_participant_map_layers`), timestamps are not truncated to day boundary during writes; time-of-day is preserved.

Comparison rule:
- Any competition-window checks must compare against UTC "now" on server side.
- In package code this is done via:
  `cast((systimestamp at time zone 'UTC') as timestamp)`
  and compared with `starts_at` / `ends_at`.

Why this model:
- Avoids DST ambiguity and duplicate local times.
- Keeps server-side business logic deterministic.
- Allows every user to see times in their own timezone automatically.

## Data visibility rule (soft delete)

Architecture rule for all ORDS endpoints:
- ORDS responses must never return soft-deleted rows.
- Filtering is done in DB/package SQL (`end_date is null or end_date > sysdate`) for soft-deletable tables, not in frontend/backend UI code.
- `submissions` does not use soft delete (`start_date`/`end_date` removed), so no active-row filter applies there.
- If a future UI needs deleted rows, create a separate dedicated ORDS endpoint for that use case.

## Planned Data Model (after current changes)

### Core identity and roles
- `users`
  - `user_id` PK
  - `email` nullable
  - `full_name` nullable
  - `google_sub` nullable
  - `auth_type` not null, check in `('ANON','GOOGLE')`
  - soft-delete/audit: `start_date`, `end_date`, `created_by`, `updated_by`, `created_at`, `updated_at`
- `roles`
  - `role_id` PK, `role_code` unique, `role_name`
  - soft-delete columns: `start_date`, `end_date`
- `user_roles`
  - `user_role_id` PK
  - FK: `user_id -> users`, `role_id -> roles`, `assigned_by -> users`
  - soft-delete columns: `start_date`, `end_date`, `assigned_at`

### Competitions and access
- `competitions`
  - `competition_id` PK
  - `name`, `description`, `status`
  - location flags: `use_location`, `show_competitor_location`, `radius_m`
  - schedule: `starts_at`, `ends_at`
  - soft-delete/audit columns
- `competition_access_codes`
  - `access_code_id` PK
  - FK: `competition_id -> competitions`, `created_by -> users`
  - `code` globally unique
  - `code_type` in `('COMPETITOR','ORGANIZER')`
  - `status`, `expires_at`, `max_uses`, `used_count`
  - soft-delete columns
- `competition_organizers`
  - `competition_organizer_id` PK
  - FK: `competition_id -> competitions`, `user_id -> users`, `assigned_by -> users`
  - soft-delete columns

### Competition terms (competition-specific, multilingual)
- `competition_terms`
  - `terms_id` PK
  - FK: `competition_id -> competitions`, `created_by/updated_by -> users`
  - `version_no` (> 0), `status` in `('ACTIVE','INACTIVE')`
  - soft-delete/audit columns
- `competition_terms_texts`
  - `terms_text_id` PK
  - FK: `terms_id -> competition_terms`, `created_by/updated_by -> users`
  - `lang_code` validated by regex `^[a-z]{2}(-[A-Z]{2})?$`
  - `terms_text` CLOB
  - soft-delete/audit columns

### Competition participants
- `competition_participants`
  - `competition_participant_id` PK
  - FK: `competition_id -> competitions`, `user_id -> users`, `access_code_id -> competition_access_codes`, `terms_id -> competition_terms`
  - `alias_display` required, non-blank
  - `contact_email` nullable, regex-validated if present
  - `terms_lang_code` required (same lang regex), `terms_accepted_at` required
  - `status`, `joined_at`
  - soft-delete columns: `start_date`, `end_date`

### Competition content
- `checkpoints`
  - `checkpoint_id` PK, FK: `competition_id -> competitions`
  - `title`, optional `order_no`, optional location fields (`latitude`, `longitude`, `radius_m`)
  - `location_required` in `('Y','N')`
  - soft-delete/audit columns
- `questions`
  - `question_id` PK, FK: `checkpoint_id -> checkpoints`
  - `question_type` in `('TEXT','SINGLE_CHOICE')`
  - optional input constraints: `input_type` in `('TEXT','NUMERIC')`, `input_max_length`, `input_pattern`
  - `points`, `wrong_points`, `status`
  - soft-delete/audit columns
- `question_texts`
  - `question_text_id` PK, FK: `question_id -> questions`
  - `lang_code`, `question_text`
  - soft-delete/audit columns
- `question_options`
  - `option_id` PK, FK: `question_id -> questions`
  - `option_code`, `order_no`, `is_correct` in `('Y','N')`
  - soft-delete/audit columns
- `question_option_texts`
  - `question_option_text_id` PK, FK: `option_id -> question_options`
  - `lang_code`, `option_text`
  - soft-delete/audit columns
- `question_answers`
  - `answer_id` PK, FK: `question_id -> questions`
  - `answer_value`, `is_correct` in `('Y','N')`
  - `normalize_mode` in `('EXACT','TRIM_UPPER','LOWER_TRIM','NUMERIC')`
  - soft-delete/audit columns
- `translations`
  - `translation_id` PK
  - `translation_key`, `lang_code`, `text_value`
  - `lang_code` regex `^[a-z]{2}(-[A-Z]{2})?$`
  - soft-delete/audit columns

### Runtime/result data
- `submissions`
  - `submission_id` PK
  - FK: `competition_id -> competitions`, `checkpoint_id -> checkpoints`, `question_id -> questions`, `user_id -> users`, `selected_option_id -> question_options`, `evaluated_by -> users`
  - answer fields: `answer_text` CLOB, `selected_option_id`
  - scoring fields: `awarded_points`, `is_correct`
  - timestamps: `submitted_at`, `evaluated_at`
  - no `start_date/end_date` soft-delete columns
- `materials`
  - `material_id` PK
  - optional FK owner: `competition_id` and/or `checkpoint_id`
  - `title`, `material_type`, `uri`, `visibility`
  - soft-delete/audit columns
- `audit_log`
  - `audit_id` PK
  - `entity_type`, `entity_id`, `action_type`
  - FK: `changed_by -> users`
  - `changed_at`, `old_data_json`, `new_data_json`

### Key uniqueness indexes
- `ux_users_email` on `lower(email)`
- `ux_users_google_sub` on `google_sub`
- `ux_roles_code` on `role_code`
- `ux_competition_access_code_global` on `competition_access_codes(code)` (added by migration 11)
- Active-record unique indexes (`end_date is null`) for:
  - access codes by `code`
  - organizers by `(competition_id, user_id)`
  - participants by `user_id` (one active competition at a time)
  - participants by `(competition_id, user_id)`
  - participants alias by `(competition_id, nlssort(trim(alias_display), 'NLS_SORT=BINARY_CI'))`
  - terms versions by `(competition_id, version_no)`
  - terms text language by `(terms_id, lower(lang_code))`
  - checkpoint `order_no` per competition (only when `order_no` is not null)
  - question/question-option language and option uniqueness indexes
