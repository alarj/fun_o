let currentCompetitionOrganizers = [];
let pendingCompetitionCopySourceId = null;
let currentCompetitionRoute = null;
let currentCompetitionIdLoaded = null;
let cpOverviewLabelsOpen = false;

function cpDialogStateSnapshot() {
  return JSON.stringify({
    checkpointType: byId("cpType").value,
    title: byId("cpName").value,
    location: byId("cpLocation").value,
    order: byId("cpOrder").value,
    lat: byId("cpLatitude").value,
    lon: byId("cpLongitude").value,
    radius: byId("cpRadiusM").value,
    required: byId("cpLocationRequired").checked ? "Y" : "N"
  });
}

function setCpLocationRequiredValue(v) {
  const checked = String(v || "N").toUpperCase() === "Y";
  byId("cpLocationRequired").checked = checked;
}

function getCpLocationRequiredValue() {
  return byId("cpLocationRequired").checked ? "Y" : "N";
}

function fillCheckpointTypeSelect(selectedType = "NORMAL", editingCheckpointId = null) {
  const normalizedSelected = normalizeCheckpointType(selectedType);
  const sel = byId("cpType");
  const options = [
    { value: "NORMAL", label: tr("admin.cp_dialog.checkpoint_type.normal") }
  ];
  if (normalizedSelected === "START" || !hasActiveCheckpointType("START", editingCheckpointId)) {
    options.push({ value: "START", label: tr("admin.cp_dialog.checkpoint_type.start") });
  }
  if (normalizedSelected === "FINISH" || !hasActiveCheckpointType("FINISH", editingCheckpointId)) {
    options.push({ value: "FINISH", label: tr("admin.cp_dialog.checkpoint_type.finish") });
  }
  sel.innerHTML = options.map((opt) => `<option value="${esc(opt.value)}">${esc(opt.label)}</option>`).join("");
  sel.value = options.some((opt) => opt.value === normalizedSelected) ? normalizedSelected : "NORMAL";
}

function syncCheckpointTypeUi() {
  const checkpointType = normalizeCheckpointType(byId("cpType").value);
  const isSpecial = isSpecialCheckpointType(checkpointType);
  const cpName = byId("cpName");
  const cpOrder = byId("cpOrder");
  byId("cpNameRow").style.display = "";
  byId("cpOrderRow").style.display = isSpecial ? "none" : "";
  byId("cpType").disabled = byId("cpId").value !== "";
  if (checkpointType === "START") {
    cpName.value = "START";
  } else if (checkpointType === "FINISH") {
    cpName.value = "FINISH";
  }
  cpName.readOnly = isSpecial;
  cpOrder.readOnly = isSpecial;
  if (isSpecial) {
    cpOrder.value = checkpointType === "START" ? "0" : "9999";
  }
  syncCpQuestionButton();
}

function setMetaUseLocationValue(v) {
  byId("metaUseLocationInput").checked = String(v || "N").toUpperCase() === "Y";
}

function getMetaUseLocationValue() {
  return byId("metaUseLocationInput").checked ? "Y" : "N";
}

function setMetaShowCompetitorLocationValue(v) {
  byId("metaShowCompetitorLocationInput").checked = String(v || "N").toUpperCase() === "Y";
}

function getMetaShowCompetitorLocationValue() {
  return byId("metaShowCompetitorLocationInput").checked ? "Y" : "N";
}

function syncMetaLocationSwitches() {
  const useLoc = getMetaUseLocationValue() === "Y";
  const showLocEl = byId("metaShowCompetitorLocationInput");
  const mapLayerBtn = byId("metaMapLayersBtn");
  const mapLayersRow = byId("metaMapLayersRow");
  const ownMapBtn = byId("metaOwnMapBtn");
  const ownMapRow = byId("metaOwnMapRow");
  showLocEl.disabled = !useLoc;
  if (!useLoc) showLocEl.checked = false;
  if (mapLayerBtn) mapLayerBtn.style.display = useLoc ? "inline-block" : "none";
  if (mapLayersRow) mapLayersRow.style.display = useLoc ? "" : "none";
  if (ownMapBtn) ownMapBtn.style.display = useLoc ? "inline-block" : "none";
  if (ownMapRow) ownMapRow.style.display = useLoc ? "" : "none";
  if (!useLoc && byId("participantMapLayersDialog").open) {
    byId("participantMapLayersDialog").close();
  }
}

function syncCpQuestionButton() {
  const btn = byId("cpOpenQuestion");
  if (!btn) return;
  if (!cpDialogCheckpointId) {
    btn.textContent = tr("admin.cp_dialog.open_question_new");
    btn.disabled = true;
    return;
  }
  const row = checkpointsData.find((x) => Number(x.checkpoint_id) === Number(cpDialogCheckpointId));
  const hasQuestion = !!row?.question_id;
  btn.textContent = hasQuestion
    ? tr("admin.cp_dialog.open_question_edit")
    : tr("admin.cp_dialog.open_question_new");
  const dirty = cpDialogStateSnapshot() !== cpDialogInitialState;
  btn.disabled = dirty;
}

function setEditModeByCompetition(isActive) {
  currentCompetitionActive = isActive;
  ["regenCompetitor","regenOrganizer","newCheckpointBtn","newQuestionBtn","openCompetitionEditBtn","openTermsBtn"].forEach((id) => {
    const el = byId(id);
    if (el) el.disabled = !isActive;
  });
}

function userIconSvg() {
  return `<svg class="organizer-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="8.5" r="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M6.5 18.5c0-3 2.4-5 5.5-5s5.5 2 5.5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`;
}

function logoutIconSvg() {
  return `<svg class="logout-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M14 8l6 4-6 4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M20 12H9" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`;
}

function copyIconSvg() {
  return `<svg class="copy-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="11" height="14" rx="2" ry="2" fill="none" stroke="currentColor" stroke-width="2"/><rect x="4" y="8" width="11" height="13" rx="2" ry="2" fill="none" stroke="currentColor" stroke-width="2"/></svg>`;
}

function normalizeCompetitionRouteData(route) {
  if (!route || typeof route !== "object") return null;
  const normalized = { ...route };
  if (typeof route.route_order_json === "string") {
    try {
      normalized.route_order_json = JSON.parse(route.route_order_json);
    } catch (err) {
      console.warn("Failed to parse competition route order JSON", err);
      normalized.route_order_json = [];
    }
  } else {
    normalized.route_order_json = Array.isArray(route.route_order_json) ? route.route_order_json : [];
  }
  return normalized;
}

function setCurrentCompetitionRoute(route) {
  currentCompetitionRoute = normalizeCompetitionRouteData(route);
  window.__lastCompetitionRoute = currentCompetitionRoute;
}

function getCurrentCompetitionRouteStatus(route = currentCompetitionRoute) {
  return String(route?.calc_status || "").trim().toUpperCase();
}

function competitionRouteSnapshotExists(route = currentCompetitionRoute) {
  if (!route || typeof route !== "object") return false;
  if (Number.isFinite(Number(route.route_length_m))) return true;
  if (Array.isArray(route.route_order_json) && route.route_order_json.length > 0) return true;
  if (String(route.algorithm_code || "").trim()) return true;
  if (String(route.calculated_at || "").trim()) return true;
  return false;
}

function competitionRouteIsCurrent(route = currentCompetitionRoute) {
  return String(route?.is_current || "N").toUpperCase() === "Y";
}

function competitionRouteHasOrder(route = currentCompetitionRoute) {
  return competitionRouteSnapshotExists(route)
    && Array.isArray(route?.route_order_json)
    && route.route_order_json.length >= 2;
}

function competitionRouteCanRequest(route = currentCompetitionRoute) {
  const status = getCurrentCompetitionRouteStatus(route);
  if (status === "PENDING" || status === "PROCESSING") return false;
  return !competitionRouteIsCurrent(route);
}

function formatCompetitionRouteDistanceKm(routeLengthM) {
  const meters = Number(routeLengthM);
  if (!Number.isFinite(meters) || meters < 0) return null;
  return (meters / 1000).toFixed(2);
}

function buildCompetitionRouteTextHtml(routeLabelKey, staleLabelKey, distanceKm, isStale) {
  const template = tr(routeLabelKey);
  const parts = String(template).split("{distance_km}");
  const prefix = esc(parts[0] || "");
  const suffix = esc(parts.slice(1).join("{distance_km}") || "");
  const distanceMarkup = `<span class="cp-overview-route-distance${isStale ? " is-stale" : ""}">${esc(distanceKm ?? "-")}</span>`;
  const staleMarkup = isStale
    ? `<span class="cp-overview-route-stale-note"> ${esc(tr(staleLabelKey))}</span>`
    : "";
  return `${prefix}${distanceMarkup}${suffix}${staleMarkup}`;
}

function renderCompetitionRouteSummary() {
  const routeSummaryTextEl = byId("checkpointsRouteSummaryText");
  if (!routeSummaryTextEl) return;
  const route = currentCompetitionRoute;
  const snapshotExists = competitionRouteSnapshotExists(route);
  const isCurrent = competitionRouteIsCurrent(route);
  const distanceKm = formatCompetitionRouteDistanceKm(route?.route_length_m);
  const routeLabelKey = currentCompetitionType === "S"
    ? "admin.cp_table.route_length_text_s"
    : "admin.cp_table.route_length_text_r";
  routeSummaryTextEl.innerHTML = buildCompetitionRouteTextHtml(
    routeLabelKey,
    "admin.cp_table.route_stale_suffix",
    distanceKm != null ? distanceKm : "-",
    snapshotExists && !isCurrent
  );
}

function routeActionButtonHtml(labelKey) {
  return `<span>${esc(tr(labelKey))}</span>`;
}

