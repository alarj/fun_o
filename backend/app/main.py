import asyncio
import base64
import hashlib
import hmac
import json
import math
import os
import re
import time
from datetime import datetime, timezone
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
    mapycz_api_key: str = os.getenv("MAPYCZ_API_KEY", "")
    maptiler_api_key: str = os.getenv("MAPTILER_API_KEY", "")
    mml_api_key: str = os.getenv("MML_API_KEY", "")
    declination_service_url_template: str | None = os.getenv("DECLINATION_SERVICE_URL_TEMPLATE")
    declination_refresh_days: int = int(os.getenv("DECLINATION_REFRESH_DAYS", "30"))
    http_timeout_seconds: float = float(os.getenv("HTTP_TIMEOUT_SECONDS", "12"))
    session_cookie_name: str = os.getenv("SESSION_COOKIE_NAME", "funo_session")
    competitor_session_cookie_name: str = os.getenv("COMPETITOR_SESSION_COOKIE_NAME", "funo_competitor_session")
    competitor_participation_cookie_name: str = os.getenv("COMPETITOR_PARTICIPATION_COOKIE_NAME", "funo_participation")
    competitor_participation_cookie_ttl_hours: int = int(os.getenv("COMPETITOR_PARTICIPATION_COOKIE_TTL_HOURS", "360"))
    session_secret: str = os.getenv("SESSION_SECRET", "")
    session_cookie_secure: bool = os.getenv("SESSION_COOKIE_SECURE", "true").lower() == "true"
    lang_available: list[str] = [x.strip() for x in os.getenv("LANG_AVAILABLE", "et,en").split(",") if x.strip()]
    lang_default: str = os.getenv("LANG_DEFAULT", "et").strip() or "et"
    promo100_max_total_competitions: int = int(os.getenv("PROMO100_MAX_TOTAL_COMPETITIONS", "100"))


settings = Settings()
i18n_cache: dict[str, dict[str, str]] = {}
map_checkpoints_cache: dict[str, dict[str, Any]] = {}
open_checkpoints_last_response: dict[str, dict[str, Any]] = {}
map_layers_cache: dict[str, Any] = {"loaded_at": 0.0, "items": None}
competitor_map_layers_cache: dict[int, dict[str, Any]] = {}
competitor_terms_cache: dict[str, dict[str, Any]] = {}
background_tasks: set[asyncio.Task[None]] = set()

MAP_CHECKPOINTS_CACHE_TTL_SECONDS = 900.0
OPEN_CHECKPOINTS_THROTTLE_SECONDS = 2.0
ORDS_RETRY_ATTEMPTS = 3
ORDS_RETRY_BACKOFF_SECONDS = (0.2, 0.5, 1.0)
MAP_LAYERS_CACHE_TTL_SECONDS = 31536000.0
MAP_LAYERS_CONFIG_PATH = os.path.join(os.path.dirname(__file__), "map_layers.json")
CONTENT_DEFAULTS_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "frontend_dist", "content")
)
CONTENT_DEFAULTS_DIR_CANDIDATES = [
    x
    for x in [
        os.getenv("CONTENT_DEFAULTS_DIR", "").strip(),
        CONTENT_DEFAULTS_DIR,
        "/app/frontend_dist/content",
        "/frontend_dist/content",
        "/usr/share/nginx/html/content",
    ]
    if x
]
UTC_TS_KEYS = {
    "starts_at",
    "ends_at",
    "created_at",
    "updated_at",
    "submitted_at",
    "joined_at",
    "assigned_at",
    "expires_at",
    "terms_accepted_at",
    "last_submission_at",
    "declination_last_updated",
}
UTC_TS_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$")
ADMIN_COMPETITIONS_TERMS_PATH = "admin/competitions/terms"
ADMIN_CHECKPOINTS_PATH = "admin/checkpoints"
API_ERROR_INVALID_ORDS_RESPONSE = "api.error.invalid_ords_response"
ORACLE_ERROR_MAP: tuple[tuple[tuple[str, ...], tuple[str, str]], ...] = (
    (("ORA-01722",), ("INVALID_NUMBER_FORMAT", "api.error.invalid_request")),
    (("ORA-20031",), ("INVALID_ACCESS_CODE", "api.error.invalid_access_code")),
    (("ORA-20032",), ("ACCESS_CODE_LIMIT_REACHED", "api.error.access_code_limit_reached")),
    (("ORA-20033",), ("ALREADY_REGISTERED", "api.error.already_registered")),
    (("ORA-20060",), ("INVALID_SUBMISSION", "api.error.invalid_submission")),
    (("ORA-20061",), ("NOT_PARTICIPANT", "api.error.not_participant")),
    (("ORA-20062",), ("QUESTION_NOT_FOUND", "api.error.invalid_submission")),
    (("ORA-20063",), ("MISSING_SELECTED_OPTION", "api.error.invalid_submission")),
    (("ORA-20064",), ("MISSING_ANSWER_TEXT", "api.error.invalid_submission")),
    (("ORA-20065", "ORA-20066"), ("INVALID_SUBMISSION_STATE", "api.error.invalid_submission")),
    (("ORA-20067",), ("INVALID_CHECKPOINT_ORDER", "api.error.invalid_checkpoint_order")),
    (("ORA-20010",), ("INVALID_GOOGLE_PROFILE", "api.error.invalid_google_profile")),
    (("ORA-20081",), ("INVALID_ORGANIZER_ACCESS_CODE", "api.error.invalid_access_code")),
    (("ORA-20082",), ("ALREADY_ORGANIZER", "api.error.already_registered")),
    (("ORA-20080",), ("INVALID_REQUEST", "api.error.invalid_submission")),
    (("ORA-20110", "ORA-20115"), ("INVALID_QUESTION_PAYLOAD", "api.error.invalid_submission")),
    (("ORA-20113",), ("CHECKPOINT_HAS_QUESTION", "api.error.invalid_submission")),
    (("ORA-20130",), ("ALIAS_TAKEN", "api.error.alias_taken")),
    (("ORA-20131",), ("ALREADY_PARTICIPANT", "api.error.already_participant")),
    (("ORA-20102", "ORA-20103", "ORA-20104", "ORA-20196", "ORA-20197", "ORA-20198"), ("INVALID_CHECKPOINT_PAYLOAD", "api.error.invalid_submission")),
    (("ORA-02290",), ("CONSTRAINT_VIOLATION", "api.error.invalid_submission")),
)


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


class CompetitorEnsureSessionResponse(BaseModel):
    user_id: int | None = None


class RegisterCompetitionRequest(BaseModel):
    user_id: int | None = None
    access_code: str = Field(min_length=1, max_length=20)


class RegisterCompetitionResponse(BaseModel):
    competition_id: int


class CompetitorSessionParticipant(BaseModel):
    competition_participant_id: int
    competition_id: int
    competition_name: str
    competition_description: str | None = None
    competition_type: str | None = None
    alias_display: str | None = None
    competitor_name: str | None = None
    use_location: str | None = None
    show_competitor_location: str | None = None


class CompetitorSessionResponse(BaseModel):
    authenticated: bool
    user_id: int | None = None
    participant: CompetitorSessionParticipant | None = None


class CompetitorJoinPreviewRequest(BaseModel):
    code: str = Field(min_length=1, max_length=200)
    lang_code: str | None = None
    alias_display: str | None = Field(default=None, max_length=120)


class CompetitorJoinPreviewTerms(BaseModel):
    terms_id: int
    lang_code: str
    terms_text: str


class CompetitorJoinPreviewResponse(BaseModel):
    competition_id: int
    competition_name: str
    competition_description: str | None = None
    already_active_for_user: bool
    terms: CompetitorJoinPreviewTerms | None = None

class CompetitorTermsResponse(BaseModel):
    competition_id: int
    terms: CompetitorJoinPreviewTerms | None = None


class CompetitorJoinCompleteRequest(BaseModel):
    code: str = Field(min_length=1, max_length=200)
    alias_display: str = Field(min_length=1, max_length=120)
    contact_email: str | None = Field(default=None, max_length=320)
    terms_id: int
    terms_lang_code: str = Field(min_length=2, max_length=10)
    accept_terms: bool


class CompetitorJoinCompleteResponse(BaseModel):
    competition_participant_id: int
    competition_id: int
    switched_from_participant_id: int | None = None
    no_change: bool = False


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

class CompetitorProgressResponse(BaseModel):
    competition_id: int
    user_id: int
    total_checkpoints: int
    answered_checkpoints: int
    score: int


class CompetitorCompetition(BaseModel):
    competition_id: int
    name: str
    description: str | None = None
    type: str | None = None
    starts_at: str | None = None
    ends_at: str | None = None
    use_location: str | None = None
    show_competitor_location: str | None = None


class CompetitorCompetitionsResponse(BaseModel):
    items: list[CompetitorCompetition]


class CompetitorOpenCheckpointsResponse(BaseModel):
    declination: float = 0.0
    declination_last_updated: str | None = None
    items: list[dict[str, Any]]

class CompetitorCheckpointAccessRequest(BaseModel):
    competition_id: int
    checkpoint_ids: list[int] = []
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None
    user_id: int | None = None

class CompetitorCheckpointAccessEntry(BaseModel):
    checkpoint_id: int
    can_open: bool
    needs_ords: bool = False
    reason: str | None = None

class CompetitorCheckpointAccessResponse(BaseModel):
    items: list[CompetitorCheckpointAccessEntry]
class CompetitorMySubmissionEntry(BaseModel):
    checkpoint_title: str | None = None
    submission_id: int | None = None
    submitted_at: str | None = None
    awarded_points: int = 0


class CompetitorMySubmissionsResponse(BaseModel):
    items: list[CompetitorMySubmissionEntry]


class CompetitorMySubmissionDetailOption(BaseModel):
    option_text: str | None = None
    is_correct: str = "N"
    is_selected: str = "N"


class CompetitorMySubmissionDetailResponse(BaseModel):
    submission_id: int | None = None
    checkpoint_title: str | None = None
    question_text: str | None = None
    question_type: str | None = None
    points: int = 0
    wrong_points: int = 0
    submitted_at: str | None = None
    awarded_points: int = 0
    competitor_answer: str | None = None
    responders_count: int = 0
    correct_pct: float | None = None
    options: list[CompetitorMySubmissionDetailOption] = []


class LeaderboardEntry(BaseModel):
    user_id: int
    competitor_name: str | None = None
    answered_checkpoints: int | None = None
    score: int
    last_checkpoint: str | None = None
    last_submission_at: str | None = None
    total_elapsed_seconds: int | None = None
    total_distance_m: int | None = None


class LeaderboardResponse(BaseModel):
    competition_id: int
    access_granted: bool = True
    items: list[LeaderboardEntry]

class CheckpointResultEntry(BaseModel):
    checkpoint_id: int | None = None
    checkpoint_title: str | None = None
    last_submission_at: str | None = None
    last_team: str | None = None
    checkpoint_points: int = 0
    correct_count: int = 0
    wrong_count: int = 0


class CheckpointResultsResponse(BaseModel):
    competition_id: int
    access_granted: bool = True
    items: list[CheckpointResultEntry]


class CheckpointResponderEntry(BaseModel):
    user_id: int
    competitor_name: str | None = None
    is_correct: str = "N"


class CheckpointRespondersResponse(BaseModel):
    competition_id: int
    checkpoint_id: int
    access_granted: bool = True
    items: list[CheckpointResponderEntry]

