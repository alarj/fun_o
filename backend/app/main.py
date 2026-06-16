import asyncio
import base64
import hashlib
import hmac
import json
import logging
import math
import os
import shutil
import re
import time
import uuid
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from PIL import Image
from fastapi import FastAPI, File, Form, Header, HTTPException, Request, Response, UploadFile, status
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

app = FastAPI(title="fun_o API", version="0.3.0")
logger = logging.getLogger(__name__)


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
    session_refresh_cookie_name: str = os.getenv("SESSION_REFRESH_COOKIE_NAME", "funo_session_refresh")
    session_access_ttl_minutes: int = int(os.getenv("SESSION_ACCESS_TTL_MINUTES", "15"))
    session_refresh_ttl_days: int = int(os.getenv("SESSION_REFRESH_TTL_DAYS", "14"))
    competitor_session_cookie_name: str = os.getenv("COMPETITOR_SESSION_COOKIE_NAME", "funo_competitor_session")
    competitor_participation_cookie_name: str = os.getenv("COMPETITOR_PARTICIPATION_COOKIE_NAME", "funo_participation")
    competitor_participation_cookie_ttl_hours: int = int(os.getenv("COMPETITOR_PARTICIPATION_COOKIE_TTL_HOURS", "360"))
    session_secret: str = os.getenv("SESSION_SECRET", "")
    session_cookie_secure: bool = os.getenv("SESSION_COOKIE_SECURE", "true").lower() == "true"
    lang_available: list[str] = [x.strip() for x in os.getenv("LANG_AVAILABLE", "et,en").split(",") if x.strip()]
    lang_default: str = os.getenv("LANG_DEFAULT", "et").strip() or "et"
    add_empty_competition_to_new_admin: bool = (
        os.getenv("ADD_EMPTY_COMPETITION_TO_NEW_ADMIN", "false").strip().lower() in ("1", "true", "y", "yes")
    )
    max_new_competitions: int = int(os.getenv("MAX_NEW_COMPETITIONS", "100"))
    max_competition_admin: int = int(os.getenv("MAX_COMPETITION_ADMIN", "10"))
    overlay_storage_dir: str = os.getenv("OVERLAY_STORAGE_DIR", "/app/storage/competition_overlays").strip() or "/app/storage/competition_overlays"
    overlay_max_upload_bytes: int = int(os.getenv("OVERLAY_MAX_UPLOAD_BYTES", "104857600"))
    overlay_max_dimension_px: int = int(os.getenv("OVERLAY_MAX_DIMENSION_PX", "12000"))
    overlay_tile_min_zoom: int = int(os.getenv("OVERLAY_TILE_MIN_ZOOM", "5"))
    overlay_tile_max_zoom: int = int(os.getenv("OVERLAY_TILE_MAX_ZOOM", "14"))
    overlay_tile_token_ttl_seconds: int = int(os.getenv("OVERLAY_TILE_TOKEN_TTL_SECONDS", "86400"))


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
EPK_LAYER_CODE = "maaamet_pohikaart"
EPK_OVERLAY_LAYER_CODE = "maaamet_pohikaart_overlay"
SUPPORTED_OVERLAY_IMAGE_EXTENSIONS = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
SUPPORTED_OVERLAY_WORLD_EXTENSIONS = {".png": {".pgw"}, ".jpg": {".jgw"}, ".jpeg": {".jgw"}}
OVERLAY_TILE_SIZE_PX = 256
ROUTE_HASH_COORD_PRECISION = Decimal("0.000001")
ROUTE_HASH_COORD_SCALE = Decimal("1000000")
EPSG3301_ORIGIN_X = 40500.0
EPSG3301_ORIGIN_Y = 7017000.0
EPSG3301_RESOLUTIONS = (
    4000.0, 2000.0, 1000.0, 500.0, 250.0, 125.0, 62.5, 31.25,
    15.625, 7.8125, 3.90625, 1.953125, 0.9765625, 0.48828125, 0.244140625,
)
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
    "mass_start_at",
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
API_ERROR_UNAUTHENTICATED = "api.error.unauthenticated"
ADMIN_OVERLAY_INVALID_IMAGE_FILE_MSG = "admin.overlay.invalid_image_file_msg"
ADMIN_OVERLAY_INVALID_WORLD_FILE_MSG = "admin.overlay.invalid_world_file_msg"
ADMIN_OVERLAY_INVALID_LEST97_BOUNDS_MSG = "admin.overlay.invalid_lest97_bounds_msg"
ADMIN_OVERLAY_IMAGE_FILE_SIZE_TOO_LARGE_MSG = "admin.overlay.image_file_size_too_large_msg"
ADMIN_OVERLAY_IMAGE_DIMENSIONS_TOO_LARGE_MSG = "admin.overlay.image_dimensions_too_large_msg"
ORDS_AUTH_USER_PROFILE_PATH = "auth/user-profile"
TOKEN_KIND_REFRESH = "refresh"
L_EST97_MIN_X = 300000.0
L_EST97_MAX_X = 800000.0
L_EST97_MIN_Y = 6300000.0
L_EST97_MAX_Y = 7000000.0
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
    (("ORA-20071",), ("USER_NOT_FOUND", API_ERROR_UNAUTHENTICATED)),
    (("ORA-20210",), ("COMPETITION_ADMIN_LIMIT_REACHED", "api.error.competition_admin_limit_reached")),
    (("ORA-20211",), ("GOOGLE_AUTH_REQUIRED", API_ERROR_UNAUTHENTICATED)),
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
    route: dict[str, Any] | None = None


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
    question_id: int | None = None
    lang_code: str | None = None
    answer_text: str | None = Field(default=None, max_length=4000)
    selected_option_id: int | None = None
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None


class SubmitAnswerResponse(BaseModel):
    submission_id: int
    is_correct: bool
    awarded_points: int
    total_score: int
    correct_answer_texts: list[str] = []
    other_correct_answer_texts: list[str] = []
    total_elapsed_seconds: int | None = None
    total_distance_m: int | None = None
    distance_display_allowed: bool = False
    current_rank: int | None = None


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
    competition_type: str | None = None
    current_source_hash: str | None = None
    mass_start_at: str | None = None
    declination: float = 0.0
    declination_last_updated: str | None = None
    route: dict[str, Any] | None = None
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
    id: int | None = None
    checkpoint_title: str | None = None
    submission_id: int | None = None
    submission_event_id: int | None = None
    submission_source: str | None = None
    event: str | None = None
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
    id: int | None = None
    submission_id: int | None = None
    submission_event_id: int | None = None
    submission_source: str | None = None
    event: str | None = None
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


class AdminCompetitionMapLayersResponse(BaseModel):
    competition_id: int
    layer_codes: list[str]


class AdminCompetitionMapLayersUpdateRequest(BaseModel):
    competition_id: int
    layer_codes: list[str] = []


class CompetitionOverlayBoundsResponse(BaseModel):
    min_x: float
    min_y: float
    max_x: float
    max_y: float


class CompetitorMapLayerEntry(MapLayerEntry):
    overlay_composite_base_code: str | None = None
    overlay_tile_url_template: str | None = None
    overlay_tile_min_zoom: int | None = None
    overlay_tile_max_zoom: int | None = None
    overlay_bounds_3301: CompetitionOverlayBoundsResponse | None = None


class CompetitorMapLayersResponse(BaseModel):
    competition_id: int
    items: list[CompetitorMapLayerEntry]


class CompetitionOverlayResponse(BaseModel):
    overlay_id: int | None = None
    competition_id: int
    max_upload_bytes: int | None = None
    display_label: str | None = None
    display_name: str | None = None
    attribution: str | None = None
    image_file_name: str | None = None
    world_file_name: str | None = None
    image_mime_type: str | None = None
    image_size_bytes: int | None = None
    storage_rel_path: str | None = None
    processing_status: str | None = None
    processing_error: str | None = None
    tile_storage_rel_path: str | None = None
    tile_min_zoom: int | None = None
    tile_max_zoom: int | None = None
    tiles_generated_at: str | None = None
    crs_code: str | None = None
    width_px: int | None = None
    height_px: int | None = None
    pixel_size_x: float | None = None
    pixel_size_y: float | None = None
    top_left_x: float | None = None
    top_left_y: float | None = None
    bounds_3301: CompetitionOverlayBoundsResponse | None = None
    image_url: str | None = None
    tile_url_template: str | None = None
    exists: bool = False


class CompetitionOverlayDeleteRequest(BaseModel):
    competition_id: int


class CompetitionOverlayMetaUpdateRequest(BaseModel):
    competition_id: int
    display_name: str
    attribution: str | None = None


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
    checkpoint_interaction: str | None = None
    order_no: int | None = None
    location_hint: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None
    location_required: str | None = None
    mass_start_at: str | None = None
    created_by: int | None = None


class AdminCreateCheckpointResponse(BaseModel):
    checkpoint_id: int


class AdminCreateQuestionRequest(BaseModel):
    competition_id: int | None = None
    checkpoint_id: int
    question_type: str
    input_type: str | None = None
    input_max_length: int | None = Field(default=None, le=4000)
    input_pattern: str | None = None
    points: int = 0
    wrong_points: int = 0
    lang_code: str = "et"
    question_text: str
    created_by: int | None = None


class AdminCreateQuestionResponse(BaseModel):
    question_id: int


class AdminCreateQuestionOptionRequest(BaseModel):
    competition_id: int | None = None
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
    competition_id: int | None = None
    question_id: int
    answer_value: str
    normalize_mode: str = "EXACT"
    is_correct: str = "Y"
    created_by: int | None = None


class AdminCreateQuestionAnswerResponse(BaseModel):
    answer_id: int


class AdminCompetitionOverviewResponse(BaseModel):
    data: dict[str, Any]


class AdminCompetitionRouteRequest(BaseModel):
    competition_id: int


class AdminCompetitionRouteActionRequest(BaseModel):
    competition_id: int
    requested_by: int | None = None


class AdminCompetitionRouteProcessPendingRequest(BaseModel):
    limit: int | None = None


class AdminCompetitionRouteResponse(BaseModel):
    data: dict[str, Any]


