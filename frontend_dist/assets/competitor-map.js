function getMapViewCookieKey() {
  const cid = Number(state.selectedCompetitionId || 0);
  const crsSuffix = String(compMapCurrentCrs || "EPSG:3857").toLowerCase().replace(/[^a-z0-9]+/g, "_");
  return cid > 0 ? `funo_comp_map_view_c${cid}_${crsSuffix}` : `funo_comp_map_view_${crsSuffix}`;
}

function getMapLayerCookieKey() {
  const cid = Number(state.selectedCompetitionId || 0);
  return cid > 0 ? `funo_comp_map_layer_c${cid}` : "funo_comp_map_layer";
}

function getMapHeadingCookieKey() {
  const cid = Number(state.selectedCompetitionId || 0);
  return cid > 0 ? `funo_comp_map_heading_c${cid}` : "funo_comp_map_heading";
}

function getMapHeadingBiasStorageKey() {
  const cid = Number(state.selectedCompetitionId || 0);
  return cid > 0 ? `funo_comp_map_heading_bias_c${cid}` : "funo_comp_map_heading_bias";
}

function loadHeadingBiasFromStorage() {
  try {
    const raw = localStorage.getItem(getMapHeadingBiasStorageKey());
    if (!raw) return;
    const parsed = JSON.parse(raw);
    const bias = Number(parsed?.bias_deg);
    const confidence = Number(parsed?.confidence);
    if (Number.isFinite(bias)) {
      mapHeadingBiasDeg = Math.max(-HEADING_BIAS_MAX_DEG, Math.min(HEADING_BIAS_MAX_DEG, bias));
    }
    if (Number.isFinite(confidence)) {
      mapHeadingBiasConfidence = Math.max(0, Math.min(1, confidence));
    }
  } catch {}
}

function saveHeadingBiasToStorage() {
  try {
    const payload = {
      bias_deg: Number(mapHeadingBiasDeg || 0),
      confidence: Number(mapHeadingBiasConfidence || 0),
      updated_at: Date.now(),
    };
    localStorage.setItem(getMapHeadingBiasStorageKey(), JSON.stringify(payload));
  } catch {}
}

function saveCompMapView() {
  if (!compMap || !mapViewPersistenceEnabled) return;
  const c = compMap.getCenter();
  const z = compMap.getZoom();
  setCookie(getMapViewCookieKey(), `${c.lat.toFixed(7)},${c.lng.toFixed(7)},${z}`, 30);
}

function restoreCompMapView() {
  const key = getMapViewCookieKey();
  const raw = getCookie(key);
  const legacyCid = Number(state.selectedCompetitionId || 0);
  const legacyKey = legacyCid > 0 ? `funo_comp_map_view_c${legacyCid}` : "funo_comp_map_view";
  const effectiveRaw = raw || getCookie(legacyKey);
  if (!effectiveRaw) return false;
  const parts = effectiveRaw.split(",");
  if (parts.length !== 3) return false;
  const lat = Number(parts[0]);
  const lng = Number(parts[1]);
  const zoom = Number(parts[2]);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !Number.isFinite(zoom)) return false;
  compMap.setView([lat, lng], zoom);
  return true;
}

async function loadAllowedMapLayers() {
  const cid = Number(state.selectedCompetitionId || 0);
  if (!cid) return [];
  const res = await apiGet(`/api/competitor/map-layers?competition_id=${cid}`);
  if (!res.ok) return [];
  const items = Array.isArray(res.data?.items) ? res.data.items : [];
  return items;
}

function createBaseLayer(layer) {
  const url = String(layer.url_template || "");
  const attrib = String(layer.attribution || "");
  const minZoom = Number(layer.min_zoom ?? 0);
  const maxZoom = Number(layer.max_zoom ?? 19);
  const tms = String(layer.tms || "false").toLowerCase() === "true" || layer.tms === true;
  const layerType = String(layer.layer_type || "xyz").toLowerCase();
  if (layerType === "wms") {
    return L.tileLayer.wms(url, {
      layers: String(layer.wms_layers || ""),
      format: String(layer.wms_format || "image/png"),
      transparent: layer.wms_transparent === true,
      version: String(layer.wms_version || "1.1.1"),
      attribution: attrib,
      minZoom,
      maxZoom,
      tms,
    });
  }
  return L.tileLayer(url, { attribution: attrib, minZoom, maxZoom, tms });
}

function requiresLestCrs(layer) {
  return String(layer?.crs || "").toUpperCase() === "EPSG:3301";
}

