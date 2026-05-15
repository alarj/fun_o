import asyncio
import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException, Request, Response, status
from pydantic import BaseModel, Field

app = FastAPI(title="fun_o API", version="0.3.0")


class Settings:
    app_env: str = os.getenv("APP_ENV", "production").lower()
    ords_base_url: str = os.getenv("ORDS_BASE_URL", "").rstrip("/")
    ords_username: str = os.getenv("ORDS_USERNAME", "")
    ords_password: str = os.getenv("ORDS_PASSWORD", "")
    google_client_id: str = os.getenv("GOOGLE_CLIENT_ID", "")
    http_timeout_seconds: float = float(os.getenv("HTTP_TIMEOUT_SECONDS", "12"))
    session_cookie_name: str = os.getenv("SESSION_COOKIE_NAME", "funo_session")
    session_secret: str = os.getenv("SESSION_SECRET", "")
    session_cookie_secure: bool = os.getenv("SESSION_COOKIE_SECURE", "true").lower() == "true"
    lang_available: list[str] = [x.strip() for x in os.getenv("LANG_AVAILABLE", "et,en").split(",") if x.strip()]
    lang_default: str = os.getenv("LANG_DEFAULT", "et").strip() or "et"


settings = Settings()
i18n_cache: dict[str, dict[str, str]] = {}
map_checkpoints_cache: dict[str, dict[str, Any]] = {}
open_checkpoints_last_response: dict[str, dict[str, Any]] = {}

MAP_CHECKPOINTS_CACHE_TTL_SECONDS = 900.0
OPEN_CHECKPOINTS_THROTTLE_SECONDS = 2.0
ORDS_RETRY_ATTEMPTS = 3
ORDS_RETRY_BACKOFF_SECONDS = (0.2, 0.5, 1.0)


class ApiError(BaseModel):
    code: str
    message: str
    details: dict[str, Any] | None = None


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(min_length=20)


class GoogleAuthResponse(BaseModel):
    user_id: int
    email: str
    full_name: str | None = None
    google_sub: str


class DevLoginRequest(BaseModel):
    user_id: int | None = None
    email: str | None = None


class DevLoginResponse(BaseModel):
    user_id: int


class RegisterCompetitionRequest(BaseModel):
    user_id: int | None = None
    access_code: str = Field(min_length=1, max_length=20)


class RegisterCompetitionResponse(BaseModel):
    competition_id: int


class RegisterOrganizerResponse(BaseModel):
    competition_id: int


class SubmitAnswerRequest(BaseModel):
    user_id: int | None = None
    competition_id: int
    checkpoint_id: int
    question_id: int
    answer_text: str | None = None
    selected_option_id: int | None = None
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None


class SubmitAnswerResponse(BaseModel):
    submission_id: int
    is_correct: bool
    awarded_points: int
    total_score: int


class ScoreResponse(BaseModel):
    competition_id: int
    user_id: int
    score: int


class CompetitorCompetition(BaseModel):
    competition_id: int
    name: str
    starts_at: str | None = None
    ends_at: str | None = None
    use_location: str | None = None


class CompetitorCompetitionsResponse(BaseModel):
    items: list[CompetitorCompetition]


class CompetitorOpenCheckpointsResponse(BaseModel):
    items: list[dict[str, Any]]


class LeaderboardEntry(BaseModel):
    user_id: int
    score: int


class LeaderboardResponse(BaseModel):
    competition_id: int
    items: list[LeaderboardEntry]


class TranslationsResponse(BaseModel):
    lang: str
    default_lang: str
    items: dict[str, str]

class I18nMetaResponse(BaseModel):
    default_lang: str
    available_langs: list[str]


class AdminCreateCheckpointRequest(BaseModel):
    competition_id: int
    title: str
    order_no: int | None = None
    location_hint: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None
    location_required: str | None = None
    created_by: int | None = None


class AdminCreateCheckpointResponse(BaseModel):
    checkpoint_id: int


class AdminCreateQuestionRequest(BaseModel):
    checkpoint_id: int
    question_type: str
    input_type: str | None = None
    input_max_length: int | None = None
    input_pattern: str | None = None
    points: int = 0
    lang_code: str = "et"
    question_text: str
    created_by: int | None = None


class AdminCreateQuestionResponse(BaseModel):
    question_id: int


class AdminCreateQuestionOptionRequest(BaseModel):
    question_id: int
    option_code: str
    order_no: int
    is_correct: str = "N"
    lang_code: str = "et"
    option_text: str
    created_by: int | None = None


