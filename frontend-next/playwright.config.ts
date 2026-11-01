import { defineConfig, devices } from "@playwright/test";
import { URL_APP, risolviBersaglio } from "./e2e/support/stack";

/**
 * Suite browser Vinea (VPM-LAB-003). Gira SOLO contro uno stack Supabase locale
 * ed effimero e contro un'app costruita qui con le flag Accessori accese nel
 * processo di prova: `risolviBersaglio()` rifiuta qualunque altro bersaglio
 * prima di avviare il server o aprire un browser.
 *
 * Progetti: Chromium desktop esegue tutto; Chromium a 375 px e WebKit eseguono i
 * soli casi marcati `@cross` (sola lettura sullo stesso stato).
 */
const bersaglio = risolviBersaglio();
const inCi = Boolean(process.env.CI);

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  outputDir: "./e2e/artifacts/test-results",
  globalSetup: "./e2e/global-setup.ts",
  globalTeardown: "./e2e/global-teardown.ts",
  // Un solo database condiviso: i casi cambiano interruttori e utenti.
  fullyParallel: false,
  workers: 1,
  forbidOnly: inCi,
  retries: inCi ? 1 : 0,
  timeout: 90_000,
  expect: { timeout: 10_000 },
  reporter: [
    ["list"],
    ["html", { outputFolder: "./e2e/artifacts/report", open: "never" }],
    ["json", { outputFile: "./e2e/artifacts/results.json" }],
  ],
  use: {
    baseURL: URL_APP,
    locale: "it-IT",
    timezoneId: "Europe/Rome",
    // Le trace non contengono credenziali: l'accesso con password avviene in
    // contesti senza tracciamento (vedi `accediDaBrowser`).
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "chromium-desktop", use: { ...devices["Desktop Chrome"] } },
    {
      name: "chromium-mobile-375",
      grep: /@cross/,
      use: { ...devices["Pixel 5"], viewport: { width: 375, height: 812 } },
    },
    { name: "webkit-desktop", grep: /@cross/, use: { ...devices["Desktop Safari"] } },
  ],
  webServer: {
    command: "node scripts/e2e-serve.mjs",
    url: `${URL_APP}/accedi`,
    // Mai riusare un server qualunque: potrebbe avere flag o bersaglio diversi.
    reuseExistingServer: process.env.E2E_REUSE_SERVER === "1",
    timeout: 900_000,
    stdout: "pipe",
    stderr: "pipe",
    env: {
      PORT: String(new URL(URL_APP).port),
      NEXT_PUBLIC_SUPABASE_URL: bersaglio.apiUrl,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: bersaglio.anonKey,
      // Accessori acceso nel solo processo di prova; pagamenti e IA sempre spenti.
      NEXT_PUBLIC_ACCESSORI_ENABLED: "true",
      ACCESSORI_ENABLED: "true",
      NEXT_PUBLIC_ACCESSORI_NAV_MOBILE: "false",
      NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED: "false",
      NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED: "false",
      PAYMENTS_ENABLED: "false",
      NEXT_PUBLIC_AI_UI_ENABLED: "false",
      NEXT_PUBLIC_AI_ACTIONS_ENABLED: "false",
      AI_ENABLED: "false",
      NEXT_TELEMETRY_DISABLED: "1",
    },
  },
});
