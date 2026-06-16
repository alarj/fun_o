# Load Test 41 (frontend emulation)

This test emulates competition `41` competitors as closely as practical to the current frontend flow.

Assumptions:
- competition `41` is active;
- the mass-start moment has already passed, so the first real answer creates the automatic start event by system rules;
- 200 test users `t001@funo.local` ... `t200@funo.local` are already active participants on that competition;
- the competition has 50 location-required checkpoints.

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
- the test does not send a separate `START` submit;
- the mass-start event must be created by the system itself on the first real answer;
- `map-checkpoints` is loaded once per user, like in the frontend;
- checkpoint opening is checked through `checkpoint-access`, so FastAPI can do the geo prefilter before a possible ORDS roundtrip.

## Load profile

Defaults:
- `200` users
- `50` submit attempts per user
- on average about `250` `checkpoint-access` requests per user
- the first checkpoints happen more densely, then the pace spreads out
- near/far geo attempts are distributed across the whole user journey, not front-loaded into the beginning

Near/far logic:
- `far` attempts stay intentionally outside checkpoint radius and should mostly stop at FastAPI level
- `near` attempts go inside the 50 m answering radius and should reach final open-check plus submit flow

## Logging

The test writes one growing `JSONL` file.

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
  - logical action (`load_map`, `checkpoint_access`, `open_checkpoint`, `submit_answer`)

By default the Locust container writes to:
- `/mnt/load_logs/fun_o_test_41.jsonl`

Recommended host-side mount target:
- `~/fun_o_test`

## Server preparation

On the Ubuntu server:

```bash
mkdir -p ~/fun_o_test
cd ~/fun_o
```

The `testing` container now runs by default as UID/GID `1000:1000`, which matches the normal `ubuntu` user setup on your server and allows writing into a bind-mounted `~/fun_o_test`.

If the server user has a different UID/GID, set them before running:

```bash
export TESTING_UID=$(id -u)
export TESTING_GID=$(id -g)
```

## Recommended run

```bash
docker compose --profile testing run --rm \
  -v ~/fun_o_test:/mnt/load_logs \
  -e LOAD_COMPETITION_ID=41 \
  -e LOAD_DURATION_MIN=60 \
  -e LOAD_DURATION_JITTER_PCT=6 \
  -e LOAD_MAP_BURST_SECONDS=5 \
  -e LOAD_USER_PREFIX=t \
  -e LOAD_USER_COUNT=200 \
  -e LOAD_LOG_FILE=/mnt/load_logs/fun_o_test_41.jsonl \
  -e LOAD_LANG_CODE=et \
  -e LOAD_TEXT_OK_PROBABILITY=0.82 \
  testing \
  -f /mnt/locust/locustfile.py \
  --host https://fun-o.eu \
  --users 200 \
  --spawn-rate 40 \
  --run-time 70m \
  --headless
```

Notes:
- `--run-time 70m` leaves buffer so the full 60-minute journey can finish.
- `spawn-rate 40` creates roughly a 5-second start wave.
- the log file stays on the server outside the repo, under `~/fun_o_test`.
- if writing still fails, first check `echo $TESTING_UID`, `echo $TESTING_GID`, and that `~/fun_o_test` is owned by the same host user.

## Smoke test

Before the full run, use a short smoke test:

```bash
docker compose --profile testing run --rm \
  -v ~/fun_o_test:/mnt/load_logs \
  -e LOAD_COMPETITION_ID=41 \
  -e LOAD_DURATION_MIN=5 \
  -e LOAD_LOG_FILE=/mnt/load_logs/fun_o_test_smoke.jsonl \
  testing \
  -f /mnt/locust/locustfile.py \
  --host https://fun-o.eu \
  --users 10 \
  --spawn-rate 5 \
  --run-time 7m \
  --headless
```

## Main environment variables

- `LOAD_COMPETITION_ID`
  - default `41`