class AdminCreateQuestionOptionResponse(BaseModel):
    option_id: int


class AdminCreateQuestionAnswerRequest(BaseModel):
    question_id: int
    answer_value: str
    normalize_mode: str = "EXACT"
    is_correct: str = "Y"
    created_by: int | None = None


class AdminCreateQuestionAnswerResponse(BaseModel):
    answer_id: int


class AdminCompetitionOverviewResponse(BaseModel):
    data: dict[str, Any]


class AdminQuestionsOverviewResponse(BaseModel):
    items: list[dict[str, Any]]


class AdminUpsertAccessCodeRequest(BaseModel):
    competition_id: int
    code_type: str
    code: str
    status: str = "ACTIVE"
    max_uses: int | None = None
    created_by: int | None = None


class AdminUpsertAccessCodeResponse(BaseModel):
    access_code_id: int


class AdminCompetitionsResponse(BaseModel):
    items: list[dict[str, Any]]


class AdminCheckpointsResponse(BaseModel):
    items: list[dict[str, Any]]


class AdminUpdateCheckpointRequest(BaseModel):
    checkpoint_id: int
    title: str
    order_no: int | None = None
    location_hint: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None
    location_required: str | None = None
    updated_by: int | None = None


class AdminDeleteCheckpointRequest(BaseModel):
    checkpoint_id: int
    deleted_by: int | None = None


class AdminUpdateQuestionRequest(BaseModel):
    question_id: int
    checkpoint_id: int
    question_type: str
    input_type: str | None = None
    input_max_length: int | None = None
    input_pattern: str | None = None
    points: int = 0
    lang_code: str = "et"
    question_text: str
    options_json: str | None = None
    answers_json: str | None = None
    updated_by: int | None = None


class AdminDeleteQuestionRequest(BaseModel):
    question_id: int
    deleted_by: int | None = None


class AdminUpdateCompetitionDatesRequest(BaseModel):
    competition_id: int
    starts_at: str | None = None
    ends_at: str | None = None
    updated_by: int | None = None


class AdminUpdateCompetitionMetaRequest(BaseModel):
    competition_id: int
    name: str
    description: str | None = None
    status: str = "ACTIVE"
    use_location: str | None = None
    radius_m: float | None = None
    updated_by: int | None = None


def _raise_api_error(status_code: int, code: str, message: str, details: dict[str, Any] | None = None) -> None:
    raise HTTPException(
        status_code=status_code,
        detail=ApiError(code=code, message=message, details=details).model_dump(),
    )


def _extract_oracle_error(payload: Any) -> tuple[str, str]:
    text = str(payload)
    if "ORA-20031" in text:
        return ("INVALID_ACCESS_CODE", "api.error.invalid_access_code")
    if "ORA-20032" in text:
        return ("ACCESS_CODE_LIMIT_REACHED", "api.error.access_code_limit_reached")
    if "ORA-20033" in text:
        return ("ALREADY_REGISTERED", "api.error.already_registered")
    if "ORA-20060" in text:
        return ("INVALID_SUBMISSION", "api.error.invalid_submission")
    if "ORA-20061" in text:
        return ("NOT_PARTICIPANT", "api.error.not_participant")
    if "ORA-20010" in text:
        return ("INVALID_GOOGLE_PROFILE", "api.error.invalid_google_profile")
    if "ORA-20081" in text:
        return ("INVALID_ORGANIZER_ACCESS_CODE", "api.error.invalid_access_code")
    if "ORA-20082" in text:
        return ("ALREADY_ORGANIZER", "api.error.already_registered")
    if "ORA-20080" in text:
        return ("INVALID_REQUEST", "api.error.invalid_submission")
    if "ORA-20110" in text or "ORA-20115" in text:
        return ("INVALID_QUESTION_PAYLOAD", "api.error.invalid_submission")
    if "ORA-20113" in text:
        return ("CHECKPOINT_HAS_QUESTION", "api.error.invalid_submission")
    if "ORA-20102" in text or "ORA-20103" in text or "ORA-20104" in text:
        return ("INVALID_CHECKPOINT_PAYLOAD", "api.error.invalid_submission")
    if "ORA-02290" in text:
        return ("CONSTRAINT_VIOLATION", "api.error.invalid_submission")
    return ("ORDS_ERROR", "api.error.ords_request_failed")


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(data: str) -> bytes:
    pad = "=" * ((4 - len(data) % 4) % 4)
    return base64.urlsafe_b64decode(data + pad)


