# FastAPI <-> ORDS integration notes

FastAPI expects these ORDS endpoints under `{ORDS_BASE_URL}`:
- POST `/auth/google/upsert` - loob/uuendab Google kasutaja kirje ja tagastab `user_id`.
- POST `/auth/dev/resolve-user` (dev-only login helper) - leiab või loob dev-kasutaja (`user_id`/`email`) testlogini jaoks.
- GET `/auth/has-role?user_id=...&role_code=...` - kontrollib, kas kasutajal on nõutud roll (nt superadmin).
- GET `/auth/user-profile?user_id=...` - tagastab kasutaja profiiliandmed (`email`, `full_name`) sessiooni rikastamiseks.
- POST `/competitions/register` - registreerib kasutaja võistlusele osalejana ligipääsukoodi alusel.
- POST `/organizers/register` - registreerib kasutaja võistluse korraldajaks korraldaja koodi alusel.
- POST `/submissions` - salvestab vastuse, hindab selle ja tagastab punktitulemuse koos competitor popupi jaoks vajalike lisaväljadega (õiged vastused, koguaeg, hetke koht ja tingimuslikult kumulatiivne linnulennuline vahemaa).
- POST `/competitor/join-preview` - valideerib liitumiskoodi ja tagastab liitumise eelvaate (võistlus + tingimused).
- POST `/competitor/join-complete` - lõpetab liitumise, seob kasutaja osalusega ja salvestab tingimuste nõustumise.
- GET `/competitor/competitions?user_id=...` - toob kasutaja aktiivsed/sobivad osalusega võistlused.
- GET `/competitor/open-checkpoints?competition_id=...&user_id=...` - tagastab küsimuste avamiseks lubatud KP-d (lõplik serveripoolne otsus).
- GET `/competitor/map-checkpoints?competition_id=...&user_id=...` - tagastab kaardivaate KP andmed (asukohad, staatused, answered lipud ja asukohanõudega KP-de efektiivse vastamisraadiuse).
- GET `/competitor/progress?competition_id=...&user_id=...` - tagastab osaleja progressi kokkuvõtte (KP-de arv, vastatud, skoor).
- GET `/competitor/my-submissions?competition_id=...&user_id=...` - toob osaleja enda vastuste loendi.
- GET `/competitor/my-submission-detail?competition_id=...&submission_id=...&lang_code=...&user_id=...` - toob osaleja ühe vastuse detailvaate.
- GET `/competitor/session-by-participant?user_id=...&competition_participant_id=...` - valideerib osalus-sessiooni ja tagastab aktiivse osaluse andmed.
- GET `/competitor/terms?competition_id=...&user_id=...&lang_code=...` - tagastab võistluse osalustingimused valitud keeles.
- GET `/results/score?competition_id=...&user_id=...` - tagastab kasutaja skoori võistluses.
- GET `/organizer/leaderboard?competition_id=...` - tagastab korraldaja leaderboardi (punktid, tempo, distants jms).
- GET `/organizer/checkpoint-results?competition_id=...` - tagastab KP-põhise koondstatistika korraldajale.
- GET `/organizer/checkpoint-responders?competition_id=...&checkpoint_id=...` - tagastab konkreetsele KP-le vastanud osalejad.
- GET `/organizer/participant-submissions?competition_id=...&user_id=...` - tagastab valitud osaleja vastuste ajajoone + koondnäitajad.
- GET `/organizer/submission-detail?competition_id=...&user_id=...&submission_id=...` - tagastab korraldajale ühe vastuse detaili.
- GET `/i18n/translations?lang=...&default_lang=...` - tagastab UI tõlked valitud keele jaoks.
- GET `/admin/competitions?user_id=...` - tagastab admini hallatavate võistluste loendi.
- GET `/admin/competition-overview?competition_id=...` - tagastab valitud võistluse admin ülevaateandmed.
- GET `/admin/questions-overview?competition_id=...` - tagastab küsimuste/KP-de ülevaate admin halduses.
- GET `/admin/checkpoints?competition_id=...` - tagastab valitud võistluse KP-de loendi.
- GET `/admin/competitions/map-layers?competition_id=...` - tagastab võistlusele lubatud kaardikihtide sidumise.
- GET `/admin/competitions/overlay?competition_id=...` - tagastab võistluse aktiivse oma kaardi metadata, kui see on olemas.
- GET `/admin/competitions/overlays/pending-processing` - tagastab aktiivsed oma kaardid, mille töötlus tuleb käivitada või taastada.
- GET `/admin/competitions/terms?competition_id=...&lang_code=...` - tagastab adminile tingimuste teksti redigeerimiseks.
- POST `/admin/checkpoints` - loob uue kontrollpunkti.
- POST `/admin/checkpoints/update` - uuendab kontrollpunkti andmeid.
- POST `/admin/checkpoints/delete` - teeb kontrollpunkti soft-delete.
- POST `/admin/questions` - loob uue küsimuse kontrollpunkti alla.
- POST `/admin/questions/update` - uuendab küsimust ja seotud valikuid/vastuseid.
- POST `/admin/questions/delete` - teeb küsimuse soft-delete.
- POST `/admin/question-options` - lisab valikvastuse küsimusele.
- POST `/admin/question-answers` - lisab tekstvastuse/õige vastuse reegli küsimusele.
- POST `/admin/access-codes` - loob või uuendab ligipääsukoodi.
- POST `/admin/competitions/map-layers` - salvestab võistluse aktiivsed kaardikihid.
- POST `/admin/competitions/overlay` - salvestab või asendab võistluse aktiivse oma kaardi metadata.
- POST `/admin/competitions/overlay/processing` - uuendab oma kaardi töötluse staatust ja tile metadata't.
- POST `/admin/competitions/overlay/delete` - teeb võistluse oma kaardi soft-delete.
- POST `/admin/competitions/dates` - uuendab võistluse algus/lõpp kuupäevi.
- POST `/admin/competitions/meta` - uuendab võistluse metaandmeid (nimi, tüüp, staatus, location lipud jne).
- POST `/admin/competitions/terms` - salvestab võistluse tingimuste teksti.
- GET `/superadmin/competitions` - tagastab kõik võistlused superadmin vaates.
- GET `/superadmin/translations` - tagastab tõlgete halduse andmed (filtrid + kirjed).
- POST `/superadmin/competitions` - loob uue võistluse superadmini kaudu.
- POST `/superadmin/competitions/copy` - kopeerib olemasoleva võistluse seadistused/sisu.
- POST `/superadmin/organizers/remove` - eemaldab kasutaja korraldaja rollist valitud võistlusel.
- POST `/superadmin/translations/upsert` - lisab/uuendab tõlkekirje.
- POST `/superadmin/translations/delete` - teeb tõlkekirje soft-delete.

