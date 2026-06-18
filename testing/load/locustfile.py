from __future__ import annotations

import json
import math
import os
import random
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from gevent import sleep as gevent_sleep
from locust import HttpUser, constant, events, task


COMPETITION_ID = int(os.getenv("LOAD_COMPETITION_ID", "41"))
BASE_DURATION_MIN = float(os.getenv("LOAD_DURATION_MIN", "60"))
DURATION_JITTER_PCT = float(os.getenv("LOAD_DURATION_JITTER_PCT", "6"))
MAP_BURST_SECONDS = float(os.getenv("LOAD_MAP_BURST_SECONDS", "5"))
USER_PREFIX = os.getenv("LOAD_USER_PREFIX", "t")
USER_COUNT = int(os.getenv("LOAD_USER_COUNT", "200"))
USER_START_INDEX = int(os.getenv("LOAD_USER_START_INDEX", "1"))
LOG_FILE = os.getenv("LOAD_LOG_FILE", "/mnt/load_logs/fun_o_test_41.jsonl")
MAX_BODY_CHARS = int(os.getenv("LOAD_MAX_BODY_CHARS", "0"))
LANG_CODE = os.getenv("LOAD_LANG_CODE", "et").strip().lower() or "et"
TEXT_OK_PROBABILITY = float(os.getenv("LOAD_TEXT_OK_PROBABILITY", "0.82"))
MAX_NEAR_RETRIES = int(os.getenv("LOAD_MAX_NEAR_RETRIES", "3"))
GPS_ACCURACY_MIN_M = float(os.getenv("LOAD_GPS_ACCURACY_MIN_M", "8"))
GPS_ACCURACY_MAX_M = float(os.getenv("LOAD_GPS_ACCURACY_MAX_M", "22"))
CHECKPOINT_RADIUS_FALLBACK_M = float(os.getenv("LOAD_CHECKPOINT_RADIUS_FALLBACK_M", "50"))
BOOTSTRAP_RETRY_MIN_SECONDS = float(os.getenv("LOAD_BOOTSTRAP_RETRY_MIN_SECONDS", "5"))
BOOTSTRAP_RETRY_MAX_SECONDS = float(os.getenv("LOAD_BOOTSTRAP_RETRY_MAX_SECONDS", "15"))


@dataclass
class Checkpoint:
    checkpoint_id: int
    title: str
    lat: float
    lon: float
    radius_m: float
    order_no: int
    question_id: int | None
    question_type: str | None
    checkpoint_type: str
    checkpoint_interaction: str


@dataclass
class AccessAttempt:
    due_at_s: float
    checkpoint_id: int
    geo_kind: str
    distance_m: float
    retry_no: int = 0


_user_seq = 0
_user_lock = threading.Lock()
_run_started_at_ts: float | None = None
_log_lock = threading.Lock()
_log_path_initialized = False


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def _init_log_path() -> None:
    global _log_path_initialized
    if _log_path_initialized:
        return
    with _log_lock:
        if _log_path_initialized:
            return
        Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
        _log_path_initialized = True


def _append_jsonl(payload: dict[str, Any]) -> None:
    _init_log_path()
    row = {"logged_at": _utc_now_iso(), **payload}
    line = json.dumps(row, ensure_ascii=False, separators=(",", ":"))
    with _log_lock:
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(line)
            fh.write("\n")


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


def offset_from_point(lat: float, lon: float, distance_m: float, angle_rad: float) -> tuple[float, float]:
    dy = math.sin(angle_rad) * distance_m
    dx = math.cos(angle_rad) * distance_m
    return lat + meters_to_lat(dy), lon + meters_to_lon(dx, lat)


def random_geo_near_checkpoint(cp: Checkpoint, distance_m: float) -> tuple[float, float]:
    angle = random.random() * 2.0 * math.pi
    return offset_from_point(cp.lat, cp.lon, distance_m, angle)


def parse_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    items = payload.get("items")
    return items if isinstance(items, list) else []