def _session_sign(payload_b64: str) -> str:
    if not settings.session_secret:
        _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "CONFIG_ERROR", "api.error.config_session_secret_missing")
    digest = hmac.new(settings.session_secret.encode("utf-8"), payload_b64.encode("utf-8"), hashlib.sha256).digest()
    return _b64url(digest)


def _make_session_token(user_id: int) -> str:
    payload = {"user_id": user_id}
    payload_b64 = _b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = _session_sign(payload_b64)
    return f"{payload_b64}.{sig}"


def _read_session_user_id(request: Request) -> int | None:
    token = request.cookies.get(settings.session_cookie_name)
    if not token or "." not in token:
        return None

    payload_b64, sig = token.split(".", 1)
    expected_sig = _session_sign(payload_b64)
    if not hmac.compare_digest(sig, expected_sig):
        return None

    try:
        payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))
    except Exception:
        return None

    user_id = payload.get("user_id")
    return user_id if isinstance(user_id, int) else None


def _resolve_user_id(request: Request, payload_user_id: int | None, x_user_id: int | None) -> int:
    session_user_id = _read_session_user_id(request)

    if session_user_id is not None:
        if payload_user_id is not None and payload_user_id != session_user_id:
            _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "api.error.user_mismatch")
        if x_user_id is not None and x_user_id != session_user_id:
            _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "api.error.user_mismatch")
        return session_user_id

    if payload_user_id is None:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", "api.error.unauthenticated")
    if x_user_id is not None and x_user_id != payload_user_id:
        _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "api.error.user_mismatch")
    return payload_user_id


async def _request_ords(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    if not settings.ords_base_url:
        _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "CONFIG_ERROR", "api.error.config_ords_base_url_missing")

    url = f"{settings.ords_base_url}/{path.lstrip('/')}"
    auth = None
    if settings.ords_username and settings.ords_password:
        auth = (settings.ords_username, settings.ords_password)

    last_exc: httpx.RequestError | None = None
    response: httpx.Response | None = None
    async with httpx.AsyncClient(timeout=settings.http_timeout_seconds) as client:
        for attempt in range(ORDS_RETRY_ATTEMPTS + 1):
            try:
                if method == "POST":
                    response = await client.post(url, json=payload or {}, auth=auth)
                else:
                    response = await client.get(url, params=payload or {}, auth=auth)
                if response.status_code < 500:
                    break
                if attempt < ORDS_RETRY_ATTEMPTS:
                    backoff = ORDS_RETRY_BACKOFF_SECONDS[min(attempt, len(ORDS_RETRY_BACKOFF_SECONDS) - 1)]
                    await asyncio.sleep(backoff)
                    continue
                break
            except httpx.RequestError as exc:
                last_exc = exc
                if attempt < ORDS_RETRY_ATTEMPTS:
                    backoff = ORDS_RETRY_BACKOFF_SECONDS[min(attempt, len(ORDS_RETRY_BACKOFF_SECONDS) - 1)]
                    await asyncio.sleep(backoff)
                    continue
                _raise_api_error(
                    status.HTTP_502_BAD_GATEWAY,
                    "ORDS_UNREACHABLE",
                    "api.error.ords_unreachable",
                    {"reason": str(exc)},
                )

    if response is None and last_exc is not None:
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "ORDS_UNREACHABLE",
            "api.error.ords_unreachable",
            {"reason": str(last_exc)},
        )

    if response.status_code >= 400:
        code, message = _extract_oracle_error(response.text)
        _raise_api_error(
            status.HTTP_400_BAD_REQUEST if response.status_code < 500 else status.HTTP_502_BAD_GATEWAY,
            code,
            message,
            {"ords_status": response.status_code, "ords_body": response.text[:500]},
        )

    try:
        return response.json()
    except ValueError:
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "ORDS_INVALID_JSON",
            "api.error.ords_invalid_json",
            {"ords_body": response.text[:500]},
        )


async def _post_to_ords(path: str, payload: dict[str, Any]) -> dict[str, Any]:
    return await _request_ords("POST", path, payload)


async def _get_from_ords(path: str, params: dict[str, Any]) -> dict[str, Any]:
    return await _request_ords("GET", path, params)


