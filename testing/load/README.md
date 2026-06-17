# Load Test 41 (frontend emulation)

This test emulates competition `41` competitors as closely as practical to the current frontend flow.

## Test Run Comparison

### Run Matrix

| Run ID | Date | Competitions | Users | Spawn Rate | Map Burst | Run Time | Submission Events | Checkpoint Submissions | Total Requests | Total Failures | 429 Failures | Non-429 Failures | Aggregated Median ms | Aggregated Max ms | Key Outcome |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| R1 | 2026-06-16 | 1 | 200 | 40 | 5 | 70m | 192 | 9600 | 68424 | 641 | 621 | 20 | 42 | 37915 | 192 users reached full 50 KP path |
| R2 | 2026-06-16 | 1 | 200 | 20 | 25 | 85m | 200 | 10000 | 71315 | 862 | 862 | 0 | 42 | 5177 | All 200 users reached full 50 KP path |
| R3 | 2026-06-16 | 1 | 400 | 20 | 25 | 85m | 400 | 17590 | 156657 | 33068 | 32991 | 77 | 47 | 25540 | All 400 users got a start mark, but no user completed all 50 KP |
| R4 | 2026-06-16 | 2 | 200 | 20 | 25 | 85m | 200 | 9985 | 71244 | 1392 | 1392 | 0 | 43 | 5989 | Split load across 2 competitions: 185 users completed all 50 KP, 15 users missed 1 KP |

### Endpoint Comparison

| Run ID | Endpoint | Requests | Failures | Avg ms | Median ms | P99 ms | P99.9 ms | Max ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| R1 | `GET /api/competitor/competitions` | 199 | 5 | 2569.87 | 750 | 13000 | 13000 | 13000 |
| R1 | `GET /api/competitor/map-checkpoints` | 194 | 3 | 2002.39 | 110 | 12000 | 13000 | 13000 |
| R1 | `POST /api/competitor/checkpoint-access` | 49538 | 561 | 70.45 | 5 | 130 | 12000 | 37915 |
| R1 | `GET /api/competitor/open-checkpoints` | 9169 | 45 | 176.20 | 49 | 3500 | 22000 | 37000 |
| R1 | `POST /api/submissions` | 9124 | 26 | 188.27 | 68 | 3200 | 12000 | 38000 |
| R1 | `POST /api/dev/login` | 200 | 1 | 3470.21 | 1200 | 26000 | 26000 | 26000 |
| R2 | `GET /api/competitor/competitions` | 200 | 0 | 232.00 | 240 | 340 | 340 | 340 |
| R2 | `GET /api/competitor/map-checkpoints` | 200 | 0 | 83.00 | 48 | 630 | 640 | 640 |
| R2 | `POST /api/competitor/checkpoint-access` | 50569 | 755 | 26.00 | 7 | 96 | 720 | 5177 |
| R2 | `GET /api/competitor/open-checkpoints` | 10107 | 68 | 55.00 | 49 | 130 | 1000 | 3692 |
| R2 | `POST /api/submissions` | 10039 | 39 | 89.00 | 68 | 820 | 2100 | 4749 |
| R2 | `POST /api/dev/login` | 200 | 0 | 369.00 | 370 | 530 | 550 | 550 |
| R3 | `GET /api/competitor/competitions` | 400 | 0 | 283.00 | 240 | 1300 | 8200 | 8204 |
| R3 | `GET /api/competitor/map-checkpoints` | 400 | 0 | 201.00 | 58 | 3900 | 8400 | 8410 |
| R3 | `POST /api/competitor/checkpoint-access` | 117225 | 30836 | 270.00 | 31 | 3700 | 15000 | 25540 |
| R3 | `GET /api/competitor/open-checkpoints` | 19769 | 1306 | 563.00 | 63 | 13000 | 16000 | 25235 |
| R3 | `POST /api/submissions` | 18463 | 926 | 497.00 | 97 | 11000 | 15000 | 25279 |
| R3 | `POST /api/dev/login` | 400 | 0 | 618.00 | 380 | 7800 | 12000 | 11933 |
| R4 | `GET /api/competitor/competitions` | 200 | 0 | 121.00 | 125 | 210 | 210 | 208 |
| R4 | `GET /api/competitor/map-checkpoints` | 200 | 0 | 45.00 | 43 | 280 | 280 | 276 |
| R4 | `POST /api/competitor/checkpoint-access` | 50575 | 1320 | 28.00 | 8 | 100 | 1200 | 5817 |
| R4 | `GET /api/competitor/open-checkpoints` | 10057 | 45 | 58.00 | 49 | 120 | 2200 | 5832 |
| R4 | `POST /api/submissions` | 10012 | 27 | 85.50 | 64 | 770 | 3000 | 5989 |
| R4 | `POST /api/dev/login` | 200 | 0 | 219.50 | 195 | 750 | 750 | 747 |

