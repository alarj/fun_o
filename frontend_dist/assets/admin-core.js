const byId = (id) => document.getElementById(id);
const esc = (v) => (v ?? "").toString().replace(/[&<>"']/g, (m) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[m]));
let checkpointsData = [];
let competitionsData = [];
let i18nItems = {};
let sortKey = "checkpoint_title";
let sortDir = "asc";
let currentUserId = null;
let currentUserName = "";
let currentUserEmail = "";
let currentUiLang = "et";
let availableLangs = ["et", "en"];
let defaultLang = "et";

const tr = (key, fallback = "") => i18nItems[key] || fallback || key;
const applyI18n = () => {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    el.textContent = tr(key, el.textContent);
  });
  document.querySelectorAll("[data-i18n-title]").forEach((el) => {
    const key = el.getAttribute("data-i18n-title");
    el.setAttribute("title", tr(key, el.getAttribute("title") || key));
  });
  document.querySelectorAll("[data-i18n-aria-label]").forEach((el) => {
    const key = el.getAttribute("data-i18n-aria-label");
    el.setAttribute("aria-label", tr(key, el.getAttribute("aria-label") || key));
  });
  document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => {
    const key = el.getAttribute("data-i18n-placeholder");
    el.setAttribute("placeholder", tr(key, el.getAttribute("placeholder") || key));
  });
};

const showMsg = (id, ok, text) => {
  const el = byId(id);
  if (!text) {
    el.className = "";
    el.textContent = "";
    return;
  }
  el.className = ok ? "ok" : "err";
  el.textContent = text;
};

const textIncludesAny = (text, patterns) => patterns.some((pattern) => text.includes(pattern));
const errorMatchesAny = (msg, detailsText, patterns) =>
  textIncludesAny(msg, patterns) || textIncludesAny(detailsText, patterns);

const translateAdminError = (msg, detailsText) => {
  if (errorMatchesAny(msg, detailsText, [
    "checkpoint title already exists in this competition",
    "-20101",
    "-20103",
    "ora-20101",
    "ora-20103"
  ])) {
    return tr("admin.msg.cp_title_exists");
  }
  if (errorMatchesAny(msg, detailsText, ["ora-20196"])) return tr("admin.msg.cp_reserved_title");
  if (errorMatchesAny(msg, detailsText, ["ora-20197"])) return tr("admin.msg.cp_order_reserved");
  if (errorMatchesAny(msg, detailsText, ["ora-20198"])) return tr("admin.msg.cp_special_type_exists");
  return "";
};

const humanizeError = (raw, details = null) => {
  const msg = (raw || "").toString().trim();
  if (!msg) return tr("admin.msg.error_generic");
  if (msg === "api.error.invalid_access_code") return tr("admin.msg.invalid_access_code");
  if (msg === "api.error.already_registered") return tr("admin.msg.already_registered_organizer");
  if (msg === "api.error.unauthenticated") return tr("admin.msg.unauthenticated");
  const ordsBody = (details && typeof details.ords_body === "string") ? details.ords_body : "";
  const detailsText = `${ordsBody}`.toLowerCase();
  const lmsg = msg.toLowerCase();
  const translated = translateAdminError(lmsg, detailsText);
  if (translated) return translated;
  if (msg === "api.error.ords_request_failed" && detailsText) {
    const bodyRaw = String(details?.ords_body || "");
    const oraMatch = bodyRaw.match(/ORA-\d{5}:[^<\r\n]*/i);
    const shortOra = oraMatch ? oraMatch[0].trim() : "";
    if (shortOra) {
      return `${tr("admin.msg.error_generic")} ${shortOra}`;
    }
    return `${tr("admin.msg.error_generic")} ${msg}`;
  }
  return msg;
};

const qTextId = (lang) => `qText_${lang}`;
const langLabel = (code) => (code || "").toLowerCase() === "en" ? "EN" : "ET";
const uiLangCookieName = "funo_admin_ui_lang";
const isPromo100Mode = new URLSearchParams(window.location.search).get("mode") === "promo100";
const lastCompCookieName = () => currentUserId ? `funo_last_competition_u${currentUserId}` : null;