function createCompMap(targetCrs) {
  let previousView = null;
  if (compMap) {
    const c = compMap.getCenter();
    const z = compMap.getZoom();
    if (Number.isFinite(Number(c?.lat)) && Number.isFinite(Number(c?.lng)) && Number.isFinite(Number(z))) {
      previousView = { lat: Number(c.lat), lon: Number(c.lng), zoom: Number(z) };
    }
    compMap.remove();
    compMap = null;
    compMapLayer = null;
    baseMapLayer = null;
    mapRings = [];
    userPosMarker = null;
  }
  const options = {
    zoomControl: true,
    dragging: true,
    scrollWheelZoom: true,
    rotate: true,
    bearing: 0,
  };
  if (targetCrs === "EPSG:3301" && window.L?.Proj?.CRS) {
    options.crs = new L.Proj.CRS(
      "EPSG:3301",
      "+proj=lcc +lat_1=59.33333333333334 +lat_2=58 +lat_0=57.51755393055556 +lon_0=24 +x_0=500000 +y_0=6375000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs",
      {
        origin: [40500, 7017000],
        resolutions: [
          4000, 2000, 1000, 500, 250, 125, 62.5, 31.25,
          15.625, 7.8125, 3.90625, 1.953125, 0.9765625, 0.48828125, 0.244140625
        ],
        bounds: L.bounds([40500, 5993000], [1064500, 7017000])
      }
    );
  }
  compMap = L.map("compMapCanvas", options);
  if (compMap?.rotateControl && typeof compMap.rotateControl.remove === "function") {
    compMap.rotateControl.remove();
  }
  compMapLayer = L.layerGroup().addTo(compMap);
  compMap.on("moveend zoomend", () => saveCompMapView());
  compMap.on("movestart", () => {
    if (!mapProgrammaticMove) {
      mapFollowUser = false;
      updateFollowButton();
    }
  });
  compMapCurrentCrs = targetCrs;
  return previousView;
}

function renderCompMapLayerList() {
  const list = el("compMapLayerList");
  if (!list) return;
  if (!allowedMapLayers.length) {
    list.innerHTML = `<div class="msg err">${tr("competitor.map.layer_list_empty_msg")}</div>`;
    return;
  }
  list.innerHTML = allowedMapLayers.map((layer) => {
    const code = String(layer.code || "").toLowerCase();
    const active = code === activeMapLayerCode ? " active" : "";
    return `<button class="mapLayerItem${active}" data-map-layer-code="${esc(code)}">${esc(layer.label || code)}</button>`;
  }).join("");
}

function applyBaseLayer(code) {
  if (!compMap) return false;
  const low = String(code || "").toLowerCase();
  const layer = mapLayersByCode[low];
  if (!layer) return false;
  const targetCrs = requiresLestCrs(layer) ? "EPSG:3301" : "EPSG:3857";
  let previousView = null;
  if (compMapCurrentCrs !== targetCrs) {
    previousView = createCompMap(targetCrs);
  }
  if (baseMapLayer) {
    compMap.removeLayer(baseMapLayer);
    baseMapLayer = null;
  }
  baseMapLayer = createBaseLayer(layer);
  baseMapLayer.addTo(compMap);
  activeMapLayerCode = low;
  setCookie(getMapLayerCookieKey(), activeMapLayerCode, 30);
  if (previousView) {
    mapProgrammaticMove = true;
    const restored = restoreCompMapView();
    if (!restored) {
      compMap.setView([previousView.lat, previousView.lon], previousView.zoom, { animate: false });
      saveCompMapView();
    }
    setTimeout(() => { mapProgrammaticMove = false; }, 250);
  }
  renderCompMapLayerList();
  return true;
}

function ensureCompMapInit() {
  if (compMap) return;
  createCompMap("EPSG:3857");
  mapProgrammaticMove = true;
  compMap.setView([58.8, 25.4], 8);
  setTimeout(() => { mapProgrammaticMove = false; }, 250);
}

function updateFollowButton() {
  const btn = el("compMapFollowBtn");
  if (!btn) return;
  if (!selectedCompetitionShowsUserLocation()) {
    btn.style.display = "none";
    return;
  }
  btn.style.display = "inline-block";
  btn.textContent = mapFollowUser ? tr("competitor.map.follow_on_btn") : tr("competitor.map.follow_off_btn");
}

let mapGpsSignalLost = false;

function updateMapGpsStatus() {
  const box = el("compMapGpsStatus");
  if (!box) return;
  const mapOpen = el("compMapBackdrop")?.style?.display === "block";
  const show = mapOpen && mapGpsSignalLost;
  box.style.display = show ? "block" : "none";
  box.textContent = show ? tr("competitor.map.gps_signal_lost") : "";
}