Expected ORDS JSON responses:
- `auth/google/upsert` -> `{ "user_id": 123 }`
- `auth/dev/resolve-user` -> `{ "user_id": 123 }`
- `auth/has-role` -> `{ "has_role":"Y|N" }`
- `auth/user-profile` -> `{ "email":"...", "full_name":"..." }`
- `competitions/register` -> `{ "competition_id": 456 }`
- `organizers/register` -> `{ "competition_id": 456 }`
- `submissions` -> `{ "submission_id": 789, "is_correct": "Y|N", "awarded_points": 0, "total_score": 42, "correct_answer_texts": ["..."], "other_correct_answer_texts": ["..."], "total_elapsed_seconds": 2975, "total_distance_m": 2460, "distance_display_allowed": "Y|N", "current_rank": 2 }`
  - request may include `lang_code`; backend forwards it to ORDS so localized correct-answer texts can be returned for `SINGLE_CHOICE` questions.
  - `correct_answer_texts` contains every correct answer shown to the competitor after submit.
  - `other_correct_answer_texts` contains the remaining correct answers when the competitor answered correctly and more than one correct answer exists.
  - `total_elapsed_seconds` is the competitor total elapsed time on that competition from the first submission until the just-saved submission.
  - `current_rank` is the competitor rank immediately after the just-saved submission using the same ordering rule as results/leaderboard.
  - `distance_display_allowed = Y` only when the just-saved submission row itself contains `submissions.latitude` and `submissions.longitude` and the competition distance logic has at least two usable geo points; otherwise competitor UI must not show the distance line for that popup.
  - when `distance_display_allowed = Y`, `total_distance_m` is the cumulative as-the-crow-flies distance using the same DB-side calculation as organizer results.
- `competitor/join-preview` -> `{ "competition_id": 1, "competition_name":"...", "already_active_for_user":"Y|N", "terms": {...} }`
- `competitor/join-complete` -> `{ "user_id":123, "competition_participant_id":456, "competition_id":1, "switched_from_participant_id":null, "no_change":"Y|N" }`
- `competitor/competitions` -> `{ "items": [{ "competition_id": 1, "name": "...", "type": "R|S" }] }`
- `competitor/open-checkpoints` -> `{ "items": [...] }`
- `competitor/map-checkpoints` -> `{ "items": [...] }`
  - asukohanõudega KP (`location_required = Y`) `radius_m` on efektiivne vastamisraadius:
    - `checkpoints.radius_m`, kui see on määratud;
    - muidu `competitions.radius_m`;
    - kui kumbki puudub, tagastatakse `0`.
- `competitor/progress` -> `{ "total_checkpoints": 10, "answered_checkpoints": 3, "score": 30 }`
- `competitor/my-submissions` -> `{ "items": [...] }`
- `competitor/my-submission-detail` -> `{ ... }`
- `competitor/session-by-participant` -> `{ "participant": {...} }`
  - participant may include `competition_type` (`R|S`) in addition to name/description/location flags.
