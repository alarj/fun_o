let competitorMobileAppConfig = {
  androidOpenUrl: "funo://open",
  androidDownloadUrl: "",
};

function mySortIconFor(key) {
  if (myResultsSortKey !== key) return "\u2630";
  return myResultsSortDir === "asc" ? "\u25B2" : "\u25BC";
}

function refreshMySortIcons() {
  el("mrSortTitle").textContent = mySortIconFor("checkpoint_title");
  el("mrSortTime").textContent = mySortIconFor("submitted_at");
}

function sortMyResults() {
  const dir = myResultsSortDir === "asc" ? 1 : -1;
  return [...myResultsItems].sort((a, b) => {
    if (myResultsSortKey === "checkpoint_title") {
      return String(a.checkpoint_title || "").localeCompare(String(b.checkpoint_title || ""), "et", { sensitivity: "base" }) * dir;
    }
    const av = a.submitted_at ? (parseUtcDate(a.submitted_at)?.getTime() ?? 0) : 0;
    const bv = b.submitted_at ? (parseUtcDate(b.submitted_at)?.getTime() ?? 0) : 0;
    return (av - bv) * dir;
  });
}

function renderMyResults() {
  const rows = sortMyResults();
  const box = el("myResultsRows");
  if (!rows.length) {
    box.innerHTML = `<tr><td colspan="3">${tr("competitor.msg.no_completed_cp")}</td></tr>`;
    refreshMySortIcons();
    return;
  }
  box.innerHTML = rows.map((r) => {
    const isSubmission = String(r.submission_source || "SUBMISSION").toUpperCase() === "SUBMISSION";
    const detailId = Number(r.submission_id || 0);
    const titleHtml = isSubmission && detailId > 0
      ? `<button class="kpLink" data-sub-id="${detailId}">${esc(r.checkpoint_title || "-")}</button>`
      : `<span>${esc(r.checkpoint_title || "-")}</span>`;
    return `<tr>
    <td>${titleHtml}</td>
    <td>${esc(fmtEtLocal(r.submitted_at))}</td>
    <td>${Number(r.awarded_points || 0)}</td>
  </tr>`;
  }).join("");
  refreshMySortIcons();
}

function setMyResultsOpen(open) {
  el("myResultsCollapsed").style.display = open ? "none" : "flex";
  el("myResExpanded").style.display = open ? "block" : "none";
}

function setMySort(key) {
  if (myResultsSortKey === key) myResultsSortDir = myResultsSortDir === "asc" ? "desc" : "asc";
  else {
    myResultsSortKey = key;
    myResultsSortDir = key === "submitted_at" ? "desc" : "asc";
  }
  renderMyResults();
}

async function loadMyResults() {
  if (!state.selectedCompetitionId) return;
  const res = await apiGet(`/api/competitor/my-submissions?competition_id=${state.selectedCompetitionId}`);
  if (!res.ok) {
    setMsg("answerMsg", res.userMessage || tr("competitor.msg.my_results_load_failed"), false);
    return;
  }
  myResultsItems = Array.isArray(res.data.items) ? res.data.items : [];
  state.mapItems = await loadMapCheckpoints();
  if (compMap && el("compMapBackdrop")?.style?.display === "block") {
    renderCompMap(state.mapItems || [], { preserveViewport: true });
    if (mapHeadingMode) {
      refreshHeadingOutput("compass");
    }
  }
  renderMyResults();
  setMyResultsOpen(true);
}

async function openMyAnswerDetail(submissionId) {
  if (!state.selectedCompetitionId || !submissionId) return;
  const lang = (el("langSelect")?.value || i18nMeta.default_lang || "et").trim().toLowerCase();
  const res = await apiGet(`/api/competitor/my-submission-detail?competition_id=${state.selectedCompetitionId}&submission_id=${Number(submissionId)}&lang_code=${encodeURIComponent(lang)}`);
  if (!res.ok || !res.data) {
    setMsg("answerMsg", res.userMessage || tr("competitor.msg.answer_detail_load_failed"), false);
    return;
  }
  const d = res.data;
  el("myAnswerQuestion").textContent = `${d.question_text || "-"} (${Number(d.points || 0)} / ${Number(d.wrong_points || 0)})`;
  el("myAnswerSubmittedAt").textContent = trf("competitor.answer_detail.submitted_at", { value: fmtEtLocal(d.submitted_at) });
  el("myAnswerPoints").textContent = trf("competitor.answer_detail.points", { value: Number(d.awarded_points || 0) });
  el("myAnswerResponders").textContent = trf("competitor.answer_detail.responders", { value: Number(d.responders_count || 0) });
  el("myAnswerCorrectPct").textContent = trf("competitor.answer_detail.correct_pct", { value: d.correct_pct == null ? "-" : `${Number(d.correct_pct).toFixed(1)}%` });

  const options = Array.isArray(d.options) ? d.options : [];
  const answer = String(d.competitor_answer || "");
  if (!options.length) {
    el("myAnswerVariants").innerHTML = `<li><span class="ansPicked">${esc(answer || "-")}</span></li>`;
  } else {
    const normalizedAnswer = normAnswer(answer);
    let matchedByText = false;
    const rendered = options.map((o) => {
      const c = String(o.is_correct || "N").toUpperCase() === "Y";
      const selectedByFlag = String(o.is_selected || "N").toUpperCase() === "Y";
      const selectedByText = normalizedAnswer && normAnswer(o.option_text || "") === normalizedAnswer;
      if (selectedByText) matchedByText = true;
      const s = selectedByFlag || selectedByText;
      const icon = c ? "\u2713" : "\u2717";
      const cls = c ? "okI" : "noI";
      return `<li><span class="${cls}">${icon}</span><span class="${s ? "ansPicked" : ""}">${esc(o.option_text || "-")}</span></li>`;
    });
    if (normalizedAnswer && !matchedByText) {
      rendered.push(`<li><span class="noI">\u2717</span><span class="ansPicked">${esc(answer)}</span> <span style="color:#5f6b70;">(${tr("competitor.answer_detail.your_answer")})</span></li>`);
    }
    el("myAnswerVariants").innerHTML = rendered.join("");
  }
  el("myAnswerDetailBackdrop").style.display = "flex";
}