def parse_json(response: Any) -> dict[str, Any]:
    try:
        data = response.json()
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _response_branch_name(base_name: str, payload: dict[str, Any], status_code: int | None) -> str:
    if base_name == "POST /api/competitor/checkpoint-access":
        ords_called = payload.get("ords_called")
        if isinstance(ords_called, bool):
            return f"{base_name} [{'ords' if ords_called else 'fastapi'}]"
        detail = payload.get("detail")
        if isinstance(detail, dict) and str(detail.get("code") or "").startswith("ORDS_"):
            return f"{base_name} [ords]"
        return f"{base_name} [fastapi]"
    if base_name in {"GET /api/competitor/open-checkpoints", "GET /api/competitor/map-checkpoints"}:
        response_source = str(payload.get("response_source") or "").strip().lower()
        if response_source in {"cache", "ords", "fastapi"}:
            return f"{base_name} [{response_source}]"
        detail = payload.get("detail")
        if isinstance(detail, dict) and str(detail.get("code") or "").startswith("ORDS_"):
            return f"{base_name} [ords]"
    return base_name


def _augment_request_row(row: dict[str, Any], response: Any) -> None:
    path = row.get("path")
    if path not in {
        "/api/competitor/checkpoint-access",
        "/api/competitor/open-checkpoints",
        "/api/competitor/map-checkpoints",
    }:
        return
    payload = parse_json(response)
    if not payload:
        return
    if path == "/api/competitor/checkpoint-access":
        if isinstance(payload.get("ords_called"), bool):
            row["ords_called"] = payload.get("ords_called")
        items = payload.get("items")
        if isinstance(items, list):
            row["checkpoint_access_item_count"] = len(items)
            row["checkpoint_access_open_count"] = sum(
                1 for item in items if isinstance(item, dict) and item.get("can_open") is True
            )
            reason_counts: dict[str, int] = {}
            for item in items:
                if not isinstance(item, dict):
                    continue
                reason = str(item.get("reason") or "unknown")
                reason_counts[reason] = reason_counts.get(reason, 0) + 1
            row["checkpoint_access_reason_counts"] = reason_counts
        detail = payload.get("detail")
        if isinstance(detail, dict):
            row["error_code"] = detail.get("code")
    else:
        response_source = payload.get("response_source")
        if isinstance(response_source, str):
            row["response_source"] = response_source
        items = payload.get("items")
        if isinstance(items, list):
            row["item_count"] = len(items)
        detail = payload.get("detail")
        if isinstance(detail, dict):
            row["error_code"] = detail.get("code")


def maybe_truncate(value: str | None) -> str | None:
    if value is None:
        return None
    if MAX_BODY_CHARS > 0 and len(value) > MAX_BODY_CHARS:
        return value[:MAX_BODY_CHARS] + "...<truncated>"
    return value


def request_inputs(url: str | None, response: Any) -> dict[str, Any]:
    parsed_url = urlparse(url or "")
    query = {k: (v[0] if len(v) == 1 else v) for k, v in parse_qs(parsed_url.query).items()}
    body_text: str | None = None
    req = getattr(response, "request", None) if response is not None else None
    body = getattr(req, "body", None) if req is not None else None
    if body is not None:
        if isinstance(body, bytes):
            body_text = body.decode("utf-8", errors="replace")
        else:
            body_text = str(body)
    return {
        "path": parsed_url.path or None,
        "query_params": query,
        "request_body": maybe_truncate(body_text),
    }


def response_body(response: Any) -> str | None:
    if response is None:
        return None
    return maybe_truncate(str(getattr(response, "text", "")))


def _safe_num(value: Any) -> int | float | None:
    if isinstance(value, (int, float)):
        return value
    return None


def _collect_stats(environment) -> dict[str, Any]:
    total = environment.stats.total
    entries = []
    for (_, _), stat in sorted(environment.stats.entries.items(), key=lambda item: (item[0][0], item[0][1])):
        entries.append(
            {
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
            }
        )
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
    }