class AdminQuestionsOverviewResponse(BaseModel):
    items: list[dict[str, Any]]


class AdminUpsertAccessCodeRequest(BaseModel):
    competition_id: int
    code_type: str
    code: str | None = None
    status: str = "ACTIVE"
    max_uses: int | None = None
    force_regenerate: str | None = None
    created_by: int | None = None


class AdminUpsertAccessCodeResponse(BaseModel):
    access_code_id: int
    code: str


class AdminCompetitionsResponse(BaseModel):
    items: list[dict[str, Any]]


class SuperAdminCreateCompetitionRequest(BaseModel):
    name: str
    description: str | None = None


class SuperAdminCreateCompetitionResponse(BaseModel):
    competition_id: int
    organizer_code: str


class AdminOnboardingOptionsResponse(BaseModel):
    can_create_empty_competition: bool = False


class AdminCopyCompetitionRequest(BaseModel):
    source_competition_id: int
    copy_questions: str = "N"
    copy_organizers: str = "N"
    copy_overlay: str = "N"


class SuperAdminCopyCompetitionRequest(BaseModel):
    source_competition_id: int
    copy_questions: str = "N"
    copy_organizers: str = "N"
    copy_overlay: str = "N"


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
    checkpoint_interaction: str | None = None
    order_no: int | None = None
    location_hint: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    radius_m: float | None = None
    location_required: str | None = None
    mass_start_at: str | None = None
    updated_by: int | None = None


class AdminDeleteCheckpointRequest(BaseModel):
    competition_id: int
    checkpoint_id: int
    deleted_by: int | None = None


class AdminUpdateQuestionRequest(BaseModel):
    competition_id: int | None = None
    question_id: int
    checkpoint_id: int
    question_type: str
    input_type: str | None = None
    input_max_length: int | None = Field(default=None, le=4000)
    input_pattern: str | None = None
    points: int = 0
    wrong_points: int = 0
    lang_code: str = "et"
    question_text: str
    options_json: str | None = None
    answers_json: str | None = None
    updated_by: int | None = None


class AdminDeleteQuestionRequest(BaseModel):
    competition_id: int | None = None
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
    mass_start_at: str | None = None
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


async def _get_admin_competition_items(user_id: int) -> list[dict[str, Any]]:
    data = await _get_from_ords("admin/competitions", {"user_id": user_id})
    items = data.get("items") if isinstance(data, dict) else []
    return [item for item in items if isinstance(item, dict)] if isinstance(items, list) else []

async def _get_total_active_competitions_count() -> int:
    data = await _get_from_ords("superadmin/competitions", {})
    items = data.get("items") if isinstance(data, dict) else []
    return len(items) if isinstance(items, list) else 0


def _default_new_admin_competition_name(email: str | None) -> str:
    if isinstance(email, str) and "@" in email:
        local_part = email.split("@", 1)[0].strip()
        if local_part:
            return local_part[:200]
    return "admin"


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


def _make_admin_access_token(user_id: int, auth_provider: str) -> str:
    ttl_seconds = max(60, int(settings.session_access_ttl_minutes) * 60)
    return _make_signed_token(
        {
            "user_id": user_id,
            "auth_provider": auth_provider,
            "exp": int(time.time()) + ttl_seconds,
        }
    )


def _make_admin_refresh_token(user_id: int, auth_provider: str) -> str:
    ttl_seconds = max(3600, int(settings.session_refresh_ttl_days) * 24 * 60 * 60)
    return _make_signed_token(
        {
            "user_id": user_id,
            "auth_provider": auth_provider,
            "token_kind": TOKEN_KIND_REFRESH,
            "exp": int(time.time()) + ttl_seconds,
        }
    )


def _make_competitor_participation_token(competition_participant_id: int) -> str:
    return _make_signed_token({"competition_participant_id": competition_participant_id})


def _read_signed_token(token: str | None) -> dict[str, Any] | None:
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


def _signed_payload_is_expired(payload: dict[str, Any] | None) -> bool:
    if not isinstance(payload, dict):
        return True
    exp_value = payload.get("exp")
    if exp_value is None:
        return False
    try:
        return int(exp_value) < int(time.time())
    except Exception:
        return True


def _read_session_payload(request: Request) -> dict[str, Any] | None:
    state_payload = getattr(request.state, "admin_session_payload", None)
    if isinstance(state_payload, dict):
        return state_payload
    return _read_session_payload_from_cookie(request, settings.session_cookie_name)


def _read_competitor_session_payload(request: Request) -> dict[str, Any] | None:
    return _read_session_payload_from_cookie(request, settings.competitor_session_cookie_name)


def _read_competitor_participation_payload(request: Request) -> dict[str, Any] | None:
    return _read_session_payload_from_cookie(request, settings.competitor_participation_cookie_name)


def _read_admin_refresh_payload(request: Request) -> dict[str, Any] | None:
    return _read_session_payload_from_cookie(request, settings.session_refresh_cookie_name)


def _read_session_payload_from_cookie(request: Request, cookie_name: str) -> dict[str, Any] | None:
    payload = _read_signed_token(request.cookies.get(cookie_name))
    if _signed_payload_is_expired(payload):
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
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", API_ERROR_UNAUTHENTICATED)
    if x_user_id is not None and x_user_id != payload_user_id:
        _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "api.error.user_mismatch")
    return payload_user_id


def _require_google_session_user(request: Request, x_user_id: int | None = None) -> int:
    payload = _read_session_payload(request)
    if payload is None:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", API_ERROR_UNAUTHENTICATED)

    session_user_id = payload.get("user_id")
    if not isinstance(session_user_id, int):
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED", API_ERROR_UNAUTHENTICATED)

    if payload.get("auth_provider") != "google":
        _raise_api_error(status.HTTP_403_FORBIDDEN, "GOOGLE_AUTH_REQUIRED", API_ERROR_UNAUTHENTICATED)

    if x_user_id is not None and x_user_id != session_user_id:
        _raise_api_error(status.HTTP_403_FORBIDDEN, "USER_MISMATCH", "api.error.user_mismatch")

    return session_user_id


def _mark_admin_session_for_clear(request: Request) -> None:
    request.state.clear_admin_session = True
    request.state.admin_session_payload = None
    request.state.admin_session_refresh = None


def _mark_admin_session_for_refresh(request: Request, user_id: int, auth_provider: str) -> None:
    request.state.admin_session_payload = {"user_id": user_id, "auth_provider": auth_provider}
    request.state.admin_session_refresh = {"user_id": user_id, "auth_provider": auth_provider}


def _set_admin_session_cookies(response: Response, user_id: int, auth_provider: str) -> None:
    response.set_cookie(
        key=settings.session_cookie_name,
        value=_make_admin_access_token(user_id, auth_provider),
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )
    response.set_cookie(
        key=settings.session_refresh_cookie_name,
        value=_make_admin_refresh_token(user_id, auth_provider),
        httponly=True,
        secure=settings.session_cookie_secure,
        samesite="lax",
        path="/",
    )


def _clear_admin_session_cookies(response: Response) -> None:
    response.delete_cookie(
        key=settings.session_cookie_name,
        path="/",
        secure=settings.session_cookie_secure,
        samesite="lax",
    )
    response.delete_cookie(
        key=settings.session_refresh_cookie_name,
        path="/",
        secure=settings.session_cookie_secure,
        samesite="lax",
    )


def _is_active_google_profile(profile: dict[str, Any] | None) -> bool:
    if not isinstance(profile, dict):
        return False
    email = profile.get("email")
    auth_type = str(profile.get("auth_type") or "").upper()
    google_sub = profile.get("google_sub")
    return isinstance(email, str) and bool(email.strip()) and auth_type == "GOOGLE" and isinstance(google_sub, str) and bool(google_sub.strip())


async def _restore_admin_session_from_refresh_cookie(request: Request) -> None:
    access_payload = _read_signed_token(request.cookies.get(settings.session_cookie_name))
    if isinstance(access_payload, dict) and not _signed_payload_is_expired(access_payload):
        request.state.admin_session_payload = access_payload
        return

    refresh_payload = _read_signed_token(request.cookies.get(settings.session_refresh_cookie_name))
    if not isinstance(refresh_payload, dict) or _signed_payload_is_expired(refresh_payload):
        if access_payload is not None or refresh_payload is not None:
            _mark_admin_session_for_clear(request)
        return

    if refresh_payload.get("token_kind") != TOKEN_KIND_REFRESH:
        _mark_admin_session_for_clear(request)
        return

    user_id = refresh_payload.get("user_id")
    auth_provider = refresh_payload.get("auth_provider")
    if not isinstance(user_id, int) or auth_provider != "google":
        _mark_admin_session_for_clear(request)
        return

    try:
        profile = await _get_from_ords(ORDS_AUTH_USER_PROFILE_PATH, {"user_id": user_id})
    except HTTPException as exc:
        if exc.status_code >= status.HTTP_500_INTERNAL_SERVER_ERROR:
            request.state.admin_session_refresh_error = ApiError(
                code="SESSION_REFRESH_TEMPORARILY_UNAVAILABLE",
                message="api.error.ords_unreachable",
                details=exc.detail.get("details") if isinstance(exc.detail, dict) else None,
            ).model_dump()
            return
        _mark_admin_session_for_clear(request)
        return

    if not _is_active_google_profile(profile):
        _mark_admin_session_for_clear(request)
        return

    request.state.admin_session_profile = profile
    _mark_admin_session_for_refresh(request, user_id, "google")


def _resolve_ui_lang(lang_code: str | None) -> str:
    effective_lang = (lang_code or settings.lang_default or "et").strip().lower()
    if effective_lang not in settings.lang_available:
        effective_lang = settings.lang_default
    return effective_lang


async def _require_system_owner_session_user(request: Request, x_user_id: int | None = None) -> int:
    user_id = _require_google_session_user(request, x_user_id)
    if not await _user_has_system_owner_role(user_id):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "FORBIDDEN", API_ERROR_UNAUTHENTICATED)
    return user_id