function setActiveCompetitionFromSession(sessionData) {
  if (!sessionData || !sessionData.participant) {
    state.activeCompetition = null;
    state.selectedCompetitionId = null;
    state.mapRoute = null;
    return;
  }
  const p = sessionData.participant;
  state.userId = Number(sessionData.user_id || 0) || null;
  state.selectedCompetitionId = Number(p.competition_id || 0) || null;
  state.mapRoute = normalizeCompetitionRouteSnapshot(p.route);
  state.activeCompetition = {
    competition_id: state.selectedCompetitionId,
    name: p.competition_name || "-",
    description: p.competition_description || "",
    type: p.competition_type || "R",
    status: p.status || null,
    starts_at: p.starts_at || null,
    ends_at: p.ends_at || null,
    mass_start_at: null,
    alias_display: p.alias_display || null,
    competitor_name: p.competitor_name || null,
    use_location: p.use_location || "N",
    show_competitor_location: p.show_competitor_location || "Y",
    competition_participant_id: Number(p.competition_participant_id || 0) || null,
  };
}

let competitorSessionEndedHandled = false;

function handleCompetitorSessionEnded() {
  if (competitorSessionEndedHandled) return;
  competitorSessionEndedHandled = true;
  try {
    if (el("compMapBackdrop")?.style?.display === "block" && typeof closeCompMapModal === "function") {
      closeCompMapModal();
    }
  } catch {}
  try {
    state.feedbackOpen = false;
    el("feedbackBackdrop").style.display = "none";
  } catch {}
  try {
    if (typeof closeMapQuestionModal === "function") closeMapQuestionModal();
  } catch {}
  try {
    setSubmissionBusy(false);
  } catch {}
  state.hasAuthenticatedCompetitionSession = false;
  state.openItems = [];
  state.openItemsLoaded = false;
  state.mapItems = [];
  state.mapQuestionItem = null;
  state.joinPreview = null;
  state.geo.enabled = false;
  state.geo.latitude = null;
  state.geo.longitude = null;
  state.geo.radius_m = null;
  state.geo.error = null;
  state.mapRoute = null;
  globalThis.funoResetCompetitorClientCaches?.();
  setActiveCompetitionFromSession(null);
  el("competitionPickerBackdrop").style.display = "none";
  el("joinTermsBackdrop").style.display = "none";
  el("joinSwitchWarningBackdrop").style.display = "none";
  el("myAnswerDetailBackdrop").style.display = "none";
  el("mainCard").style.display = "none";
  el("competitionRouteCard").style.display = "none";
  el("answerCard").style.display = "none";
  el("myResultsCard").style.display = "none";
  renderCompetitionRouteSummary();
  openJoinModal(null, { showClose: false, hasActive: false, codeReadonly: false });
}

globalThis.funoHandleCompetitorSessionEnded = handleCompetitorSessionEnded;

async function ensureCompetitorSession() {
  const res = await apiPost("/api/competitor/ensure-session", {});
  if (!res.ok) {
    setMsg("joinMsg", res.userMessage || tr("competitor.msg.session_create_failed"), false);
    return false;
  }
  state.userId = Number(res.data?.user_id || 0) || null;
  return true;
}

async function loadJoinCaptchaConfig() {
  const res = await apiGet("/api/competitor/join-config");
  if (!res.ok || !res.data) {
    joinCaptchaConfig = {
      enabled: false,
      v3SiteKey: "",
      v2SiteKey: "",
      v3Action: "competitor_join_preview",
      unavailable: true,
    };
    return;
  }
  joinCaptchaConfig = {
    enabled: res.data.enabled === true,
    v3SiteKey: String(res.data.v3_site_key || ""),
    v2SiteKey: String(res.data.v2_site_key || ""),
    v3Action: String(res.data.v3_action || "competitor_join_preview"),
    unavailable: false,
  };
}

function isAndroidBrowserContext() {
  if (globalThis.funoApp?.isNativePlatform?.()) return false;
  const ua = String(globalThis.navigator?.userAgent || "").toLowerCase();
  return ua.includes("android");
}

function canShowCompetitorAppPrompt() {
  if (!isAndroidBrowserContext()) return false;
  try {
    return globalThis.sessionStorage?.getItem("funo_competitor_app_prompt_dismissed") !== "1";
  } catch {
    return true;
  }
}

function dismissCompetitorAppPrompt() {
  try {
    globalThis.sessionStorage?.setItem("funo_competitor_app_prompt_dismissed", "1");
  } catch {}
  el("competitorAppPromptBackdrop").style.display = "none";
}

