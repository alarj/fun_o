(function initFunoAppBridge(global) {
  const runtimeConfig = global.__FUNO_APP_RUNTIME_CONFIG__ || {};

  function getCapacitor() {
    return global.Capacitor || null;
  }

  function isNativePlatform() {
    const capacitor = getCapacitor();
    try {
      if (!capacitor || typeof capacitor.isNativePlatform !== "function") return false;
      return capacitor.isNativePlatform();
    } catch {
      return false;
    }
  }

  function getPlugin(name) {
    const capacitor = getCapacitor();
    return capacitor?.Plugins?.[name] || null;
  }

  function toDomPosition(position) {
    const coords = position?.coords || {};
    return {
      coords: {
        latitude: Number(coords.latitude),
        longitude: Number(coords.longitude),
        accuracy: Number(coords.accuracy),
        altitude: coords.altitude ?? null,
        altitudeAccuracy: coords.altitudeAccuracy ?? null,
        heading: coords.heading ?? null,
        speed: coords.speed ?? null,
      },
      timestamp: Number(position?.timestamp || Date.now()),
    };
  }

  function toDomPositionError(error) {
    const domError = new Error(error?.message || "Geolocation failed");
    domError.code = typeof error?.code === "number" ? error.code : 2;
    return domError;
  }

  function normalizeLocationPermissionState(payload) {
    return String(
      payload?.location || payload?.coarseLocation || payload?.permission || ""
    ).toLowerCase();
  }

  async function ensureNativeLocationPermission() {
    const geolocation = getPlugin("Geolocation");
    if (!geolocation) return true;
    if (typeof geolocation.checkPermissions === "function") {
      const permissions = await geolocation.checkPermissions();
      const locationState = normalizeLocationPermissionState(permissions);
      if (locationState === "granted") return true;
    }
    if (typeof geolocation.requestPermissions === "function") {
      const requested = await geolocation.requestPermissions();
      return normalizeLocationPermissionState(requested) === "granted";
    }
    return false;
  }

  function installNativeGeolocationShim() {
    if (!isNativePlatform()) return;
    const geolocation = getPlugin("Geolocation");
    const nativeGeo = global.navigator?.geolocation;
    if (!geolocation?.getCurrentPosition || !geolocation?.watchPosition || !geolocation?.clearWatch || !nativeGeo) {
      return;
    }

    const watchMap = new Map();
    let watchSeq = 1;

    function handleWatchPositionUpdate(success, error, position, err) {
      if (err) {
        if (typeof error === "function") error(toDomPositionError(err));
        return;
      }
      if (position && typeof success === "function") success(toDomPosition(position));
    }

    function cleanupPluginWatch(pluginWatchId) {
      if (!pluginWatchId) return Promise.resolve(null);
      return geolocation.clearWatch({ id: pluginWatchId }).catch(() => {});
    }

    function handleWatchRegistrationFailure(localWatchId, watchState, error, err) {
      if (watchMap.get(localWatchId) === watchState) {
        watchMap.delete(localWatchId);
      }
      if (typeof error === "function") error(toDomPositionError(err));
    }

    function registerPluginWatch(localWatchId, watchState, success, error, options) {
      return geolocation.watchPosition(options || {}, (position, err) => {
        handleWatchPositionUpdate(success, error, position, err);
      }).then((pluginWatchId) => {
        watchState.pluginWatchId = pluginWatchId;
        if (watchState.cancelled) {
          return cleanupPluginWatch(pluginWatchId);
        }
        return null;
      }).catch((err) => {
        handleWatchRegistrationFailure(localWatchId, watchState, error, err);
      });
    }

    nativeGeo.getCurrentPosition = function getCurrentPosition(success, error, options) {
      ensureNativeLocationPermission()
        .then(() => geolocation.getCurrentPosition(options || {}))
        .then((position) => {
          if (typeof success === "function") success(toDomPosition(position));
        })
        .catch((err) => {
          if (typeof error === "function") error(toDomPositionError(err));
        });
    };

    nativeGeo.watchPosition = function watchPosition(success, error, options) {
      const localWatchId = watchSeq++;
      const watchState = {
        cancelled: false,
        pluginWatchId: null,
      };
      watchMap.set(localWatchId, watchState);

      const registrationPromise = ensureNativeLocationPermission()
        .then(() => registerPluginWatch(localWatchId, watchState, success, error, options));
      watchState.registrationPromise = registrationPromise;
      return localWatchId;
    };

    nativeGeo.clearWatch = function clearWatch(localWatchId) {
      const normalizedId = Number(localWatchId);
      const watchState = watchMap.get(normalizedId);
      watchMap.delete(normalizedId);
      if (!watchState) return;
      watchState.cancelled = true;
      if (!watchState.pluginWatchId) return;
      geolocation.clearWatch({ id: watchState.pluginWatchId }).catch(() => {});
    };
  }

  function normalizeBaseUrl(url) {
    if (!url) return "";
    let normalized = String(url);
    while (normalized.endsWith("/")) {
      normalized = normalized.slice(0, -1);
    }
    return normalized;
  }

  function resolveApiUrl(url) {
    const raw = String(url || "");
    if (!raw) return raw;
    if (/^(?:[a-z]+:)?\/\//i.test(raw) || raw.startsWith("data:")) return raw;
    const apiBaseUrl = normalizeBaseUrl(runtimeConfig.apiBaseUrl);
    if (!apiBaseUrl) return raw;
    return raw.startsWith("/") ? `${apiBaseUrl}${raw}` : `${apiBaseUrl}/${raw}`;
  }

  async function lockPortrait() {
    const screenOrientation = getPlugin("ScreenOrientation");
    if (!screenOrientation?.lock) return false;
    try {
      await screenOrientation.lock({ orientation: "portrait" });
      return true;
    } catch {
      return false;
    }
  }

  async function setMapKeepAwake(enabled) {
    const funoApp = getPlugin("FunoApp");
    if (!funoApp?.setMapKeepAwake) return false;
    try {
      await funoApp.setMapKeepAwake({ enabled: !!enabled });
      return true;
    } catch {
      return false;
    }
  }

  async function initialize() {
    if (isNativePlatform()) {
      global.document?.documentElement?.classList?.add("is-capacitor-app");
      installNativeGeolocationShim();
      await lockPortrait();
    }
  }

  global.funoApp = {
    config: runtimeConfig,
    getPlugin,
    initialize,
    isNativePlatform,
    lockPortrait,
    resolveApiUrl,
    setMapKeepAwake,
  };
})(globalThis);
