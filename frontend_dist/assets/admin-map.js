function cpOverviewViewStorageKey(crs = null) {
  const code = String(crs || cpOverviewCurrentCrs || "EPSG:3857").toUpperCase();
  return `${lastCpOverviewViewKey()}_${code.replace(/[^A-Z0-9]+/g, "_")}`;
}

function cpDialogViewStorageKey(crs = null) {
  const code = String(crs || cpDialogCurrentCrs || "EPSG:3857").toUpperCase();
  return `${lastCpDialogViewKey()}_${code.replace(/[^A-Z0-9]+/g, "_")}`;
}

let cpOverlayLayer = null;
let cpOverviewOverlayLayer = null;
let cpOverviewRouteVisible = false;

function ensureCompetitionOverlayPane(mapRef, target = "dialog") {
  if (!mapRef?.createPane) return null;
  const paneName = target === "overview" ? "competitionOverlayPaneOverview" : "competitionOverlayPaneDialog";
  let pane = mapRef.getPane?.(paneName);
  if (!pane) {
    pane = mapRef.createPane(paneName);
  }
  if (pane?.style) {
    pane.style.zIndex = "350";
    pane.style.pointerEvents = "none";
  }
  return paneName;
}

function ensureCheckpointRadiusPane(mapRef, target = "dialog") {
  if (!mapRef?.createPane) return null;
  const paneName = target === "overview" ? "checkpointRadiusPaneOverview" : "checkpointRadiusPaneDialog";
  let pane = mapRef.getPane?.(paneName);
  if (!pane) {
    pane = mapRef.createPane(paneName);
  }
  if (pane?.style) {
    pane.style.zIndex = "560";
    pane.style.pointerEvents = "none";
  }
  return paneName;
}

function mergeMapAttribution(baseAttribution, overlayAttribution) {
  const base = String(baseAttribution || "").trim();
  const overlay = String(overlayAttribution || "").trim();
  if (base && overlay) return `${base} | ${overlay}`;
  if (overlay) return overlay;
  if (base) return base;
  return "&copy;";
}

function readLastCpDialogView(crs = null) {
  try {
    const raw = localStorage.getItem(cpDialogViewStorageKey(crs)) || localStorage.getItem(lastCpDialogViewKey());
    if (!raw) return null;
    const d = JSON.parse(raw);
    if (!d || !Number.isFinite(Number(d.lat)) || !Number.isFinite(Number(d.lon)) || !Number.isFinite(Number(d.zoom))) return null;
    return { lat: Number(d.lat), lon: Number(d.lon), zoom: Number(d.zoom) };
  } catch (_e) {
    return null;
  }
}

function writeLastCpDialogView() {
  if (!cpMap) return;
  const center = cpMap.getCenter();
  const zoom = cpMap.getZoom();
  if (!Number.isFinite(Number(center.lat)) || !Number.isFinite(Number(center.lng)) || !Number.isFinite(Number(zoom))) return;
  const payload = JSON.stringify({ lat: Number(center.lat), lon: Number(center.lng), zoom: Number(zoom) });
  localStorage.setItem(cpDialogViewStorageKey(), payload);
  localStorage.setItem(lastCpDialogViewKey(), payload);
}

function createCpDialogMap(targetCrs) {
  let previousView = null;
  if (cpMap) {
    const c = cpMap.getCenter();
    const z = cpMap.getZoom();
    if (Number.isFinite(Number(c?.lat)) && Number.isFinite(Number(c?.lng)) && Number.isFinite(Number(z))) {
      previousView = { lat: Number(c.lat), lon: Number(c.lng), zoom: Number(z) };
    }
    cpMap.off("moveend", writeLastCpDialogView);
    cpMap.remove();
    cpMap = null;
    cpBaseLayer = null;
    cpOverlayLayer = null;
    cpMarker = null;
    cpRadiusCircle = null;
    cpExistingLayer = null;
    cpExistingRoutesLayer = null;
    cpExistingZoomHandler = null;
  }
  const options = { zoomControl: true, dragging: true, scrollWheelZoom: true };
  const customCrs = createCustomCrs(targetCrs);
  if (customCrs) options.crs = customCrs;
  cpMap = L.map("cpMap", options);
  cpMap.on("click", (e) => setCpCoordinates(e.latlng.lat, e.latlng.lng, true));
  cpMap.on("moveend", writeLastCpDialogView);
  cpExistingLayer = L.layerGroup().addTo(cpMap);
  cpExistingRoutesLayer = L.layerGroup().addTo(cpMap);
  cpDialogCurrentCrs = targetCrs;
  return previousView;
}

function latLngInBounds(lat, lon, bounds) {
  if (!bounds) return true;
  return lat >= bounds.minLat && lat <= bounds.maxLat && lon >= bounds.minLon && lon <= bounds.maxLon;
}

function selectedMapCrsCode(layerCfg) {
  const code = String(layerCfg?.crs || "").trim().toUpperCase();
  if (code === "EPSG:3301" || code === "EPSG:3059") return code;
  return "EPSG:3857";
}

function hasBaseLayerCode(code) {
  return Array.isArray(baseMapLayers) && baseMapLayers.some((x) => String(x?.code || "") === String(code || ""));
}

function hasActiveCompetitionOverlay() {
  return !!(currentCompetitionOverlay && currentCompetitionOverlay.exists && currentCompetitionOverlay.bounds_3301);
}

function hasReadyCompetitionOverlay() {
  return hasActiveCompetitionOverlay()
    && String(currentCompetitionOverlay.processing_status || "").toUpperCase() === "READY"
    && !!String(currentCompetitionOverlay.tile_url_template || "").trim();
}

function buildEffectiveMapLayers() {
  const base = Array.isArray(baseMapLayers) ? [...baseMapLayers] : [];
  const canUseOverlay = hasBaseLayerCode(EPK_LAYER_CODE) && hasReadyCompetitionOverlay();
  if (canUseOverlay) {
    const epk = base.find((x) => String(x?.code || "") === EPK_LAYER_CODE);
    if (epk) {
      base.push({
        ...epk,
        code: EPK_OVERLAY_LAYER_CODE,
        label: String(currentCompetitionOverlay?.display_label || currentCompetitionOverlay?.display_name || "").trim(),
        participant_default: false,
      });
    }
  }
  return base;
}

function sizeSelectToLongestOption(selectEl) {
  if (!selectEl || !selectEl.options?.length) return;
  try {
    const style = window.getComputedStyle(selectEl);
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.font = style.font || `${style.fontSize} ${style.fontFamily}`;
    let longestPx = 0;
    Array.from(selectEl.options).forEach((option) => {
      const label = String(option?.text || "").trim();
      if (!label) return;
      longestPx = Math.max(longestPx, ctx.measureText(label).width);
    });
    const extraPx = 48;
    const targetPx = Math.ceil(longestPx + extraPx);
    selectEl.style.width = `${targetPx}px`;
    selectEl.style.maxWidth = "100%";
  } catch (_e) {
    // Ignore width measurement failures and let CSS fallback take over.
  }
}

