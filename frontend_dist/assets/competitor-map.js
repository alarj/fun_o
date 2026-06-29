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

function getSavedCompMapViewRaw() {
  const key = getMapViewCookieKey();
  const raw = getCookie(key);
  const legacyCid = Number(state.selectedCompetitionId || 0);
  const legacyKey = legacyCid > 0 ? `funo_comp_map_view_c${legacyCid}` : "funo_comp_map_view";
  return raw || getCookie(legacyKey) || "";
}

function hasSavedCompMapView() {
  return !!getSavedCompMapViewRaw();
}

function restoreCompMapView() {
  const effectiveRaw = getSavedCompMapViewRaw();
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

function resolveMapLayerUrl(url) {
  const raw = String(url || "").trim();
  if (!raw) return "";
  if (/^[a-z]+:\/\//i.test(raw) || raw.startsWith("//")) return raw;
  try {
    if (globalThis.funoApp && typeof globalThis.funoApp.resolveApiUrl === "function") {
      return globalThis.funoApp.resolveApiUrl(raw);
    }
  } catch {}
  return raw;
}

function createBaseLayer(layer, options = {}) {
  const url = resolveMapLayerUrl(layer.url_template || "");
  const attrib = options.suppressAttribution ? "" : String(layer.attribution || "");
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

function isCompetitionOverlaySelection(layer) {
  return String(layer?.code || "").toLowerCase() === EPK_OVERLAY_LAYER_CODE
    && String(layer?.overlay_composite_base_code || "").trim().length > 0;
}

function resolveBaseLayerForSelection(layer) {
  if (!isCompetitionOverlaySelection(layer)) return layer;
  const baseCode = String(layer?.overlay_composite_base_code || "").toLowerCase();
  return mapLayersByCode[baseCode] || layer;
}

function createCompetitionOverlayTileLayer(layer) {
  const url = resolveMapLayerUrl(layer?.overlay_tile_url_template || "");
  if (!url) return null;
  return L.tileLayer(url, {
    minZoom: Number(layer?.overlay_tile_min_zoom ?? 0),
    maxZoom: Number(layer?.overlay_tile_max_zoom ?? 14),
    tileSize: 256,
    opacity: 1,
    tms: false,
    noWrap: true,
    attribution: String(layer?.attribution || ""),
  });
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
    compMapRouteLayer = null;
    baseMapLayer = null;
    competitionOverlayTileLayer = null;
    mapRings = [];
    mapRoutePoints = [];
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
  compMapRouteLayer = L.layerGroup().addTo(compMap);
  compMapLayer = L.layerGroup().addTo(compMap);
  compMap.on("moveend zoomend", () => {
    saveCompMapView();
    refreshCompMapRouteDecorations();
  });
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
  const baseLayerConfig = resolveBaseLayerForSelection(layer);
  if (!baseLayerConfig) return false;
  const targetCrs = requiresLestCrs(baseLayerConfig) ? "EPSG:3301" : "EPSG:3857";
  let previousView = null;
  if (compMapCurrentCrs !== targetCrs) {
    previousView = createCompMap(targetCrs);
  }
  if (competitionOverlayTileLayer) {
    compMap.removeLayer(competitionOverlayTileLayer);
    competitionOverlayTileLayer = null;
  }
  if (baseMapLayer) {
    compMap.removeLayer(baseMapLayer);
    baseMapLayer = null;
  }
  baseMapLayer = createBaseLayer(baseLayerConfig, { suppressAttribution: isCompetitionOverlaySelection(layer) });
  baseMapLayer.addTo(compMap);
  if (isCompetitionOverlaySelection(layer)) {
    competitionOverlayTileLayer = createCompetitionOverlayTileLayer(layer);
    if (competitionOverlayTileLayer) {
      competitionOverlayTileLayer.addTo(compMap);
      if (typeof competitionOverlayTileLayer.bringToFront === "function") {
        competitionOverlayTileLayer.bringToFront();
      }
    }
  }
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

function setCompMapViewToUserLocation(restored) {
  if (restored) {
    compMap.panTo([state.geo.latitude, state.geo.longitude], { animate: false });
    return;
  }
  compMap.setView([state.geo.latitude, state.geo.longitude], 15, { animate: false });
}

function fitCompMapToCheckpointBounds(checkpointBounds) {
  compMap.fitBounds(checkpointBounds, { padding: [24, 24], maxZoom: 18 });
  const openedZoom = Number(compMap.getZoom() || 0);
  const minOpenZoom = 10;
  if (openedZoom > 0 && openedZoom < minOpenZoom) {
    compMap.setZoom(minOpenZoom);
  }
}

function applyInitialCompMapViewport(checkpointBounds, opts = {}) {
  if (!compMap) return;
  const forceInitialFit = opts?.forceInitialFit === true;
  const hasUserGeo = opts?.hasUserGeo === true;
  const restored = forceInitialFit ? false : restoreCompMapView();
  if (mapFollowUser && selectedCompetitionShowsUserLocationMarker() && hasUserGeo) {
    setCompMapViewToUserLocation(restored);
    return;
  }
  if (checkpointBounds.length) {
    if (!restored || forceInitialFit) {
      fitCompMapToCheckpointBounds(checkpointBounds);
    }
    return;
  }
  if (hasUserGeo) {
    compMap.setView([state.geo.latitude, state.geo.longitude], 15, { animate: false });
    return;
  }
  if (!restored) {
    compMap.setView([58.8, 25.4], 8, { animate: false });
  }
}

function getDefaultAllowedMapLayerCode() {
  const overlayLayer = allowedMapLayers.find((layer) => isCompetitionOverlaySelection(layer));
  if (overlayLayer?.code) return String(overlayLayer.code).toLowerCase();
  const participantDefault = allowedMapLayers.find((layer) => layer?.participant_default === true);
  if (participantDefault?.code) return String(participantDefault.code).toLowerCase();
  return String(allowedMapLayers[0]?.code || "").toLowerCase();
}

function updateFollowButton() {
  const btn = el("compMapFollowBtn");
  if (!btn) return;
  if (!selectedCompetitionUsesLocation()) {
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
  userPosMarker.setIcon(buildUserLocationMarkerIcon(mapGpsSignalLost));
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
  return selectedCompetitionUsesLocation();
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

function updateNorthIndicator() {
  const indicator = el("compMapNorthIndicator");
  if (!indicator) return;
  const show = mapHeadingMode;
  indicator.style.display = show ? "block" : "none";
  if (!show) {
    indicator.style.transform = "rotate(0deg)";
    return;
  }
  const rotation = Number.isFinite(Number(mapHeadingCurrent)) ? -Number(mapHeadingCurrent) : 0;
  indicator.style.transform = `rotate(${rotation}deg)`;
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
  pane.style.transform = stripRotateTransform(pane.style.transform);
}

function stripRotateTransform(transformValue) {
  return String(transformValue || "")
    .split(/\s+/)
    .filter((part) => part && !part.startsWith("rotate("))
    .join(" ")
    .trim();
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
  const baseTransform = stripRotateTransform(pane.style.transform);
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
  updateNorthIndicator();
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
  updateNorthIndicator();
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

function isCompMapModalOpen() {
  return el("compMapBackdrop")?.style?.display === "block";
}

function refreshCompMapPopupContents() {
  mapRings.forEach((entry) => {
    const popup = entry?.ring?.getPopup?.();
    if (entry?.ring && entry?.cp && popup?.isOpen()) {
      entry.ring.setPopupContent(checkpointPopupLabel(entry.cp));
    }
  });
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
  const passedSuffix = String(cp?.is_answered || "N").toUpperCase() === "Y"
    ? ` ${tr("competitor.map.checkpoint_passed_suffix")}`
    : "";
  const firstLine = `${points} ${tr("competitor.common.points_short")}${passedSuffix}`;
  const popupState = getCheckpointPopupState(cp);
  const actionLabel = popupState.messageKey === "competitor.check_only.submit_btn"
    ? tr("competitor.check_only.submit_btn")
    : tr("competitor.map.answer_cta_btn");
  const popupMessage = typeof popupState.messageText === "string" && popupState.messageText.trim()
    ? popupState.messageText
    : tr(popupState.messageKey);
  const secondLine = popupState.canAnswer
    ? `<button type="button" class="cpPopupAnswerBtn" data-checkpoint-id="${Number(cp?.checkpoint_id || 0)}">${esc(actionLabel)}</button>`
    : `<div class="cpPopupNoQuestion">${esc(popupMessage)}</div>`;
  return `<div class="cpPopupContent"><div class="cpPopupLine cpPopupPoints">${esc(firstLine)}</div><div class="cpPopupLine cpPopupAction">${secondLine}</div></div>`;
}

function mapCheckpointRows() {
  return Array.isArray(state.mapItems) ? state.mapItems.filter((row) => row && typeof row === "object") : [];
}

function hasMassStartBegun() {
  const massStartAt = String(getSelectedCompetition()?.mass_start_at || "").trim();
  const massStartDate = parseUtcDate(massStartAt);
  return !!massStartDate && massStartDate.getTime() <= Date.now();
}

function isLogicalStartAnswered(rows) {
  const normalizedRows = Array.isArray(rows) ? rows : [];
  const explicitStartAnswered = normalizedRows.some((row) => (
    normalizeCheckpointType(row?.checkpoint_type) === "START"
    && String(row?.is_answered || "N").toUpperCase() === "Y"
  ));
  if (explicitStartAnswered) return true;
  if (!hasMassStartBegun()) return false;
  return normalizedRows.some((row) => (
    normalizeCheckpointType(row?.checkpoint_type) === "START"
    && normalizeCheckpointInteraction(row?.checkpoint_interaction) === "MASS_START"
  ));
}

function currentSequentialCheckpointId() {
  if (selectedCompetitionType() !== "S") return null;
  const normals = mapCheckpointRows()
    .filter((row) => normalizeCheckpointType(row?.checkpoint_type) === "NORMAL" && String(row?.is_answered || "N").toUpperCase() !== "Y")
    .map((row) => ({
      checkpointId: Number(row?.checkpoint_id || 0),
      orderNo: Number(row?.checkpoint_order_no),
    }))
    .filter((row) => row.checkpointId > 0 && Number.isFinite(row.orderNo))
    .sort((a, b) => a.orderNo - b.orderNo || a.checkpointId - b.checkpointId);
  return normals.length ? normals[0].checkpointId : null;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = (
    Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * (Math.sin(dLon / 2) ** 2)
  );
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)));
}

function getCheckpointPopupState(cp) {
  const checkpointId = Number(cp?.checkpoint_id || 0);
  const questionId = Number(cp?.question_id || 0);
  const interaction = normalizeCheckpointInteraction(cp?.checkpoint_interaction);
  const checkpointType = normalizeCheckpointType(cp?.checkpoint_type);
  if (checkpointType === "START" && interaction === "MASS_START") {
    const massStartAt = String(getSelectedCompetition()?.mass_start_at || "").trim();
    return {
      canAnswer: false,
      messageKey: "competitor.map.mass_start_auto_info",
      messageText: trf("competitor.map.mass_start_auto_info", {
        value: massStartAt ? fmtEtLocal(massStartAt) : "-",
      }),
    };
  }
  if (checkpointId <= 0) {
    return { canAnswer: false, messageKey: "competitor.map.popup_question_missing" };
  }
  if (interaction === "QUESTION" && questionId <= 0) {
    return { canAnswer: false, messageKey: "competitor.map.popup_question_missing" };
  }
  if (String(cp?.is_answered || "N").toUpperCase() === "Y") {
    return { canAnswer: false, messageKey: "competitor.map.popup_question_missing" };
  }

  const rows = mapCheckpointRows();
  const finishAnswered = rows.some((row) => (
    normalizeCheckpointType(row?.checkpoint_type) === "FINISH"
    && String(row?.is_answered || "N").toUpperCase() === "Y"
  ));
  if (finishAnswered) {
    return { canAnswer: false, messageKey: "competitor.map.access_reason_finished" };
  }

  const startExists = rows.some((row) => normalizeCheckpointType(row?.checkpoint_type) === "START");
  const startAnswered = isLogicalStartAnswered(rows);
  if (startExists && !startAnswered && checkpointType !== "START") {
    return { canAnswer: false, messageKey: "competitor.map.access_reason_start_required" };
  }

  if (selectedCompetitionType() === "S") {
    if (!(startExists && !startAnswered && checkpointType === "START")) {
      const nextSequentialId = currentSequentialCheckpointId();
      if (nextSequentialId != null) {
        if (checkpointType !== "NORMAL" || checkpointId !== nextSequentialId) {
          return { canAnswer: false, messageKey: "competitor.map.access_reason_wrong_order" };
        }
      } else if (checkpointType !== "FINISH") {
        return { canAnswer: false, messageKey: "competitor.map.access_reason_wrong_order" };
      }
    }
  }

  const locationRequired = String(cp?.location_required || "N").toUpperCase() === "Y";
  if (!locationRequired) {
    return { canAnswer: true, messageKey: interaction === "CHECK_ONLY" ? "competitor.check_only.submit_btn" : "competitor.map.answer_cta_btn" };
  }
  if (!(state.geo.enabled && Number.isFinite(Number(state.geo.latitude)) && Number.isFinite(Number(state.geo.longitude)))) {
    return { canAnswer: false, messageKey: "competitor.map.access_reason_missing_location" };
  }

  const lat = Number(cp?.latitude);
  const lon = Number(cp?.longitude);
  const effectiveRadius = Number(cp?.radius_m);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || !Number.isFinite(effectiveRadius) || effectiveRadius <= 0) {
    return { canAnswer: false, messageKey: "competitor.map.access_reason_not_open" };
  }
  const distanceM = haversineMeters(Number(state.geo.latitude), Number(state.geo.longitude), lat, lon);
  if (!(Number.isFinite(distanceM) && distanceM <= effectiveRadius)) {
    return { canAnswer: false, messageKey: "competitor.map.access_reason_too_far" };
  }
  return { canAnswer: true, messageKey: interaction === "CHECK_ONLY" ? "competitor.check_only.submit_btn" : "competitor.map.answer_cta_btn" };
}

function buildCompetitionMapPoints(items) {
  return (items || []).map((cp) => {
    const lat = Number(cp?.latitude);
    const lon = Number(cp?.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    const locationRequired = String(cp?.location_required || "N").toUpperCase() === "Y";
    const checkpointType = normalizeCheckpointType(cp?.checkpoint_type);
    const rawOrder = Number(cp?.checkpoint_order_no);
    return {
      checkpointId: Number(cp?.checkpoint_id || 0),
      rawCp: cp,
      checkpointType,
      orderNo: Number.isFinite(rawOrder) ? rawOrder : null,
      mapLabel: typeof cp?.checkpoint_map_label === "string" ? cp.checkpoint_map_label.trim() : "",
      lat,
      lon,
      markerColor: locationRequired ? "#c0392b" : "#7d3c98",
      markerRadiusPx: 15,
      markerWeight: 3,
    };
  }).filter(Boolean);
}

function shouldShowCheckpointMapLabel(point) {
  if (!point || isSpecialCheckpointType(point.checkpointType)) return false;
  return typeof point.mapLabel === "string" && point.mapLabel.length > 0;
}

function buildCheckpointShapeMarker(point, extraOptions = {}) {
  const haloWidth = 2;
  const stroke = esc(point.markerColor || "#7d3c98");
  const weight = Math.max(2, Number(point.markerWeight || 3));
  const haloStrokeWidth = weight + (haloWidth * 2);
  let svg = "";
  let iconSize = [36, 36];
  let iconAnchor = [18, 18];
  let popupAnchor = [0, -18];

  if (point.checkpointType === "START") {
    svg = `<svg width="36" height="36" viewBox="0 0 36 36" aria-hidden="true"><polygon points="18,5 31,29 5,29" fill="none" stroke="#ffffff" stroke-width="${haloStrokeWidth}" stroke-linejoin="round"/><polygon points="18,5 31,29 5,29" fill="none" stroke="${stroke}" stroke-width="${weight}" stroke-linejoin="round"/></svg>`;
  } else if (point.checkpointType === "FINISH") {
    iconSize = [42, 42];
    iconAnchor = [21, 21];
    popupAnchor = [0, -21];
    svg = `<svg width="42" height="42" viewBox="0 0 42 42" aria-hidden="true"><circle cx="21" cy="21" r="15" fill="none" stroke="#ffffff" stroke-width="${haloStrokeWidth}"/><circle cx="21" cy="21" r="20" fill="none" stroke="#ffffff" stroke-width="${haloStrokeWidth}"/><circle cx="21" cy="21" r="15" fill="none" stroke="${stroke}" stroke-width="${weight}"/><circle cx="21" cy="21" r="20" fill="none" stroke="${stroke}" stroke-width="${weight}"/></svg>`;
  } else {
    svg = `<svg width="36" height="36" viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="15" fill="none" stroke="#ffffff" stroke-width="${haloStrokeWidth}"/><circle cx="18" cy="18" r="15" fill="none" stroke="${stroke}" stroke-width="${weight}"/></svg>`;
  }

  return L.marker([point.lat, point.lon], {
    icon: L.divIcon({
      className: "cp-special-div-icon",
      html: svg,
      iconSize,
      iconAnchor,
      popupAnchor,
    }),
    pane: "markerPane",
    ...extraOptions,
  });
}

function addCheckpointShapeMarker(layerRef, point, extraOptions = {}) {
  if (!layerRef || !point) return null;
  return buildCheckpointShapeMarker(point, extraOptions).addTo(layerRef);
}

function buildUserLocationMarkerIcon(isSignalLost) {
  const fill = isSignalLost ? "#8a959c" : "#2f8cff";
  const stroke = isSignalLost ? "#dfe6ea" : "#ffffff";
  const svg = `<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><circle cx="9" cy="9" r="7" fill="${fill}" stroke="${stroke}" stroke-width="2"/></svg>`;
  return L.divIcon({
    className: "cp-special-div-icon",
    html: svg,
    iconSize: [18, 18],
    iconAnchor: [9, 9],
    popupAnchor: [0, -9],
  });
}

function drawOrderedRoutesForPoints(mapRef, layerRef, points) {
  if (!mapRef || !layerRef) return;
  layerRef.clearLayers();
  if (selectedCompetitionType() !== "S") return;
  const ordered = (points || [])
    .filter((p) => Number.isFinite(Number(p.orderNo)))
    .sort((a, b) => Number(a.orderNo) - Number(b.orderNo) || Number(a.checkpointId) - Number(b.checkpointId));
  if (ordered.length < 2) return;

  const withPixels = ordered.map((p) => ({
    ...p,
    ringRadiusPx: Number.isFinite(Number(p.markerRadiusPx)) ? Number(p.markerRadiusPx) : 15,
  }));

  const markerGapPx = 10;
  const breakHalfPx = 10;
  const segments = [];

  for (let i = 0; i < withPixels.length - 1; i += 1) {
    const start = withPixels[i];
    const end = withPixels[i + 1];
    const p1 = mapRef.latLngToLayerPoint([start.lat, start.lon]);
    const p2 = mapRef.latLngToLayerPoint([end.lat, end.lon]);
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const length = Math.hypot(dx, dy);
    if (!Number.isFinite(length) || length <= 0) continue;
    if (length <= (start.ringRadiusPx + end.ringRadiusPx)) continue;
    const trimStart = start.ringRadiusPx + markerGapPx;
    const trimEnd = end.ringRadiusPx + markerGapPx;
    if (length <= (trimStart + trimEnd)) continue;
    const ux = dx / length;
    const uy = dy / length;
    const sx = p1.x + ux * trimStart;
    const sy = p1.y + uy * trimStart;
    const ex = p2.x - ux * trimEnd;
    const ey = p2.y - uy * trimEnd;
    const segLen = Math.hypot(ex - sx, ey - sy);
    if (!Number.isFinite(segLen) || segLen <= 0) continue;
    segments.push({
      idx: i,
      orderPairStart: Number(start.orderNo),
      orderPairEnd: Number(end.orderNo),
      color: end.markerColor,
      weight: Number.isFinite(Number(end.markerWeight)) ? Number(end.markerWeight) : 3,
      sx,
      sy,
      ex,
      ey,
      len: segLen,
    });
  }

  const tBreaks = new Map();
  const addBreak = (idx, t0, t1) => {
    const key = String(idx);
    if (!tBreaks.has(key)) tBreaks.set(key, []);
    tBreaks.get(key).push([Math.max(0, t0), Math.min(1, t1)]);
  };
  const cross = (ax, ay, bx, by) => ax * by - ay * bx;

  for (let a = 0; a < segments.length; a += 1) {
    for (let b = a + 1; b < segments.length; b += 1) {
      const s1 = segments[a];
      const s2 = segments[b];
      const shareEndpoint = s1.orderPairStart === s2.orderPairStart
        || s1.orderPairStart === s2.orderPairEnd
        || s1.orderPairEnd === s2.orderPairStart
        || s1.orderPairEnd === s2.orderPairEnd;
      if (shareEndpoint) continue;

      const rX = s1.ex - s1.sx;
      const rY = s1.ey - s1.sy;
      const qmpX = s2.sx - s1.sx;
      const qmpY = s2.sy - s1.sy;
      const sX = s2.ex - s2.sx;
      const sY = s2.ey - s2.sy;
      const den = cross(rX, rY, sX, sY);
      if (Math.abs(den) < 1e-9) continue;
      const t = cross(qmpX, qmpY, sX, sY) / den;
      const u = cross(qmpX, qmpY, rX, rY) / den;
      if (t <= 0 || t >= 1 || u <= 0 || u >= 1) continue;

      const lower = s1.orderPairStart < s2.orderPairStart ? s1 : s2;
      const dt = breakHalfPx / lower.len;
      addBreak(lower.idx, t - dt, t + dt);
    }
  }

  const mergeIntervals = (arr) => {
    if (!arr || arr.length === 0) return [];
    const sorted = [...arr].sort((x, y) => x[0] - y[0]);
    const out = [sorted[0].slice()];
    for (let i = 1; i < sorted.length; i += 1) {
      const cur = sorted[i];
      const last = out[out.length - 1];
      if (cur[0] <= last[1]) last[1] = Math.max(last[1], cur[1]);
      else out.push(cur.slice());
    }
    return out.filter((x) => x[1] > x[0]);
  };

  segments.forEach((seg) => {
    const breaks = mergeIntervals(tBreaks.get(String(seg.idx)) || []);
    const drawPart = (t0, t1) => {
      if (t1 <= t0) return;
      const pA = L.point(seg.sx + (seg.ex - seg.sx) * t0, seg.sy + (seg.ey - seg.sy) * t0);
      const pB = L.point(seg.sx + (seg.ex - seg.sx) * t1, seg.sy + (seg.ey - seg.sy) * t1);
      L.polyline([mapRef.layerPointToLatLng(pA), mapRef.layerPointToLatLng(pB)], {
        color: "#ffffff",
        weight: seg.weight + 2,
        opacity: 0.95,
        interactive: false,
      }).addTo(layerRef);
      L.polyline([mapRef.layerPointToLatLng(pA), mapRef.layerPointToLatLng(pB)], {
        color: seg.color,
        weight: seg.weight,
        opacity: 0.95,
        interactive: false,
      }).addTo(layerRef);
    };
    if (!breaks.length) {
      drawPart(0, 1);
      return;
    }
    let cursor = 0;
    breaks.forEach(([b0, b1]) => {
      drawPart(cursor, b0);
      cursor = Math.max(cursor, b1);
    });
    drawPart(cursor, 1);
  });
}

function estimateCheckpointMapLabelRect(point, placement, mapRef) {
  if (!point || !placement || !mapRef) return null;
  const mapPoint = mapRef.latLngToLayerPoint([point.lat, point.lon]);
  const labelText = typeof point.mapLabel === "string" ? point.mapLabel : "";
  const labelWidth = Math.max(26, Math.round(labelText.length * 12) + 12);
  const labelHeight = 26;
  const offsetX = Number(placement.offset?.[0] || 0);
  const offsetY = Number(placement.offset?.[1] || 0);
  const gap = 6;
  let left = mapPoint.x + offsetX;
  let top = mapPoint.y + offsetY - (labelHeight / 2);

  if (placement.direction === "left") {
    left = mapPoint.x + offsetX - labelWidth - gap;
  } else if (placement.direction === "right") {
    left = mapPoint.x + offsetX + gap;
  } else if (placement.direction === "top") {
    left = mapPoint.x + offsetX - (labelWidth / 2);
    top = mapPoint.y + offsetY - labelHeight - gap;
  } else if (placement.direction === "bottom") {
    left = mapPoint.x + offsetX - (labelWidth / 2);
    top = mapPoint.y + offsetY + gap;
  }

  return {
    left,
    top,
    right: left + labelWidth,
    bottom: top + labelHeight,
  };
}

function rectsOverlap(a, b, padding = 0) {
  if (!a || !b) return false;
  return !(
    a.right + padding < b.left
    || a.left - padding > b.right
    || a.bottom + padding < b.top
    || a.top - padding > b.bottom
  );
}

function markerRect(point, mapRef) {
  if (!point || !mapRef) return null;
  const mapPoint = mapRef.latLngToLayerPoint([point.lat, point.lon]);
  const radius = Number.isFinite(Number(point.markerRadiusPx)) ? Number(point.markerRadiusPx) : 15;
  return {
    left: mapPoint.x - radius,
    top: mapPoint.y - radius,
    right: mapPoint.x + radius,
    bottom: mapPoint.y + radius,
  };
}

function buildRCheckpointLabelPlacement(mapRef, points) {
  const placements = new Map();
  if (!mapRef) return placements;

  const candidates = [
    { direction: "right", offset: [14, -14] },
    { direction: "right", offset: [14, 0] },
    { direction: "top", offset: [0, -16] },
    { direction: "left", offset: [-14, 0] },
    { direction: "bottom", offset: [0, 16] },
    { direction: "right", offset: [14, 14] },
  ];

  const labeledPoints = (points || []).filter((point) => shouldShowCheckpointMapLabel(point));
  const pointById = new Map(labeledPoints.map((point) => [Number(point.checkpointId), point]));
  const placedRects = [];

  labeledPoints.forEach((point) => {
    let chosenPlacement = candidates[0];
    let chosenRect = estimateCheckpointMapLabelRect(point, chosenPlacement, mapRef);
    let chosenScore = Number.POSITIVE_INFINITY;

    candidates.forEach((candidate, index) => {
      const rect = estimateCheckpointMapLabelRect(point, candidate, mapRef);
      if (!rect) return;

      let conflicts = 0;
      labeledPoints.forEach((otherPoint) => {
        if (Number(otherPoint.checkpointId) === Number(point.checkpointId)) return;
        const otherRect = markerRect(otherPoint, mapRef);
        if (rectsOverlap(rect, otherRect, 4)) conflicts += 1;
      });
      placedRects.forEach((otherRect) => {
        if (rectsOverlap(rect, otherRect, 4)) conflicts += 2;
      });

      const score = conflicts * 100 + index;
      if (score < chosenScore) {
        chosenScore = score;
        chosenPlacement = candidate;
        chosenRect = rect;
      }
      if (conflicts === 0 && index === 0) {
        chosenScore = score;
        chosenPlacement = candidate;
        chosenRect = rect;
      }
    });

    placements.set(Number(point.checkpointId), chosenPlacement);
    if (chosenRect) {
      placedRects.push(chosenRect);
    }
  });

  pointById.forEach((point, checkpointId) => {
    if (!placements.has(checkpointId)) {
      placements.set(checkpointId, candidates[0]);
    }
  });
  return placements;
}

function buildOrderLabelPlacement(mapRef, points) {
  const placements = new Map();
  (points || []).forEach((p) => {
    placements.set(Number(p.checkpointId), { direction: "right", offset: [12, 0] });
  });
  if (!mapRef) return placements;
  if (selectedCompetitionType() === "R") {
    return buildRCheckpointLabelPlacement(mapRef, points);
  }
  if (selectedCompetitionType() !== "S") return placements;
  if (typeof mapRef.getSize !== "function" || typeof mapRef.getZoom !== "function") {
    return placements;
  }
  try {
    const size = mapRef.getSize();
    const zoom = Number(mapRef.getZoom());
    if (!size || size.x <= 0 || size.y <= 0 || !Number.isFinite(zoom)) return placements;
  } catch {
    return placements;
  }

  const ordered = (points || [])
    .filter((p) => Number.isFinite(Number(p.orderNo)))
    .sort((a, b) => Number(a.orderNo) - Number(b.orderNo) || Number(a.checkpointId) - Number(b.checkpointId));
  if (!ordered.length) return placements;

  const unit = (ax, ay, bx, by) => {
    const dx = bx - ax;
    const dy = by - ay;
    const len = Math.hypot(dx, dy);
    if (!Number.isFinite(len) || len <= 0) return { x: 0, y: 0 };
    return { x: dx / len, y: dy / len };
  };

  for (let i = 0; i < ordered.length; i += 1) {
    const cur = ordered[i];
    const curPoint = mapRef.latLngToLayerPoint([cur.lat, cur.lon]);
    let sumX = 0;
    let sumY = 0;
    if (i > 0) {
      const prev = ordered[i - 1];
      const prevPoint = mapRef.latLngToLayerPoint([prev.lat, prev.lon]);
      const v = unit(curPoint.x, curPoint.y, prevPoint.x, prevPoint.y);
      sumX += v.x;
      sumY += v.y;
    }
    if (i < ordered.length - 1) {
      const next = ordered[i + 1];
      const nextPoint = mapRef.latLngToLayerPoint([next.lat, next.lon]);
      const v = unit(curPoint.x, curPoint.y, nextPoint.x, nextPoint.y);
      sumX += v.x;
      sumY += v.y;
    }

    let dx = -sumX;
    let dy = -sumY;
    if (Math.hypot(dx, dy) < 0.01) {
      dx = 1;
      dy = -1;
    }
    const len = Math.hypot(dx, dy) || 1;
    dx /= len;
    dy /= len;

    let direction = "right";
    if (Math.abs(dx) >= Math.abs(dy)) {
      direction = dx >= 0 ? "right" : "left";
    } else {
      direction = dy >= 0 ? "bottom" : "top";
    }
    placements.set(Number(cur.checkpointId), {
      direction,
      offset: [Math.round(dx * 18), Math.round(dy * 18)],
    });
  }
  return placements;
}

function refreshCompMapRouteDecorations() {
  if (!compMap || !compMapRouteLayer) return;
  drawOrderedRoutesForPoints(compMap, compMapRouteLayer, mapRoutePoints);
  const labelPlacement = buildOrderLabelPlacement(compMap, mapRoutePoints);
  mapRings.forEach((entry) => {
    const marker = entry?.ring;
    const point = entry?.point;
    if (!marker || !point) return;
    if (!shouldShowCheckpointMapLabel(point)) {
      if (typeof marker.unbindTooltip === "function") marker.unbindTooltip();
      return;
    }
    const placement = labelPlacement.get(Number(point.checkpointId)) || { direction: "right", offset: [12, 0] };
    if (typeof marker.unbindTooltip === "function") marker.unbindTooltip();
    marker.bindTooltip(point.mapLabel, {
      permanent: true,
      direction: placement.direction,
      offset: placement.offset,
      className: point.markerColor === "#c0392b" ? "cp-order-tooltip cp-order-red" : "cp-order-tooltip cp-order-purple",
      interactive: false,
      opacity: 1,
    });
  });
}

function checkpointAccessReasonMessage(reason) {
  const key = {
    missing_location: "competitor.map.access_reason_missing_location",
    too_far: "competitor.map.access_reason_too_far",
    finished: "competitor.map.access_reason_finished",
    start_required: "competitor.map.access_reason_start_required",
    wrong_order: "competitor.map.access_reason_wrong_order",
    not_open: "competitor.map.access_reason_not_open",
    not_found: "competitor.map.access_reason_not_open",
  }[String(reason || "").toLowerCase()];
  return key ? tr(key) : "";
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
  setMapNotice("", true);
  const requiresLocation = String(cp?.location_required || "N").toUpperCase() === "Y";
  if (requiresLocation) {
    setMapNoticeBusy(tr("competitor.map.detecting_location_notice"));
    await requestGeolocation({ maximumAge: 10000, timeout: 5000, enableHighAccuracy: true });
    setMapNotice("", true);
    if (!state.geo.enabled) {
      if (state.geo.error) setMapNotice(state.geo.error, false);
      return;
    }
  }
  const accessItems = await checkCheckpointAccess([cpId]);
  const access = accessItems.find((x) => Number(x?.checkpoint_id || 0) === cpId) || null;
  if (!access || access.can_open !== true) {
    if (String(access?.reason || "") === "answered") {
      cp.is_answered = "Y";
      const ringEntry = mapRings.find((x) => Number(x?.cp?.checkpoint_id || 0) === cpId);
      ringEntry?.ring?.setPopupContent(checkpointPopupLabel(cp));
      return;
    }
    const reasonMessage = checkpointAccessReasonMessage(access?.reason);
    if (reasonMessage) setMapNotice(reasonMessage, false);
    return;
  }
  const loaded = await loadOpenCheckpoints({ force: true, preferredCheckpointId: cpId });
  if (!loaded) {
    setMapNotice(tr("competitor.msg.open_cp_load_failed"), false);
    return;
  }
  const item = getOpenItemByCheckpointId(cpId);
  if (!item) {
    setMapNotice(tr("competitor.map.popup_question_missing"), false);
    return;
  }
  if (normalizeCheckpointInteraction(item?.checkpoint_interaction) === "CHECK_ONLY") {
    submitAnswer(item, {}, {
      messageTargetId: "compMapNotice",
      busyNoticeKey: "competitor.check_only.submitting_notice",
    });
    return;
  }
  openMapQuestionModal(item);
}

function renderCompMap(items, opts = {}) {
  const forceInitialFit = opts && opts.forceInitialFit === true;
  const preserveViewport = opts && opts.preserveViewport === true;
  ensureCompMapInit();
  compMapLayer.clearLayers();
  if (compMapRouteLayer) compMapRouteLayer.clearLayers();
  mapRings = [];
  mapRoutePoints = [];
  if (userPosMarker) {
    compMap.removeLayer(userPosMarker);
    userPosMarker = null;
  }
  mapRoutePoints = buildCompetitionMapPoints(items);
  const checkpointBounds = [];
  mapRoutePoints.forEach((point) => {
    const marker = addCheckpointShapeMarker(compMapLayer, point);
    marker.bindPopup(checkpointPopupLabel(point.rawCp), { autoClose: false, closeOnClick: false, autoPan: false, className: "cpPopup", maxWidth: 260 });
    mapRings.push({ ring: marker, cp: point.rawCp, point });
    checkpointBounds.push([point.lat, point.lon]);
  });
  const hasUserGeo = state.geo.enabled && state.geo.latitude != null && state.geo.longitude != null;
  const showUserMarker = selectedCompetitionShowsUserLocationMarker() && hasUserGeo;
  if (showUserMarker) {
    userPosMarker = L.marker([state.geo.latitude, state.geo.longitude], {
      icon: buildUserLocationMarkerIcon(mapGpsSignalLost),
      pane: "markerPane",
      zIndexOffset: -1000,
    }).addTo(compMap);
    userPosMarker.bindPopup(tr("competitor.map.user_location_popup"));
    applyUserMarkerVisualState();
  }
  updateMapGpsStatus();
  mapProgrammaticMove = true;
  setMapInfoVisibility(mapInfoVisible);
  setTimeout(() => {
    if (!compMap) return;
    compMap.invalidateSize();
    if (!preserveViewport) {
      applyInitialCompMapViewport(checkpointBounds, { forceInitialFit, hasUserGeo });
    }
    refreshCompMapRouteDecorations();
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
  refreshCompMapPopupContents();
  if (userPosMarker && !selectedCompetitionShowsUserLocationMarker()) {
    compMap?.removeLayer(userPosMarker);
    userPosMarker = null;
  }
  if (!compMap) return;
  if (selectedCompetitionShowsUserLocationMarker() && !userPosMarker) {
    userPosMarker = L.marker([lat, lon], {
      icon: buildUserLocationMarkerIcon(mapGpsSignalLost),
      pane: "markerPane",
      zIndexOffset: -1000,
    }).addTo(compMap);
    userPosMarker.bindPopup(tr("competitor.map.user_location_popup"));
    applyUserMarkerVisualState();
  } else if (userPosMarker) {
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
  showCompetitorBusy("competitor.map.open_loading_msg");
  try {
  mapViewPersistenceEnabled = false;
  mapGpsSignalLost = false;
  mapHeadingPermissionAsked = false;
  setMapNotice("", true);
  mapFollowUser = selectedCompetitionShowsUserLocationMarker();
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
  const shouldRetryInitialCheckpointFit =
    !selectedCompetitionShowsUserLocationMarker()
    && !hasSavedCompMapView()
    && !state.mapItems.length;
  if (shouldRetryInitialCheckpointFit) {
    await new Promise((resolve) => setTimeout(resolve, 350));
    state.mapItems = await loadMapCheckpoints();
  }
  el("compMapBackdrop").style.display = "block";
  await new Promise((resolve) => requestAnimationFrame(() => resolve()));
  mapProgrammaticMove = true;
  ensureCompMapInit();
  const rememberedLayerCode = String(getCookie(getMapLayerCookieKey()) || "").toLowerCase();
  if (rememberedLayerCode && mapLayersByCode[rememberedLayerCode]) {
    activeMapLayerCode = rememberedLayerCode;
  } else if (!activeMapLayerCode || !mapLayersByCode[activeMapLayerCode]) {
    activeMapLayerCode = getDefaultAllowedMapLayerCode();
  }
  applyBaseLayer(activeMapLayerCode);
  const layerBtn = el("compMapLayerBtn");
  if (layerBtn) {
    layerBtn.style.display = allowedMapLayers.length > 1 ? "inline-flex" : "none";
  }
  renderCompMapLayerList();
  compMap.invalidateSize();
  const forceInitialFit = !selectedCompetitionShowsUserLocationMarker() && !hasSavedCompMapView();
  renderCompMap(state.mapItems, { forceInitialFit });
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
  globalThis.funoApp?.setMapKeepAwake?.(true).catch?.(() => {});
  } finally {
    hideCompetitorBusy();
  }
}

function closeCompMapModal() {
  saveCompMapView();
  setHeadingMode(false);
  mapHeadingPermissionAsked = false;
  stopMapGeolocationWatch();
  syncMapGpsSignalState(true);
  setMapNotice("", true);
  closeMapQuestionModal();
  el("compMapLayerBackdrop").style.display = "none";
  el("compMapBackdrop").style.display = "none";
  globalThis.funoApp?.setMapKeepAwake?.(false).catch?.(() => {});
}

async function applyCheckpointLoadingMode() {
  const needsLocation = selectedCompetitionUsesLocation();
  closeMapQuestionModal();
  el("answerCard").style.display = needsLocation ? "none" : "block";
  el("showKpBtn").style.display = needsLocation ? "none" : "inline-block";
  state.openItems = [];
  state.openItemsLoaded = false;
  renderCheckpointSelect();
  if (needsLocation) {
    state.mapItems = await loadMapCheckpoints();
  }
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