function renderCheckpointOverviewRouteControls() {
  const routeTextInlineEl = byId("cpOverviewRouteTextInline");
  const calcBtn = byId("cpOverviewRouteCalcBtn");
  const toggleBtn = byId("cpOverviewRouteToggleBtn");
  const toggleInfoBtn = byId("cpOverviewRouteToggleInfoBtn");
  const toggleWrap = byId("cpOverviewRouteToggleWrap");
  const stateIcon = byId("cpOverviewRouteStateIcon");
  const routeInfoBtn = document.querySelector('[data-info-key="admin.cp_overview.route_length_text"]');
  if (!routeTextInlineEl || !calcBtn || !toggleBtn || !toggleInfoBtn || !toggleWrap || !stateIcon) return;

  if (routeInfoBtn?.parentElement && stateIcon.previousElementSibling !== routeTextInlineEl) {
    routeInfoBtn.parentElement.insertBefore(stateIcon, routeInfoBtn);
  }

  const route = currentCompetitionRoute;
  const isSType = String(currentCompetitionType || "R").toUpperCase() === "S";
  const snapshotExists = competitionRouteSnapshotExists(route);
  const isCurrent = competitionRouteIsCurrent(route);
  const hasOrder = competitionRouteHasOrder(route);
  const status = getCurrentCompetitionRouteStatus(route);
  const distanceKm = formatCompetitionRouteDistanceKm(route?.route_length_m);
  const routeLabelKey = currentCompetitionType === "S"
    ? "admin.cp_overview.route_length_text_s"
    : "admin.cp_overview.route_length_text_r";
  const displayDistanceKm = distanceKm != null ? distanceKm : "-";
  routeTextInlineEl.innerHTML = buildCompetitionRouteTextHtml(
    routeLabelKey,
    "admin.cp_overview.route_stale_suffix",
    displayDistanceKm,
    snapshotExists && !isCurrent
  );
  routeTextInlineEl.classList.remove("is-stale");

  calcBtn.className = "secondary cp-overview-route-btn route-calc-btn";
  calcBtn.innerHTML = routeActionButtonHtml("admin.cp_overview.route_calculate_btn");
  calcBtn.disabled = !competitionRouteCanRequest(route);

  const routeVisible = isCheckpointOverviewRouteVisible();
  toggleBtn.className = "secondary cp-overview-route-btn route-toggle-btn";
  toggleBtn.innerHTML = routeActionButtonHtml(
    routeVisible ? "admin.cp_overview.route_toggle_hide_btn" : "admin.cp_overview.route_toggle_show_btn"
  );
  toggleWrap.classList.toggle("hidden", isSType || !hasOrder);

  stateIcon.className = "cp-overview-route-state-icon hidden";
  stateIcon.removeAttribute("title");
  stateIcon.removeAttribute("aria-label");
  if (status === "PENDING") {
    stateIcon.className = "cp-overview-route-state-icon route-state-pending";
    stateIcon.title = tr("admin.cp_overview.route_pending_state_title");
    stateIcon.setAttribute("aria-label", tr("admin.cp_overview.route_pending_state_title"));
  } else if (status === "PROCESSING") {
    stateIcon.className = "cp-overview-route-state-icon route-state-processing";
    stateIcon.title = tr("admin.cp_overview.route_processing_state_title");
    stateIcon.setAttribute("aria-label", tr("admin.cp_overview.route_processing_state_title"));
  } else if (status === "FAILED") {
    const failedTitle = String(route?.error_message || "").trim() || tr("admin.cp_overview.route_failed_state_title");
    stateIcon.className = "cp-overview-route-state-icon route-state-failed";
    stateIcon.title = failedTitle;
    stateIcon.setAttribute("aria-label", failedTitle);
  }
  renderCompetitionRouteSummary();
}

function renderCheckpointOverviewLabelsToggle() {
  const btn = byId("cpOverviewLabelsToggleBtn");
  if (!btn) return;
  const key = cpOverviewLabelsOpen ? "admin.cp_overview.close_labels_btn" : "admin.cp_overview.open_labels_btn";
  btn.textContent = tr(key);
  btn.setAttribute("data-i18n", key);
}

async function refreshCurrentCompetitionRoute() {
  const payload = await get(`/api/admin/competitions/route?competition_id=${compId()}`);
  setCurrentCompetitionRoute(payload?.data || null);
  renderCheckpointOverviewRouteControls();
  refreshCheckpointOverviewRouteDisplay();
}

async function requestCheckpointOverviewRouteCalculation() {
  showMsg("cpOverviewRouteMsg", false, "");
  const requestPayload = { competition_id: compId() };
  if (currentCompetitionType === "S") {
    await post("/api/admin/competitions/route/calculate-now", requestPayload);
    await refreshCurrentCompetitionRoute();
    showMsg("cpOverviewRouteMsg", true, tr("admin.cp_overview.route_calculated_msg"));
  } else {
    await post("/api/admin/competitions/route/request", requestPayload);
    await refreshCurrentCompetitionRoute();
    showMsg("cpOverviewRouteMsg", true, tr("admin.cp_overview.route_requested_msg"));
  }
  renderCheckpointOverviewRouteControls();
  refreshCheckpointOverviewRouteDisplay();
}

async function copyTextToClipboard(text) {
  const value = (text || "").trim();
  if (!value || value === "-") return;
  if (navigator.clipboard && navigator.clipboard.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }
  const ta = document.createElement("textarea");
  ta.value = value;
  ta.setAttribute("readonly", "");
  ta.style.position = "absolute";
  ta.style.left = "-9999px";
  document.body.appendChild(ta);
  ta.select();
  document.execCommand("copy");
  document.body.removeChild(ta);
}

function renderOrganizers(org) {
  const target = byId("organizers");
  if (!Array.isArray(org) || org.length === 0) {
    target.textContent = tr("admin.msg.missing_value");
    return;
  }

  const current = [];
  const others = [];
  org.forEach((o) => {
    if (Number(o?.user_id) === Number(currentUserId)) current.push(o);
    else others.push(o);
  });
  const ordered = [...current, ...others];
  const html = ordered.map((o) => {
    const isCurrent = Number(o?.user_id) === Number(currentUserId);
    const name = (o?.full_name || o?.email || "-").toString();
    const email = (o?.email || "").toString();
    const tooltip = email || name;
    const logout = isCurrent
      ? `<button class="logout-btn logout-btn-inline" title="${esc(tr("admin.common.logout_btn"))}" aria-label="${esc(tr("admin.common.logout_btn"))}">${logoutIconSvg()}</button>`
      : "";
    return `<div class="organizer-row ${isCurrent ? "current" : ""}" title="${esc(tooltip)}">${isCurrent ? userIconSvg() : ""}<span>${esc(name)}</span>${logout}</div>`;
  }).join("");
  target.innerHTML = `<div class="organizers-list">${html}</div>`;
}

function setEmptyCompetitionCreateVisible(isVisible) {
  const row = byId("createEmptyCompetitionNoCompRow");
  if (row) row.classList.toggle("hidden", !isVisible);
}

function getCurrentAdminDisplayName() {
  const fullName = String(currentUserName || "").trim();
  if (fullName) return fullName;
  const email = String(currentUserEmail || "").trim();
  if (email) return email;
  return "";
}

function getIntroContentHref() {
  return currentUiLang === "en" ? "./content/intro_en.html" : "./content/intro_et.html";
}

function sanitizeIntroHtml(html) {
  const dirty = String(html || "");
  if (!globalThis.DOMPurify?.sanitize) {
    return esc(dirty);
  }
  return globalThis.DOMPurify.sanitize(dirty, {
    USE_PROFILES: { html: true },
  });
}

async function loadIntroDialogContent() {
  const body = byId("introDialogBody");
  if (!body) return;
  const response = await fetch(getIntroContentHref(), { cache: "no-store" });
  if (!response.ok) {
    throw new Error("admin.intro.load_failed");
  }
  const html = (await response.text()).trim();
  body.innerHTML = sanitizeIntroHtml(html || `<p>${esc(tr("admin.intro.load_failed"))}</p>`);
}

async function openIntroDialog() {
  const dialog = byId("introDialog");
  const title = byId("introDialogTitle");
  const body = byId("introDialogBody");
  if (!dialog || !title || !body) return;
  title.textContent = tr("admin.intro.modal_title");
  body.innerHTML = `<p>${esc(tr("admin.intro.load_failed"))}</p>`;
  await loadIntroDialogContent();
  if (!dialog.open) {
    dialog.showModal();
  }
}

async function refreshIntroDialogIfOpen() {
  const dialog = byId("introDialog");
  const title = byId("introDialogTitle");
  if (title) {
    title.textContent = tr("admin.intro.modal_title");
  }
  if (!dialog || !dialog.open) return;
  try {
    await loadIntroDialogContent();
  } catch (_e) {
    const body = byId("introDialogBody");
    if (body) {
      body.innerHTML = `<p>${esc(tr("admin.intro.load_failed"))}</p>`;
    }
  }
}

function closeIntroDialog() {
  const dialog = byId("introDialog");
  if (dialog?.open) dialog.close();
}

function showAdminBootLoading() {
  const backdrop = byId("adminBootBackdrop");
  if (backdrop) backdrop.classList.add("admin-boot-backdrop-visible");
  document.body?.classList.add("admin-booting");
}

function hideAdminBootLoading() {
  const backdrop = byId("adminBootBackdrop");
  if (backdrop) backdrop.classList.remove("admin-boot-backdrop-visible");
  document.body?.classList.remove("admin-booting");
}

function markAdminBootTextReady() {
  const text = byId("adminBootText");
  if (!text) return;
  text.classList.remove("admin-boot-text-pending");
  text.classList.add("admin-boot-text-ready");
}

function renderNoOrgCardCopy() {
  const heading = byId("noOrgHeading");
  if (heading) {
    const displayName = getCurrentAdminDisplayName();
    heading.textContent = displayName
      ? formatTr("admin.no_org.heading_named", { user_name: displayName })
      : tr("admin.no_org.heading");
  }
}

async function refreshAdminOnboardingOptions() {
  try {
    const res = await get("/api/admin/onboarding-options");
    setEmptyCompetitionCreateVisible(!!res?.can_create_empty_competition);
  } catch (_e) {
    setEmptyCompetitionCreateVisible(false);
  }
}

function resetCompetitionCopyDialog() {
  pendingCompetitionCopySourceId = null;
  byId("copyCompetitionWithQuestions").checked = false;
  byId("copyCompetitionWithOrganizers").checked = false;
  byId("copyCompetitionWithOverlay").checked = false;
  byId("copyCompetitionWithOrganizersRow").classList.add("hidden");
  byId("copyCompetitionWithOverlayRow").classList.add("hidden");
  showMsg("copyCompetitionMsg", false, "");
}

function openCompetitionCopyDialog() {
  const sourceCompetitionId = compId();
  if (!sourceCompetitionId) return;
  resetCompetitionCopyDialog();
  pendingCompetitionCopySourceId = sourceCompetitionId;
  const currentName = byId("cName").textContent || `#${sourceCompetitionId}`;
  byId("copyCompetitionText").textContent = `${tr("admin.copy.confirm_prefix")} ${currentName} ${tr("admin.copy.confirm_suffix")}`;
  const hasOtherOrganizers = currentCompetitionOrganizers.length > 1;
  byId("copyCompetitionWithOrganizersRow").classList.toggle("hidden", !hasOtherOrganizers);
  byId("copyCompetitionWithOverlayRow").classList.toggle("hidden", !currentCompetitionOverlay?.exists);
  showMsg("copyCompetitionMsg", false, "");
  byId("copyCompetitionDialog").showModal();
}

async function finishAdminLogin() {
  byId("loginCard").classList.add("hidden");
  byId("appArea").classList.remove("hidden");
  renderNoOrgCardCopy();
  await refreshSuperadminNavButton();
  try {
    const hasCompetitions = await loadCompetitions();
    if (hasCompetitions) await loadView();
  } catch (e) {
    showMsg("topMsg", false, humanizeError(e.message || tr("admin.msg.google_login_failed")));
  }
}

async function handleAdminAuthInvalidated() {
  closeIntroDialog();
  currentUserId = null;
  currentUserName = "";
  currentUserEmail = "";
  competitionsData = [];
  checkpointsData = [];
  byId("loginCard").classList.remove("hidden");
  byId("appArea").classList.add("hidden");
  showMsg("topMsg", false, "");
  showMsg("noOrgMsg", false, "");
  showMsg("loginMsg", false, "");
  await initGoogleLogin().catch(() => {});
}

async function refreshSuperadminNavButton() {
  const btn = byId("goSuperadminBtn");
  btn.classList.add("hidden");
  try {
    await get("/api/superadmin/session");
    btn.classList.remove("hidden");
  } catch (_e) {
    btn.classList.add("hidden");
  }
}

async function googleLoginWithCredential(credential) {
  const d = await post("/api/auth/google", { id_token: credential });
  currentUserId = d.user_id || null;
  currentUserName = d.full_name || "";
  currentUserEmail = d.email || "";
  showMsg("loginMsg", true, `${tr("admin.msg.login_ok_prefix")}${d.user_id}`);
  await finishAdminLogin();
}