class ParticipantSubmissionEntry(BaseModel):
    submission_id: int | None = None
    checkpoint_title: str | None = None
    submitted_at: str | None = None
    delta_from_prev_seconds: int | None = None
    awarded_points: int = 0
    answer_text: str | None = None
    is_correct: str = "N"


class ParticipantSubmissionsResponse(BaseModel):
    competition_id: int
    user_id: int
    access_granted: bool = True
    total_elapsed_seconds: int | None = None
    total_distance_m: int | None = None
    distance_available: bool = False
    items: list[ParticipantSubmissionEntry]

class SubmissionDetailOption(BaseModel):
    option_text: str | None = None
    is_correct: str = "N"
    is_selected: str = "N"


class SubmissionDetailResponse(BaseModel):
    access_granted: bool = True
    submission_id: int | None = None
    checkpoint_title: str | None = None
    question_text: str | None = None
    question_type: str | None = None
    points: int = 0
    wrong_points: int = 0
    submitted_at: str | None = None
    awarded_points: int = 0
    competitor_answer: str | None = None
    options: list[SubmissionDetailOption] = []


class TranslationsResponse(BaseModel):
    lang: str
    default_lang: str
    items: dict[str, str]

class I18nMetaResponse(BaseModel):
    default_lang: str
    available_langs: list[str]


class IntroContentResponse(BaseModel):
    lang_code: str | None = None
    html: str


class GoogleClientConfigResponse(BaseModel):
    client_id: str | None = None
    enabled: bool


class MapLayerEntry(BaseModel):
    code: str
    label: str
    url_template: str
    attribution: str
    max_zoom: int = 19
    min_zoom: int = 0
    tms: bool = False
    tile_size: int | None = None
    layer_type: str = "xyz"
    wms_layers: str | None = None
    wms_format: str | None = None
    wms_transparent: bool | None = None
    wms_version: str | None = None
    wmts_matrix_set: str | None = None
    wmts_zoom_offset: int | None = None
    fallback_url_template: str | None = None
    fallback_tile_size: int | None = None
    fallback_wmts_matrix_set: str | None = None
    fallback_wmts_zoom_offset: int | None = None
    fallback_zoom_threshold: int | None = None
    crs: str | None = None
    participant_default: bool = False


class MapLayersResponse(BaseModel):
    items: list[MapLayerEntry]


class CompetitorMapLayersResponse(BaseModel):
    competition_id: int
    items: list[MapLayerEntry]


class AdminCompetitionMapLayersResponse(BaseModel):
    competition_id: int
    layer_codes: list[str]


class AdminCompetitionMapLayersUpdateRequest(BaseModel):
    competition_id: int
    layer_codes: list[str] = []


class SessionInfoResponse(BaseModel):
    authenticated: bool
    user_id: int | None = None
    auth_provider: str | None = None
    email: str | None = None
    full_name: str | None = None


class AdminCreateCheckpointRequest(BaseModel):
    competition_id: int
    title: str
    checkpoint_type: str | None = None
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
    wrong_points: int = 0
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


class SuperAdminCreateCompetitionRequest(BaseModel):
    name: str
    description: str | None = None


class SuperAdminCreateCompetitionResponse(BaseModel):
    competition_id: int
    organizer_code: str


class AdminPromoBootstrapResponse(BaseModel):
    attempted: bool
    created: bool
    competition_id: int | None = None


class SuperAdminCopyCompetitionRequest(BaseModel):
    source_competition_id: int
    copy_questions: str = "N"
    copy_organizers: str = "N"


class SuperAdminRemoveOrganizerRequest(BaseModel):
    competition_id: int
    user_id: int

class SuperAdminTranslationItem(BaseModel):
    translation_key: str
    lang_code: str
    text_value: str | None = None
    is_deleted: bool = False
    updated_at: str | None = None

class SuperAdminTranslationsResponse(BaseModel):
    items: list[SuperAdminTranslationItem]

class SuperAdminTranslationUpsertRequest(BaseModel):
    translation_key: str = Field(min_length=1, max_length=300)
    lang_code: str = Field(min_length=2, max_length=10)
    text_value: str = Field(min_length=1, max_length=4000)

class SuperAdminTranslationDeleteRequest(BaseModel):
    translation_key: str = Field(min_length=1, max_length=300)
    lang_code: str = Field(min_length=2, max_length=10)


class SuperAdminSessionResponse(BaseModel):
    ok: bool
    user_id: int


class AdminCheckpointsResponse(BaseModel):
    items: list[dict[str, Any]]


class AdminUpdateCheckpointRequest(BaseModel):
    competition_id: int
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
    competition_id: int
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
    wrong_points: int = 0
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
    type: str = "R"
    status: str = "ACTIVE"
    use_location: str | None = None
    show_competitor_location: str | None = None
    radius_m: float | None = None
    updated_by: int | None = None


class AdminCompetitionTermsResponse(BaseModel):
    competition_id: int
    lang_code: str
    terms_id: int | None = None
    terms_text: str = ""


class AdminCompetitionTermsUpdateRequest(BaseModel):
    competition_id: int
    lang_code: str
    terms_text: str