- `competitor/terms` -> `{ "competition_id":1, "terms": {...} }`
- `results/score` -> `{ "score": 42 }`
- `organizer/leaderboard` -> `{ "access_granted":"Y|N", "items":[...] }`
- `organizer/checkpoint-results` -> `{ "access_granted":"Y|N", "items":[...] }`
- `organizer/checkpoint-responders` -> `{ "access_granted":"Y|N", "items":[...] }`
- `organizer/participant-submissions` -> `{ "access_granted":"Y|N", "items":[...], "total_elapsed_seconds":1234, "total_distance_m":2460, "distance_available":"Y|N" }`
- `organizer/submission-detail` -> `{ "access_granted":"Y|N", ... }`
- `i18n/translations` -> `{ "lang":"et","default_lang":"et","items":{"competitor.heading":"..."}}`
- `admin/competitions` -> `{ "items": [...] }`
- `admin/competition-overview` -> `{ ..., "type": "R|S" }`
- `admin/questions-overview` -> `{ "items": [...] }`
- `admin/checkpoints` -> `{ "items": [...] }`
- `admin/competitions/map-layers` -> `{ "items": [{"layer_code":"..."}] }`
- `admin/competitions/overlay` (GET) -> `{ "overlay_id":..., "display_name":"...", "processing_status":"UPLOADED|PROCESSING|READY|FAILED", "tile_min_zoom":..., "tile_max_zoom":..., "crs_code":"EPSG:3301", "bounds_3301":{...}, "width_px":..., "height_px":... }` või tühi objekt, kui aktiivne oma kaart puudub.
- `admin/competitions/overlay` (GET) tagastab overlay metadata admin UI jaoks; kui `processing_status != READY`, ei tohi frontend pakkuda seda kasutatava kaardina admin kaardivaadetes.
- `admin/competitions/terms` -> `{ "competition_id":1, "terms": {...} }`
- `admin/checkpoints` -> `{ "checkpoint_id": 123 }`
- `admin/questions` -> `{ "question_id": 456 }`
- `admin/question-options` -> `{ "option_id": 789 }`
- `admin/question-answers` -> `{ "answer_id": 321 }`
- `admin/access-codes` -> `{ "access_code_id": 654, "code": "123456" }`
- `admin/competitions/overlay` (POST) -> `{ "overlay_id":..., "display_name":"...", "processing_status":"UPLOADED|PROCESSING|READY|FAILED", "crs_code":"EPSG:3301", "bounds_3301":{...}, "width_px":..., "height_px":... }`
- `admin/competitions/overlay/processing` -> `{ "ok": true }` või tühi 200 JSON
- `admin/competitions/overlay/delete` -> `{ "ok": true }` või tühi 200 JSON
- `admin/*/update|delete|dates|meta|map-layers|terms` -> `{ "ok": true }` or empty 200 JSON
- `superadmin/competitions` -> `{ "items": [...] }` (GET) or `{ "competition_id":..., "organizer_code":"..." }` (POST/copy)
- `superadmin/translations` -> `{ "items": [...] }`
- `superadmin/organizers/remove` -> `{ "ok": true }` or empty 200 JSON
- `superadmin/translations/upsert|delete` -> `{ "ok": true }` or empty 200 JSON

Session cookie flow:
- `POST /api/auth/google` now sets an HttpOnly session cookie (`SESSION_COOKIE_NAME`, default `funo_session`).
- `POST /api/dev/login` sets competitor session cookie (`COMPETITOR_SESSION_COOKIE_NAME`, default `funo_competitor_session`) in dev mode (`APP_ENV=dev`).
- `POST /api/competitor/join-complete` sets both competitor cookies:
  - `COMPETITOR_SESSION_COOKIE_NAME` (signed session payload incl. user/participant)
  - `COMPETITOR_PARTICIPATION_COOKIE_NAME` (active participant id token)
- `GET /api/competitor/session` validates competitor cookies against ORDS (`competitor/session-by-participant`) and refreshes cookie TTL.
- `POST /api/auth/logout` currently clears only `SESSION_COOKIE_NAME` (Google/admin session).
- Protected admin/superadmin endpoints resolve user from `SESSION_COOKIE_NAME`; competitor endpoints resolve user from competitor cookies.
- `user_id` in payload and `x-user-id` header are optional guards; if sent, they must match session user.

Required backend env:
- `ORDS_BASE_URL`
- `SESSION_SECRET` (required for cookie signing)
- Optional: `SESSION_COOKIE_NAME`, `COMPETITOR_SESSION_COOKIE_NAME`, `COMPETITOR_PARTICIPATION_COOKIE_NAME`, `COMPETITOR_PARTICIPATION_COOKIE_TTL_HOURS`, `SESSION_COOKIE_SECURE`, `ORDS_USERNAME`, `ORDS_PASSWORD`, `GOOGLE_CLIENT_ID`, `APP_ENV`, `PROMO100_MAX_TOTAL_COMPETITIONS`
- Optional overlay config: `OVERLAY_STORAGE_DIR`, `OVERLAY_MAX_UPLOAD_BYTES`, `OVERLAY_MAX_DIMENSION_PX`, `OVERLAY_TILE_MIN_ZOOM`, `OVERLAY_TILE_MAX_ZOOM`
- Optional overlay config: `OVERLAY_STORAGE_DIR`, `OVERLAY_MAX_UPLOAD_BYTES`, `OVERLAY_MAX_DIMENSION_PX`, `OVERLAY_TILE_MIN_ZOOM`, `OVERLAY_TILE_MAX_ZOOM`, `OVERLAY_TILE_TOKEN_TTL_SECONDS`
- Overlay upload voog salvestab source-failid `OVERLAY_STORAGE_DIR` alla ning käivitab taustatöö, mis lõikab rasteri tile'ideks ja uuendab staatust `UPLOADED -> PROCESSING -> READY|FAILED`.
- Backend startup proovib uuesti käivitada aktiivsed overlay'd, mille staatus on jäänud `UPLOADED` või `PROCESSING`.
- Optional magnetic declination config: `DECLINATION_SERVICE_URL_TEMPLATE`, `DECLINATION_REFRESH_DAYS`
- Optional map-provider keys: `MAPYCZ_API_KEY`, `MAPTILER_API_KEY`, `MML_API_KEY`
- Optional i18n config: `LANG_AVAILABLE` (for example `et,en`), `LANG_DEFAULT` (for example `et`)
- FastAPI loads i18n translations to in-memory cache on startup for every `LANG_AVAILABLE` language.
- You can reload i18n cache without restarting backend: `POST /api/i18n/reload`
- Results visibility rule: requester must be active organizer of the competition at request time.
  - If authorized and no data exists, API returns empty `items` and `access_granted = Y`.
  - If unauthorized (or inaccessible competition), API returns neutral empty payload with `access_granted = N`.