- `LOAD_DURATION_MIN`
  - base planned journey length in minutes, default `60`
- `LOAD_DURATION_JITTER_PCT`
  - small timing spread between users, default `6`
- `LOAD_MAP_BURST_SECONDS`
  - how quickly users load the map at the start, default `5`
- `LOAD_USER_PREFIX`
  - default `t`
- `LOAD_USER_COUNT`
  - default `200`
- `LOAD_LOG_FILE`
  - in-container path for the JSONL log file
- `LOAD_LANG_CODE`
  - default `et`
- `LOAD_TEXT_OK_PROBABILITY`
  - how often TEXT answers use `OK`, default `0.82`
- `LOAD_MAX_BODY_CHARS`
  - `0` means request/response bodies are not truncated
- `LOAD_MAX_NEAR_RETRIES`
  - how many times a near-open can be retried for the same checkpoint, default `3`

## What this test intentionally does not do

- does not re-register users to the competition;
- does not send a separate start-submit;
- does not collect ORDS-side detailed tracing yet;
- does not modify application code.

## Full run summary (2026-06-16)

This section records the first full `competition_id=41` run with the current frontend-emulation Locust script.

Run profile:
- `200` users
- `spawn-rate 40`
- `LOAD_DURATION_MIN=60`
- `LOAD_MAP_BURST_SECONDS=5`
- `--run-time 70m`

Observed outcome:
- the run ended normally because the configured `--run-time` limit was reached;
- `submission_events`: `192`
- `submissions`: about `9600`
- practical interpretation:
  - `192` users completed all `50` checkpoints;
  - `8` users did not complete the full path before the run stopped.

Locust totals from `run_stop`:
- total requests: `68424`
- total failures: `641`
- aggregated median response time: `42 ms`
- aggregated max response time: about `38 s`

Per-endpoint totals:
- `GET /api/competitor/competitions`
  - `199` requests
  - `5` failures
  - median `750 ms`
- `GET /api/competitor/map-checkpoints`
  - `194` requests
  - `3` failures
  - median `110 ms`
- `POST /api/competitor/checkpoint-access`
  - `49538` requests
  - `561` failures
  - median `5 ms`
- `GET /api/competitor/open-checkpoints`
  - `9169` requests
  - `45` failures
  - median `49 ms`
- `POST /api/submissions`
  - `9124` requests
  - `26` failures
  - median `68 ms`
- `POST /api/dev/login`
  - `200` requests
  - `1` failure
  - median `1200 ms`

Important percentile observations:
- `POST /api/competitor/checkpoint-access`
  - `99%` about `130 ms`
  - `99.9%` about `12 s`
  - max about `38 s`
- `GET /api/competitor/open-checkpoints`
  - `99%` about `3.5 s`
  - `99.9%` about `22 s`
  - max about `37 s`
- `POST /api/submissions`
  - `99%` about `3.2 s`
  - `99.9%` about `12 s`
  - max about `38 s`

Error summary from Locust:
- `559` x `429` on `POST /api/competitor/checkpoint-access`
- `42` x `429` on `GET /api/competitor/open-checkpoints`
- `20` x `429` on `POST /api/submissions`
- small number of `400` errors on login, competitions, map-checkpoints, open-checkpoints, submissions, and checkpoint-access
- `1` x `502` on `POST /api/submissions`

Root-cause interpretation:
- the Ubuntu VM itself was not the bottleneck;
- during the run the host stayed low on CPU and memory usage, so infra capacity on that VM remained comfortable;
- the dominant bottleneck was ORDS-side throttling and related tail latency;
- many `400` responses were not client payload mistakes, but FastAPI-wrapped ORDS errors:
  - log details showed `api.error.ords_request_failed`
  - underlying ORDS status was `404`
  - ORDS returned HTML error pages in those cases;
- the `429` responses were real ORDS rate-limit responses and were the main reason why a part of users did not finish.

