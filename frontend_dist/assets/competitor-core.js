const state = {
  userId: null,
  activeCompetition: null,
  selectedCompetitionId: null,
  joinPreview: null,
  hasAuthenticatedCompetitionSession: false,
  openItems: [],
  openItemsLoaded: false,
  feedbackOpen: false,
  submissionInFlight: false,
  geo: {
    enabled: false,
    latitude: null,
    longitude: null,
    radius_m: null,
    error: null,
  },
  mapItems: [],
  mapDeclination: 0,
  mapDeclinationUpdatedAt: null,
};
let compMap = null;
let compMapLayer = null;
let compMapRouteLayer = null;
let userPosMarker = null;
let mapInfoVisible = false;
let mapRings = [];
let mapRoutePoints = [];
let geoWatchId = null;
let mapFollowUser = true;
let mapProgrammaticMove = false;
let allowedMapLayers = [];
let activeMapLayerCode = "";
let baseMapLayer = null;
let compMapCurrentCrs = "EPSG:3857";
let compMapOpenedOnce = false;
let mapViewPersistenceEnabled = false;
let mapHeadingMode = false;
let mapHeadingPermissionAsked = false;
let mapHeadingListenerAttached = false;
let mapHeadingSmoothed = null;
let mapHeadingLastApplied = null;
let mapHeadingLastAppliedAt = 0;
let mapHeadingCurrent = null;
let mapHeadingHasSignal = false;
let mapHeadingCompassSeenAt = 0;
let mapHeadingState = "COMPASS_ONLY";
let mapHeadingGpsStableCount = 0;
let mapHeadingCompassRaw = null;
let mapHeadingGpsRaw = null;
let mapHeadingBiasDeg = 0;
let mapHeadingBiasConfidence = 0;
let mapDebugRawAlpha = null;
let mapDebugRawCompass = null;
let mapDebugGpsHeading = null;
let mapDebugGpsSpeed = null;
const mapLayersByCode = {};
const MAP_HEADING_OFFSET_DEG = 0;
const HEADING_SPEED_LOW_MPS = 1.0;
const HEADING_SPEED_HIGH_MPS = 1.5;
const HEADING_SPEED_BLEND_EARLY_MPS = 0.7;
const HEADING_GPS_ACC_MAX_M = 25;
const HEADING_BIAS_ALPHA = 0.03;
const HEADING_BIAS_MAX_DEG = 45;
const OPEN_CHECKPOINTS_CLIENT_THROTTLE_MS = 2000;
const COMP_PROGRESS_TTL_MS = 3 * 60 * 60 * 1000;
let openCheckpointsClientCache = { key: "", ts: 0, items: [] };
let progressCache = { key: "", updatedAt: 0, totalKp: 0, answeredKp: 0, score: 0 };
let myResultsItems = [];
let myResultsSortKey = "submitted_at";
let myResultsSortDir = "desc";
let introLoading = false;
let joinHasActiveBeforeOpen = false;
const competitionTermsCache = {};
let i18nItems = {};
let i18nMeta = { default_lang: "et", available_langs: ["et", "en"] };

const el = (id) => document.getElementById(id);
const tr = (key) => i18nItems[key] || key;
function trf(key, vars) {
  let text = tr(key);
  Object.entries(vars || {}).forEach(([k, v]) => {
    text = text.replaceAll(`{${k}}`, String(v ?? ""));
  });
  return text;
}

function trfBold(key, vars) {
  let text = esc(tr(key));
  Object.entries(vars || {}).forEach(([k, v]) => {
    text = text.replaceAll(`{${k}}`, `<strong>${esc(String(v ?? ""))}</strong>`);
  });
  return text;
}

function setMsg(targetId, text, ok) {
  const box = el(targetId);
  if (!text) { box.className = ""; box.textContent = ""; return; }
  box.className = "msg " + (ok ? "ok" : "err");
  box.textContent = text;
}