function updateCompetitorAppPromptButtons() {
  const downloadUrl = String(competitorMobileAppConfig.androidDownloadUrl || "").trim();
  const hasDownloadUrl = !!downloadUrl;
  el("competitorAppPromptDownloadBtn").style.display = hasDownloadUrl ? "block" : "none";
  el("competitorAppPromptDownloadHint").style.display = hasDownloadUrl ? "block" : "none";
}

async function loadCompetitorMobileAppConfig() {
  const res = await apiGet("/api/competitor/mobile-app-config");
  if (!res.ok || !res.data) {
    competitorMobileAppConfig = {
      androidOpenUrl: "funo://open",
      androidDownloadUrl: "",
    };
    updateCompetitorAppPromptButtons();
    return;
  }
  competitorMobileAppConfig = {
    androidOpenUrl: String(res.data.android_open_url || "funo://open").trim() || "funo://open",
    androidDownloadUrl: String(res.data.android_download_url || "").trim(),
  };
  updateCompetitorAppPromptButtons();
}

function maybeShowCompetitorAppPrompt() {
  if (!canShowCompetitorAppPrompt()) return;
  updateCompetitorAppPromptButtons();
  el("competitorAppPromptBackdrop").style.display = "flex";
}

async function loadSessionState() {
  competitorSessionEndedHandled = false;
  const res = await apiGet("/api/competitor/session");
  if (!res.ok || !res.data?.authenticated) {
    state.hasAuthenticatedCompetitionSession = false;
    setActiveCompetitionFromSession(null);
    el("mainCard").style.display = "none";
    el("competitionRouteCard").style.display = "none";
    el("answerCard").style.display = "none";
    el("myResultsCard").style.display = "none";
    renderCompetitionRouteSummary();
    return false;
  }
  state.hasAuthenticatedCompetitionSession = true;
  setActiveCompetitionFromSession(res.data);
  el("joinByCodeBackdrop").style.display = "none";
  el("competitionPickerBackdrop").style.display = "none";
  renderCompetitionText();
  renderCompetitionPicker();
  el("mainCard").style.display = "block";
  el("myResultsCard").style.display = "block";
  renderCompetitionRouteSummary();
  setMyResultsOpen(false);
  try {
    await applyCheckpointLoadingMode();
    await ensureProgressLoaded(true);
  } catch {
    setMsg("answerMsg", tr("competitor.msg.competition_data_load_failed"), false);
  }
  return true;
}

function preferredJoinCaptchaLang() {
  return String(
    el("joinLangSelect")?.value ||
    el("langSelect")?.value ||
    i18nMeta.default_lang ||
    "et"
  ).trim().toLowerCase();
}

function closeJoinCaptchaModal() {
  joinCaptchaPending = null;
  setMsg("joinCaptchaMsg", "", true);
  el("joinCaptchaBackdrop").style.display = "none";
  if (globalThis.grecaptcha && joinRecaptchaWidgetId !== null) {
    try {
      globalThis.grecaptcha.reset(joinRecaptchaWidgetId);
    } catch {}
  }
}

async function ensureJoinRecaptchaApiLoaded() {
  if (!joinCaptchaConfig.enabled) return false;
  if (globalThis.grecaptcha?.ready) return true;
  if (!joinRecaptchaScriptPromise) {
    joinRecaptchaScriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = `https://www.google.com/recaptcha/api.js?render=${encodeURIComponent(joinCaptchaConfig.v3SiteKey)}&hl=${encodeURIComponent(preferredJoinCaptchaLang())}`;
      script.async = true;
      script.defer = true;
      script.onload = () => {
        if (globalThis.grecaptcha?.ready) resolve(true);
        else reject(new Error("grecaptcha_not_ready"));
      };
      script.onerror = () => reject(new Error("grecaptcha_load_failed"));
      document.head.appendChild(script);
    }).catch((err) => {
      joinRecaptchaScriptPromise = null;
      throw err;
    });
  }
  await joinRecaptchaScriptPromise;
  return true;
}

async function executeJoinRecaptchaV3() {
  await ensureJoinRecaptchaApiLoaded();
  if (!globalThis.grecaptcha?.ready) throw new Error("grecaptcha_not_available");
  await new Promise((resolve) => globalThis.grecaptcha.ready(resolve));
  return globalThis.grecaptcha.execute(joinCaptchaConfig.v3SiteKey, {
    action: joinCaptchaConfig.v3Action || "competitor_join_preview",
  });
}

async function ensureJoinCaptchaWidgetRendered() {
  await ensureJoinRecaptchaApiLoaded();
  if (!globalThis.grecaptcha?.ready) throw new Error("grecaptcha_not_available");
  await new Promise((resolve) => globalThis.grecaptcha.ready(resolve));
  if (joinRecaptchaWidgetId !== null) {
    try {
      globalThis.grecaptcha.reset(joinRecaptchaWidgetId);
    } catch {}
    return joinRecaptchaWidgetId;
  }
  joinRecaptchaWidgetId = globalThis.grecaptcha.render("joinCaptchaWidget", {
    sitekey: joinCaptchaConfig.v2SiteKey,
    callback: (token) => {
      handleJoinCaptchaSolved(token).catch(() => {});
    },
    "expired-callback": () => {
      setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_expired"), false);
    },
    "error-callback": () => {
      setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_failed"), false);
    },
  });
  return joinRecaptchaWidgetId;
}

