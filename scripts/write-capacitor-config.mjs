import fs from "node:fs/promises";
import path from "node:path";

const mode = String(process.argv[2] || process.env.FUNO_COMPETITOR_APP_MODE || "hosted").trim().toLowerCase();
const rootDir = process.cwd();
const configPath = path.join(rootDir, "capacitor.config.json");
const runtimeConfigPath = path.join(rootDir, "frontend_dist", "assets", "competitor-app-config.js");
const hostedUrl = String(process.env.FUNO_COMPETITOR_APP_URL || "").trim();
const bundledApiBaseUrl = String(process.env.FUNO_COMPETITOR_API_BASE_URL || "").trim();
const cleartext = String(process.env.FUNO_COMPETITOR_APP_ALLOW_CLEARTEXT || "").trim().toLowerCase() === "true";
const buildMode = String(process.env.FUNO_COMPETITOR_APP_BUILD || "debug").trim().toLowerCase();
const webDebuggingEnabled = buildMode !== "release";

if (!["hosted", "bundled"].includes(mode)) {
  throw new Error(`Unknown Capacitor mode "${mode}". Use "hosted" or "bundled".`);
}

if (mode === "hosted" && !hostedUrl) {
  throw new Error(
    "FUNO_COMPETITOR_APP_URL is required for hosted mode. Example: https://funo.example.com/index.html"
  );
}

if (mode === "bundled" && !bundledApiBaseUrl) {
  throw new Error(
    "FUNO_COMPETITOR_API_BASE_URL is required for bundled mode. Example: https://funo.example.com"
  );
}

function normalizeBaseUrl(url) {
  let normalized = String(url || "").trim();
  while (normalized.endsWith("/")) {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}

const runtimeConfig = {
  apiBaseUrl: mode === "bundled" ? normalizeBaseUrl(bundledApiBaseUrl) : "",
  mode,
};

const config = {
  appId: "ee.funo.competitor",
  appName: "fun_o Competitor",
  webDir: "frontend_dist",
  backgroundColor: "#ffffff",
  appendUserAgent: " fun_o-competitor-app/0.1",
  android: {
    path: "android",
    webContentsDebuggingEnabled: webDebuggingEnabled
  },
  plugins: {
    StatusBar: {
      overlaysWebView: false,
      style: "DARK",
      backgroundColor: "#ffffffff"
    }
  }
};

if (mode === "hosted") {
  config.server = {
    url: hostedUrl,
    cleartext
  };
}

await fs.writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");
await fs.writeFile(
  runtimeConfigPath,
  `globalThis.__FUNO_APP_RUNTIME_CONFIG__ = ${JSON.stringify(runtimeConfig, null, 2)};\n`,
  "utf8"
);
process.stdout.write(`Wrote ${path.basename(configPath)} for ${mode} mode.\n`);