def _raise_api_error(
    status_code: int,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> None:
    raise HTTPException(
        status_code=status_code,
        headers=headers,
        detail=ApiError(code=code, message=message, details=details).model_dump(),
    )


def _normalize_ords_payload_datetimes(value: Any, key_hint: str | None = None) -> Any:
    if isinstance(value, dict):
        return {k: _normalize_ords_payload_datetimes(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [_normalize_ords_payload_datetimes(v, key_hint) for v in value]
    if isinstance(value, str) and key_hint in UTC_TS_KEYS and UTC_TS_PATTERN.match(value):
        return f"{value}Z"
    return value


def _extract_oracle_error(payload: Any) -> tuple[str, str]:
    text = str(payload)
    if "ORA-00001" in text and "UX_SUBMISSIONS_COMP_USER_CP_Q" in text.upper():
        return ("DUPLICATE_SUBMISSION", "api.error.duplicate_submission")
    for ora_codes, mapped_error in ORACLE_ERROR_MAP:
        if any(ora_code in text for ora_code in ora_codes):
            return mapped_error
    if "ORA-00001" in text and "UX_ACTIVE_CP_ALIAS_CI" in text.upper():
        return ("ALIAS_TAKEN", "api.error.alias_taken")
    return ("ORDS_ERROR", "api.error.ords_request_failed")


def _superadmin_translations_params(
    lang: str | None,
    prefix: str | None,
    include_deleted: str | None,
) -> dict[str, Any]:
    params: dict[str, Any] = {}
    if lang:
        params["lang"] = lang.strip().lower()
    if prefix:
        params["prefix"] = prefix.strip()
    if include_deleted:
        params["include_deleted"] = include_deleted.strip().upper()
    return params


def _to_superadmin_translation_item(row: dict[str, Any]) -> SuperAdminTranslationItem:
    return SuperAdminTranslationItem(
        translation_key=str(row.get("translation_key") or ""),
        lang_code=str(row.get("lang_code") or ""),
        text_value=str(row.get("text_value")) if row.get("text_value") is not None else None,
        is_deleted=str(row.get("is_deleted") or "N").upper() == "Y",
        updated_at=str(row.get("updated_at")) if row.get("updated_at") is not None else None,
    )


def _resolve_effective_lang(lang_code: str | None) -> str:
    effective_lang = (lang_code or settings.lang_default or "et").strip().lower()
    if effective_lang not in settings.lang_available:
        effective_lang = settings.lang_default
    return effective_lang


async def _fetch_competition_terms(competition_id: int, lang_code: str) -> dict[str, Any]:
    return await _get_from_ords(
        ADMIN_COMPETITIONS_TERMS_PATH,
        {
            "competition_id": competition_id,
            "lang_code": lang_code,
        },
    )


def _should_insert_default_terms(terms: dict[str, Any] | None, effective_lang: str) -> bool:
    terms_text = terms.get("terms_text") if isinstance(terms, dict) else ""
    terms_lang = str(terms.get("lang_code") or "").strip().lower() if isinstance(terms, dict) else ""
    return (not isinstance(terms_text, str) or not terms_text.strip()) or terms_lang != effective_lang


def _read_default_terms_html(lang_code: str) -> str:
    lang = (lang_code or settings.lang_default or "et").strip().lower()
    if not lang:
        lang = "et"
    filename = f"default_{lang}.html"
    for base_dir in CONTENT_DEFAULTS_DIR_CANDIDATES:
        path = os.path.join(base_dir, filename)
        try:
            with open(path, "r", encoding="utf-8-sig") as f:
                content = f.read()
            if content.strip():
                return content
        except Exception:
            continue
    return ""


def _read_content_html_with_fallback(prefix: str, lang_code: str | None) -> tuple[str | None, str]:
    requested = (lang_code or "").strip().lower()
    candidates: list[str] = []
    for candidate in [
        requested,
        (settings.lang_default or "et").strip().lower(),
        "et",
        "en",
        *[str(x).strip().lower() for x in settings.lang_available],
    ]:
        if candidate and candidate not in candidates:
            candidates.append(candidate)

    for lang in candidates:
        filename = f"{prefix}_{lang}.html"
        for base_dir in CONTENT_DEFAULTS_DIR_CANDIDATES:
            path = os.path.join(base_dir, filename)
            try:
                with open(path, "r", encoding="utf-8-sig") as f:
                    content = f.read()
                if content.strip():
                    return (lang, content)
            except Exception:
                continue
    return (None, "")


async def _ensure_default_terms_for_competition(competition_id: int) -> None:
    if not isinstance(competition_id, int):
        return
    for lang in settings.lang_available:
        default_html = _read_default_terms_html(lang)
        if not default_html.strip():
            continue
        try:
            await _post_to_ords(
                ADMIN_COMPETITIONS_TERMS_PATH,
                {
                    "competition_id": competition_id,
                    "lang_code": lang,
                    "terms_text": default_html,
                    "updated_by": None,
                },
            )
        except Exception:
            continue


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


def _make_signed_token(payload: dict[str, Any]) -> str:
    payload_b64 = _b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = _session_sign(payload_b64)
    return f"{payload_b64}.{sig}"


def _make_session_token(user_id: int) -> str:
    return _make_signed_token({"user_id": user_id})


def _make_session_token_for_provider(user_id: int, auth_provider: str) -> str:
    return _make_signed_token({"user_id": user_id, "auth_provider": auth_provider})


def _make_competitor_participation_token(competition_participant_id: int) -> str:
    return _make_signed_token({"competition_participant_id": competition_participant_id})


def _read_session_payload(request: Request) -> dict[str, Any] | None:
    return _read_session_payload_from_cookie(request, settings.session_cookie_name)


def _read_competitor_session_payload(request: Request) -> dict[str, Any] | None:
    return _read_session_payload_from_cookie(request, settings.competitor_session_cookie_name)


def _read_competitor_participation_payload(request: Request) -> dict[str, Any] | None:
    return _read_session_payload_from_cookie(request, settings.competitor_participation_cookie_name)


def _read_session_payload_from_cookie(request: Request, cookie_name: str) -> dict[str, Any] | None:
    token = request.cookies.get(cookie_name)
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

    if not isinstance(payload, dict):
        return None
    return payload


def _read_session_user_id(request: Request) -> int | None:
    payload = _read_session_payload(request)
    if payload is None:
        return None
    user_id = payload.get("user_id")
    return user_id if isinstance(user_id, int) else None


def _read_competitor_session_user_id(request: Request) -> int | None:
    payload = _read_competitor_session_payload(request)
    if payload is None:
        return None
    user_id = payload.get("user_id")
    return user_id if isinstance(user_id, int) else None


def _read_competitor_participation_id(request: Request) -> int | None:
    payload = _read_competitor_participation_payload(request)
    if payload is not None:
        participant_id = payload.get("competition_participant_id")
        if isinstance(participant_id, int):
            return participant_id
    # Fallback for environments where only one Set-Cookie header is preserved by proxy.
    session_payload = _read_competitor_session_payload(request)
    if session_payload is None:
        return None
    participant_id = session_payload.get("competition_participant_id")
    return participant_id if isinstance(participant_id, int) else None


def _resolve_user_id(request: Request, payload_user_id: int | None, x_user_id: int | None) -> int:
    session_user_id = _read_competitor_session_user_id(request)
    if session_user_id is None:
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


def _require_google_session_user(request: Request, x_user_id: int | None = None) -> int:
    payload = _read_session_payload(request)
    if payload is None:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", "api.error.unauthenticated")

    session_user_id = payload.get("user_id")
    if not isinstance(session_user_id, int):
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", "api.error.unauthenticated")

    if payload.get("auth_provider") != "google":
        _raise_api_error(status.HTTP_403_FORBIDDEN, "GOOGLE_AUTH_REQUIRED", "api.error.unauthenticated")

    if x_user_id is not None and x_user_id != session_user_id:
        _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "api.error.user_mismatch")

    return session_user_id


def _resolve_ui_lang(lang_code: str | None) -> str:
    effective_lang = (lang_code or settings.lang_default or "et").strip().lower()
    if effective_lang not in settings.lang_available:
        effective_lang = settings.lang_default
    return effective_lang


async def _require_system_owner_session_user(request: Request, x_user_id: int | None = None) -> int:
    user_id = _require_google_session_user(request, x_user_id)
    role_resp = await _get_from_ords(
        "auth/has-role",
        {"user_id": user_id, "role_code": "SYSTEM_OWNER"},
    )
    has_role = role_resp.get("has_role") if isinstance(role_resp, dict) else None
    if str(has_role).upper() != "Y":
        _raise_api_error(status.HTTP_403_FORBIDDEN, "FORBIDDEN", "api.error.unauthenticated")
    return user_id


async def _request_ords(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:  # NOSONAR
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
        if response.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
            retry_after = response.headers.get("Retry-After")
            hdrs = {"Retry-After": retry_after} if retry_after else None
            _raise_api_error(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "ORDS_RATE_LIMITED",
                "api.error.ords_rate_limited",
                {"ords_status": response.status_code, "ords_body": response.text[:500]},
                headers=hdrs,
            )
        code, message = _extract_oracle_error(response.text)
        _raise_api_error(
            status.HTTP_400_BAD_REQUEST if response.status_code < 500 else status.HTTP_502_BAD_GATEWAY,
            code,
            message,
            {"ords_status": response.status_code, "ords_body": response.text[:500]},
        )

    try:
        payload_json = response.json()
        return _normalize_ords_payload_datetimes(payload_json)
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


def _fallback_map_layers() -> list[dict[str, Any]]:
    return [
        {
            "code": "osm",
            "label": "OpenStreetMap",
            "url_template": "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            "attribution": "&copy; OpenStreetMap contributors",
            "max_zoom": 19,
            "min_zoom": 0,
            "participant_default": True,
        }
    ]


def _load_map_layers_config() -> list[dict[str, Any]]:  # NOSONAR
    now = time.monotonic()
    cached_items = map_layers_cache.get("items")
    cached_at = map_layers_cache.get("loaded_at")
    if isinstance(cached_items, list) and isinstance(cached_at, float):
        if now - cached_at <= MAP_LAYERS_CACHE_TTL_SECONDS:
            return cached_items

    items: list[dict[str, Any]] = []
    try:
        # Accept both UTF-8 and UTF-8 with BOM, because Windows editors may write BOM.
        with open(MAP_LAYERS_CONFIG_PATH, "r", encoding="utf-8-sig") as fh:
            raw = json.load(fh)
        raw_items = raw.get("items") if isinstance(raw, dict) else None
        if isinstance(raw_items, list):
            for item in raw_items:
                if not isinstance(item, dict):
                    continue
                code = str(item.get("code", "")).strip()
                label = str(item.get("label", "")).strip()
                url_template = str(item.get("url_template", "")).strip()
                attribution = str(item.get("attribution", "")).strip()
                enabled = item.get("enabled", True)
                if isinstance(enabled, str):
                    enabled = enabled.strip().lower() in ("1", "true", "y", "yes")
                else:
                    enabled = bool(enabled)
                if not enabled:
                    continue
                if not code or not label or not url_template:
                    continue
                url_template = url_template.replace("{MAPYCZ_API_KEY}", settings.mapycz_api_key.strip())
                url_template = url_template.replace("{MAPTILER_API_KEY}", settings.maptiler_api_key.strip())
                url_template = url_template.replace("{MML_API_KEY}", settings.mml_api_key.strip())
                if "{MAPYCZ_API_KEY}" in str(item.get("url_template", "")) and not settings.mapycz_api_key.strip():
                    continue
                if "{MAPTILER_API_KEY}" in str(item.get("url_template", "")) and not settings.maptiler_api_key.strip():
                    continue
                if "{MML_API_KEY}" in str(item.get("url_template", "")) and not settings.mml_api_key.strip():
                    continue
                participant_default = item.get("participant_default", False)
                if isinstance(participant_default, str):
                    participant_default = participant_default.strip().lower() in ("1", "true", "y", "yes")
                else:
                    participant_default = bool(participant_default)
                items.append(
                    {
                        "code": code,
                        "label": label,
                        "url_template": url_template,
                        "attribution": attribution or "&copy;",
                        "max_zoom": int(item.get("max_zoom", 19)),
                        "min_zoom": int(item.get("min_zoom", 0)),
                        "tms": bool(item.get("tms", False)),
                        "tile_size": int(item.get("tile_size", 0)) or None,
                        "layer_type": str(item.get("layer_type", "xyz")).strip().lower() or "xyz",
                        "wms_layers": str(item.get("wms_layers", "")).strip() or None,
                        "wms_format": str(item.get("wms_format", "")).strip() or None,
                        "wms_transparent": bool(item.get("wms_transparent", False)),
                        "wms_version": str(item.get("wms_version", "")).strip() or None,
                        "wmts_matrix_set": str(item.get("wmts_matrix_set", "")).strip() or None,
                        "wmts_zoom_offset": int(item.get("wmts_zoom_offset", 0)) if item.get("wmts_zoom_offset") is not None else None,
                        "fallback_url_template": str(item.get("fallback_url_template", "")).strip() or None,
                        "fallback_tile_size": int(item.get("fallback_tile_size", 0)) or None,
                        "fallback_wmts_matrix_set": str(item.get("fallback_wmts_matrix_set", "")).strip() or None,
                        "fallback_wmts_zoom_offset": int(item.get("fallback_wmts_zoom_offset", 0)) if item.get("fallback_wmts_zoom_offset") is not None else None,
                        "fallback_zoom_threshold": int(item.get("fallback_zoom_threshold", 0)) if item.get("fallback_zoom_threshold") is not None else None,
                        "crs": str(item.get("crs", "")).strip() or None,
                        "participant_default": participant_default,
                    }
                )
    except Exception:
        items = []

    if not items:
        items = _fallback_map_layers()
    map_layers_cache["items"] = items
    map_layers_cache["loaded_at"] = now
    return items


def _map_cache_key(*, competition_id: int, user_id: int) -> str:
    return f"{competition_id}:{user_id}"


def _open_checkpoints_key(*, competition_id: int, user_id: int) -> str:
    return f"{competition_id}:{user_id}"


def _open_checkpoints_signature(latitude: float | None, longitude: float | None, radius_m: float | None) -> str:
    def _fmt(v: float | None) -> str:
        if not isinstance(v, (int, float)):
            return "none"
        return f"{float(v):.6f}"

    return f"{_fmt(latitude)}|{_fmt(longitude)}|{_fmt(radius_m)}"


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
    competitor_map_layers_cache.pop(competition_id, None)
    for key in list(open_checkpoints_last_response.keys()):
        if key.startswith(prefix):
            open_checkpoints_last_response.pop(key, None)


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius_m = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2.0) ** 2
    return 2.0 * earth_radius_m * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def _normalize_competition_type(raw: Any) -> str:
    value = str(raw or "R").strip().upper()
    return "S" if value == "S" else "R"


def _normalize_checkpoint_type(raw: Any) -> str:
    value = str(raw or "NORMAL").strip().upper()
    if value in {"START", "FINISH"}:
        return value
    return "NORMAL"


def _normalize_checkpoint_title(raw: Any) -> str:
    return str(raw or "").strip()


def _truncate_competitor_map_title_for_r(title: str) -> str:
    return title if len(title) <= 8 else f"{title[:5]}..."


def _truncate_competitor_map_title_for_s(title: str) -> str:
    return title[:5]


def _build_competitor_checkpoint_map_label(
    checkpoint: dict[str, Any],
    competition_type: str,
) -> str | None:
    cp_type = _normalize_checkpoint_type(checkpoint.get("checkpoint_type"))
    if cp_type != "NORMAL":
        return None

    title = _normalize_checkpoint_title(checkpoint.get("checkpoint_title"))
    if not title:
        return None

    if competition_type == "S":
        try:
            order_no = int(checkpoint.get("checkpoint_order_no"))
        except (TypeError, ValueError):
            return None
        return f"{order_no} - {_truncate_competitor_map_title_for_s(title)}"

    return _truncate_competitor_map_title_for_r(title)


def _enrich_competitor_map_checkpoint_items(raw_items: list[Any]) -> list[Any]:
    competition_type = _normalize_competition_type(
        next(
            (
                row.get("competition_type")
                for row in raw_items
                if isinstance(row, dict) and row.get("competition_type") is not None
            ),
            "R",
        )
    )
    enriched: list[Any] = []
    for row in raw_items:
        if not isinstance(row, dict):
            enriched.append(row)
            continue
        item = dict(row)
        item["checkpoint_map_label"] = _build_competitor_checkpoint_map_label(item, competition_type)
        enriched.append(item)
    return enriched


def _ordered_checkpoint_id_from_map_items(map_items: list[dict[str, Any]]) -> int | None:
    pending: list[tuple[int, int]] = []
    for row in map_items:
        cp_type = _normalize_checkpoint_type(row.get("checkpoint_type"))
        if cp_type != "NORMAL":
            continue
        if str(row.get("is_answered", "N")).upper() == "Y":
            continue
        cp_id = row.get("checkpoint_id")
        if not isinstance(cp_id, int):
            continue
        try:
            order_no = int(row.get("checkpoint_order_no"))
        except (TypeError, ValueError):
            order_no = 9999
        pending.append((order_no, cp_id))
    if not pending:
        return None
    pending.sort()
    return pending[0][1]


def _parse_utc_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _format_declination_service_url(latitude: float, longitude: float, date_value: datetime) -> str:
    template = (settings.declination_service_url_template or "").strip()
    return template.format(
        latitude=f"{latitude:.6f}",
        longitude=f"{longitude:.6f}",
        altitude="0",
        date=date_value.date().isoformat(),
    )


def _declination_refresh_needed(overview: dict[str, Any]) -> bool:
    if str(overview.get("status", "")).upper() != "ACTIVE":
        return False
    if str(overview.get("use_location", "N")).upper() != "Y":
        return False

    current_declination = overview.get("declination")
    current_last_updated = _parse_utc_datetime(overview.get("declination_last_updated"))
    refresh_days = max(1, int(settings.declination_refresh_days))
    needs_refresh = not isinstance(current_declination, (int, float)) or current_last_updated is None
    if not needs_refresh and current_last_updated is not None:
        age_days = (datetime.now(timezone.utc) - current_last_updated).days
        needs_refresh = age_days >= refresh_days
    return needs_refresh


def _extract_checkpoint_coords(checkpoints_data: dict[str, Any]) -> list[tuple[float, float]]:
    raw_checkpoints = checkpoints_data.get("items") if isinstance(checkpoints_data, dict) else []
    if not isinstance(raw_checkpoints, list):
        return []

    coords: list[tuple[float, float]] = []
    for item in raw_checkpoints:
        if not isinstance(item, dict):
            continue
        lat = item.get("latitude")
        lon = item.get("longitude")
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
            coords.append((float(lat), float(lon)))
    return coords


def _average_checkpoint_coord(coords: list[tuple[float, float]]) -> tuple[float, float] | None:
    if not coords:
        return None
    avg_lat = sum(lat for lat, _ in coords) / len(coords)
    avg_lon = sum(lon for _, lon in coords) / len(coords)
    return avg_lat, avg_lon


async def _fetch_declination_from_service(latitude: float, longitude: float) -> float | None:
    if not (settings.declination_service_url_template or "").strip():
        return None
    url = _format_declination_service_url(latitude, longitude, datetime.now(timezone.utc))
    try:
        async with httpx.AsyncClient(timeout=settings.http_timeout_seconds) as client:
            response = await client.get(url)
            response.raise_for_status()
            data = response.json()
    except (httpx.RequestError, httpx.HTTPStatusError, ValueError):
        return None

    model = data.get("geomagnetic-field-model-result") if isinstance(data, dict) else None
    field_value = model.get("field-value") if isinstance(model, dict) else None
    declination = field_value.get("declination") if isinstance(field_value, dict) else None
    value = declination.get("value") if isinstance(declination, dict) else None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


async def _upsert_declination_for_competition(competition_id: int, declination: float) -> None:
    await _post_to_ords(
        "admin/competitions/declination",
        {
            "competition_id": competition_id,
            "declination": declination,
        },
    )
    _invalidate_competition_cache(competition_id)


async def _refresh_competition_declination(competition_id: int) -> None:
    try:
        overview = await _get_from_ords("admin/competition-overview", {"competition_id": competition_id})
        if not isinstance(overview, dict):
            return
        if not _declination_refresh_needed(overview):
            return

        checkpoints_data = await _get_from_ords(ADMIN_CHECKPOINTS_PATH, {"competition_id": competition_id})
        coords = _extract_checkpoint_coords(checkpoints_data)
        avg_coord = _average_checkpoint_coord(coords)
        if avg_coord is None:
            return

        avg_lat, avg_lon = avg_coord
        declination = await _fetch_declination_from_service(avg_lat, avg_lon)
        if declination is None:
            return
        await _upsert_declination_for_competition(competition_id, declination)
    except Exception:
        return


def _schedule_declination_refresh(competition_id: int | None) -> None:
    if not isinstance(competition_id, int):
        return
    try:
        task = asyncio.create_task(_refresh_competition_declination(competition_id))
        background_tasks.add(task)
        task.add_done_callback(background_tasks.discard)
    except RuntimeError:
        pass


async def _get_map_checkpoints_payload(competition_id: int, user_id: int) -> dict[str, Any]:
    now = time.monotonic()
    _purge_expired_map_cache(now)
    key = _map_cache_key(competition_id=competition_id, user_id=user_id)
    cached = map_checkpoints_cache.get(key)
    if isinstance(cached, dict):
        cached_items = cached.get("items")
        if isinstance(cached_items, list):
            return {
                "items": cached_items,
                "declination": cached.get("declination", 0.0),
                "declination_last_updated": cached.get("declination_last_updated"),
            }

    ords_response = await _get_from_ords(
        "competitor/map-checkpoints",
        {
            "competition_id": competition_id,
            "user_id": user_id,
        },
    )
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else []
    items = _enrich_competitor_map_checkpoint_items(raw_items if isinstance(raw_items, list) else [])
    declination_raw = ords_response.get("declination") if isinstance(ords_response, dict) else 0
    declination = float(declination_raw) if isinstance(declination_raw, (int, float)) else 0.0
    declination_last_updated = ords_response.get("declination_last_updated") if isinstance(ords_response, dict) else None
    payload = {
        "items": items,
        "declination": declination,
        "declination_last_updated": declination_last_updated if isinstance(declination_last_updated, str) else None,
    }
    map_checkpoints_cache[key] = {"cached_at": now, **payload}
    return payload


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


@app.get("/api/content/intro", response_model=IntroContentResponse)
async def get_intro_content(lang: str | None = None) -> IntroContentResponse:
    resolved_lang, html = _read_content_html_with_fallback("intro", lang)
    return IntroContentResponse(lang_code=resolved_lang, html=html or "")


@app.get("/api/map-layers", response_model=MapLayersResponse)
async def get_map_layers() -> MapLayersResponse:
    return MapLayersResponse(items=_load_map_layers_config())


@app.get("/api/competitor/map-layers", response_model=CompetitorMapLayersResponse)
async def competitor_map_layers(  # NOSONAR
    competition_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> CompetitorMapLayersResponse:
    _ = _resolve_user_id(request, None, x_user_id)
    cached = competitor_map_layers_cache.get(competition_id)
    if isinstance(cached, dict):
        cached_items = cached.get("items")
        if isinstance(cached_items, list):
            return CompetitorMapLayersResponse(competition_id=competition_id, items=cached_items)

    enabled_layers = _load_map_layers_config()
    enabled_by_code: dict[str, dict[str, Any]] = {}
    for layer in enabled_layers:
        code = str(layer.get("code", "")).strip().lower()
        if code:
            enabled_by_code[code] = layer

    ords_data = await _get_from_ords("admin/competitions/map-layers", {"competition_id": competition_id})
    raw_items = ords_data.get("items") if isinstance(ords_data, dict) else []
    selected_codes: list[str] = []
    if isinstance(raw_items, list):
        for item in raw_items:
            if not isinstance(item, dict):
                continue
            code = str(item.get("layer_code", "")).strip().lower()
            if code:
                selected_codes.append(code)

    selected_set = {code for code in selected_codes if code}
    resolved_layers: list[MapLayerEntry] = []
    for layer in enabled_layers:
        code = str(layer.get("code", "")).strip().lower()
        if not code or code not in selected_set:
            continue
        resolved_layers.append(MapLayerEntry(**layer))

    competitor_map_layers_cache[competition_id] = {
        "cached_at": time.time(),
        "items": resolved_layers,
    }
    return CompetitorMapLayersResponse(competition_id=competition_id, items=resolved_layers)


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

    session_token = _make_session_token_for_provider(user_id, "google")
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

    session_token = _make_session_token_for_provider(user_id, "dev")
    response.set_cookie(
        key=settings.competitor_session_cookie_name,
        value=session_token,
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )
    return DevLoginResponse(user_id=user_id)


@app.post("/api/competitor/ensure-session", response_model=CompetitorEnsureSessionResponse)
async def competitor_ensure_session(request: Request, response: Response) -> CompetitorEnsureSessionResponse:
    existing_user_id = _read_competitor_session_user_id(request)
    if isinstance(existing_user_id, int):
        return CompetitorEnsureSessionResponse(user_id=existing_user_id)
    # Do not pre-create anonymous users here. User row is created only during
    # successful join-complete in DB transaction with competition_participants.
    return CompetitorEnsureSessionResponse(user_id=None)


@app.get("/api/auth/google/config", response_model=GoogleClientConfigResponse)
async def auth_google_config() -> GoogleClientConfigResponse:
    cid = settings.google_client_id.strip() if settings.google_client_id else ""
    return GoogleClientConfigResponse(client_id=cid or None, enabled=bool(cid))


@app.post("/api/auth/logout")
async def auth_logout(response: Response) -> dict[str, bool]:
    response.delete_cookie(
        key=settings.session_cookie_name,
        path="/",
        secure=settings.session_cookie_secure,
        samesite="lax",
    )
    return {"ok": True}


@app.get("/api/auth/session", response_model=SessionInfoResponse)
async def auth_session(request: Request) -> SessionInfoResponse:
    payload = _read_session_payload(request)
    if payload is None:
        return SessionInfoResponse(authenticated=False)
    user_id = payload.get("user_id") if isinstance(payload.get("user_id"), int) else None
    email: str | None = None
    full_name: str | None = None
    if user_id is not None:
        try:
            prof = await _get_from_ords("auth/user-profile", {"user_id": user_id})
            if isinstance(prof, dict):
                email = prof.get("email") if isinstance(prof.get("email"), str) else None
                full_name = prof.get("full_name") if isinstance(prof.get("full_name"), str) else None
        except Exception:
            pass
    return SessionInfoResponse(
        authenticated=True,
        user_id=user_id,
        auth_provider=payload.get("auth_provider") if isinstance(payload.get("auth_provider"), str) else None,
        email=email,
        full_name=full_name,
    )


def _set_competitor_cookies(response: Response, user_id: int, competition_participant_id: int) -> None:
    session_token = _make_signed_token(
        {"user_id": user_id, "auth_provider": "competitor", "competition_participant_id": competition_participant_id}
    )
    participation_token = _make_competitor_participation_token(competition_participant_id)
    max_age_seconds = max(1, int(settings.competitor_participation_cookie_ttl_hours) * 60 * 60)
    response.set_cookie(
        key=settings.competitor_session_cookie_name,
        value=session_token,
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        max_age=max_age_seconds,
        path="/",
    )
    response.set_cookie(
        key=settings.competitor_participation_cookie_name,
        value=participation_token,
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        max_age=max_age_seconds,
        path="/",
    )


def _delete_competitor_participation_cookie(response: Response) -> None:
    response.delete_cookie(
        key=settings.competitor_participation_cookie_name,
        path="/",
        secure=settings.session_cookie_secure,
        samesite="lax",
    )


@app.get("/api/competitor/session", response_model=CompetitorSessionResponse)
async def competitor_session(request: Request, response: Response) -> CompetitorSessionResponse:
    user_id = _read_competitor_session_user_id(request)
    participant_id = _read_competitor_participation_id(request)
    if user_id is None or participant_id is None:
        return CompetitorSessionResponse(authenticated=False)

    ords_response = await _get_from_ords(
        "competitor/session-by-participant",
        {"user_id": user_id, "competition_participant_id": participant_id},
    )
    participant = ords_response.get("participant") if isinstance(ords_response, dict) else None
    if not isinstance(participant, dict):
        _delete_competitor_participation_cookie(response)
        return CompetitorSessionResponse(authenticated=False)

    cp_id = participant.get("competition_participant_id")
    cid = participant.get("competition_id")
    name = participant.get("competition_name")
    if not isinstance(cp_id, int) or not isinstance(cid, int) or not isinstance(name, str):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)

    _set_competitor_cookies(response, user_id=user_id, competition_participant_id=cp_id)
    return CompetitorSessionResponse(
        authenticated=True,
        user_id=user_id,
        participant=CompetitorSessionParticipant(
            competition_participant_id=cp_id,
            competition_id=cid,
            competition_name=name,
            competition_description=participant.get("competition_description") if isinstance(participant.get("competition_description"), str) else None,
            competition_type=participant.get("competition_type") if isinstance(participant.get("competition_type"), str) else None,
            alias_display=participant.get("alias_display") if isinstance(participant.get("alias_display"), str) else None,
            competitor_name=participant.get("competitor_name") if isinstance(participant.get("competitor_name"), str) else None,
            use_location=participant.get("use_location") if isinstance(participant.get("use_location"), str) else None,
            show_competitor_location=participant.get("show_competitor_location") if isinstance(participant.get("show_competitor_location"), str) else None,
        ),
    )


@app.post("/api/competitor/join-preview", response_model=CompetitorJoinPreviewResponse)
async def competitor_join_preview(req: CompetitorJoinPreviewRequest, request: Request) -> CompetitorJoinPreviewResponse:
    user_id = _read_competitor_session_user_id(request)
    lang_code = (req.lang_code or settings.lang_default or "et").strip().lower()
    if lang_code not in settings.lang_available:
        lang_code = settings.lang_default

    preview_payload: dict[str, Any] = {"access_code": req.code, "lang_code": lang_code}
    if isinstance(user_id, int):
        preview_payload["user_id"] = user_id
    if req.alias_display is not None and req.alias_display.strip():
        preview_payload["alias_display"] = req.alias_display.strip()
    ords_response = await _post_to_ords("competitor/join-preview", preview_payload)
    cid = ords_response.get("competition_id")
    name = ords_response.get("competition_name")
    if not isinstance(cid, int) or not isinstance(name, str):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    terms_raw = ords_response.get("terms")
    terms: CompetitorJoinPreviewTerms | None = None
    if isinstance(terms_raw, dict):
        tid = terms_raw.get("terms_id")
        t_lang = terms_raw.get("lang_code")
        t_text = terms_raw.get("terms_text")
        if isinstance(tid, int) and isinstance(t_lang, str) and isinstance(t_text, str):
            terms = CompetitorJoinPreviewTerms(terms_id=tid, lang_code=t_lang, terms_text=t_text)
    return CompetitorJoinPreviewResponse(
        competition_id=cid,
        competition_name=name,
        competition_description=ords_response.get("competition_description") if isinstance(ords_response.get("competition_description"), str) else None,
        already_active_for_user=str(ords_response.get("already_active_for_user", "N")).upper() == "Y",
        terms=terms,
    )


@app.post("/api/competitor/join-complete", response_model=CompetitorJoinCompleteResponse)
async def competitor_join_complete(req: CompetitorJoinCompleteRequest, request: Request, response: Response) -> CompetitorJoinCompleteResponse:
    user_id = _read_competitor_session_user_id(request)
    if not req.accept_terms:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "TERMS_NOT_ACCEPTED", "api.error.terms_not_accepted")

    current_participant_id = _read_competitor_participation_id(request)
    payload: dict[str, Any] = {
        "access_code": req.code,
        "alias_display": req.alias_display,
        "terms_id": req.terms_id,
        "terms_lang_code": req.terms_lang_code,
        "accept_terms": "Y" if req.accept_terms else "N",
    }
    if isinstance(user_id, int):
        payload["user_id"] = user_id
    if req.contact_email:
        payload["contact_email"] = req.contact_email
    if current_participant_id is not None:
        payload["current_competition_participant_id"] = current_participant_id

    ords_response = await _post_to_ords("competitor/join-complete", payload)
    effective_user_id = ords_response.get("user_id")
    if not isinstance(effective_user_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    cp_id = ords_response.get("competition_participant_id")
    cid = ords_response.get("competition_id")
    if not isinstance(cp_id, int) or not isinstance(cid, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    switched_from = ords_response.get("switched_from_participant_id")
    switched_from_id = switched_from if isinstance(switched_from, int) else None
    no_change = str(ords_response.get("no_change", "N")).upper() == "Y"
    _set_competitor_cookies(response, user_id=effective_user_id, competition_participant_id=cp_id)
    return CompetitorJoinCompleteResponse(
        competition_participant_id=cp_id,
        competition_id=cid,
        switched_from_participant_id=switched_from_id,
        no_change=no_change,
    )


@app.post("/api/competitor/terms-cache/reset")
async def reset_competitor_terms_cache() -> dict[str, Any]:
    competitor_terms_cache.clear()
    return {"ok": True, "cache_size": 0}


@app.get("/api/competitor/terms", response_model=CompetitorTermsResponse)
async def competitor_terms(competition_id: int, request: Request, lang_code: str | None = None) -> CompetitorTermsResponse:
    user_id = _read_competitor_session_user_id(request)
    if not isinstance(user_id, int):
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHORIZED", "api.error.unauthorized")

    effective_lang = (lang_code or settings.lang_default or "et").strip().lower()
    if effective_lang not in settings.lang_available:
        effective_lang = settings.lang_default
    cache_key = f"{competition_id}|{effective_lang}"
    cached = competitor_terms_cache.get(cache_key)
    if isinstance(cached, dict):
        terms_raw_cached = cached.get("terms")
        terms_cached: CompetitorJoinPreviewTerms | None = None
        if isinstance(terms_raw_cached, dict):
            tid = terms_raw_cached.get("terms_id")
            t_lang = terms_raw_cached.get("lang_code")
            t_text = terms_raw_cached.get("terms_text")
            if isinstance(tid, int) and isinstance(t_lang, str) and isinstance(t_text, str):
                terms_cached = CompetitorJoinPreviewTerms(terms_id=tid, lang_code=t_lang, terms_text=t_text)
        return CompetitorTermsResponse(competition_id=competition_id, terms=terms_cached)

    ords_response = await _get_from_ords(
        "competitor/terms",
        {"user_id": user_id, "competition_id": competition_id, "lang_code": effective_lang},
    )
    cid = ords_response.get("competition_id")
    if not isinstance(cid, int):
        _raise_api_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "api.error.not_found")

    competitor_terms_cache[cache_key] = ords_response

    terms_raw = ords_response.get("terms")
    terms: CompetitorJoinPreviewTerms | None = None
    if isinstance(terms_raw, dict):
        tid = terms_raw.get("terms_id")
        t_lang = terms_raw.get("lang_code")
        t_text = terms_raw.get("terms_text")
        if isinstance(tid, int) and isinstance(t_lang, str) and isinstance(t_text, str):
            terms = CompetitorJoinPreviewTerms(terms_id=tid, lang_code=t_lang, terms_text=t_text)
    return CompetitorTermsResponse(competition_id=cid, terms=terms)


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
    user_id = _require_google_session_user(request, x_user_id)
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
    # Event-driven cache refresh for competitor status after successful submit.
    map_checkpoints_cache.pop(_map_cache_key(competition_id=req.competition_id, user_id=user_id), None)
    open_checkpoints_last_response.pop(_open_checkpoints_key(competition_id=req.competition_id, user_id=user_id), None)
    return SubmitAnswerResponse(
        submission_id=submission_id,
        is_correct=(is_correct_raw == "Y"),
        awarded_points=awarded_points,
        total_score=total_score,
    )


@app.get("/api/competitor/competitions", response_model=CompetitorCompetitionsResponse)
async def competitor_competitions(  # NOSONAR
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
                        description=item.get("description") if isinstance(item.get("description"), str) else None,
                        type=item.get("type") if isinstance(item.get("type"), str) else None,
                        starts_at=item.get("starts_at") if isinstance(item.get("starts_at"), str) else None,
                        ends_at=item.get("ends_at") if isinstance(item.get("ends_at"), str) else None,
                        use_location=item.get("use_location") if isinstance(item.get("use_location"), str) else None,
                        show_competitor_location=item.get("show_competitor_location") if isinstance(item.get("show_competitor_location"), str) else None,
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
    req_signature = _open_checkpoints_signature(latitude, longitude, radius_m)
    key = _open_checkpoints_key(competition_id=competition_id, user_id=resolved_user_id)
    previous = open_checkpoints_last_response.get(key)
    if previous:
        previous_at = previous.get("response_at")
        previous_items = previous.get("items")
        previous_signature = previous.get("signature")
        if (
            isinstance(previous_at, float)
            and isinstance(previous_items, list)
            and previous_signature == req_signature
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
    open_checkpoints_last_response[key] = {"response_at": now, "items": items, "signature": req_signature}
    return CompetitorOpenCheckpointsResponse(items=items)


@app.get("/api/competitor/map-checkpoints", response_model=CompetitorOpenCheckpointsResponse)
async def competitor_map_checkpoints(
    competition_id: int,
    request: Request,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorOpenCheckpointsResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    payload = await _get_map_checkpoints_payload(competition_id=competition_id, user_id=resolved_user_id)
    return CompetitorOpenCheckpointsResponse(
        items=payload.get("items") if isinstance(payload.get("items"), list) else [],
        declination=float(payload.get("declination", 0.0)) if isinstance(payload.get("declination"), (int, float)) else 0.0,
        declination_last_updated=payload.get("declination_last_updated") if isinstance(payload.get("declination_last_updated"), str) else None,
    )


@app.post("/api/competitor/checkpoint-access", response_model=CompetitorCheckpointAccessResponse)
async def competitor_checkpoint_access(
    req: CompetitorCheckpointAccessRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> CompetitorCheckpointAccessResponse:
    resolved_user_id = _resolve_user_id(request, req.user_id, x_user_id)
    map_payload = await _get_map_checkpoints_payload(competition_id=req.competition_id, user_id=resolved_user_id)
    map_items = map_payload.get("items") if isinstance(map_payload.get("items"), list) else []
    by_id: dict[int, dict[str, Any]] = {}
    for row in map_items:
        if not isinstance(row, dict):
            continue
        cp_id = row.get("checkpoint_id")
        if isinstance(cp_id, int):
            by_id[cp_id] = row

    requested_ids = [cp_id for cp_id in req.checkpoint_ids if isinstance(cp_id, int)]
    if not requested_ids:
        return CompetitorCheckpointAccessResponse(items=[])

    items: list[CompetitorCheckpointAccessEntry] = []
    candidate_ids: list[int] = []
    lat = req.latitude if isinstance(req.latitude, (int, float)) else None
    lon = req.longitude if isinstance(req.longitude, (int, float)) else None
    base_radius = req.radius_m if isinstance(req.radius_m, (int, float)) else None
    comp_type = "R"
    start_exists = False
    start_answered = False
    finish_answered = False
    next_ordered_checkpoint_id: int | None = None
    if map_items:
        comp_type = _normalize_competition_type(
            next(
                (
                    row.get("competition_type")
                    for row in map_items
                    if isinstance(row, dict) and row.get("competition_type") is not None
                ),
                "R",
            )
        )
        start_exists = any(
            _normalize_checkpoint_type(row.get("checkpoint_type")) == "START"
            for row in map_items
            if isinstance(row, dict)
        )
        start_answered = any(
            _normalize_checkpoint_type(row.get("checkpoint_type")) == "START"
            and str(row.get("is_answered", "N")).upper() == "Y"
            for row in map_items
            if isinstance(row, dict)
        )
        finish_answered = any(
            _normalize_checkpoint_type(row.get("checkpoint_type")) == "FINISH"
            and str(row.get("is_answered", "N")).upper() == "Y"
            for row in map_items
            if isinstance(row, dict)
        )
        if comp_type == "S":
            next_ordered_checkpoint_id = _ordered_checkpoint_id_from_map_items(
                [row for row in map_items if isinstance(row, dict)]
            )

    for cp_id in requested_ids:
        cp = by_id.get(cp_id)
        if not isinstance(cp, dict):
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="not_found"))
            continue
        cp_type = _normalize_checkpoint_type(cp.get("checkpoint_type"))
        if str(cp.get("is_answered", "N")).upper() == "Y":
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="answered"))
            continue
        if finish_answered:
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="finished"))
            continue
        if start_exists and not start_answered and cp_type != "START":
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="start_required"))
            continue
        if comp_type == "S":
            if start_exists and not start_answered and cp_type == "START":
                pass
            elif next_ordered_checkpoint_id is not None:
                if cp_type != "NORMAL" or cp_id != next_ordered_checkpoint_id:
                    items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="wrong_order"))
                    continue
            elif cp_type != "FINISH":
                items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="wrong_order"))
                continue
        location_required = str(cp.get("location_required", "N")).upper() == "Y"
        if not location_required:
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=True, reason="no_location_required"))
            continue
        if lat is None or lon is None:
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="missing_location"))
            continue

        cp_lat = cp.get("latitude")
        cp_lon = cp.get("longitude")
        cp_radius = cp.get("radius_m")
        if not isinstance(cp_lat, (int, float)) or not isinstance(cp_lon, (int, float)):
            candidate_ids.append(cp_id)
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, needs_ords=True, reason="needs_ords"))
            continue
        effective_radius = cp_radius if isinstance(cp_radius, (int, float)) and cp_radius > 0 else base_radius
        if not isinstance(effective_radius, (int, float)) or effective_radius <= 0:
            candidate_ids.append(cp_id)
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, needs_ords=True, reason="needs_ords"))
            continue
        distance_m = _haversine_meters(float(lat), float(lon), float(cp_lat), float(cp_lon))
        if distance_m <= float(effective_radius):
            candidate_ids.append(cp_id)
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, needs_ords=True, reason="needs_ords"))
        else:
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="too_far"))

    if candidate_ids:
        ords_response = await _get_from_ords(
            "competitor/open-checkpoints",
            {
                "competition_id": req.competition_id,
                "user_id": resolved_user_id,
                "latitude": lat,
                "longitude": lon,
                "radius_m": base_radius,
            },
        )
        raw = ords_response.get("items") if isinstance(ords_response, dict) else []
        open_ids: set[int] = set()
        if isinstance(raw, list):
            for row in raw:
                if isinstance(row, dict) and isinstance(row.get("checkpoint_id"), int):
                    open_ids.add(int(row["checkpoint_id"]))
        for entry in items:
            if not entry.needs_ords:
                continue
            entry.needs_ords = False
            entry.can_open = entry.checkpoint_id in open_ids
            entry.reason = "open" if entry.can_open else "not_open"

    return CompetitorCheckpointAccessResponse(items=items)


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