async function openJoinCaptchaModal(context) {
  joinCaptchaPending = context;
  setMsg("joinCaptchaMsg", "", true);
  el("joinCaptchaBackdrop").style.display = "flex";
  try {
    await ensureJoinCaptchaWidgetRendered();
  } catch {
    setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_load_failed"), false);
  }
}

async function requestJoinPreview(accessCode, aliasDisplay, extraPayload = {}) {
  const payload = {
    code: accessCode,
    lang_code: el("joinLangSelect")?.value || el("langSelect")?.value || "et",
    alias_display: aliasDisplay,
    ...extraPayload,
  };
  return apiPost("/api/competitor/join-preview", payload);
}

async function handleJoinCaptchaSolved(v2Token) {
  const pending = joinCaptchaPending;
  if (!pending?.accessCode || !pending?.aliasDisplay || !v2Token) {
    setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_failed"), false);
    return;
  }
  setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_verifying"), true);
  const previewRes = await requestJoinPreview(pending.accessCode, pending.aliasDisplay, {
    recaptcha_v2_token: v2Token,
  });
  if (!previewRes.ok) {
    const errCode = previewRes.data?.detail?.code;
    if (errCode === "JOIN_CAPTCHA_FAILED") {
      setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_failed"), false);
    } else if (errCode === "JOIN_CAPTCHA_UNAVAILABLE") {
      setMsg("joinCaptchaMsg", tr("competitor.msg.join_captcha_unavailable"), false);
    } else {
      setMsg("joinCaptchaMsg", previewRes.userMessage || tr("competitor.msg.join_failed"), false);
    }
    if (globalThis.grecaptcha && joinRecaptchaWidgetId !== null) {
      try {
        globalThis.grecaptcha.reset(joinRecaptchaWidgetId);
      } catch {}
    }
    return;
  }
  closeJoinCaptchaModal();
  await finalizeJoinPreview(previewRes);
}

async function finalizeJoinPreview(previewRes) {
  state.joinPreview = previewRes.data;
  const termsText = state.joinPreview?.terms?.terms_text || "";
  if (!state.joinPreview?.terms?.terms_id || !state.joinPreview?.join_proof) {
    setMsg("joinMsg", tr("competitor.msg.terms_missing"), false);
    return;
  }
  setMsg("joinMsg", "", true);
  setMsg("joinTermsMsg", "", true);
  setMsg("joinCaptchaMsg", "", true);
  el("joinTermsCompName").textContent = state.joinPreview?.competition_name || "-";
  el("joinTermsBody").innerHTML = sanitizeTermsHtml(termsText || "");
  el("joinTermsBackdrop").style.display = "flex";
}

async function joinCompetition() {
  setMsg("joinMsg", "", true);
  setMsg("joinTermsMsg", "", true);
  if (joinCaptchaConfig.unavailable) {
    setMsg("joinMsg", tr("competitor.msg.join_captcha_unavailable"), false);
    return;
  }
  const accessCode = el("joinCode").value.trim();
  if (!accessCode) {
    setMsg("joinMsg", tr("competitor.msg.enter_code"), false);
    return;
  }
  const aliasDisplay = el("joinAlias").value.trim();
  if (!aliasDisplay) {
    setMsg("joinMsg", tr("competitor.msg.enter_alias"), false);
    return;
  }
  let previewRes;
  try {
    if (joinCaptchaConfig.enabled) {
      setMsg("joinMsg", tr("competitor.msg.join_captcha_verifying"), true);
      const v3Token = await executeJoinRecaptchaV3();
      previewRes = await requestJoinPreview(accessCode, aliasDisplay, { recaptcha_v3_token: v3Token });
    } else {
      previewRes = await requestJoinPreview(accessCode, aliasDisplay);
    }
  } catch {
    setMsg("joinMsg", tr("competitor.msg.join_captcha_load_failed"), false);
    return;
  }
  if (!previewRes.ok) {
    const errCode = previewRes.data?.detail?.code;
    if (errCode === "JOIN_CAPTCHA_V2_REQUIRED") {
      setMsg("joinMsg", "", true);
      await openJoinCaptchaModal({ accessCode, aliasDisplay });
      return;
    }
    if (errCode === "INVALID_ACCESS_CODE" || errCode === "ACCESS_CODE_LIMIT_REACHED") setMsg("joinMsg", tr("competitor.msg.join_not_possible"), false);
    else if (errCode === "ALREADY_PARTICIPANT") setMsg("joinMsg", tr("competitor.msg.already_participant"), false);
    else if (errCode === "ALIAS_TAKEN") setMsg("joinMsg", tr("competitor.msg.alias_not_suitable"), false);
    else if (errCode === "ORDS_ERROR") setMsg("joinMsg", tr("competitor.msg.join_service_unavailable"), false);
    else if (errCode === "JOIN_CAPTCHA_UNAVAILABLE") setMsg("joinMsg", tr("competitor.msg.join_captcha_unavailable"), false);
    else if (errCode === "JOIN_CAPTCHA_FAILED" || errCode === "JOIN_CAPTCHA_REQUIRED") setMsg("joinMsg", tr("competitor.msg.join_captcha_retry"), false);
    else setMsg("joinMsg", previewRes.userMessage || tr("competitor.msg.unknown_code"), false);
    return;
  }
  await finalizeJoinPreview(previewRes);
}

