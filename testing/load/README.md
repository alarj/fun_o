# Load Testing

This load test emulates competitor behaviour as closely as practical to the current frontend flow.

## Important note about earlier test runs

After the first test iterations it became clear that logging and FastAPI response metadata had to be improved before the system's real behaviour could be identified narrowly and reliably.

Because of that, the early runs are not treated as architectural comparison material anymore.

The following observability improvements were added after those early runs:
- backend log level is now configurable from `.env` via `LOG_LEVEL`
- typical usage:
  - `ERROR` for minimal production error visibility
  - `INFO` for normal operational logging
  - `DEBUG` for load testing and branch-level tracing
- `DEBUG` is intended to expose application branch traces only; noisy third-party HTTP client logs are suppressed so test runs stay analyzable
- comparison runs must use `LOG_LEVEL=DEBUG`
- competitor-facing API responses were extended so the caller can see whether the answer came from:
  - local FastAPI rules / cache
  - or a real ORDS / database roundtrip
- `checkpoint-access` now exposes `ords_called`
- `open-checkpoints` and `map-checkpoints` now expose response-source metadata
- FastAPI logging was extended with structured trace rows so we can see:
  - which branch handled the request
  - whether ORDS was called
  - branch-specific timing
  - local-vs-ORDS decision paths

These changes were necessary because the earlier aggregated endpoint totals did not show narrowly enough what the system was actually doing.

## Current test scope

Current comparable runs are expected to use:
- improved FastAPI tracing
- response metadata that shows whether a result came from FastAPI/cache or required ORDS
- Locust statistics split by FastAPI/cache/ORDS branches where applicable

Only runs produced after those observability improvements should be used as comparison input for architectural decisions.

Important:
- after the next-version cache split (`competition-content` static payload + `checkpoint-state` participant overlay), new runs should be compared primarily against each other
- earlier `R4`/`R5` remain useful as historical baseline, but they describe the pre-split implementation

## Comparable run matrix

| Run ID | Date | Scenario | Competitions | Users | Spawn rate | Duration min | Map burst s | Start events | KP submissions | Full 50 KP | Partial users | Submission window | Key result |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| R4 | 2026-06-17 | `2 x 100` split load | 2 | 200 | 20 total | 60 | 25 | 200 | 9989 | 190 | `10` users at `48..49` KP | `10:27:00` to `11:30:19` UTC | FastAPI branch stayed clean; main error source was ORDS-backed `checkpoint-access` |
| R5 | 2026-06-17 | `2 x 100` split load | 2 | 200 | 20 total | 60 | 25 | 200 | 10000 | 200 | `0` partial users | `12:53:58` to `13:57:27` UTC | Removing ordinary ORDS confirmation from `checkpoint-access` eliminated the main failure branch |
| R6 | 2026-06-17 | `2 x 100` split load, static/state split version | 2 | 200 | 20 total | 60 | 25 | 200 | 10000 | 200 | `0` partial users | `20:54:11` to `21:57:23` UTC | New cache split stayed stable; only `2` early `submissions` 429 remained |
| R8 | 2026-06-18 | `2 x 100` split load, local `open-checkpoints` active | 2 | 200 | 20 total | 60 | 25 | 200 | 10000 | 200 | `0` partial users | `07:06:38` to `08:10:00` UTC | Clean zero-failure run; `open-checkpoints` served locally in FastAPI and `submission_v` matched successful test submissions exactly |
| R9 | 2026-06-18 | `1 x 400` mass start, local `open-checkpoints` active | 1 | 400 | 20 | 60 | 25 | 400 | 20000 | 400 | `0` partial users | `08:54:11` to `09:57:23` UTC | Core flow stayed fully clean at `400` users; all `61` failures were early bootstrap `429` on login and first metadata loads |

Notes:
- `R4` consists of two simultaneous runs:
  - competition `41`, users `t100..t199`
  - competition `341`, users `t300..t399`
- `submissions_v` confirmed:
  - competition `41`: `100` start events, `4991` KP submissions, `92` users completed all `50`, `8` users ended at `48..49`
  - competition `341`: `100` start events, `4998` KP submissions, `98` users completed all `50`, `2` users ended at `49`
- `R5` consists of the same two simultaneous runs after the `checkpoint-access` change:
  - competition `41`, users `t100..t199`
  - competition `341`, users `t300..t399`
- `submissions_v` / DB counts confirmed for `R5`:
  - competition `41`: `100` start events, `5000` KP submissions, all `100` users completed all `50`
  - competition `341`: `100` start events, `5000` KP submissions, all `100` users completed all `50`
