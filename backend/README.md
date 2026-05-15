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
- Optional i18n config: `LANG_AVAILABLE` (for example `et,en`), `LANG_DEFAULT` (for example `et`)
- FastAPI loads i18n translations to in-memory cache on startup for every `LANG_AVAILABLE` language.
- You can reload i18n cache without restarting backend: `POST /api/i18n/reload`

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

## Data visibility rule (soft delete)

Architecture rule for all ORDS endpoints:
- ORDS responses must never return soft-deleted rows.
- Filtering is done in DB/package SQL (`end_date is null or end_date > sysdate`), not in frontend/backend UI code.
- If a future UI needs deleted rows, create a separate dedicated ORDS endpoint for that use case.