const setCookie = (name, value, days = 365) => {
  const d = new Date();
  d.setTime(d.getTime() + days * 24 * 60 * 60 * 1000);
  document.cookie = `${name}=${encodeURIComponent(value)}; expires=${d.toUTCString()}; path=/; SameSite=Lax`;
};

const getCookie = (name) => {
  const prefix = `${name}=`;
  const parts = (document.cookie || "").split(";");
  for (const part of parts) {
    const p = part.trim();
    if (p.startsWith(prefix)) return decodeURIComponent(p.slice(prefix.length));
  }
  return null;
};

async function get(url) {
  const r = await fetch(url);
  const d = await r.json();
  if (!r.ok) {
    const err = new Error(d?.detail?.message || d?.detail?.code || tr("admin.msg.error_short"));
    err.details = d?.detail?.details || null;
    err.code = d?.detail?.code || null;
    throw err;
  }
  return d;
}

async function post(url, body) {
  const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const d = await r.json();
  if (!r.ok) {
    const err = new Error(d?.detail?.message || d?.detail?.code || tr("admin.msg.error_short"));
    err.details = d?.detail?.details || null;
    err.code = d?.detail?.code || null;
    throw err;
  }
  return d;
}

function hasDuplicateCheckpointTitle(title, editingCheckpointId = null) {
  const wanted = (title || "").trim().toLowerCase();
  if (!wanted) return false;
  return checkpointsData.some((r) => {
    const sameId = editingCheckpointId != null && Number(r.checkpoint_id) === Number(editingCheckpointId);
    if (sameId) return false;
    const existing = String(r.checkpoint_title || "").trim().toLowerCase();
    return existing === wanted;
  });
}

function normalizeCheckpointType(value) {
  const normalized = String(value || "NORMAL").trim().toUpperCase();
  return ["START", "FINISH", "NORMAL"].includes(normalized) ? normalized : "NORMAL";
}

function isSpecialCheckpointType(value) {
  const normalized = normalizeCheckpointType(value);
  return normalized === "START" || normalized === "FINISH";
}

function hasActiveCheckpointType(type, editingCheckpointId = null) {
  const wanted = normalizeCheckpointType(type);
  return checkpointsData.some((row) => {
    if (editingCheckpointId != null && Number(row?.checkpoint_id) === Number(editingCheckpointId)) return false;
    return normalizeCheckpointType(row?.checkpoint_type) === wanted;
  });
}

async function loadI18nMeta() {
  try {
    const d = await get("/api/i18n/meta");
    const langs = Array.isArray(d.available_langs) ? d.available_langs.map((x) => String(x).trim().toLowerCase()).filter(Boolean) : [];
    defaultLang = (d.default_lang || "et").toString().trim().toLowerCase() || "et";
    availableLangs = langs.length ? langs : [defaultLang];
    if (!availableLangs.includes(defaultLang)) availableLangs.unshift(defaultLang);
  } catch (_e) {
    availableLangs = ["et", "en"];
    defaultLang = "et";
  }
  const selectedLang = byId("uiLang")?.value;
  const rememberedLang = getCookie(uiLangCookieName);
  const browserLang = ((navigator.language || defaultLang).toLowerCase().startsWith("en")) ? "en" : defaultLang;
  if (selectedLang && availableLangs.includes(selectedLang)) {
    currentUiLang = selectedLang;
  } else if (rememberedLang && availableLangs.includes(rememberedLang)) {
    currentUiLang = rememberedLang;
  } else {
    currentUiLang = availableLangs.includes(browserLang) ? browserLang : defaultLang;
  }
  renderLangSelector();
  renderTermsLangSelector();
  await loadTranslations(currentUiLang);
  renderQuestionLangRows();
  renderOptionLangHead();
}

function renderLangSelector() {
  ["uiLang", "uiLangApp"].forEach((id) => {
    const sel = byId(id);
    if (!sel) return;
    sel.innerHTML = availableLangs.map((l) => `<option value="${esc(l)}">${langLabel(l)}</option>`).join("");
    sel.value = currentUiLang;
  });
}