async def _verify_google_id_token(id_token: str) -> dict[str, Any]:
    token_info_url = "https://oauth2.googleapis.com/tokeninfo"
    try:
        async with httpx.AsyncClient(timeout=settings.http_timeout_seconds) as client:
            response = await client.get(token_info_url, params={"id_token": id_token})
    except httpx.RequestError as exc:
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "GOOGLE_UNREACHABLE",
            "api.error.google_unreachable",
            {"reason": str(exc)},
        )

    if response.status_code >= 400:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "INVALID_GOOGLE_TOKEN", "api.error.invalid_google_token")

    profile = response.json()
    aud = profile.get("aud")
    if settings.google_client_id and aud != settings.google_client_id:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "INVALID_GOOGLE_AUDIENCE", "api.error.invalid_google_audience")
    return profile


async def _load_i18n_cache() -> None:
    i18n_cache.clear()
    for lang in settings.lang_available:
        data = await _get_from_ords(
            "i18n/translations",
            {"lang": lang, "default_lang": settings.lang_default},
        )
        raw_items = data.get("items") if isinstance(data, dict) else None
        if isinstance(raw_items, dict):
            i18n_cache[lang] = {str(k): str(v) for k, v in raw_items.items()}
        else:
            i18n_cache[lang] = {}


def _map_cache_key(*, competition_id: int, user_id: int) -> str:
    return f"{competition_id}:{user_id}"


def _open_checkpoints_key(*, competition_id: int, user_id: int) -> str:
    return f"{competition_id}:{user_id}"


def _purge_expired_map_cache(now: float | None = None) -> None:
    current = now if now is not None else time.monotonic()
    expired_keys: list[str] = []
    for key, value in map_checkpoints_cache.items():
        cached_at = value.get("cached_at")
        if not isinstance(cached_at, float):
            expired_keys.append(key)
            continue
        if current - cached_at > MAP_CHECKPOINTS_CACHE_TTL_SECONDS:
            expired_keys.append(key)
    for key in expired_keys:
        map_checkpoints_cache.pop(key, None)


def _invalidate_competition_cache(competition_id: int | None) -> None:
    if competition_id is None:
        return
    prefix = f"{competition_id}:"
    for key in list(map_checkpoints_cache.keys()):
        if key.startswith(prefix):
            map_checkpoints_cache.pop(key, None)
    for key in list(open_checkpoints_last_response.keys()):
        if key.startswith(prefix):
            open_checkpoints_last_response.pop(key, None)


@app.on_event("startup")
async def startup_event() -> None:
    await _load_i18n_cache()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/health")
def api_health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/i18n/translations", response_model=TranslationsResponse)
async def get_translations(lang: str | None = None) -> TranslationsResponse:
    requested = (lang or settings.lang_default).strip().lower()
    if requested not in i18n_cache:
        # Non-listed language uses default language cache.
        requested = settings.lang_default
    items = i18n_cache.get(requested, i18n_cache.get(settings.lang_default, {}))
    return TranslationsResponse(lang=requested, default_lang=settings.lang_default, items=items)


@app.get("/api/i18n/meta", response_model=I18nMetaResponse)
async def get_i18n_meta() -> I18nMetaResponse:
    langs = [x.strip().lower() for x in settings.lang_available if x and x.strip()]
    default_lang = (settings.lang_default or "et").strip().lower()
    if default_lang not in langs:
        langs = [default_lang] + langs
    return I18nMetaResponse(default_lang=default_lang, available_langs=langs)


@app.post("/api/i18n/reload")
async def reload_i18n_cache() -> dict[str, Any]:
    await _load_i18n_cache()
    return {
        "ok": True,
        "default_lang": settings.lang_default,
        "available_langs": list(i18n_cache.keys()),
    }


@app.post("/api/auth/google", response_model=GoogleAuthResponse)
async def auth_google(req: GoogleAuthRequest, response: Response) -> GoogleAuthResponse:
    profile = await _verify_google_id_token(req.id_token)
    google_sub = profile.get("sub")
    email = profile.get("email")
    full_name = profile.get("name")
    if not google_sub or not email:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "INVALID_GOOGLE_PROFILE", "api.error.invalid_google_profile")

    ords_response = await _post_to_ords(
        "auth/google/upsert",
        {
            "google_sub": google_sub,
            "email": email,
            "full_name": full_name,
        },
    )
    user_id = ords_response.get("user_id")
    if not isinstance(user_id, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_ords_response_user_id",
            {"ords_response": ords_response},
        )

    session_token = _make_session_token(user_id)
    response.set_cookie(
        key=settings.session_cookie_name,
        value=session_token,
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )

    return GoogleAuthResponse(user_id=user_id, email=email, full_name=full_name, google_sub=google_sub)