function refreshAdminMapLayerOptions() {
  availableMapLayers = buildEffectiveMapLayers();
  if (!availableMapLayers.length) return availableMapLayers;
  const sel = byId("cpOverviewMapLayerSelect");
  const cpSel = byId("cpDialogMapLayerSelect");
  const remembered = localStorage.getItem(lastCpOverviewMapLayerKey) || "";
  const rememberedCp = localStorage.getItem(lastCpDialogMapLayerKey) || "";
  if (sel) {
    sel.innerHTML = availableMapLayers.map((x) => `<option value="${esc(x.code)}">${esc(x.label)}</option>`).join("");
    sel.value = availableMapLayers.some((x) => x.code === remembered) ? remembered : availableMapLayers[0].code;
    sizeSelectToLongestOption(sel);
  }
  if (cpSel) {
    cpSel.innerHTML = availableMapLayers.map((x) => `<option value="${esc(x.code)}">${esc(x.label)}</option>`).join("");
    cpSel.value = availableMapLayers.some((x) => x.code === rememberedCp)
      ? rememberedCp
      : ((sel?.value && availableMapLayers.some((x) => x.code === sel.value)) ? sel.value : availableMapLayers[0].code);
    sizeSelectToLongestOption(cpSel);
  }
  return availableMapLayers;
}

function overlaySelectionUsesComposite(selectId = "cpOverviewMapLayerSelect", storageKey = lastCpOverviewMapLayerKey) {
  return selectedMapLayerCode(selectId, storageKey) === EPK_OVERLAY_LAYER_CODE;
}

function resolveBaseMapLayerForSelection(selectId = "cpOverviewMapLayerSelect", storageKey = lastCpOverviewMapLayerKey) {
  const layerCfg = resolveSelectedMapLayer(selectId, storageKey);
  if (!layerCfg) return null;
  if (String(layerCfg.code || "") !== EPK_OVERLAY_LAYER_CODE) return layerCfg;
  return (Array.isArray(baseMapLayers) ? baseMapLayers : []).find((x) => String(x.code || "") === EPK_LAYER_CODE) || layerCfg;
}

function overlayBoundsToLatLng(bounds3301) {
  if (!bounds3301 || !window.proj4) return null;
  const sw = window.proj4("EPSG:3301", "EPSG:4326", [Number(bounds3301.min_x), Number(bounds3301.min_y)]);
  const ne = window.proj4("EPSG:3301", "EPSG:4326", [Number(bounds3301.max_x), Number(bounds3301.max_y)]);
  if (!Array.isArray(sw) || !Array.isArray(ne)) return null;
  return L.latLngBounds([sw[1], sw[0]], [ne[1], ne[0]]);
}

function crsDefaultView(targetCrs) {
  if (targetCrs === "EPSG:3301") return { lat: 58.6, lon: 25.0, zoom: 5 };
  if (targetCrs === "EPSG:3059") return { lat: 56.95, lon: 24.1, zoom: 4 };
  return { lat: 58.6, lon: 25.0, zoom: 7 };
}

function crsMaxOverviewZoom(targetCrs) {
  if (targetCrs === "EPSG:3301") return 14;
  if (targetCrs === "EPSG:3059") return 11;
  return 16;
}

function isViewCompatibleWithCrs(view, targetCrs) {
  if (!view) return false;
  if (targetCrs === "EPSG:3301") {
    return latLngInBounds(view.lat, view.lon, { minLat: 57.3, maxLat: 60.2, minLon: 21.0, maxLon: 29.2 });
  }
  if (targetCrs === "EPSG:3059") {
    return latLngInBounds(view.lat, view.lon, { minLat: 55.5, maxLat: 58.3, minLon: 20.4, maxLon: 28.7 });
  }
  return true;
}