async function initGoogleLogin() {
  try {
    const cfg = await get("/api/auth/google/config");
    if (!cfg || !cfg.enabled || !cfg.client_id) {
      showMsg("loginMsg", false, tr("admin.msg.google_not_configured"));
      return;
    }
    if (!window.google || !window.google.accounts || !window.google.accounts.id) {
      showMsg("loginMsg", false, tr("admin.msg.google_script_failed"));
      return;
    }
    window.google.accounts.id.initialize({
      client_id: cfg.client_id,
      callback: async (resp) => {
        try {
          if (!resp || !resp.credential) throw new Error("Google credential puudub.");
          await googleLoginWithCredential(resp.credential);
        } catch (e) {
          showMsg("loginMsg", false, humanizeError(e.message || tr("admin.msg.google_login_failed")));
        }
      }
    });
    const mount = byId("googleLoginMount");
    mount.innerHTML = "";
    window.google.accounts.id.renderButton(mount, {
      theme: "outline",
      size: "large",
      text: "signin_with",
      shape: "rectangular"
    });
  } catch (e) {
    showMsg("loginMsg", false, humanizeError(e.message || tr("admin.msg.google_login_failed")));
  }
}

async function hydrateSessionUser() {
  try {
    const s = await get("/api/auth/session");
    if (s && s.authenticated && Number.isFinite(Number(s.user_id))) {
      currentUserId = Number(s.user_id);
      currentUserName = String(s.full_name || "").trim();
      currentUserEmail = String(s.email || "").trim();
    }
  } catch (_e) {
    // ignore; unauthenticated is handled by admin API calls
  }
}

async function loadCompetitions() {
  const d = await get("/api/admin/competitions");
  const items = Array.isArray(d.items) ? d.items : [];
  competitionsData = items;
  if (items.length === 0) {
    byId("competitionSelect").innerHTML = "";
    byId("competitionOverviewCard").classList.add("hidden");
    byId("noOrgCard").classList.remove("hidden");
    byId("checkpointsCard").classList.add("hidden");
    byId("topMsg").textContent = "";
    byId("topMsg").className = "";
    byId("cName").textContent = "-";
    byId("cDesc").textContent = "";
    byId("cStatus").textContent = "";
    byId("cType").textContent = "-";
    byId("cCreated").textContent = "";
    byId("cUpdated").textContent = "";
    byId("cStarts").textContent = "-";
    byId("cEnds2").textContent = "-";
    byId("codeCompetitor").textContent = "-";
    byId("codeOrganizer").textContent = "-";
    byId("organizers").textContent = "-";
    currentCompetitionUseLocation = "N";
    currentCompetitionType = "R";
    currentCompetitionOrganizers = [];
    checkpointsData = [];
    renderRows();
    setEditModeByCompetition(false);
    await refreshAdminOnboardingOptions();
    return false;
  }
  setEmptyCompetitionCreateVisible(false);
  byId("noOrgCard").classList.add("hidden");
  byId("competitionOverviewCard").classList.remove("hidden");
  byId("checkpointsCard").classList.remove("hidden");
  byId("topMsg").textContent = "";
  byId("topMsg").className = "";
  renderCompetitionOptions();
  const rememberedName = lastCompCookieName();
  const rememberedId = rememberedName ? getCookie(rememberedName) : null;
  if (rememberedId && competitionsData.some((x) => String(x.competition_id) === String(rememberedId))) {
    byId("competitionSelect").value = String(rememberedId);
    return true;
  }
  const active = competitionsData
    .filter((x) => x.is_active === "Y")
    .sort((a, b) => {
      const av = a?.starts_at ? (asUtcDate(a.starts_at)?.getTime() ?? 8640000000000000) : 8640000000000000;
      const bv = b?.starts_at ? (asUtcDate(b.starts_at)?.getTime() ?? 8640000000000000) : 8640000000000000;
      return av - bv;
    });
  if (active.length > 0) {
    byId("competitionSelect").value = String(active[0].competition_id);
  }
  return true;
}

function renderCompetitionOptions() {
  const selected = byId("competitionSelect").value;
  const sorted = [...competitionsData].sort((a, b) => {
    const av = a?.starts_at ? (asUtcDate(a.starts_at)?.getTime() ?? -8640000000000000) : -8640000000000000;
    const bv = b?.starts_at ? (asUtcDate(b.starts_at)?.getTime() ?? -8640000000000000) : -8640000000000000;
    return av - bv;
  });
  byId("competitionSelect").innerHTML = sorted.map((c) => {
    const isEndedByDate = c?.ends_at ? ((asUtcDate(c.ends_at) || new Date(0)) < new Date()) : false;
    const ended = c?.status !== "ACTIVE" || isEndedByDate;
    const label = `${esc(c.name)} (id=${c.competition_id}) - ${fmtDateEtShort(c.starts_at)} - ${fmtDateEtShort(c.ends_at)}`;
    return `<option value="${c.competition_id}" ${ended ? "style=\"font-style:italic;\"" : ""}>${label}</option>`;
  }).join("");
  if (selected && sorted.some((x) => String(x.competition_id) === String(selected))) {
    byId("competitionSelect").value = selected;
  }
}

function refreshCompetitionTypeDisplay() {
  const compType = String(window.__lastCompetitionType || "R").toUpperCase();
  const target = byId("cType");
  if (!target) return;
  target.textContent = tr(`admin.competition.type.${compType.toLowerCase()}`);
}

function rerenderCompetitionRouteTexts() {
  renderCompetitionRouteSummary();
  renderCheckpointOverviewRouteControls();
  refreshCheckpointOverviewRouteDisplay();
}

async function loadView() {
  if (!byId("competitionSelect").value) return;
  const rememberedName = lastCompCookieName();
  if (rememberedName) setCookie(rememberedName, byId("competitionSelect").value);
  const ov = await get(`/api/admin/competition-overview?competition_id=${compId()}`);
  const v = ov.data || {};
  const nextCompetitionId = Number(v.competition_id || compId() || 0);
  if (currentCompetitionIdLoaded !== nextCompetitionId) {
    setCheckpointOverviewRouteVisible(false);
    currentCompetitionIdLoaded = nextCompetitionId;
  }
  byId("cName").textContent = `${v.name || "-"} (id=${v.competition_id || "-"})`;
  const locBadge = byId("cLocationBadge");
  const compLocBadge = byId("cCompetitorLocationBadge");
  if ((v.use_location || "N") === "Y") {
    const r = v.radius_m != null ? ` (${Number(v.radius_m)} m)` : "";
    locBadge.textContent = `📍${r}`;
    locBadge.classList.remove("hidden");
    const showCompLoc = String(v.show_competitor_location || "Y").toUpperCase() === "Y";
    compLocBadge.textContent = "●";
    compLocBadge.style.color = showCompLoc ? "#2f8cff" : "#8a8a8a";
    compLocBadge.classList.remove("hidden");
    compLocBadge.style.display = "inline-block";
  } else {
    locBadge.classList.add("hidden");
    locBadge.textContent = "";
    compLocBadge.classList.add("hidden");
    compLocBadge.style.display = "none";
  }
  byId("cDesc").textContent = v.description || "";
  byId("cStatus").textContent = v.status || "";
  const compType = String(v.type || "R").toUpperCase();
  byId("cType").textContent = tr(`admin.competition.type.${compType.toLowerCase()}`);
  window.__lastCompetitionName = v.name || "";
  window.__lastCompetitionDescription = v.description || "";
  window.__lastCompetitionType = compType;
  window.__lastCompetitionStatus = v.status || "ACTIVE";
  window.__lastCompetitionUseLocation = v.use_location || "N";
  window.__lastCompetitionShowCompetitorLocation = v.show_competitor_location || "Y";
  window.__lastCompetitionRadiusM = v.radius_m ?? null;
  window.__lastCompetitionDeclination = v.declination ?? 0;
  window.__lastCompetitionDeclinationUpdatedAt = v.declination_last_updated || null;
  currentCompetitionUseLocation = window.__lastCompetitionUseLocation;
  currentCompetitionType = String(window.__lastCompetitionType || "R").toUpperCase();
  setCurrentCompetitionRoute(v.route);
  renderCheckpointOverviewRouteControls();
  if (currentCompetitionUseLocation === "Y") {
    await loadMapLayersConfig();
    await loadCompetitionOverlay();
    await loadCompetitionParticipantMapLayers();
  } else {
    currentCompetitionOverlay = { exists: false };
    refreshAdminMapLayerOptions();
    competitionParticipantLayerCodes = [];
  }
  byId("cCreated").textContent = fmtDateEt(v.created_at) || "";
  byId("cUpdated").textContent = fmtDateEt(v.updated_at) || "-";
  byId("cStarts").textContent = fmtDateEt(v.starts_at) || "-";
  byId("cEnds2").textContent = fmtDateEt(v.ends_at) || "-";
  window.__lastStartsAt = v.starts_at || null;
  window.__lastEndsAt = v.ends_at || null;
  setEditModeByCompetition(!v.ends_at || ((asUtcDate(v.ends_at) || new Date(0)) > new Date()));
  byId("codeCompetitor").textContent = v.competitor_code?.code || "-";
  byId("codeOrganizer").textContent = v.organizer_code?.code || "-";
  const org = Array.isArray(v.organizers) ? v.organizers : [];
  currentCompetitionOrganizers = org;
  renderOrganizers(org);

  const q = await get(`/api/admin/questions-overview?competition_id=${compId()}`);
  const rawItems = Array.isArray(q.items) ? q.items : [];
  checkpointsData = rawItems.map((it) => {
    const row = { ...it };
    if (typeof row.options === "string") {
      try { row.options = JSON.parse(row.options); } catch (_e) { row.options = []; }
    }
    if (!Array.isArray(row.options)) row.options = [];
    if (typeof row.answers === "string") {
      try { row.answers = JSON.parse(row.answers); } catch (_e) { row.answers = []; }
    }
    if (!Array.isArray(row.answers)) row.answers = [];
    return row;
  });
  renderRows();
  fillCheckpointSelect();
}

async function loadCompetitionOverlay() {
  const overlay = await get(`/api/admin/competitions/overlay?competition_id=${compId()}`);
  currentCompetitionOverlay = overlay || { exists: false };
  refreshAdminMapLayerOptions();
  updateMetaOwnMapButtonLabel();
  updateCompetitionOverlayReadyBadge();
}