Map layer config (admin "Näita kaardil"):
- File: `backend/app/map_layers.json`
- Endpoint: `GET /api/map-layers`
- Config is cached in backend memory (`MAP_LAYERS_CACHE_TTL_SECONDS`, currently 31536000s / 1 year).
- If a layer has `"enabled": false`, it is hidden from UI.
- If a layer URL contains `{MAPYCZ_API_KEY}`, `{MAPTILER_API_KEY}` or `{MML_API_KEY}`, the backend injects
  the matching key from `.env`.
  If key is missing, that layer is automatically omitted from API response.
- Demo-stage note: `map_layers.json` may intentionally contain both well-verified layers and experimental
  third-party candidates so that real devices can be used to compare coverage, speed and rendering quality.
  In this stage, admin and competitor UIs may therefore expose layers whose upstream stability or licensing
  still needs practical validation.
- Supported layer types:
  - `layer_type: "xyz"` (default) -> Leaflet `L.tileLayer(...)`
  - `layer_type: "wms"` -> Leaflet `L.tileLayer.wms(...)` with optional
    `wms_layers`, `wms_format`, `wms_transparent`, `wms_version`
  - `layer_type: "wmts"` -> custom Leaflet tile layer with optional
    `wmts_matrix_set`, `wmts_zoom_offset`, `tile_size`
  - `layer_type: "wmts_fallback"` -> admin-side composite WMTS layer that switches from the primary
    WMTS source to a fallback WMTS source after `fallback_zoom_threshold`
- Optional CRS override per layer: `crs` (for example `EPSG:3301`).
- Current optional providers:
  - `mapycz_outdoor` (Mapy.cz Outdoor)
  - `maptiler_outdoor` (MapTiler Outdoor)
  - `maptiler_topo_v2` (MapTiler Topo)
  - `maptiler_hybrid` (MapTiler Hybrid)
  - `finland_mml_maastokartta` (Finland MML Maastokartta, requires `MML_API_KEY`)
  - `finland_mml_ortokuva` (Finland MML Ortoilmakuva, requires `MML_API_KEY`)
  - `finland_mml_taustakartta` (Finland MML Taustakartta, requires `MML_API_KEY`)
  - `norway_kartverket_topo` (Norway Kartverket topo cache, WebMercator WMTS path)
  - `france_ign_planign` (France IGN Plan IGN via G\u00e9oplateforme WMTS)
  - `france_ign_orthophoto` (France IGN orthophoto via G\u00e9oplateforme WMTS)
  - `latvia_geolatvija_fallback` (Latvia GeoLatvija fallback: `Topo250` low zoom, `ortofoto_kombi` high zoom)
  - `opentopomap` (OpenTopoMap fallback topo layer)
  - `austria_basemap_standard` (Austria basemap.at Standard)
  - `austria_basemap_orthofoto` (Austria basemap.at Orthofoto)
- Currently disabled until a separate validation or access step is completed:
  - `latvia_tapis_background`
    because `tapis.gov.lv/tapis/services/wms` did not expose a working public base-map WMS in practice
    and the official GeoLatvija client uses Latvia topo/ortho through `https://geolatvija.lv/geoserver`
    WMTS layers on `EPSG:3059`, so the old TAPIS/WMS guess was left disabled after the 3059 path replaced it
  - `latvia_geolatvija_topo250`, `latvia_geolatvija_ortho`
    because they were replaced by the temporary composite fallback layer to avoid gray tiles when `Topo250`
    runs out of supported WMTS matrix levels
  - `baltics_openmap_topo`
    because it is a community candidate and was not kept as a default visible layer after validation
  - `lithuania_standard`
    because the candidate standard layer did not match the app's current CRS assumptions
  - `lithuania_ort10lt`
    because it rendered as a gray background in practical testing and was not compatible with the current
    Leaflet/slippy-tile assumptions
  - `austria_basemap_shading`
    because it is better treated as an overlay than as a standalone base map in the current UI
- Latvia note: GeoLatvija runtime config points to `https://geolatvija.lv/geoserver` and the public client
  uses `EPSG:3059` WMTS layers such as `Topo250` and `ortofoto_kombi`. The current admin map now has
  targeted `EPSG:3059` support plus a temporary fallback layer that shows `Topo250` only on the low zoom
  levels where it really exists and switches to `ortofoto_kombi` deeper in. Deeper Latvia topo variants
  (`Topo50_v2`, `Topo10v3`) still depend on upstream LGIA/GeoLatvija service health.
- Not yet configured: Retkikartta was discussed as a potential Finland WMS overlay, but it is not in
  `map_layers.json` yet because a concrete public layer identifier / WMS parameter set was not locked down.
- South Tyrol note: public provincial documentation still points to a legacy BaseMap WMTS path and the current public
  `https://geoservices9.civis.bz.it/geoserver` preview exposes concrete `p_bz-BasemapImagery:TopographicMap-*`
  layers, but practical validation showed that the tested public South Tyrol candidates are technically reachable yet
  visually poor grayscale/legacy maps. They were therefore removed from `map_layers.json` instead of being kept as
  visible demo layers. A clearly usable public HTTPS South Tyrol color basemap or orthophoto layer contract has not
  been confirmed yet from the same official sources.