function createCustomCrs(targetCrs) {
  if (!window.L?.Proj?.CRS) return null;
  if (targetCrs === "EPSG:3301") {
    return new L.Proj.CRS(
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
  if (targetCrs === "EPSG:3059") {
    return new L.Proj.CRS(
      "EPSG:3059",
      "+proj=tmerc +lat_0=0 +lon_0=24 +k=0.9996 +x_0=500000 +y_0=-6000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +axis=neu",
      {
        origin: [488667, 1500000],
        resolutions: [
          132.29193125051253, 66.14596562525626, 33.07298281262813, 16.536491406314066,
          8.268245703157033, 4.134122851578516, 2.067061425789258, 1.033530712894629,
          0.5167653564473145, 0.25838267822365724, 0.12919133911182862, 0.06459566955591431
        ],
        bounds: L.bounds([488667, 1161333], [1166520, 1500000])
      }
    );
  }
  return null;
}

function createWmtsTileLayerFromConfig(layerCfg, urlOverride = null, matrixSetOverride = null, zoomOffsetOverride = null, tileSizeOverride = null) {
  const urlTemplate = String(urlOverride || layerCfg?.url_template || "");
  const matrixSet = String(matrixSetOverride || layerCfg?.wmts_matrix_set || "").trim();
  const zoomOffset = Number(zoomOffsetOverride ?? layerCfg?.wmts_zoom_offset ?? 0);
  const tileSize = Number(tileSizeOverride ?? layerCfg?.tile_size ?? 256);
  const WmtsTileLayer = L.TileLayer.extend({
    getTileUrl(coords) {
      return L.Util.template(urlTemplate, {
        x: coords.x,
        y: coords.y,
        z: coords.z,
        s: this._getSubdomain(coords),
        r: L.Browser.retina ? "@2x" : "",
        wmts_z: matrixSet ? `${matrixSet}:${coords.z + zoomOffset}` : String(coords.z + zoomOffset),
      });
    }
  });
  return new WmtsTileLayer(urlTemplate, {
    maxZoom: Number(layerCfg?.max_zoom || 19),
    minZoom: Number(layerCfg?.min_zoom || 0),
    attribution: layerCfg?.attribution || "&copy;",
    tileSize,
    tms: !!layerCfg?.tms,
  });
}

function createConfiguredTileLayer(layerCfg, mapRef = null) {
  if (!layerCfg) return null;
  if ((layerCfg.layer_type || "xyz") === "wms") {
    return L.tileLayer.wms(layerCfg.url_template, {
      layers: layerCfg.wms_layers || "",
      format: layerCfg.wms_format || "image/png",
      transparent: !!layerCfg.wms_transparent,
      version: layerCfg.wms_version || "1.3.0",
      maxZoom: Number(layerCfg.max_zoom || 19),
      minZoom: Number(layerCfg.min_zoom || 0),
      attribution: layerCfg.attribution || "&copy;",
    });
  }
  if ((layerCfg.layer_type || "xyz") === "wmts") {
    return createWmtsTileLayerFromConfig(layerCfg);
  }
  if ((layerCfg.layer_type || "xyz") === "wmts_fallback") {
    if (!mapRef) return createWmtsTileLayerFromConfig(layerCfg);
    const topoLayer = createWmtsTileLayerFromConfig(layerCfg);
    const orthoLayer = createWmtsTileLayerFromConfig(
      layerCfg,
      layerCfg.fallback_url_template || layerCfg.url_template,
      layerCfg.fallback_wmts_matrix_set || layerCfg.wmts_matrix_set,
      layerCfg.fallback_wmts_zoom_offset,
      layerCfg.fallback_tile_size
    );
    const switchZoom = Number(layerCfg.fallback_zoom_threshold ?? 1);
    return {
      _mapRef: null,
      _activeLayer: null,
      _updateActiveLayer() {
        if (!this._mapRef) return;
        const nextLayer = Number(this._mapRef.getZoom()) <= switchZoom ? topoLayer : orthoLayer;
        if (this._activeLayer === nextLayer) return;
        if (this._activeLayer && this._mapRef.hasLayer(this._activeLayer)) this._mapRef.removeLayer(this._activeLayer);
        this._activeLayer = nextLayer;
        if (!this._mapRef.hasLayer(this._activeLayer)) this._activeLayer.addTo(this._mapRef);
      },
      addTo(targetMap) {
        this._mapRef = targetMap;
        this._boundUpdate = this._updateActiveLayer.bind(this);
        targetMap.on("zoomend", this._boundUpdate);
        this._boundUpdate();
        return this;
      },
      removeFrom(targetMap) {
        if (this._boundUpdate) targetMap.off("zoomend", this._boundUpdate);
        if (targetMap.hasLayer(topoLayer)) targetMap.removeLayer(topoLayer);
        if (targetMap.hasLayer(orthoLayer)) targetMap.removeLayer(orthoLayer);
        this._mapRef = null;
        this._activeLayer = null;
        return this;
      }
    };
  }
  return L.tileLayer(layerCfg.url_template, {
    maxZoom: Number(layerCfg.max_zoom || 19),
    minZoom: Number(layerCfg.min_zoom || 0),
    attribution: layerCfg.attribution || "&copy;",
    tms: !!layerCfg.tms,
    tileSize: Number(layerCfg.tile_size || 256),
  });
}

function baseLayerConfigForSelection(layerCfg, usesOverlay) {
  if (!layerCfg || !usesOverlay) return layerCfg;
  return {
    ...layerCfg,
    attribution: "",
  };
}

function applyCompetitionOverlayToMap(mapRef, target = "dialog") {
  const overlayRefName = target === "overview" ? "cpOverviewOverlayLayer" : "cpOverlayLayer";
  const existing = target === "overview" ? cpOverviewOverlayLayer : cpOverlayLayer;
  if (existing && mapRef?.hasLayer?.(existing)) {
    mapRef.removeLayer(existing);
  }
  if (target === "overview") cpOverviewOverlayLayer = null;
  else cpOverlayLayer = null;

  const shouldUseOverlay = target === "overview"
    ? overlaySelectionUsesComposite("cpOverviewMapLayerSelect", lastCpOverviewMapLayerKey)
    : overlaySelectionUsesComposite("cpDialogMapLayerSelect", lastCpDialogMapLayerKey);
  if (!shouldUseOverlay || !hasReadyCompetitionOverlay() || !mapRef) return;
  const bounds = overlayBoundsToLatLng(currentCompetitionOverlay.bounds_3301);
  if (!bounds) return;
  const paneName = ensureCompetitionOverlayPane(mapRef, target);
  const layer = L.tileLayer(currentCompetitionOverlay.tile_url_template, {
    minZoom: Number(currentCompetitionOverlay.tile_min_zoom ?? 0),
    maxZoom: Number(currentCompetitionOverlay.tile_max_zoom ?? 14),
    tileSize: 256,
    opacity: 1,
    bounds,
    pane: paneName || undefined,
    tms: false,
    noWrap: true,
    attribution: mergeMapAttribution(
      resolveBaseMapLayerForSelection(
        target === "overview" ? "cpOverviewMapLayerSelect" : "cpDialogMapLayerSelect",
        target === "overview" ? lastCpOverviewMapLayerKey : lastCpDialogMapLayerKey
      )?.attribution,
      currentCompetitionOverlay.attribution
    ),
  });
  layer.addTo(mapRef);
  if (overlayRefName === "cpOverviewOverlayLayer") cpOverviewOverlayLayer = layer;
  else cpOverlayLayer = layer;
}

function initCheckpointMap() {
  const layerCfg = resolveSelectedMapLayer("cpDialogMapLayerSelect", lastCpDialogMapLayerKey);
  const targetCrs = selectedMapCrsCode(layerCfg);
  const clampZoom = (z) => {
    const maxZoom = Number(layerCfg?.max_zoom || 19);
    const minZoom = Number(layerCfg?.min_zoom || 0);
    return Math.max(minZoom, Math.min(maxZoom, Number(z)));
  };
  if (!cpMap) {
    createCpDialogMap(targetCrs);
    const saved = readLastCpDialogView(targetCrs);
    if (saved && isViewCompatibleWithCrs(saved, targetCrs)) {
      cpMap.setView([saved.lat, saved.lon], clampZoom(saved.zoom));
    } else {
      const fallback = crsDefaultView(targetCrs);
      cpMap.setView([fallback.lat, fallback.lon], clampZoom(fallback.zoom));
    }
    applyCheckpointDialogBaseLayer();
    return;
  }
  if (cpDialogCurrentCrs !== targetCrs) {
    const previousView = createCpDialogMap(targetCrs);
    applyCheckpointDialogBaseLayer();
    const saved = readLastCpDialogView(targetCrs);
    if (saved && isViewCompatibleWithCrs(saved, targetCrs)) {
      cpMap.setView([saved.lat, saved.lon], clampZoom(saved.zoom));
    } else if (previousView && isViewCompatibleWithCrs(previousView, targetCrs)) {
      cpMap.setView([previousView.lat, previousView.lon], clampZoom(previousView.zoom));
    } else {
      const fallback = crsDefaultView(targetCrs);
      cpMap.setView([fallback.lat, fallback.lon], clampZoom(fallback.zoom));
    }
    return;
  }
  applyCheckpointDialogBaseLayer();
}

function applyCheckpointDialogBaseLayer() {
  if (!cpMap) return;
  const layerCfg = resolveBaseMapLayerForSelection("cpDialogMapLayerSelect", lastCpDialogMapLayerKey);
  if (!layerCfg) return;
  const usesOverlay = overlaySelectionUsesComposite("cpDialogMapLayerSelect", lastCpDialogMapLayerKey);
  if (cpBaseLayer) {
    if (typeof cpBaseLayer.removeFrom === "function") cpBaseLayer.removeFrom(cpMap);
    else cpMap.removeLayer(cpBaseLayer);
  }
  cpBaseLayer = createConfiguredTileLayer(baseLayerConfigForSelection(layerCfg, usesOverlay), cpMap);
  if (cpBaseLayer && typeof cpBaseLayer.addTo === "function") cpBaseLayer.addTo(cpMap);
  applyCompetitionOverlayToMap(cpMap, "dialog");
}

function selectedMapLayerCode(selectId = "cpOverviewMapLayerSelect", storageKey = lastCpOverviewMapLayerKey) {
  const sel = byId(selectId);
  const v = (sel?.value || "").trim();
  if (v) return v;
  const remembered = localStorage.getItem(storageKey) || "";
  return remembered.trim();
}

function resolveSelectedMapLayer(selectId = "cpOverviewMapLayerSelect", storageKey = lastCpOverviewMapLayerKey) {
  const code = selectedMapLayerCode(selectId, storageKey);
  const found = availableMapLayers.find((x) => String(x.code) === code);
  return found || availableMapLayers[0] || null;
}

function createCpOverviewMap(targetCrs) {
  let previousView = null;
  if (cpOverviewMap) {
    const c = cpOverviewMap.getCenter();
    const z = cpOverviewMap.getZoom();
    if (Number.isFinite(Number(c?.lat)) && Number.isFinite(Number(c?.lng)) && Number.isFinite(Number(z))) {
      previousView = { lat: Number(c.lat), lon: Number(c.lng), zoom: Number(z) };
    }
    cpOverviewMap.off("moveend", writeLastCpOverviewView);
    cpOverviewMap.remove();
    cpOverviewMap = null;
    cpOverviewBaseLayer = null;
    cpOverviewOverlayLayer = null;
    cpOverviewLayer = null;
    cpOverviewRoutesLayer = null;
    cpOverviewZoomHandler = null;
    cpOverviewMarkers = [];
  }
  const options = { zoomControl: true, dragging: true, scrollWheelZoom: true };
  const customCrs = createCustomCrs(targetCrs);
  if (customCrs) options.crs = customCrs;
  cpOverviewMap = L.map("cpOverviewMap", options);
  cpOverviewLayer = L.layerGroup().addTo(cpOverviewMap);
  cpOverviewRoutesLayer = L.layerGroup().addTo(cpOverviewMap);
  cpOverviewMap.on("moveend", writeLastCpOverviewView);
  cpOverviewCurrentCrs = targetCrs;
  return previousView;
}

function applyCheckpointOverviewBaseLayer() {
  if (!cpOverviewMap) return;
  const layerCfg = resolveBaseMapLayerForSelection();
  if (!layerCfg) return;
  const usesOverlay = overlaySelectionUsesComposite();
  if (cpOverviewBaseLayer) {
    if (typeof cpOverviewBaseLayer.removeFrom === "function") cpOverviewBaseLayer.removeFrom(cpOverviewMap);
    else cpOverviewMap.removeLayer(cpOverviewBaseLayer);
  }
  cpOverviewBaseLayer = createConfiguredTileLayer(baseLayerConfigForSelection(layerCfg, usesOverlay), cpOverviewMap);
  if (cpOverviewBaseLayer && typeof cpOverviewBaseLayer.addTo === "function") cpOverviewBaseLayer.addTo(cpOverviewMap);
  applyCompetitionOverlayToMap(cpOverviewMap, "overview");
}

async function loadMapLayersConfig() {
  if (baseMapLayers.length) {
    refreshAdminMapLayerOptions();
    return availableMapLayers;
  }
  const d = await get("/api/map-layers");
  const items = Array.isArray(d?.items) ? d.items : [];
  baseMapLayers = items
    .map((x) => ({
      code: String(x?.code || "").trim(),
      label: String(x?.label || "").trim(),
      url_template: String(x?.url_template || "").trim(),
      attribution: String(x?.attribution || "").trim(),
      max_zoom: Number(x?.max_zoom || 19),
      min_zoom: Number(x?.min_zoom || 0),
      tms: !!x?.tms,
      tile_size: Number(x?.tile_size || 256),
      layer_type: String(x?.layer_type || "xyz").trim().toLowerCase(),
      wms_layers: String(x?.wms_layers || "").trim(),
      wms_format: String(x?.wms_format || "").trim(),
      wms_transparent: !!x?.wms_transparent,
      wms_version: String(x?.wms_version || "").trim(),
      wmts_matrix_set: String(x?.wmts_matrix_set || "").trim(),
      wmts_zoom_offset: Number(x?.wmts_zoom_offset || 0),
      fallback_url_template: String(x?.fallback_url_template || "").trim(),
      fallback_tile_size: Number(x?.fallback_tile_size || 0),
      fallback_wmts_matrix_set: String(x?.fallback_wmts_matrix_set || "").trim(),
      fallback_wmts_zoom_offset: Number(x?.fallback_wmts_zoom_offset || 0),
      fallback_zoom_threshold: Number(x?.fallback_zoom_threshold || 0),
      crs: String(x?.crs || "").trim().toUpperCase(),
      participant_default: !!x?.participant_default,
    }))
    .filter((x) => x.code && x.label && x.url_template);
  if (!baseMapLayers.length) {
    baseMapLayers = [{
      code: "osm",
      label: "OpenStreetMap",
      url_template: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
      attribution: "&copy; OpenStreetMap contributors",
      max_zoom: 19,
      min_zoom: 0,
      tms: false,
      layer_type: "xyz",
      wms_layers: "",
      wms_format: "",
      wms_transparent: false,
      wms_version: "",
      crs: "",
    }];
  }
  refreshAdminMapLayerOptions();
  return availableMapLayers;
}

function initCheckpointOverviewMap() {
  if (cpOverviewMap) return;
  createCpOverviewMap("EPSG:3857");
  cpOverviewMap.setView([58.6, 25.0], 7);
  applyCheckpointOverviewBaseLayer();
}

function readLastCpOverviewView() {
  try {
    const raw = localStorage.getItem(cpOverviewViewStorageKey()) || localStorage.getItem(lastCpOverviewViewKey());
    if (!raw) return null;
    const d = JSON.parse(raw);
    if (!d || !Number.isFinite(Number(d.lat)) || !Number.isFinite(Number(d.lon)) || !Number.isFinite(Number(d.zoom))) return null;
    return { lat: Number(d.lat), lon: Number(d.lon), zoom: Number(d.zoom) };
  } catch (_e) {
    return null;
  }
}

function writeLastCpOverviewView() {
  if (!cpOverviewMap) return;
  const center = cpOverviewMap.getCenter();
  const zoom = cpOverviewMap.getZoom();
  if (!Number.isFinite(Number(center.lat)) || !Number.isFinite(Number(center.lng)) || !Number.isFinite(Number(zoom))) return;
  const payload = JSON.stringify({ lat: Number(center.lat), lon: Number(center.lng), zoom: Number(zoom) });
  localStorage.setItem(cpOverviewViewStorageKey(), payload);
  localStorage.setItem(lastCpOverviewViewKey(), payload);
}

function effectiveCheckpointRadius(row) {
  const cpRadius = Number(row?.radius_m);
  if (Number.isFinite(cpRadius) && cpRadius > 0) return { radius: cpRadius, fallback: false };
  const compRadius = Number(window.__lastCompetitionRadiusM);
  if (Number.isFinite(compRadius) && compRadius > 0) return { radius: compRadius, fallback: true };
  return { radius: null, fallback: false };
}

function buildCheckpointMapPoints(excludeCheckpointId = null) {
  const byCheckpoint = new Map();
  checkpointsData.forEach((r) => {
    const cpId = Number(r.checkpoint_id);
    const lat = Number(r.latitude);
    const lon = Number(r.longitude);
    if (!Number.isFinite(cpId) || !Number.isFinite(lat) || !Number.isFinite(lon)) return;
    if (excludeCheckpointId != null && cpId === Number(excludeCheckpointId)) return;
    if (byCheckpoint.has(cpId)) return;
    const radiusInfo = effectiveCheckpointRadius(r);
    const locationRequired = String(r.location_required || "N").toUpperCase() === "Y";
    const rawOrder = r.checkpoint_order_no ?? r.order_no;
    const orderNo = Number.isFinite(Number(rawOrder)) ? Number(rawOrder) : null;
    const checkpointType = normalizeCheckpointType(r.checkpoint_type);
    byCheckpoint.set(cpId, {
      checkpointId: cpId,
      questionId: Number.isFinite(Number(r.question_id)) ? Number(r.question_id) : null,
      title: String(r.checkpoint_title || ""),
      checkpointType,
      questionType: String(r.question_type || ""),
      points: Number.isFinite(Number(r.points)) ? Number(r.points) : 0,
      wrongPoints: Number.isFinite(Number(r.wrong_points)) ? Number(r.wrong_points) : 0,
      questionTexts: {
        et: String(r.text_et || ""),
        en: String(r.text_en || "")
      },
      options: Array.isArray(r.options) ? r.options : [],
      answers: Array.isArray(r.answers) ? r.answers : [],
      lat,
      lon,
      orderNo,
      markerColor: locationRequired ? "#c0392b" : "#7d3c98",
      markerRadiusPx: 15,
      markerWeight: 3,
      ringColor: radiusInfo.fallback ? "#f1c40f" : "#2f7f87",
      ringWeight: 2,
      ringRadiusM: Number.isFinite(Number(radiusInfo.radius)) && Number(radiusInfo.radius) > 0 ? Number(radiusInfo.radius) : null
    });
  });
  return Array.from(byCheckpoint.values());
}

function shouldShowCheckpointOrderLabel(point) {
  if (String(currentCompetitionType || "R").toUpperCase() !== "S") return false;
  if (!point || isSpecialCheckpointType(point.checkpointType)) return false;
  return Number.isFinite(Number(point.orderNo));
}

function localizedCheckpointQuestionText(point) {
  const wanted = String(currentUiLang || defaultLang || "et").toLowerCase();
  const fallback = String(defaultLang || "et").toLowerCase();
  const texts = [point?.questionTexts || {}, point?.optionTexts || {}];
  const read = (bucket, lang) => String(bucket?.[lang] || "").trim();
  for (const bucket of texts) {
    const wantedValue = read(bucket, wanted);
    if (wantedValue) return wantedValue;
    const fallbackValue = read(bucket, fallback);
    if (fallbackValue) return fallbackValue;
    const etValue = read(bucket, "et");
    if (etValue) return etValue;
    const enValue = read(bucket, "en");
    if (enValue) return enValue;
    const anyValue = Object.values(bucket || {}).find((value) => String(value || "").trim());
    if (anyValue) return String(anyValue).trim();
  }
  return "";
}

function localizedOptionText(option) {
  const wanted = String(currentUiLang || defaultLang || "et").toLowerCase();
  const fallback = String(defaultLang || "et").toLowerCase();
  const wantedValue = String(option?.[`text_${wanted}`] || "").trim();
  if (wantedValue) return wantedValue;
  const fallbackValue = String(option?.[`text_${fallback}`] || "").trim();
  if (fallbackValue) return fallbackValue;
  const etValue = String(option?.text_et || "").trim();
  if (etValue) return etValue;
  const enValue = String(option?.text_en || "").trim();
  if (enValue) return enValue;
  return "";
}

function questionTypeShort(point) {
  return String(point?.questionType || "").toUpperCase() === "SINGLE_CHOICE" ? "SC" : "T";
}

function checkpointPopupText(point) {
  const orderPrefix = shouldShowCheckpointOrderLabel(point) ? `${point.orderNo}. ` : "";
  const radiusSuffix = Number.isFinite(point?.ringRadiusM) && point.ringRadiusM > 0 ? ` (${point.ringRadiusM} m)` : "";
  const firstLine = `${orderPrefix}${esc(point?.title || "")}${radiusSuffix}`;
  if (!point?.questionId) {
    return `<div class="cp-map-popup-content"><div class="cp-map-popup-line cp-map-popup-title">${firstLine}</div></div>`;
  }
  const questionText = esc(localizedCheckpointQuestionText(point));
  const questionMeta = `${questionTypeShort(point)} ${Number(point?.points || 0)} / ${Number(point?.wrongPoints || 0)}`;
  let thirdLine = "";
  if (String(point?.questionType || "").toUpperCase() === "SINGLE_CHOICE") {
    const optionHtml = (Array.isArray(point?.options) ? point.options : [])
      .map((option) => {
        const text = esc(localizedOptionText(option));
        if (!text) return "";
        return option?.is_correct === "Y" ? `<strong>${text}</strong>` : text;
      })
      .filter(Boolean)
      .join(" · ");
    if (optionHtml) thirdLine = `<div class="cp-map-popup-line cp-map-popup-meta">${optionHtml}</div>`;
  } else {
    const answers = (Array.isArray(point?.answers) ? point.answers : [])
      .map((answer) => esc(String(answer?.answer_value || "").trim()))
      .filter(Boolean)
      .join(" · ");
    if (answers) thirdLine = `<div class="cp-map-popup-line cp-map-popup-meta">${answers}</div>`;
  }
  return `<div class="cp-map-popup-content"><div class="cp-map-popup-line cp-map-popup-title">${firstLine}</div><div class="cp-map-popup-line cp-map-popup-question">${questionText} (${esc(questionMeta)})</div>${thirdLine}</div>`;
}

function specialCheckpointSvg(point) {
  const stroke = esc(point.markerColor || "#7d3c98");
  const weight = Math.max(2, Number(point.markerWeight || 3));
  const haloWeight = weight + 4;
  if (point.checkpointType === "START") {
    return `<svg width="36" height="36" viewBox="0 0 36 36" aria-hidden="true"><polygon points="18,5 31,29 5,29" fill="none" stroke="#ffffff" stroke-width="${haloWeight}" stroke-linejoin="round"/><polygon points="18,5 31,29 5,29" fill="none" stroke="${stroke}" stroke-width="${weight}" stroke-linejoin="round"/></svg>`;
  }
  return `<svg width="42" height="42" viewBox="0 0 42 42" aria-hidden="true"><circle cx="21" cy="21" r="15" fill="none" stroke="#ffffff" stroke-width="${haloWeight}"/><circle cx="21" cy="21" r="20" fill="none" stroke="#ffffff" stroke-width="${haloWeight}"/><circle cx="21" cy="21" r="15" fill="none" stroke="${stroke}" stroke-width="${weight}"/><circle cx="21" cy="21" r="20" fill="none" stroke="${stroke}" stroke-width="${weight}"/></svg>`;
}

function createCheckpointShapeMarker(point, extraOptions = {}) {
  const baseOptions = {
    color: point.markerColor,
    weight: point.markerWeight || 3,
    fillOpacity: 0,
    ...extraOptions
  };
  if (point.checkpointType === "START" || point.checkpointType === "FINISH") {
    return L.marker([point.lat, point.lon], {
      icon: L.divIcon({
        className: "cp-special-div-icon",
        html: specialCheckpointSvg(point),
        iconSize: point.checkpointType === "FINISH" ? [42, 42] : [36, 36],
        iconAnchor: point.checkpointType === "FINISH" ? [21, 21] : [18, 18],
        popupAnchor: point.checkpointType === "FINISH" ? [0, -21] : [0, -18]
      }),
      ...extraOptions
    });
  }
  return L.circleMarker([point.lat, point.lon], {
    radius: point.markerRadiusPx || 15,
    ...baseOptions
  });
}

function addCheckpointShapeMarker(targetLayer, point, extraOptions = {}) {
  if (point.checkpointType !== "START" && point.checkpointType !== "FINISH") {
    L.circleMarker([point.lat, point.lon], {
      radius: point.markerRadiusPx || 15,
      color: "#ffffff",
      weight: (point.markerWeight || 3) + 4,
      fillOpacity: 0,
      interactive: false
    }).addTo(targetLayer);
  }
  const marker = createCheckpointShapeMarker(point, extraOptions).addTo(targetLayer);
  marker.__checkpointId = point.checkpointId;
  return marker;
}

function drawRouteSegment(layerRef, mapRef, seg, t0, t1) {
  if (t1 <= t0) return;
  const pA = L.point(seg.sx + (seg.ex - seg.sx) * t0, seg.sy + (seg.ey - seg.sy) * t0);
  const pB = L.point(seg.sx + (seg.ex - seg.sx) * t1, seg.sy + (seg.ey - seg.sy) * t1);
  const latLngs = [mapRef.layerPointToLatLng(pA), mapRef.layerPointToLatLng(pB)];
  L.polyline(latLngs, {
    color: "#ffffff",
    weight: seg.weight + 2,
    opacity: 0.95,
    interactive: false
  }).addTo(layerRef);
  L.polyline(latLngs, {
    color: seg.color,
    weight: seg.weight,
    opacity: 0.95,
    interactive: false
  }).addTo(layerRef);
}

function drawRouteForOrderedPoints(mapRef, layerRef, orderedPoints) {
  if (!mapRef || !layerRef) return;
  layerRef.clearLayers();
  const ordered = (orderedPoints || [])
    .filter((p) => Number.isFinite(Number(p.orderNo)) && Number.isFinite(Number(p.lat)) && Number.isFinite(Number(p.lon)))
    .sort((a, b) => Number(a.orderNo) - Number(b.orderNo) || Number(a.checkpointId) - Number(b.checkpointId));
  if (ordered.length < 2) return;

  const withPixels = ordered.map((p) => {
    const ringRadiusPx = Number.isFinite(Number(p.markerRadiusPx)) ? Number(p.markerRadiusPx) : 15;
    return { ...p, ringRadiusPx };
  });

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
      sx, sy, ex, ey, ux: (ex - sx) / segLen, uy: (ey - sy) / segLen, len: segLen
    });
  }

  const tBreaks = new Map();
  const keyFor = (idx) => String(idx);
  const addBreak = (idx, t0, t1) => {
    const k = keyFor(idx);
    if (!tBreaks.has(k)) tBreaks.set(k, []);
    tBreaks.get(k).push([Math.max(0, t0), Math.min(1, t1)]);
  };
  const cross = (ax, ay, bx, by) => ax * by - ay * bx;

  for (let a = 0; a < segments.length; a += 1) {
    for (let b = a + 1; b < segments.length; b += 1) {
      const s1 = segments[a];
      const s2 = segments[b];
      const shareEndpoint = Math.abs(s1.orderPairStart - s2.orderPairStart) === 0
        || Math.abs(s1.orderPairStart - s2.orderPairEnd) === 0
        || Math.abs(s1.orderPairEnd - s2.orderPairStart) === 0
        || Math.abs(s1.orderPairEnd - s2.orderPairEnd) === 0;
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
    const s = [...arr].sort((x, y) => x[0] - y[0]);
    const out = [s[0].slice()];
    for (let i = 1; i < s.length; i += 1) {
      const cur = s[i];
      const last = out[out.length - 1];
      if (cur[0] <= last[1]) last[1] = Math.max(last[1], cur[1]);
      else out.push(cur.slice());
    }
    return out.filter((x) => x[1] > x[0]);
  };

  segments.forEach((seg) => {
    const breaks = mergeIntervals(tBreaks.get(keyFor(seg.idx)) || []);
    if (breaks.length === 0) {
      drawRouteSegment(layerRef, mapRef, seg, 0, 1);
      return;
    }
    let cur = 0;
    breaks.forEach(([b0, b1]) => {
      drawRouteSegment(layerRef, mapRef, seg, cur, b0);
      cur = Math.max(cur, b1);
    });
    drawRouteSegment(layerRef, mapRef, seg, cur, 1);
  });
}