function renderRows() {
  const sorted = [...checkpointsData].sort((a, b) => {
    const dir = sortDir === "asc" ? 1 : -1;
    if (sortKey === "points") {
      const av = Number(a?.points ?? 0);
      const bv = Number(b?.points ?? 0);
      return (av - bv) * dir;
    }
    const av = String(a?.[sortKey] ?? "");
    const bv = String(b?.[sortKey] ?? "");
    return av.localeCompare(bv, "et", { sensitivity: "base" }) * dir;
  });

  byId("cpRows").innerHTML = sorted.map((r) => {
    const hasQuestion = !!r.question_id;
    const qText = currentUiLang === "en"
      ? (r.text_en || r.text_et || "")
      : (r.text_et || r.text_en || "");
    const optionsCount = Array.isArray(r.options) ? r.options.length : 0;
    const questionTypeDisplay = String(r.question_type || "") === "SINGLE_CHOICE"
      ? `SINGLE_CHOICE (${optionsCount})`
      : String(r.question_type || "");
    return `<tr>
      <td>${esc(r.checkpoint_title || "")}</td>
      <td>${r.points ?? ""}</td>
      <td class="q-col"><span class="q-cell-text" title="${esc(qText)}">${esc(qText)}</span></td>
      <td>${esc(questionTypeDisplay)}</td>
      <td class="cp-loc-col">${
        (r.location_required === "Y" ? '<span style="color:#1f9d55;font-weight:700;">&#10003;</span>' : '-')
        + ((r.latitude != null && r.longitude != null) ? ` (${Number(r.latitude).toFixed(5)}, ${Number(r.longitude).toFixed(5)})` : '')
      }</td>
      <td class="actions-col">
        <div class="tools">
          <button data-act="edit-q" data-cp="${r.checkpoint_id}" ${(hasQuestion && currentCompetitionActive) ? "" : "disabled"}>${esc(tr("admin.cp_table.edit_question_btn"))}</button>
          <button data-act="edit-cp" data-cp="${r.checkpoint_id}" ${currentCompetitionActive ? "" : "disabled"}>${esc(tr("admin.cp_table.edit_checkpoint_btn"))}</button>
        </div>
      </td>
    </tr>`;
  }).join("");
  const showLocCol = currentCompetitionUseLocation === "Y";
  byId("showCheckpointMapBtn").classList.toggle("hidden", !showLocCol);
  byId("cpLocationColHead").style.display = showLocCol ? "" : "none";
  document.querySelectorAll(".cp-loc-col").forEach((el) => {
    el.style.display = showLocCol ? "" : "none";
  });
}

function toggleSort(key) {
  if (sortKey === key) {
    sortDir = sortDir === "asc" ? "desc" : "asc";
  } else {
    sortKey = key;
    sortDir = "asc";
  }
  refreshSortIcons();
  renderRows();
}

function sortIconFor(key) {
  if (sortKey !== key) return "☰";
  return sortDir === "asc" ? "▲" : "▼";
}

function refreshSortIcons() {
  byId("sortByTitleIcon").textContent = sortIconFor("checkpoint_title");
  byId("sortByPointsIcon").textContent = sortIconFor("points");
  byId("sortByQuestionEtIcon").textContent = sortIconFor("text_et");
}

function fillCheckpointSelect(includeAll = true, currentCpId = null) {
  const currentIdNum = currentCpId == null ? null : Number(currentCpId);
  const rows = includeAll
    ? checkpointsData
    : checkpointsData.filter((c) => {
      const isCurrent = currentIdNum != null && Number(c.checkpoint_id) === Number(currentIdNum);
      if (isCurrent) return true;
      return !c.question_id;
    });
  byId("qCheckpoint").innerHTML = rows.map((c) => `<option value="${c.checkpoint_id}">${esc(c.checkpoint_title || "")}</option>`).join("");
}

function renderQuestionLangRows() {
  const container = byId("questionLangRows");
  container.innerHTML = availableLangs.map((lang) => {
    const required = lang === defaultLang ? " *" : "";
    const inputId = qTextId(lang);
    return `<div class="row"><div class="field-label-with-info"><label for="${inputId}">${esc(tr("admin.q_dialog.question_text_prefix"))} (${lang})${required}</label>${infoButtonHtml("admin.q_dialog.question_text_prefix")}</div><textarea id="${inputId}"></textarea></div>`;
  }).join("");
}

function renderOptionLangHead() {
  const el = byId("optionLangHead");
  const text = availableLangs.map((l) => `${tr("admin.q_dialog.option_text_prefix")} (${l})${l === defaultLang ? " *" : ""}`).join(" / ");
  el.innerHTML = `<span class="field-label-with-info"><span>${esc(text)}</span>${infoButtonHtml("admin.q_dialog.option_text_prefix")}</span>`;
}

function syncQuestionTypeUI() {
  const t = byId("qType").value;
  const isSingle = t === "SINGLE_CHOICE";
  byId("singleChoiceBlock").classList.toggle("hidden", !isSingle);
  byId("textAnswersBlock").classList.toggle("hidden", isSingle);
  byId("qInputTypeRow").style.display = isSingle ? "none" : "grid";
  byId("qInputMaxRow").style.display = isSingle ? "none" : "grid";
}

function addOptionRow(v = {}) {
  const rowEl = document.createElement("tr");
  rowEl.className = "option-row";
  const existingCodeReadonly = v.option_code ? "readonly" : "";
  const langsHtml = availableLangs.map((lang) => {
    const key = `text_${lang}`;
    const placeholder = `${tr("admin.q_dialog.option_text_prefix")} (${lang})${lang === defaultLang ? " *" : ""}`;
    return `<input class="opt-lang" data-lang="${lang}" placeholder="${esc(placeholder)}" value="${esc(v[key] || "")}" style="margin-bottom:4px;" />`;
  }).join("");
  rowEl.innerHTML = `
    <td class="opt-code-cell"><input class="opt-code" value="${esc(v.option_code || "")}" ${existingCodeReadonly} /></td>
    <td class="opt-text-cell">${langsHtml}</td>
    <td class="opt-correct-cell"><input class="opt-correct" type="checkbox" ${v.is_correct === "Y" ? "checked" : ""} /></td>
    <td class="opt-del-cell"><button type="button" class="warn del-opt">${esc(tr("admin.q_dialog.delete_option_row_btn"))}</button></td>
  `;
  rowEl.querySelector(".del-opt").onclick = () => rowEl.remove();
  byId("optionRows").appendChild(rowEl);
}

function addAnswerRow(v = {}) {
  const rowEl = document.createElement("tr");
  rowEl.className = "answer-row";
  rowEl.innerHTML = `
    <td><input class="ans-val" value="${esc(v.answer_value || "")}" /></td>
    <td>
      <select class="ans-mode">
        <option value="LOWER_TRIM" ${(v.normalize_mode || "LOWER_TRIM") === "LOWER_TRIM" ? "selected" : ""}>LOWER_TRIM</option>
        <option value="TRIM" ${v.normalize_mode === "TRIM" ? "selected" : ""}>TRIM</option>
        <option value="EXACT" ${v.normalize_mode === "EXACT" ? "selected" : ""}>EXACT</option>
      </select>
    </td>
    <td><button type="button" class="warn del-ans">${esc(tr("admin.q_dialog.delete_answer_row_btn"))}</button></td>
  `;
  rowEl.querySelector(".del-ans").onclick = () => rowEl.remove();
  byId("answerRows").appendChild(rowEl);
}

function collectSingleChoiceOptions() {
  const rows = Array.from(document.querySelectorAll("#optionRows .option-row"));
  const opts = [];
  let hasCorrect = false;
  rows.forEach((row, idx) => {
    const texts = {};
    row.querySelectorAll(".opt-lang").forEach((el) => {
      const lang = el.getAttribute("data-lang");
      texts[lang] = el.value.trim();
    });
    const code = row.querySelector(".opt-code").value.trim() || nextOptionCode(idx);
    const isCorrect = row.querySelector(".opt-correct").checked ? "Y" : "N";
    if (!texts[defaultLang]) return;
    if (isCorrect === "Y") hasCorrect = true;
    const item = { option_code: code, is_correct: isCorrect };
    availableLangs.forEach((lang) => { item[`text_${lang}`] = texts[lang] || null; });
    opts.push(item);
  });
  return { opts, hasCorrect };
}

function collectTextAnswers() {
  const rows = Array.from(document.querySelectorAll("#answerRows .answer-row"));
  const answers = [];
  rows.forEach((row) => {
    const value = row.querySelector(".ans-val").value.trim();
    const mode = row.querySelector(".ans-mode").value || "LOWER_TRIM";
    if (!value) return;
    answers.push({ answer_value: value, normalize_mode: mode, is_correct: "Y" });
  });
  return answers;
}

function initCheckpointDialogMapState() {
  showMsg("cpMsg", false, "");
  setCheckpointDialogSize(false);
  setExistingCheckpointsVisible(false);
  const cpLayerSelect = byId("cpDialogMapLayerSelect");
  if (cpLayerSelect && !cpLayerSelect.value && availableMapLayers.length) {
    const rememberedCp = localStorage.getItem(lastCpDialogMapLayerKey) || "";
    cpLayerSelect.value = availableMapLayers.some((x) => x.code === rememberedCp)
      ? rememberedCp
      : availableMapLayers[0].code;
  }
  initCheckpointMap();
  applyCheckpointDialogBaseLayer();
}

function applyCheckpointDialogLocationMode(showGps) {
  byId("cpMap").style.display = showGps ? "block" : "none";
  byId("cpMapToggleSizeBtn").style.display = showGps ? "inline-block" : "none";
  byId("cpToggleExistingBtn").style.display = showGps ? "inline-block" : "none";
  byId("cpDialogMapLayerSelect").style.display = showGps ? "inline-block" : "none";
  document.querySelectorAll(".cp-gps-row").forEach((el) => {
    el.style.display = "grid";
  });
  ["cpLatitude","cpLongitude","cpRadiusM","cpLocationRequired"].forEach((id) => {
    const el = byId(id);
    if (el) el.disabled = !showGps;
  });
}

function resetCheckpointDialogMarkerLayers() {
  if (cpMarker) {
    cpMap.removeLayer(cpMarker);
    cpMarker = null;
  }
  if (cpRadiusCircle) {
    cpMap.removeLayer(cpRadiusCircle);
    cpRadiusCircle = null;
  }
}

function checkpointRadiusPlaceholder(showGps) {
  if (showGps && Number.isFinite(Number(window.__lastCompetitionRadiusM)) && Number(window.__lastCompetitionRadiusM) > 0) {
    return String(Number(window.__lastCompetitionRadiusM));
  }
  return "";
}

function applyNewCheckpointDialogState(showGps) {
  byId("cpTitle").textContent = tr("admin.cp_dialog.new_title");
  byId("cpId").value = "";
  fillCheckpointTypeSelect("NORMAL", null);
  byId("cpName").value = "";
  byId("cpLocation").value = "";
  byId("cpOrder").value = "";
  byId("cpLatitude").value = "";
  byId("cpLongitude").value = "";
  byId("cpRadiusM").value = "";
  byId("cpRadiusM").placeholder = checkpointRadiusPlaceholder(showGps);
  setCpLocationRequiredValue(showGps ? "Y" : "N");
  byId("cpDelete").disabled = true;
  cpDialogCheckpointId = null;
  syncCheckpointTypeUi();
  resetCheckpointDialogMarkerLayers();
  const last = readLastCpCoord();
  if (showGps && last) {
    cpMap.setView([last.lat, last.lon], 16);
    return;
  }
  cpMap.setView([58.6, 25.0], 7);
}

function applyExistingCheckpointDialogState(row, cpId, showGps) {
  byId("cpTitle").textContent = tr("admin.cp_dialog.edit_title");
  byId("cpId").value = cpId;
  fillCheckpointTypeSelect(row?.checkpoint_type || "NORMAL", Number(cpId));
  byId("cpName").value = row?.checkpoint_title || "";
  byId("cpLocation").value = row?.location_hint || "";
  byId("cpOrder").value = row?.checkpoint_order_no ?? "";
  byId("cpLatitude").value = row?.latitude ?? "";
  byId("cpLongitude").value = row?.longitude ?? "";
  byId("cpRadiusM").value = row?.radius_m ?? "";
  byId("cpRadiusM").placeholder = checkpointRadiusPlaceholder(showGps);
  setCpLocationRequiredValue(row?.location_required || "N");
  byId("cpDelete").disabled = false;
  cpDialogCheckpointId = Number(cpId);
  if (row?.latitude != null && row?.longitude != null) {
    setCpCoordinates(Number(row.latitude), Number(row.longitude), true);
  } else {
    resetCheckpointDialogMarkerLayers();
  }
  syncCheckpointTypeUi();
}

