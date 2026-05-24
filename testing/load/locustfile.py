from __future__ import annotations

import math
import os
import random
import threading
import time
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from locust import HttpUser, between, events, task


# ----------------------
# Config via ENV vars
# ----------------------
COMPETITION_ID = int(os.getenv("LOAD_COMPETITION_ID", "41"))
ACCESS_CODE = os.getenv("LOAD_ACCESS_CODE", "508671")
KP_COUNT = int(os.getenv("LOAD_KP_COUNT", "50"))
BASE_DURATION_MIN = float(os.getenv("LOAD_DURATION_MIN", "180"))
FINISH_JITTER_PCT = float(os.getenv("LOAD_FINISH_JITTER_PCT", "15"))
FAR_REQUEST_MULTIPLIER = int(os.getenv("LOAD_FAR_REQUEST_MULTIPLIER", "4"))
NO_LOCATION_MODE = os.getenv("LOAD_NO_LOCATION_MODE", "false").lower() == "true"
MAP_BURST_SECONDS = float(os.getenv("LOAD_MAP_BURST_SECONDS", "5"))
DEFAULT_RADIUS_M = float(os.getenv("LOAD_DEFAULT_RADIUS_M", "25"))
USER_PREFIX = os.getenv("LOAD_USER_PREFIX", "T")
USER_COUNT = int(os.getenv("LOAD_USER_COUNT", "200"))
RESULTS_DIR = os.getenv("LOAD_RESULTS_DIR", "/mnt/locust/results")
SLOW_REQUEST_MS = float(os.getenv("LOAD_SLOW_REQUEST_MS", "1500"))
# 0 or negative = unlimited
MAX_LOGGED_EVENTS = int(os.getenv("LOAD_MAX_LOGGED_EVENTS", "0"))
MAX_BODY_CHARS = int(os.getenv("LOAD_MAX_BODY_CHARS", "0"))

# Keep cookies usable in DEV (http)
SESSION_COOKIE_SECURE = os.getenv("LOAD_SESSION_COOKIE_SECURE", "false").lower() == "true"


@dataclass
class Checkpoint:
    checkpoint_id: int
    title: str
    lat: float | None
    lon: float | None
    radius_m: float | None
    question_id: int | None
    question_type: str | None


_user_seq = 0
_user_lock = threading.Lock()
_run_started_at_ts: float | None = None
_error_events: list[dict[str, Any]] = []
_slow_events: list[dict[str, Any]] = []
_error_events_lock = threading.Lock()


def _is_already_registered_response(name: str | None, status_code: int | None, response: Any) -> bool:
    if name != "POST /api/competitions/register":
        return False
    if status_code not in (400, 409):
        return False

    txt = ""
    try:
        body = response.json() if response is not None else None
        if isinstance(body, dict):
            err_code = str(body.get("code") or body.get("error_code") or "").upper()
            err_msg = str(body.get("message") or body.get("detail") or "").upper()
            txt = f"{err_code} {err_msg}"
    except Exception:
        pass

    if not txt and response is not None:
        txt = str(getattr(response, "text", "")).upper()

    return (
        "ALREADY_REGISTERED" in txt
        or "JUBA" in txt
        or "REGISTERED" in txt
    )


def _extract_request_inputs(url: str | None, response: Any) -> dict[str, Any]:
    parsed_url = urlparse(url or "")
    query: dict[str, Any] = {}
    if parsed_url.query:
        query = {k: (v[0] if len(v) == 1 else v) for k, v in parse_qs(parsed_url.query).items()}

    request_body: str | None = None
    req = getattr(response, "request", None) if response is not None else None
    body = getattr(req, "body", None) if req is not None else None
    if body is not None:
        if isinstance(body, bytes):
            request_body = body.decode("utf-8", errors="replace")
        else:
            request_body = str(body)
        if MAX_BODY_CHARS > 0 and len(request_body) > MAX_BODY_CHARS:
            request_body = request_body[:MAX_BODY_CHARS] + "...<truncated>"

    return {
        "path": parsed_url.path or None,
        "query_params": query,
        "request_body": request_body,
    }


def _extract_response_body(response: Any) -> str | None:
    if response is None:
        return None
    txt = str(getattr(response, "text", ""))
    if MAX_BODY_CHARS > 0 and len(txt) > MAX_BODY_CHARS:
        txt = txt[:MAX_BODY_CHARS] + "...<truncated>"
    return txt