- `R6` consists of the same two simultaneous runs after the static payload / participant-state split:
  - competition `41`, users `t100..t199`
  - competition `341`, users `t300..t399`
- DB counts confirmed for `R6`:
  - competition `41`: `100` start events, `5000` KP submissions
  - competition `341`: `100` start events, `5000` KP submissions
  - combined: `200` start events, `10000` KP submissions
- `R8` consists of the same two simultaneous runs after the local `open-checkpoints` path was confirmed active:
  - competition `41`, users `t100..t199`
  - competition `341`, users `t300..t399`
- DB counts confirmed for `R8`:
  - competition `41`: `100` start events, `5000` KP submissions
  - competition `341`: `100` start events, `5000` KP submissions
  - combined: `200` start events, `10000` KP submissions
- `R8` successful `POST /api/submissions` rows were reconciled against `submission_v` by
  `competition_id + email + checkpoint_id + question_id`:
  - log success rows: `10000`
  - `submission_v` submission rows: `10000`
  - DB-only rows: `0`
  - log-only rows: `0`
  - duplicate keys on either side: `0`
  - conclusion: every successful load-test KP marking was persisted for the same competition, same competitor, same checkpoint and same question as in the test log
- `R9` used competition `41` with users `t001..t400`
- DB counts confirmed for `R9`:
  - competition `41`: `400` start events, `20000` KP submissions
  - all `400` users completed all `50` KP
- `R9` successful `POST /api/submissions` rows were reconciled against `submission_v` by
  `competition_id + email + checkpoint_id + question_id`:
  - log success rows: `20000`
  - `submission_v` submission rows: `20000`
  - DB-only rows: `0`
  - log-only rows: `0`
  - duplicate keys on either side: `0`
  - `checkpoint_id` and `checkpoint_title` matched between log and DB rows for every successful submission
  - per-checkpoint distribution was exact: all `50` checkpoints received `400` submissions each
  - conclusion: every successful `R9` load-test KP marking was persisted for the same competition, same competitor, same checkpoint and same question as in the test log

## Endpoint comparison

### Run R4 by competition

| Run ID | Competition | Endpoint branch | Requests | Failures | Failure % | Avg ms | Median ms | P99 ms | Max ms | Main interpretation |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| R4 | 41 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 312 | 270 | 680 | 683 | bootstrap stable |
| R4 | 41 | `GET /api/competitor/map-checkpoints [cache]` | 45 | 0 | 0.00% | 18 | 4 | 240 | 238 | fast cache hit path |
| R4 | 41 | `GET /api/competitor/map-checkpoints [ords]` | 55 | 0 | 0.00% | 90 | 45 | 640 | 644 | first-load ORDS path |
| R4 | 41 | `GET /api/competitor/open-checkpoints [ords]` | 5025 | 18 | 0.36% | 57 | 49 | 120 | 3739 | ORDS-backed but mostly stable |
| R4 | 41 | `POST /api/competitor/checkpoint-access [fastapi]` | 19872 | 0 | 0.00% | 19 | 4 | 82 | 5447 | local FastAPI path was clean |
| R4 | 41 | `POST /api/competitor/checkpoint-access [ords]` | 5384 | 359 | 6.67% | 61 | 51 | 160 | 3693 | main `429` hotspot |
| R4 | 41 | `POST /api/dev/login` | 100 | 0 | 0.00% | 425 | 410 | 800 | 803 | bootstrap stable |
| R4 | 41 | `POST /api/submissions` | 5007 | 16 | 0.32% | 91 | 63 | 1100 | 6558 | real save path stayed stable |
| R4 | 341 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 296 | 270 | 660 | 655 | bootstrap stable |
| R4 | 341 | `GET /api/competitor/map-checkpoints [cache]` | 2 | 0 | 0.00% | 3 | 3 | 5 | 4 | almost no cache reuse during first wave |
| R4 | 341 | `GET /api/competitor/map-checkpoints [ords]` | 98 | 0 | 0.00% | 57 | 46 | 320 | 317 | first-load ORDS path |
| R4 | 341 | `GET /api/competitor/open-checkpoints [ords]` | 5030 | 23 | 0.46% | 59 | 49 | 140 | 5935 | ORDS-backed but mostly stable |
| R4 | 341 | `POST /api/competitor/checkpoint-access [fastapi]` | 19709 | 0 | 0.00% | 19 | 4 | 81 | 5478 | local FastAPI path was clean |
| R4 | 341 | `POST /api/competitor/checkpoint-access [ords]` | 5399 | 369 | 6.83% | 59 | 50 | 160 | 5048 | main `429` hotspot |
| R4 | 341 | `POST /api/dev/login` | 100 | 0 | 0.00% | 468 | 440 | 810 | 814 | bootstrap stable |
| R4 | 341 | `POST /api/submissions` | 5007 | 9 | 0.18% | 83 | 63 | 710 | 5544 | real save path stayed stable |