function openCheckpointDialog(cpId = null) {
  initCheckpointDialogMapState();
  const showGps = currentCompetitionUseLocation === "Y";
  applyCheckpointDialogLocationMode(showGps);
  if (!cpId) {
    if (!currentCompetitionActive) return;
    applyNewCheckpointDialogState(showGps);
  } else {
    const row = checkpointsData.find((x) => Number(x.checkpoint_id) === Number(cpId));
    applyExistingCheckpointDialogState(row, cpId, showGps);
  }
  cpDialogInitialState = cpDialogStateSnapshot();
  syncCpQuestionButton();
  renderExistingCheckpointsOnDialogMap();
  byId("cpDialog").showModal();
  setTimeout(() => cpMap.invalidateSize(), 50);
}

async function saveCheckpoint() {
  if (!currentCompetitionActive) return;
  const form = {
    checkpointType: normalizeCheckpointType(byId("cpType").value),
    cpId: byId("cpId").value,
    title: byId("cpName").value.trim(),
    orderRaw: byId("cpOrder").value.trim(),
    location: byId("cpLocation").value.trim(),
    latRaw: byId("cpLatitude").value.trim(),
    lonRaw: byId("cpLongitude").value.trim(),
    radiusRaw: byId("cpRadiusM").value.trim(),
    locRequired: getCpLocationRequiredValue()
  };
  form.isSpecial = isSpecialCheckpointType(form.checkpointType);
  form.editingId = form.cpId ? Number(form.cpId) : null;
  if (!form.title) return showMsg("cpMsg", false, tr("admin.msg.cp_title_required"));
  if (hasDuplicateCheckpointTitle(form.title, form.editingId)) {
    return showMsg("cpMsg", false, tr("admin.msg.cp_title_exists"));
  }
  if (!form.isSpecial && currentCompetitionType === "S" && form.orderRaw === "") {
    return showMsg("cpMsg", false, tr("admin.msg.cp_order_required_for_s"));
  }
  if (!form.isSpecial && currentCompetitionType === "S" && form.orderRaw !== "") {
    const nextOrder = Number(form.orderRaw);
    const hasDuplicateOrder = checkpointsData.some((r) => {
      const cpOrder = r?.checkpoint_order_no ?? r?.order_no;
      if (!Number.isFinite(Number(cpOrder))) return false;
      if (Number(cpOrder) !== nextOrder) return false;
      if (form.editingId != null && Number(r?.checkpoint_id) === Number(form.editingId)) return false;
      return true;
    });
    if (hasDuplicateOrder) {
      return showMsg("cpMsg", false, tr("admin.msg.cp_order_exists"));
    }
  }
  if (!form.cpId) {
    const payload = { competition_id: compId(), title: form.title, checkpoint_type: form.checkpointType };
    if (!form.isSpecial && form.orderRaw !== "") payload.order_no = Number(form.orderRaw);
    if (form.location) payload.location_hint = form.location;
    if (currentCompetitionUseLocation === "Y") {
      if (form.latRaw !== "") payload.latitude = Number(form.latRaw);
      if (form.lonRaw !== "") payload.longitude = Number(form.lonRaw);
      if (form.radiusRaw !== "") payload.radius_m = Number(form.radiusRaw);
      payload.location_required = form.locRequired;
    }
    await post("/api/admin/checkpoints", payload);
    if (currentCompetitionUseLocation === "Y" && form.latRaw !== "" && form.lonRaw !== "") {
      writeLastCpCoord(Number(form.latRaw), Number(form.lonRaw));
    }
  } else {
    const payload = { competition_id: compId(), checkpoint_id: Number(form.cpId), title: form.title };
    if (!form.isSpecial && form.orderRaw !== "") payload.order_no = Number(form.orderRaw);
    if (form.location) payload.location_hint = form.location;
    if (currentCompetitionUseLocation === "Y") {
      if (form.latRaw !== "") payload.latitude = Number(form.latRaw);
      if (form.lonRaw !== "") payload.longitude = Number(form.lonRaw);
      if (form.radiusRaw !== "") payload.radius_m = Number(form.radiusRaw);
      payload.location_required = form.locRequired;
    }
    await post("/api/admin/checkpoints/update", payload);
    if (currentCompetitionUseLocation === "Y" && form.latRaw !== "" && form.lonRaw !== "") {
      writeLastCpCoord(Number(form.latRaw), Number(form.lonRaw));
    }
  }
  byId("cpDialog").close();
  await loadView();
}

async function deleteCheckpoint() {
  if (!currentCompetitionActive) return;
  const cpId = Number(byId("cpId").value);
  if (!cpId) return;
  pendingDeleteCheckpointId = cpId;
  byId("cpDeleteDialog").showModal();
}

function setQuestionDialogMode(mode, message = "") {
  const isBlocked = mode === "blocked";
  byId("qDialog").querySelectorAll(".row").forEach((el) => {
    el.classList.toggle("hidden", isBlocked);
    el.style.display = isBlocked ? "none" : "";
  });
  ["singleChoiceBlock", "textAnswersBlock", "qDelete", "qSave"].forEach((id) => {
    const el = byId(id);
    if (!el) return;
    el.classList.toggle("hidden", isBlocked);
    el.style.display = isBlocked ? "none" : "";
  });
  byId("qCancel").disabled = false;
  byId("qDelete").disabled = isBlocked;
  byId("qSave").disabled = isBlocked;

  const qMsgEl = byId("qMsg");
  qMsgEl.textContent = "";
  qMsgEl.className = "";
  if (isBlocked && message) showMsg("qMsg", false, message);
}

function openQuestionDialog(cpId, editMode) {
  if (!currentCompetitionActive) return;
  setQuestionDialogMode("normal");
  fillCheckpointSelect(false, cpId);
  const row = checkpointsData.find((x) => Number(x.checkpoint_id) === Number(cpId));
  byId("qCheckpoint").value = String(cpId);
  if (!editMode) {
    byId("qTitle").textContent = tr("admin.q_dialog.new_title");
    byId("qId").value = "";
    availableLangs.forEach((lang) => { byId(qTextId(lang)).value = ""; });
    byId("qType").value = "SINGLE_CHOICE";
    byId("qPoints").value = "0";
    byId("qWrongPoints").value = "0";
    byId("qInputType").value = "";
    byId("qInputMax").value = "";
    byId("optionRows").innerHTML = "";
    byId("answerRows").innerHTML = "";
    addOptionRow();
    addOptionRow();
    byId("qDelete").disabled = true;
  } else {
    byId("qTitle").textContent = tr("admin.q_dialog.edit_title");
    byId("qId").value = row?.question_id || "";
    availableLangs.forEach((lang) => {
      const key = `text_${lang}`;
      byId(qTextId(lang)).value = row?.[key] || (lang === "et" ? (row?.text_et || "") : "");
    });
    byId("qType").value = row?.question_type || "TEXT";
    byId("qPoints").value = row?.points ?? 0;
    byId("qWrongPoints").value = row?.wrong_points ?? 0;
    byId("qInputType").value = row?.input_type || "";
    byId("qInputMax").value = row?.input_max_length ?? "";
    byId("optionRows").innerHTML = "";
    byId("answerRows").innerHTML = "";
    (row?.options || []).forEach((o) => addOptionRow({
      option_code: o.option_code,
      ...o,
      is_correct: o.is_correct
    }));
    (row?.answers || []).forEach((a) => addAnswerRow({
      answer_value: a.answer_value,
      normalize_mode: a.normalize_mode || "LOWER_TRIM"
    }));
    if ((row?.question_type || "TEXT") === "SINGLE_CHOICE" && (row?.options || []).length === 0) addOptionRow();
    if ((row?.question_type || "TEXT") === "TEXT" && (row?.answers || []).length === 0) addAnswerRow({ normalize_mode: "LOWER_TRIM" });
    byId("qDelete").disabled = false;
  }
  syncQuestionTypeUI();
  byId("qDialog").showModal();
}

function openQuestionBlockedDialog(message) {
  byId("qTitle").textContent = tr("admin.q_dialog.new_title");
  byId("qId").value = "";
  setQuestionDialogMode("blocked", message);
  byId("qDialog").showModal();
}

function resetQuestionDialogVisibility() {
  setQuestionDialogMode("normal");
}

function collectQuestionTextsByLang() {
  const textsByLang = {};
  availableLangs.forEach((lang) => {
    textsByLang[lang] = byId(qTextId(lang)).value.trim();
  });
  return textsByLang;
}

function collectQuestionVariantPayload(questionType) {
  if (questionType === "SINGLE_CHOICE") {
    const { opts, hasCorrect } = collectSingleChoiceOptions();
    if (opts.length === 0) return { error: tr("admin.msg.min_one_option") };
    if (!hasCorrect) return { error: tr("admin.msg.min_one_correct_option") };
    return { optionsJson: JSON.stringify(opts), answersJson: null };
  }
  const answers = collectTextAnswers();
  if (answers.length === 0) return { error: tr("admin.msg.min_one_answer") };
  return { optionsJson: null, answersJson: JSON.stringify(answers) };
}

async function persistQuestionTranslations(questionId, payload, textsByLang, optionsJson, answersJson) {
  for (const lang of availableLangs) {
    const text = textsByLang[lang];
    if (!text && lang !== defaultLang) continue;
    await post("/api/admin/questions/update", {
      competition_id: compId(),
      question_id: Number(questionId),
      checkpoint_id: payload.checkpoint_id,
      question_type: payload.question_type,
      input_type: payload.input_type,
      input_max_length: payload.input_max_length,
      input_pattern: payload.input_pattern,
      points: payload.points,
      wrong_points: payload.wrong_points,
      lang_code: lang,
      question_text: text || payload.question_text,
      options_json: lang === defaultLang ? optionsJson : null,
      answers_json: lang === defaultLang ? answersJson : null
    });
  }
}

async function saveQuestion() {
  if (!currentCompetitionActive) return;
  const textsByLang = collectQuestionTextsByLang();
  const defaultText = textsByLang[defaultLang] || "";
  if (!defaultText) return showMsg("qMsg", false, `${tr("admin.msg.question_text_required_prefix")} (${defaultLang}) ${tr("admin.msg.required_suffix")}`);
  const qType = byId("qType").value;
  const qId = byId("qId").value;
  const payload = {
    competition_id: compId(),
    checkpoint_id: Number(byId("qCheckpoint").value),
    question_type: qType,
    input_type: qType === "SINGLE_CHOICE" ? null : (byId("qInputType").value || null),
    input_max_length: qType === "SINGLE_CHOICE" ? null : (byId("qInputMax").value ? Number(byId("qInputMax").value) : null),
    input_pattern: null,
    points: Number(byId("qPoints").value || 0),
    wrong_points: Number(byId("qWrongPoints").value || 0),
    lang_code: defaultLang,
    question_text: defaultText
  };

  const variants = collectQuestionVariantPayload(qType);
  if (variants.error) return showMsg("qMsg", false, variants.error);
  const { optionsJson, answersJson } = variants;

  try {
    if (!qId) {
      const created = await post("/api/admin/questions", payload);
      const cpState = checkpointsData.find((x) => Number(x.checkpoint_id) === Number(payload.checkpoint_id));
      await persistQuestionTranslations(created.question_id, payload, textsByLang, optionsJson, answersJson);
      if (!cpState?.question_id) {
        byId("qDialog").close();
        await loadView();
        return;
      }
    } else {
      await persistQuestionTranslations(qId, payload, textsByLang, optionsJson, answersJson);
    }
    byId("qDialog").close();
    await loadView();
  } catch (e) {
    showMsg("qMsg", false, humanizeError(e.message, e.details));
  }
}