def next_user_seq() -> int:
    global _user_seq
    with _user_lock:
        _user_seq += 1
        return _user_seq


def meters_to_lat(meters: float) -> float:
    return meters / 111_111.0


def meters_to_lon(meters: float, lat_deg: float) -> float:
    scale = math.cos(math.radians(lat_deg))
    if abs(scale) < 1e-6:
        scale = 1e-6
    return meters / (111_111.0 * scale)


def random_offset_within_radius_m(radius_m: float, lat: float) -> tuple[float, float]:
    # Uniform-ish in disc
    r = radius_m * math.sqrt(random.random())
    a = random.random() * 2.0 * math.pi
    dy = math.sin(a) * r
    dx = math.cos(a) * r
    return meters_to_lat(dy), meters_to_lon(dx, lat)


def parse_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    items = payload.get("items")
    return items if isinstance(items, list) else []


@events.test_start.add_listener
def _print_config(environment, **kwargs):
    global _run_started_at_ts
    _run_started_at_ts = time.time()
    environment.runner.greenlet.spawn(lambda: print(
        f"[load] config competition_id={COMPETITION_ID} kp_count={KP_COUNT} "
        f"duration_min={BASE_DURATION_MIN} far_multiplier={FAR_REQUEST_MULTIPLIER}"
    ))


def _iso(ts: float | None) -> str | None:
    if ts is None:
        return None
    return datetime.fromtimestamp(ts).isoformat(timespec="seconds")


def _safe_num(v: Any) -> int | float | None:
    if isinstance(v, (int, float)):
        return v
    return None


def _collect_stats(environment) -> dict[str, Any]:
    total = environment.stats.total
    entries = []
    for (_, _), stat in sorted(environment.stats.entries.items(), key=lambda x: (x[0][0], x[0][1])):
        entries.append({
            "method": stat.method,
            "name": stat.name,
            "num_requests": stat.num_requests,
            "num_failures": stat.num_failures,
            "avg_response_time_ms": _safe_num(stat.avg_response_time),
            "min_response_time_ms": _safe_num(stat.min_response_time),
            "max_response_time_ms": _safe_num(stat.max_response_time),
            "median_response_time_ms": _safe_num(stat.median_response_time),
            "current_rps": _safe_num(stat.current_rps),
            "current_fail_per_sec": _safe_num(stat.current_fail_per_sec),
        })

    errors = []
    for err in environment.stats.errors.values():
        errors.append({
            "name": getattr(err, "name", None),
            "method": getattr(err, "method", None),
            "error": str(getattr(err, "error", None)),
            "occurrences": getattr(err, "occurrences", None),
        })

    return {
        "aggregated": {
            "num_requests": total.num_requests,
            "num_failures": total.num_failures,
            "avg_response_time_ms": _safe_num(total.avg_response_time),
            "min_response_time_ms": _safe_num(total.min_response_time),
            "max_response_time_ms": _safe_num(total.max_response_time),
            "median_response_time_ms": _safe_num(total.median_response_time),
            "current_rps": _safe_num(total.current_rps),
            "current_fail_per_sec": _safe_num(total.current_fail_per_sec),
        },
        "entries": entries,
        "errors": errors,
    }


@events.request.add_listener
def _capture_error_event(
    request_type,
    name,
    response_time,
    response_length,
    response,
    context,
    exception,
    start_time,
    url,
    **kwargs,
):
    status_code = getattr(response, "status_code", None) if response is not None else None
    is_error = (exception is not None) or (isinstance(status_code, int) and status_code >= 400)
    is_slow = isinstance(response_time, (int, float)) and response_time >= SLOW_REQUEST_MS

    # Expected business outcome: already registered should not pollute error-events.
    if _is_already_registered_response(name, status_code, response):
        is_error = False

    if not is_error and not is_slow:
        return

    row: dict[str, Any] = {
        "timestamp": _iso(start_time if isinstance(start_time, (int, float)) else time.time()),
        "request_type": request_type,
        "name": name,
        "url": url,
        "status_code": status_code,
        "response_time_ms": _safe_num(response_time),
        "response_length": _safe_num(response_length),
        "exception": str(exception) if exception is not None else None,
    }
    row.update(_extract_request_inputs(url, response))
    if is_error and isinstance(status_code, int) and status_code >= 400:
        row["response_body"] = _extract_response_body(response)
    with _error_events_lock:
        can_log_error = MAX_LOGGED_EVENTS <= 0 or len(_error_events) < MAX_LOGGED_EVENTS
        can_log_slow = MAX_LOGGED_EVENTS <= 0 or len(_slow_events) < MAX_LOGGED_EVENTS
        if is_error and can_log_error:
            _error_events.append(row)
        if is_slow and can_log_slow:
            _slow_events.append(row)