### Run R5 by competition

| Run ID | Competition | Endpoint branch | Requests | Failures | Failure % | Avg ms | Median ms | P99 ms | Max ms | Main interpretation |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| R5 | 41 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 504 | 180 | 10000 | 10238 | bootstrap stable, but with long-tail startup latency |
| R5 | 41 | `GET /api/competitor/map-checkpoints [ords]` | 100 | 0 | 0.00% | 445 | 51 | 11000 | 11227 | first-load ORDS path only |
| R5 | 41 | `GET /api/competitor/open-checkpoints [ords]` | 5001 | 0 | 0.00% | 59 | 51 | 170 | 3703 | ORDS-backed and fully stable in this run |
| R5 | 41 | `POST /api/competitor/checkpoint-access [fastapi]` | 25002 | 0 | 0.00% | 16 | 4 | 76 | 5332 | local FastAPI path carried the precheck load cleanly |
| R5 | 41 | `POST /api/dev/login` | 100 | 0 | 0.00% | 600 | 360 | 9800 | 9756 | bootstrap stable, but with long-tail startup latency |
| R5 | 41 | `POST /api/submissions` | 5001 | 1 | 0.02% | 88 | 61 | 1000 | 11769 | real save path was effectively clean |
| R5 | 341 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 642 | 240 | 9100 | 9098 | bootstrap stable, but with long-tail startup latency |
| R5 | 341 | `GET /api/competitor/map-checkpoints [ords]` | 100 | 0 | 0.00% | 94 | 47 | 3500 | 3512 | first-load ORDS path only |
| R5 | 341 | `GET /api/competitor/open-checkpoints [ords]` | 5000 | 0 | 0.00% | 62 | 51 | 180 | 3734 | ORDS-backed and fully stable in this run |
| R5 | 341 | `POST /api/competitor/checkpoint-access [fastapi]` | 24990 | 0 | 0.00% | 15 | 4 | 73 | 4988 | local FastAPI path carried the precheck load cleanly |
| R5 | 341 | `POST /api/competitor/checkpoint-access [ords]` | 2 | 2 | 100.00% | 23 | 20 | 27 | 26 | narrow fallback path still exists but was hit only twice |
| R5 | 341 | `POST /api/dev/login` | 100 | 0 | 0.00% | 619 | 290 | 10000 | 10191 | bootstrap stable, but with long-tail startup latency |
| R5 | 341 | `POST /api/submissions` | 5000 | 0 | 0.00% | 86 | 61 | 880 | 10760 | real save path was fully clean |

### Run R6 by competition

| Run ID | Competition | Endpoint branch | Requests | Failures | Failure % | Avg ms | Median ms | P99 ms | Max ms | Main interpretation |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| R6 | 41 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 124 | 130 | 170 | 165 | bootstrap stable |
| R6 | 41 | `GET /api/competitor/map-checkpoints [cache]` | 45 | 0 | 0.00% | 12 | 4 | 83 | 83 | cache reuse visible already in first wave |
| R6 | 41 | `GET /api/competitor/map-checkpoints [ords]` | 55 | 0 | 0.00% | 69 | 45 | 500 | 499 | static/state split reduced first-load ORDS cost |
| R6 | 41 | `GET /api/competitor/open-checkpoints [ords]` | 5002 | 0 | 0.00% | 54 | 47 | 160 | 2600 | log still showed old ORDS response branch |
| R6 | 41 | `POST /api/competitor/checkpoint-access [fastapi]` | 24989 | 0 | 0.00% | 12 | 4 | 78 | 4400 | precheck stayed fully local and clean |
| R6 | 41 | `POST /api/dev/login` | 100 | 0 | 0.00% | 193 | 180 | 270 | 273 | bootstrap stable |
| R6 | 41 | `POST /api/submissions` | 5002 | 2 | 0.04% | 71 | 53 | 650 | 5200 | only remaining errors were two early ORDS 429 on save |
| R6 | 341 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 120 | 120 | 160 | 156 | bootstrap stable |
| R6 | 341 | `GET /api/competitor/map-checkpoints [cache]` | 98 | 0 | 0.00% | 7 | 4 | 80 | 79 | almost all first map loads came from cache |
| R6 | 341 | `GET /api/competitor/map-checkpoints [ords]` | 2 | 0 | 0.00% | 57 | 57 | 58 | 58 | static payload dedup worked as intended |
| R6 | 341 | `GET /api/competitor/open-checkpoints [ords]` | 5000 | 0 | 0.00% | 59 | 51 | 180 | 5400 | log still showed old ORDS response branch |
| R6 | 341 | `POST /api/competitor/checkpoint-access [fastapi]` | 25059 | 0 | 0.00% | 15 | 4 | 77 | 5200 | precheck stayed fully local and clean |
| R6 | 341 | `POST /api/dev/login` | 100 | 0 | 0.00% | 195 | 190 | 590 | 592 | bootstrap stable |
| R6 | 341 | `POST /api/submissions` | 5000 | 0 | 0.00% | 82 | 60 | 830 | 3525 | save path fully clean |