function drawOrderedRoutesForPoints(mapRef, layerRef, points) {
  if (String(currentCompetitionType || "R").toUpperCase() !== "S") {
    if (layerRef?.clearLayers) layerRef.clearLayers();
    return;
  }
  const ordered = (points || [])
    .filter((p) => Number.isFinite(Number(p.orderNo)));
  drawRouteForOrderedPoints(mapRef, layerRef, ordered);
}

function buildCalculatedRoutePoints(points, routeSnapshot) {
  const orderItems = Array.isArray(routeSnapshot?.route_order_json) ? routeSnapshot.route_order_json : [];
  if (!orderItems.length) return [];
  const byCheckpointId = new Map((points || []).map((point) => [Number(point.checkpointId), point]));
  return orderItems.map((item, index) => {
    const cpId = Number(item?.checkpoint_id);
    const base = byCheckpointId.get(cpId);
    if (!base) return null;
    const seq = Number(item?.seq);
    return {
      ...base,
      orderNo: Number.isFinite(seq) ? seq : index + 1,
    };
  }).filter(Boolean);
}

function renderCheckpointOverviewRoute(points) {
  if (!cpOverviewRoutesLayer) return;
  if (!cpOverviewRouteVisible) {
    cpOverviewRoutesLayer.clearLayers();
    return;
  }
  if (String(currentCompetitionType || "R").toUpperCase() === "S") {
    drawOrderedRoutesForPoints(cpOverviewMap, cpOverviewRoutesLayer, points);
    return;
  }
  const routeSnapshot = window.__lastCompetitionRoute;
  const ordered = buildCalculatedRoutePoints(points, routeSnapshot);
  drawRouteForOrderedPoints(cpOverviewMap, cpOverviewRoutesLayer, ordered);
}