### Current Conclusions

- The Ubuntu VM was not the bottleneck in either run; CPU and memory stayed comfortably below saturation.
- The dominant limiting factor remained ORDS throttling.
- FastAPI-side geo prefiltering kept `checkpoint-access` median latency very low in both runs.
- Reducing `spawn-rate` from `40` to `20` and increasing `LOAD_MAP_BURST_SECONDS` from `5` to `25` materially improved the bootstrap phase and enabled all `200` users to complete the path.
- Extending `--run-time` from `70m` to `85m` was not the main reason for the improvement; the key gain came from a softer start wave.
- At `400` users with the same softer start wave, the system did not crash and all users eventually got a start mark, but the ORDS-backed active competition flow degraded sharply during the start wave.
- In the `400`-user run the failure rate dropped later, which indicates partial recovery after the initial spike, but the current test logic still allowed users to stall with unfinished checkpoints.
- The next iteration of the load script should keep retrying unfinished checkpoints while competition time remains, so temporary early errors do not artificially cap end-of-run usage.
- Splitting the same `200` total users across two simultaneous `100`-user competitions produced a near-perfect result with low latency and no non-`429` errors.
- For this system, competition-local concurrency clearly matters: `2 x 100` was materially better than `1 x 200` on one competition, even though total user count was the same.

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
- `LOAD_USER_START_INDEX`
  - first numeric user index, default `1`
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

## Full run summary (2026-06-16, run 2)

This section records the second full `competition_id=41` run with the tuned frontend-emulation Locust script.

Run profile:
- `200` users
- `spawn-rate 20`
- `LOAD_DURATION_MIN=60`
- `LOAD_MAP_BURST_SECONDS=25`
- `--run-time 85m`

Observed outcome:
- the run ended normally because the configured `--run-time` limit was reached;
- `submission_events`: `200`
- `submissions`: `10000`
- practical interpretation:
  - all `200` users completed all `50` checkpoints.

Locust totals from `run_stop`:
- total requests: `71315`
- total failures: `862`
- aggregated median response time: `42 ms`
- aggregated max response time: `5177 ms`

Per-endpoint totals:
- `GET /api/competitor/competitions`
  - `200` requests
  - `0` failures
  - median `240 ms`
- `GET /api/competitor/map-checkpoints`
  - `200` requests
  - `0` failures
  - median `48 ms`
- `POST /api/competitor/checkpoint-access`
  - `50569` requests
  - `755` failures
  - median `7 ms`
- `GET /api/competitor/open-checkpoints`
  - `10107` requests
  - `68` failures
  - median `49 ms`
- `POST /api/submissions`
  - `10039` requests
  - `39` failures
  - median `68 ms`
- `POST /api/dev/login`
  - `200` requests
  - `0` failures
  - median `370 ms`

Error summary from Locust:
- `755` x `429` on `POST /api/competitor/checkpoint-access`
- `68` x `429` on `GET /api/competitor/open-checkpoints`
- `39` x `429` on `POST /api/submissions`
- no non-`429` failures