async function confirmJoinCompetition() {
  setMsg("joinTermsMsg", "", true);
  setMsg("joinMsg", "", true);
  const accessCode = el("joinCode").value.trim();
  const aliasDisplay = el("joinAlias").value.trim();
  if (!accessCode || !aliasDisplay || !state.joinPreview?.terms?.terms_id) {
    setMsg("joinTermsMsg", tr("competitor.msg.join_not_possible"), false);
    return;
  }
  const completeRes = await apiPost("/api/competitor/join-complete", {
    code: accessCode,
    alias_display: aliasDisplay,
    contact_email: el("joinEmail").value.trim() || null,
    terms_id: state.joinPreview.terms.terms_id,
    terms_lang_code: state.joinPreview.terms.lang_code || (el("langSelect").value || i18nMeta.default_lang),
    accept_terms: true,
    join_proof: state.joinPreview.join_proof || null,
  });
  if (!completeRes.ok) {
    const errCode = completeRes.data?.detail?.code;
    if (errCode === "ALREADY_PARTICIPANT") {
      setMsg("joinTermsMsg", tr("competitor.msg.already_participant"), false);
    } else if (errCode === "ALIAS_TAKEN") {
      setMsg("joinTermsMsg", tr("competitor.msg.alias_not_suitable"), false);
    } else if (errCode === "INVALID_ACCESS_CODE" || errCode === "ACCESS_CODE_LIMIT_REACHED") {
      setMsg("joinTermsMsg", tr("competitor.msg.join_not_possible"), false);
    } else if (errCode === "ORDS_ERROR") {
      setMsg("joinTermsMsg", tr("competitor.msg.join_service_unavailable"), false);
    } else {
      setMsg("joinTermsMsg", completeRes.userMessage || tr("competitor.msg.join_failed"), false);
    }
    return;
  }
  const loaded = await loadSessionState();
  if (!loaded) {
    setMsg("joinTermsMsg", tr("competitor.msg.join_ok_session_load_failed"), false);
    return;
  }
  el("joinTermsBackdrop").style.display = "none";
  el("joinByCodeBackdrop").style.display = "none";
  el("competitionPickerBackdrop").style.display = "none";
  closeJoinSwitchWarning();
  clearJoinCodeFromUrl();
  setMsg("joinTermsMsg", tr("competitor.msg.join_ok"), true);
}

function backFromTerms() {
  el("joinTermsBackdrop").style.display = "none";
  setMsg("joinTermsMsg", "", true);
  setMsg("joinMsg", "", true);
  setMsg("joinCaptchaMsg", "", true);
  if (joinHasActiveBeforeOpen) {
    el("joinByCodeBackdrop").style.display = "none";
    el("competitionPickerBackdrop").style.display = "none";
  } else {
    el("joinByCodeBackdrop").style.display = "flex";
  }
}

function getCodeFromUrl() {
  const params = new URLSearchParams(window.location.search || "");
  const code = (params.get("join_code") || params.get("code") || "").trim();
  return code || null;
}

function clearJoinCodeFromUrl() {
  const url = new URL(window.location.href);
  let changed = false;
  if (url.searchParams.has("join_code")) {
    url.searchParams.delete("join_code");
    changed = true;
  }
  if (url.searchParams.has("code")) {
    url.searchParams.delete("code");
    changed = true;
  }
  if (changed) {
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
  }
}

function setJoinCodeReadonly(readonly) {
  joinCodeReadonly = readonly;
  const input = el("joinCode");
  input.readOnly = readonly;
  input.classList.toggle("joinReadonlyCode", readonly);
  el("joinCodeReadonlyHint").classList.toggle("hidden", !readonly);
}

function closeJoinSwitchWarning() {
  el("joinSwitchWarningBackdrop").style.display = "none";
  el("joinSwitchWarningBody").innerHTML = "";
  setMsg("joinSwitchWarningMsg", "", true);
  pendingJoinSwitch = null;
}

function openJoinSwitchWarning(nextCompetition) {
  pendingJoinSwitch = nextCompetition;
  el("joinSwitchWarningBody").innerHTML = trfBold("competitor.join.switch_warning_msg", {
    current_competition: state.activeCompetition?.name || "-",
    next_competition: nextCompetition?.competition_name || "-",
  });
  setMsg("joinSwitchWarningMsg", "", true);
  el("joinSwitchWarningBackdrop").style.display = "flex";
}

async function resolveJoinCodePreview(joinCode) {
  return apiGet(`/api/competitor/join-code-preview?code=${encodeURIComponent(joinCode)}`);
}

async function handleJoinCodeFromUrl(joinCode, hasActive) {
  const previewRes = await resolveJoinCodePreview(joinCode);
  if (!previewRes.ok || !previewRes.data) {
    if (hasActive) {
      setMsg("answerMsg", previewRes.userMessage || tr("competitor.msg.qr_code_not_valid"), false);
      clearJoinCodeFromUrl();
      return;
    }
    openJoinModal(joinCode, { showClose: false, hasActive: false, codeReadonly: false });
    setMsg("joinMsg", previewRes.userMessage || tr("competitor.msg.qr_code_not_valid"), false);
    return;
  }
  if (hasActive && Number(state.selectedCompetitionId || 0) === Number(previewRes.data.competition_id || 0)) {
    clearJoinCodeFromUrl();
    return;
  }
  if (hasActive) {
    openJoinSwitchWarning({
      code: joinCode,
      competition_id: Number(previewRes.data.competition_id || 0),
      competition_name: String(previewRes.data.competition_name || "").trim() || "-",
    });
    return;
  }
  openJoinModal(joinCode, { showClose: false, hasActive: false, codeReadonly: true });
}