function setCheckpointOverviewRouteVisible(visible) {
  cpOverviewRouteVisible = !!visible;
  return cpOverviewRouteVisible;
}

function isCheckpointOverviewRouteVisible() {
  return !!cpOverviewRouteVisible;
}

function refreshCheckpointOverviewRouteDisplay() {
  if (!cpOverviewMap || !cpOverviewRoutesLayer) return;
  const points = buildCheckpointMapPoints();
  renderCheckpointOverviewRoute(points);
}

function buildOrderLabelPlacement(mapRef, points) {
  const placements = new Map();
  (points || []).forEach((p) => {
    placements.set(Number(p.checkpointId), { direction: "right", offset: [12, 0] });
  });
  if (!mapRef || String(currentCompetitionType || "R").toUpperCase() !== "S") return placements;
  try {
    if (!mapRef._loaded) return placements;
  } catch (_e) {
    return placements;
  }

  const ordered = (points || [])
    .filter((p) => Number.isFinite(Number(p.orderNo)))
    .sort((a, b) => Number(a.orderNo) - Number(b.orderNo) || Number(a.checkpointId) - Number(b.checkpointId));
  if (ordered.length === 0) return placements;

  const unit = (ax, ay, bx, by) => {
    const dx = bx - ax;
    const dy = by - ay;
    const len = Math.hypot(dx, dy);
    if (!Number.isFinite(len) || len <= 0) return { x: 0, y: 0 };
    return { x: dx / len, y: dy / len };
  };

  for (let i = 0; i < ordered.length; i += 1) {
    const cur = ordered[i];
    const curP = mapRef.latLngToLayerPoint([cur.lat, cur.lon]);
    let sumX = 0;
    let sumY = 0;
    if (i > 0) {
      const prev = ordered[i - 1];
      const prevP = mapRef.latLngToLayerPoint([prev.lat, prev.lon]);
      const v = unit(curP.x, curP.y, prevP.x, prevP.y);
      sumX += v.x;
      sumY += v.y;
    }
    if (i < ordered.length - 1) {
      const next = ordered[i + 1];
      const nextP = mapRef.latLngToLayerPoint([next.lat, next.lon]);
      const v = unit(curP.x, curP.y, nextP.x, nextP.y);
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
      offset: [Math.round(dx * 18), Math.round(dy * 18)]
    });
  }
  return placements;
}