What changed versus run 1:
- the softer start wave removed the earlier `400` and `502` noise;
- all `200` users reached a full `50 KP` path;
- median latencies stayed low and endpoint max times dropped sharply.

## Full run summary (2026-06-16, run 3)

This section records the first `400`-user full run for `competition_id=41` with the same tuned start profile as run 2.

Run profile:
- `400` users
- `spawn-rate 20`
- `LOAD_DURATION_MIN=60`
- `LOAD_MAP_BURST_SECONDS=25`
- `--run-time 85m`

Observed outcome:
- the run ended with Locust exit code `1` because failures were present, but the configured run completed;
- `submission_events`: `400`
- `submissions`: `17590`
- practical interpretation:
  - all `400` users eventually got a start mark;
  - no user completed all `50` checkpoints;
  - users stopped between `38` and `49` checkpoint submissions each;
  - the distribution concentrated in the middle: `286` users ended at `43` to `46` checkpoints, `32` users reached `47` to `49`, and `11` users remained at `38` to `40`.

Locust totals from `run_stop`:
- total requests: `156657`
- total failures: `33068`
- aggregated median response time: `47 ms`
- aggregated max response time: `25540 ms`

Per-endpoint totals:
- `GET /api/competitor/competitions`
  - `400` requests
  - `0` failures
  - median `240 ms`
- `GET /api/competitor/map-checkpoints`
  - `400` requests
  - `0` failures
  - median `58 ms`
- `POST /api/competitor/checkpoint-access`
  - `117225` requests
  - `30836` failures
  - median `31 ms`
- `GET /api/competitor/open-checkpoints`
  - `19769` requests
  - `1306` failures
  - median `63 ms`
- `POST /api/submissions`
  - `18463` requests
  - `926` failures
  - median `97 ms`
- `POST /api/dev/login`
  - `400` requests
  - `0` failures
  - median `380 ms`

Important percentile observations:
- `POST /api/competitor/checkpoint-access`
  - `99%` about `3.7 s`
  - `99.9%` about `15 s`
  - max about `25.5 s`
- `GET /api/competitor/open-checkpoints`
  - `99%` about `13 s`
  - `99.9%` about `16 s`
  - max about `25.2 s`
- `POST /api/submissions`
  - `99%` about `11 s`
  - `99.9%` about `15 s`
  - max about `25.3 s`

Error summary from Locust:
- `30808` x `429` on `POST /api/competitor/checkpoint-access`
- `1290` x `429` on `GET /api/competitor/open-checkpoints`
- `893` x `429` on `POST /api/submissions`
- `31` x `400` on `POST /api/submissions`
- `16` x `400` on `GET /api/competitor/open-checkpoints`
- `28` x `400` on `POST /api/competitor/checkpoint-access`
- `2` x `502` on `POST /api/submissions`

Operational observations during the run:
- Ubuntu VM memory stayed low, around `1.75 GB` used on a `24 GB` server;
- CPU spiked during the start wave, but later stabilized and finally dropped under `1%`;
- `429` rows became rare later in the run, which suggests the system partially recovered after the initial start-wave spike.

Interpretation:
- the main bottleneck again appeared in the ORDS-backed active competition flow, especially `checkpoint-access` leading into `open-checkpoints`;
- the system did not hard-fail and eventually created all `400` start marks;
- the database end state confirmed `400` `submission_events` rows and `17590` `submissions` rows for the run;
- per-user completion counts clustered heavily below the finish line, with the largest groups at `44` checkpoints (`86` users), `43` checkpoints (`77` users), and `45` checkpoints (`77` users);
- however, the current Locust journey logic let users stall after early failures instead of returning to unfinished checkpoints later in the hour;
- this means the final `17590` submissions total reflects both real ORDS throttling and a test-scenario limitation.