async def _user_has_system_owner_role(user_id: int) -> bool:
    role_resp = await _get_from_ords(
        "auth/has-role",
        {"user_id": user_id, "role_code": "SYSTEM_OWNER"},
    )
    has_role = role_resp.get("has_role") if isinstance(role_resp, dict) else None
    return str(has_role).upper() == "Y"


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
    next_cache: dict[str, dict[str, str]] = {}
    for lang in settings.lang_available:
        data = await _get_from_ords(
            "i18n/translations",
            {"lang": lang, "default_lang": settings.lang_default},
        )
        raw_items = data.get("items") if isinstance(data, dict) else None
        if isinstance(raw_items, dict):
            next_cache[lang] = {str(k): str(v) for k, v in raw_items.items()}
        else:
            next_cache[lang] = {}
    i18n_cache.clear()
    i18n_cache.update(next_cache)


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


def _overlay_storage_root() -> Path:
    return Path(settings.overlay_storage_dir).resolve()


def _overlay_relative_dir(competition_id: int) -> str:
    return f"{competition_id}/{uuid.uuid4().hex}"


def _safe_overlay_path(storage_rel_path: str) -> Path:
    rel = Path(storage_rel_path)
    if rel.is_absolute():
        _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "INVALID_OVERLAY_PATH", API_ERROR_INVALID_ORDS_RESPONSE)
    full = (_overlay_storage_root() / rel).resolve()
    try:
        full.relative_to(_overlay_storage_root())
    except ValueError:
        _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "INVALID_OVERLAY_PATH", API_ERROR_INVALID_ORDS_RESPONSE)
    return full


def _normalize_overlay_extension(filename: str) -> str:
    return Path(filename or "").suffix.lower()


def _validate_overlay_filename(image_name: str, world_name: str) -> tuple[str, str]:
    image_ext = _normalize_overlay_extension(image_name)
    world_ext = _normalize_overlay_extension(world_name)
    if image_ext not in SUPPORTED_OVERLAY_IMAGE_EXTENSIONS:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_OVERLAY_IMAGE", ADMIN_OVERLAY_INVALID_IMAGE_FILE_MSG)
    if world_ext not in SUPPORTED_OVERLAY_WORLD_EXTENSIONS.get(image_ext, set()):
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_OVERLAY_WORLD_FILE", ADMIN_OVERLAY_INVALID_WORLD_FILE_MSG)
    return image_ext, world_ext


def _parse_world_file(raw_text: str) -> dict[str, float]:
    rows = [line.strip() for line in raw_text.replace("\r", "\n").split("\n") if line.strip()]
    if len(rows) != 6:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_OVERLAY_WORLD_FILE", ADMIN_OVERLAY_INVALID_WORLD_FILE_MSG)
    try:
        pixel_size_x = float(rows[0])
        rotation_x = float(rows[1])
        rotation_y = float(rows[2])
        pixel_size_y = float(rows[3])
        top_left_x = float(rows[4])
        top_left_y = float(rows[5])
    except ValueError:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_OVERLAY_WORLD_FILE", ADMIN_OVERLAY_INVALID_WORLD_FILE_MSG)
    if abs(rotation_x) > 1e-9 or abs(rotation_y) > 1e-9:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "UNSUPPORTED_OVERLAY_ROTATION", "admin.overlay.rotation_not_supported_msg")
    return {
        "pixel_size_x": pixel_size_x,
        "pixel_size_y": pixel_size_y,
        "top_left_x": top_left_x,
        "top_left_y": top_left_y,
    }


def _validate_overlay_bounds_lest97(bounds: dict[str, float]) -> None:
    min_x = float(bounds.get("min_x") or 0.0)
    max_x = float(bounds.get("max_x") or 0.0)
    min_y = float(bounds.get("min_y") or 0.0)
    max_y = float(bounds.get("max_y") or 0.0)
    if (
        min_x < L_EST97_MIN_X
        or max_x > L_EST97_MAX_X
        or min_y < L_EST97_MIN_Y
        or max_y > L_EST97_MAX_Y
    ):
        _raise_api_error(
            status.HTTP_400_BAD_REQUEST,
            "INVALID_OVERLAY_LEST97_BOUNDS",
            ADMIN_OVERLAY_INVALID_LEST97_BOUNDS_MSG,
        )


def _format_mb(value_bytes: int) -> str:
    return f"{value_bytes / (1024 * 1024):.1f}"


def _read_overlay_image_meta_from_path(image_path: Path) -> tuple[int, int]:
    try:
        with Image.open(image_path) as img:
            width, height = img.size
    except Exception:
        _raise_api_error(status.HTTP_400_BAD_REQUEST, "INVALID_OVERLAY_IMAGE", ADMIN_OVERLAY_INVALID_IMAGE_FILE_MSG)
    if width < 1 or height < 1 or width > settings.overlay_max_dimension_px or height > settings.overlay_max_dimension_px:
        _raise_api_error(
            status.HTTP_400_BAD_REQUEST,
            "OVERLAY_IMAGE_DIMENSIONS_TOO_LARGE",
            ADMIN_OVERLAY_IMAGE_DIMENSIONS_TOO_LARGE_MSG,
            {
                "actual_width": width,
                "actual_height": height,
                "max_width": settings.overlay_max_dimension_px,
                "max_height": settings.overlay_max_dimension_px,
            },
        )
    return width, height


def _overlay_temp_dir() -> Path:
    return _overlay_storage_root() / "_tmp"


def _remove_path_quietly(path: Path | None) -> None:
    if not path:
        return
    if path.is_dir():
        shutil.rmtree(path, ignore_errors=True)
    elif path.exists():
        try:
            path.unlink()
        except FileNotFoundError:
            return


async def _stream_upload_to_temp_file(upload: UploadFile, suffix: str, max_bytes: int) -> tuple[Path, int]:
    temp_root = _overlay_temp_dir()
    temp_root.mkdir(parents=True, exist_ok=True)
    temp_path = temp_root / f"{uuid.uuid4().hex}{suffix}"
    written = 0
    try:
        with temp_path.open("wb") as target:
            while True:
                chunk = await upload.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                if written > max_bytes:
                    _raise_api_error(
                        status.HTTP_400_BAD_REQUEST,
                        "OVERLAY_IMAGE_TOO_LARGE",
                        ADMIN_OVERLAY_IMAGE_FILE_SIZE_TOO_LARGE_MSG,
                        {
                            "actual_bytes": written,
                            "max_bytes": max_bytes,
                            "actual_mb": _format_mb(written),
                            "max_mb": _format_mb(max_bytes),
                        },
                    )
                target.write(chunk)
    except Exception:
        _remove_path_quietly(temp_path)
        raise
    finally:
        await upload.close()
    return temp_path, written


def _build_overlay_bounds(*, width_px: int, height_px: int, pixel_size_x: float, pixel_size_y: float, top_left_x: float, top_left_y: float) -> dict[str, float]:
    min_x = top_left_x - (pixel_size_x / 2.0)
    max_x = top_left_x + (width_px - 0.5) * pixel_size_x
    max_y = top_left_y - (pixel_size_y / 2.0)
    min_y = top_left_y + (height_px - 0.5) * pixel_size_y
    return {
        "min_x": min(min_x, max_x),
        "max_x": max(min_x, max_x),
        "min_y": min(min_y, max_y),
        "max_y": max(min_y, max_y),
    }


def _overlay_display_label(display_name: str | None) -> str | None:
    name = str(display_name or "").strip()
    if not name:
        return None
    return f"* {name}"


