from __future__ import annotations

import math
import os
import random
import threading
import time
from dataclasses import dataclass
from typing import Any

from locust import HttpUser, between, events, task


# ----------------------
# Config via ENV vars
# ----------------------
COMPETITION_ID = int(os.getenv("LOAD_COMPETITION_ID", "0"))
ACCESS_CODE = os.getenv("LOAD_ACCESS_CODE", "")
KP_COUNT = int(os.getenv("LOAD_KP_COUNT", "50"))
BASE_DURATION_MIN = float(os.getenv("LOAD_DURATION_MIN", "60"))
FINISH_JITTER_PCT = float(os.getenv("LOAD_FINISH_JITTER_PCT", "15"))
FAR_REQUEST_MULTIPLIER = int(os.getenv("LOAD_FAR_REQUEST_MULTIPLIER", "4"))
MAP_BURST_SECONDS = float(os.getenv("LOAD_MAP_BURST_SECONDS", "5"))
DEFAULT_RADIUS_M = float(os.getenv("LOAD_DEFAULT_RADIUS_M", "25"))
USER_PREFIX = os.getenv("LOAD_USER_PREFIX", "T")
USER_COUNT = int(os.getenv("LOAD_USER_COUNT", "200"))

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
    environment.runner.greenlet.spawn(lambda: print(
        f"[load] config competition_id={COMPETITION_ID} kp_count={KP_COUNT} "
        f"duration_min={BASE_DURATION_MIN} far_multiplier={FAR_REQUEST_MULTIPLIER}"
    ))


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

    def on_start(self):
        self._dev_login()
        self._join_competition()
        self._resolve_competition()

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
            # 200 = joined now, 400 with ALREADY_REGISTERED is also acceptable
            if r.status_code == 200:
                return
            if r.status_code == 400 and "ALREADY_REGISTERED" in r.text:
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
        far_n = KP_COUNT * FAR_REQUEST_MULTIPLIER
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

    def _open_checkpoints(self, lat: float, lon: float, radius: float):
        url = (
            f"/api/competitor/open-checkpoints?competition_id={self.competition_id}"
            f"&latitude={lat:.7f}&longitude={lon:.7f}&radius_m={radius:.2f}"
        )
        return self.client.get(url, name="GET /api/competitor/open-checkpoints")

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