Competition-specific own map overlay in competitor UI:
- `GET /api/competitor/map-layers?competition_id=...` may add a dynamic map-layer entry when all of these are true:
  - participant map-layers include `maaamet_pohikaart_overlay`;
  - active competition overlay exists and `processing_status = READY`;
  - global base layer `maaamet_pohikaart` is enabled in `map_layers.json`.
- The dynamic competitor-visible layer is returned as:
  - `code = "maaamet_pohikaart_overlay"`
  - `label = "* <display_name>"`
  - `overlay_composite_base_code = "maaamet_pohikaart"`
  - `overlay_tile_url_template = "/api/competitor/competitions/overlay/tiles/{overlay_id}/{z}/{x}/{y}.png?token=..."`
- The dynamic layer is not a separate global base map; competitor frontend must render it as a composite:
  - base map = `maaamet_pohikaart`
  - overlay = competition-specific tile layer
- Competitor frontend must treat this overlay as a plain map layer on top of EPK:
  - overlay visibility must not depend on GPS availability, current user location or follow mode;
  - follow mode may change only map center movement;
  - user location marker may change only user-location rendering.
- If participant layer selection contains `maaamet_pohikaart_overlay`, backend treats `maaamet_pohikaart` as its technical prerequisite.
- Overlay tile media is served by FastAPI endpoint:
  - `GET /api/competitor/competitions/overlay/tiles/{overlay_id}/{z}/{x}/{y}.png?token=...`
- If current map view is outside the overlay coverage, only the base layer remains visible in that area because matching overlay tiles do not exist there.

Magnetic declination flow:
- `competition_declinations` stores one current declination row per competition.
- The backend schedules an asynchronous refresh after competition meta/date changes and checkpoint create/update/delete events when the competition is active and uses location.
- The refresh center is the arithmetic mean of all checkpoint coordinates with latitude/longitude.
- If stored declination is missing or the stored timestamp is older than `DECLINATION_REFRESH_DAYS`, FastAPI queries the configured BGS WMM JSON service using `DECLINATION_SERVICE_URL_TEMPLATE`.
- The service response is expected to expose `geomagnetic-field-model-result.field-value.declination.value` in degrees east-positive.
- On success, the new declination and timestamp are written back to ORDS, and both `/api/admin/competition-overview` and `/api/competitor/map-checkpoints` expose `declination` plus `declination_last_updated`.
- Frontend compass logic uses `true_heading = magnetic_heading + declination`.

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
- ORA-20067 -> INVALID_CHECKPOINT_ORDER
- ORA-00001 on `UX_SUBMISSIONS_COMP_USER_CP_Q` -> DUPLICATE_SUBMISSION
- ORA-20010 -> INVALID_GOOGLE_PROFILE

I18n cache reload:
- Endpoint: `POST /api/i18n/reload`
- Example:
  `curl -sS -X POST "http://localhost:8080/api/i18n/reload"`

Superadmin translations management:
- `GET /api/superadmin/translations?prefix=competitor.&lang=et&include_deleted=N`
- `POST /api/superadmin/translations/upsert`
  - body: `{ "translation_key": "...", "lang_code": "et", "text_value": "..." }`
- `POST /api/superadmin/translations/delete` (soft-delete)
  - body: `{ "translation_key": "...", "lang_code": "et" }`
- These endpoints only write to database (no automatic i18n cache reload).
- After completing translation edits, run `POST /api/i18n/reload` to apply changes to runtime cache.

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
  - `name`, `description`, `type` (`R|S`), `status`
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

Access code generation rule:
- Global uniqueness is enforced in DB (`competition_access_codes.code` + package-level uniqueness check).
- Normal "ensure code exists" flow keeps the existing active code unchanged.
- Explicit admin regeneration flow is separate and must request a new code intentionally; the new code is generated in DB and returned via `POST /admin/access-codes`.
- `competition_organizers`
  - `competition_organizer_id` PK
  - FK: `competition_id -> competitions`, `user_id -> users`, `assigned_by -> users`
  - soft-delete columns
- `competition_declinations`
  - `competition_id` PK, FK: `competition_id -> competitions`
  - `declination` signed degrees east-positive
  - `last_updated` timestamp of the latest successful refresh

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
  - `title`, `checkpoint_type` (`NORMAL|START|FINISH`; `NULL` handled as `NORMAL`), optional `order_no`, optional location fields (`latitude`, `longitude`, `radius_m`)
  - `location_required` in `('Y','N')`
  - invariant: `1 checkpoint = 1 active question`
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
  - unique business key: `(competition_id, user_id, checkpoint_id, question_id)`
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
- `ux_submissions_comp_user_cp_q` on `submissions(competition_id, user_id, checkpoint_id, question_id)` (added by migration 24)
- Active-record unique indexes (`end_date is null`) for:
  - access codes by `code`
  - organizers by `(competition_id, user_id)`
  - participants by `user_id` (one active competition at a time)
  - participants by `(competition_id, user_id)`
  - participants alias by `(competition_id, nlssort(trim(alias_display), 'NLS_SORT=BINARY_CI'))`
  - terms versions by `(competition_id, version_no)`
  - terms text language by `(terms_id, lower(lang_code))`

## Competition Terms Runtime Flow (Admin + Competitor)