### Run R8 by competition

| Run ID | Competition | Endpoint branch | Requests | Failures | Failure % | Avg ms | Median ms | P99 ms | Max ms | Main interpretation |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| R8 | 41 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 166 | 150 | 440 | 443 | bootstrap stable |
| R8 | 41 | `GET /api/competitor/map-checkpoints [ords]` | 100 | 0 | 0.00% | 96 | 42 | 2400 | 2378 | first map load still comes from ORDS |
| R8 | 41 | `GET /api/competitor/open-checkpoints [fastapi]` | 5000 | 0 | 0.00% | 2 | 3 | 11 | 36 | local FastAPI question-open path was active and very fast |
| R8 | 41 | `POST /api/competitor/checkpoint-access [fastapi]` | 25104 | 0 | 0.00% | 3 | 3 | 11 | 82 | local FastAPI precheck path stayed fully clean |
| R8 | 41 | `POST /api/dev/login` | 100 | 0 | 0.00% | 269 | 210 | 920 | 921 | bootstrap stable |
| R8 | 41 | `POST /api/submissions` | 5000 | 0 | 0.00% | 84 | 60 | 800 | 4643 | final save path fully clean |
| R8 | 341 | `GET /api/competitor/competitions` | 100 | 0 | 0.00% | 127 | 120 | 680 | 676 | bootstrap stable |
| R8 | 341 | `GET /api/competitor/map-checkpoints [ords]` | 100 | 0 | 0.00% | 68 | 43 | 590 | 589 | first map load still comes from ORDS |
| R8 | 341 | `GET /api/competitor/open-checkpoints [fastapi]` | 5000 | 0 | 0.00% | 2 | 3 | 8 | 36 | local FastAPI question-open path was active and very fast |
| R8 | 341 | `POST /api/competitor/checkpoint-access [fastapi]` | 24920 | 0 | 0.00% | 3 | 3 | 11 | 48 | local FastAPI precheck path stayed fully clean |
| R8 | 341 | `POST /api/dev/login` | 100 | 0 | 0.00% | 219 | 200 | 710 | 710 | bootstrap stable |
| R8 | 341 | `POST /api/submissions` | 5000 | 0 | 0.00% | 86 | 60 | 810 | 5756 | final save path fully clean |

### Run R9 by competition

| Run ID | Competition | Endpoint branch | Requests | Failures | Failure % | Avg ms | Median ms | P99 ms | Max ms | Main interpretation |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| R9 | 41 | `GET /api/competitor/competitions` | 413 | 13 | 3.15% | 221 | 230 | 370 | 510 | bootstrap-only `429` branch in first wave |
| R9 | 41 | `GET /api/competitor/map-checkpoints [ords]` | 430 | 30 | 6.98% | 100 | 49 | 420 | 510 | first metadata wave still hits ORDS and is the main startup hotspot |
| R9 | 41 | `GET /api/competitor/open-checkpoints [fastapi]` | 20000 | 0 | 0.00% | 3 | 3 | 12 | 113 | local FastAPI question-open path stayed fully clean at `400` users |
| R9 | 41 | `POST /api/competitor/checkpoint-access [fastapi]` | 100171 | 0 | 0.00% | 4 | 4 | 14 | 256 | local FastAPI precheck carried the full in-race load cleanly |
| R9 | 41 | `POST /api/dev/login` | 418 | 18 | 4.31% | 351 | 350 | 610 | 667 | startup login burst still produced some `429` |
| R9 | 41 | `POST /api/submissions` | 20000 | 0 | 0.00% | 84 | 60 | 760 | 6998 | final save path stayed fully clean even at `400` users |