async function loadCompetitionParticipantMapLayers() {
  const res = await get(`/api/admin/competitions/map-layers?competition_id=${compId()}`);
  const selected = Array.isArray(res?.layer_codes) ? res.layer_codes.map((x) => String(x || "").trim()).filter(Boolean) : [];
  competitionParticipantLayerCodes = selected;
  if (!currentCompetitionOverlay?.exists || String(currentCompetitionOverlay?.processing_status || "").toUpperCase() !== "READY") {
    competitionParticipantLayerCodes = competitionParticipantLayerCodes.filter((code) => code !== EPK_OVERLAY_LAYER_CODE);
  }
  if (!competitionParticipantLayerCodes.length && availableMapLayers.length) {
    const participantDefaults = availableMapLayers.filter((x) => x.participant_default).map((x) => x.code);
    if (participantDefaults.length) {
      competitionParticipantLayerCodes = [...participantDefaults];
    } else {
      const osm = availableMapLayers.find((x) => x.code === "osm");
      competitionParticipantLayerCodes = [osm ? osm.code : availableMapLayers[0].code];
    }
  }
  refreshAdminMapLayerOptions();
  updateMetaMapLayersButtonLabel();
}

function updateMetaOwnMapButtonLabel() {
  const btn = byId("metaOwnMapBtn");
  if (!btn) return;
  btn.textContent = currentCompetitionOverlay?.exists
    ? `${tr("admin.meta.overlay_btn")} (${tr("admin.overlay.exists_short")})`
    : tr("admin.meta.overlay_btn");
}

function updateCompetitionOverlayReadyBadge() {
  const badge = byId("cOverlayReadyBadge");
  if (!badge) return;
  const isReady = String(currentCompetitionOverlay?.processing_status || "").toUpperCase() === "READY";
  badge.classList.toggle("hidden", !isReady);
}

function updateMetaMapLayersButtonLabel() {
  const btn = byId("metaMapLayersBtn");
  if (!btn) return;
  const n = Array.isArray(competitionParticipantLayerCodes) ? competitionParticipantLayerCodes.length : 0;
  btn.textContent = `${tr("admin.meta.map_layers_btn")} (${n})`;
}

function renderParticipantMapLayersDialog() {
  const list = byId("participantMapLayersList");
  list.innerHTML = availableMapLayers.map((layer, idx) => {
    const checked = participantLayerSelection.includes(layer.code);
    const id = `participantLayer_${idx}`;
    return `
      <div class="layer-row">
        <span class="label">${esc(layer.label)}</span>
        <label class="yn-switch" for="${id}">
          <input id="${id}" data-layer-code="${esc(layer.code)}" type="checkbox" ${checked ? "checked" : ""} />
          <span class="yn-slider"></span>
        </label>
      </div>`;
  }).join("");
}

function selectedParticipantLayersFromDialog() {
  return Array.from(document.querySelectorAll("#participantMapLayersList input[data-layer-code]:checked"))
    .map((el) => String(el.getAttribute("data-layer-code") || "").trim())
    .filter(Boolean);
}

function normalizeParticipantLayerSelection(selected) {
  const cleaned = Array.isArray(selected) ? selected.filter(Boolean) : [];
  if (cleaned.includes(EPK_OVERLAY_LAYER_CODE) && !cleaned.includes(EPK_LAYER_CODE)) {
    return [...cleaned, EPK_LAYER_CODE];
  }
  return cleaned;
}

async function openParticipantMapLayersDialog() {
  showMsg("participantMapLayersMsg", false, "");
  await loadMapLayersConfig();
  await loadCompetitionParticipantMapLayers();
  participantLayerSelection = [...competitionParticipantLayerCodes];
  renderParticipantMapLayersDialog();
  byId("participantMapLayersDialog").showModal();
}

async function saveParticipantMapLayersDialog() {
  const selected = normalizeParticipantLayerSelection(selectedParticipantLayersFromDialog());
  if (!selected.length) {
    showMsg("participantMapLayersMsg", false, tr("admin.msg.select_at_least_one_map"));
    return;
  }
  const compareLayerCodes = (a, b) => String(a || "").localeCompare(String(b || ""), "en", { sensitivity: "base" });
  const prevSorted = [...competitionParticipantLayerCodes].sort(compareLayerCodes);
  const nextSorted = [...selected].sort(compareLayerCodes);
  const changed = prevSorted.length !== nextSorted.length || prevSorted.some((x, i) => x !== nextSorted[i]);
  if (changed) {
    await post("/api/admin/competitions/map-layers", {
      competition_id: compId(),
      layer_codes: selected
    });
  }
  competitionParticipantLayerCodes = selected;
  participantLayerSelection = [...selected];
  refreshAdminMapLayerOptions();
  updateMetaMapLayersButtonLabel();
  showMsg("participantMapLayersMsg", true, tr("admin.msg.map_layers_saved"));
  setTimeout(() => byId("participantMapLayersDialog").close(), 350);
}

function renderOverlayCurrentInfo() {
  const target = byId("overlayCurrentInfo");
  const statusTarget = byId("overlayStatusInfo");
  const errorTarget = byId("overlayErrorInfo");
  const errorRow = byId("overlayErrorRow");
  if (!target) return;
  if (statusTarget) statusTarget.textContent = tr("admin.overlay.status.none");
  if (errorTarget) errorTarget.textContent = "";
  if (errorRow) errorRow.classList.add("hidden");
  if (!currentCompetitionOverlay?.exists) {
    target.textContent = tr("admin.overlay.none_selected");
    return;
  }
  const width = Number(currentCompetitionOverlay.width_px || 0);
  const height = Number(currentCompetitionOverlay.height_px || 0);
  target.textContent = `${currentCompetitionOverlay.display_name || "-"} (${width} x ${height})`;
  const statusCode = String(currentCompetitionOverlay.processing_status || "UPLOADED").trim().toLowerCase();
  if (statusTarget) statusTarget.textContent = tr(`admin.overlay.status.${statusCode}`);
  if (errorTarget && errorRow && String(currentCompetitionOverlay.processing_status || "").toUpperCase() === "FAILED" && currentCompetitionOverlay.processing_error) {
    errorTarget.textContent = currentCompetitionOverlay.processing_error;
    errorRow.classList.remove("hidden");
  }
}

function syncOverlayFileInputsEnabled() {
  const hasExistingOverlay = !!currentCompetitionOverlay?.exists;
  const imageInput = byId("overlayImageInput");
  const worldInput = byId("overlayWorldInput");
  if (imageInput) imageInput.disabled = hasExistingOverlay;
  if (worldInput) worldInput.disabled = hasExistingOverlay;
}

async function openOverlayDialog() {
  showMsg("overlayMsg", false, "");
  await loadCompetitionOverlay();
  byId("overlayNameInput").value = currentCompetitionOverlay?.display_name || "";
  byId("overlayAttributionInput").value = currentCompetitionOverlay?.attribution || "";
  byId("overlayImageInput").value = "";
  byId("overlayWorldInput").value = "";
  syncOverlayFileInputsEnabled();
  renderOverlayCurrentInfo();
  byId("overlayDeleteBtn").disabled = !currentCompetitionOverlay?.exists;
  byId("overlayDialog").showModal();
}

async function saveOverlayDialog() {
  const displayName = byId("overlayNameInput").value.trim();
  const attribution = byId("overlayAttributionInput").value.trim();
  if (!displayName) {
    showMsg("overlayMsg", false, tr("admin.overlay.name_required_msg"));
    return;
  }
  if (currentCompetitionOverlay?.exists) {
    await post("/api/admin/competitions/overlay/meta", {
      competition_id: compId(),
      display_name: displayName,
      attribution,
    });
  } else {
    const imageFile = byId("overlayImageInput").files?.[0] || null;
    const worldFile = byId("overlayWorldInput").files?.[0] || null;
    const maxUploadBytes = Number(currentCompetitionOverlay?.max_upload_bytes || 0);
    if (!imageFile || !worldFile) {
      showMsg("overlayMsg", false, tr("admin.overlay.files_required_msg"));
      return;
    }
    if (Number.isFinite(maxUploadBytes) && maxUploadBytes > 0 && Number(imageFile.size || 0) > maxUploadBytes) {
      showMsg("overlayMsg", false, formatTr("admin.overlay.image_file_size_too_large_msg", {
        actual_mb: formatFileSizeMb(imageFile.size || 0),
        max_mb: formatFileSizeMb(maxUploadBytes),
      }));
      return;
    }
    const fd = new FormData();
    fd.append("competition_id", String(compId()));
    fd.append("display_name", displayName);
    fd.append("attribution", attribution);
    fd.append("image_file", imageFile);
    fd.append("world_file", worldFile);
    await postFormData("/api/admin/competitions/overlay/upload", fd);
  }
  await loadView();
  syncOverlayFileInputsEnabled();
  renderOverlayCurrentInfo();
  showMsg("overlayMsg", true, tr("admin.overlay.saved_msg"));
}

async function deleteOverlayDialog() {
  await post("/api/admin/competitions/overlay/delete", { competition_id: compId() });
  if (competitionParticipantLayerCodes.includes(EPK_OVERLAY_LAYER_CODE)) {
    const nextLayers = competitionParticipantLayerCodes.filter((code) => code !== EPK_OVERLAY_LAYER_CODE);
    if (nextLayers.length) {
      await post("/api/admin/competitions/map-layers", {
        competition_id: compId(),
        layer_codes: nextLayers
      });
    }
  }
  await loadView();
  byId("overlayImageInput").value = "";
  byId("overlayWorldInput").value = "";
  byId("overlayNameInput").value = "";
  byId("overlayAttributionInput").value = "";
  syncOverlayFileInputsEnabled();
  renderOverlayCurrentInfo();
  byId("overlayDeleteBtn").disabled = true;
  showMsg("overlayMsg", true, tr("admin.overlay.deleted_msg"));
}

function openMetaDialog() {
  if (!currentCompetitionActive) return;
  byId("metaMsg").textContent = "";
  byId("metaMsg").className = "";
  byId("metaNameInput").value = window.__lastCompetitionName || "";
  byId("metaDescInput").value = window.__lastCompetitionDescription || "";
  byId("metaTypeInput").value = String(window.__lastCompetitionType || "R").toUpperCase();
  byId("metaStatusInput").value = window.__lastCompetitionStatus || "ACTIVE";
  setMetaUseLocationValue(window.__lastCompetitionUseLocation || "N");
  setMetaShowCompetitorLocationValue(window.__lastCompetitionShowCompetitorLocation || "Y");
  syncMetaLocationSwitches();
  byId("metaRadiusMInput").value = (window.__lastCompetitionRadiusM ?? "");
  byId("metaDeclinationValue").textContent = fmtMagDeclination(window.__lastCompetitionDeclination);
  byId("metaDeclinationUpdatedValue").textContent = window.__lastCompetitionDeclinationUpdatedAt
    ? fmtDateEt(window.__lastCompetitionDeclinationUpdatedAt)
    : "-";
  byId("metaStartsEt").value = fmtEtInput((window.__lastStartsAt || ""));
  byId("metaEndsEt").value = fmtEtInput((window.__lastEndsAt || ""));
  syncMetaLocationSwitches();
  updateMetaOwnMapButtonLabel();
  updateMetaMapLayersButtonLabel();
  byId("metaDialog").showModal();
}