function applyUiTranslations() {
  el("switchCompetitionBtn").textContent = tr("competitor.main.new_btn");
  el("showKpBtn").textContent = tr("competitor.main.show_cp_btn");
  el("mapBtn").textContent = tr("competitor.main.map_btn");
  el("checkpointSelectLabel").textContent = tr("competitor.main.select_open_cp_label");
  el("textAnswer").placeholder = tr("competitor.answer.text_placeholder");
  el("textSubmitBtn").textContent = tr("competitor.answer.submit_btn");
  el("myResultsBtn").textContent = tr("competitor.results.open_btn");
  el("myResultsTitle").textContent = tr("competitor.results.title");
  el("myResultsCloseBtn").textContent = tr("competitor.common.close_btn");
  el("myResThKp").textContent = tr("competitor.results.col_checkpoint");
  el("myResThTime").textContent = tr("competitor.results.col_time");
  el("myResThPoints").textContent = tr("competitor.results.col_points");
  el("competitionPickerLine1").textContent = tr("competitor.picker.line1");
  el("competitionPickerLine2").textContent = tr("competitor.picker.line2");
  el("openJoinByCodeBtn").textContent = tr("competitor.picker.open_join_btn");
  el("closeCompetitionPickerBtn").textContent = tr("competitor.common.close_btn");
  el("joinModalTitle").textContent = tr("competitor.join.title");
  el("joinCodeLabel").innerHTML = `${tr("competitor.join.code_label")} <span class="reqStar">*</span>`;
  el("joinAliasLabel").innerHTML = `${tr("competitor.join.alias_label")} <span class="reqStar">*</span>`;
  el("joinEmailLabel").textContent = tr("competitor.join.email_label");
  el("joinBtn").textContent = tr("competitor.join.continue_btn");
  el("joinIntroText").textContent = tr("competitor.join.intro_text");
  el("openIntroLink").textContent = tr("competitor.join.intro_link");
  el("openIntroLinkFooter").textContent = tr("competitor.join.intro_link");
  el("introInviteText").textContent = tr("competitor.main.intro_invite_text");
  el("closeJoinByCodeBtn").textContent = tr("competitor.common.close_btn");
  el("joinTermsTitle").textContent = tr("competitor.join.terms_title");
  el("confirmJoinBtn").textContent = tr("competitor.join.confirm_btn");
  el("backFromTermsBtn").textContent = tr("competitor.join.back_btn");
  el("introModalTitle").textContent = tr("competitor.intro.title");
  el("closeIntroBtn").textContent = tr("competitor.common.close_btn");
  el("competitionTermsTitle").textContent = tr("competitor.terms.title");
  el("closeCompetitionTermsBtn").textContent = tr("competitor.common.close_btn");
  el("feedbackCloseBtn").textContent = tr("competitor.common.close_btn");
  el("compMapShowKpBtn").textContent = tr("competitor.map.show_cp_btn");
  el("compMapInfoBtn").title = tr("competitor.map.info_btn");
  el("compMapLayerBtn").title = tr("competitor.map.layer_btn");
  el("compMapCloseBtn").title = tr("competitor.common.close_btn");
  el("compMapLayerTitle").textContent = tr("competitor.map.layer_title");
  el("compMapLayerCloseBtn").textContent = tr("competitor.common.close_btn");
  el("myAnswerDetailTitle").textContent = tr("competitor.answer_detail.title");
  el("myAnswerDetailCloseBtn").textContent = tr("competitor.common.close_btn");
  el("termsAndLicenseLine").innerHTML = `${tr("competitor.main.terms_prefix")} <a id="openCompetitionTermsLink" href="#">${tr("competitor.main.terms_link")}</a> | ${tr("competitor.main.license_line")}`;
}

function bindTermsLink() {
  el("openCompetitionTermsLink").addEventListener("click", (e) => {
    e.preventDefault();
    openCompetitionTermsModal().catch((err) => {
      setMsg("answerMsg", (err && err.message) ? String(err.message) : tr("competitor.msg.terms_load_failed"), false);
    });
  });
}

function sanitizeTermsHtml(html) {
  const dirty = String(html || "");
  if (!globalThis.DOMPurify?.sanitize) {
    return esc(dirty);
  }
  return globalThis.DOMPurify.sanitize(dirty, {
    USE_PROFILES: { html: true },
  });
}

function esc(v) {
  return (v ?? "").toString().replace(/[&<>"']/g, (m) => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#039;" }[m]));
}

function normAnswer(v) {
  return (v ?? "").toString().trim().toLocaleLowerCase("et");
}

function parseUtcDate(ts) {
  if (!ts) return null;
  const s = String(ts).trim();
  if (!s) return null;
  const iso = /z$/i.test(s) || /[+-]\d{2}:\d{2}$/.test(s) ? s : `${s}Z`;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
}