### Combined branch totals by run

| Run ID | Branch | Requests | Failures | Failure % | Main meaning |
|---|---|---:|---:|---:|---|
| R4 | `map-checkpoints [cache]` | 47 | 0 | 0.00% | small cache-hit share |
| R4 | `map-checkpoints [ords]` | 153 | 0 | 0.00% | most first map loads still hit ORDS |
| R4 | `open-checkpoints [ords]` | 10055 | 41 | 0.41% | low ORDS failure rate |
| R4 | `checkpoint-access [fastapi]` | 39581 | 0 | 0.00% | FastAPI branch stayed fully stable |
| R4 | `checkpoint-access [ords]` | 10783 | 728 | 6.75% | dominant ORDS error branch |
| R4 | `submissions` | 10014 | 25 | 0.25% | save path was far more stable than ORDS pre-check |
| R5 | `map-checkpoints [cache]` | 0 | 0 | 0.00% | no cache-hit observations in this run snapshot |
| R5 | `map-checkpoints [ords]` | 200 | 0 | 0.00% | all first map loads hit ORDS |
| R5 | `open-checkpoints [ords]` | 10001 | 0 | 0.00% | ORDS-backed and fully stable |
| R5 | `checkpoint-access [fastapi]` | 49992 | 0 | 0.00% | FastAPI branch absorbed the full precheck load cleanly |
| R5 | `checkpoint-access [ords]` | 2 | 2 | 100.00% | residual fallback path only, no longer a material branch |
| R5 | `submissions` | 10001 | 1 | 0.01% | save path effectively clean |
| R6 | `map-checkpoints [cache]` | 143 | 0 | 0.00% | static/state split produced strong cache reuse in first wave |
| R6 | `map-checkpoints [ords]` | 57 | 0 | 0.00% | only a small first-load ORDS share remained |
| R6 | `open-checkpoints [ords]` | 10002 | 0 | 0.00% | response log still showed ORDS branch for every call |
| R6 | `checkpoint-access [fastapi]` | 50048 | 0 | 0.00% | local FastAPI branch carried all precheck load cleanly |
| R6 | `submissions` | 10002 | 2 | 0.02% | only two early ORDS 429 remained on final save path |
| R8 | `map-checkpoints [ords]` | 200 | 0 | 0.00% | first map loads still hit ORDS once per user |
| R8 | `open-checkpoints [fastapi]` | 10000 | 0 | 0.00% | local question-open assembly was active for every call |
| R8 | `checkpoint-access [fastapi]` | 50024 | 0 | 0.00% | local FastAPI precheck carried the full branch cleanly |
| R8 | `submissions` | 10000 | 0 | 0.00% | final save path fully clean |
| R9 | `map-checkpoints [ords]` | 430 | 30 | 6.98% | first-wave ORDS bootstrap remained the only material startup hotspot |
| R9 | `open-checkpoints [fastapi]` | 20000 | 0 | 0.00% | local question-open assembly scaled cleanly to `400` users |
| R9 | `checkpoint-access [fastapi]` | 100171 | 0 | 0.00% | local FastAPI precheck carried the entire in-race branch cleanly |
| R9 | `submissions` | 20000 | 0 | 0.00% | final save path stayed fully clean at `400` users |

### Run R9 time distribution for bootstrap errors

| Run ID | Branch | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| R9 | `GET /api/competitor/map-checkpoints [ords]` | 30 | 0 | 0 | 0 | 0 | 0 | 0 |
| R9 | `POST /api/dev/login` | 18 | 0 | 0 | 0 | 0 | 0 | 0 |
| R9 | `GET /api/competitor/competitions` | 13 | 0 | 0 | 0 | 0 | 0 | 0 |
| R9 | Combined | 61 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R4 time distribution for `checkpoint-access [ords]` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R4 | 41 | 359 | 0 | 0 | 0 | 0 | 0 | 0 |
| R4 | 341 | 369 | 0 | 0 | 0 | 0 | 0 | 0 |
| R4 | Combined | 728 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R4 time distribution for `open-checkpoints [ords]` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R4 | 41 | 18 | 0 | 0 | 0 | 0 | 0 | 0 |
| R4 | 341 | 23 | 0 | 0 | 0 | 0 | 0 | 0 |
| R4 | Combined | 41 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R4 time distribution for `submissions` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R4 | 41 | 16 | 0 | 0 | 0 | 0 | 0 | 0 |
| R4 | 341 | 9 | 0 | 0 | 0 | 0 | 0 | 0 |
| R4 | Combined | 25 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R5 time distribution for `checkpoint-access [ords]` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R5 | 41 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| R5 | 341 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| R5 | Combined | 2 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R5 time distribution for `open-checkpoints [ords]` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R5 | 41 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| R5 | 341 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| R5 | Combined | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R5 time distribution for `submissions` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R5 | 41 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| R5 | 341 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| R5 | Combined | 1 | 0 | 0 | 0 | 0 | 0 | 0 |