function updateJoinContinueEnabled() {
  const code = (el("joinCode").value || "").trim();
  const alias = (el("joinAlias").value || "").trim();
  el("joinBtn").disabled = !(code && alias);
}

function openJoinModal(prefillCode = null, opts = {}) {
  const showClose = opts.showClose === true;
  const codeReadonly = opts.codeReadonly === true;
  joinHasActiveBeforeOpen = opts.hasActive === true;
  closeJoinCaptchaModal();
  setMsg("joinMsg", "", true);
  setMsg("joinTermsMsg", "", true);
  state.joinPreview = null;
  el("joinTermsBody").innerHTML = "";
  el("joinTermsCompName").textContent = "-";
  el("joinTermsBackdrop").style.display = "none";
  el("joinCloseWrap").style.display = showClose ? "block" : "none";
  el("joinIntroCta").style.display = showClose ? "none" : "block";
  el("joinCode").value = prefillCode || "";
  setJoinCodeReadonly(codeReadonly);
  updateJoinContinueEnabled();
  competitorSessionEndedHandled = false;
  el("joinByCodeBackdrop").style.display = "flex";
}

async function bootstrapCompetitorView() {
  const ok = await ensureCompetitorSession();
  const hasActive = ok ? await loadSessionState() : false;
  const urlJoinCode = getCodeFromUrl();
  if (urlJoinCode) {
    await handleJoinCodeFromUrl(urlJoinCode, hasActive);
    if (!ok && !hasActive && !el("joinMsg").textContent) {
      setMsg("joinMsg", tr("competitor.msg.session_create_failed_retry"), false);
    }
    return;
  }
  if (!hasActive) {
    openJoinModal(null, { showClose: false, hasActive: false, codeReadonly: false });
    if (!ok) setMsg("joinMsg", tr("competitor.msg.session_create_failed_retry"), false);
  }
}

function introLangCandidates() {
  const selected = (
    el("joinLangSelect")?.value ||
    el("langSelect")?.value ||
    ""
  ).trim().toLowerCase();
  const htmlLang = (document.documentElement.lang || "").trim().toLowerCase();
  const unique = [];
  const defaults = [
    selected,
    htmlLang,
    String(i18nMeta.default_lang || "et").toLowerCase(),
    ...((i18nMeta.available_langs || []).map((x) => String(x).toLowerCase())),
  ];
  defaults.forEach((x) => {
    if (x && !unique.includes(x)) unique.push(x);
  });
  return unique;
}

async function loadContentHtml(prefix, targetId) {
  const target = el(targetId);
  target.innerHTML = "";
  const langs = introLangCandidates();
  const preferred = langs[0] || (i18nMeta.default_lang || "et");
  const res = await apiGet(`/api/content/${encodeURIComponent(prefix)}?lang=${encodeURIComponent(preferred)}`);
  if (!res.ok) return;
  const html = String(res.data?.html || "").trim();
  if (!html) return;
  target.innerHTML = html;
}

async function openIntroModal() {
  if (introLoading) return;
  introLoading = true;
  try {
    await loadContentHtml("intro", "introBody");
    el("introBackdrop").style.display = "flex";
  } finally {
    introLoading = false;
  }
}

async function openHelpModal() {
  if (helpLoading) return;
  helpLoading = true;
  try {
    await loadContentHtml("help", "helpBody");
    if (!String(el("helpBody").innerHTML || "").trim()) {
      el("helpBody").innerHTML = `<p>${esc(tr("competitor.msg.help_load_failed"))}</p>`;
    }
    el("helpBackdrop").style.display = "flex";
  } finally {
    helpLoading = false;
  }
}

async function openCompetitionTermsModal() {
  const cid = Number(state.selectedCompetitionId || state.activeCompetition?.competition_id || 0);
  if (!cid) {
    setMsg("answerMsg", tr("competitor.msg.terms_unavailable"), false);
    return;
  }
  el("competitionTermsBody").innerHTML = `<p>${tr("competitor.msg.loading_terms")}</p>`;
  el("competitionTermsBackdrop").style.display = "flex";
  const lang = (el("langSelect")?.value || "et").trim().toLowerCase();
  const cacheKey = `${cid}|${lang}`;
  const res = await apiGet(`/api/competitor/terms?competition_id=${cid}&lang_code=${encodeURIComponent(lang)}`);
  if (!res.ok) {
    el("competitionTermsBody").innerHTML = `<p>${tr("competitor.msg.terms_load_failed")}</p>`;
    setMsg("answerMsg", res.userMessage || tr("competitor.msg.terms_load_failed"), false);
    return;
  }
  competitionTermsCache[cacheKey] = String(res.data?.terms?.terms_text || "");
  const html = String(competitionTermsCache[cacheKey] || "").trim();
  el("competitionTermsBody").innerHTML = sanitizeTermsHtml(html || `<p>${tr("competitor.msg.terms_missing")}</p>`);
}