function applyUserMarkerVisualState() {
  if (!userPosMarker) return;
  userPosMarker.setStyle({
    color: mapGpsSignalLost ? "#dfe6ea" : "#ffffff",
    weight: 2,
    fillColor: mapGpsSignalLost ? "#8a959c" : "#2f8cff",
    fillOpacity: 1,
  });
}

function syncMapGpsSignalState(hasSignal) {
  mapGpsSignalLost = !hasSignal;
  applyUserMarkerVisualState();
  updateMapGpsStatus();
}

function applyGpsSignalLossState() {
  state.geo.error = tr("competitor.map.gps_signal_lost");
  mapDebugGpsHeading = null;
  mapDebugGpsSpeed = null;
  mapHeadingGpsRaw = null;
  refreshHeadingOutput("gps");
  const hasLastKnownGeo = state.geo.latitude != null && state.geo.longitude != null;
  if (!hasLastKnownGeo) {
    state.geo.enabled = false;
    state.geo.radius_m = null;
  }
  syncMapGpsSignalState(false);
}

function canUseHeadingMode() {
  return selectedCompetitionShowsUserLocation();
}

function formatHeadingDebugNum(value) {
  return Number.isFinite(Number(value)) ? Number(value).toFixed(1) : "-";
}

function formatHeadingDebugState() {
  if (mapHeadingState === "GPS_PRIMARY") return "GPS";
  if (mapHeadingState === "BLEND") return "BLEND";
  return "COMP";
}

function updateHeadingDebugBox() {
  const box = el("compMapHeadingDebug");
  if (!box) return;
  const show = mapHeadingMode;
  box.style.display = show ? "block" : "none";
  if (!show) return;
  box.textContent =
    `${formatHeadingDebugState()}  bias=${formatHeadingDebugNum(mapHeadingBiasDeg)}  decl=${formatHeadingDebugNum(state.mapDeclination)}`;
}

function resetMapHeadingRotation() {
  if (!compMap) return;
  if (typeof compMap.setBearing === "function") {
    compMap.setBearing(0);
    return;
  }
  const pane = compMap.getPane && compMap.getPane("mapPane");
  if (!pane) return;
  pane.style.transformOrigin = "";
  pane.style.transform = String(pane.style.transform || "").replace(/\s*rotate\([^)]*\)\s*/g, " ").trim();
}

function applyMapHeading(headingDeg) {
  if (!compMap) return;
  const adjustedHeading = normalizeDegrees(Number(headingDeg) + MAP_HEADING_OFFSET_DEG);
  const bearing = ((-adjustedHeading % 360) + 360) % 360;
  if (typeof compMap.setBearing === "function") {
    compMap.setBearing(bearing);
    return;
  }
  const pane = compMap.getPane && compMap.getPane("mapPane");
  if (!pane) return;
  const baseTransform = String(pane.style.transform || "").replace(/\s*rotate\([^)]*\)\s*/g, " ").trim();
  pane.style.transformOrigin = "50% 50%";
  pane.style.transform = `${baseTransform} rotate(${bearing}deg)`.trim();
}

function normalizeDegrees(deg) {
  const n = Number(deg);
  if (!Number.isFinite(n)) return null;
  return ((n % 360) + 360) % 360;
}

function shortestAngleDiff(fromDeg, toDeg) {
  const from = normalizeDegrees(fromDeg);
  const to = normalizeDegrees(toDeg);
  if (!Number.isFinite(from) || !Number.isFinite(to)) return 0;
  let diff = to - from;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff;
}

function normalizeHeadingEvent(evt) {
  if (evt && Number.isFinite(Number(evt.webkitCompassHeading))) {
    return (Number(evt.webkitCompassHeading) + 360) % 360;
  }
  if (evt && Number.isFinite(Number(evt.alpha))) {
    return ((360 - Number(evt.alpha)) + 360) % 360;
  }
  return null;
}

function canUseGpsHeading() {
  const speed = Number(mapDebugGpsSpeed);
  const acc = Number(state.geo.radius_m);
  return Number.isFinite(Number(mapHeadingGpsRaw))
    && Number.isFinite(speed)
    && speed >= HEADING_SPEED_LOW_MPS
    && Number.isFinite(acc)
    && acc > 0
    && acc <= HEADING_GPS_ACC_MAX_M;
}

function canUseGpsHeadingEarly() {
  const speed = Number(mapDebugGpsSpeed);
  const acc = Number(state.geo.radius_m);
  return Number.isFinite(Number(mapHeadingGpsRaw))
    && Number.isFinite(speed)
    && speed >= HEADING_SPEED_BLEND_EARLY_MPS
    && Number.isFinite(acc)
    && acc > 0
    && acc <= HEADING_GPS_ACC_MAX_M;
}