function fmtEtLocal(ts) {
  if (!ts) return "-";
  const d = parseUtcDate(ts);
  if (!d) return ts;
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getDate())}.${p(d.getMonth()+1)}.${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function fmtHhMmSs(totalSeconds) {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return "-";
  const value = Math.floor(totalSeconds);
  const hh = Math.floor(value / 3600);
  const mm = Math.floor((value % 3600) / 60);
  const ss = value % 60;
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:${String(ss).padStart(2, "0")}`;
}

function fmtDistanceKmFromMeters(distanceM) {
  if (!Number.isFinite(distanceM) || distanceM < 0) return "-";
  return (distanceM / 1000).toFixed(2);
}

function setCookie(name, value, days = 30) {
  const d = new Date();
  d.setTime(d.getTime() + days * 24 * 60 * 60 * 1000);
  document.cookie = `${name}=${encodeURIComponent(value)}; expires=${d.toUTCString()}; path=/`;
}

function getCookie(name) {
  const prefix = name + "=";
  const part = document.cookie.split(";").map((x) => x.trim()).find((x) => x.startsWith(prefix));
  return part ? decodeURIComponent(part.substring(prefix.length)) : null;
}

function getProgressCookieName() {
  const uid = Number(state.userId || 0);
  const cid = Number(state.selectedCompetitionId || 0);
  if (uid <= 0 || cid <= 0) return null;
  return `funo_comp_progress_u${uid}_c${cid}`;
}

function getProgressCacheKey() {
  return `${Number(state.userId || 0)}|${Number(state.selectedCompetitionId || 0)}`;
}

function isProgressStale(ts) {
  const t = Number(ts || 0);
  if (!Number.isFinite(t) || t <= 0) return true;
  return Date.now() - t > COMP_PROGRESS_TTL_MS;
}

function saveProgressCookie() {
  const name = getProgressCookieName();
  if (!name) return;
  setCookie(name, JSON.stringify(progressCache), 30);
}

function loadProgressCookie() {
  const name = getProgressCookieName();
  if (!name) return false;
  const raw = getCookie(name);
  if (!raw) return false;
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return false;
    if (String(parsed.key || "") !== getProgressCacheKey()) return false;
    progressCache = {
      key: String(parsed.key || ""),
      updatedAt: Number(parsed.updatedAt || 0),
      totalKp: Math.max(0, Number(parsed.totalKp || 0)),
      answeredKp: Math.max(0, Number(parsed.answeredKp || 0)),
      score: Number(parsed.score || 0),
    };
    return true;
  } catch {
    return false;
  }
}

function renderProgressBox() {
  const total = Math.max(0, Number(progressCache.totalKp || 0));
  const answered = Math.min(total, Math.max(0, Number(progressCache.answeredKp || 0)));
  const score = Number(progressCache.score || 0);
  const text = trf("competitor.results.progress_line", { answered, total, score });
  const p1 = el("myResultsProgress");
  if (p1) p1.textContent = text;
}

async function refreshProgressFromApi() {
  if (!state.selectedCompetitionId) return false;
  const res = await apiGet(`/api/competitor/progress?competition_id=${state.selectedCompetitionId}`);
  if (!res.ok || !res.data) return false;
  const total = Number(res.data.total_checkpoints);
  const answered = Number(res.data.answered_checkpoints);
  const score = Number(res.data.score);
  if (!Number.isFinite(total) || !Number.isFinite(answered) || !Number.isFinite(score)) return false;
  progressCache = {
    key: getProgressCacheKey(),
    updatedAt: Date.now(),
    totalKp: Math.max(0, total),
    answeredKp: Math.max(0, Math.min(Math.max(0, total), answered)),
    score: score,
  };
  saveProgressCookie();
  renderProgressBox();
  return true;
}

async function ensureProgressLoaded(forceRefresh = false) {
  const baseProgress = { key: getProgressCacheKey(), updatedAt: 0, totalKp: 0, answeredKp: 0, score: 0 };
  progressCache = baseProgress;
  const hasCookie = loadProgressCookie();
  if (!hasCookie) progressCache = baseProgress;
  renderProgressBox();
  if (forceRefresh || !hasCookie || isProgressStale(progressCache.updatedAt)) {
    await refreshProgressFromApi();
  }
}

async function apiGet(url) {
  return apiRequest(url, { method: "GET" }, { allowRetry429: true });
}

async function apiPost(url, payload) {
  return apiRequest(
    url,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {}),
    },
    { allowRetry429: false }
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseRetryAfterSeconds(value) {
  const n = Number(value);
  if (Number.isFinite(n) && n > 0) return Math.min(10, Math.floor(n));
  return 2;
}

function enrichErrorMessage(status, data, retryAfterSeconds) {
  const code = data?.detail?.code || "";
  if (status === 429 || code === "ORDS_RATE_LIMITED") {
    return trf("competitor.msg.server_busy_retry_seconds", { seconds: retryAfterSeconds });
  }
  const message = data?.detail?.message || "";
  if (typeof message === "string" && message.startsWith("api.error.")) {
    return tr(message);
  }
  return message;
}

async function apiRequest(url, init, options = {}) {
  const allowRetry429 = options.allowRetry429 === true;
  const maxAttempts = allowRetry429 ? 2 : 1;
  let attempt = 0;
  while (attempt < maxAttempts) {
    attempt += 1;
    const r = await fetch(url, init);
    const data = await r.json().catch(() => ({}));
    const retryAfterSeconds = parseRetryAfterSeconds(r.headers.get("Retry-After"));
    const userMessage = enrichErrorMessage(r.status, data, retryAfterSeconds);

    if (!r.ok && r.status === 429 && allowRetry429 && attempt < maxAttempts) {
      await sleep(retryAfterSeconds * 1000);
      continue;
    }

    return { ok: r.ok, status: r.status, data, userMessage, retryAfterSeconds };
  }

  return {
    ok: false,
    status: 429,
    data: { detail: { code: "ORDS_RATE_LIMITED" } },
    userMessage: tr("competitor.msg.server_busy_retry"),
    retryAfterSeconds: 2,
  };
}

async function loadI18nMeta() {
  const res = await apiGet("/api/i18n/meta");
  if (!res.ok || !res.data) return;
  const langs = Array.isArray(res.data.available_langs) ? res.data.available_langs : [];
  const def = String(res.data.default_lang || "et").trim().toLowerCase() || "et";
  i18nMeta = { default_lang: def, available_langs: langs.length ? langs : [def] };
}

async function loadTranslationsForLang(langCode) {
  const lang = String(langCode || i18nMeta.default_lang || "et").trim().toLowerCase();
  const res = await apiGet(`/api/i18n/translations?lang=${encodeURIComponent(lang)}`);
  if (!res.ok || !res.data?.items || typeof res.data.items !== "object") {
    i18nItems = {};
    return;
  }
  i18nItems = res.data.items;
}

async function setLanguage(langCode) {
  const lang = String(langCode || i18nMeta.default_lang || "et").trim().toLowerCase();
  await loadTranslationsForLang(lang);
  applyUiTranslations();
  if (el("checkpointSelect")) {
    const preferredCheckpointId = Number(el("checkpointSelect").value || 0) || null;
    renderCheckpointSelect(preferredCheckpointId);
  }
  if (el("myResultsRows") && myResultsItems.length) {
    renderMyResults();
  }
  bindTermsLink();
  const select = el("langSelect");
  if (select) select.value = lang;
  const joinSelect = el("joinLangSelect");
  if (joinSelect) joinSelect.value = lang;
  setCookie("funo_competitor_ui_lang", lang);
}

function renderLangOptions() {
  const langs = Array.isArray(i18nMeta.available_langs) && i18nMeta.available_langs.length
    ? i18nMeta.available_langs
    : [i18nMeta.default_lang || "et"];
  const optionsHtml = langs
    .map((l) => `<option value="${esc(String(l).toLowerCase())}">${esc(String(l).toUpperCase())}</option>`)
    .join("");
  const select = el("langSelect");
  if (select) select.innerHTML = optionsHtml;
  const joinSelect = el("joinLangSelect");
  if (joinSelect) joinSelect.innerHTML = optionsHtml;
}

function getGeoQueryParams() {
  if (!state.geo.enabled || state.geo.latitude == null || state.geo.longitude == null) return "";
  const p = new URLSearchParams();
  p.set("latitude", String(state.geo.latitude));
  p.set("longitude", String(state.geo.longitude));
  if (state.geo.radius_m != null) p.set("radius_m", String(state.geo.radius_m));
  return "&" + p.toString();
}

async function requestGeolocation(opts = {}) {
  if (!navigator.geolocation) {
    state.geo.enabled = false;
    state.geo.error = tr("competitor.msg.geo_unavailable");
    return false;
  }
  const maxAge = Number.isFinite(Number(opts.maximumAge)) ? Number(opts.maximumAge) : 15000;
  const timeoutMs = Number.isFinite(Number(opts.timeout)) ? Number(opts.timeout) : 7000;
  const highAccuracy = opts.enableHighAccuracy !== false;
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        state.geo.enabled = true;
        state.geo.latitude = Number(pos.coords.latitude);
        state.geo.longitude = Number(pos.coords.longitude);
        state.geo.radius_m = Number(pos.coords.accuracy);
        state.geo.error = null;
        resolve(true);
      },
      () => {
        state.geo.enabled = false;
        state.geo.latitude = null;
        state.geo.longitude = null;
        state.geo.radius_m = null;
        state.geo.error = tr("competitor.msg.geo_denied_or_failed");
        resolve(false);
      },
      { enableHighAccuracy: highAccuracy, timeout: timeoutMs, maximumAge: maxAge }
    );
  });
}

async function requestFreshGeolocationForMapOpen() {
  if (!navigator.geolocation) {
    state.geo.enabled = false;
    state.geo.error = tr("competitor.msg.geo_unavailable");
    return false;
  }
  const hadPreviousGeo = state.geo.enabled && state.geo.latitude != null && state.geo.longitude != null && Number.isFinite(Number(state.geo.radius_m));
  const previousGeo = hadPreviousGeo
    ? {
        latitude: Number(state.geo.latitude),
        longitude: Number(state.geo.longitude),
        radius_m: Number(state.geo.radius_m),
      }
    : null;
  state.geo.enabled = false;
  state.geo.latitude = null;
  state.geo.longitude = null;
  state.geo.radius_m = null;
  state.geo.error = null;
  return new Promise((resolve) => {
    let resolved = false;
    let watchId = null;
    let bestPos = null;
    const desiredAccuracyM = 75;
    const acceptableInitialAccuracyM = 1000;
    const maxWaitMs = 4500;
    const restorePreviousGeo = () => {
      if (!previousGeo) return false;
      state.geo.enabled = true;
      state.geo.latitude = previousGeo.latitude;
      state.geo.longitude = previousGeo.longitude;
      state.geo.radius_m = previousGeo.radius_m;
      state.geo.error = null;
      return true;
    };
    const commitBestPos = (force = false) => {
      if (!bestPos) return false;
      const accuracy = Number(bestPos.coords?.accuracy);
      if (!force && (!Number.isFinite(accuracy) || accuracy > acceptableInitialAccuracyM)) {
        return false;
      }
      state.geo.enabled = true;
      state.geo.latitude = Number(bestPos.coords.latitude);
      state.geo.longitude = Number(bestPos.coords.longitude);
      state.geo.radius_m = accuracy;
      state.geo.error = null;
      return true;
    };
    const finish = (ok) => {
      if (resolved) return;
      resolved = true;
      try { if (watchId != null) navigator.geolocation.clearWatch(watchId); } catch {}
      resolve(ok);
    };
    watchId = navigator.geolocation.watchPosition(
      (pos) => {
        const accuracy = Number(pos?.coords?.accuracy);
        if (!bestPos || (Number.isFinite(accuracy) && accuracy < Number(bestPos.coords?.accuracy || Infinity))) {
          bestPos = pos;
        }
        if (commitBestPos()) {
          if (Number.isFinite(accuracy) && accuracy <= desiredAccuracyM) {
            finish(true);
          }
          return;
        }
        if (Number.isFinite(accuracy) && accuracy <= desiredAccuracyM) {
          commitBestPos(true);
          finish(true);
        }
      },
      () => {
        if (commitBestPos() || restorePreviousGeo()) {
          finish(true);
          return;
        }
        state.geo.enabled = false;
        state.geo.latitude = null;
        state.geo.longitude = null;
        state.geo.radius_m = null;
        state.geo.error = tr("competitor.msg.geo_denied_or_failed");
        finish(false);
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    );
    setTimeout(() => {
      if (commitBestPos() || restorePreviousGeo()) {
        finish(true);
        return;
      }
      finish(false);
    }, maxWaitMs);
  });
}

function renderCompetitionText() {
  const c = state.activeCompetition;
  const aliasOrName = (c?.competitor_name || "---").trim() || "---";
  el("competitionLine").textContent = c ? c.name : "-";
  el("competitionDescLine").textContent = c?.description || "";
  el("userLine").textContent = aliasOrName;
}

function getSelectedCompetition() {
  return state.activeCompetition;
}

function selectedCompetitionUsesLocation() {
  const c = getSelectedCompetition();
  return String(c?.use_location || "N").toUpperCase() === "Y";
}

function selectedCompetitionShowsUserLocation() {
  const c = getSelectedCompetition();
  const usesLocation = String(c?.use_location || "N").toUpperCase() === "Y";
  if (!usesLocation) return false;
  return String(c?.show_competitor_location || "Y").toUpperCase() === "Y";
}

function selectedCompetitionType() {
  const fromState = String(getSelectedCompetition()?.type || "").trim().toUpperCase();
  if (fromState === "S" || fromState === "R") return fromState;
  const fromOpen = String(state.openItems?.[0]?.competition_type || "").trim().toUpperCase();
  if (fromOpen === "S" || fromOpen === "R") return fromOpen;
  const fromMap = String(state.mapItems?.[0]?.competition_type || "").trim().toUpperCase();
  if (fromMap === "S" || fromMap === "R") return fromMap;
  return "R";
}

function normalizeCheckpointType(rawType) {
  const value = String(rawType || "NORMAL").trim().toUpperCase();
  if (value === "START" || value === "FINISH") return value;
  return "NORMAL";
}

function isSpecialCheckpointType(rawType) {
  const value = normalizeCheckpointType(rawType);
  return value === "START" || value === "FINISH";
}

function checkpointListLabel(item) {
  const cpType = normalizeCheckpointType(item?.checkpoint_type);
  const requiresLocation = String(item?.location_required || "N").toUpperCase() === "Y";
  const pin = requiresLocation ? "\uD83D\uDCCD " : "";
  const points = Number(item?.points || 0);
  const orderNo = Number(item?.checkpoint_order_no);
  const showOrder = selectedCompetitionType() === "S" && cpType === "NORMAL" && Number.isFinite(orderNo);
  const orderPrefix = showOrder ? `${orderNo}. ` : "";
  return `${pin}${orderPrefix}${item?.checkpoint_title || tr("competitor.common.checkpoint_short")} (${points} ${tr("competitor.common.points_short")})`;
}

function renderCompetitionPicker() {
  const c = state.activeCompetition;
  el("competitionPickerName").textContent = c?.name || "-";
}

function renderCheckpointSelect(preferredCheckpointId = null) {
  const s = el("checkpointSelect");
  s.innerHTML = "";
  if (!state.openItemsLoaded) {
    const o = document.createElement("option");
    o.value = "";
    o.textContent = tr("competitor.msg.press_show_cp");
    s.appendChild(o);
    s.disabled = true;
    el("questionBlock").style.display = "none";
    return;
  }
  if (!state.openItems.length) {
    const o = document.createElement("option");
    o.value = "";
    o.textContent = tr("competitor.msg.all_cp_answered");
    s.appendChild(o);
    s.disabled = true;
    el("questionBlock").style.display = "none";
    return;
  }
  s.disabled = false;
  const preferredIdNum = Number(preferredCheckpointId || 0);
  let hasPreferred = false;
  state.openItems.forEach((item, idx) => {
    const o = document.createElement("option");
    o.value = String(item.checkpoint_id);
    o.textContent = checkpointListLabel(item);
    if (preferredIdNum > 0 && Number(item.checkpoint_id) === preferredIdNum) {
      o.selected = true;
      hasPreferred = true;
    } else if (!hasPreferred && idx === 0) {
      o.selected = true;
    }
    s.appendChild(o);
  });
  renderQuestionForSelectedCheckpoint();
}

function getSelectedOpenItem() {
  const cpId = Number(el("checkpointSelect").value);
  return state.openItems.find((x) => x.checkpoint_id === cpId) || null;
}

function currentLang() {
  return String(el("langSelect")?.value || i18nMeta.default_lang || "et").toLowerCase();
}

function pickLocalized(item, etKey, enKey) {
  const lang = currentLang();
  const et = (item?.[etKey] || "").toString();
  const en = (item?.[enKey] || "").toString();
  if (lang === "en") return en || et;
  return et || en;
}

function optionLabel(opt) {
  const t = pickLocalized(opt, "text_et", "text_en").trim();
  return t || `[${opt.option_code || "?"}]`;
}

function renderQuestionForSelectedCheckpoint() {
  const item = getSelectedOpenItem();
  setMsg("answerMsg", "", true);
  if (!item) {
    el("questionBlock").style.display = "none";
    return;
  }
  el("questionBlock").style.display = "block";
  el("questionText").textContent = pickLocalized(item, "text_et", "text_en") || tr("competitor.msg.question_text_missing");
  const inputType = (item.input_type || "").toUpperCase();
  const maxLen = Number(item.input_max_length || 0);
  let promptText;
  if ((item.question_type || "").toUpperCase() === "SINGLE_CHOICE") {
    promptText = tr("competitor.msg.select_answer");
  } else if (inputType === "NUMERIC") {
    promptText = maxLen > 0 ? trf("competitor.answer.number_placeholder_max", { max: maxLen }) : tr("competitor.answer.number_placeholder");
  } else {
    promptText = maxLen > 0 ? trf("competitor.answer.text_placeholder_max", { max: maxLen }) : tr("competitor.answer.text_placeholder");
  }
  el("questionMeta").textContent = promptText;
  el("singleChoiceBlock").style.display = "none";
  el("textBlock").style.display = "none";

  if (item.question_type === "SINGLE_CHOICE") {
    const box = el("singleChoiceBlock");
    box.innerHTML = "";
    const opts = Array.isArray(item.options) ? item.options : [];
    opts.forEach((opt, idx) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = `optionBtn opt${idx % 6}`;
      b.textContent = optionLabel(opt);
      b.onclick = () => submitAnswer(item, { selected_option_id: opt.option_id });
      box.appendChild(b);
    });
    box.style.display = "block";
  } else {
    el("textAnswer").value = "";
    el("textBlock").style.display = "block";
  }
  setSubmissionBusy(state.submissionInFlight);
}

function showFeedback(data) {
  const ok = !!data?.is_correct;
  const points = Number(data?.awarded_points || 0);
  const total = Number(data?.total_score || 0);
  const correctAnswers = Array.isArray(data?.correct_answer_texts)
    ? data.correct_answer_texts.filter((v) => typeof v === "string" && v.trim())
    : [];
  const otherCorrectAnswers = Array.isArray(data?.other_correct_answer_texts)
    ? data.other_correct_answer_texts.filter((v) => typeof v === "string" && v.trim())
    : [];
  const distanceAllowed = data?.distance_display_allowed === true;
  const totalDistanceM = Number(data?.total_distance_m);
  const totalElapsedSeconds = Number(data?.total_elapsed_seconds);
  const currentRank = Number(data?.current_rank);
  state.feedbackOpen = true;
  const modal = el("feedbackModal");
  modal.className = "modal " + (ok ? "feedback-ok" : "feedback-err");
  el("feedbackTitle").textContent = ok ? tr("competitor.feedback.correct_title") : tr("competitor.feedback.wrong_title");
  el("feedbackBody").innerHTML = trfBold("competitor.feedback.points_total", {
    points,
    total,
  });
  el("feedbackAnswerLine").innerHTML = "";
  if (!ok && correctAnswers.length) {
    el("feedbackAnswerLine").innerHTML = trfBold("competitor.feedback.correct_answers_line", {
      answers: correctAnswers.join(", "),
    });
  } else if (ok && otherCorrectAnswers.length) {
    el("feedbackAnswerLine").innerHTML = trfBold("competitor.feedback.other_correct_answers_line", {
      answers: otherCorrectAnswers.join(", "),
    });
  }
  el("feedbackDistanceLine").innerHTML = (
    distanceAllowed && Number.isFinite(totalDistanceM) && totalDistanceM >= 0
  ) ? trfBold("competitor.feedback.distance_line", {
    distance_km: fmtDistanceKmFromMeters(totalDistanceM),
  }) : "";
  el("feedbackElapsedLine").innerHTML = (
    Number.isFinite(totalElapsedSeconds) && totalElapsedSeconds >= 0
  ) ? trfBold("competitor.feedback.elapsed_line", {
    elapsed: fmtHhMmSs(totalElapsedSeconds),
  }) : "";
  el("feedbackRankLine").innerHTML = (
    Number.isFinite(currentRank) && currentRank > 0
  ) ? trfBold("competitor.feedback.rank_line", {
    rank: currentRank,
  }) : "";
  el("feedbackBackdrop").style.display = "flex";
}

function setSubmissionBusy(isBusy) {
  state.submissionInFlight = isBusy === true;
  const textSubmitBtn = el("textSubmitBtn");
  if (textSubmitBtn) textSubmitBtn.disabled = state.submissionInFlight;
  const checkpointSelect = el("checkpointSelect");
  if (checkpointSelect) checkpointSelect.disabled = state.submissionInFlight;
  const optionButtons = Array.from(document.querySelectorAll("#singleChoiceBlock .optionBtn"));
  optionButtons.forEach((btn) => {
    btn.disabled = state.submissionInFlight;
  });
}

async function submitAnswer(item, extra) {
  if (state.feedbackOpen || state.submissionInFlight) return;
  setMsg("answerMsg", "", true);
  const payload = {
    competition_id: state.selectedCompetitionId,
    checkpoint_id: item.checkpoint_id,
    question_id: item.question_id,
    lang_code: currentLang(),
    latitude: state.geo.enabled ? state.geo.latitude : null,
    longitude: state.geo.enabled ? state.geo.longitude : null,
    radius_m: state.geo.enabled ? state.geo.radius_m : null,
    ...extra,
  };
  setSubmissionBusy(true);
  try {
    const res = await apiPost("/api/submissions", payload);
    if (!res.ok) {
      setMsg("answerMsg", res.userMessage || tr("competitor.msg.submit_failed"), false);
      return;
    }
    const d = res.data || {};
    progressCache.score = Number(d.total_score || 0);
    progressCache.answeredKp = Math.max(0, Number(progressCache.answeredKp || 0) + 1);
    progressCache.updatedAt = Date.now();
    progressCache.key = getProgressCacheKey();
    saveProgressCookie();
    renderProgressBox();

    const answeredCpId = Number(item?.checkpoint_id || 0);
    if (answeredCpId > 0 && Array.isArray(state.mapItems)) {
      state.mapItems.forEach((cp) => {
        if (Number(cp?.checkpoint_id || 0) === answeredCpId) {
          cp.is_answered = "Y";
        }
      });
      mapRings.forEach((entry) => {
        if (Number(entry?.cp?.checkpoint_id || 0) === answeredCpId) {
          if (entry.cp) entry.cp.is_answered = "Y";
          entry.ring?.setPopupContent(checkpointPopupLabel(entry.cp));
        }
      });
    }
    showFeedback(d);
  } catch (err) {
    console.error("submitAnswer failed", err);
    setMsg("answerMsg", tr("competitor.msg.submit_failed"), false);
  } finally {
    if (!state.feedbackOpen) setSubmissionBusy(false);
  }
}

async function closeFeedback() {
  state.feedbackOpen = false;
  el("feedbackBackdrop").style.display = "none";
  setSubmissionBusy(false);
  await loadOpenCheckpoints();
}

async function loadOpenCheckpoints(opts = {}) {
  if (!state.selectedCompetitionId) return;
  const forceReload = opts && opts.force === true;
  const preferredCheckpointId = Number(
    opts?.preferredCheckpointId || el("checkpointSelect")?.value || 0
  ) || null;
  const geoParams = getGeoQueryParams();
  const requestLang = currentLang();
  const requestKey = `${state.selectedCompetitionId}|${requestLang}|${geoParams}`;
  const now = Date.now();

  if (
    !forceReload &&
    openCheckpointsClientCache.key === requestKey &&
    now - openCheckpointsClientCache.ts < OPEN_CHECKPOINTS_CLIENT_THROTTLE_MS
  ) {
    state.openItems = [...openCheckpointsClientCache.items];
    state.openItemsLoaded = true;
    renderCheckpointSelect(preferredCheckpointId);
    return;
  }

  const res = await apiGet(`/api/competitor/open-checkpoints?competition_id=${state.selectedCompetitionId}&lang_code=${encodeURIComponent(requestLang)}${geoParams}`);
  if (!res.ok) {
    setMsg("answerMsg", res.userMessage || tr("competitor.msg.open_cp_load_failed"), false);
    state.openItems = [];
    state.openItemsLoaded = true;
    renderCheckpointSelect(preferredCheckpointId);
    return;
  }
  state.openItems = Array.isArray(res.data.items) ? res.data.items : [];
  if (state.activeCompetition && state.openItems[0]?.competition_type) {
    state.activeCompetition.type = String(state.openItems[0].competition_type || "R").toUpperCase() === "S" ? "S" : "R";
  }
  state.openItemsLoaded = true;
  openCheckpointsClientCache = {
    key: requestKey,
    ts: now,
    items: [...state.openItems],
  };
  renderCheckpointSelect(preferredCheckpointId);
}

async function refreshQuestionsOnLanguageChange(langCode) {
  const previousCheckpointId = Number(el("checkpointSelect")?.value || 0) || null;
  await setLanguage(langCode);
  renderQuestionForSelectedCheckpoint();
  if (state.selectedCompetitionId && state.openItemsLoaded) {
    await loadOpenCheckpoints({ force: true, preferredCheckpointId: previousCheckpointId });
  }
}

async function loadMapCheckpoints() {
  if (!state.selectedCompetitionId) return [];
  const res = await apiGet(`/api/competitor/map-checkpoints?competition_id=${state.selectedCompetitionId}`);
  if (!res.ok) return [];
  const items = Array.isArray(res.data.items) ? res.data.items : [];
  if (state.activeCompetition && items[0]?.competition_type) {
    state.activeCompetition.type = String(items[0].competition_type || "R").toUpperCase() === "S" ? "S" : "R";
  }
  const declination = Number(res.data?.declination);
  state.mapDeclination = Number.isFinite(declination) ? declination : 0;
  state.mapDeclinationUpdatedAt = typeof res.data?.declination_last_updated === "string" ? res.data.declination_last_updated : null;
  return items.filter((x) => x && x.latitude != null && x.longitude != null);
}