### Run R6 time distribution for `submissions` errors

| Run ID | Competition | 0-10 min | 10-20 min | 20-30 min | 30-40 min | 40-50 min | 50-60 min | 60+ min |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R6 | 41 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| R6 | 341 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| R6 | Combined | 2 | 0 | 0 | 0 | 0 | 0 | 0 |

## Current conclusions from R4 vs R5 vs R6

- All three comparable runs used the same `2 x 100` split-load scenario, same users, same competitions, same duration, and the same mass-start model.
- Architectural steps by run:
  - `R4`: old design where `checkpoint-access` still had a meaningful ORDS-backed branch
  - `R5`: ordinary in-radius `checkpoint-access` requests were answered locally in FastAPI instead of performing an ORDS confirmation roundtrip
  - `R6`: same `checkpoint-access` improvement plus the new static payload / participant-state cache split
- End result:
  - `R4`: `9989` successful KP submissions, `190` full finishers
  - `R5`: `10000` successful KP submissions, `200` full finishers
  - `R6`: `10000` successful KP submissions, `200` full finishers
- `R4 -> R5` removed the dominant failure branch:
  - `R4 checkpoint-access [ords]`: `10783` requests, `728` failures, `6.75%`
  - `R5 checkpoint-access [ords]`: `2` requests, `2` failures
- `R5 -> R6` kept that gain and improved first-wave map loading:
  - `R5 map-checkpoints [ords]`: `200`
  - `R5 map-checkpoints [cache]`: `0`
  - `R6 map-checkpoints [ords]`: `57`
  - `R6 map-checkpoints [cache]`: `143`
- The FastAPI precheck branch stayed fully stable in both newer designs:
  - `R5 checkpoint-access [fastapi]`: `49992` requests, `0` failures
  - `R6 checkpoint-access [fastapi]`: `50048` requests, `0` failures
- The final save path remained very clean:
  - `R5 submissions`: `10001` requests, `1` failure, `0.01%`
  - `R6 submissions`: `10002` requests, `2` failures, `0.02%`
- In `R6`, the only errors were two early `429` responses on `/ords/funo/submissions`, both in the first `0-10` minutes.

## Architectural findings to carry forward

- `R5` strongly validated the decision to remove ordinary ORDS confirmation from `checkpoint-access`.
- `R6` strongly validated the static payload / participant-state split for `map-checkpoints` first-wave loading.
- The new cache split did not introduce a new visible failure branch in this `2 x 100` scenario.
- Remaining save-path risk is now narrow and explicit:
  - `submissions` can still hit ORDS rate limit during the very first spike
  - after the first minutes, that error pattern disappeared in `R6`
- Important investigation result from `R6`:
  - run logs still showed `GET /api/competitor/open-checkpoints [ords]` for every call
  - detailed response bodies also showed the old ORDS-style payload shape:
    - top-level `competition_type = null`
    - top-level `mass_start_at = null`
    - top-level `route = null`
    - item-level `radius_m = null`
  - this does **not** match the new local FastAPI `open-checkpoints` implementation now present in repo
  - therefore `R6` must not be interpreted as proof that the new local `open-checkpoints` branch was active on the server
- Practical conclusion:
  - `R6` proves the new `map-checkpoints` split is active and beneficial
  - `R6` does **not** yet prove that the new local `open-checkpoints` assembly path was deployed and used in production during that run
  - before the next `1 x 400` comparison run, deployment state for `open-checkpoints` should be rechecked explicitly

## Current conclusions from R8

- `R8` is the first fully clean `2 x 100` comparison run where the load log itself shows the intended steady-state branch split:
  - `map-checkpoints [ords]`
  - `open-checkpoints [fastapi]`
  - `checkpoint-access [fastapi]`
  - `submissions`
- `R8` completed with:
  - `200` mass-start events
  - `10000` successful KP submissions
  - `0` endpoint failures across both simultaneous runs
  - submission window `07:06:38` to `08:10:00` UTC