Follow-up requirement for the next test-script iteration:
- if a checkpoint is still unfinished and competition time remains, the virtual competitor should keep trying later instead of effectively abandoning that checkpoint after early failures;
- start-wave errors should not artificially suppress end-of-run load when the competition window is still open.

## Full run summary (2026-06-16, run 4)

This section records the split-load comparison run: two simultaneous competitions with `100` users each, for a combined total of `200` users.

Run profile:
- competition `41`: users `t100..t199`
- competition `341`: users `t300..t399`
- `100` users per container, `200` total
- `spawn-rate 10` per container, `20` total
- `LOAD_DURATION_MIN=60`
- `LOAD_MAP_BURST_SECONDS=25`
- `--run-time 85m`

Observed outcome:
- both runs ended with Locust exit code `1` because failures were present, but the configured runs completed;
- `submission_events`: `200`
- `submissions`: `9985`
- practical interpretation:
  - all `200` users got a start mark;
  - `185` users completed all `50` checkpoints;
  - `15` users missed exactly `1` checkpoint;
  - of those `15`, `8` belonged to competition `41` and `7` to competition `341`;
  - the effective submission window was about `1 h 3 min`.

Combined Locust totals from both `run_stop` reports:
- total requests: `71244`
- total failures: `1392`
- aggregated median response time: `43 ms`
- aggregated max response time: `5989 ms`

Per-competition totals:
- competition `41`
  - total requests: `35671`
  - total failures: `656`
  - aggregated median response time: `43 ms`
  - aggregated max response time: `5989 ms`
- competition `341`
  - total requests: `35573`
  - total failures: `736`
  - aggregated median response time: `43 ms`
  - aggregated max response time: `5832 ms`

Combined per-endpoint totals:
- `GET /api/competitor/competitions`
  - `200` requests
  - `0` failures
  - median about `125 ms`
- `GET /api/competitor/map-checkpoints`
  - `200` requests
  - `0` failures
  - median about `43 ms`
- `POST /api/competitor/checkpoint-access`
  - `50575` requests
  - `1320` failures
  - median `8 ms`
- `GET /api/competitor/open-checkpoints`
  - `10057` requests
  - `45` failures
  - median `49 ms`
- `POST /api/submissions`
  - `10012` requests
  - `27` failures
  - median about `64 ms`
- `POST /api/dev/login`
  - `200` requests
  - `0` failures
  - median about `195 ms`

Error summary from Locust:
- competition `41`
  - `620` x `429` on `POST /api/competitor/checkpoint-access`
  - `24` x `429` on `GET /api/competitor/open-checkpoints`
  - `12` x `429` on `POST /api/submissions`
- competition `341`
  - `700` x `429` on `POST /api/competitor/checkpoint-access`
  - `21` x `429` on `GET /api/competitor/open-checkpoints`
  - `15` x `429` on `POST /api/submissions`

Operational observations during the run:
- all `200` users got their start marks quickly;
- server RAM stayed around `1.7 GB`;
- CPU stayed mostly around `5%` to `10%`, with only occasional small spikes;
- no visible sustained `429` burst appeared in the live tail view.

Comparison against run 2 (`1 x 200` on one competition):
- total request volume was almost identical: `71244` in run 4 vs `71315` in run 2;
- total failures were higher: `1392` vs `862`;
- `checkpoint-access` failures were higher: `1320` vs `755`;
- however, the practical completion outcome remained very close:
  - run 2: `200 / 200` users completed all `50` checkpoints;
  - run 4: `185 / 200` users completed all `50`, and the remaining `15` missed only `1` checkpoint each.

Interpretation:
- splitting the same total `200` users across two competitions kept the infrastructure profile very calm and avoided the severe degradation seen in the `400`-user single-competition run;
- compared with the best `1 x 200` single-competition run, the split run was slightly worse on raw `429` counts but still nearly equivalent in practical business outcome;
- the remaining gap to a perfect `10000` submissions is again best explained by the current Locust journey logic, which does not keep returning to unfinished checkpoints late in the run.

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