function renderTermsLangSelector() {
  const sel = byId("termsLangSelect");
  if (!sel) return;
  sel.innerHTML = availableLangs.map((l) => `<option value="${esc(l)}">${langLabel(l)}</option>`).join("");
  termsCurrentLang = availableLangs.includes(currentUiLang) ? currentUiLang : (availableLangs[0] || defaultLang || "et");
  sel.value = termsCurrentLang;
}

function setTermsEditorHtml(html) {
  const safeHtml = String(html || "");
  if (termsQuill) termsQuill.clipboard.dangerouslyPasteHTML(safeHtml || "");
  else byId("termsHtmlEditor").innerHTML = safeHtml;
  byId("termsHtmlInput").value = safeHtml;
}

function getTermsEditorHtml() {
  const html = termsQuill
    ? String(termsQuill.root?.innerHTML || "")
    : String(byId("termsHtmlEditor").innerHTML || "");
  byId("termsHtmlInput").value = html;
  return html;
}

function initTermsEditor() {
  if (termsQuill) return;
  if (!window.Quill) throw new Error(tr("admin.msg.editor_not_loaded"));
  termsQuill = new Quill("#termsHtmlEditor", {
    theme: "snow",
    modules: {
      toolbar: [
        [{ header: [2, 3, false] }],
        ["bold", "italic", "underline", "strike"],
        [{ list: "ordered" }, { list: "bullet" }],
        ["link", "blockquote", "code-block"],
        [{ align: [] }],
        ["clean"]
      ]
    }
  });
  termsQuill.on("text-change", () => getTermsEditorHtml());
}

async function loadCompetitionTermsForLang(lang) {
  const competitionId = compId();
  if (!competitionId) throw new Error(tr("admin.msg.select_competition_first"));
  const payload = await get(`/api/admin/competitions/terms?competition_id=${encodeURIComponent(competitionId)}&lang_code=${encodeURIComponent(lang || defaultLang || "et")}`);
  termsCurrentLang = String(payload?.lang_code || lang || defaultLang || "et").toLowerCase();
  byId("termsLangSelect").value = termsCurrentLang;
  setTermsEditorHtml(String(payload?.terms_text || ""));
}

async function openTermsDialog() {
  const competitionId = compId();
  if (!competitionId) {
    showMsg("topMsg", false, tr("admin.msg.select_competition_first"));
    return;
  }
  showMsg("termsMsg", true, "");
  initTermsEditor();
  renderTermsLangSelector();
  try {
    await loadCompetitionTermsForLang(termsCurrentLang);
    for (const lang of availableLangs) {
      if (lang === termsCurrentLang) continue;
      get(`/api/admin/competitions/terms?competition_id=${encodeURIComponent(compId())}&lang_code=${encodeURIComponent(lang)}`).catch(() => {});
    }
    byId("termsLangSelect").value = termsCurrentLang;
    byId("termsDialog").showModal();
  } catch (e) {
    showMsg("topMsg", false, humanizeError(e.message));
  }
}

async function saveTermsDialog() {
  const competitionId = compId();
  if (!competitionId) {
    showMsg("termsMsg", false, tr("admin.msg.select_competition_first"));
    return;
  }
  const lang = (byId("termsLangSelect").value || termsCurrentLang || defaultLang || "et").toLowerCase();
  const termsText = getTermsEditorHtml();
  try {
    await post("/api/admin/competitions/terms", {
      competition_id: competitionId,
      lang_code: lang,
      terms_text: termsText
    });
    termsCurrentLang = lang;
    showMsg("termsMsg", true, tr("admin.msg.saved"));
  } catch (e) {
    showMsg("termsMsg", false, humanizeError(e.message));
  }
}

async function loadTranslations(lang) {
  try {
    const tdata = await get(`/api/i18n/translations?lang=${encodeURIComponent(lang)}`);
    i18nItems = tdata?.items || {};
  } catch (_e) {
    i18nItems = {};
  }
  applyI18n();
}