def _normalize_overlay_attribution(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _merge_layer_attribution(base_attribution: Any, overlay_attribution: Any) -> str:
    base = str(base_attribution or "").strip()
    overlay = _normalize_overlay_attribution(overlay_attribution)
    if base and overlay:
        return f"{base} | {overlay}"
    if overlay:
        return overlay
    if base:
        return base
    return "&copy;"


def _overlay_response_from_ords(competition_id: int, data: dict[str, Any] | None) -> CompetitionOverlayResponse:
    if not isinstance(data, dict) or not data.get("overlay_id"):
        return CompetitionOverlayResponse(
            competition_id=competition_id,
            max_upload_bytes=settings.overlay_max_upload_bytes,
            exists=False,
        )
    version = str(data.get("updated_at") or data.get("created_at") or "").replace(":", "").replace("-", "").replace("T", "").replace("Z", "")
    bounds = CompetitionOverlayBoundsResponse(
        min_x=float(data.get("min_x")),
        min_y=float(data.get("min_y")),
        max_x=float(data.get("max_x")),
        max_y=float(data.get("max_y")),
    )
    overlay_id = int(data.get("overlay_id"))
    return CompetitionOverlayResponse(
        overlay_id=overlay_id,
        competition_id=competition_id,
        max_upload_bytes=settings.overlay_max_upload_bytes,
        display_label=_overlay_display_label(str(data.get("display_name") or "")),
        display_name=str(data.get("display_name") or ""),
        attribution=_normalize_overlay_attribution(data.get("attribution")),
        image_file_name=str(data.get("image_file_name") or ""),
        world_file_name=str(data.get("world_file_name") or ""),
        image_mime_type=str(data.get("image_mime_type") or ""),
        image_size_bytes=int(data.get("image_size_bytes")) if data.get("image_size_bytes") is not None else None,
        storage_rel_path=str(data.get("storage_rel_path") or ""),
        processing_status=str(data.get("processing_status") or ""),
        processing_error=str(data.get("processing_error") or "") or None,
        tile_storage_rel_path=str(data.get("tile_storage_rel_path") or "") or None,
        tile_min_zoom=int(data.get("tile_min_zoom")) if data.get("tile_min_zoom") is not None else None,
        tile_max_zoom=int(data.get("tile_max_zoom")) if data.get("tile_max_zoom") is not None else None,
        tiles_generated_at=str(data.get("tiles_generated_at") or "") or None,
        crs_code=str(data.get("crs_code") or ""),
        width_px=int(data.get("width_px")) if data.get("width_px") is not None else None,
        height_px=int(data.get("height_px")) if data.get("height_px") is not None else None,
        pixel_size_x=float(data.get("pixel_size_x")) if data.get("pixel_size_x") is not None else None,
        pixel_size_y=float(data.get("pixel_size_y")) if data.get("pixel_size_y") is not None else None,
        top_left_x=float(data.get("top_left_x")) if data.get("top_left_x") is not None else None,
        top_left_y=float(data.get("top_left_y")) if data.get("top_left_y") is not None else None,
        bounds_3301=bounds,
        image_url=f"/api/admin/competitions/overlay/file/{competition_id}?v={version}" if version else f"/api/admin/competitions/overlay/file/{competition_id}",
        exists=True,
    )


async def _get_admin_competition_overlay(competition_id: int) -> CompetitionOverlayResponse:
    data = await _get_from_ords("admin/competitions/overlay", {"competition_id": competition_id})
    return _overlay_response_from_ords(competition_id, data)


async def _get_pending_admin_competition_overlays() -> list[CompetitionOverlayResponse]:
    payload = await _get_from_ords("admin/competitions/overlays/pending-processing", {})
    items = payload.get("items") if isinstance(payload, dict) else []
    if not isinstance(items, list):
        return []
    overlays: list[CompetitionOverlayResponse] = []
    for item in items:
        try:
            overlays.append(_overlay_response_from_ords(int(item.get("competition_id")), item))
        except Exception:
            continue
    return overlays


def _make_admin_overlay_tile_token(user_id: int, overlay: CompetitionOverlayResponse) -> str | None:
    if not overlay.exists or not overlay.overlay_id or not overlay.tile_storage_rel_path:
        return None
    return _make_signed_token(
        {
            "kind": "admin_overlay_tile",
            "user_id": user_id,
            "competition_id": overlay.competition_id,
            "overlay_id": overlay.overlay_id,
            "tile_storage_rel_path": overlay.tile_storage_rel_path,
            "exp": int(time.time()) + max(60, int(settings.overlay_tile_token_ttl_seconds)),
        }
    )


def _make_competitor_overlay_tile_token(
    user_id: int,
    competition_participant_id: int,
    overlay: CompetitionOverlayResponse,
) -> str | None:
    if not overlay.exists or not overlay.overlay_id or not overlay.tile_storage_rel_path:
        return None
    return _make_signed_token(
        {
            "kind": "competitor_overlay_tile",
            "user_id": user_id,
            "competition_participant_id": competition_participant_id,
            "competition_id": overlay.competition_id,
            "overlay_id": overlay.overlay_id,
            "tile_storage_rel_path": overlay.tile_storage_rel_path,
            "exp": int(time.time()) + max(60, int(settings.overlay_tile_token_ttl_seconds)),
        }
    )


def _decorate_admin_overlay_response(overlay: CompetitionOverlayResponse, user_id: int) -> CompetitionOverlayResponse:
    if not overlay.exists:
        overlay.max_upload_bytes = settings.overlay_max_upload_bytes
        return overlay
    overlay.display_label = overlay.display_label or _overlay_display_label(overlay.display_name)
    if overlay.processing_status == "READY" and overlay.tile_storage_rel_path and overlay.overlay_id:
        token = _make_admin_overlay_tile_token(user_id, overlay)
        if token:
            overlay.tile_url_template = (
                f"/api/admin/competitions/overlay/tiles/{overlay.overlay_id}/{{z}}/{{x}}/{{y}}.png?token={token}"
            )
    return overlay


def _build_competitor_overlay_layer_cache_item(
    base_layer: dict[str, Any],
    overlay: CompetitionOverlayResponse,
) -> dict[str, Any] | None:
    if not overlay.exists:
        return None
    if (
        str(overlay.processing_status or "").upper() != "READY"
        or str(overlay.crs_code or "").upper() != "EPSG:3301"
        or not overlay.overlay_id
        or not overlay.tile_storage_rel_path
    ):
        return None
    label = str(overlay.display_label or overlay.display_name or "").strip()
    if not label:
        return None
    return {
        **base_layer,
        "code": EPK_OVERLAY_LAYER_CODE,
        "label": label,
        "attribution": _merge_layer_attribution(base_layer.get("attribution"), overlay.attribution),
        "participant_default": False,
        "crs": "EPSG:3301",
        "overlay_composite_base_code": EPK_LAYER_CODE,
        "overlay_tile_min_zoom": overlay.tile_min_zoom,
        "overlay_tile_max_zoom": overlay.tile_max_zoom,
        "overlay_bounds_3301": overlay.bounds_3301.model_dump() if overlay.bounds_3301 else None,
        "__overlay_id": overlay.overlay_id,
        "__overlay_tile_storage_rel_path": overlay.tile_storage_rel_path,
        "__competition_id": overlay.competition_id,
    }


def _decorate_competitor_map_layer_entry(
    raw_layer: dict[str, Any],
    user_id: int,
    competition_participant_id: int,
) -> CompetitorMapLayerEntry:
    layer_data = {k: v for k, v in raw_layer.items() if not str(k).startswith("__")}
    if str(layer_data.get("code") or "").strip().lower() == EPK_OVERLAY_LAYER_CODE:
        overlay = CompetitionOverlayResponse(
            overlay_id=int(raw_layer.get("__overlay_id") or 0) or None,
            competition_id=int(raw_layer.get("__competition_id") or 0),
            tile_storage_rel_path=str(raw_layer.get("__overlay_tile_storage_rel_path") or "").strip() or None,
            exists=True,
        )
        token = _make_competitor_overlay_tile_token(user_id, competition_participant_id, overlay)
        if token and overlay.overlay_id:
            layer_data["overlay_tile_url_template"] = (
                f"/api/competitor/competitions/overlay/tiles/{overlay.overlay_id}/{{z}}/{{x}}/{{y}}.png?token={token}"
            )
    return CompetitorMapLayerEntry(**layer_data)


async def _set_overlay_processing_status(
    overlay_id: int,
    processing_status: str,
    *,
    updated_by: int | None,
    processing_error: str | None = None,
    tile_storage_rel_path: str | None = None,
    tile_min_zoom: int | None = None,
    tile_max_zoom: int | None = None,
) -> None:
    await _post_to_ords(
        "admin/competitions/overlay/processing",
        {
            "overlay_id": overlay_id,
            "processing_status": processing_status,
            "processing_error": processing_error,
            "tile_storage_rel_path": tile_storage_rel_path,
            "tile_min_zoom": tile_min_zoom,
            "tile_max_zoom": tile_max_zoom,
            "updated_by": updated_by,
        },
    )


def _ensure_overlay_storage_root_exists() -> None:
    _overlay_storage_root().mkdir(parents=True, exist_ok=True)


def _remove_overlay_dir(storage_rel_path: str | None) -> None:
    if not storage_rel_path:
        return
    target = _safe_overlay_path(storage_rel_path)
    if target.exists():
        shutil.rmtree(target, ignore_errors=True)


def _overlay_zoom_range(overlay: CompetitionOverlayResponse) -> tuple[int, int]:
    min_zoom = max(0, min(len(EPSG3301_RESOLUTIONS) - 1, int(settings.overlay_tile_min_zoom)))
    max_zoom = max(0, min(len(EPSG3301_RESOLUTIONS) - 1, int(settings.overlay_tile_max_zoom)))
    if max_zoom < min_zoom:
        max_zoom = min_zoom
    return min_zoom, max_zoom


def _overlay_source_path(overlay: CompetitionOverlayResponse) -> Path:
    if not overlay.storage_rel_path or not overlay.image_file_name:
        raise FileNotFoundError("overlay source path missing")
    return _safe_overlay_path(overlay.storage_rel_path) / overlay.image_file_name


def _overlay_tiles_rel_path(overlay: CompetitionOverlayResponse) -> str:
    return f"{str(overlay.storage_rel_path or '').rstrip('/').rstrip('\\')}/tiles"


def _generate_overlay_tiles_sync(overlay: CompetitionOverlayResponse) -> tuple[str, int, int]:
    if not overlay.exists or not overlay.bounds_3301:
        raise ValueError("overlay does not exist")
    if not overlay.storage_rel_path:
        raise ValueError("overlay storage path missing")

    source_path = _overlay_source_path(overlay)
    if not source_path.exists():
        raise FileNotFoundError("overlay source image not found")

    bounds = overlay.bounds_3301
    pixel_size_x = float(overlay.pixel_size_x or 0)
    pixel_size_y = abs(float(overlay.pixel_size_y or 0))
    if pixel_size_x <= 0 or pixel_size_y <= 0:
        raise ValueError("overlay pixel size invalid")

    tile_rel_path = _overlay_tiles_rel_path(overlay)
    tile_root = _safe_overlay_path(tile_rel_path)
    if tile_root.exists():
        shutil.rmtree(tile_root, ignore_errors=True)
    tile_root.mkdir(parents=True, exist_ok=True)

    min_zoom, max_zoom = _overlay_zoom_range(overlay)
    source_min_x = float(bounds.min_x)
    source_max_x = float(bounds.max_x)
    source_min_y = float(bounds.min_y)
    source_max_y = float(bounds.max_y)
    epsilon = 1e-9

    with Image.open(source_path) as src_img:
        for zoom in range(min_zoom, max_zoom + 1):
            resolution = float(EPSG3301_RESOLUTIONS[zoom])
            tile_world_size = OVERLAY_TILE_SIZE_PX * resolution
            x_start = max(0, int(math.floor((source_min_x - EPSG3301_ORIGIN_X) / tile_world_size)))
            x_end = max(0, int(math.floor(((source_max_x - epsilon) - EPSG3301_ORIGIN_X) / tile_world_size)))
            y_start = max(0, int(math.floor((EPSG3301_ORIGIN_Y - source_max_y) / tile_world_size)))
            y_end = max(0, int(math.floor((EPSG3301_ORIGIN_Y - (source_min_y + epsilon)) / tile_world_size)))

            for tile_x in range(x_start, x_end + 1):
                tile_min_x = EPSG3301_ORIGIN_X + tile_x * tile_world_size
                tile_max_x = tile_min_x + tile_world_size
                intersect_min_x = max(tile_min_x, source_min_x)
                intersect_max_x = min(tile_max_x, source_max_x)
                if intersect_min_x >= intersect_max_x:
                    continue

                for tile_y in range(y_start, y_end + 1):
                    tile_max_y = EPSG3301_ORIGIN_Y - tile_y * tile_world_size
                    tile_min_y = tile_max_y - tile_world_size
                    intersect_min_y = max(tile_min_y, source_min_y)
                    intersect_max_y = min(tile_max_y, source_max_y)
                    if intersect_min_y >= intersect_max_y:
                        continue

                    src_left = (intersect_min_x - source_min_x) / pixel_size_x
                    src_right = (intersect_max_x - source_min_x) / pixel_size_x
                    src_top = (source_max_y - intersect_max_y) / pixel_size_y
                    src_bottom = (source_max_y - intersect_min_y) / pixel_size_y
                    crop_box = (
                        max(0, int(math.floor(src_left))),
                        max(0, int(math.floor(src_top))),
                        min(int(overlay.width_px or src_img.width), int(math.ceil(src_right))),
                        min(int(overlay.height_px or src_img.height), int(math.ceil(src_bottom))),
                    )
                    if crop_box[2] <= crop_box[0] or crop_box[3] <= crop_box[1]:
                        continue

                    target_left = max(0, int(round((intersect_min_x - tile_min_x) / resolution)))
                    target_right = min(OVERLAY_TILE_SIZE_PX, int(round((intersect_max_x - tile_min_x) / resolution)))
                    target_top = max(0, int(round((tile_max_y - intersect_max_y) / resolution)))
                    target_bottom = min(OVERLAY_TILE_SIZE_PX, int(round((tile_max_y - intersect_min_y) / resolution)))
                    if target_right <= target_left or target_bottom <= target_top:
                        continue

                    tile_image = Image.new("RGBA", (OVERLAY_TILE_SIZE_PX, OVERLAY_TILE_SIZE_PX), (0, 0, 0, 0))
                    crop = src_img.crop(crop_box)
                    resized = crop.resize((target_right - target_left, target_bottom - target_top), Image.Resampling.LANCZOS)
                    if resized.mode != "RGBA":
                        resized = resized.convert("RGBA")
                    tile_image.paste(resized, (target_left, target_top), resized)

                    tile_dir = tile_root / str(zoom) / str(tile_x)
                    tile_dir.mkdir(parents=True, exist_ok=True)
                    tile_image.save(tile_dir / f"{tile_y}.png", format="PNG", optimize=True)

    return tile_rel_path, min_zoom, max_zoom


async def _process_overlay_tiles(overlay: CompetitionOverlayResponse, user_id: int | None) -> None:
    if not overlay.exists or not overlay.overlay_id or not overlay.storage_rel_path:
        return
    try:
        await _set_overlay_processing_status(overlay.overlay_id, "PROCESSING", updated_by=user_id)
        competitor_map_layers_cache.pop(overlay.competition_id, None)
        tile_rel_path, tile_min_zoom, tile_max_zoom = await asyncio.to_thread(_generate_overlay_tiles_sync, overlay)
        refreshed = await _get_admin_competition_overlay(overlay.competition_id)
        if (
            not refreshed.exists
            or refreshed.overlay_id != overlay.overlay_id
            or refreshed.storage_rel_path != overlay.storage_rel_path
        ):
            _remove_overlay_dir(tile_rel_path)
            return
        await _set_overlay_processing_status(
            overlay.overlay_id,
            "READY",
            updated_by=user_id,
            tile_storage_rel_path=tile_rel_path,
            tile_min_zoom=tile_min_zoom,
            tile_max_zoom=tile_max_zoom,
        )
        competitor_map_layers_cache.pop(overlay.competition_id, None)
    except Exception as exc:
        _remove_overlay_dir(_overlay_tiles_rel_path(overlay))
        try:
            await _set_overlay_processing_status(
                overlay.overlay_id,
                "FAILED",
                updated_by=user_id,
                processing_error=str(exc)[:2000],
            )
            competitor_map_layers_cache.pop(overlay.competition_id, None)
        except Exception:
            return


def _schedule_overlay_processing(overlay: CompetitionOverlayResponse, user_id: int | None) -> None:
    if not overlay.exists or not overlay.overlay_id:
        return
    try:
        task = asyncio.create_task(_process_overlay_tiles(overlay, user_id))
        background_tasks.add(task)
        task.add_done_callback(background_tasks.discard)
    except RuntimeError:
        pass


async def _resume_pending_overlay_processing() -> None:
    try:
        pending = await _get_pending_admin_competition_overlays()
    except Exception:
        return
    for overlay in pending:
        if overlay.exists and overlay.overlay_id:
            _schedule_overlay_processing(overlay, None)


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


def _format_route_hash_number(value: Any) -> str:
    rounded = Decimal(str(value)).quantize(ROUTE_HASH_COORD_PRECISION, rounding=ROUND_HALF_UP)
    scaled = int((rounded * ROUTE_HASH_COORD_SCALE).to_integral_value(rounding=ROUND_HALF_UP))
    return str(scaled)


def _build_route_source_hash_payload(competition_type: str | None, items: list[dict[str, Any]]) -> str:
    normalized_type = str(competition_type or "R").strip().upper() or "R"
    sortable: list[tuple[int, str, str, str, str]] = []
    for row in items:
        if not isinstance(row, dict):
            continue
        checkpoint_id = row.get("checkpoint_id")
        latitude = row.get("latitude")
        longitude = row.get("longitude")
        if not isinstance(checkpoint_id, int):
            continue
        if not isinstance(latitude, (int, float)) or not isinstance(longitude, (int, float)):
            continue
        checkpoint_type = str(row.get("checkpoint_type") or "NORMAL").strip().upper() or "NORMAL"
        order_no = row.get("checkpoint_order_no")
        order_value = str(int(order_no)) if isinstance(order_no, (int, float)) else ""
        sortable.append(
            (
                checkpoint_id,
                checkpoint_type,
                order_value,
                _format_route_hash_number(latitude),
                _format_route_hash_number(longitude),
            )
        )
    sortable.sort(key=lambda x: x[0])
    rows = [f"{checkpoint_id}:{checkpoint_type}:{order_value}:{latitude}:{longitude}" for checkpoint_id, checkpoint_type, order_value, latitude, longitude in sortable]
    return f"T|{normalized_type}|" + "|".join(rows) + ("|" if rows else "")


def _compute_route_source_hash_from_items(competition_type: str | None, items: list[dict[str, Any]]) -> str:
    payload = _build_route_source_hash_payload(competition_type, items)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest().upper()


def _normalize_route_payload(route_raw: Any) -> dict[str, Any] | None:
    if isinstance(route_raw, str):
        try:
            route_raw = json.loads(route_raw)
        except Exception as exc:
            logger.warning("Failed to parse route payload JSON: %s", exc)
            return None
    if not isinstance(route_raw, dict):
        return None
    route = dict(route_raw)
    route_order_raw = route.get("route_order_json")
    if isinstance(route_order_raw, str):
        try:
            route["route_order_json"] = json.loads(route_order_raw)
        except Exception as exc:
            logger.warning("Failed to parse route_order_json: %s", exc)
            route["route_order_json"] = None
    elif route_order_raw is not None and not isinstance(route_order_raw, list):
        route["route_order_json"] = None
    return route


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


def _has_mass_start_begun(value: Any) -> bool:
    dt = _parse_utc_datetime(value)
    if dt is None:
        return False
    return dt <= datetime.now(timezone.utc)


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
                "competition_type": cached.get("competition_type"),
                "current_source_hash": cached.get("current_source_hash"),
                "mass_start_at": cached.get("mass_start_at"),
                "items": cached_items,
                "declination": cached.get("declination", 0.0),
                "declination_last_updated": cached.get("declination_last_updated"),
                "route": cached.get("route"),
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
    competition_type = _normalize_competition_type(ords_response.get("competition_type") if isinstance(ords_response, dict) else "R")
    current_source_hash_raw = ords_response.get("current_source_hash") if isinstance(ords_response, dict) else None
    current_source_hash = current_source_hash_raw if isinstance(current_source_hash_raw, str) and current_source_hash_raw.strip() else None
    mass_start_at_raw = ords_response.get("mass_start_at") if isinstance(ords_response, dict) else None
    mass_start_at = mass_start_at_raw if isinstance(mass_start_at_raw, str) and mass_start_at_raw.strip() else None
    declination_raw = ords_response.get("declination") if isinstance(ords_response, dict) else 0
    declination = float(declination_raw) if isinstance(declination_raw, (int, float)) else 0.0
    declination_last_updated = ords_response.get("declination_last_updated") if isinstance(ords_response, dict) else None
    route = _normalize_route_payload(ords_response.get("route") if isinstance(ords_response, dict) else None)
    locally_computed_hash = _compute_route_source_hash_from_items(competition_type, items)
    route_valid = False
    if current_source_hash and current_source_hash == locally_computed_hash and isinstance(route, dict):
        calculated_source_hash = route.get("calculated_source_hash")
        route_valid = isinstance(calculated_source_hash, str) and calculated_source_hash == current_source_hash
    if not route_valid:
        route = None
    payload = {
        "competition_type": competition_type,
        "current_source_hash": current_source_hash if current_source_hash == locally_computed_hash else locally_computed_hash,
        "mass_start_at": mass_start_at,
        "items": items,
        "declination": declination,
        "declination_last_updated": declination_last_updated if isinstance(declination_last_updated, str) else None,
        "route": route,
    }
    map_checkpoints_cache[key] = {"cached_at": now, **payload}
    return payload


@app.on_event("startup")
async def startup_event() -> None:
    await _load_i18n_cache()
    await _resume_pending_overlay_processing()


@app.middleware("http")
async def admin_session_refresh_middleware(request: Request, call_next):
    request.state.admin_session_payload = None
    request.state.admin_session_profile = None
    request.state.admin_session_refresh = None
    request.state.admin_session_refresh_error = None
    request.state.clear_admin_session = False

    path = request.url.path
    if (
        path.startswith("/api/admin/")
        or path.startswith("/api/superadmin/")
        or path == "/api/auth/session"
    ):
        await _restore_admin_session_from_refresh_cookie(request)

    response = await call_next(request)

    refresh_error = getattr(request.state, "admin_session_refresh_error", None)
    if (
        isinstance(refresh_error, dict)
        and not bool(getattr(request.state, "clear_admin_session", False))
        and response.status_code == status.HTTP_401_UNAUTHORIZED
    ):
        response = JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"detail": refresh_error},
        )

    refresh_payload = getattr(request.state, "admin_session_refresh", None)
    if isinstance(refresh_payload, dict):
        user_id = refresh_payload.get("user_id")
        auth_provider = refresh_payload.get("auth_provider")
        if isinstance(user_id, int) and isinstance(auth_provider, str) and auth_provider:
            _set_admin_session_cookies(response, user_id, auth_provider)

    if bool(getattr(request.state, "clear_admin_session", False)):
        _clear_admin_session_cookies(response)

    return response


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