What this run proved:
- FastAPI-side geo prefiltering helps significantly;
- most `checkpoint-access` calls stayed very fast, which means the far-check filtering avoided unnecessary ORDS work;
- the remaining limiting factor is still ORDS under concurrent near-open and submit load.

Recommended next run tuning without changing application code:
- reduce `spawn-rate` from `40` to `20` or `25`
- increase `LOAD_MAP_BURST_SECONDS` from `5` to `20` or `30`
- increase `--run-time` from `70m` to `80m` or `85m`

Suggested next attempt:

```bash
docker compose --profile testing run --rm \
  -v ~/fun_o_test:/mnt/load_logs \
  -e LOAD_COMPETITION_ID=41 \
  -e LOAD_DURATION_MIN=60 \
  -e LOAD_DURATION_JITTER_PCT=6 \
  -e LOAD_MAP_BURST_SECONDS=25 \
  -e LOAD_USER_PREFIX=t \
  -e LOAD_USER_COUNT=200 \
  -e LOAD_LOG_FILE=/mnt/load_logs/fun_o_test_41_run2.jsonl \
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

## How to analyze JSONL after a run

All examples below assume the log file is on the Ubuntu server under `~/fun_o_test/`.

Example:

```bash
cd ~/fun_o_test
```

### 1. Check that the run ended normally

Show the final `run_stop` line:

```bash
grep '"event_type":"run_stop"' fun_o_test_41.jsonl | tail -n 1
```

This line contains:
- total request count
- total failure count
- aggregated timings
- per-endpoint summary

### 2. Watch only real errors during a live run

Only `429`, `500`, `502`, `503`:

```bash
tail -f fun_o_test_41.jsonl | grep -E '"status_code":(429|500|502|503)'
```

Only non-null exceptions:

```bash
tail -f fun_o_test_41.jsonl | grep -v '"exception":null' | grep '"exception":'
```

### 3. Count how many users actually finished

```bash
grep -c '"event_type":"user_complete"' fun_o_test_41.jsonl
```

To inspect the completion rows themselves:

```bash
grep '"event_type":"user_complete"' fun_o_test_41.jsonl | tail -n 20
```

### 4. See the slowest requests

If `jq` is available, show requests slower than 1000 ms:

```bash
jq -c 'select(.event_type=="request" and (.response_time_ms > 1000))' fun_o_test_41.jsonl
```

For a stricter threshold, for example 5000 ms:

```bash
jq -c 'select(.event_type=="request" and (.response_time_ms > 5000))' fun_o_test_41.jsonl
```

### 5. See only failed requests

With `jq`:

```bash
jq -c 'select(.event_type=="request" and (.status_code != 200 or .exception != null))' fun_o_test_41.jsonl
```

### 6. Group by status code

If `jq` is available:

```bash
jq -r 'select(.event_type=="request") | .status_code' fun_o_test_41.jsonl | sort | uniq -c
```

### 7. Group by endpoint

If `jq` is available:

```bash
jq -r 'select(.event_type=="request") | .name' fun_o_test_41.jsonl | sort | uniq -c
```

### 8. Extract only ORDS throttling rows

This is useful when ORDS `429` is suspected:

```bash
grep '"code":"ORDS_RATE_LIMITED"' fun_o_test_41.jsonl
```

### 9. Extract FastAPI-wrapped ORDS errors

This helps separate true client-side mistakes from upstream failures:

```bash
grep '"code":"ORDS_ERROR"' fun_o_test_41.jsonl
```

### 10. Quick interpretation checklist

After a run, check at least:
- how many `user_complete` rows exist
- whether `run_stop` exists
- total failures in the `run_stop` stats
- whether failures are mostly `429`
- whether the highest tail latencies are concentrated on:
  - `checkpoint-access`
  - `open-checkpoints`
  - `submissions`

If most failures are `429`, the practical bottleneck is usually ORDS throttling rather than the Ubuntu VM itself.