async function openCheckpointOverviewMap() {
  await loadMapLayersConfig();
  const layerCfg = resolveSelectedMapLayer();
  const targetCrs = selectedMapCrsCode(layerCfg);
  let carryView = null;
  if (!cpOverviewMap || cpOverviewCurrentCrs !== targetCrs) {
    carryView = createCpOverviewMap(targetCrs);
  }
  initCheckpointOverviewMap();
  applyCheckpointOverviewBaseLayer();
  cpOverviewLayer.clearLayers();
  if (cpOverviewRoutesLayer) cpOverviewRoutesLayer.clearLayers();
  cpOverviewMarkers = [];
  const points = buildCheckpointMapPoints();
  const savedView = readLastCpOverviewView();
  if (points.length === 0) {
    const fallback = crsDefaultView(targetCrs);
    cpOverviewMap.setView([fallback.lat, fallback.lon], fallback.zoom);
  } else {
    const bounds = [];
    points.forEach((p) => {
      const m = addCheckpointShapeMarker(cpOverviewLayer, p);
      m.bindPopup(checkpointPopupText(p), { autoClose: false, closeOnClick: false, className: "cp-map-popup", maxWidth: 280 });
      cpOverviewMarkers.push(m);
      if (Number.isFinite(p.ringRadiusM) && p.ringRadiusM > 0) {
        L.circle([p.lat, p.lon], {
          radius: p.ringRadiusM,
          color: p.ringColor,
          weight: p.ringWeight,
          fillColor: p.ringColor,
          fillOpacity: 0.12,
          interactive: false,
          pane: ensureCheckpointRadiusPane(cpOverviewMap, "overview") || undefined
        }).addTo(cpOverviewLayer);
      }
      bounds.push([p.lat, p.lon]);
    });
    if (savedView && isViewCompatibleWithCrs(savedView, targetCrs)) {
      cpOverviewMap.setView([savedView.lat, savedView.lon], savedView.zoom);
    } else if (carryView && isViewCompatibleWithCrs(carryView, targetCrs)) {
      const maxZoom = crsMaxOverviewZoom(targetCrs);
      const clamped = Math.max(0, Math.min(maxZoom, carryView.zoom));
      cpOverviewMap.setView([carryView.lat, carryView.lon], clamped);
    } else {
      cpOverviewMap.fitBounds(bounds, { padding: [30, 30], maxZoom: crsMaxOverviewZoom(targetCrs) });
    }
    const labelPlacement = buildOrderLabelPlacement(cpOverviewMap, points);
    cpOverviewMarkers.forEach((m) => {
      const cpIdRaw = m?.__checkpointId;
      if (!Number.isFinite(Number(cpIdRaw))) return;
      const cpId = Number(cpIdRaw);
      const p = points.find((x) => Number(x.checkpointId) === cpId);
      if (!shouldShowCheckpointOrderLabel(p)) return;
      const placement = labelPlacement.get(cpId) || { direction: "right", offset: [12, 0] };
      m.unbindTooltip();
      m.bindTooltip(String(p.orderNo), {
        permanent: true,
        direction: placement.direction,
        offset: placement.offset,
        className: p.markerColor === "#c0392b" ? "cp-order-tooltip cp-order-red" : "cp-order-tooltip cp-order-purple"
      });
    });
    renderCheckpointOverviewRoute(points);
    if (cpOverviewZoomHandler) cpOverviewMap.off("zoomend", cpOverviewZoomHandler);
    cpOverviewZoomHandler = () => {
      renderCheckpointOverviewRoute(points);
      const nextPlacement = buildOrderLabelPlacement(cpOverviewMap, points);
      cpOverviewMarkers.forEach((m) => {
        const cpIdRaw = m?.__checkpointId;
        if (!Number.isFinite(Number(cpIdRaw))) return;
        const cpId = Number(cpIdRaw);
        const p = points.find((x) => Number(x.checkpointId) === cpId);
        if (!shouldShowCheckpointOrderLabel(p)) return;
        const placement = nextPlacement.get(cpId) || { direction: "right", offset: [12, 0] };
        m.unbindTooltip();
        m.bindTooltip(String(p.orderNo), {
          permanent: true,
          direction: placement.direction,
          offset: placement.offset,
          className: p.markerColor === "#c0392b" ? "cp-order-tooltip cp-order-red" : "cp-order-tooltip cp-order-purple"
        });
      });
    };
    cpOverviewMap.on("zoomend", cpOverviewZoomHandler);
  }
  byId("cpOverviewMapDialog").showModal();
  setTimeout(() => {
    cpOverviewMap.invalidateSize();
    if (typeof cpOverviewZoomHandler === "function") cpOverviewZoomHandler();
  }, 50);
}