@app.get("/api/content/help", response_model=IntroContentResponse)
async def get_help_content(lang: str | None = None) -> IntroContentResponse:
    resolved_lang, html = _read_content_html_with_fallback("help", lang)
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
    user_id = _resolve_user_id(request, None, x_user_id)
    competition_participant_id = _read_competitor_participation_id(request)
    if competition_participant_id is None:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "NOT_AUTHENTICATED", "api.error.not_authenticated")
    cached = competitor_map_layers_cache.get(competition_id)
    if isinstance(cached, dict):
        cached_items = cached.get("items")
        if isinstance(cached_items, list):
            return CompetitorMapLayersResponse(
                competition_id=competition_id,
                items=[_decorate_competitor_map_layer_entry(item, user_id, competition_participant_id) for item in cached_items],
            )

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
    if EPK_OVERLAY_LAYER_CODE in selected_set:
        selected_set.add(EPK_LAYER_CODE)
    overlay: CompetitionOverlayResponse | None = None
    should_offer_overlay = EPK_OVERLAY_LAYER_CODE in selected_set and EPK_LAYER_CODE in enabled_by_code
    if should_offer_overlay:
        overlay = await _get_admin_competition_overlay(competition_id)
    resolved_layers: list[MapLayerEntry] = []
    cache_items: list[dict[str, Any]] = []
    for layer in enabled_layers:
        code = str(layer.get("code", "")).strip().lower()
        if not code or code not in selected_set:
            continue
        cache_items.append(dict(layer))
        if code == EPK_LAYER_CODE and overlay is not None:
            overlay_layer = _build_competitor_overlay_layer_cache_item(layer, overlay)
            if overlay_layer is not None:
                cache_items.append(overlay_layer)

    competitor_map_layers_cache[competition_id] = {
        "cached_at": time.time(),
        "items": cache_items,
    }
    resolved_layers = [
        _decorate_competitor_map_layer_entry(item, user_id, competition_participant_id)
        for item in cache_items
    ]
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

    _set_admin_session_cookies(response, user_id, "google")

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
    _clear_admin_session_cookies(response)
    return {"ok": True}