@app.post("/api/dev/login", response_model=DevLoginResponse)
async def dev_login(req: DevLoginRequest, response: Response) -> DevLoginResponse:
    if settings.app_env != "dev":
        _raise_api_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "api.error.endpoint_not_available")

    if req.user_id is None and not req.email:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_REQUEST", "api.error.dev_login_user_or_email_required")

    payload: dict[str, Any] = {}
    if req.user_id is not None:
        payload["user_id"] = req.user_id
    if req.email:
        payload["email"] = req.email

    ords_response = await _post_to_ords("auth/dev/resolve-user", payload)
    user_id = ords_response.get("user_id")
    if not isinstance(user_id, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_ords_response_user_id",
            {"ords_response": ords_response},
        )

    session_token = _make_session_token(user_id)
    response.set_cookie(
        key=settings.session_cookie_name,
        value=session_token,
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )
    return DevLoginResponse(user_id=user_id)


@app.post("/api/competitions/register", response_model=RegisterCompetitionResponse)
async def register_to_competition(
    req: RegisterCompetitionRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> RegisterCompetitionResponse:
    user_id = _resolve_user_id(request, req.user_id, x_user_id)

    ords_response = await _post_to_ords(
        "competitions/register",
        {
            "user_id": user_id,
            "access_code": req.access_code,
        },
    )
    competition_id = ords_response.get("competition_id")
    if not isinstance(competition_id, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_ords_response_competition_id",
            {"ords_response": ords_response},
        )
    return RegisterCompetitionResponse(competition_id=competition_id)


@app.post("/api/organizers/register", response_model=RegisterOrganizerResponse)
async def register_organizer(
    req: RegisterCompetitionRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> RegisterOrganizerResponse:
    user_id = _resolve_user_id(request, req.user_id, x_user_id)
    ords_response = await _post_to_ords(
        "organizers/register",
        {
            "user_id": user_id,
            "access_code": req.access_code,
        },
    )
    competition_id = ords_response.get("competition_id")
    if not isinstance(competition_id, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_ords_response_competition_id",
            {"ords_response": ords_response},
        )
    return RegisterOrganizerResponse(competition_id=competition_id)


@app.post("/api/submissions", response_model=SubmitAnswerResponse)
async def submit_answer(
    req: SubmitAnswerRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> SubmitAnswerResponse:
    user_id = _resolve_user_id(request, req.user_id, x_user_id)

    ords_response = await _post_to_ords(
        "submissions",
        {
            "user_id": user_id,
            "competition_id": req.competition_id,
            "checkpoint_id": req.checkpoint_id,
            "question_id": req.question_id,
            "answer_text": req.answer_text,
            "selected_option_id": req.selected_option_id,
            "latitude": req.latitude,
            "longitude": req.longitude,
            "radius_m": req.radius_m,
        },
    )
    submission_id = ords_response.get("submission_id")
    is_correct_raw = ords_response.get("is_correct")
    awarded_points = ords_response.get("awarded_points")
    total_score = ords_response.get("total_score")
    if not isinstance(submission_id, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_ords_response_submission_id",
            {"ords_response": ords_response},
        )
    if is_correct_raw not in ("Y", "N"):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_submission",
            {"ords_response": ords_response},
        )
    if not isinstance(awarded_points, int) or not isinstance(total_score, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "api.error.invalid_ords_response_score",
            {"ords_response": ords_response},
        )
    return SubmitAnswerResponse(
        submission_id=submission_id,
        is_correct=(is_correct_raw == "Y"),
        awarded_points=awarded_points,
        total_score=total_score,
    )


@app.get("/api/competitor/competitions", response_model=CompetitorCompetitionsResponse)
async def competitor_competitions(
    request: Request,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorCompetitionsResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    ords_response = await _get_from_ords("competitor/competitions", {"user_id": resolved_user_id})
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else []
    items: list[CompetitorCompetition] = []
    if isinstance(raw_items, list):
        for item in raw_items:
            if not isinstance(item, dict):
                continue
            cid = item.get("competition_id")
            name = item.get("name")
            if isinstance(cid, int) and isinstance(name, str):
                items.append(
                    CompetitorCompetition(
                        competition_id=cid,
                        name=name,
                        starts_at=item.get("starts_at") if isinstance(item.get("starts_at"), str) else None,
                        ends_at=item.get("ends_at") if isinstance(item.get("ends_at"), str) else None,
                        use_location=item.get("use_location") if isinstance(item.get("use_location"), str) else None,
                    )
                )
    return CompetitorCompetitionsResponse(items=items)


@app.get("/api/competitor/open-checkpoints", response_model=CompetitorOpenCheckpointsResponse)
async def competitor_open_checkpoints(
    competition_id: int,
    request: Request,
    latitude: float | None = None,
    longitude: float | None = None,
    radius_m: float | None = None,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorOpenCheckpointsResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    now = time.monotonic()
    key = _open_checkpoints_key(competition_id=competition_id, user_id=resolved_user_id)
    previous = open_checkpoints_last_response.get(key)
    if previous:
        previous_at = previous.get("response_at")
        previous_items = previous.get("items")
        if (
            isinstance(previous_at, float)
            and isinstance(previous_items, list)
            and (now - previous_at) <= OPEN_CHECKPOINTS_THROTTLE_SECONDS
        ):
            return CompetitorOpenCheckpointsResponse(items=previous_items)

    ords_response = await _get_from_ords(
        "competitor/open-checkpoints",
        {
            "competition_id": competition_id,
            "user_id": resolved_user_id,
            "latitude": latitude,
            "longitude": longitude,
            "radius_m": radius_m,
        },
    )
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else []
    items = raw_items if isinstance(raw_items, list) else []
    open_checkpoints_last_response[key] = {"response_at": now, "items": items}
    return CompetitorOpenCheckpointsResponse(items=items)


@app.get("/api/competitor/map-checkpoints", response_model=CompetitorOpenCheckpointsResponse)
async def competitor_map_checkpoints(
    competition_id: int,
    request: Request,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorOpenCheckpointsResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    now = time.monotonic()
    _purge_expired_map_cache(now)
    key = _map_cache_key(competition_id=competition_id, user_id=resolved_user_id)
    cached = map_checkpoints_cache.get(key)
    if cached:
        cached_items = cached.get("items")
        if isinstance(cached_items, list):
            return CompetitorOpenCheckpointsResponse(items=cached_items)

    ords_response = await _get_from_ords(
        "competitor/map-checkpoints",
        {
            "competition_id": competition_id,
            "user_id": resolved_user_id,
        },
    )
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else []
    items = raw_items if isinstance(raw_items, list) else []
    map_checkpoints_cache[key] = {"cached_at": now, "items": items}
    return CompetitorOpenCheckpointsResponse(items=items)


@app.get("/api/results/score", response_model=ScoreResponse)
async def results_score(
    competition_id: int,
    request: Request,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> ScoreResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    ords_response = await _get_from_ords(
        "results/score",
        {
            "competition_id": competition_id,
            "user_id": resolved_user_id,
        },
    )
    score = ords_response.get("score", 0)
    if not isinstance(score, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "api.error.invalid_ords_response_score")
    return ScoreResponse(competition_id=competition_id, user_id=resolved_user_id, score=score)


@app.get("/api/admin/leaderboard", response_model=LeaderboardResponse)
async def admin_leaderboard(
    competition_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> LeaderboardResponse:
    _ = _resolve_user_id(request, None, x_user_id)
    ords_response = await _get_from_ords(
        "organizer/leaderboard",
        {
            "competition_id": competition_id,
        },
    )

    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else None
    if not isinstance(raw_items, list):
        raw_items = []

    items: list[LeaderboardEntry] = []
    for item in raw_items:
        if isinstance(item, dict) and isinstance(item.get("user_id"), int) and isinstance(item.get("score"), int):
            items.append(LeaderboardEntry(user_id=item["user_id"], score=item["score"]))

    return LeaderboardResponse(competition_id=competition_id, items=items)


@app.post("/api/admin/checkpoints", response_model=AdminCreateCheckpointResponse)
async def admin_create_checkpoint(req: AdminCreateCheckpointRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateCheckpointResponse:
    user_id = _resolve_user_id(request, req.created_by, x_user_id)
    payload: dict[str, Any] = {
        "competition_id": req.competition_id,
        "title": req.title,
        "created_by": user_id,
    }
    if req.order_no is not None:
        payload["order_no"] = req.order_no
    if req.location_hint is not None:
        payload["location_hint"] = req.location_hint
    if req.latitude is not None:
        payload["latitude"] = req.latitude
    if req.longitude is not None:
        payload["longitude"] = req.longitude
    if req.radius_m is not None:
        payload["radius_m"] = req.radius_m
    if req.location_required is not None:
        payload["location_required"] = req.location_required

    ords_response = await _post_to_ords(
        "admin/checkpoints",
        payload,
    )
    checkpoint_id = ords_response.get("checkpoint_id")
    if not isinstance(checkpoint_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "api.error.invalid_ords_response")
    _invalidate_competition_cache(req.competition_id)
    return AdminCreateCheckpointResponse(checkpoint_id=checkpoint_id)


@app.post("/api/admin/questions", response_model=AdminCreateQuestionResponse)
async def admin_create_question(req: AdminCreateQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionResponse:
    user_id = _resolve_user_id(request, req.created_by, x_user_id)
    ords_response = await _post_to_ords(
        "admin/questions",
        {
            "checkpoint_id": req.checkpoint_id,
            "question_type": req.question_type,
            "input_type": req.input_type,
            "input_max_length": req.input_max_length,
            "input_pattern": req.input_pattern,
            "points": req.points,
            "lang_code": req.lang_code,
            "question_text": req.question_text,
            "created_by": user_id,
        },
    )
    question_id = ords_response.get("question_id")
    if not isinstance(question_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "api.error.invalid_ords_response")
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return AdminCreateQuestionResponse(question_id=question_id)


@app.post("/api/admin/question-options", response_model=AdminCreateQuestionOptionResponse)
async def admin_create_question_option(req: AdminCreateQuestionOptionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionOptionResponse:
    user_id = _resolve_user_id(request, req.created_by, x_user_id)
    ords_response = await _post_to_ords(
        "admin/question-options",
        {
            "question_id": req.question_id,
            "option_code": req.option_code,
            "order_no": req.order_no,
            "is_correct": req.is_correct,
            "lang_code": req.lang_code,
            "option_text": req.option_text,
            "created_by": user_id,
        },
    )
    option_id = ords_response.get("option_id")
    if not isinstance(option_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "api.error.invalid_ords_response")
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return AdminCreateQuestionOptionResponse(option_id=option_id)


@app.post("/api/admin/question-answers", response_model=AdminCreateQuestionAnswerResponse)
async def admin_create_question_answer(req: AdminCreateQuestionAnswerRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionAnswerResponse:
    user_id = _resolve_user_id(request, req.created_by, x_user_id)
    ords_response = await _post_to_ords(
        "admin/question-answers",
        {
            "question_id": req.question_id,
            "answer_value": req.answer_value,
            "normalize_mode": req.normalize_mode,
            "is_correct": req.is_correct,
            "created_by": user_id,
        },
    )
    answer_id = ords_response.get("answer_id")
    if not isinstance(answer_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "api.error.invalid_ords_response")
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return AdminCreateQuestionAnswerResponse(answer_id=answer_id)


@app.get("/api/admin/competition-overview", response_model=AdminCompetitionOverviewResponse)
async def admin_competition_overview(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionOverviewResponse:
    _ = _resolve_user_id(request, None, x_user_id)
    data = await _get_from_ords("admin/competition-overview", {"competition_id": competition_id})
    return AdminCompetitionOverviewResponse(data=data if isinstance(data, dict) else {})


@app.get("/api/admin/questions-overview", response_model=AdminQuestionsOverviewResponse)
async def admin_questions_overview(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminQuestionsOverviewResponse:
    _ = _resolve_user_id(request, None, x_user_id)
    data = await _get_from_ords("admin/questions-overview", {"competition_id": competition_id})
    raw_items = data.get("items") if isinstance(data, dict) else []
    if not isinstance(raw_items, list):
        raw_items = []

    normalized: list[dict[str, Any]] = []
    for item in raw_items:
        if not isinstance(item, dict):
            continue
        row = dict(item)
        for key in ("options", "answers"):
            value = row.get(key)
            if isinstance(value, str):
                try:
                    row[key] = json.loads(value)
                except Exception:
                    row[key] = []
            elif value is None:
                row[key] = []
            elif not isinstance(value, list):
                row[key] = []
        normalized.append(row)
    return AdminQuestionsOverviewResponse(items=normalized)


@app.post("/api/admin/access-codes", response_model=AdminUpsertAccessCodeResponse)
async def admin_upsert_access_code(req: AdminUpsertAccessCodeRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminUpsertAccessCodeResponse:
    user_id = _resolve_user_id(request, req.created_by, x_user_id)
    ords_response = await _post_to_ords(
        "admin/access-codes",
        {
            "competition_id": req.competition_id,
            "code_type": req.code_type,
            "code": req.code,
            "status": req.status,
            "max_uses": req.max_uses,
            "created_by": user_id,
        },
    )
    access_code_id = ords_response.get("access_code_id")
    if not isinstance(access_code_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "api.error.invalid_ords_response")
    return AdminUpsertAccessCodeResponse(access_code_id=access_code_id)


@app.get("/api/admin/competitions", response_model=AdminCompetitionsResponse)
async def admin_competitions(request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionsResponse:
    user_id = _resolve_user_id(request, None, x_user_id)
    data = await _get_from_ords("admin/competitions", {"user_id": user_id})
    items = data.get("items") if isinstance(data, dict) else []
    return AdminCompetitionsResponse(items=items if isinstance(items, list) else [])


@app.get("/api/admin/checkpoints", response_model=AdminCheckpointsResponse)
async def admin_checkpoints(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCheckpointsResponse:
    _ = _resolve_user_id(request, None, x_user_id)
    data = await _get_from_ords("admin/checkpoints", {"competition_id": competition_id})
    items = data.get("items") if isinstance(data, dict) else []
    return AdminCheckpointsResponse(items=items if isinstance(items, list) else [])


@app.post("/api/admin/checkpoints/update")
async def admin_update_checkpoint(req: AdminUpdateCheckpointRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _resolve_user_id(request, req.updated_by, x_user_id)
    payload: dict[str, Any] = {
        "checkpoint_id": req.checkpoint_id,
        "title": req.title,
        "updated_by": user_id,
    }
    if req.order_no is not None:
        payload["order_no"] = req.order_no
    if req.location_hint is not None:
        payload["location_hint"] = req.location_hint
    if req.latitude is not None:
        payload["latitude"] = req.latitude
    if req.longitude is not None:
        payload["longitude"] = req.longitude
    if req.radius_m is not None:
        payload["radius_m"] = req.radius_m
    if req.location_required is not None:
        payload["location_required"] = req.location_required

    await _post_to_ords(
        "admin/checkpoints/update",
        payload,
    )
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return {"ok": True}


@app.post("/api/admin/checkpoints/delete")
async def admin_delete_checkpoint(req: AdminDeleteCheckpointRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _resolve_user_id(request, req.deleted_by, x_user_id)
    await _post_to_ords(
        "admin/checkpoints/delete",
        {
            "checkpoint_id": req.checkpoint_id,
            "deleted_by": user_id,
        },
    )
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return {"ok": True}


@app.post("/api/admin/questions/update")
async def admin_update_question(req: AdminUpdateQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _resolve_user_id(request, req.updated_by, x_user_id)
    payload: dict[str, Any] = {
        "question_id": req.question_id,
        "checkpoint_id": req.checkpoint_id,
        "question_type": req.question_type,
        "input_type": req.input_type,
        "input_max_length": req.input_max_length,
        "input_pattern": req.input_pattern,
        "points": req.points,
        "lang_code": req.lang_code,
        "question_text": req.question_text,
        "updated_by": user_id,
    }
    # IMPORTANT:
    # options/answers must be sent only when caller explicitly wants to replace them.
    # Sending null would still trigger ORDS "has(...)" and may clear existing rows.
    if req.options_json is not None:
        payload["options_json"] = req.options_json
    if req.answers_json is not None:
        payload["answers_json"] = req.answers_json

    await _post_to_ords(
        "admin/questions/update",
        payload,
    )
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return {"ok": True}


@app.post("/api/admin/questions/delete")
async def admin_delete_question(req: AdminDeleteQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _resolve_user_id(request, req.deleted_by, x_user_id)
    await _post_to_ords(
        "admin/questions/delete",
        {
            "question_id": req.question_id,
            "deleted_by": user_id,
        },
    )
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return {"ok": True}


@app.post("/api/admin/competitions/dates")
async def admin_update_competition_dates(req: AdminUpdateCompetitionDatesRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _resolve_user_id(request, req.updated_by, x_user_id)
    await _post_to_ords(
        "admin/competitions/dates",
        {
            "competition_id": req.competition_id,
            "starts_at": req.starts_at,
            "ends_at": req.ends_at,
            "updated_by": user_id,
        },
    )
    _invalidate_competition_cache(req.competition_id)
    return {"ok": True}


@app.post("/api/admin/competitions/meta")
async def admin_update_competition_meta(req: AdminUpdateCompetitionMetaRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _resolve_user_id(request, req.updated_by, x_user_id)
    await _post_to_ords(
        "admin/competitions/meta",
        {
            "competition_id": req.competition_id,
            "name": req.name,
            "description": req.description,
            "status": req.status,
            "use_location": req.use_location,
            "radius_m": req.radius_m,
            "updated_by": user_id,
        },
    )
    _invalidate_competition_cache(req.competition_id)
    return {"ok": True}