function setCheckpointOverviewSize(fullscreen) {
  cpOverviewFullscreen = !!fullscreen;
  const dlg = byId("cpOverviewMapDialog");
  dlg.classList.toggle("fullscreen", cpOverviewFullscreen);
  byId("cpOverviewMapToggleSizeBtn").textContent = cpOverviewFullscreen
    ? tr("admin.common.restore_btn")
    : tr("admin.cp_overview.expand_btn");
  setTimeout(() => {
    if (cpOverviewMap) cpOverviewMap.invalidateSize();
  }, 30);
}

function setCheckpointDialogSize(fullscreen) {
  cpDialogFullscreen = !!fullscreen;
  const dlg = byId("cpDialog");
  dlg.classList.toggle("fullscreen", cpDialogFullscreen);
  byId("cpMapToggleSizeBtn").textContent = cpDialogFullscreen
    ? tr("admin.common.restore_btn")
    : tr("admin.cp_dialog.expand_btn");
  setTimeout(() => {
    if (cpMap) cpMap.invalidateSize();
  }, 30);
}

function openAllCheckpointLabels() {
  cpOverviewMarkers.forEach((m) => m.openPopup());
}

function closeAllCheckpointLabels() {
  cpOverviewMarkers.forEach((m) => m.closePopup());
}