- Admin API endpoints:
  - `GET /api/admin/competitions/terms?competition_id=...&lang_code=...`
  - `POST /api/admin/competitions/terms`
- ORDS routes used by backend:
  - `GET /admin/competitions/terms`
  - `POST /admin/competitions/terms`

Default terms source:
- Backend reads default HTML files from `CONTENT_DEFAULTS_DIR`.
- Expected files: `default_et.html`, `default_en.html`, ... (by `LANG_AVAILABLE`).
- `CONTENT_DEFAULTS_DIR` must be readable inside `fastapi` container.
- In this project, docker-compose mounts:
  - `./frontend_dist -> /app/frontend_dist` (read-only)
  - therefore `CONTENT_DEFAULTS_DIR=/app/frontend_dist/content`

Fallback behavior:
- On admin terms load, if requested language terms are missing, backend loads default file for that language and creates terms via ORDS POST.
- If the file does not exist or is empty, backend does not synthesize any HTML fallback and returns empty terms content.
- This is language-specific file-based fallback (for example `et` and `en` handled independently).
- Admin terms modal preloads all `LANG_AVAILABLE` languages in background, so language switch is immediately editable without changing admin UI language.

Caching:
- Competitor terms endpoint uses server-side in-memory cache:
  - key: `competition_id|lang_code`
  - cache store: `competitor_terms_cache`
- Cache invalidation:
  - `POST /api/admin/competitions/terms` clears competitor terms cache immediately.
  - Manual reset endpoint exists: `POST /api/competitor/terms-cache/reset`
- Competitor UI requests terms on each modal open; backend cache still prevents excessive ORDS load.

Important Oracle JSON note:
- Terms text is CLOB and can exceed 4000 chars.
- JSON responses that include terms text must use `JSON_OBJECT ... RETURNING CLOB` in PL/SQL.
- Without this, ORDS can fail with:
  - `ORA-40478: output value too large (maximum: 4000)`
  - checkpoint `order_no` per competition (only when `order_no` is not null)
  - question/question-option language and option uniqueness indexes


## Server-side caching (authoritative)

This section reflects current behavior in `backend/app/main.py`.

### 1) `i18n_cache`
- Purpose: translations cache for `/api/i18n/translations`.
- Key: language code.
- TTL: no time-based TTL (lives in memory until reload/restart).
- Filled: backend startup.
- Invalidated/reset:
  - `POST /api/i18n/reload` loads a fresh cache snapshot and swaps it in only after all configured languages load successfully.
  - Process restart clears + reloads.

### Multilingual fallback rules (all views)

- UI texts (buttons, headings, static labels):
  1. selected language
  2. `.env` `LANG_DEFAULT`
  3. translation key string

- Data-driven content texts (for example question text and option text):
  1. selected language
  2. `.env` `LANG_DEFAULT`
  3. `---` (must not throw UI error)

Scope:
- Apply this exact fallback order in all multilingual views:
  - `index.html` (competitor)
  - `admin.html`
  - `superadmin.html`
  - `results.html`

### Admin SINGLE_CHOICE option update rules

When updating question options (`replace_question_options_et`), use diff-based updates by `option_code`:
- Existing option (same `option_code`): update `is_correct` and option texts only; do **not** renumber `order_no`.
- New option (new `option_code`): insert with `order_no = max(active order_no) + 1`.
- Missing option (not present in incoming payload): soft-delete option texts and option row.

### Admin multilingual question edit limitation

Current admin question edit flow treats empty non-default-language texts as "no update", not as an explicit delete:
- If `admin-main.js` sends an update for the default language, `question_text` must always be present.
- If a non-default-language question text is cleared in the UI, the frontend currently skips that language update instead of deleting the existing translation row.
- The same practical limitation applies to non-default-language SINGLE_CHOICE option texts in the current admin flow: clearing the field in the UI does not remove an already existing translation in the database.

This is intentional for now to avoid `api.error.invalid_submission` on empty translated question text updates. Explicit deletion of existing non-default-language texts needs a separate end-to-end design and implementation.

Important:
- Keep all changes in one transaction (single commit).
- Do not compact `order_no` gaps after delete (for example `1,2,4,5` is valid).
- This avoids transient unique-index conflicts on active `(question_id, order_no)` during delete/update flows.

### 2) `map_layers_cache`
- Purpose: parsed `backend/app/map_layers.json` (+ API key substitution).
- Key: single global cache object (`items`, `loaded_at`).
- TTL: `MAP_LAYERS_CACHE_TTL_SECONDS = 31536000` (1 year).
- Filled: lazy, first call to `/api/map-layers` or `/api/competitor/map-layers`.
- Invalidated/reset:
  - no dedicated reset endpoint.
  - expires by TTL or process restart.

### 3) `competitor_map_layers_cache`
- Purpose: competition-specific map layer set for competitor.
- Key: `competition_id`.
- TTL: no time-based TTL.
- Filled: first call to `GET /api/competitor/map-layers`.
- Invalidated/reset:
  - `_invalidate_competition_cache(competition_id)` removes entry.
  - `POST /api/admin/competitions/map-layers` removes entry for that competition.
  - process restart clears all.

### 4) `map_checkpoints_cache`
- Purpose: cached payload for `GET /api/competitor/map-checkpoints`.
- Key: `competition_id:user_id`.
- TTL: `MAP_CHECKPOINTS_CACHE_TTL_SECONDS = 900` (15 min).
- Filled: first request per key.
- Additive payload fields (backward-compatible):
  - `checkpoint_order_no`
  - `checkpoint_type`
  - `competition_type` (`R|S`)
  - `checkpoint_map_label` (competitor map tooltip text preformatted for the current competition type)