function headingBlendWeight() {
  const speed = Number(mapDebugGpsSpeed);
  if (!Number.isFinite(speed)) return 0;
  if (speed <= HEADING_SPEED_BLEND_EARLY_MPS) return 0;
  if (speed >= HEADING_SPEED_HIGH_MPS) return 1;
  return (speed - HEADING_SPEED_BLEND_EARLY_MPS) / (HEADING_SPEED_HIGH_MPS - HEADING_SPEED_BLEND_EARLY_MPS);
}

function setHeadingState(nextState) {
  mapHeadingState = nextState;
}

function updateHeadingState() {
  const speed = Number(mapDebugGpsSpeed);
  const gpsTrusted = canUseGpsHeading();
  const gpsEarly = canUseGpsHeadingEarly();
  if (!gpsTrusted) {
    mapHeadingGpsStableCount = 0;
    if (gpsEarly) {
      setHeadingState("BLEND");
      return;
    }
    setHeadingState("COMPASS_ONLY");
    return;
  }
  mapHeadingGpsStableCount = Math.min(10, mapHeadingGpsStableCount + 1);
  if (!Number.isFinite(speed)) {
    setHeadingState("COMPASS_ONLY");
    return;
  }
  if (speed >= HEADING_SPEED_HIGH_MPS && mapHeadingGpsStableCount >= 2) {
    setHeadingState("GPS_PRIMARY");
    return;
  }
  if (speed >= HEADING_SPEED_LOW_MPS) {
    setHeadingState("BLEND");
    return;
  }
  setHeadingState("COMPASS_ONLY");
}

function blendAngles(fromDeg, toDeg, weight) {
  const w = Math.min(1, Math.max(0, Number(weight) || 0));
  const diff = shortestAngleDiff(fromDeg, toDeg);
  return normalizeDegrees(Number(fromDeg) + (diff * w));
}

function getCalibratedCompass() {
  if (!Number.isFinite(Number(mapHeadingCompassRaw))) return null;
  return normalizeDegrees(Number(mapHeadingCompassRaw) + Number(mapHeadingBiasDeg || 0) + Number(state.mapDeclination || 0));
}

function updateHeadingBias() {
  if (mapHeadingState === "COMPASS_ONLY") return;
  const comp = getCalibratedCompass();
  const gps = normalizeDegrees(mapHeadingGpsRaw);
  if (!Number.isFinite(comp) || !Number.isFinite(gps) || !canUseGpsHeading()) return;
  const diff = shortestAngleDiff(comp, gps);
  const nextBias = Number(mapHeadingBiasDeg || 0) + (diff * HEADING_BIAS_ALPHA);
  mapHeadingBiasDeg = Math.max(-HEADING_BIAS_MAX_DEG, Math.min(HEADING_BIAS_MAX_DEG, nextBias));
  mapHeadingBiasConfidence = Math.min(1, Number(mapHeadingBiasConfidence || 0) + 0.05);
  saveHeadingBiasToStorage();
}

function selectTargetHeading() {
  const comp = getCalibratedCompass();
  const gps = (canUseGpsHeading() || canUseGpsHeadingEarly()) ? normalizeDegrees(mapHeadingGpsRaw) : null;
  if (mapHeadingState === "GPS_PRIMARY" && Number.isFinite(gps)) return gps;
  if (mapHeadingState === "BLEND" && Number.isFinite(comp) && Number.isFinite(gps)) {
    return blendAngles(comp, gps, headingBlendWeight());
  }
  if (Number.isFinite(comp)) return comp;
  if (Number.isFinite(gps)) return gps;
  return null;
}

function pushHeadingToMap(nextHeading, now) {
  if (!Number.isFinite(nextHeading)) return;
  mapHeadingHasSignal = true;
  mapHeadingCurrent = normalizeDegrees(nextHeading);
  const compassOnlyUncalibrated = mapHeadingState === "COMPASS_ONLY" && Number(mapHeadingBiasConfidence || 0) < 0.5;
  const smoothingAlpha = compassOnlyUncalibrated ? 0.025 : 0.04;
  const deadzoneDeg = compassOnlyUncalibrated ? 11 : 8;
  const minIntervalMs = compassOnlyUncalibrated ? 900 : 760;
  if (mapHeadingSmoothed == null) {
    mapHeadingSmoothed = mapHeadingCurrent;
  } else {
    const diff = shortestAngleDiff(mapHeadingSmoothed, mapHeadingCurrent);
    mapHeadingSmoothed = normalizeDegrees(mapHeadingSmoothed + (diff * smoothingAlpha));
  }
  if (mapHeadingLastApplied != null) {
    const delta = Math.abs(shortestAngleDiff(mapHeadingLastApplied, mapHeadingSmoothed));
    if (delta < deadzoneDeg && now - mapHeadingLastAppliedAt < minIntervalMs) return;
  } else if (now - mapHeadingLastAppliedAt < minIntervalMs) {
    return;
  }
  mapHeadingLastApplied = mapHeadingSmoothed;
  mapHeadingLastAppliedAt = now;
  applyMapHeading(mapHeadingSmoothed);
}