async function saveMetaDialog() {
  try {
    const payload = {
      competition_id: compId(),
      name: byId("metaNameInput").value.trim(),
      description: byId("metaDescInput").value.trim() || null,
      type: String(byId("metaTypeInput").value || "R").toUpperCase(),
      status: byId("metaStatusInput").value,
      use_location: getMetaUseLocationValue(),
      show_competitor_location: getMetaShowCompetitorLocationValue(),
      radius_m: byId("metaRadiusMInput").value.trim() ? Number(byId("metaRadiusMInput").value.trim()) : null
    };
    if (!payload.name) {
      showMsg("metaMsg", false, tr("admin.msg.comp_name_required"));
      return;
    }
    const startParsed = parseEtInput(byId("metaStartsEt").value);
    const endParsed = parseEtInput(byId("metaEndsEt").value);
    if (startParsed && startParsed.error) return showMsg("metaMsg", false, startParsed.error);
    if (endParsed && endParsed.error) return showMsg("metaMsg", false, endParsed.error);
    await post("/api/admin/competitions/meta", payload);
    await post("/api/admin/competitions/dates", {
      competition_id: compId(),
      starts_at: startParsed,
      ends_at: endParsed
    });
    byId("metaDialog").close();
    await loadCompetitions();
    await loadView();
    showMsg("topMsg", true, tr("admin.msg.comp_updated"));
  } catch (e) {
    showMsg("metaMsg", false, humanizeError(e.message));
  }
}

async function deleteQuestion() {
  if (!currentCompetitionActive) return;
  const qId = Number(byId("qId").value);
  if (!qId) return;
  pendingDeleteQuestionId = qId;
  byId("qDeleteDialog").showModal();
}

byId("uiLang").onchange = async () => {
  currentUiLang = byId("uiLang").value || defaultLang;
  setCookie(uiLangCookieName, currentUiLang);
  await loadTranslations(currentUiLang);
  renderNoOrgCardCopy();
  await refreshIntroDialogIfOpen();
  refreshAdminMapLayerOptions();
  refreshCompetitionTypeDisplay();
  rerenderCompetitionRouteTexts();
  renderRows();
};

byId("uiLangApp").onchange = async () => {
  currentUiLang = byId("uiLangApp").value || defaultLang;
  setCookie(uiLangCookieName, currentUiLang);
  await loadTranslations(currentUiLang);
  renderNoOrgCardCopy();
  await refreshIntroDialogIfOpen();
  refreshAdminMapLayerOptions();
  refreshCompetitionTypeDisplay();
  rerenderCompetitionRouteTexts();
  renderRows();
};

byId("uiLangNoOrg").onchange = async () => {
  currentUiLang = byId("uiLangNoOrg").value || defaultLang;
  setCookie(uiLangCookieName, currentUiLang);
  await loadTranslations(currentUiLang);
  renderNoOrgCardCopy();
  await refreshIntroDialogIfOpen();
  refreshAdminMapLayerOptions();
  refreshCompetitionTypeDisplay();
  rerenderCompetitionRouteTexts();
  renderRows();
};

byId("loginIntroLink").onclick = async (e) => {
  e.preventDefault();
  try {
    await openIntroDialog();
  } catch (_e) {
    showMsg("loginMsg", false, tr("admin.intro.load_failed"));
  }
};

byId("noOrgIntroLink").onclick = async (e) => {
  e.preventDefault();
  try {
    await openIntroDialog();
  } catch (_e) {
    showMsg("noOrgMsg", false, tr("admin.intro.load_failed"));
  }
};

byId("introDialogClose").onclick = () => closeIntroDialog();

byId("organizers").addEventListener("click", async (e) => {
  const btn = e.target.closest(".logout-btn-inline");
  if (!btn) return;
  try {
    await post("/api/auth/logout", {});
    closeIntroDialog();
    currentUserId = null;
    currentUserName = "";
    currentUserEmail = "";
    byId("appArea").classList.add("hidden");
    byId("loginCard").classList.remove("hidden");
    showMsg("loginMsg", true, tr("admin.msg.logout_ok"));
    await initGoogleLogin();
  } catch (err) {
    showMsg("topMsg", false, humanizeError(err.message || tr("admin.msg.logout_failed")));
  }
});

byId("openCompetitionPickerBtn").onclick = () => byId("competitionPickerDialog").showModal();
byId("copyCompetitionBtn").onclick = () => openCompetitionCopyDialog();
byId("openResultsBtn").onclick = () => {
  const cid = compId();
  if (!cid) return;
  window.open(`/results.html?competition_id=${encodeURIComponent(String(cid))}`, "_blank", "noopener");
};
byId("competitionPickerCancel").onclick = () => {
  byId("competitionPickerJoinCode").value = "";
  showMsg("competitionPickerJoinMsg", false, "");
  byId("competitionPickerDialog").close();
};
byId("competitionPickerApply").onclick = async () => {
  byId("competitionPickerDialog").close();
  await loadView().catch((e) => showMsg("topMsg", false, e.message));
};
byId("copyCompetitionCancel").onclick = () => {
  resetCompetitionCopyDialog();
  byId("copyCompetitionDialog").close();
};
byId("copyCompetitionDialog").addEventListener("close", resetCompetitionCopyDialog);
byId("goSuperadminBtn").onclick = () => {
  window.location.href = "/superadmin.html";
};
byId("competitionPickerJoinSave").onclick = async () => {
  try {
    const code = byId("competitionPickerJoinCode").value.trim();
    if (!code) {
      showMsg("competitionPickerJoinMsg", false, tr("admin.msg.enter_organizer_code_join_dialog"));
      return;
    }
    const joinRes = await post("/api/organizers/register", { access_code: code });
    const joinedCompetitionId = Number(joinRes?.competition_id || 0);
    byId("competitionPickerJoinCode").value = "";
    const hasCompetitions = await loadCompetitions();
    if (hasCompetitions) {
      if (joinedCompetitionId && competitionsData.some((x) => Number(x.competition_id) === joinedCompetitionId)) {
        byId("competitionSelect").value = String(joinedCompetitionId);
      }
      await loadView();
      showMsg("topMsg", true, tr("admin.msg.organizer_code_accepted_join_dialog"));
      showMsg("competitionPickerJoinMsg", false, "");
      byId("competitionPickerDialog").close();
    } else {
      showMsg("competitionPickerJoinMsg", false, tr("admin.msg.organizer_competitions_not_found_join_dialog"));
    }
  } catch (e) {
    showMsg("competitionPickerJoinMsg", false, humanizeError(e.message, e.details));
  }
};
byId("copyCompetitionSave").onclick = async () => {
  try {
    if (!pendingCompetitionCopySourceId) return;
    const res = await post("/api/admin/competitions/copy", {
      source_competition_id: pendingCompetitionCopySourceId,
      copy_questions: byId("copyCompetitionWithQuestions").checked ? "Y" : "N",
      copy_organizers: byId("copyCompetitionWithOrganizers").checked ? "Y" : "N",
      copy_overlay: byId("copyCompetitionWithOverlay").checked ? "Y" : "N",
    });
    resetCompetitionCopyDialog();
    byId("copyCompetitionDialog").close();
    const hasCompetitions = await loadCompetitions();
    if (hasCompetitions && res?.competition_id) {
      byId("competitionSelect").value = String(res.competition_id);
      await loadView();
    }
    showMsg("topMsg", true, tr("admin.copy.created_msg"));
  } catch (e) {
    showMsg("copyCompetitionMsg", false, humanizeError(e.message, e.details));
  }
};

byId("copyCompetitorCodeBtn").innerHTML = copyIconSvg();
byId("copyOrganizerCodeBtn").innerHTML = copyIconSvg();
byId("copyCompetitorCodeBtn").onclick = async () => {
  try {
    await copyTextToClipboard(byId("codeCompetitor").textContent || "");
  } catch (e) {
    showMsg("topMsg", false, humanizeError(e.message));
  }
};
byId("copyOrganizerCodeBtn").onclick = async () => {
  try {
    await copyTextToClipboard(byId("codeOrganizer").textContent || "");
  } catch (e) {
    showMsg("topMsg", false, humanizeError(e.message));
  }
};

byId("regenCompetitor").onclick = () => {
  pendingCodeType = "COMPETITOR";
  pendingOldCode = (byId("codeCompetitor").textContent || "").trim();
  byId("codeConfirmText").innerHTML = `${esc(tr("admin.code_confirm.prompt_prefix"))} <strong style="font-size:22px;">${esc(pendingOldCode || "-")}</strong>?`;
  byId("codeConfirmDialog").showModal();
};

byId("regenOrganizer").onclick = () => {
  pendingCodeType = "ORGANIZER";
  pendingOldCode = (byId("codeOrganizer").textContent || "").trim();
  byId("codeConfirmText").innerHTML = `${esc(tr("admin.code_confirm.prompt_prefix_dup"))} <strong style="font-size:22px;">${esc(pendingOldCode || "-")}</strong>?`;
  byId("codeConfirmDialog").showModal();
};

byId("newCheckpointBtn").onclick = () => openCheckpointDialog();
byId("cpMapToggleSizeBtn").onclick = () => setCheckpointDialogSize(!cpDialogFullscreen);
byId("showCheckpointMapBtn").onclick = async () => {
  showMsg("cpOverviewRouteMsg", false, "");
  cpOverviewLabelsOpen = false;
  try {
    await refreshCurrentCompetitionRoute();
    setCheckpointOverviewRouteVisible(String(currentCompetitionType || "R").toUpperCase() === "S");
    renderCheckpointOverviewLabelsToggle();
    renderCheckpointOverviewRouteControls();
    await openCheckpointOverviewMap();
  } catch (e) {
    showMsg("topMsg", false, humanizeError(e.message, e.details));
  }
};
byId("cpOverviewRouteCalcBtn").onclick = () => requestCheckpointOverviewRouteCalculation().catch((e) => showMsg("cpOverviewRouteMsg", false, humanizeError(e.message, e.details)));
byId("cpOverviewRouteToggleBtn").onclick = () => {
  setCheckpointOverviewRouteVisible(!isCheckpointOverviewRouteVisible());
  renderCheckpointOverviewRouteControls();
  refreshCheckpointOverviewRouteDisplay();
};
byId("cpOverviewLabelsToggleBtn").onclick = () => {
  cpOverviewLabelsOpen = !cpOverviewLabelsOpen;
  if (cpOverviewLabelsOpen) openAllCheckpointLabels();
  else closeAllCheckpointLabels();
  renderCheckpointOverviewLabelsToggle();
};
byId("cpOverviewMapLayerSelect").onchange = () => {
  const selected = selectedMapLayerCode();
  if (selected) localStorage.setItem(lastCpOverviewMapLayerKey, selected);
  openCheckpointOverviewMap().catch((e) => showMsg("topMsg", false, humanizeError(e.message, e.details)));
};
byId("cpDialogMapLayerSelect").onchange = () => {
  const selected = selectedMapLayerCode("cpDialogMapLayerSelect", lastCpDialogMapLayerKey);
  if (selected) localStorage.setItem(lastCpDialogMapLayerKey, selected);
  initCheckpointMap();
  const latRaw = (byId("cpLatitude").value || "").trim();
  const lonRaw = (byId("cpLongitude").value || "").trim();
  const lat = Number(latRaw);
  const lon = Number(lonRaw);
  if (latRaw !== "" && lonRaw !== "" && Number.isFinite(lat) && Number.isFinite(lon)) {
    setCpCoordinates(lat, lon, true);
  }
  renderExistingCheckpointsOnDialogMap();
};