@app.get("/api/competitor/progress", response_model=CompetitorProgressResponse)
async def competitor_progress(
    competition_id: int,
    request: Request,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorProgressResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    ords_response = await _get_from_ords(
        "competitor/progress",
        {
            "competition_id": competition_id,
            "user_id": resolved_user_id,
        },
    )
    total_checkpoints = ords_response.get("total_checkpoints", 0)
    answered_checkpoints = ords_response.get("answered_checkpoints", 0)
    score = ords_response.get("score", 0)
    if not isinstance(total_checkpoints, int) or not isinstance(answered_checkpoints, int) or not isinstance(score, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    return CompetitorProgressResponse(
        competition_id=competition_id,
        user_id=resolved_user_id,
        total_checkpoints=max(0, total_checkpoints),
        answered_checkpoints=max(0, answered_checkpoints),
        score=score,
    )


@app.get("/api/competitor/my-submissions", response_model=CompetitorMySubmissionsResponse)
async def competitor_my_submissions(  # NOSONAR
    competition_id: int,
    request: Request,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorMySubmissionsResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    ords_response = await _get_from_ords(
        "competitor/my-submissions",
        {
            "competition_id": competition_id,
            "user_id": resolved_user_id,
        },
    )
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else None
    if not isinstance(raw_items, list):
        raw_items = []
    items: list[CompetitorMySubmissionEntry] = []
    for item in raw_items:
        if isinstance(item, dict):
            items.append(
                CompetitorMySubmissionEntry(
                    checkpoint_title=item.get("checkpoint_title") if isinstance(item.get("checkpoint_title"), str) else None,
                    submission_id=item.get("submission_id") if isinstance(item.get("submission_id"), int) else None,
                    submitted_at=item.get("submitted_at") if isinstance(item.get("submitted_at"), str) else None,
                    awarded_points=item.get("awarded_points") if isinstance(item.get("awarded_points"), int) else 0,
                )
            )
    return CompetitorMySubmissionsResponse(items=items)


@app.get("/api/competitor/my-submission-detail", response_model=CompetitorMySubmissionDetailResponse)
async def competitor_my_submission_detail(  # NOSONAR
    competition_id: int,
    submission_id: int,
    request: Request,
    lang_code: str | None = None,
    user_id: int | None = None,
    x_user_id: int | None = Header(default=None),
) -> CompetitorMySubmissionDetailResponse:
    resolved_user_id = _resolve_user_id(request, user_id, x_user_id)
    effective_lang = (lang_code or settings.lang_default or "et").strip().lower()
    if effective_lang not in settings.lang_available:
        effective_lang = settings.lang_default
    ords_response = await _get_from_ords(
        "competitor/my-submission-detail",
        {
            "competition_id": competition_id,
            "user_id": resolved_user_id,
            "submission_id": submission_id,
            "lang_code": effective_lang,
            "default_lang_code": settings.lang_default,
        },
    )
    if not isinstance(ords_response, dict):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)

    raw_options = ords_response.get("options")
    options: list[CompetitorMySubmissionDetailOption] = []
    if isinstance(raw_options, list):
        for o in raw_options:
            if isinstance(o, dict):
                options.append(
                    CompetitorMySubmissionDetailOption(
                        option_text=o.get("option_text") if isinstance(o.get("option_text"), str) else None,
                        is_correct=o.get("is_correct") if isinstance(o.get("is_correct"), str) else "N",
                        is_selected=o.get("is_selected") if isinstance(o.get("is_selected"), str) else "N",
                    )
                )

    cp = ords_response.get("correct_pct")
    correct_pct = float(cp) if isinstance(cp, (int, float)) else None
    return CompetitorMySubmissionDetailResponse(
        submission_id=ords_response.get("submission_id") if isinstance(ords_response.get("submission_id"), int) else None,
        checkpoint_title=ords_response.get("checkpoint_title") if isinstance(ords_response.get("checkpoint_title"), str) else None,
        question_text=ords_response.get("question_text") if isinstance(ords_response.get("question_text"), str) else None,
        question_type=ords_response.get("question_type") if isinstance(ords_response.get("question_type"), str) else None,
        points=ords_response.get("points") if isinstance(ords_response.get("points"), int) else 0,
        wrong_points=ords_response.get("wrong_points") if isinstance(ords_response.get("wrong_points"), int) else 0,
        submitted_at=ords_response.get("submitted_at") if isinstance(ords_response.get("submitted_at"), str) else None,
        awarded_points=ords_response.get("awarded_points") if isinstance(ords_response.get("awarded_points"), int) else 0,
        competitor_answer=ords_response.get("competitor_answer") if isinstance(ords_response.get("competitor_answer"), str) else None,
        responders_count=ords_response.get("responders_count") if isinstance(ords_response.get("responders_count"), int) else 0,
        correct_pct=correct_pct,
        options=options,
    )


@app.get("/api/admin/leaderboard", response_model=LeaderboardResponse)
async def admin_leaderboard(  # NOSONAR
    competition_id: int,
    request: Request,
    lang_code: str | None = None,
    x_user_id: int | None = Header(default=None),
) -> LeaderboardResponse:
    requester_user_id = _require_google_session_user(request, x_user_id)
    effective_lang = _resolve_ui_lang(lang_code)
    ords_response = await _get_from_ords(
        "organizer/leaderboard",
        {
            "competition_id": competition_id,
            "requester_user_id": requester_user_id,
            "lang_code": effective_lang,
        },
    )

    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else None
    if not isinstance(raw_items, list):
        raw_items = []

    items: list[LeaderboardEntry] = []
    for item in raw_items:
        if isinstance(item, dict) and isinstance(item.get("user_id"), int) and isinstance(item.get("score"), int):
            items.append(
                LeaderboardEntry(
                    user_id=item["user_id"],
                    competitor_name=item.get("competitor_name") if isinstance(item.get("competitor_name"), str) else None,
                    answered_checkpoints=item.get("answered_checkpoints") if isinstance(item.get("answered_checkpoints"), int) else None,
                    score=item["score"],
                    last_checkpoint=item.get("last_checkpoint") if isinstance(item.get("last_checkpoint"), str) else None,
                    last_submission_at=item.get("last_submission_at") if isinstance(item.get("last_submission_at"), str) else None,
                    total_elapsed_seconds=item.get("total_elapsed_seconds") if isinstance(item.get("total_elapsed_seconds"), int) else None,
                    total_distance_m=item.get("total_distance_m") if isinstance(item.get("total_distance_m"), int) else None,
                )
            )

    access_granted = str(ords_response.get("access_granted") if isinstance(ords_response, dict) else "N").upper() == "Y"
    return LeaderboardResponse(competition_id=competition_id, access_granted=access_granted, items=items)


@app.get("/api/admin/checkpoint-results", response_model=CheckpointResultsResponse)
async def admin_checkpoint_results(  # NOSONAR
    competition_id: int,
    request: Request,
    lang_code: str | None = None,
    x_user_id: int | None = Header(default=None),
) -> CheckpointResultsResponse:
    requester_user_id = _require_google_session_user(request, x_user_id)
    effective_lang = _resolve_ui_lang(lang_code)
    ords_response = await _get_from_ords(
        "organizer/checkpoint-results",
        {
            "competition_id": competition_id,
            "requester_user_id": requester_user_id,
            "lang_code": effective_lang,
        },
    )
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else None
    if not isinstance(raw_items, list):
        raw_items = []

    items: list[CheckpointResultEntry] = []
    for item in raw_items:
        if isinstance(item, dict):
            items.append(
                CheckpointResultEntry(
                    checkpoint_id=item.get("checkpoint_id") if isinstance(item.get("checkpoint_id"), int) else None,
                    checkpoint_title=item.get("checkpoint_title") if isinstance(item.get("checkpoint_title"), str) else None,
                    last_submission_at=item.get("last_submission_at") if isinstance(item.get("last_submission_at"), str) else None,
                    last_team=item.get("last_team") if isinstance(item.get("last_team"), str) else None,
                    checkpoint_points=item.get("checkpoint_points") if isinstance(item.get("checkpoint_points"), int) else 0,
                    correct_count=item.get("correct_count") if isinstance(item.get("correct_count"), int) else 0,
                    wrong_count=item.get("wrong_count") if isinstance(item.get("wrong_count"), int) else 0,
                )
            )

    access_granted = str(ords_response.get("access_granted") if isinstance(ords_response, dict) else "N").upper() == "Y"
    return CheckpointResultsResponse(competition_id=competition_id, access_granted=access_granted, items=items)

@app.get("/api/admin/checkpoint-responders", response_model=CheckpointRespondersResponse)
async def admin_checkpoint_responders(
    competition_id: int,
    checkpoint_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> CheckpointRespondersResponse:
    requester_user_id = _require_google_session_user(request, x_user_id)
    ords_response = await _get_from_ords(
        "organizer/checkpoint-responders",
        {
            "competition_id": competition_id,
            "checkpoint_id": checkpoint_id,
            "requester_user_id": requester_user_id,
        },
    )
    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else None
    if not isinstance(raw_items, list):
        raw_items = []

    items: list[CheckpointResponderEntry] = []
    for item in raw_items:
        if isinstance(item, dict) and isinstance(item.get("user_id"), int):
            items.append(
                CheckpointResponderEntry(
                    user_id=item["user_id"],
                    competitor_name=item.get("competitor_name") if isinstance(item.get("competitor_name"), str) else None,
                    is_correct=item.get("is_correct") if isinstance(item.get("is_correct"), str) else "N",
                )
            )

    return CheckpointRespondersResponse(
        competition_id=competition_id,
        checkpoint_id=checkpoint_id,
        access_granted=str(ords_response.get("access_granted") if isinstance(ords_response, dict) else "N").upper() == "Y",
        items=items,
    )

@app.get("/api/admin/participant-submissions", response_model=ParticipantSubmissionsResponse)
async def admin_participant_submissions(  # NOSONAR
    competition_id: int,
    user_id: int,
    request: Request,
    lang_code: str | None = None,
    x_user_id: int | None = Header(default=None),
) -> ParticipantSubmissionsResponse:
    requester_user_id = _require_google_session_user(request, x_user_id)
    effective_lang = _resolve_ui_lang(lang_code)
    ords_response = await _get_from_ords(
        "organizer/participant-submissions",
        {
            "competition_id": competition_id,
            "user_id": user_id,
            "requester_user_id": requester_user_id,
            "lang_code": effective_lang,
            "default_lang_code": settings.lang_default,
        },
    )

    raw_items = ords_response.get("items") if isinstance(ords_response, dict) else None
    if not isinstance(raw_items, list):
        raw_items = []

    items: list[ParticipantSubmissionEntry] = []
    for item in raw_items:
        if isinstance(item, dict):
            cp_title = item.get("checkpoint_title")
            points = item.get("awarded_points")
            is_correct = item.get("is_correct")
            delta_from_prev = item.get("delta_from_prev_seconds")
            items.append(
                ParticipantSubmissionEntry(
                    submission_id=item.get("submission_id") if isinstance(item.get("submission_id"), int) else None,
                    checkpoint_title=cp_title if isinstance(cp_title, str) else None,
                    submitted_at=item.get("submitted_at") if isinstance(item.get("submitted_at"), str) else None,
                    delta_from_prev_seconds=delta_from_prev if isinstance(delta_from_prev, int) else None,
                    awarded_points=points if isinstance(points, int) else 0,
                    answer_text=item.get("answer_text") if isinstance(item.get("answer_text"), str) else None,
                    is_correct=is_correct if isinstance(is_correct, str) else "N",
                )
            )

    total_elapsed_seconds = ords_response.get("total_elapsed_seconds") if isinstance(ords_response, dict) else None
    total_distance_m = ords_response.get("total_distance_m") if isinstance(ords_response, dict) else None
    distance_available_raw = ords_response.get("distance_available") if isinstance(ords_response, dict) else None
    distance_available = str(distance_available_raw or "N").upper() == "Y"

    return ParticipantSubmissionsResponse(
        competition_id=competition_id,
        user_id=user_id,
        access_granted=str(ords_response.get("access_granted") if isinstance(ords_response, dict) else "N").upper() == "Y",
        total_elapsed_seconds=total_elapsed_seconds if isinstance(total_elapsed_seconds, int) else None,
        total_distance_m=total_distance_m if isinstance(total_distance_m, int) else None,
        distance_available=distance_available,
        items=items,
    )


@app.get("/api/admin/submission-detail", response_model=SubmissionDetailResponse)
async def admin_submission_detail(  # NOSONAR
    competition_id: int,
    user_id: int,
    submission_id: int,
    request: Request,
    lang_code: str | None = None,
    x_user_id: int | None = Header(default=None),
) -> SubmissionDetailResponse:
    requester_user_id = _require_google_session_user(request, x_user_id)
    effective_lang = _resolve_ui_lang(lang_code)
    ords_response = await _get_from_ords(
        "organizer/submission-detail",
        {
            "competition_id": competition_id,
            "user_id": user_id,
            "submission_id": submission_id,
            "requester_user_id": requester_user_id,
            "lang_code": effective_lang,
            "default_lang_code": settings.lang_default,
        },
    )
    if not isinstance(ords_response, dict):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)

    raw_options = ords_response.get("options")
    options: list[SubmissionDetailOption] = []
    if isinstance(raw_options, list):
        for o in raw_options:
            if isinstance(o, dict):
                options.append(
                    SubmissionDetailOption(
                        option_text=o.get("option_text") if isinstance(o.get("option_text"), str) else None,
                        is_correct=o.get("is_correct") if isinstance(o.get("is_correct"), str) else "N",
                        is_selected=o.get("is_selected") if isinstance(o.get("is_selected"), str) else "N",
                    )
                )

    return SubmissionDetailResponse(
        access_granted=str(ords_response.get("access_granted") if isinstance(ords_response, dict) else "N").upper() == "Y",
        submission_id=ords_response.get("submission_id") if isinstance(ords_response.get("submission_id"), int) else None,
        checkpoint_title=ords_response.get("checkpoint_title") if isinstance(ords_response.get("checkpoint_title"), str) else None,
        question_text=ords_response.get("question_text") if isinstance(ords_response.get("question_text"), str) else None,
        question_type=ords_response.get("question_type") if isinstance(ords_response.get("question_type"), str) else None,
        points=ords_response.get("points") if isinstance(ords_response.get("points"), int) else 0,
        wrong_points=ords_response.get("wrong_points") if isinstance(ords_response.get("wrong_points"), int) else 0,
        submitted_at=ords_response.get("submitted_at") if isinstance(ords_response.get("submitted_at"), str) else None,
        awarded_points=ords_response.get("awarded_points") if isinstance(ords_response.get("awarded_points"), int) else 0,
        competitor_answer=ords_response.get("competitor_answer") if isinstance(ords_response.get("competitor_answer"), str) else None,
        options=options,
    )


@app.post("/api/admin/checkpoints", response_model=AdminCreateCheckpointResponse)
async def admin_create_checkpoint(req: AdminCreateCheckpointRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateCheckpointResponse:
    user_id = _require_google_session_user(request, x_user_id)
    payload: dict[str, Any] = {
        "competition_id": req.competition_id,
        "title": req.title,
        "created_by": user_id,
    }
    if req.checkpoint_type is not None:
        payload["checkpoint_type"] = req.checkpoint_type
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
        ADMIN_CHECKPOINTS_PATH,
        payload,
    )
    checkpoint_id = ords_response.get("checkpoint_id")
    if not isinstance(checkpoint_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    _invalidate_competition_cache(req.competition_id)
    _schedule_declination_refresh(req.competition_id)
    return AdminCreateCheckpointResponse(checkpoint_id=checkpoint_id)


@app.post("/api/admin/questions", response_model=AdminCreateQuestionResponse)
async def admin_create_question(req: AdminCreateQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionResponse:
    user_id = _require_google_session_user(request, x_user_id)
    ords_response = await _post_to_ords(
        "admin/questions",
        {
            "checkpoint_id": req.checkpoint_id,
            "question_type": req.question_type,
            "input_type": req.input_type,
            "input_max_length": req.input_max_length,
            "input_pattern": req.input_pattern,
            "points": req.points,
            "wrong_points": req.wrong_points,
            "lang_code": req.lang_code,
            "question_text": req.question_text,
            "created_by": user_id,
        },
    )
    question_id = ords_response.get("question_id")
    if not isinstance(question_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return AdminCreateQuestionResponse(question_id=question_id)


@app.post("/api/admin/question-options", response_model=AdminCreateQuestionOptionResponse)
async def admin_create_question_option(req: AdminCreateQuestionOptionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionOptionResponse:
    user_id = _require_google_session_user(request, x_user_id)
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
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return AdminCreateQuestionOptionResponse(option_id=option_id)


@app.post("/api/admin/question-answers", response_model=AdminCreateQuestionAnswerResponse)
async def admin_create_question_answer(req: AdminCreateQuestionAnswerRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionAnswerResponse:
    user_id = _require_google_session_user(request, x_user_id)
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
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    return AdminCreateQuestionAnswerResponse(answer_id=answer_id)


@app.get("/api/admin/competition-overview", response_model=AdminCompetitionOverviewResponse)
async def admin_competition_overview(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionOverviewResponse:
    _ = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords("admin/competition-overview", {"competition_id": competition_id})
    return AdminCompetitionOverviewResponse(data=data if isinstance(data, dict) else {})


@app.get("/api/admin/questions-overview", response_model=AdminQuestionsOverviewResponse)
async def admin_questions_overview(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminQuestionsOverviewResponse:  # NOSONAR
    _ = _require_google_session_user(request, x_user_id)
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
    user_id = _require_google_session_user(request, x_user_id)
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
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    return AdminUpsertAccessCodeResponse(access_code_id=access_code_id)


@app.get("/api/admin/competitions", response_model=AdminCompetitionsResponse)
async def admin_competitions(request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionsResponse:
    user_id = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords("admin/competitions", {"user_id": user_id})
    items = data.get("items") if isinstance(data, dict) else []
    return AdminCompetitionsResponse(items=items if isinstance(items, list) else [])


@app.post("/api/admin/promo100/bootstrap", response_model=AdminPromoBootstrapResponse)
async def admin_promo100_bootstrap(request: Request, x_user_id: int | None = Header(default=None)) -> AdminPromoBootstrapResponse:
    user_id = _require_google_session_user(request, x_user_id)
    if settings.promo100_max_total_competitions <= 0:
        return AdminPromoBootstrapResponse(attempted=False, created=False)

    mine_data = await _get_from_ords("admin/competitions", {"user_id": user_id})
    mine_items = mine_data.get("items") if isinstance(mine_data, dict) else []
    if isinstance(mine_items, list) and len(mine_items) > 0:
        return AdminPromoBootstrapResponse(attempted=True, created=False)

    all_data = await _get_from_ords("superadmin/competitions", {})
    all_items = all_data.get("items") if isinstance(all_data, dict) else []
    total_competitions = len(all_items) if isinstance(all_items, list) else 0
    if total_competitions >= settings.promo100_max_total_competitions:
        return AdminPromoBootstrapResponse(attempted=True, created=False)

    profile = await _get_from_ords("auth/user-profile", {"user_id": user_id})
    email = profile.get("email") if isinstance(profile, dict) else None
    if not isinstance(email, str) or "@" not in email:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_REQUEST", "api.error.invalid_request")
    local_part = email.split("@", 1)[0].strip()
    if not local_part:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_REQUEST", "api.error.invalid_request")

    create_data = await _post_to_ords(
        "superadmin/competitions",
        {
            "name": f"{local_part} võistlus",
            "description": "Sinu esimene võistlus siin -- muuda see endale sobivaks ja kutsu sõbrad osalema!",
            "created_by": user_id,
        },
    )
    competition_id = create_data.get("competition_id") if isinstance(create_data, dict) else None
    organizer_code = create_data.get("organizer_code") if isinstance(create_data, dict) else None
    if not isinstance(competition_id, int):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    if not isinstance(organizer_code, str) or not organizer_code.strip():
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)

    # Ensure the newly created competition is immediately linked to the logged-in
    # user as organizer (same mechanism as organizer access-code join flow).
    join_data = await _post_to_ords(
        "organizers/register",
        {
            "user_id": user_id,
            "access_code": organizer_code.strip(),
        },
    )
    joined_competition_id = join_data.get("competition_id") if isinstance(join_data, dict) else None
    if not isinstance(joined_competition_id, int) or joined_competition_id != competition_id:
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)

    await _ensure_default_terms_for_competition(competition_id)
    return AdminPromoBootstrapResponse(attempted=True, created=True, competition_id=competition_id)


@app.get("/api/admin/competitions/map-layers", response_model=AdminCompetitionMapLayersResponse)
async def admin_competition_map_layers(
    competition_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> AdminCompetitionMapLayersResponse:
    _ = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords("admin/competitions/map-layers", {"competition_id": competition_id})
    raw_items = data.get("items") if isinstance(data, dict) else []
    layer_codes: list[str] = []
    if isinstance(raw_items, list):
        for item in raw_items:
            if not isinstance(item, dict):
                continue
            code = str(item.get("layer_code", "")).strip()
            if code:
                layer_codes.append(code)
    return AdminCompetitionMapLayersResponse(competition_id=competition_id, layer_codes=layer_codes)


@app.post("/api/admin/competitions/map-layers")
async def admin_competition_map_layers_update(
    req: AdminCompetitionMapLayersUpdateRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    cleaned_codes: list[str] = []
    seen: set[str] = set()
    for raw in req.layer_codes:
        code = str(raw or "").strip()
        if not code:
            continue
        low = code.lower()
        if low in seen:
            continue
        seen.add(low)
        cleaned_codes.append(code)
    await _post_to_ords(
        "admin/competitions/map-layers",
        {
            "competition_id": req.competition_id,
            "layer_codes": cleaned_codes,
            "updated_by": user_id,
        },
    )
    competitor_map_layers_cache.pop(req.competition_id, None)
    return {"ok": True}


@app.get("/api/superadmin/session", response_model=SuperAdminSessionResponse)
async def superadmin_session(request: Request, x_user_id: int | None = Header(default=None)) -> SuperAdminSessionResponse:
    user_id = await _require_system_owner_session_user(request, x_user_id)
    return SuperAdminSessionResponse(ok=True, user_id=user_id)


@app.get("/api/superadmin/competitions", response_model=AdminCompetitionsResponse)
async def superadmin_competitions(request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionsResponse:
    _ = await _require_system_owner_session_user(request, x_user_id)
    data = await _get_from_ords("superadmin/competitions", {})
    items = data.get("items") if isinstance(data, dict) else []
    return AdminCompetitionsResponse(items=items if isinstance(items, list) else [])


@app.post("/api/superadmin/competitions", response_model=SuperAdminCreateCompetitionResponse)
async def superadmin_create_competition(
    req: SuperAdminCreateCompetitionRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> SuperAdminCreateCompetitionResponse:
    user_id = await _require_system_owner_session_user(request, x_user_id)
    data = await _post_to_ords(
        "superadmin/competitions",
        {
            "name": req.name,
            "description": req.description,
            "created_by": user_id,
        },
    )
    competition_id = data.get("competition_id") if isinstance(data, dict) else None
    organizer_code = data.get("organizer_code") if isinstance(data, dict) else None
    if not isinstance(competition_id, int) or not isinstance(organizer_code, str):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    await _ensure_default_terms_for_competition(competition_id)
    return SuperAdminCreateCompetitionResponse(
        competition_id=competition_id,
        organizer_code=organizer_code,
    )


@app.post("/api/superadmin/competitions/copy", response_model=SuperAdminCreateCompetitionResponse)
async def superadmin_copy_competition(
    req: SuperAdminCopyCompetitionRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> SuperAdminCreateCompetitionResponse:
    user_id = await _require_system_owner_session_user(request, x_user_id)
    data = await _post_to_ords(
        "superadmin/competitions/copy",
        {
            "source_competition_id": req.source_competition_id,
            "copy_questions": req.copy_questions,
            "copy_organizers": req.copy_organizers,
            "created_by": user_id,
        },
    )
    competition_id = data.get("competition_id") if isinstance(data, dict) else None
    organizer_code = data.get("organizer_code") if isinstance(data, dict) else None
    if not isinstance(competition_id, int) or not isinstance(organizer_code, str):
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    await _ensure_default_terms_for_competition(competition_id)
    return SuperAdminCreateCompetitionResponse(
        competition_id=competition_id,
        organizer_code=organizer_code,
    )


@app.post("/api/superadmin/organizers/remove")
async def superadmin_remove_organizer(
    req: SuperAdminRemoveOrganizerRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> dict[str, bool]:
    user_id = await _require_system_owner_session_user(request, x_user_id)
    await _post_to_ords(
        "superadmin/organizers/remove",
        {
            "competition_id": req.competition_id,
            "user_id": req.user_id,
            "removed_by": user_id,
        },
    )
    return {"ok": True}

@app.get("/api/superadmin/translations", response_model=SuperAdminTranslationsResponse)
async def superadmin_translations(
    request: Request,
    lang: str | None = None,
    prefix: str | None = None,
    include_deleted: str | None = None,
    x_user_id: int | None = Header(default=None),
) -> SuperAdminTranslationsResponse:
    _ = await _require_system_owner_session_user(request, x_user_id)
    params = _superadmin_translations_params(lang, prefix, include_deleted)
    data = await _get_from_ords("superadmin/translations", params)
    raw_items = data.get("items") if isinstance(data, dict) else []
    items = [_to_superadmin_translation_item(row) for row in raw_items if isinstance(row, dict)] if isinstance(raw_items, list) else []
    return SuperAdminTranslationsResponse(items=items)


@app.post("/api/superadmin/translations/upsert")
async def superadmin_translations_upsert(
    req: SuperAdminTranslationUpsertRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> dict[str, Any]:
    user_id = await _require_system_owner_session_user(request, x_user_id)
    payload = {
        "translation_key": req.translation_key.strip(),
        "lang_code": req.lang_code.strip().lower(),
        "text_value": req.text_value,
        "updated_by": user_id,
    }
    await _post_to_ords("superadmin/translations/upsert", payload)
    return {"ok": True}


@app.post("/api/superadmin/translations/delete")
async def superadmin_translations_delete(
    req: SuperAdminTranslationDeleteRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> dict[str, Any]:
    user_id = await _require_system_owner_session_user(request, x_user_id)
    payload = {
        "translation_key": req.translation_key.strip(),
        "lang_code": req.lang_code.strip().lower(),
        "deleted_by": user_id,
    }
    await _post_to_ords("superadmin/translations/delete", payload)
    return {"ok": True}


@app.get("/api/admin/checkpoints", response_model=AdminCheckpointsResponse)
async def admin_checkpoints(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCheckpointsResponse:
    _ = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords(ADMIN_CHECKPOINTS_PATH, {"competition_id": competition_id})
    items = data.get("items") if isinstance(data, dict) else []
    return AdminCheckpointsResponse(items=items if isinstance(items, list) else [])


@app.post("/api/admin/checkpoints/update")
async def admin_update_checkpoint(req: AdminUpdateCheckpointRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
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
    _schedule_declination_refresh(req.competition_id)
    return {"ok": True}


@app.post("/api/admin/checkpoints/delete")
async def admin_delete_checkpoint(req: AdminDeleteCheckpointRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    await _post_to_ords(
        "admin/checkpoints/delete",
        {
            "checkpoint_id": req.checkpoint_id,
            "deleted_by": user_id,
        },
    )
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    _schedule_declination_refresh(req.competition_id)
    return {"ok": True}


@app.post("/api/admin/questions/update")
async def admin_update_question(req: AdminUpdateQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    payload: dict[str, Any] = {
        "question_id": req.question_id,
        "checkpoint_id": req.checkpoint_id,
        "question_type": req.question_type,
        "input_type": req.input_type,
        "input_max_length": req.input_max_length,
        "input_pattern": req.input_pattern,
        "points": req.points,
        "wrong_points": req.wrong_points,
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
    user_id = _require_google_session_user(request, x_user_id)
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
    user_id = _require_google_session_user(request, x_user_id)
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
    _schedule_declination_refresh(req.competition_id)
    return {"ok": True}


@app.post("/api/admin/competitions/meta")
async def admin_update_competition_meta(req: AdminUpdateCompetitionMetaRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    competition_type = str(req.type or "R").strip().upper() or "R"
    await _post_to_ords(
        "admin/competitions/meta",
        {
            "competition_id": req.competition_id,
            "name": req.name,
            "description": req.description,
            "type": competition_type,
            "status": req.status,
            "use_location": req.use_location,
            "show_competitor_location": req.show_competitor_location,
            "radius_m": req.radius_m,
            "updated_by": user_id,
        },
    )
    _invalidate_competition_cache(req.competition_id)
    _schedule_declination_refresh(req.competition_id)
    return {"ok": True}


@app.get("/api/admin/competitions/terms", response_model=AdminCompetitionTermsResponse)
async def admin_get_competition_terms(
    competition_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
    lang_code: str | None = None,
) -> AdminCompetitionTermsResponse:
    _ = _require_google_session_user(request, x_user_id)
    effective_lang = _resolve_effective_lang(lang_code)
    data = await _fetch_competition_terms(competition_id, effective_lang)
    terms = data.get("terms") if isinstance(data, dict) else None
    if _should_insert_default_terms(terms, effective_lang):
        default_terms = _read_default_terms_html(effective_lang)
        if default_terms.strip():
            await _post_to_ords(
                ADMIN_COMPETITIONS_TERMS_PATH,
                {
                    "competition_id": competition_id,
                    "lang_code": effective_lang,
                    "terms_text": default_terms,
                    "updated_by": None,
                },
            )
            data = await _fetch_competition_terms(competition_id, effective_lang)
            terms = data.get("terms") if isinstance(data, dict) else None
    terms_id = terms.get("terms_id") if isinstance(terms, dict) else None
    terms_text = terms.get("terms_text") if isinstance(terms, dict) else ""
    return AdminCompetitionTermsResponse(
        competition_id=competition_id,
        lang_code=effective_lang,
        terms_id=terms_id if isinstance(terms_id, int) else None,
        terms_text=terms_text if isinstance(terms_text, str) else "",
    )


@app.post("/api/admin/competitions/terms")
async def admin_update_competition_terms(
    req: AdminCompetitionTermsUpdateRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    await _post_to_ords(
        ADMIN_COMPETITIONS_TERMS_PATH,
        {
            "competition_id": req.competition_id,
            "lang_code": req.lang_code,
            "terms_text": req.terms_text,
            "updated_by": user_id,
        },
    )
    competitor_terms_cache.clear()
    return {"ok": True}







