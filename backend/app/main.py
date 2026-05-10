import base64
import hashlib
import hmac
import json
import os
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


settings = Settings()


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


class SubmitAnswerRequest(BaseModel):
    user_id: int | None = None
    competition_id: int
    checkpoint_id: int
    question_id: int
    answer_text: str | None = None


class SubmitAnswerResponse(BaseModel):
    submission_id: int


class ScoreResponse(BaseModel):
    competition_id: int
    user_id: int
    score: int


class LeaderboardEntry(BaseModel):
    user_id: int
    score: int


class LeaderboardResponse(BaseModel):
    competition_id: int
    items: list[LeaderboardEntry]


def _raise_api_error(status_code: int, code: str, message: str, details: dict[str, Any] | None = None) -> None:
    raise HTTPException(
        status_code=status_code,
        detail=ApiError(code=code, message=message, details=details).model_dump(),
    )


def _extract_oracle_error(payload: Any) -> tuple[str, str]:
    text = str(payload)
    if "ORA-20031" in text:
        return ("INVALID_ACCESS_CODE", "Invalid or inactive access code.")
    if "ORA-20032" in text:
        return ("ACCESS_CODE_LIMIT_REACHED", "Access code usage limit reached.")
    if "ORA-20033" in text:
        return ("ALREADY_REGISTERED", "User is already an active participant in this competition.")
    if "ORA-20060" in text:
        return ("INVALID_SUBMISSION", "Required submission fields are missing.")
    if "ORA-20061" in text:
        return ("NOT_PARTICIPANT", "User is not an active participant in this competition.")
    if "ORA-20010" in text:
        return ("INVALID_GOOGLE_PROFILE", "google_sub and email are required.")
    return ("ORDS_ERROR", "Upstream ORDS request failed.")


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(data: str) -> bytes:
    pad = "=" * ((4 - len(data) % 4) % 4)
    return base64.urlsafe_b64decode(data + pad)


def _session_sign(payload_b64: str) -> str:
    if not settings.session_secret:
        _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "CONFIG_ERROR", "SESSION_SECRET is not set.")
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
            _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "request user_id does not match session user.")
        if x_user_id is not None and x_user_id != session_user_id:
            _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "x-user-id does not match session user.")
        return session_user_id

    if payload_user_id is None:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", "Session is missing. Authenticate via /api/auth/google.")
    if x_user_id is not None and x_user_id != payload_user_id:
        _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "x-user-id does not match request user_id.")
    return payload_user_id


async def _request_ords(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    if not settings.ords_base_url:
        _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "CONFIG_ERROR", "ORDS_BASE_URL is not set.")

    url = f"{settings.ords_base_url}/{path.lstrip('/')}"
    auth = None
    if settings.ords_username and settings.ords_password:
        auth = (settings.ords_username, settings.ords_password)

    try:
        async with httpx.AsyncClient(timeout=settings.http_timeout_seconds) as client:
            if method == "POST":
                response = await client.post(url, json=payload or {}, auth=auth)
            else:
                response = await client.get(url, params=payload or {}, auth=auth)
    except httpx.RequestError as exc:
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "ORDS_UNREACHABLE",
            "Cannot reach ORDS service.",
            {"reason": str(exc)},
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
            "ORDS response is not valid JSON.",
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
            "Cannot verify Google token right now.",
            {"reason": str(exc)},
        )

    if response.status_code >= 400:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "INVALID_GOOGLE_TOKEN", "Google token is invalid or expired.")

    profile = response.json()
    aud = profile.get("aud")
    if settings.google_client_id and aud != settings.google_client_id:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "INVALID_GOOGLE_AUDIENCE", "Google token audience mismatch.")
    return profile


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/health")
def api_health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/auth/google", response_model=GoogleAuthResponse)
async def auth_google(req: GoogleAuthRequest, response: Response) -> GoogleAuthResponse:
    profile = await _verify_google_id_token(req.id_token)
    google_sub = profile.get("sub")
    email = profile.get("email")
    full_name = profile.get("name")
    if not google_sub or not email:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "INVALID_GOOGLE_PROFILE", "Google profile is missing required fields.")

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
            "ORDS did not return user_id.",
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
        _raise_api_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "Endpoint not available.")

    if req.user_id is None and not req.email:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_REQUEST", "Provide user_id or email.")

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
            "ORDS did not return user_id.",
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
            "ORDS did not return competition_id.",
            {"ords_response": ords_response},
        )
    return RegisterCompetitionResponse(competition_id=competition_id)


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
        },
    )
    submission_id = ords_response.get("submission_id")
    if not isinstance(submission_id, int):
        _raise_api_error(
            status.HTTP_502_BAD_GATEWAY,
            "INVALID_ORDS_RESPONSE",
            "ORDS did not return submission_id.",
            {"ords_response": ords_response},
        )
    return SubmitAnswerResponse(submission_id=submission_id)


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
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", "ORDS did not return valid score.")
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