const compId = () => Number(byId("competitionSelect").value);
let currentCompetitionActive = true;

const asUtcDate = (v) => {
  if (!v) return null;
  const s = String(v).trim();
  if (!s) return null;
  const iso = /z$/i.test(s) || /[+-]\d{2}:\d{2}$/.test(s) ? s : `${s}Z`;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
};

const fmtDateEt = (v) => {
  if (!v) return "";
  const d = asUtcDate(v);
  if (!d) return v;
  const p2 = (n) => String(n).padStart(2, "0");
  return `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())} ${p2(d.getDate())}.${p2(d.getMonth() + 1)}.${d.getFullYear()}`;
};

const fmtDateEtShort = (v) => {
  if (!v) return "-";
  const d = asUtcDate(v);
  if (!d) return "-";
  const p2 = (n) => String(n).padStart(2, "0");
  return `${p2(d.getDate())}.${p2(d.getMonth() + 1)}.${d.getFullYear()}`;
};

const fmtEtInput = (v) => {
  if (!v) return "";
  const d = asUtcDate(v);
  if (!d) return "";
  const p2 = (n) => String(n).padStart(2, "0");
  return `${p2(d.getDate())}.${p2(d.getMonth() + 1)}.${d.getFullYear()} ${p2(d.getHours())}:${p2(d.getMinutes())}`;
};

const fmtMagDeclination = (v) => {
  const n = Number(v);
  if (!Number.isFinite(n)) return "0.000°";
  return `${n.toFixed(3)}°`;
};

const parseEtInput = (v) => {
  const t = (v || "").trim();
  if (!t) return null;
  const m = t.match(/^(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2})$/);
  if (!m) return { error: tr("admin.msg.date_format_error") };
  const [, dd, mm, yyyy, hh, mi] = m;
  const month = Number(mm);
  const day = Number(dd);
  const hour = Number(hh);
  const minute = Number(mi);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
    return { error: tr("admin.msg.date_value_error") };
  }
  const localDate = new Date(Number(yyyy), Number(mm) - 1, Number(dd), Number(hh), Number(mi), 0);
  if (Number.isNaN(localDate.getTime())) return { error: tr("admin.msg.date_value_error") };
  return localDate.toISOString().slice(0, 19) + "Z";
};

const nextOptionCode = (idx) => String.fromCharCode(65 + (idx % 26));
let pendingCodeType = null;
let pendingOldCode = null;
let pendingDeleteCheckpointId = null;
let pendingDeleteQuestionId = null;
let currentCompetitionUseLocation = "N";
let currentCompetitionType = "R";
let cpMap = null;
let cpBaseLayer = null;
let cpMarker = null;
let cpRadiusCircle = null;
let cpDialogCurrentCrs = "EPSG:3857";
let cpOverviewMap = null;
let cpOverviewBaseLayer = null;
let cpOverviewLayer = null;
let cpOverviewRoutesLayer = null;
let cpOverviewZoomHandler = null;
let cpOverviewMarkers = [];
let cpOverviewCurrentCrs = "EPSG:3857";
let cpOverviewFullscreen = false;
let availableMapLayers = [];
let competitionParticipantLayerCodes = [];
let participantLayerSelection = [];
let termsCurrentLang = "et";
let termsQuill = null;
let cpDialogFullscreen = false;
let cpDialogInitialState = "";
let cpDialogCheckpointId = null;
let cpExistingVisible = false;
let cpExistingLayer = null;
let cpExistingRoutesLayer = null;
let cpExistingZoomHandler = null;
const lastCpCoordKey = () => `funo_last_cp_coord_c${compId()}`;
const lastCpOverviewViewKey = () => `funo_cp_overview_view_c${compId()}`;
const lastCpDialogViewKey = () => `funo_cp_dialog_view_c${compId()}`;
const lastCpOverviewMapLayerKey = "funo_cp_overview_map_layer";
const lastCpDialogMapLayerKey = "funo_cp_dialog_map_layer";