- `R8` also passed persistence reconciliation:
  - successful `POST /api/submissions` rows in both JSONL logs matched `submission_v` exactly by `competition_id + email + checkpoint_id + question_id`
  - there were no extra DB rows, no missing DB rows and no duplicate keys on either side
- Practical meaning:
  - for this scenario, the optimized FastAPI-side open/precheck flow is not only fast but also persisted exactly the checkpoints and competitors that the test intended to submit
  - remaining ORDS dependency in the competitor read path is now mainly the first `map-checkpoints` load and the final `submissions` save

## Current conclusions from R9

- `R9` is the first completed `1 x 400` mass-start comparison run on the optimized branch split:
  - `map-checkpoints [ords]`
  - `open-checkpoints [fastapi]`
  - `checkpoint-access [fastapi]`
  - `submissions`
- `R9` completed with:
  - `400` mass-start events
  - `20000` successful KP submissions
  - `400` users finishing all `50` KP
  - submission window `08:54:11` to `09:57:23` UTC
- `R9` error pattern was narrow and startup-bound:
  - total failures: `61` out of `141432` requests (`0.04%`)
  - all `61` failures happened in the first `10` minutes
  - there were no failures at all in the core in-race branches:
    - `open-checkpoints [fastapi]`
    - `checkpoint-access [fastapi]`
    - `submissions`
- Persistence validation was exact:
  - successful `POST /api/submissions` rows in the JSONL log matched `submission_v` exactly by `competition_id + email + checkpoint_id + question_id`
  - there were no extra DB rows, no missing DB rows and no duplicate keys
  - all `50` checkpoints were marked exactly `400` times each
- Practical meaning:
  - once the first-wave bootstrap passes, the optimized steady-state flow scales cleanly to `400` simultaneous competitors on this test scenario
  - the remaining bottleneck is no longer the race-time question/open/save flow, but the first metadata burst that still depends on ORDS during user bootstrap

## Aborted diagnostic run: `R6` (`1 x 400`, competition `41`)

- `R6` was intentionally stopped early after the first-wave error pattern was identified.
- Locust snapshot at interruption:
  - `GET /api/competitor/map-checkpoints [ords]`: `407` requests, `7` failures
  - `GET /api/competitor/open-checkpoints [ords]`: `838` requests, `193` failures
  - `POST /api/competitor/checkpoint-access [fastapi]`: `4142` requests, `0` failures
  - `POST /api/competitor/checkpoint-access [ords]`: `335` requests, `335` failures
  - `POST /api/submissions`: `638` requests, `16` failures
- Detailed JSONL analysis showed that the apparent `checkpoint-access [ords]` branch in `R6` was misleading:
  - `ords_called:true` count in `checkpoint-access` responses was `0`
  - the failing `checkpoint-access [ords]` log rows contained ORDS errors from `/ords/funo/competitor/map-checkpoints`
  - this means `checkpoint-access` itself was not reintroducing the old `open-checkpoints` confirmation flow
- Root cause identified from the log:
  - some users received `429` during bootstrap `GET /api/competitor/map-checkpoints [ords]`
  - those users later reached `checkpoint-access` without a personal map cache
  - `checkpoint-access` then tried to refill `map-checkpoints` via `_get_map_checkpoints_payload(...)`
  - Locust grouped those failures under `checkpoint-access [ords]`, even though the underlying ORDS bottleneck was still `map-checkpoints`
- Architectural conclusion from aborted `R6`:
  - after fixing ordinary `checkpoint-access` ORDS confirmation in `R5`, the next bottleneck at `1 x 400` moved to first-wave `map-checkpoints` loading
  - the next backend improvement therefore targets bootstrap deduplication for `map-checkpoints`, not further `checkpoint-access` rule changes

## What the test does

Each virtual user does:
- `POST /api/dev/login`
- `GET /api/competitor/competitions`
- `GET /api/competitor/map-checkpoints`
- then, over roughly 60 minutes, a stream of `POST /api/competitor/checkpoint-access` calls
- after each successful near-open:
  - `GET /api/competitor/open-checkpoints`
  - `POST /api/submissions`

Important:
- the test does not send a separate `START` submit
- the mass-start event must be created by the system itself on the first real answer
- `map-checkpoints` is loaded once per user, like in the frontend
- unfinished checkpoints are retried while competition time remains

## Branch visibility

The current test and backend expose these distinctions:

- `POST /api/competitor/checkpoint-access`
  - response field: `ords_called`
  - Locust stats:
    - `POST /api/competitor/checkpoint-access [fastapi]`
    - `POST /api/competitor/checkpoint-access [ords]`
  - current FastAPI behavior opens ordinary in-radius checkpoints locally; the `[ords]` branch should now appear only for narrow fallback cases where local metadata is insufficient

