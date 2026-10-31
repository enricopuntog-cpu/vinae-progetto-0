import { expect, test as base, type Page, type TestInfo } from "@playwright/test";

/**
 * `test` esteso: raccoglie, per ogni pagina osservata, errori della console,
 * eccezioni non gestite, richieste fallite e risposte 5xx dell'app, li allega
 * al report come `diagnostica.json` e fa fallire il caso se ce ne sono di non
 * attesi. Distingue così un difetto applicativo da un esito che sembra verde.
 */

interface Evento {
  tipo: "console" | "pageerror" | "requestfailed" | "http5xx";
  testo: string;
  url: string;
}

export interface Diagnostica {
  osserva: (page: Page, etichetta?: string) => void;
  eventi: Evento[];
  /** Ignora gli eventi il cui testo o URL contiene una di queste stringhe (atteso e motivato nel test). */
  ammetti: (...frammenti: string[]) => void;
}

const abortiTolleratiDalBrowser = /net::ERR_ABORTED|NS_BINDING_ABORTED|cancelled|Load request cancelled/i;

/**
 * Rumore d'infrastruttura noto, ammesso in ogni caso: lo stack di prova non
 * avvia il servizio Realtime (escluso come nel gate CI, `e2e-stack.mjs`), quindi
 * il client non riesce ad aprire il WebSocket. Non è un difetto dell'app.
 */
// Origine dell'API locale (porta compresa) letta dal bersaglio risolto.
const ORIGINE_API = new URL(process.env.E2E_SUPABASE_URL ?? "http://127.0.0.1:54321").origin;

const RUMORE_INFRASTRUTTURA = [
  "/realtime/v1/websocket",
  // Il fallback CSP statico (solo Report-Only, `security-headers.ts`) nomina l'origine
  // Supabase di produzione: sullo stack locale WebKit lo scrive in console per ogni
  // chiamata e il rate limit risponde 429 ai report. Una violazione della CSP
  // effettiva (enforcing, nonce del Proxy) NON contiene «[Report Only]» e fa fallire.
  `[Report Only] Refused to connect to ${ORIGINE_API}`,
  `[Report Only] Refused to load ${ORIGINE_API}`,
  "/api/security/csp-report",
];

/** Nessuna chiave o token finisce nel report: si oscurano apikey e JWT. */
const oscura = (testo: string): string =>
  testo
    .replace(/apikey=[^&\s'"]+/gi, "apikey=<oscurata>")
    .replace(/eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{5,}/g, "<jwt oscurato>");

export const test = base.extend<{ diagnostica: Diagnostica }>({
  diagnostica: [
    async ({ page }, use, info: TestInfo) => {
      const eventi: Evento[] = [];
      const ammessi: string[] = [...RUMORE_INFRASTRUTTURA];
      const osservate = new WeakSet<Page>();

      const osserva = (p: Page, etichetta = "pagina") => {
        if (osservate.has(p)) return;
        osservate.add(p);
        const origine = new URL(info.project.use.baseURL ?? "http://127.0.0.1").origin;
        p.on("console", (m) => {
          if (m.type() === "error") eventi.push({ tipo: "console", testo: `[${etichetta}] ${m.text()}`, url: m.location().url });
        });
        p.on("pageerror", (e) => eventi.push({ tipo: "pageerror", testo: `[${etichetta}] ${e.message}`, url: p.url() }));
        p.on("requestfailed", (r) => {
          const motivo = r.failure()?.errorText ?? "";
          if (!abortiTolleratiDalBrowser.test(motivo)) eventi.push({ tipo: "requestfailed", testo: `[${etichetta}] ${motivo}`, url: r.url() });
        });
        p.on("response", (r) => {
          if (r.status() >= 500 && r.url().startsWith(origine)) {
            eventi.push({ tipo: "http5xx", testo: `[${etichetta}] HTTP ${r.status()}`, url: r.url() });
          }
        });
      };

      osserva(page);
      await use({ osserva, eventi, ammetti: (...f) => void ammessi.push(...f) });

      const inattesi = eventi.filter((e) => !ammessi.some((a) => e.testo.includes(a) || e.url.includes(a)));
      await info.attach("diagnostica.json", {
        body: oscura(JSON.stringify({ totali: eventi.length, inattesi: inattesi.length, eventi }, null, 2)),
        contentType: "application/json",
      });
      const elenco = inattesi.map((e) => `${e.tipo} ${e.testo} ${e.url}`).join("\n");
      // Si confronta il testo oscurato, non gli oggetti: il confronto stampa ciò che riceve.
      expect(oscura(elenco), "Errori browser o rete non attesi").toBe("");
    },
    { auto: true },
  ],
});

export { expect };