function refreshHeadingOutput(sourceTag) {
  if (!mapHeadingMode) return;
  updateHeadingState();
  updateHeadingBias();
  const target = selectTargetHeading();
  if (Number.isFinite(target)) {
    pushHeadingToMap(target, Date.now());
  } else {
    mapHeadingHasSignal = false;
  }
  if (sourceTag === "compass") mapHeadingCompassSeenAt = Date.now();
  updateHeadingButton();
  updateHeadingDebugBox();
}

function onDeviceOrientation(evt) {
  if (!mapHeadingMode) return;
  mapDebugRawAlpha = Number.isFinite(Number(evt?.alpha)) ? Number(evt.alpha) : null;
  mapDebugRawCompass = Number.isFinite(Number(evt?.webkitCompassHeading)) ? Number(evt.webkitCompassHeading) : null;
  const heading = normalizeHeadingEvent(evt);
  mapHeadingCompassRaw = Number.isFinite(heading) ? normalizeDegrees(heading) : null;
  refreshHeadingOutput("compass");
}

let mapHeadingEventName = null;

function attachHeadingListener() {
  if (mapHeadingListenerAttached) return;
  if (typeof window.DeviceOrientationEvent === "undefined") return;
  mapHeadingEventName = "ondeviceorientationabsolute" in window
    ? "deviceorientationabsolute"
    : "deviceorientation";
  window.addEventListener(mapHeadingEventName, onDeviceOrientation, true);
  mapHeadingListenerAttached = true;
}

function detachHeadingListener() {
  if (!mapHeadingListenerAttached) return;
  if (mapHeadingEventName) {
    window.removeEventListener(mapHeadingEventName, onDeviceOrientation, true);
  }
  mapHeadingEventName = null;
  mapHeadingListenerAttached = false;
}

function updateHeadingButton() {
  const btn = el("compMapHeadingBtn");
  if (!btn) return;
  const visible = canUseHeadingMode();
  btn.style.display = visible ? "inline-flex" : "none";
  btn.classList.toggle("is-on", mapHeadingMode && visible);
  btn.classList.toggle("is-off", !(mapHeadingMode && visible));
  btn.classList.toggle("is-waiting", mapHeadingMode && visible && !mapHeadingHasSignal);
  updateHeadingDebugBox();
}

function setHeadingMode(enabled) {
  if (!canUseHeadingMode()) {
    mapHeadingMode = false;
    setCookie(getMapHeadingCookieKey(), "off", 30);
    detachHeadingListener();
    mapHeadingSmoothed = null;
    mapHeadingLastApplied = null;
    mapHeadingCurrent = null;
    mapHeadingHasSignal = false;
    mapHeadingCompassRaw = null;
    mapHeadingGpsRaw = null;
    mapHeadingGpsStableCount = 0;
    mapHeadingState = "COMPASS_ONLY";
    mapHeadingBiasDeg = 0;
    resetMapHeadingRotation();
    updateHeadingButton();
    return;
  }
  mapHeadingMode = !!enabled;
  setCookie(getMapHeadingCookieKey(), mapHeadingMode ? "on" : "off", 30);
  if (mapHeadingMode) {
    mapHeadingSmoothed = null;
    mapHeadingLastApplied = null;
    mapHeadingLastAppliedAt = 0;
    mapHeadingHasSignal = false;
    mapHeadingCompassRaw = null;
    mapHeadingGpsRaw = null;
    mapHeadingGpsStableCount = 0;
    mapHeadingState = "COMPASS_ONLY";
    if (Number.isFinite(mapHeadingCurrent)) {
      applyMapHeading(mapHeadingCurrent);
    }
    attachHeadingListener();
  } else {
    detachHeadingListener();
    resetMapHeadingRotation();
  }
  updateHeadingButton();
  updateHeadingDebugBox();
}

function applyHeadingFromGps(headingValue) {
  if (!mapHeadingMode) return;
  const heading = Number(headingValue);
  mapDebugGpsHeading = Number.isFinite(heading) ? heading : null;
  mapHeadingGpsRaw = Number.isFinite(heading) && heading >= 0 ? normalizeDegrees(heading) : null;
  refreshHeadingOutput("gps");
}

