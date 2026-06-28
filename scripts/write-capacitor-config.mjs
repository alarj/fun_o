import fs from "node:fs/promises";
import path from "node:path";

const mode = String(process.argv[2] || process.env.FUNO_COMPETITOR_APP_MODE || "hosted").trim().toLowerCase();
const rootDir = process.cwd();
const configPath = path.join(rootDir, "capacitor.config.json");
const hostedUrl = String(process.env.FUNO_COMPETITOR_APP_URL || "").trim();
const cleartext = String(process.env.FUNO_COMPETITOR_APP_ALLOW_CLEARTEXT || "").trim().toLowerCase() === "true";

if (!["hosted", "bundled"].includes(mode)) {
  throw new Error(`Unknown Capacitor mode "${mode}". Use "hosted" or "bundled".`);
}

if (mode === "hosted" && !hostedUrl) {
  throw new Error(
    "FUNO_COMPETITOR_APP_URL is required for hosted mode. Example: https://funo.example.com/index.html"
  );
}

const config = {
  appId: "ee.funo.competitor",
  appName: "fun_o Competitor",
  webDir: "frontend_dist",
  backgroundColor: "#ffffff",
  appendUserAgent: " fun_o-competitor-app/0.1",
  android: {
    path: "android",
    webContentsDebuggingEnabled: true
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
process.stdout.write(`Wrote ${path.basename(configPath)} for ${mode} mode.\n`);
