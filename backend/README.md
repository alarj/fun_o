# FastAPI <-> ORDS integration notes

FastAPI expects these ORDS endpoints under `{ORDS_BASE_URL}`:
- POST `/auth/google/upsert`
- POST `/auth/dev/resolve-user` (dev-only login helper)
- POST `/competitions/register`
- POST `/submissions`
- GET `/results/score?competition_id=...&user_id=...`
- GET `/organizer/leaderboard?competition_id=...`

Expected ORDS JSON responses:
- `auth/google/upsert` -> `{ "user_id": 123 }`
- `competitions/register` -> `{ "competition_id": 456 }`
- `submissions` -> `{ "submission_id": 789 }`
- `results/score` -> `{ "score": 42 }`
- `organizer/leaderboard` -> standard ORDS query JSON (`items` array), for example:
  `{ "items": [{ "user_id": 1, "score": 100 }] }`

Session cookie flow:
- `POST /api/auth/google` now sets an HttpOnly session cookie (`SESSION_COOKIE_NAME`, default `funo_session`).
- `POST /api/dev/login` can set the same cookie in dev mode (`APP_ENV=dev`) without Google token.
- Protected endpoints resolve user from session cookie first.
- `user_id` in payload and `x-user-id` header are optional guards; if sent, they must match session user.

Required backend env:
- `ORDS_BASE_URL`
- `SESSION_SECRET` (required for cookie signing)
- Optional: `SESSION_COOKIE_NAME`, `SESSION_COOKIE_SECURE`, `ORDS_USERNAME`, `ORDS_PASSWORD`, `GOOGLE_CLIENT_ID`, `APP_ENV`

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

Database scripts added:
- ORDS handlers: `db/oracle/ords/07_ords_handlers.sql`
- App packages with active-record business checks: `db/oracle/api/05_api_packages_stub.sql`