@events.test_stop.add_listener
def _write_json_results(environment, **kwargs):
    started = _run_started_at_ts
    ended = time.time()
    stamp = time.strftime("%d%m%y_%H%M%S", time.localtime(started or ended))
    results_path = Path(RESULTS_DIR)
    results_path.mkdir(parents=True, exist_ok=True)
    out_file = results_path / f"results_{stamp}.json"

    options = getattr(environment, "parsed_options", None)
    with _error_events_lock:
        error_events = list(_error_events)
        slow_events = list(_slow_events)

    payload = {
        "run": {
            "started_at": _iso(started),
            "ended_at": _iso(ended),
            "duration_seconds": round((ended - started), 3) if started else None,
        },
        "parameters": {
            "host": getattr(environment, "host", None),
            "users": getattr(options, "num_users", None),
            "spawn_rate": getattr(options, "spawn_rate", None),
            "run_time": getattr(options, "run_time", None),
            "headless": bool(getattr(options, "headless", False)) if options else None,
            "only_summary": bool(getattr(options, "only_summary", False)) if options else None,
            "load_competition_id": COMPETITION_ID,
            "load_access_code_set": bool(ACCESS_CODE),
            "load_kp_count": KP_COUNT,
            "load_duration_min": BASE_DURATION_MIN,
            "load_finish_jitter_pct": FINISH_JITTER_PCT,
            "load_far_request_multiplier": FAR_REQUEST_MULTIPLIER,
            "load_no_location_mode": NO_LOCATION_MODE,
            "load_map_burst_seconds": MAP_BURST_SECONDS,
            "load_default_radius_m": DEFAULT_RADIUS_M,
            "load_user_prefix": USER_PREFIX,
            "load_user_count": USER_COUNT,
            "load_session_cookie_secure": SESSION_COOKIE_SECURE,
            "load_slow_request_ms": SLOW_REQUEST_MS,
            "load_max_logged_events": MAX_LOGGED_EVENTS,
            "load_max_body_chars": MAX_BODY_CHARS,
        },
        "stats": _collect_stats(environment),
        "error_events": error_events,
        "slow_events": slow_events,
    }

    out_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[load] results written to {out_file}")