@app.get("/api/auth/session", response_model=SessionInfoResponse)
async def auth_session(request: Request) -> SessionInfoResponse:
    payload = _read_session_payload(request)
    refresh_error = getattr(request.state, "admin_session_refresh_error", None)
    if payload is None:
        if isinstance(refresh_error, dict):
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=refresh_error)
        return SessionInfoResponse(authenticated=False)
    if payload.get("auth_provider") != "google":
        _mark_admin_session_for_clear(request)
        return SessionInfoResponse(authenticated=False)
    user_id = payload.get("user_id") if isinstance(payload.get("user_id"), int) else None
    profile = getattr(request.state, "admin_session_profile", None)
    if not isinstance(profile, dict) and user_id is not None:
        try:
            profile = await _get_from_ords(ORDS_AUTH_USER_PROFILE_PATH, {"user_id": user_id})
        except HTTPException as exc:
            if exc.status_code >= status.HTTP_500_INTERNAL_SERVER_ERROR:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=ApiError(
                        code="SESSION_PROFILE_TEMPORARILY_UNAVAILABLE",
                        message="api.error.ords_unreachable",
                        details=exc.detail.get("details") if isinstance(exc.detail, dict) else None,
                    ).model_dump(),
                ) from exc
            profile = None
    if not _is_active_google_profile(profile):
        _mark_admin_session_for_clear(request)
        return SessionInfoResponse(authenticated=False)
    email = profile.get("email") if isinstance(profile.get("email"), str) else None
    full_name = profile.get("full_name") if isinstance(profile.get("full_name"), str) else None
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
            route=participant.get("route") if isinstance(participant.get("route"), dict) else None,
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
            "max_admin_competitions": settings.max_competition_admin,
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
    effective_lang = (req.lang_code or settings.lang_default or "et").strip().lower()
    if effective_lang not in settings.lang_available:
        effective_lang = settings.lang_default

    payload = {
        "user_id": user_id,
        "competition_id": req.competition_id,
        "checkpoint_id": req.checkpoint_id,
        "lang_code": effective_lang,
        "default_lang_code": settings.lang_default,
        "answer_text": req.answer_text,
        "selected_option_id": req.selected_option_id,
        "latitude": req.latitude,
        "longitude": req.longitude,
        "radius_m": req.radius_m,
    }
    if req.question_id is not None:
        payload["question_id"] = req.question_id
    ords_response = await _post_to_ords("submissions", payload)
    submission_id = ords_response.get("submission_id")
    is_correct_raw = ords_response.get("is_correct")
    awarded_points = ords_response.get("awarded_points")
    total_score = ords_response.get("total_score")
    correct_answer_texts_raw = ords_response.get("correct_answer_texts")
    other_correct_answer_texts_raw = ords_response.get("other_correct_answer_texts")
    total_elapsed_seconds = ords_response.get("total_elapsed_seconds")
    total_distance_m = ords_response.get("total_distance_m")
    distance_display_allowed_raw = ords_response.get("distance_display_allowed")
    current_rank = ords_response.get("current_rank")
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
    correct_answer_texts = (
        [str(v) for v in correct_answer_texts_raw if isinstance(v, str) and v.strip()]
        if isinstance(correct_answer_texts_raw, list)
        else []
    )
    other_correct_answer_texts = (
        [str(v) for v in other_correct_answer_texts_raw if isinstance(v, str) and v.strip()]
        if isinstance(other_correct_answer_texts_raw, list)
        else []
    )
    distance_display_allowed = distance_display_allowed_raw in (True, "Y", "y", "true", "TRUE", 1)
    # Event-driven cache refresh for competitor status after successful submit.
    map_checkpoints_cache.pop(_map_cache_key(competition_id=req.competition_id, user_id=user_id), None)
    open_checkpoints_last_response.pop(_open_checkpoints_key(competition_id=req.competition_id, user_id=user_id), None)
    return SubmitAnswerResponse(
        submission_id=submission_id,
        is_correct=(is_correct_raw == "Y"),
        awarded_points=awarded_points,
        total_score=total_score,
        correct_answer_texts=correct_answer_texts,
        other_correct_answer_texts=other_correct_answer_texts,
        total_elapsed_seconds=total_elapsed_seconds if isinstance(total_elapsed_seconds, int) else None,
        total_distance_m=total_distance_m if isinstance(total_distance_m, int) else None,
        distance_display_allowed=distance_display_allowed,
        current_rank=current_rank if isinstance(current_rank, int) else None,
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
        competition_type=payload.get("competition_type") if isinstance(payload.get("competition_type"), str) else None,
        current_source_hash=payload.get("current_source_hash") if isinstance(payload.get("current_source_hash"), str) else None,
        mass_start_at=payload.get("mass_start_at") if isinstance(payload.get("mass_start_at"), str) else None,
        items=payload.get("items") if isinstance(payload.get("items"), list) else [],
        declination=float(payload.get("declination", 0.0)) if isinstance(payload.get("declination"), (int, float)) else 0.0,
        declination_last_updated=payload.get("declination_last_updated") if isinstance(payload.get("declination_last_updated"), str) else None,
        route=payload.get("route") if isinstance(payload.get("route"), dict) else None,
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
    comp_type = "R"
    start_exists = False
    start_answered = False
    finish_answered = False
    next_ordered_checkpoint_id: int | None = None
    mass_start_at = map_payload.get("mass_start_at") if isinstance(map_payload.get("mass_start_at"), str) else None
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
        if not start_answered and _has_mass_start_begun(mass_start_at):
            start_answered = any(
                _normalize_checkpoint_type(row.get("checkpoint_type")) == "START"
                and str(row.get("checkpoint_interaction") or "").strip().upper() == "MASS_START"
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
        effective_radius = cp_radius if isinstance(cp_radius, (int, float)) and cp_radius > 0 else None
        if not isinstance(effective_radius, (int, float)) or effective_radius <= 0:
            items.append(CompetitorCheckpointAccessEntry(checkpoint_id=cp_id, can_open=False, reason="not_open"))
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
                "radius_m": req.radius_m if isinstance(req.radius_m, (int, float)) else None,
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
                    id=item.get("id") if isinstance(item.get("id"), int) else None,
                    checkpoint_title=item.get("checkpoint_title") if isinstance(item.get("checkpoint_title"), str) else None,
                    submission_id=item.get("submission_id") if isinstance(item.get("submission_id"), int) else None,
                    submission_event_id=item.get("submission_event_id") if isinstance(item.get("submission_event_id"), int) else None,
                    submission_source=item.get("submission_source") if isinstance(item.get("submission_source"), str) else None,
                    event=item.get("event") if isinstance(item.get("event"), str) else None,
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
                    id=item.get("id") if isinstance(item.get("id"), int) else None,
                    submission_id=item.get("submission_id") if isinstance(item.get("submission_id"), int) else None,
                    submission_event_id=item.get("submission_event_id") if isinstance(item.get("submission_event_id"), int) else None,
                    submission_source=item.get("submission_source") if isinstance(item.get("submission_source"), str) else None,
                    event=item.get("event") if isinstance(item.get("event"), str) else None,
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
    if req.checkpoint_interaction is not None:
        payload["checkpoint_interaction"] = req.checkpoint_interaction
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
    if req.mass_start_at is not None:
        payload["mass_start_at"] = req.mass_start_at

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
            "competition_id": req.competition_id,
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
    if req.competition_id is not None:
        _invalidate_competition_cache(req.competition_id)
    else:
        map_checkpoints_cache.clear()
        open_checkpoints_last_response.clear()
    return AdminCreateQuestionResponse(question_id=question_id)


@app.post("/api/admin/question-options", response_model=AdminCreateQuestionOptionResponse)
async def admin_create_question_option(req: AdminCreateQuestionOptionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionOptionResponse:
    user_id = _require_google_session_user(request, x_user_id)
    ords_response = await _post_to_ords(
        "admin/question-options",
        {
            "competition_id": req.competition_id,
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
    if req.competition_id is not None:
        _invalidate_competition_cache(req.competition_id)
    else:
        map_checkpoints_cache.clear()
        open_checkpoints_last_response.clear()
    return AdminCreateQuestionOptionResponse(option_id=option_id)


@app.post("/api/admin/question-answers", response_model=AdminCreateQuestionAnswerResponse)
async def admin_create_question_answer(req: AdminCreateQuestionAnswerRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCreateQuestionAnswerResponse:
    user_id = _require_google_session_user(request, x_user_id)
    ords_response = await _post_to_ords(
        "admin/question-answers",
        {
            "competition_id": req.competition_id,
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
    if req.competition_id is not None:
        _invalidate_competition_cache(req.competition_id)
    else:
        map_checkpoints_cache.clear()
        open_checkpoints_last_response.clear()
    return AdminCreateQuestionAnswerResponse(answer_id=answer_id)


@app.get("/api/admin/competition-overview", response_model=AdminCompetitionOverviewResponse)
async def admin_competition_overview(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionOverviewResponse:
    _ = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords("admin/competition-overview", {"competition_id": competition_id})
    return AdminCompetitionOverviewResponse(data=data if isinstance(data, dict) else {})


@app.get("/api/admin/competitions/route", response_model=AdminCompetitionRouteResponse)
async def admin_competition_route(competition_id: int, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionRouteResponse:
    _ = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords("admin/competitions/route", {"competition_id": competition_id})
    return AdminCompetitionRouteResponse(data=data if isinstance(data, dict) else {})


@app.post("/api/admin/competitions/route/request")
async def admin_request_competition_route(req: AdminCompetitionRouteActionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    await _post_to_ords(
        "admin/competitions/route/request",
        {
            "competition_id": req.competition_id,
            "requested_by": req.requested_by if isinstance(req.requested_by, int) else user_id,
        },
    )
    return {"ok": True}


@app.post("/api/admin/competitions/route/calculate-now", response_model=AdminCompetitionRouteResponse)
async def admin_calculate_competition_route_now(req: AdminCompetitionRouteActionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionRouteResponse:
    user_id = _require_google_session_user(request, x_user_id)
    data = await _post_to_ords(
        "admin/competitions/route/calculate-now",
        {
            "competition_id": req.competition_id,
            "requested_by": req.requested_by if isinstance(req.requested_by, int) else user_id,
        },
    )
    _invalidate_competition_cache(req.competition_id)
    return AdminCompetitionRouteResponse(data=data if isinstance(data, dict) else {})


@app.post("/api/admin/competitions/routes/process-pending")
async def admin_process_pending_competition_routes(req: AdminCompetitionRouteProcessPendingRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, int]:
    _ = _require_google_session_user(request, x_user_id)
    data = await _post_to_ords(
        "admin/competitions/routes/process-pending",
        {"limit": req.limit} if isinstance(req.limit, int) else {},
    )
    map_checkpoints_cache.clear()
    open_checkpoints_last_response.clear()
    processed_count = data.get("processed_count") if isinstance(data, dict) else 0
    return {"processed_count": processed_count if isinstance(processed_count, int) else 0}


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
    payload: dict[str, Any] = {
        "competition_id": req.competition_id,
        "code_type": req.code_type,
        "status": req.status,
        "max_uses": req.max_uses,
        "created_by": user_id,
    }
    if req.code is not None:
        payload["code"] = req.code
    if req.force_regenerate is not None:
        payload["force_regenerate"] = req.force_regenerate
    ords_response = await _post_to_ords(
        "admin/access-codes",
        payload,
    )
    access_code_id = ords_response.get("access_code_id")
    code = ords_response.get("code")
    if not isinstance(access_code_id, int) or not isinstance(code, str) or not code.strip():
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    return AdminUpsertAccessCodeResponse(access_code_id=access_code_id, code=code.strip())


@app.get("/api/admin/competitions", response_model=AdminCompetitionsResponse)
async def admin_competitions(request: Request, x_user_id: int | None = Header(default=None)) -> AdminCompetitionsResponse:
    user_id = _require_google_session_user(request, x_user_id)
    data = await _get_from_ords("admin/competitions", {"user_id": user_id})
    items = data.get("items") if isinstance(data, dict) else []
    return AdminCompetitionsResponse(items=items if isinstance(items, list) else [])


@app.get("/api/admin/onboarding-options", response_model=AdminOnboardingOptionsResponse)
async def admin_onboarding_options(request: Request, x_user_id: int | None = Header(default=None)) -> AdminOnboardingOptionsResponse:
    user_id = _require_google_session_user(request, x_user_id)
    if await _user_has_system_owner_role(user_id):
        return AdminOnboardingOptionsResponse(can_create_empty_competition=False)

    if not settings.add_empty_competition_to_new_admin or settings.max_new_competitions <= 0:
        return AdminOnboardingOptionsResponse(can_create_empty_competition=False)
    if await _get_admin_competition_items(user_id):
        return AdminOnboardingOptionsResponse(can_create_empty_competition=False)
    total_competitions = await _get_total_active_competitions_count()
    return AdminOnboardingOptionsResponse(
        can_create_empty_competition=total_competitions < settings.max_new_competitions
    )

@app.post("/api/admin/competitions/create-empty", response_model=SuperAdminCreateCompetitionResponse)
async def admin_create_empty_competition(
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> SuperAdminCreateCompetitionResponse:
    user_id = _require_google_session_user(request, x_user_id)
    if await _user_has_system_owner_role(user_id):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "FORBIDDEN", API_ERROR_UNAUTHENTICATED)
    if not settings.add_empty_competition_to_new_admin or settings.max_new_competitions <= 0:
        _raise_api_error(status.HTTP_409_CONFLICT, "EMPTY_CREATE_DISABLED", "admin.no_org.empty_create_unavailable_msg")
    if await _get_admin_competition_items(user_id):
        _raise_api_error(status.HTTP_409_CONFLICT, "EMPTY_CREATE_DISABLED", "admin.no_org.empty_create_unavailable_msg")
    total_competitions = await _get_total_active_competitions_count()
    if total_competitions >= settings.max_new_competitions:
        _raise_api_error(status.HTTP_409_CONFLICT, "EMPTY_CREATE_DISABLED", "admin.no_org.empty_create_unavailable_msg")

    profile = await _get_from_ords(ORDS_AUTH_USER_PROFILE_PATH, {"user_id": user_id})
    email = profile.get("email") if isinstance(profile, dict) else None
    data = await _post_to_ords(
        "admin/competitions/create-empty",
        {
            "name": _default_new_admin_competition_name(email),
            "description": None,
            "created_by": user_id,
            "add_creator_as_organizer": "Y",
            "max_admin_competitions": settings.max_competition_admin,
        },
    )
    competition_id = data.get("competition_id") if isinstance(data, dict) else None
    organizer_code = data.get("organizer_code") if isinstance(data, dict) else None
    if not isinstance(competition_id, int) or not isinstance(organizer_code, str) or not organizer_code.strip():
        _raise_api_error(status.HTTP_502_BAD_GATEWAY, "INVALID_ORDS_RESPONSE", API_ERROR_INVALID_ORDS_RESPONSE)
    await _ensure_default_terms_for_competition(competition_id)
    return SuperAdminCreateCompetitionResponse(
        competition_id=competition_id,
        organizer_code=organizer_code,
    )


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


@app.get("/api/admin/competitions/overlay", response_model=CompetitionOverlayResponse)
async def admin_competition_overlay(
    competition_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> CompetitionOverlayResponse:
    user_id = _require_google_session_user(request, x_user_id)
    overlay = await _get_admin_competition_overlay(competition_id)
    return _decorate_admin_overlay_response(overlay, user_id)


@app.post("/api/admin/competitions/overlay/upload", response_model=CompetitionOverlayResponse)
async def admin_competition_overlay_upload(
    request: Request,
    competition_id: int = Form(...),
    display_name: str = Form(...),
    attribution: str = Form(""),
    image_file: UploadFile = File(...),
    world_file: UploadFile = File(...),
    x_user_id: int | None = Header(default=None),
) -> CompetitionOverlayResponse:
    user_id = _require_google_session_user(request, x_user_id)
    _ensure_overlay_storage_root_exists()
    image_name = image_file.filename or "map.png"
    world_name = world_file.filename or "map.pgw"
    image_ext, world_ext = _validate_overlay_filename(image_name, world_name)
    temp_image_path, image_size_bytes = await _stream_upload_to_temp_file(
        image_file,
        image_ext,
        settings.overlay_max_upload_bytes,
    )
    world_bytes = await world_file.read()
    try:
        world_text = world_bytes.decode("utf-8-sig")
    except UnicodeDecodeError:
        _raise_api_error(
            status.HTTP_400_BAD_REQUEST,
            "INVALID_OVERLAY_WORLD_FILE",
            ADMIN_OVERLAY_INVALID_WORLD_FILE_MSG,
        )

    try:
        world_meta = _parse_world_file(world_text)
        width_px, height_px = _read_overlay_image_meta_from_path(temp_image_path)
        bounds = _build_overlay_bounds(
            width_px=width_px,
            height_px=height_px,
            pixel_size_x=world_meta["pixel_size_x"],
            pixel_size_y=world_meta["pixel_size_y"],
            top_left_x=world_meta["top_left_x"],
            top_left_y=world_meta["top_left_y"],
        )
        _validate_overlay_bounds_lest97(bounds)

        previous_overlay = await _get_admin_competition_overlay(competition_id)
        storage_rel_path = _overlay_relative_dir(competition_id)
        storage_dir = _safe_overlay_path(storage_rel_path)
        storage_dir.mkdir(parents=True, exist_ok=True)
        image_target_name = f"map{'.jpg' if image_ext in ('.jpg', '.jpeg') else image_ext}"
        world_target_name = f"map{world_ext}"
        image_target_path = storage_dir / image_target_name
        world_target_path = storage_dir / world_target_name
        try:
            shutil.move(str(temp_image_path), image_target_path)
            world_target_path.write_text(world_text, encoding="utf-8")
        except Exception:
            _remove_overlay_dir(storage_rel_path)
            _raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, "OVERLAY_WRITE_FAILED", API_ERROR_INVALID_ORDS_RESPONSE)

        try:
            await _post_to_ords(
                "admin/competitions/overlay",
                {
                    "competition_id": competition_id,
                    "display_name": display_name.strip(),
                    "attribution": attribution.strip(),
                    "image_file_name": image_target_name,
                    "world_file_name": world_target_name,
                    "image_mime_type": SUPPORTED_OVERLAY_IMAGE_EXTENSIONS[image_ext],
                    "image_size_bytes": image_size_bytes,
                    "storage_rel_path": storage_rel_path,
                    "crs_code": "EPSG:3301",
                    "width_px": width_px,
                    "height_px": height_px,
                    "pixel_size_x": world_meta["pixel_size_x"],
                    "pixel_size_y": world_meta["pixel_size_y"],
                    "top_left_x": world_meta["top_left_x"],
                    "top_left_y": world_meta["top_left_y"],
                    "min_x": bounds["min_x"],
                    "min_y": bounds["min_y"],
                    "max_x": bounds["max_x"],
                    "max_y": bounds["max_y"],
                    "updated_by": user_id,
                },
            )
        except Exception:
            _remove_overlay_dir(storage_rel_path)
            raise

        current_overlay = await _get_admin_competition_overlay(competition_id)
        competitor_map_layers_cache.pop(competition_id, None)
        _schedule_overlay_processing(current_overlay, user_id)

        if previous_overlay.exists and previous_overlay.storage_rel_path and previous_overlay.storage_rel_path != storage_rel_path:
            _remove_overlay_dir(previous_overlay.storage_rel_path)
        return _decorate_admin_overlay_response(current_overlay, user_id)
    finally:
        _remove_path_quietly(temp_image_path)
        await world_file.close()


@app.post("/api/admin/competitions/overlay/meta", response_model=CompetitionOverlayResponse)
async def admin_competition_overlay_meta_update(
    req: CompetitionOverlayMetaUpdateRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> CompetitionOverlayResponse:
    user_id = _require_google_session_user(request, x_user_id)
    await _post_to_ords(
        "admin/competitions/overlay/meta",
        {
            "competition_id": req.competition_id,
            "display_name": req.display_name.strip(),
            "attribution": (req.attribution or "").strip(),
            "updated_by": user_id,
        },
    )
    competitor_map_layers_cache.pop(req.competition_id, None)
    overlay = await _get_admin_competition_overlay(req.competition_id)
    return _decorate_admin_overlay_response(overlay, user_id)


@app.post("/api/admin/competitions/overlay/delete")
async def admin_competition_overlay_delete(
    req: CompetitionOverlayDeleteRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    previous_overlay = await _get_admin_competition_overlay(req.competition_id)
    await _post_to_ords(
        "admin/competitions/overlay/delete",
        {
            "competition_id": req.competition_id,
            "updated_by": user_id,
        },
    )
    competitor_map_layers_cache.pop(req.competition_id, None)
    if previous_overlay.exists and previous_overlay.storage_rel_path:
        _remove_overlay_dir(previous_overlay.storage_rel_path)
    return {"ok": True}


@app.get("/api/admin/competitions/overlay/file/{competition_id}")
async def admin_competition_overlay_file(
    competition_id: int,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> FileResponse:
    _ = _require_google_session_user(request, x_user_id)
    overlay = await _get_admin_competition_overlay(competition_id)
    if not overlay.exists or not overlay.storage_rel_path or not overlay.image_file_name:
        _raise_api_error(status.HTTP_404_NOT_FOUND, "OVERLAY_NOT_FOUND", "api.error.invalid_submission")
    file_path = _safe_overlay_path(overlay.storage_rel_path) / overlay.image_file_name
    if not file_path.exists():
        _raise_api_error(status.HTTP_404_NOT_FOUND, "OVERLAY_FILE_NOT_FOUND", "api.error.invalid_submission")
    return FileResponse(file_path, media_type=overlay.image_mime_type or "application/octet-stream")


@app.get("/api/admin/competitions/overlay/tiles/{overlay_id}/{z}/{x}/{y}.png")
async def admin_competition_overlay_tile(
    overlay_id: int,
    z: int,
    x: int,
    y: int,
    token: str,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> FileResponse:
    user_id = _require_google_session_user(request, x_user_id)
    payload = _read_signed_token(token)
    if not isinstance(payload, dict):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "INVALID_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    if _signed_payload_is_expired(payload):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "EXPIRED_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    if str(payload.get("kind") or "") != "admin_overlay_tile":
        _raise_api_error(status.HTTP_403_FORBIDDEN, "INVALID_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    if int(payload.get("user_id") or 0) != user_id or int(payload.get("overlay_id") or 0) != overlay_id:
        _raise_api_error(status.HTTP_403_FORBIDDEN, "INVALID_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    tile_rel_path = str(payload.get("tile_storage_rel_path") or "").strip()
    if not tile_rel_path:
        _raise_api_error(status.HTTP_404_NOT_FOUND, "OVERLAY_TILE_NOT_FOUND", "api.error.invalid_submission")
    file_path = _safe_overlay_path(tile_rel_path) / str(z) / str(x) / f"{y}.png"
    if not file_path.exists():
        _raise_api_error(status.HTTP_404_NOT_FOUND, "OVERLAY_TILE_NOT_FOUND", "api.error.invalid_submission")
    return FileResponse(file_path, media_type="image/png")


@app.get("/api/competitor/competitions/overlay/tiles/{overlay_id}/{z}/{x}/{y}.png")
async def competitor_competition_overlay_tile(
    overlay_id: int,
    z: int,
    x: int,
    y: int,
    token: str,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> FileResponse:
    user_id = _resolve_user_id(request, None, x_user_id)
    competition_participant_id = _read_competitor_participation_id(request)
    if competition_participant_id is None:
        _raise_api_error(status.HTTP_401_UNAUTHORIZED, "NOT_AUTHENTICATED", "api.error.not_authenticated")
    payload = _read_signed_token(token)
    if not isinstance(payload, dict):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "INVALID_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    if _signed_payload_is_expired(payload):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "EXPIRED_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    if str(payload.get("kind") or "") != "competitor_overlay_tile":
        _raise_api_error(status.HTTP_403_FORBIDDEN, "INVALID_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    if (
        int(payload.get("user_id") or 0) != user_id
        or int(payload.get("competition_participant_id") or 0) != competition_participant_id
        or int(payload.get("overlay_id") or 0) != overlay_id
    ):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "INVALID_OVERLAY_TILE_TOKEN", "api.error.invalid_submission")
    tile_rel_path = str(payload.get("tile_storage_rel_path") or "").strip()
    if not tile_rel_path:
        _raise_api_error(status.HTTP_404_NOT_FOUND, "OVERLAY_TILE_NOT_FOUND", "api.error.invalid_submission")
    file_path = _safe_overlay_path(tile_rel_path) / str(z) / str(x) / f"{y}.png"
    if not file_path.exists():
        _raise_api_error(status.HTTP_404_NOT_FOUND, "OVERLAY_TILE_NOT_FOUND", "api.error.invalid_submission")
    return FileResponse(file_path, media_type="image/png")


@app.post("/api/admin/competitions/copy", response_model=SuperAdminCreateCompetitionResponse)
async def admin_copy_competition(
    req: AdminCopyCompetitionRequest,
    request: Request,
    x_user_id: int | None = Header(default=None),
) -> SuperAdminCreateCompetitionResponse:
    user_id = _require_google_session_user(request, x_user_id)
    admin_items = await _get_admin_competition_items(user_id)
    if not any(int(item.get("competition_id") or 0) == req.source_competition_id for item in admin_items):
        _raise_api_error(status.HTTP_403_FORBIDDEN, "FORBIDDEN", API_ERROR_UNAUTHENTICATED)
    data = await _post_to_ords(
        "admin/competitions/copy",
        {
            "source_competition_id": req.source_competition_id,
            "copy_questions": req.copy_questions,
            "copy_organizers": req.copy_organizers,
            "copy_overlay": req.copy_overlay,
            "created_by": user_id,
            "add_creator_as_organizer": "Y",
            "max_admin_competitions": settings.max_competition_admin,
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
            "copy_overlay": req.copy_overlay,
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
    if req.checkpoint_interaction is not None:
        payload["checkpoint_interaction"] = req.checkpoint_interaction
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
    if req.mass_start_at is not None:
        payload["mass_start_at"] = req.mass_start_at

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
    _invalidate_competition_cache(req.competition_id)
    _schedule_declination_refresh(req.competition_id)
    return {"ok": True}


@app.post("/api/admin/questions/update")
async def admin_update_question(req: AdminUpdateQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    payload: dict[str, Any] = {
        "competition_id": req.competition_id,
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
    if req.competition_id is not None:
        _invalidate_competition_cache(req.competition_id)
    else:
        map_checkpoints_cache.clear()
        open_checkpoints_last_response.clear()
    return {"ok": True}


@app.post("/api/admin/questions/delete")
async def admin_delete_question(req: AdminDeleteQuestionRequest, request: Request, x_user_id: int | None = Header(default=None)) -> dict[str, bool]:
    user_id = _require_google_session_user(request, x_user_id)
    await _post_to_ords(
        "admin/questions/delete",
        {
            "competition_id": req.competition_id,
            "question_id": req.question_id,
            "deleted_by": user_id,
        },
    )
    if req.competition_id is not None:
        _invalidate_competition_cache(req.competition_id)
    else:
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
            "mass_start_at": req.mass_start_at,
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