async function ensureHeadingPermission() {
  if (!canUseHeadingMode()) return false;
  if (!window.DeviceOrientationEvent || typeof window.DeviceOrientationEvent.requestPermission !== "function") {
    return true;
  }
  if (mapHeadingPermissionAsked) return true;
  mapHeadingPermissionAsked = true;
  try {
    const permission = await window.DeviceOrientationEvent.requestPermission();
    return permission === "granted";
  } catch {
    return false;
  }
}

function anyMapPopupOpen() {
  return mapRings.some((entry) => !!entry.ring?.getPopup()?.isOpen());
}

function setMapInfoVisibility(show) {
  mapInfoVisible = !!show;
  if (mapInfoVisible) {
    mapRings.forEach((entry) => entry.ring?.openPopup());
  } else {
    mapRings.forEach((entry) => entry.ring?.closePopup());
  }
}

function checkpointPopupLabel(cp) {
  const points = Number(cp?.points || 0);
  const base = `${cp?.checkpoint_title || tr("competitor.common.checkpoint_short")} (${points} ${tr("competitor.common.points_short")})`;
  return String(cp?.is_answered || "N").toUpperCase() === "Y"
    ? `${base} ${tr("competitor.map.checkpoint_passed_suffix")}`
    : base;
}

function getOpenItemByCheckpointId(checkpointId) {
  const cpId = Number(checkpointId || 0);
  if (!cpId) return null;
  return state.openItems.find((x) => Number(x?.checkpoint_id || 0) === cpId) || null;
}

function openQuestionFromCheckpointId(checkpointId) {
  const item = getOpenItemByCheckpointId(checkpointId);
  if (!item) return false;
  const select = el("checkpointSelect");
  if (!select || select.disabled) return false;
  select.value = String(checkpointId);
  renderQuestionForSelectedCheckpoint();
  return true;
}

async function checkCheckpointAccess(checkpointIds) {
  if (!state.selectedCompetitionId) return [];
  const ids = (checkpointIds || []).map((x) => Number(x || 0)).filter((x) => x > 0);
  if (!ids.length) return [];
  const payload = {
    competition_id: state.selectedCompetitionId,
    checkpoint_ids: ids,
    latitude: state.geo.enabled ? state.geo.latitude : null,
    longitude: state.geo.enabled ? state.geo.longitude : null,
    radius_m: state.geo.enabled ? state.geo.radius_m : null,
  };
  const res = await apiPost("/api/competitor/checkpoint-access", payload);
  if (!res.ok) return [];
  return Array.isArray(res.data?.items) ? res.data.items : [];
}

async function handleMapCheckpointClick(cp) {
  const cpId = Number(cp?.checkpoint_id || 0);
  if (!cpId || state.feedbackOpen) return;
  const requiresLocation = String(cp?.location_required || "N").toUpperCase() === "Y";
  if (requiresLocation) {
    await requestGeolocation({ maximumAge: 10000, timeout: 5000, enableHighAccuracy: true });
    if (!state.geo.enabled) {
      if (state.geo.error) setMsg("answerMsg", state.geo.error, false);
      return;
    }
  }
  const accessItems = await checkCheckpointAccess([cpId]);
  const access = accessItems.find((x) => Number(x?.checkpoint_id || 0) === cpId) || null;
  if (!access || access.can_open !== true) {
    if (String(access?.reason || "") === "answered") {
      cp.is_answered = "Y";
    }
    return;
  }
  await loadOpenCheckpoints({ force: true, preferredCheckpointId: cpId });
  if (openQuestionFromCheckpointId(cpId)) {
    closeCompMapModal();
  }
}

async function handleMapInfoAccessCheck() {
  const candidates = mapRings
    .map((entry) => entry?.cp)
    .filter((cp) => cp && String(cp.location_required || "N").toUpperCase() === "Y" && String(cp.is_answered || "N").toUpperCase() !== "Y")
    .map((cp) => Number(cp.checkpoint_id || 0))
    .filter((x) => x > 0);
  if (!candidates.length) return;
  await requestGeolocation({ maximumAge: 10000, timeout: 5000, enableHighAccuracy: true });
  if (!state.geo.enabled) return;
  const accessItems = await checkCheckpointAccess(candidates);
  let preferredCheckpointId = 0;
  accessItems.forEach((entry) => {
    const cpId = Number(entry?.checkpoint_id || 0);
    if (!cpId) return;
    const ringEntry = mapRings.find((x) => Number(x?.cp?.checkpoint_id || 0) === cpId);
    if (!ringEntry || !ringEntry.cp) return;
    if (String(entry.reason || "") === "answered") {
      ringEntry.cp.is_answered = "Y";
      ringEntry.ring?.setPopupContent(checkpointPopupLabel(ringEntry.cp));
    }
    if (!preferredCheckpointId && entry.can_open === true) {
      preferredCheckpointId = cpId;
    }
  });
  if (!preferredCheckpointId) return;
  await loadOpenCheckpoints({ force: true, preferredCheckpointId });
  if (openQuestionFromCheckpointId(preferredCheckpointId)) {
    closeCompMapModal();
  }
}