function effectiveRadiusMeters() {
  const cpRaw = (byId("cpRadiusM").value || "").trim();
  if (cpRaw !== "") {
    const cpVal = Number(cpRaw);
    if (Number.isFinite(cpVal) && cpVal > 0) return cpVal;
  }
  const compVal = Number(window.__lastCompetitionRadiusM);
  if (Number.isFinite(compVal) && compVal > 0) return compVal;
  return null;
}

function syncRadiusCircle() {
  if (!cpMap || !cpMarker || currentCompetitionUseLocation !== "Y") return;
  const r = effectiveRadiusMeters();
  if (!r) {
    if (cpRadiusCircle) {
      cpMap.removeLayer(cpRadiusCircle);
      cpRadiusCircle = null;
    }
    return;
  }
  const center = cpMarker.getLatLng();
  if (!cpRadiusCircle) {
    cpRadiusCircle = L.circle(center, {
      radius: r,
      color: "#2f7f87",
      weight: 2,
      fillColor: "#2f7f87",
      fillOpacity: 0.15,
      pane: ensureCheckpointRadiusPane(cpMap, "dialog") || undefined
    }).addTo(cpMap);
  } else {
    cpRadiusCircle.setLatLng(center);
    cpRadiusCircle.setRadius(r);
  }
}

function renderExistingCheckpointsOnDialogMap() {
  if (!cpMap || !cpExistingLayer) return;
  cpExistingLayer.clearLayers();
  if (cpExistingRoutesLayer) cpExistingRoutesLayer.clearLayers();
  if (!cpExistingVisible || currentCompetitionUseLocation !== "Y") return;
  const currentId = Number(byId("cpId").value || 0);
  const points = buildCheckpointMapPoints(currentId);
  const labelPlacement = buildOrderLabelPlacement(cpMap, points);
  points.forEach((p) => {
    const marker = addCheckpointShapeMarker(cpExistingLayer, p);
    if (shouldShowCheckpointOrderLabel(p)) {
      const placement = labelPlacement.get(Number(p.checkpointId)) || { direction: "right", offset: [12, 0] };
      marker.bindTooltip(String(p.orderNo), {
        permanent: true,
        direction: placement.direction,
        offset: placement.offset,
        className: p.markerColor === "#c0392b" ? "cp-order-tooltip cp-order-red" : "cp-order-tooltip cp-order-purple"
      });
    }
    marker.bindPopup(checkpointPopupText(p), { className: "cp-map-popup", maxWidth: 280 });
    if (Number.isFinite(p.ringRadiusM) && p.ringRadiusM > 0) {
      L.circle([p.lat, p.lon], {
        radius: p.ringRadiusM,
        color: p.ringColor,
        weight: p.ringWeight,
        fillColor: p.ringColor,
        fillOpacity: 0.12,
        interactive: false,
        pane: ensureCheckpointRadiusPane(cpMap, "dialog") || undefined
      }).addTo(cpExistingLayer);
    }
  });
  drawOrderedRoutesForPoints(cpMap, cpExistingRoutesLayer, points);
  if (cpExistingZoomHandler) cpMap.off("zoomend", cpExistingZoomHandler);
  cpExistingZoomHandler = () => {
    if (!cpExistingVisible) return;
    drawOrderedRoutesForPoints(cpMap, cpExistingRoutesLayer, points);
    const nextPlacement = buildOrderLabelPlacement(cpMap, points);
    cpExistingLayer.eachLayer((layer) => {
      const cpIdRaw = layer?.__checkpointId;
      if (!Number.isFinite(Number(cpIdRaw))) return;
      const p = points.find((x) => Number(x.checkpointId) === Number(cpIdRaw));
      if (!shouldShowCheckpointOrderLabel(p)) return;
      const placement = nextPlacement.get(Number(p.checkpointId)) || { direction: "right", offset: [12, 0] };
      layer.unbindTooltip();
      layer.bindTooltip(String(p.orderNo), {
        permanent: true,
        direction: placement.direction,
        offset: placement.offset,
        className: p.markerColor === "#c0392b" ? "cp-order-tooltip cp-order-red" : "cp-order-tooltip cp-order-purple"
      });
    });
  };
  cpMap.on("zoomend", cpExistingZoomHandler);
}

function setExistingCheckpointsVisible(visible) {
  cpExistingVisible = !!visible;
  byId("cpToggleExistingBtn").textContent = cpExistingVisible ? "Peida olemasolevad KP-d" : "Olemasolevad KP-d";
  renderExistingCheckpointsOnDialogMap();
}

function setCpCoordinates(lat, lon, moveMap = false) {
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;
  const lat6 = Number(lat).toFixed(6);
  const lon6 = Number(lon).toFixed(6);
  byId("cpLatitude").value = lat6;
  byId("cpLongitude").value = lon6;
  if (!cpMap) return;
  if (!cpMarker) {
    cpMarker = L.marker([Number(lat6), Number(lon6)], { draggable: true }).addTo(cpMap);
    cpMarker.on("dragend", () => {
      const p = cpMarker.getLatLng();
      setCpCoordinates(p.lat, p.lng, false);
    });
  } else {
    cpMarker.setLatLng([Number(lat6), Number(lon6)]);
  }
  syncRadiusCircle();
  if (moveMap) cpMap.setView([Number(lat6), Number(lon6)], Math.max(cpMap.getZoom(), 15));
}

function syncMapFromCoordInputs() {
  const lat = Number(byId("cpLatitude").value);
  const lon = Number(byId("cpLongitude").value);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;
  setCpCoordinates(lat, lon, false);
}

function readLastCpCoord() {
  try {
    const raw = localStorage.getItem(lastCpCoordKey());
    if (!raw) return null;
    const d = JSON.parse(raw);
    if (!d || !Number.isFinite(Number(d.lat)) || !Number.isFinite(Number(d.lon))) return null;
    return { lat: Number(d.lat), lon: Number(d.lon) };
  } catch (_e) {
    return null;
  }
}

function writeLastCpCoord(lat, lon) {
  if (!Number.isFinite(Number(lat)) || !Number.isFinite(Number(lon))) return;
  localStorage.setItem(lastCpCoordKey(), JSON.stringify({ lat: Number(lat), lon: Number(lon) }));
}