byId("cpOverviewMapToggleSizeBtn").onclick = () => setCheckpointOverviewSize(!cpOverviewFullscreen);
byId("cpOverviewMapCloseBtn").onclick = () => {
  showMsg("cpOverviewRouteMsg", false, "");
  setCheckpointOverviewSize(false);
  byId("cpOverviewMapDialog").close();
};
byId("cpOverviewMapDialog").addEventListener("close", () => {
  showMsg("cpOverviewRouteMsg", false, "");
  cpOverviewLabelsOpen = false;
  renderCheckpointOverviewLabelsToggle();
  if (cpOverviewFullscreen) setCheckpointOverviewSize(false);
});

byId("newQuestionBtn").onclick = () => {
  const first = checkpointsData.find((x) => !x.question_id);
  if (!first) {
    openQuestionBlockedDialog(tr("admin.msg.add_checkpoint_without_question_first"));
    return;
  }
  resetQuestionDialogVisibility();
  openQuestionDialog(first.checkpoint_id, false);
};

byId("sortByTitleIcon").onclick = () => toggleSort("checkpoint_title");
byId("sortByPointsIcon").onclick = () => toggleSort("points");
byId("sortByQuestionEtIcon").onclick = () => toggleSort("text_et");
refreshSortIcons();

byId("cpRows").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-act]");
  if (!btn) return;
  const cpId = Number(btn.dataset.cp);
  if (btn.dataset.act === "edit-cp") openCheckpointDialog(cpId);
  if (btn.dataset.act === "edit-q") openQuestionDialog(cpId, true);
});

byId("cpSave").onclick = () => saveCheckpoint().catch((e) => showMsg("cpMsg", false, humanizeError(e.message, e.details)));
byId("cpToggleExistingBtn").onclick = () => setExistingCheckpointsVisible(!cpExistingVisible);
byId("cpDelete").onclick = () => deleteCheckpoint().catch((e) => showMsg("cpMsg", false, e.message));
byId("cpCancel").onclick = () => byId("cpDialog").close();
byId("cpDialog").addEventListener("close", () => {
  if (cpDialogFullscreen) setCheckpointDialogSize(false);
  showMsg("cpMsg", false, "");
  setExistingCheckpointsVisible(false);
});

byId("participantMapLayersDialog").addEventListener("cancel", (e) => {
  if (!selectedParticipantLayersFromDialog().length) {
    e.preventDefault();
    showMsg("participantMapLayersMsg", false, tr("admin.msg.select_at_least_one_map"));
  }
});

byId("cpOpenQuestion").onclick = () => {
  if (!cpDialogCheckpointId) return;
  const row = checkpointsData.find((x) => Number(x.checkpoint_id) === Number(cpDialogCheckpointId));
  const editMode = !!row?.question_id;
  byId("cpDialog").close();
  openQuestionDialog(Number(cpDialogCheckpointId), editMode);
};

byId("cpType").addEventListener("change", syncCheckpointTypeUi);
byId("cpLatitude").addEventListener("change", syncMapFromCoordInputs);
byId("cpLongitude").addEventListener("change", syncMapFromCoordInputs);
byId("cpRadiusM").addEventListener("input", syncRadiusCircle);
["cpName","cpLocation","cpOrder","cpLatitude","cpLongitude","cpRadiusM","cpLocationRequired"].forEach((id) => {
  byId(id).addEventListener("input", syncCpQuestionButton);
  byId(id).addEventListener("change", syncCpQuestionButton);
});

byId("qSave").onclick = () => saveQuestion().catch((e) => showMsg("qMsg", false, e.message));
byId("qDelete").onclick = () => deleteQuestion().catch((e) => showMsg("qMsg", false, e.message));
byId("qCancel").onclick = () => byId("qDialog").close();
byId("qType").onchange = () => syncQuestionTypeUI();
byId("metaUseLocationInput").addEventListener("change", syncMetaLocationSwitches);
byId("metaOwnMapBtn").onclick = () => openOverlayDialog().catch((e) => showMsg("topMsg", false, humanizeError(e.message, e.details)));
byId("metaMapLayersBtn").onclick = () => openParticipantMapLayersDialog().catch((e) => showMsg("metaMsg", false, humanizeError(e.message, e.details)));
byId("overlayCancelBtn").onclick = () => byId("overlayDialog").close();
byId("overlaySaveBtn").onclick = () => saveOverlayDialog().catch((e) => showMsg("overlayMsg", false, humanizeError(e.message, e.details)));
byId("overlayDeleteBtn").onclick = () => deleteOverlayDialog().catch((e) => showMsg("overlayMsg", false, humanizeError(e.message, e.details)));
byId("participantMapLayersCancel").onclick = () => {
  if (!selectedParticipantLayersFromDialog().length) {
    showMsg("participantMapLayersMsg", false, tr("admin.msg.select_at_least_one_map"));
    return;
  }
  byId("participantMapLayersDialog").close();
};
byId("participantMapLayersSave").onclick = () => saveParticipantMapLayersDialog().catch((e) => showMsg("participantMapLayersMsg", false, humanizeError(e.message, e.details)));
byId("addOptionBtn").onclick = () => addOptionRow();
byId("addAnswerBtn").onclick = () => addAnswerRow({ normalize_mode: "LOWER_TRIM" });

byId("cpDeleteNo").onclick = () => {
  pendingDeleteCheckpointId = null;
  byId("cpDeleteDialog").close();
};
byId("cpDeleteYes").onclick = async () => {
  try {
    if (!pendingDeleteCheckpointId) return;
    await post("/api/admin/checkpoints/delete", { competition_id: compId(), checkpoint_id: pendingDeleteCheckpointId });
    pendingDeleteCheckpointId = null;
    byId("cpDeleteDialog").close();
    byId("cpDialog").close();
    await loadView();
  } catch (e) {
    byId("cpDeleteDialog").close();
    showMsg("cpMsg", false, humanizeError(e.message));
  }
};

byId("qDeleteNo").onclick = () => {
  pendingDeleteQuestionId = null;
  byId("qDeleteDialog").close();
};
byId("qDeleteYes").onclick = async () => {
  try {
    if (!pendingDeleteQuestionId) return;
    await post("/api/admin/questions/delete", { competition_id: compId(), question_id: pendingDeleteQuestionId });
    pendingDeleteQuestionId = null;
    byId("qDeleteDialog").close();
    byId("qDialog").close();
    await loadView();
  } catch (e) {
    byId("qDeleteDialog").close();
    showMsg("qMsg", false, humanizeError(e.message));
  }
};

byId("metaCancel").onclick = () => byId("metaDialog").close();
byId("metaSave").onclick = saveMetaDialog;
byId("openCompetitionEditBtn").onclick = () => openMetaDialog();
byId("openTermsBtn").onclick = () => openTermsDialog();
byId("termsCancel").onclick = () => byId("termsDialog").close();
byId("termsSave").onclick = () => saveTermsDialog();
byId("termsLangSelect").onchange = async (e) => {
  const nextLang = String(e?.target?.value || "").toLowerCase();
  if (!nextLang) return;
  try {
    await loadCompetitionTermsForLang(nextLang);
    showMsg("termsMsg", true, "");
  } catch (err) {
    showMsg("termsMsg", false, humanizeError(err.message));
  }
};

byId("codeConfirmNo").onclick = () => {
  pendingCodeType = null;
  pendingOldCode = null;
  byId("codeConfirmDialog").close();
};
byId("codeConfirmYes").onclick = async () => {
  try {
    const result = await post("/api/admin/access-codes", {
      competition_id: compId(),
      code_type: pendingCodeType,
      force_regenerate: "Y",
      status: "ACTIVE"
    });
    const newCode = String(result?.code || "").trim();
    await loadView();
    byId("codeConfirmDialog").close();
    byId("codeResultText").innerHTML = `${esc(tr("admin.code_result.prefix"))} <strong style="font-size:22px;">${esc(newCode)}</strong>.<br>${esc(tr("admin.code_result.suffix"))}`;
    byId("codeResultDialog").showModal();
    pendingCodeType = null;
    pendingOldCode = null;
  } catch (e) {
    byId("codeConfirmDialog").close();
    showMsg("topMsg", false, humanizeError(e.message));
  }
};

byId("codeResultOk").onclick = () => byId("codeResultDialog").close();
byId("fieldInfoClose").onclick = () => closeFieldInfoDialog();
byId("organizerJoinLogoutNoComp").onclick = async () => {
  try {
    await post("/api/auth/logout", {});
    closeIntroDialog();
    currentUserId = null;
    currentUserName = "";
    currentUserEmail = "";
    byId("organizerJoinCodeNoComp").value = "";
    byId("loginCard").classList.remove("hidden");
    byId("appArea").classList.add("hidden");
    showMsg("noOrgMsg", false, "");
    showMsg("loginMsg", true, tr("admin.msg.logout_ok"));
    await initGoogleLogin();
  } catch (e) {
    showMsg("noOrgMsg", false, humanizeError(e.message, e.details));
  }
};
byId("createEmptyCompetitionNoComp").onclick = async () => {
  try {
    const res = await post("/api/admin/competitions/create-empty", {});
    const hasCompetitions = await loadCompetitions();
    if (hasCompetitions && res?.competition_id) {
      byId("competitionSelect").value = String(res.competition_id);
      await loadView();
    }
    showMsg("topMsg", true, tr("admin.no_org.empty_create_success_msg"));
  } catch (e) {
    showMsg("noOrgMsg", false, humanizeError(e.message, e.details));
  }
};
byId("organizerJoinSaveNoComp").onclick = async () => {
  try {
    const code = byId("organizerJoinCodeNoComp").value.trim();
    if (!code) {
      showMsg("noOrgMsg", false, tr("admin.msg.enter_organizer_code_no_comp"));
      return;
    }
    await post("/api/organizers/register", { access_code: code });
    byId("organizerJoinCodeNoComp").value = "";
    const hasCompetitions = await loadCompetitions();
    if (hasCompetitions) {
      await loadView();
      showMsg("topMsg", true, tr("admin.msg.organizer_code_accepted_top"));
    }
  } catch (e) {
    showMsg("noOrgMsg", false, humanizeError(e.message, e.details));
  }
};

document.addEventListener("keydown", (e) => {
  if (e.key === "F2" && !byId("appArea").classList.contains("hidden")) {
    const first = checkpointsData.find((x) => !x.question_id);
    if (first) openQuestionDialog(first.checkpoint_id, false);
  }
});

document.addEventListener("click", (e) => {
  const trigger = e.target.closest("[data-info-key]");
  if (!trigger) return;
  e.preventDefault();
  openFieldInfoDialog(trigger.getAttribute("data-info-key"));
});

window.addEventListener("admin-auth-invalidated", () => {
  handleAdminAuthInvalidated().catch(() => {});
});

(async () => {
  try {
    showAdminBootLoading();
    await loadI18nMeta().catch(() => {});
    markAdminBootTextReady();
    await hydrateSessionUser();
    if (currentUserId) {
      try {
        await finishAdminLogin();
      } catch (_) {
        byId("loginCard").classList.remove("hidden");
        byId("appArea").classList.add("hidden");
      }
    } else {
      byId("loginCard").classList.remove("hidden");
      byId("appArea").classList.add("hidden");
    }
    await initGoogleLogin();
  } finally {
    hideAdminBootLoading();
  }
})();