function renderCompMap(items, opts = {}) {
  const forceInitialFit = opts && opts.forceInitialFit === true;
  const preserveViewport = opts && opts.preserveViewport === true;
  ensureCompMapInit();
  compMapLayer.clearLayers();
  mapRings = [];
  if (userPosMarker) {
    compMap.removeLayer(userPosMarker);
    userPosMarker = null;
  }
  const checkpointBounds = [];
  items.forEach((cp) => {
    const lat = Number(cp.latitude);
    const lon = Number(cp.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;
    const req = String(cp.location_required || "N").toUpperCase() === "Y";
    const stroke = req ? "#d02d2d" : "#7a43c6";
    const ring = L.circleMarker([lat, lon], {
      radius: 15,
      color: stroke,
      weight: 3,
      fillOpacity: 0,
    }).addTo(compMapLayer);
    const popupText = checkpointPopupLabel(cp);
    ring.bindPopup(popupText, { autoClose: false, closeOnClick: false, autoPan: false });
    ring.on("click", () => {
      handleMapCheckpointClick(cp).catch(() => {});
    });
    mapRings.push({ ring, cp });
    checkpointBounds.push([lat, lon]);
  });
  const hasUserGeo = selectedCompetitionShowsUserLocation() && state.geo.enabled && state.geo.latitude != null && state.geo.longitude != null;
  if (hasUserGeo) {
    userPosMarker = L.circleMarker([state.geo.latitude, state.geo.longitude], {
      radius: 7,
      color: "#ffffff",
      weight: 2,
      fillColor: "#2f8cff",
      fillOpacity: 1,
    }).addTo(compMap);
    userPosMarker.bindPopup(tr("competitor.map.user_location_popup"));
    applyUserMarkerVisualState();
  }
  updateMapGpsStatus();
  mapProgrammaticMove = true;
  if (!preserveViewport) {
    const restored = forceInitialFit ? false : restoreCompMapView();
    if (mapFollowUser && hasUserGeo) {
      if (restored) {
        compMap.panTo([state.geo.latitude, state.geo.longitude], { animate: false });
      } else {
        compMap.setView([state.geo.latitude, state.geo.longitude], 15, { animate: false });
      }
    } else if (checkpointBounds.length) {
      if (!restored || forceInitialFit) {
        compMap.fitBounds(checkpointBounds, { padding: [24, 24], maxZoom: 18 });
        const openedZoom = Number(compMap.getZoom() || 0);
        const minOpenZoom = 10;
        if (openedZoom > 0 && openedZoom < minOpenZoom) {
          compMap.setZoom(minOpenZoom);
        }
      }
    } else if (hasUserGeo) {
      compMap.setView([state.geo.latitude, state.geo.longitude], 15, { animate: false });
    } else if (!restored) {
      compMap.setView([58.8, 25.4], 8, { animate: false });
    }
  }
  setMapInfoVisibility(mapInfoVisible);
  setTimeout(() => {
    if (!compMap) return;
    compMap.invalidateSize();
    if (mapHeadingMode && Number.isFinite(mapHeadingCurrent)) {
      applyMapHeading(mapHeadingCurrent);
    }
    setTimeout(() => { mapProgrammaticMove = false; }, 250);
  }, 80);
}

function updateUserPositionMarker(lat, lon, accuracy, gpsHeading, gpsSpeed) {
  state.geo.enabled = true;
  state.geo.latitude = Number(lat);
  state.geo.longitude = Number(lon);
  state.geo.radius_m = Number(accuracy);
  state.geo.error = null;
  mapDebugGpsSpeed = Number.isFinite(Number(gpsSpeed)) ? Number(gpsSpeed) : null;
  syncMapGpsSignalState(true);
  applyHeadingFromGps(gpsHeading);
  if (!selectedCompetitionShowsUserLocation()) return;
  if (!compMap) return;
  if (!userPosMarker) {
    userPosMarker = L.circleMarker([lat, lon], {
      radius: 7,
      color: "#ffffff",
      weight: 2,
      fillColor: "#2f8cff",
      fillOpacity: 1,
    }).addTo(compMap);
    userPosMarker.bindPopup(tr("competitor.map.user_location_popup"));
    applyUserMarkerVisualState();
  } else {
    userPosMarker.setLatLng([lat, lon]);
    applyUserMarkerVisualState();
  }
  if (mapFollowUser && compMap) {
    mapProgrammaticMove = true;
    compMap.panTo([lat, lon], { animate: true });
    setTimeout(() => { mapProgrammaticMove = false; }, 250);
  }
}

function startMapGeolocationWatch() {
  if (!navigator.geolocation) {
    applyGpsSignalLossState();
    return;
  }
  stopMapGeolocationWatch();
  geoWatchId = navigator.geolocation.watchPosition(
    (pos) => updateUserPositionMarker(pos.coords.latitude, pos.coords.longitude, pos.coords.accuracy, pos.coords.heading, pos.coords.speed),
    () => {
      applyGpsSignalLossState();
    },
    { enableHighAccuracy: true, timeout: 10000, maximumAge: 5000 }
  );
}

function stopMapGeolocationWatch() {
  if (geoWatchId != null && navigator.geolocation) {
    navigator.geolocation.clearWatch(geoWatchId);
  }
  geoWatchId = null;
}

async function openCompMapModal() {
  mapViewPersistenceEnabled = false;
  mapGpsSignalLost = false;
  mapFollowUser = true;
  mapHeadingPermissionAsked = false;
  updateFollowButton();
  updateHeadingButton();
  await requestFreshGeolocationForMapOpen();
  syncMapGpsSignalState(state.geo.error == null && state.geo.enabled);
  allowedMapLayers = await loadAllowedMapLayers();
  Object.keys(mapLayersByCode).forEach((k) => delete mapLayersByCode[k]);
  allowedMapLayers.forEach((x) => {
    const code = String(x.code || "").toLowerCase();
    if (code) mapLayersByCode[code] = x;
  });
  if (!allowedMapLayers.length) {
    setMsg("answerMsg", tr("competitor.map.layer_open_empty_msg"), false);
    return;
  }
  state.mapItems = await loadMapCheckpoints();
  el("compMapBackdrop").style.display = "block";
  await new Promise((resolve) => requestAnimationFrame(() => resolve()));
  mapProgrammaticMove = true;
  ensureCompMapInit();
  const rememberedLayerCode = String(getCookie(getMapLayerCookieKey()) || "").toLowerCase();
  if (rememberedLayerCode && mapLayersByCode[rememberedLayerCode]) {
    activeMapLayerCode = rememberedLayerCode;
  } else if (!activeMapLayerCode || !mapLayersByCode[activeMapLayerCode]) {
    const participantDefault = allowedMapLayers.find((x) => x && x.participant_default === true);
    activeMapLayerCode = String((participantDefault?.code || allowedMapLayers[0].code || "")).toLowerCase();
  }
  applyBaseLayer(activeMapLayerCode);
  const layerBtn = el("compMapLayerBtn");
  if (layerBtn) {
    layerBtn.style.display = allowedMapLayers.length > 1 ? "inline-flex" : "none";
  }
  renderCompMapLayerList();
  compMap.invalidateSize();
  renderCompMap(state.mapItems, { forceInitialFit: false });
  if (mapHeadingMode) {
    refreshHeadingOutput("compass");
  }
  compMapOpenedOnce = true;
  mapViewPersistenceEnabled = true;
  saveCompMapView();
  updateHeadingButton();
  if (canUseHeadingMode()) {
    loadHeadingBiasFromStorage();
    const rememberedHeadingMode = String(getCookie(getMapHeadingCookieKey()) || "off").toLowerCase();
    setHeadingMode(rememberedHeadingMode === "on");
  } else {
    setHeadingMode(false);
  }
  startMapGeolocationWatch();
}

function closeCompMapModal() {
  saveCompMapView();
  setHeadingMode(false);
  mapHeadingPermissionAsked = false;
  stopMapGeolocationWatch();
  syncMapGpsSignalState(true);
  el("compMapLayerBackdrop").style.display = "none";
  el("compMapBackdrop").style.display = "none";
}

async function applyCheckpointLoadingMode() {
  const needsLocation = selectedCompetitionUsesLocation();
  el("showKpBtn").style.display = needsLocation ? "inline-block" : "none";
  el("mapBtn").style.display = needsLocation ? "inline-block" : "none";
  state.openItems = [];
  state.openItemsLoaded = false;
  renderCheckpointSelect();
  if (!needsLocation) {
    state.geo.enabled = false;
    state.geo.latitude = null;
    state.geo.longitude = null;
    state.geo.radius_m = null;
    state.geo.error = null;
    setMsg("answerMsg", "", true);
    await loadOpenCheckpoints();
  }
}