- `checkpoint_map_label` formatting:
  - applies only to `NORMAL` checkpoints; `START`/`FINISH` stay symbol-only on map.
  - `R` type:
    - if `checkpoint_title` length is `<= 8`, use full title;
    - if length is `> 8`, use first 5 characters + `...`.
  - `S` type:
    - format is `order_no - title`;
    - title part is truncated to maximum 5 characters;
    - no ellipsis is added in `S` type.
- Invalidated/reset:
  - user+competition scoped invalidation after successful `POST /api/submissions`.
  - automatic expiry purge on reads.
  - full clear on admin content mutations (checkpoint/question/option/answer create-update-delete).
  - competition-scoped clear via `_invalidate_competition_cache(...)` on competition meta/date updates and some competition-level mutations.
  - process restart clears all.

### 5) `open_checkpoints_last_response`
- Purpose: short throttle cache for `GET /api/competitor/open-checkpoints`.
- Key: `competition_id:user_id`.
- TTL: `OPEN_CHECKPOINTS_THROTTLE_SECONDS = 2`.
- Reuse condition: cached response is reused only when request geo signature matches
  (`latitude|longitude|radius_m` normalized to a stable signature).
- Filled: each successful response.
- Additive payload fields may include:
  - `checkpoint_order_no`
  - `checkpoint_type`
  - `competition_type` (`R|S`)
- Invalidated/reset:
  - naturally overwritten by next response.
  - cleared together with map checkpoint cache on admin content mutations.
  - competition-scoped clear via `_invalidate_competition_cache(...)`.
  - process restart clears all.

### 5a) `POST /api/competitor/checkpoint-access` behavior
- Purpose: pre-validate map checkpoint availability with FastAPI-side filtering.
- Input: `competition_id`, `checkpoint_ids[]`, optional `latitude/longitude/radius_m`.
- Data source:
  - uses `map_checkpoints_cache` (same `competition_id:user_id` cache as map view) for checkpoint metadata and `is_answered` hint.
  - if needed, performs final ORDS confirmation via `competitor/open-checkpoints`.
- Rules:
  - if `FINISH` is already answered -> `can_open=false, reason=finished`
  - if active `START` exists and is not answered yet -> only `START` may open, other map clicks return `reason=start_required`
  - if `competition_type='S'` -> only the next unanswered `NORMAL` checkpoint may open; after all normal checkpoints only `FINISH` may open (`reason=wrong_order` for others)
  - `location_required='N'` can be opened without geo gate.
  - `location_required='Y'` requires geo; far checkpoints are rejected in FastAPI precheck.
  - final "open/not open" decision for candidates comes from ORDS response.

Frontend event-driven refresh notes:
- After successful answer submit, UI updates the answered checkpoint status locally (`is_answered='Y'`) for visible map markers.
- After opening competitor results (`/api/competitor/my-submissions`), UI refreshes map checkpoints from `/api/competitor/map-checkpoints` to keep map answered flags aligned.

### 6) `competitor_terms_cache`
- Purpose: cached terms payload for `GET /api/competitor/terms`.
- Key: `competition_id|lang_code`.
- TTL: no time-based TTL.
- Filled: first terms request per competition/language.
- Invalidated/reset:
  - `POST /api/admin/competitions/terms` clears whole terms cache.
  - manual reset endpoint exists: `POST /api/competitor/terms-cache/reset`.
  - process restart clears all.

Strict UI i18n implementation rule (all views):
- Do not hardcode human-readable UI text in HTML/JS for buttons, headings, labels, dialogs, or messages.
- Use `tr("translation.key")` in JS (no second-argument fallback text).
- For HTML nodes with `data-i18n`, the element text must be the translation key string itself.
- Required pattern example:
  - Correct: `<h2 data-i18n="admin.login.heading">admin.login.heading</h2>`
  - Incorrect: `<h2 data-i18n="admin.login.heading">Admin sisselogimine</h2>`
  - Incorrect: `tr("admin.login.heading", "Admin sisselogimine")`
- Effective fallback chain for UI text is:
  1) selected language
  2) `.env LANG_DEFAULT`
  3) translation key string
- Do not replace or alter icon glyphs/entities while making i18n-only text changes.

Admin contextual info modals:
- Admin field-level help texts use translation keys derived from the existing label key:
  - title: `<label_key>.info_title`
  - body HTML: `<label_key>.info`
- Body HTML is sanitized in browser before render.
- Before sanitizing, admin UI also performs a lightweight structural check for unbalanced or misnested allowed tags.
- If that check fails, the bad HTML is contained to that single info modal body:
  - the page outside the modal must remain unaffected;
  - the modal shows a translated warning and escaped raw source text for easier translation repair.
- Current allowed tags:
  - `p`, `br`, `strong`, `em`, `b`, `i`, `ul`, `ol`, `li`, `span`, `code`
- Current allowed attributes:
  - `class`, `title`
- Do not rely on inline `style`; use shared `assets/app.css` classes instead when formatted emphasis or color is needed.

## Geolocation Distance Logic (checkpoint access + results distance)

This section documents how geographic distance is used in two separate backend flows:
- checkpoint availability ("is competitor close enough to open question?")
- results distance ("how many meters did competitor travel?")