class CompetitorJourneyUser(HttpUser):
    """
    Emulates competitor UI flow without browser:
    1) dev login
    2) join competition by access code
    3) load map in first MAP_BURST_SECONDS
    4) during competition, perform 5x KP queries per KP:
       - KP_COUNT near queries (answer attempts)
       - KP_COUNT*FAR_REQUEST_MULTIPLIER far queries (mostly no match)
    5) users finish in base duration +- jitter
    """

    wait_time = between(0.05, 0.25)

    def __init__(self, environment):
        super().__init__(environment)
        self.vuser = next_user_seq()
        user_idx = ((self.vuser - 1) % USER_COUNT) + 1
        self.user_email = f"{USER_PREFIX}{user_idx:03d}@funo.local"

        self.done = False
        self.events_plan: list[str] = []
        self.next_event_idx = 0
        self.base_sleep = 0.5

        self.cp_by_id: dict[int, Checkpoint] = {}
        self.cp_route: list[int] = []
        self.cp_answered: set[int] = set()
        self.prefetched_items_by_cp: dict[int, dict[str, Any]] = {}

    def on_start(self):
        self._dev_login()
        self._join_competition()
        self._resolve_competition()

        if NO_LOCATION_MODE:
            self._prefetch_open_checkpoints()
        else:
            # All users load map within first MAP_BURST_SECONDS (plus spawn-rate influence)
            time.sleep(random.uniform(0.0, max(0.0, MAP_BURST_SECONDS)))
            self._load_map()

        self._prepare_route_and_plan()

    def _dev_login(self):
        with self.client.post(
            "/api/dev/login",
            json={"email": self.user_email},
            name="POST /api/dev/login",
            catch_response=True,
        ) as r:
            if r.status_code != 200:
                r.failure(f"dev login failed status={r.status_code} body={r.text[:200]}")
                self.done = True

    def _join_competition(self):
        if self.done or not ACCESS_CODE:
            return
        with self.client.post(
            "/api/competitions/register",
            json={"access_code": ACCESS_CODE},
            name="POST /api/competitions/register",
            catch_response=True,
        ) as r:
            # 200 = joined now; already-registered is also acceptable
            if r.status_code == 200:
                return

            if r.status_code in (400, 409):
                already_registered = False
                try:
                    body = r.json()
                    if isinstance(body, dict):
                        err_code = str(body.get("code") or body.get("error_code") or "").upper()
                        err_msg = str(body.get("message") or body.get("detail") or "").upper()
                        already_registered = (
                            "ALREADY_REGISTERED" in err_code
                            or "ALREADY_REGISTERED" in err_msg
                            or "JUBA" in err_msg
                            or "REGISTERED" in err_msg
                        )
                except Exception:
                    txt = r.text.upper()
                    already_registered = (
                        "ALREADY_REGISTERED" in txt
                        or "JUBA" in txt
                        or "REGISTERED" in txt
                    )

                if already_registered:
                    r.success()
                    return

            r.failure(f"register failed status={r.status_code} body={r.text[:250]}")

    def _resolve_competition(self):
        if self.done:
            return
        with self.client.get(
            "/api/competitor/competitions",
            name="GET /api/competitor/competitions",
            catch_response=True,
        ) as r:
            if r.status_code != 200:
                r.failure(f"competitions failed status={r.status_code} body={r.text[:200]}")
                self.done = True
                return
            try:
                payload = r.json()
            except Exception:
                self.done = True
                return

        items = parse_items(payload)
        if not items:
            self.done = True
            return

        if COMPETITION_ID > 0 and any(int(x.get("competition_id") or 0) == COMPETITION_ID for x in items):
            self.competition_id = COMPETITION_ID
        else:
            self.competition_id = int(items[0].get("competition_id") or 0)

        if self.competition_id <= 0:
            self.done = True

    def _load_map(self):
        if self.done:
            return
        with self.client.get(
            f"/api/competitor/map-checkpoints?competition_id={self.competition_id}",
            name="GET /api/competitor/map-checkpoints",
            catch_response=True,
        ) as r:
            if r.status_code != 200:
                r.failure(f"map-checkpoints failed status={r.status_code} body={r.text[:200]}")
                return

            try:
                data = r.json()
            except Exception:
                return

        cps = []
        for i in parse_items(data):
            cps.append(
                Checkpoint(
                    checkpoint_id=int(i.get("checkpoint_id") or 0),
                    title=str(i.get("checkpoint_title") or ""),
                    lat=(float(i["latitude"]) if i.get("latitude") is not None else None),
                    lon=(float(i["longitude"]) if i.get("longitude") is not None else None),
                    radius_m=(float(i["radius_m"]) if i.get("radius_m") is not None else None),
                    question_id=(int(i["question_id"]) if i.get("question_id") is not None else None),
                    question_type=(str(i.get("question_type")) if i.get("question_type") is not None else None),
                )
            )

        # Keep only checkpoint rows with question_id
        cps = [x for x in cps if x.checkpoint_id > 0 and x.question_id]
        self.cp_by_id = {x.checkpoint_id: x for x in cps}

    def _prepare_route_and_plan(self):
        if self.done:
            return

        # Juhuslik läbimisjärjekord
        self.cp_route = list(self.cp_by_id.keys())
        random.shuffle(self.cp_route)

        near_n = min(KP_COUNT, len(self.cp_route))
        far_n = 0 if NO_LOCATION_MODE else KP_COUNT * FAR_REQUEST_MULTIPLIER
        self.events_plan = (["near"] * near_n) + (["far"] * far_n)
        random.shuffle(self.events_plan)

        duration_sec = BASE_DURATION_MIN * 60.0 * random.uniform(
            1.0 - (FINISH_JITTER_PCT / 100.0),
            1.0 + (FINISH_JITTER_PCT / 100.0),
        )
        self.base_sleep = max(0.05, duration_sec / max(1, len(self.events_plan)))

    def _near_geo_for_cp(self, cp: Checkpoint) -> tuple[float, float, float]:
        lat = cp.lat if cp.lat is not None else 59.437
        lon = cp.lon if cp.lon is not None else 24.753
        radius = cp.radius_m if (cp.radius_m and cp.radius_m > 0) else DEFAULT_RADIUS_M
        # send location clearly inside checkpoint range
        effective = max(5.0, radius * 0.6)
        dlat, dlon = random_offset_within_radius_m(effective, lat)
        return lat + dlat, lon + dlon, effective

    def _far_geo(self) -> tuple[float, float, float]:
        # Tallinn baseline + larger random offset so typically outside checkpoints
        base_lat = 59.437
        base_lon = 24.753
        dlat = random.uniform(-0.05, 0.05)
        dlon = random.uniform(-0.08, 0.08)
        return base_lat + dlat, base_lon + dlon, 20.0

    def _open_checkpoints(self, lat: float | None = None, lon: float | None = None, radius: float | None = None):
        url = f"/api/competitor/open-checkpoints?competition_id={self.competition_id}"
        if lat is not None and lon is not None and radius is not None:
            url += f"&latitude={lat:.7f}&longitude={lon:.7f}&radius_m={radius:.2f}"
        return self.client.get(url, name="GET /api/competitor/open-checkpoints")

    def _prefetch_open_checkpoints(self):
        if self.done:
            return
        r = self._open_checkpoints()
        if r.status_code != 200:
            return
        try:
            data = r.json()
            items = parse_items(data)
            self.prefetched_items_by_cp = {
                int(x.get("checkpoint_id") or 0): x
                for x in items
                if int(x.get("checkpoint_id") or 0) > 0 and int(x.get("question_id") or 0) > 0
            }
        except Exception:
            self.prefetched_items_by_cp = {}

    def _submit_for_item(self, item: dict[str, Any]):
        qtype = str(item.get("question_type") or "").upper()
        payload: dict[str, Any] = {
            "competition_id": self.competition_id,
            "checkpoint_id": int(item.get("checkpoint_id") or 0),
            "question_id": int(item.get("question_id") or 0),
        }

        if qtype == "SINGLE_CHOICE":
            options = item.get("options") if isinstance(item.get("options"), list) else []
            if not options:
                return
            picked = random.choice(options)
            payload["selected_option_id"] = int(picked.get("option_id") or 0)
            if payload["selected_option_id"] <= 0:
                return
        else:
            payload["answer_text"] = random.choice(["OK", "NOK"])

        self.client.post(
            "/api/submissions",
            json=payload,
            name="POST /api/submissions",
        )

    @task
    def journey(self):
        if self.done:
            return

        if self.next_event_idx >= len(self.events_plan):
            # This user finished planned journey
            self.done = True
            return

        event_kind = self.events_plan[self.next_event_idx]
        self.next_event_idx += 1

        if event_kind == "near" and self.cp_route:
            target_cp_id = self.cp_route.pop()
            cp = self.cp_by_id.get(target_cp_id)
            if cp is not None:
                if NO_LOCATION_MODE:
                    target = self.prefetched_items_by_cp.get(target_cp_id)
                    if target is not None:
                        self._submit_for_item(target)
                        self.cp_answered.add(target_cp_id)
                    return
                lat, lon, radius = self._near_geo_for_cp(cp)
                r = self._open_checkpoints(lat, lon, radius)
                if r.status_code == 200:
                    try:
                        data = r.json()
                        items = parse_items(data)
                        target = next((x for x in items if int(x.get("checkpoint_id") or 0) == target_cp_id), None)
                        if target is not None:
                            self._submit_for_item(target)
                            self.cp_answered.add(target_cp_id)
                    except Exception:
                        pass
        else:
            lat, lon, radius = self._far_geo()
            self._open_checkpoints(lat, lon, radius)

        time.sleep(max(0.02, random.uniform(self.base_sleep * 0.5, self.base_sleep * 1.5)))