- `GET /api/competitor/open-checkpoints`
  - response field: `response_source=cache|fastapi|ords`
  - Locust stats:
    - `GET /api/competitor/open-checkpoints [cache]`
    - `GET /api/competitor/open-checkpoints [fastapi]`
    - `GET /api/competitor/open-checkpoints [ords]`

- `GET /api/competitor/map-checkpoints`
  - response field: `response_source=cache|ords`
  - Locust stats:
    - `GET /api/competitor/map-checkpoints [cache]`
    - `GET /api/competitor/map-checkpoints [ords]`

This split is required to understand actual ORDS pressure and to avoid misleading conclusions from aggregated endpoint totals.

## Logging

The Locust run writes one growing `JSONL` file.

Every line is a separate JSON object.
The file contains:
- run start and stop metadata
- every request with:
  - endpoint
  - request timestamp
  - duration
  - status
  - request body or query
  - response body
  - virtual-user info
  - logical action
  - `ords_called` for `checkpoint-access`
  - `response_source` for `open-checkpoints` and `map-checkpoints`

FastAPI debug logging should be enabled during comparison runs:
- `.env`: `LOG_LEVEL=DEBUG`

Useful FastAPI trace rows:
- `checkpoint_access_trace`
- `open_checkpoints_trace`
- `map_checkpoints_trace`

## Server preparation

On the Ubuntu server:

```bash
mkdir -p ~/fun_o_test
cd ~/fun_o
```

If needed:

```bash
export TESTING_UID=$(id -u)
export TESTING_GID=$(id -g)
```

## Example run pattern

```bash
TESTING_UID=$(id -u) TESTING_GID=$(id -g) docker compose --profile testing run --rm \
  -v ~/fun_o_test:/mnt/load_logs \
  -e LOAD_COMPETITION_ID=41 \
  -e LOAD_DURATION_MIN=60 \
  -e LOAD_DURATION_JITTER_PCT=6 \
  -e LOAD_MAP_BURST_SECONDS=25 \
  -e LOAD_USER_PREFIX=t \
  -e LOAD_USER_COUNT=200 \
  -e LOAD_LOG_FILE=/mnt/load_logs/fun_o_test_41.jsonl \
  -e LOAD_LANG_CODE=et \
  -e LOAD_TEXT_OK_PROBABILITY=0.82 \
  testing \
  -f /mnt/locust/locustfile.py \
  --host https://fun-o.eu \
  --users 200 \
  --spawn-rate 20 \
  --run-time 85m \
  --headless
```

## Live monitoring

FastAPI branch traces:

```bash
docker compose logs -f fastapi | grep -E "map_checkpoints_trace|open_checkpoints_trace|checkpoint_access_trace"
```

Locust errors from a run log:

```bash
tail -f ~/fun_o_test/fun_o_test_41.jsonl | grep --line-buffered -E '"status_code":(400|429|500|502|503|504)'
```

## How to analyze JSONL after a run

Show the final `run_stop` line:

```bash
grep '"event_type":"run_stop"' ~/fun_o_test/fun_o_test_41.jsonl | tail -n 1
```

Count FastAPI-only vs ORDS-backed `checkpoint-access` responses:

```bash
grep '"path":"/api/competitor/checkpoint-access"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"ords_called":true' | wc -l
```

```bash
grep '"path":"/api/competitor/checkpoint-access"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"ords_called":false' | wc -l
```

Count cached vs ORDS `open-checkpoints`:

```bash
grep '"path":"/api/competitor/open-checkpoints"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"response_source":"cache"' | wc -l
```

```bash
grep '"path":"/api/competitor/open-checkpoints"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"response_source":"fastapi"' | wc -l
```

```bash
grep '"path":"/api/competitor/open-checkpoints"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"response_source":"ords"' | wc -l
```

Count cached vs ORDS `map-checkpoints`:

```bash
grep '"path":"/api/competitor/map-checkpoints"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"response_source":"cache"' | wc -l
```

```bash
grep '"path":"/api/competitor/map-checkpoints"' ~/fun_o_test/fun_o_test_41.jsonl | grep '"response_source":"ords"' | wc -l
```

## Current direction

The main purpose of the current test line is not just to count failures, but to identify:
- how much load is handled fully in FastAPI
- how much load requires ORDS
- where failures actually occur
- which request steps may be redundant or architecturally questionable

This is the basis for the next architectural decisions.