### 1) Checkpoint proximity and question availability

Main API entrypoints:
- `POST /api/competitor/checkpoint-access`
- `GET /api/competitor/open-checkpoints`

FastAPI precheck (`/api/competitor/checkpoint-access`):
- reads checkpoint metadata from `map_checkpoints_cache` (or refreshes from ORDS if cache miss/expired);
- checks per checkpoint:
  - not found -> `can_open=false, reason=not_found`
  - already answered -> `can_open=false, reason=answered`
  - `location_required='N'` -> `can_open=true, reason=no_location_required`
  - missing user location for location-required checkpoint -> `can_open=false, reason=missing_location`
- for location-required checkpoints with coordinates/effective radius available:
  - computes distance with backend `_haversine_meters(lat1, lon1, lat2, lon2)`;
  - compares against effective radius from cached `competitor/map-checkpoints` item `radius_m`;
  - if outside radius -> reject immediately (`reason=too_far`) without ORDS roundtrip;
  - if inside radius -> mark as candidate (`needs_ords=true`).
- if a location-required checkpoint has no usable effective radius (`radius_m <= 0`), FastAPI rejects it locally (`reason=not_open`) and does not forward it to ORDS as a candidate.

Final authority:
- candidate checkpoint IDs are validated by ORDS `competitor/open-checkpoints`;
- FastAPI maps ORDS result to `can_open=true/false` (`reason=open|not_open`);
- this keeps database-side rule as final source of truth.

Competitor map popup flow:
- map popup open must not trigger an `open-checkpoints` bulk fetch just to decide whether to show the popup answer button.
- popup answer-button visibility is a FastAPI/client-side UI predecision based on cached `competitor/map-checkpoints` data plus the latest known user geolocation.
- user geolocation updates must not force content refresh for every closed popup; only currently open popup content should be refreshed on GPS movement.
- the authoritative “can this question really be opened now?” decision still happens only when the user presses the popup answer button and FastAPI calls the final ORDS-backed access flow for candidate checkpoints.

ORDS/PLSQL side:
- `open-checkpoints` logic uses spherical distance formula (`6371000 * 2 * asin(sqrt(...))`);
- location-required checkpoints are returned only when computed distance is within effective radius.
- if an active `START` exists and the participant has not yet answered it, only `START` is returned as open;
- if `competition.type='S'`, after `START` has been answered only the next unanswered `NORMAL` checkpoint in `order_no` order is returned as open;
- if `competition.type='S'` and all normal checkpoints are already answered, only `FINISH` may remain open;
- if `competition.type='R'`, after `START` has been answered the remaining unanswered checkpoints follow normal location rules in free order;
- if active `FINISH` has already been answered, no more checkpoints are returned as open;
- `START` and `FINISH` are answered through normal `submissions` flow and may award points like any other checkpoint;
- `submissions` enforces the same server-authoritative order rule and raises `ORA-20067` on invalid `S`-type checkpoint order.

### 2) Results distance (`total_distance_m`)

Where shown:
- organizer leaderboard (`/api/admin/leaderboard`)
- organizer participant submissions detail (`/api/admin/participant-submissions`)

Authority and calculation location:
- `total_distance_m` is computed in Oracle package/SQL (not in FastAPI);
- FastAPI only forwards returned value.

How distance is computed in DB:
- submission path is ordered by `submitted_at`, then `submission_id`;
- each submission point uses:
  - competitor submitted location (`submissions.latitude/longitude`) when available;
  - fallback to checkpoint location (`checkpoints.latitude/longitude`) when submission location is missing;
- segment distances between consecutive points are summed;
- formula is the same spherical/Haversine-style expression (`6371000 * 2 * asin(sqrt(...))`);
- result is rounded to meters (`round(sum(...))`).

Competitor submit-popup usage:
- `POST /api/submissions` may expose the same cumulative distance as `total_distance_m`, but only when the just-saved submission row itself contains submitted coordinates.
- If the just-saved submission has no `submissions.latitude/longitude`, competitor popup must hide the distance line even if older submissions would allow total path distance calculation.

Availability flag:
- `distance_available='Y'` only when at least two geo points exist in ordered path;
- otherwise distance is `null` and availability is `N`.

### 3) Performance and ORDS-load behavior

To reduce ORDS pressure (important in limited shared environments):
- `map_checkpoints_cache` (15 min TTL) avoids repeated checkpoint-metadata fetches;
- `open_checkpoints_last_response` (2 sec throttle by geo signature) coalesces bursts;
- FastAPI precheck drops obviously far checkpoints before ORDS call;
- ORDS retry/backoff (`ORDS_RETRY_ATTEMPTS`, `ORDS_RETRY_BACKOFF_SECONDS`) mitigates transient pool saturation.

### 4) Why two-stage decision exists

FastAPI precheck is an optimization and UX helper. ORDS/DB remains authoritative for final open/not-open decision to keep rule consistency across clients and avoid trusting only edge-device input.

## Results ordering rule (authoritative)

This ordering rule must stay identical in:
- organizer leaderboard / results view;
- competitor submit-popup `current_rank`;
- any other rank presentation added later.

Ordering:
- first by `score` descending (more points ranks higher);
- for equal score, by `total_elapsed_seconds` ascending (faster total time ranks higher);
- if both are still equal, implementation may use a stable deterministic fallback such as `user_id` to keep ordering reproducible, but that fallback must not change the displayed business rule above.