async function init() {
  await globalThis.funoApp?.initialize?.();
  await loadI18nMeta();
  await loadJoinCaptchaConfig();
  await loadCompetitorMobileAppConfig();
  renderLangOptions();
  const savedLang = (getCookie("funo_competitor_ui_lang") || "").trim().toLowerCase();
  const initialLang = (savedLang && i18nMeta.available_langs.includes(savedLang))
    ? savedLang
    : (i18nMeta.default_lang || "et");
  await setLanguage(initialLang);

  el("switchCompetitionBtn").addEventListener("click", () => {
    renderCompetitionPicker();
    el("competitionPickerBackdrop").style.display = "flex";
  });
  el("closeCompetitionPickerBtn").addEventListener("click", () => {
    el("competitionPickerBackdrop").style.display = "none";
  });
  el("openJoinByCodeBtn").addEventListener("click", () => {
    el("competitionPickerBackdrop").style.display = "none";
    openJoinModal(null, { showClose: true, hasActive: true, codeReadonly: false });
  });
  el("closeJoinByCodeBtn").addEventListener("click", () => {
    el("joinByCodeBackdrop").style.display = "none";
    closeJoinCaptchaModal();
    if (joinCodeReadonly) clearJoinCodeFromUrl();
  });
  el("competitorAppPromptOpenBtn").addEventListener("click", () => {
    const openUrl = String(competitorMobileAppConfig.androidOpenUrl || "funo://open").trim() || "funo://open";
    globalThis.location.href = openUrl;
  });
  el("competitorAppPromptBrowserBtn").addEventListener("click", () => {
    dismissCompetitorAppPrompt();
  });
  el("competitorAppPromptDownloadBtn").addEventListener("click", () => {
    const downloadUrl = String(competitorMobileAppConfig.androidDownloadUrl || "").trim();
    if (!downloadUrl) return;
    globalThis.location.href = downloadUrl;
  });
  el("competitorAppPromptBackdrop").addEventListener("click", (e) => {
    if (e.target === el("competitorAppPromptBackdrop")) dismissCompetitorAppPrompt();
  });
  el("joinSwitchWarningContinueBtn").addEventListener("click", () => {
    if (!pendingJoinSwitch?.code) {
      closeJoinSwitchWarning();
      return;
    }
    const nextCode = String(pendingJoinSwitch.code);
    closeJoinSwitchWarning();
    openJoinModal(nextCode, { showClose: true, hasActive: true, codeReadonly: true });
  });
  el("joinSwitchWarningCancelBtn").addEventListener("click", () => {
    closeJoinSwitchWarning();
    clearJoinCodeFromUrl();
  });
  el("joinSwitchWarningBackdrop").addEventListener("click", (e) => {
    if (e.target === el("joinSwitchWarningBackdrop")) {
      closeJoinSwitchWarning();
      clearJoinCodeFromUrl();
    }
  });
  el("openIntroLink").addEventListener("click", (e) => {
    e.preventDefault();
    openIntroModal().catch(() => {});
  });
  el("openIntroLinkFooter").addEventListener("click", (e) => {
    e.preventDefault();
    openIntroModal().catch(() => {});
  });
  el("closeCompetitionTermsBtn").addEventListener("click", () => {
    el("competitionTermsBackdrop").style.display = "none";
  });
  el("joinCaptchaCloseBtn").addEventListener("click", () => {
    closeJoinCaptchaModal();
  });
  el("joinCaptchaBackdrop").addEventListener("click", (e) => {
    if (e.target === el("joinCaptchaBackdrop")) closeJoinCaptchaModal();
  });
  el("competitionTermsBackdrop").addEventListener("click", (e) => {
    if (e.target === el("competitionTermsBackdrop")) el("competitionTermsBackdrop").style.display = "none";
  });
  el("closeIntroBtn").addEventListener("click", () => {
    el("introBackdrop").style.display = "none";
  });
  el("introBackdrop").addEventListener("click", (e) => {
    if (e.target === el("introBackdrop")) el("introBackdrop").style.display = "none";
  });
  el("closeHelpBtn").addEventListener("click", () => {
    el("helpBackdrop").style.display = "none";
  });
  el("helpBackdrop").addEventListener("click", (e) => {
    if (e.target === el("helpBackdrop")) el("helpBackdrop").style.display = "none";
  });
  el("mapBtn").addEventListener("click", openCompMapModal);
  el("compMapCloseBtn").addEventListener("click", closeCompMapModal);
  el("compMapHelpBtn").addEventListener("click", () => {
    openHelpModal();
  });
  el("compMapInfoBtn").addEventListener("click", () => {
    if (anyMapPopupOpen()) {
      setMapInfoVisibility(false);
      return;
    }
    showCompetitorBusy("competitor.map.info_loading_msg");
    requestAnimationFrame(() => {
      try {
        setMapInfoVisibility(true);
      } finally {
        hideCompetitorBusy();
      }
    });
  });
  el("compMapCanvas").addEventListener("click", (e) => {
    const btn = e.target.closest(".cpPopupAnswerBtn");
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();
    const checkpointId = Number(btn.getAttribute("data-checkpoint-id") || 0);
    const ringEntry = mapRings.find((entry) => Number(entry?.cp?.checkpoint_id || 0) === checkpointId);
    if (!ringEntry?.cp) return;
    handleMapCheckpointClick(ringEntry.cp).catch(() => {});
  });
  el("compMapLayerBtn").addEventListener("click", () => {
    renderCompMapLayerList();
    el("compMapLayerBackdrop").style.display = "flex";
  });
  el("compMapLayerCloseBtn").addEventListener("click", () => {
    el("compMapLayerBackdrop").style.display = "none";
  });
  el("compMapLayerBackdrop").addEventListener("click", (e) => {
    if (e.target === el("compMapLayerBackdrop")) el("compMapLayerBackdrop").style.display = "none";
  });
  el("compMapLayerList").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-map-layer-code]");
    if (!btn) return;
    const code = String(btn.getAttribute("data-map-layer-code") || "").toLowerCase();
    if (!code || code === activeMapLayerCode) return;
    if (applyBaseLayer(code)) {
      renderCompMap(state.mapItems || [], { preserveViewport: true });
      saveCompMapView();
    }
    el("compMapLayerBackdrop").style.display = "none";
  });
  el("compMapFollowBtn").addEventListener("click", () => {
    mapFollowUser = !mapFollowUser;
    updateFollowButton();
    if (mapFollowUser && state.geo.enabled && state.geo.latitude != null && state.geo.longitude != null && compMap) {
      mapProgrammaticMove = true;
      compMap.panTo([state.geo.latitude, state.geo.longitude], { animate: true });
      setTimeout(() => { mapProgrammaticMove = false; }, 250);
    }
  });
  el("compMapHeadingBtn").addEventListener("click", async () => {
    if (!canUseHeadingMode()) return;
    if (!mapHeadingMode) {
      const ok = await ensureHeadingPermission();
      if (!ok) return;
      setHeadingMode(true);
      return;
    }
    setHeadingMode(false);
  });
  el("showKpBtn").addEventListener("click", async () => {
    const selectedCompetition = getSelectedCompetition();
    const useLocation = String(selectedCompetition?.use_location || "N").toUpperCase() === "Y";
    if (useLocation) {
      await requestGeolocation();
      if (state.geo.error) setMsg("answerMsg", state.geo.error, false);
    } else {
      state.geo.enabled = false;
      state.geo.latitude = null;
      state.geo.longitude = null;
      state.geo.radius_m = null;
      state.geo.error = null;
      setMsg("answerMsg", "", true);
    }
    if (state.selectedCompetitionId) await loadOpenCheckpoints();
  });
  el("myResultsBtn").addEventListener("click", async () => {
    await loadMyResults();
  });
  el("myResultsCloseBtn").addEventListener("click", () => {
    setMyResultsOpen(false);
  });
  el("mrSortTitle").addEventListener("click", () => setMySort("checkpoint_title"));
  el("mrSortTime").addEventListener("click", () => setMySort("submitted_at"));
  el("myResultsRows").addEventListener("click", (e) => {
    const btn = e.target.closest(".kpLink");
    if (!btn) return;
    const sid = Number(btn.getAttribute("data-sub-id") || 0);
    openMyAnswerDetail(sid).catch(() => {});
  });
  el("myAnswerDetailCloseBtn").addEventListener("click", () => {
    el("myAnswerDetailBackdrop").style.display = "none";
  });
  el("myAnswerDetailBackdrop").addEventListener("click", (e) => {
    if (e.target === el("myAnswerDetailBackdrop")) el("myAnswerDetailBackdrop").style.display = "none";
  });
  el("joinBtn").addEventListener("click", joinCompetition);
  el("joinCode").addEventListener("input", updateJoinContinueEnabled);
  el("joinAlias").addEventListener("input", updateJoinContinueEnabled);
  el("confirmJoinBtn").addEventListener("click", confirmJoinCompetition);
  el("backFromTermsBtn").addEventListener("click", backFromTerms);
  el("checkpointSelect").addEventListener("change", renderQuestionForSelectedCheckpoint);
  el("textSubmitBtn").addEventListener("click", () => {
    const item = getSelectedOpenItem();
    if (!item) return;
    const answer = el("textAnswer").value;
    const errorText = validateQuestionTextAnswer(item, answer);
    if (errorText) {
      setMsg("answerMsg", errorText, false);
      return;
    }
    submitAnswer(item, { answer_text: (answer || "").trim() });
  });
  el("mapQuestionSubmitBtn").addEventListener("click", () => {
    const item = state.mapQuestionItem;
    if (!item) return;
    const answer = el("mapQuestionTextAnswer").value;
    const errorText = validateQuestionTextAnswer(item, answer);
    if (errorText) {
      setMsg("mapQuestionMsg", errorText, false);
      return;
    }
    submitAnswer(item, { answer_text: (answer || "").trim() }, {
      messageTargetId: "mapQuestionMsg",
      beforeFeedback: () => closeMapQuestionModal(),
    });
  });
  el("mapQuestionCloseBtn").addEventListener("click", () => {
    if (!state.submissionInFlight) closeMapQuestionModal();
  });
  el("mapQuestionBackdrop").addEventListener("click", (e) => {
    if (e.target === el("mapQuestionBackdrop")) e.stopPropagation();
  });
  el("feedbackCloseBtn").addEventListener("click", closeFeedback);
  el("langSelect").addEventListener("change", async (e) => {
    await refreshQuestionsOnLanguageChange(e.target.value);
    renderProgressBox();
  });
  el("joinLangSelect").addEventListener("change", async (e) => {
    await refreshQuestionsOnLanguageChange(e.target.value);
    renderProgressBox();
  });

  await bootstrapCompetitorView().catch(() => {
    openJoinModal(getCodeFromUrl());
    setMsg("joinMsg", tr("competitor.msg.bootstrap_failed"), false);
  });
  maybeShowCompetitorAppPrompt();
}

init().catch(() => {
  try {
    openJoinModal(null, { showClose: false, hasActive: false, codeReadonly: false });
  } catch {}
  setMsg("joinMsg", "competitor.msg.bootstrap_failed", false);
});