@events.test_start.add_listener
def _on_test_start(environment, **kwargs):
    global _run_started_at_ts
    _run_started_at_ts = time.time()
    _append_jsonl(
        {
            "event_type": "run_start",
            "competition_id": COMPETITION_ID,
            "parameters": {
                "host": getattr(environment, "host", None),
                "users": getattr(getattr(environment, "parsed_options", None), "num_users", None),
                "spawn_rate": getattr(getattr(environment, "parsed_options", None), "spawn_rate", None),
                "run_time": getattr(getattr(environment, "parsed_options", None), "run_time", None),
                "load_duration_min": BASE_DURATION_MIN,
                "load_duration_jitter_pct": DURATION_JITTER_PCT,
                "load_map_burst_seconds": MAP_BURST_SECONDS,
                "load_lang_code": LANG_CODE,
                "load_text_ok_probability": TEXT_OK_PROBABILITY,
                "load_log_file": LOG_FILE,
                "load_user_start_index": USER_START_INDEX,
            },
        }
    )


@events.request.add_listener
def _on_request(
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
    row: dict[str, Any] = {
        "event_type": "request",
        "timestamp": datetime.fromtimestamp(start_time, timezone.utc).isoformat(timespec="milliseconds")
        if isinstance(start_time, (int, float))
        else _utc_now_iso(),
        "request_type": request_type,
        "name": name,
        "url": url,
        "status_code": status_code,
        "response_time_ms": _safe_num(response_time),
        "response_length": _safe_num(response_length),
        "exception": str(exception) if exception is not None else None,
    }
    row.update(request_inputs(url, response))
    row["response_body"] = response_body(response)
    _augment_request_row(row, response)
    if isinstance(context, dict):
        row.update(context)
    _append_jsonl(row)


@events.test_stop.add_listener
def _on_test_stop(environment, **kwargs):
    ended = time.time()
    _append_jsonl(
        {
            "event_type": "run_stop",
            "started_at": datetime.fromtimestamp(_run_started_at_ts, timezone.utc).isoformat(timespec="seconds")
            if _run_started_at_ts
            else None,
            "ended_at": datetime.fromtimestamp(ended, timezone.utc).isoformat(timespec="seconds"),
            "duration_seconds": round((ended - _run_started_at_ts), 3) if _run_started_at_ts else None,
            "stats": _collect_stats(environment),
        }
    )


class CompetitorJourneyUser(HttpUser):
    wait_time = constant(0)

    def __init__(self, environment):
        super().__init__(environment)
        self.vuser = next_user_seq()
        user_idx = USER_START_INDEX + ((self.vuser - 1) % USER_COUNT)
        self.user_email = f"{USER_PREFIX}{user_idx:03d}@funo.local"
        self.competition_id = COMPETITION_ID
        self.done = False
        self.run_started_monotonic = 0.0
        self.competition_type = "R"
        self.checkpoints: dict[int, Checkpoint] = {}
        self.route: list[int] = []
        self.completed_checkpoint_ids: set[int] = set()
        self.access_plan: list[AccessAttempt] = []
        self.plan_duration_s = 0.0
        self.plan_far_attempts = 0
        self.plan_near_attempts = 0
        self.plan_extensions = 0
        self.bootstrap_started_monotonic = 0.0

    def on_start(self):
        self.bootstrap_started_monotonic = time.monotonic()
        self._run_bootstrap_step("dev_login", self._dev_login_once)
        if self.done:
            return
        self._run_bootstrap_step("load_competitions", self._resolve_competition_once)
        if self.done:
            return
        gevent_sleep(random.uniform(0.0, max(0.0, MAP_BURST_SECONDS)))
        self._run_bootstrap_step("load_map", self._load_map_once)
        if self.done:
            return
        self._prepare_route_and_plan()
        self.run_started_monotonic = time.monotonic()
        _append_jsonl(
            {
                "event_type": "user_plan",
                "competition_id": self.competition_id,
                "virtual_user": self.vuser,
                "user_email": self.user_email,
                "planned_duration_seconds": round(self.plan_duration_s, 3),
                "planned_checkpoint_count": len(self.route),
                "planned_access_attempt_count": len(self.access_plan),
                "planned_far_attempt_count": self.plan_far_attempts,
                "planned_near_attempt_count": self.plan_near_attempts,
                "bootstrap_elapsed_seconds": round(self.run_started_monotonic - self.bootstrap_started_monotonic, 3),
            }
        )

    def _context(self, logical_action: str, phase: str, **extra: Any) -> dict[str, Any]:
        payload = {
            "competition_id": self.competition_id,
            "virtual_user": self.vuser,
            "user_email": self.user_email,
            "logical_action": logical_action,
            "phase": phase,
        }
        payload.update(extra)
        return payload

    def _run_bootstrap_step(self, step_name: str, step_fn) -> None:
        attempt_no = 0
        while not self.done:
            attempt_no += 1
            if step_fn():
                if attempt_no > 1:
                    _append_jsonl(
                        {
                            "event_type": "bootstrap_step_recovered",
                            "competition_id": self.competition_id,
                            "virtual_user": self.vuser,
                            "user_email": self.user_email,
                            "step_name": step_name,
                            "attempt_no": attempt_no,
                            "elapsed_seconds": round(time.monotonic() - self.bootstrap_started_monotonic, 3),
                        }
                    )
                return
            gevent_sleep(random.uniform(BOOTSTRAP_RETRY_MIN_SECONDS, BOOTSTRAP_RETRY_MAX_SECONDS))

    def _dev_login_once(self) -> bool:
        response = self.client.post(
            "/api/dev/login",
            json={"email": self.user_email},
            name="POST /api/dev/login",
            context=self._context("dev_login", "bootstrap"),
        )
        return response.status_code == 200

    def _resolve_competition_once(self) -> bool:
        response = self.client.get(
            "/api/competitor/competitions",
            name="GET /api/competitor/competitions",
            context=self._context("load_competitions", "bootstrap"),
        )
        if response.status_code != 200:
            return False
        payload = parse_json(response)
        items = parse_items(payload)
        if not items:
            return False
        if any(int(item.get("competition_id") or 0) == COMPETITION_ID for item in items):
            self.competition_id = COMPETITION_ID
            return True
        first_id = int(items[0].get("competition_id") or 0)
        if first_id <= 0:
            return False
        self.competition_id = first_id
        return True

    def _load_map_once(self) -> bool:
        with self.client.get(
            f"/api/competitor/map-checkpoints?competition_id={self.competition_id}",
            name="GET /api/competitor/map-checkpoints",
            context=self._context("load_map", "bootstrap"),
            catch_response=True,
        ) as response:
            payload = parse_json(response)
            response.request_meta["name"] = _response_branch_name(
                "GET /api/competitor/map-checkpoints",
                payload,
                response.status_code,
            )
        if response.status_code != 200:
            return False
        payload_competition_type = str(payload.get("competition_type") or "").strip().upper()
        if payload_competition_type in {"R", "S"}:
            self.competition_type = payload_competition_type
        items = parse_items(payload)
        checkpoints: list[Checkpoint] = []
        for item in items:
            if not isinstance(item, dict):
                continue
            cp_id = int(item.get("checkpoint_id") or 0)
            lat = item.get("latitude")
            lon = item.get("longitude")
            if cp_id <= 0 or not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
                continue
            checkpoints.append(
                Checkpoint(
                    checkpoint_id=cp_id,
                    title=str(item.get("checkpoint_title") or item.get("title") or f"KP {cp_id}"),
                    lat=float(lat),
                    lon=float(lon),
                    radius_m=float(item.get("radius_m") or CHECKPOINT_RADIUS_FALLBACK_M),
                    order_no=int(item.get("checkpoint_order_no") or item.get("order_no") or 0),
                    question_id=int(item["question_id"]) if item.get("question_id") is not None else None,
                    question_type=str(item.get("question_type") or "") or None,
                    checkpoint_type=str(item.get("checkpoint_type") or "NORMAL").strip().upper() or "NORMAL",
                    checkpoint_interaction=str(item.get("checkpoint_interaction") or "QUESTION").strip().upper() or "QUESTION",
                )
            )

        normal_checkpoints = [
            cp
            for cp in checkpoints
            if cp.checkpoint_type == "NORMAL" and cp.checkpoint_interaction == "QUESTION" and cp.question_id
        ]
        self.checkpoints = {cp.checkpoint_id: cp for cp in normal_checkpoints}
        if not self.checkpoints:
            return False
        return True

    def _prepare_route_and_plan(self):
        checkpoint_ids = list(self.checkpoints.keys())
        if self.competition_type == "S":
            checkpoint_ids.sort(key=lambda cp_id: (self.checkpoints[cp_id].order_no, cp_id))
        else:
            random.shuffle(checkpoint_ids)
        self.route = checkpoint_ids

        jitter_factor = random.uniform(
            max(0.80, 1.0 - (DURATION_JITTER_PCT / 100.0)),
            min(1.10, 1.0 + (DURATION_JITTER_PCT / 100.0)),
        )
        self.plan_duration_s = BASE_DURATION_MIN * 60.0 * jitter_factor

        weights = []
        for idx, _cp_id in enumerate(self.route):
            if idx < 5:
                weights.append(random.uniform(0.38, 0.62))
            elif idx < 15:
                weights.append(random.uniform(0.72, 0.98))
            else:
                weights.append(random.uniform(0.95, 1.35))
        total_weight = sum(weights) or 1.0
        durations = [(weight / total_weight) * self.plan_duration_s for weight in weights]

        access_plan: list[AccessAttempt] = []
        elapsed = 0.0
        far_total = 0
        near_total = 0
        for cp_id, duration_s in zip(self.route, durations):
            cp = self.checkpoints[cp_id]
            far_count = random.choice([2, 3, 3, 4, 4, 4, 5, 5, 6])
            far_total += far_count
            near_total += 1
            fractions = sorted(random.uniform(0.08, 0.78) for _ in range(far_count))
            start_distance = random.uniform(180.0, 380.0)
            end_distance = random.uniform(max(cp.radius_m + 8.0, 58.0), max(cp.radius_m + 35.0, 90.0))
            far_distances = []
            for i in range(far_count):
                if far_count == 1:
                    base_distance = start_distance
                else:
                    base_distance = start_distance - ((start_distance - end_distance) * i / (far_count - 1))
                far_distances.append(max(cp.radius_m + 3.0, base_distance + random.uniform(-10.0, 10.0)))
            for fraction, distance_m in zip(fractions, far_distances):
                access_plan.append(
                    AccessAttempt(
                        due_at_s=elapsed + (duration_s * fraction),
                        checkpoint_id=cp_id,
                        geo_kind="far",
                        distance_m=distance_m,
                    )
                )
            near_fraction = max((fractions[-1] + 0.08) if fractions else 0.84, random.uniform(0.84, 0.96))
            near_fraction = min(0.97, near_fraction)
            near_distance = max(4.0, min(cp.radius_m * random.uniform(0.28, 0.64), cp.radius_m - 4.0))
            access_plan.append(
                AccessAttempt(
                    due_at_s=elapsed + (duration_s * near_fraction),
                    checkpoint_id=cp_id,
                    geo_kind="near",
                    distance_m=near_distance,
                )
            )
            elapsed += duration_s

        self.access_plan = sorted(access_plan, key=lambda attempt: (attempt.due_at_s, attempt.checkpoint_id, attempt.geo_kind))
        self.plan_far_attempts = far_total
        self.plan_near_attempts = near_total

    def _geo_accuracy_m(self) -> float:
        return random.uniform(GPS_ACCURACY_MIN_M, GPS_ACCURACY_MAX_M)

    def _checkpoint_by_id(self, checkpoint_id: int) -> Checkpoint | None:
        return self.checkpoints.get(checkpoint_id)

    def _request_checkpoint_access(self, cp: Checkpoint, lat: float, lon: float, geo_kind: str, retry_no: int) -> tuple[Any, dict[str, Any]]:
        payload = {
            "competition_id": self.competition_id,
            "checkpoint_ids": [cp.checkpoint_id],
            "latitude": round(lat, 7),
            "longitude": round(lon, 7),
            "radius_m": round(self._geo_accuracy_m(), 2),
        }
        with self.client.post(
            "/api/competitor/checkpoint-access",
            json=payload,
            name="POST /api/competitor/checkpoint-access",
            context=self._context(
                "checkpoint_access",
                "journey",
                checkpoint_id=cp.checkpoint_id,
                checkpoint_title=cp.title,
                geo_kind=geo_kind,
                simulated_distance_m=round(self._distance_from_cp(cp, lat, lon), 2),
                retry_no=retry_no,
            ),
            catch_response=True,
        ) as response:
            response_payload = parse_json(response)
            response.request_meta["name"] = _response_branch_name(
                "POST /api/competitor/checkpoint-access",
                response_payload,
                response.status_code,
            )
        return response, response_payload

    def _distance_from_cp(self, cp: Checkpoint, lat: float, lon: float) -> float:
        lat1 = math.radians(cp.lat)
        lat2 = math.radians(lat)
        dlat = lat2 - lat1
        dlon = math.radians(lon - cp.lon)
        a = math.sin(dlat / 2.0) ** 2 + math.cos(lat1) * math.cos(lat2) * (math.sin(dlon / 2.0) ** 2)
        c = 2.0 * math.asin(math.sqrt(a))
        return 6_371_000.0 * c

    def _load_open_checkpoint_item(self, cp: Checkpoint, lat: float, lon: float) -> dict[str, Any] | None:
        radius_m = round(self._geo_accuracy_m(), 2)
        with self.client.get(
            f"/api/competitor/open-checkpoints?competition_id={self.competition_id}"
            f"&lang_code={LANG_CODE}"
            f"&latitude={lat:.7f}&longitude={lon:.7f}&radius_m={radius_m:.2f}",
            name="GET /api/competitor/open-checkpoints",
            context=self._context(
                "open_checkpoint",
                "journey",
                checkpoint_id=cp.checkpoint_id,
                checkpoint_title=cp.title,
                geo_kind="near",
            ),
            catch_response=True,
        ) as response:
            payload = parse_json(response)
            response.request_meta["name"] = _response_branch_name(
                "GET /api/competitor/open-checkpoints",
                payload,
                response.status_code,
            )
        if response.status_code != 200:
            return None
        items = parse_items(payload)
        return next((item for item in items if int(item.get("checkpoint_id") or 0) == cp.checkpoint_id), None)

    def _submit_answer(self, cp: Checkpoint, item: dict[str, Any], lat: float, lon: float) -> bool:
        payload: dict[str, Any] = {
            "competition_id": self.competition_id,
            "checkpoint_id": cp.checkpoint_id,
            "question_id": int(item.get("question_id") or cp.question_id or 0),
            "lang_code": LANG_CODE,
            "latitude": round(lat, 7),
            "longitude": round(lon, 7),
            "radius_m": round(self._geo_accuracy_m(), 2),
        }
        question_type = str(item.get("question_type") or cp.question_type or "").strip().upper()
        if question_type == "SINGLE_CHOICE":
            options = item.get("options") if isinstance(item.get("options"), list) else []
            if not options:
                return False
            correct_options = [opt for opt in options if str(opt.get("is_correct") or "").upper() == "Y"]
            if correct_options and random.random() <= TEXT_OK_PROBABILITY:
                chosen = random.choice(correct_options)
            else:
                chosen = random.choice(options)
            payload["selected_option_id"] = int(chosen.get("option_id") or 0)
            if payload["selected_option_id"] <= 0:
                return False
        else:
            payload["answer_text"] = "OK" if random.random() <= TEXT_OK_PROBABILITY else random.choice(["NOK", "VALE", "X"])

        response = self.client.post(
            "/api/submissions",
            json=payload,
            name="POST /api/submissions",
            context=self._context(
                "submit_answer",
                "journey",
                checkpoint_id=cp.checkpoint_id,
                checkpoint_title=cp.title,
                question_type=question_type or "TEXT",
            ),
        )
        return response.status_code == 200

    def _schedule_retry(self, checkpoint_id: int, retry_no: int) -> None:
        if retry_no >= MAX_NEAR_RETRIES:
            return
        due_at_s = (time.monotonic() - self.run_started_monotonic) + random.uniform(10.0, 35.0)
        cp = self._checkpoint_by_id(checkpoint_id)
        if cp is None:
            return
        retry_distance = max(4.0, min(cp.radius_m * random.uniform(0.24, 0.60), cp.radius_m - 4.0))
        self.access_plan.append(
            AccessAttempt(
                due_at_s=due_at_s,
                checkpoint_id=checkpoint_id,
                geo_kind="near",
                distance_m=retry_distance,
                retry_no=retry_no + 1,
            )
        )
        self.access_plan.sort(key=lambda attempt: (attempt.due_at_s, attempt.checkpoint_id, attempt.geo_kind))

    def _time_left_s(self, elapsed_s: float) -> float:
        return max(0.0, self.plan_duration_s - elapsed_s)

    def _extend_plan_for_remaining_time(self, elapsed_s: float) -> bool:
        remaining_ids = [cp_id for cp_id in self.route if cp_id not in self.completed_checkpoint_ids]
        if not remaining_ids:
            return False

        remaining_time_s = self._time_left_s(elapsed_s)
        if remaining_time_s <= 5.0:
            return False

        batch_window_s = min(remaining_time_s, max(120.0, min(600.0, len(remaining_ids) * 12.0)))
        batch_start_s = elapsed_s + random.uniform(0.5, 2.0)
        segment_s = batch_window_s / max(1, len(remaining_ids))
        new_attempts: list[AccessAttempt] = []
        far_total = 0

        for idx, cp_id in enumerate(remaining_ids):
            cp = self.checkpoints[cp_id]
            segment_start_s = batch_start_s + (idx * segment_s)
            far_count = random.choice([4, 5, 5, 5, 6])
            far_total += far_count
            far_fractions = sorted(random.uniform(0.08, 0.76) for _ in range(far_count))
            start_distance = random.uniform(160.0, 340.0)
            end_distance = random.uniform(max(cp.radius_m + 8.0, 55.0), max(cp.radius_m + 30.0, 85.0))
            for far_idx, fraction in enumerate(far_fractions):
                if far_count == 1:
                    base_distance = start_distance
                else:
                    base_distance = start_distance - ((start_distance - end_distance) * far_idx / (far_count - 1))
                new_attempts.append(
                    AccessAttempt(
                        due_at_s=segment_start_s + (segment_s * fraction),
                        checkpoint_id=cp_id,
                        geo_kind="far",
                        distance_m=max(cp.radius_m + 3.0, base_distance + random.uniform(-10.0, 10.0)),
                    )
                )

            near_fraction = max((far_fractions[-1] + 0.08) if far_fractions else 0.84, random.uniform(0.84, 0.96))
            near_fraction = min(0.97, near_fraction)
            new_attempts.append(
                AccessAttempt(
                    due_at_s=segment_start_s + (segment_s * near_fraction),
                    checkpoint_id=cp_id,
                    geo_kind="near",
                    distance_m=max(4.0, min(cp.radius_m * random.uniform(0.28, 0.64), cp.radius_m - 4.0)),
                )
            )

        if not new_attempts:
            return False

        self.access_plan.extend(new_attempts)
        self.access_plan.sort(key=lambda attempt: (attempt.due_at_s, attempt.checkpoint_id, attempt.geo_kind))
        self.plan_extensions += 1
        _append_jsonl(
            {
                "event_type": "plan_extension",
                "competition_id": self.competition_id,
                "virtual_user": self.vuser,
                "user_email": self.user_email,
                "remaining_checkpoint_count": len(remaining_ids),
                "added_attempt_count": len(new_attempts),
                "added_far_attempt_count": far_total,
                "added_near_attempt_count": len(remaining_ids),
                "batch_window_seconds": round(batch_window_s, 3),
                "elapsed_seconds": round(elapsed_s, 3),
                "extension_no": self.plan_extensions,
            }
        )
        return True

    def _run_far_attempt(self, cp: Checkpoint, attempt: AccessAttempt) -> None:
        lat, lon = random_geo_near_checkpoint(cp, attempt.distance_m)
        self._request_checkpoint_access(cp, lat, lon, geo_kind="far", retry_no=attempt.retry_no)

    def _run_near_attempt(self, cp: Checkpoint, attempt: AccessAttempt) -> None:
        lat, lon = random_geo_near_checkpoint(cp, attempt.distance_m)
        response, payload = self._request_checkpoint_access(cp, lat, lon, geo_kind="near", retry_no=attempt.retry_no)
        if response.status_code != 200:
            self._schedule_retry(cp.checkpoint_id, attempt.retry_no)
            return
        items = payload.get("items")
        if not isinstance(items, list):
            self._schedule_retry(cp.checkpoint_id, attempt.retry_no)
            return
        access = next(
            (
                row
                for row in items
                if isinstance(row, dict) and int(row.get("checkpoint_id") or 0) == cp.checkpoint_id
            ),
            None,
        )
        if not isinstance(access, dict) or access.get("can_open") is not True:
            self._schedule_retry(cp.checkpoint_id, attempt.retry_no)
            return
        open_item = self._load_open_checkpoint_item(cp, lat, lon)
        if not isinstance(open_item, dict):
            self._schedule_retry(cp.checkpoint_id, attempt.retry_no)
            return
        if self._submit_answer(cp, open_item, lat, lon):
            self.completed_checkpoint_ids.add(cp.checkpoint_id)
            return
        self._schedule_retry(cp.checkpoint_id, attempt.retry_no)

    @task
    def journey(self):
        if self.done:
            gevent_sleep(1.0)
            return

        elapsed_s = time.monotonic() - self.run_started_monotonic
        all_completed = len(self.completed_checkpoint_ids) >= len(self.route)

        if all_completed:
            self.done = True
            _append_jsonl(
                {
                    "event_type": "user_complete",
                    "competition_id": self.competition_id,
                    "virtual_user": self.vuser,
                    "user_email": self.user_email,
                    "completed_checkpoint_count": len(self.completed_checkpoint_ids),
                    "planned_checkpoint_count": len(self.route),
                    "elapsed_seconds": round(elapsed_s, 3),
                    "completion_reason": "all_checkpoints_completed",
                    "plan_extensions": self.plan_extensions,
                }
            )
            gevent_sleep(1.0)
            return

        if elapsed_s >= self.plan_duration_s:
            self.done = True
            _append_jsonl(
                {
                    "event_type": "user_complete",
                    "competition_id": self.competition_id,
                    "virtual_user": self.vuser,
                    "user_email": self.user_email,
                    "completed_checkpoint_count": len(self.completed_checkpoint_ids),
                    "planned_checkpoint_count": len(self.route),
                    "elapsed_seconds": round(elapsed_s, 3),
                    "completion_reason": "time_elapsed",
                    "plan_extensions": self.plan_extensions,
                }
            )
            gevent_sleep(1.0)
            return

        if not self.access_plan:
            if self._extend_plan_for_remaining_time(elapsed_s):
                gevent_sleep(0.2)
                return
            self.done = True
            _append_jsonl(
                {
                    "event_type": "user_complete",
                    "competition_id": self.competition_id,
                    "virtual_user": self.vuser,
                    "user_email": self.user_email,
                    "completed_checkpoint_count": len(self.completed_checkpoint_ids),
                    "planned_checkpoint_count": len(self.route),
                    "elapsed_seconds": round(elapsed_s, 3),
                    "completion_reason": "time_elapsed_or_no_more_attempts",
                    "plan_extensions": self.plan_extensions,
                }
            )
            gevent_sleep(1.0)
            return

        attempt = self.access_plan[0]
        if attempt.due_at_s > elapsed_s:
            gevent_sleep(min(attempt.due_at_s - elapsed_s, 1.0))
            return

        self.access_plan.pop(0)
        if attempt.checkpoint_id in self.completed_checkpoint_ids:
            return
        cp = self._checkpoint_by_id(attempt.checkpoint_id)
        if cp is None:
            return
        if attempt.geo_kind == "far":
            self._run_far_attempt(cp, attempt)
            return
        self._run_near_attempt(cp, attempt)
