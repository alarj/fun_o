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

## Current conclusions from R4 vs R5

- Both runs used the same `2 x 100` scenario, same users, same competitions, same duration, and the same mass-start model.
- The key architectural change in `R5` was that ordinary in-radius `checkpoint-access` requests were answered locally in FastAPI instead of performing an ORDS confirmation roundtrip.
- End result:
  - `R4`: `9989` successful KP submissions, `190` full finishers
  - `R5`: `10000` successful KP submissions, `200` full finishers
- The dominant failure branch from `R4` disappeared in `R5`:
  - `R4 checkpoint-access [ords]`: `10783` requests, `728` failures, `6.75%`
  - `R5 checkpoint-access [ords]`: `2` requests, `2` failures
- The `R5` fallback branch is not comparable in weight to `R4` anymore:
  - it was hit only twice in the whole run
  - both failures happened in the first `0-10` minutes
  - it no longer represents a meaningful load path
- The FastAPI precheck branch remained fully stable and absorbed more load:
  - `R4 checkpoint-access [fastapi]`: `39581` requests, `0` failures
  - `R5 checkpoint-access [fastapi]`: `49992` requests, `0` failures
- ORDS-backed `open-checkpoints` also improved materially:
  - `R4`: `10055` requests, `41` failures, `0.41%`
  - `R5`: `10001` requests, `0` failures
- The final save path became almost perfectly clean:
  - `R4 submissions`: `10014` requests, `25` failures, `0.25%`
  - `R5 submissions`: `10001` requests, `1` failure, `0.01%`
- In both runs, the remaining failures were concentrated in the first wave:
  - `R4`: all `728` `checkpoint-access [ords]` failures, all `41` `open-checkpoints [ords]` failures, and all `25` `submissions` failures happened in the first `0-10` minutes
  - `R5`: the only `submissions` failure and the only `checkpoint-access [ords]` fallback failures also happened in the first `0-10` minutes

## Architectural findings to carry forward

- `R5` strongly validates the decision to remove ordinary ORDS confirmation from `checkpoint-access`.
- The earlier `R4` bottleneck was architectural, not simply a tuning issue.
- FastAPI already has:
  - cached checkpoint metadata
  - checkpoint coordinates and effective radius
  - local haversine distance calculation
- `R4` showed that the duplicated ORDS confirmation path was the most failure-prone branch.
- `R5` showed that once that duplicated precheck was bypassed for ordinary in-radius cases:
  - the local FastAPI branch stayed fully stable under higher effective precheck volume
  - `open-checkpoints` stayed fully stable
  - the final `submissions` save path was effectively clean
  - all `200` users completed all `50` checkpoints
- `map-checkpoints` still hit ORDS on first load for every user in `R5`:
  - combined ORDS path: `200`
  - combined cache path: `0`
  - this remains a separate optimization topic, but it was not the dominant failure source in `R5`

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
