import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { ruoloDaSessione } from "@/lib/auth/role";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
// La prosa che spiega un divieto non deve farlo fallire: il commento JSX cade
// per primo, con l'atomo temperato che impedisce al match di scavalcare il suo
// `*/` e mangiarsi il codice fino al successivo.
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
const sorgentiIa = [
  leggi("src/components/vinea/SommelierChat.tsx"),
  leggi("src/hooks/useSellWizard.ts"),
  leggi("src/app/esplora/page-client.tsx"),
];

const fileRicorsivi = (directory: string): string[] =>
  readdirSync(directory, { withFileTypes: true }).flatMap((voce) => {
    const percorso = join(directory, voce.name);
    return voce.isDirectory() ? fileRicorsivi(percorso) : [percorso];
  });

describe("contratto di pre-lancio beta", () => {
  it("deriva Guest dall'assenza di sessione", () => {
    expect(ruoloDaSessione(null, [])).toBe("guest");
  });

  it("deriva User da una sessione priva del ruolo admin", () => {
    expect(ruoloDaSessione({ userId: "u1", email: "u@example.test" }, ["user"])).toBe("user");
  });

  it("deriva Admin soltanto dal ruolo reale", () => {
    expect(ruoloDaSessione({ userId: "u1", email: null }, ["admin"])).toBe("admin");
  });

  it("non promuove ruoli arbitrari ad Admin", () => {
    expect(ruoloDaSessione({ userId: "u1", email: null }, ["administrator", "owner"])).toBe("user");
  });

  it("mantiene chiusi tutti i flag pubblici nell'esempio", () => {
    const env = leggi(".env.example");
    for (const nome of [
      "NEXT_PUBLIC_AI_UI_ENABLED",
      "NEXT_PUBLIC_AI_ACTIONS_ENABLED",
      "NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED",
      "NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED",
      "NEXT_PUBLIC_PACKAGING_ENABLED",
      "NEXT_PUBLIC_DEMO_UI_ENABLED",
    ]) {
      expect(env).toInclude(`${nome}=false`);
    }
  });

  it("non costruisce alcun client IA quando le azioni sono spente", () => {
    for (const sorgente of sorgentiIa) {
      expect(sorgente).toInclude("AZIONI_IA_ABILITATE");
      expect(sorgente).toInclude("? createSupabaseAiService(getSupabaseClient())");
      expect(sorgente).toMatch(/if \(!AZIONI_IA_ABILITATE \|\| !aiService\)/);
    }
  });

  it("mantiene visibili tutte le superfici IA dietro il solo flag UI", () => {
    expect(leggi("src/components/vinea/Layout.tsx")).toInclude("AI_UI.sommelier && <SommelierChat");
    expect(leggi("src/app/vendi/page-client.tsx")).toInclude("AI_UI.catalogazione &&");
    expect(leggi("src/app/esplora/page-client.tsx")).toInclude("AI_UI.abbinamento &&");
  });

  it("non rende raggiungibile il pannello sfondi della Fase 11", () => {
    expect(existsSync(join(progetto, "src/components/vinea/BetaBackgroundPanel.tsx"))).toBeFalse();
    expect(leggi("src/app/vendi/page-client.tsx")).not.toInclude("BetaBackgroundPanel");
  });

  it("collega il dettaglio alla rotta checkout reale", () => {
    const dettaglio = leggi("src/app/annuncio/[id]/page-client.tsx");
    expect(dettaglio).toInclude("PAGAMENTI_UI_ABILITATI");
    expect(dettaglio).toInclude("router.push(`/checkout/${wine.id}`)");
    expect(leggi("src/app/checkout/[id]/page.tsx")).toInclude("<CheckoutPageClient");
  });

  it("racchiude il solo comando finale nel gate pagamento", () => {
    const hook = leggi("src/app/checkout/[id]/use-beta-checkout.ts");
    const confine = hook.indexOf('eseguiAzioneBeta("pagamento"');
    const servizio = hook.indexOf("createPaymentService(getSupabaseClient()).creaCheckout");
    expect(confine).toBeGreaterThan(-1);
    expect(servizio).toBeGreaterThan(confine);
    expect(hook).not.toInclude("createOrder");
    expect(hook).not.toInclude("functions.invoke");
  });

  // La riga di prima leggeva `BetaDeliverySelector.tsx` e chiedeva che il
  // selettore di spedizione fosse finto e locale. Quel componente non esiste
  // più: al suo posto il passo Consegna dichiara una scelta vera, che finisce
  // su `listings`. Cancellare il test avrebbe tolto la garanzia insieme al
  // componente, quindi qui c'è la stessa promessa detta con più precisione —
  // la logistica non è attiva — misurata su ciò che il codice fa adesso.
  it("dichiara la logistica dell'annuncio senza attivare alcuna spedizione", () => {
    const wizard = senzaCommenti(leggi("src/hooks/useSellWizard.ts"));
    const passo = senzaCommenti(leggi("src/app/vendi/page-client.tsx"));
    const servizio = senzaCommenti(leggi("src/services/listing-service.ts"));
    const checkout = leggi("src/lib/beta/checkout.ts");

    // La scelta passa dalla sola funzione interna: nessun fornitore, nessuna
    // Edge Function, nessuna chiamata di rete propria.
    expect(servizio).toInclude('client.rpc("listing_logistica_dichiara"');
    for (const sorgente of [wizard, passo]) {
      expect(sorgente).not.toMatch(/fetch\(|functions\.invoke/);
      // I nomi dei corrieri vanno ancorati alla parola: `ups` e `brt` sono
      // sillabe che ricorrono in italiano e in mezzo alle classi CSS.
      expect(sorgente).not.toMatch(/\b(dhl|ups|gls|brt|poste|sendcloud|shippo|easypost)\b/i);
    }

    // Niente etichette, codici a barre o tracciamento: non esistono da
    // generare, e un annuncio che li promettesse prometterebbe un servizio
    // inattivo. `tracking` da solo colpirebbe `tracking-wide` di Tailwind,
    // quindi si cerca il tracciamento vero, non la spaziatura di un titolo.
    const logistica = wizard + passo;
    expect(logistica).not.toMatch(
      /etichetta di spedizione|lettera di vettura|tracciamento|tracking(?:Code|Number|Url)|numero di tracking|\bQR\b/i,
    );

    // Nessun prezzo di trasporto entra nel wizard, e il checkout beta resta
    // quello che era: il gate pagamenti non si muove da qui.
    expect(logistica).not.toMatch(/costoSpedizione|speseSpedizione|shippingCost/);
    expect(checkout).toInclude('provider: "fake"');
  });

  it("nasconde il selettore demo per default e usa il ruolo reale", () => {
    const layout = leggi("src/components/vinea/Layout.tsx");
    const store = leggi("src/lib/vinea-store.tsx");
    expect(layout).toInclude("DEMO_UI_ABILITATA ? <DemoSwitch");
    expect(store).toInclude("ruoloReale: realAuthDomain.authRuolo");
    expect(store).toInclude("demoAbilitata: DEMO_UI_ABILITATA");
  });

  it("non lascia link visibili verso route inesistenti", () => {
    const app = join(progetto, "src/app");
    const route = fileRicorsivi(app)
      .filter((file) => file.endsWith("page.tsx"))
      .map((file) => `/${relative(app, file).replaceAll("\\", "/").replace(/(^|\/)page\.tsx$/, "")}`)
      .map((percorso) => (percorso === "/" ? "/" : percorso.replace(/\/$/, "")));
    const sorgenti = fileRicorsivi(app)
      .concat(fileRicorsivi(join(progetto, "src/components")))
      .filter((file) => file.endsWith(".tsx"))
      .map((file) => readFileSync(file, "utf8"))
      .join("\n");
    const destinazioni = [...sorgenti.matchAll(/(?:href=|to:\s*|router\.(?:push|replace)\()\s*\{?["'`]([^"'`]+)["'`]/g)]
      .map((match) => match[1].split(/[?#]/)[0].replace(/\$\{[^}]+\}/g, "[id]"))
      .filter((percorso) => percorso.startsWith("/"));

    for (const destinazione of new Set(destinazioni)) {
      const esiste = route.some((candidata) => {
        const pattern = `^${candidata.replace(/\[[^/]+\]/g, "[^/]+").replaceAll("/", "\\/")}$`;
        return new RegExp(pattern).test(destinazione);
      });
      expect(esiste, `Route visibile assente: ${destinazione}`).toBeTrue();
    }
  });

  it("rimuove onboarding e profilo dalle destinazioni visibili", () => {
    const sorgenti = [
      leggi("src/components/vinea/Layout.tsx"),
      leggi("src/app/page-client.tsx"),
      leggi("src/app/home/page-client.tsx"),
    ].join("\n");
    expect(sorgenti).not.toMatch(/href=["']\/(?:onboarding|profilo)/);
    expect(sorgenti).toInclude('href="/registrati"');
  });

  it("applica noindex sia nei metadata sia negli header", () => {
    expect(leggi("src/app/layout.tsx")).toMatch(/robots:\s*\{[\s\S]*index: false,[\s\S]*follow: false/);
    expect(leggi("next.config.ts")).toInclude('{ key: "X-Robots-Tag", value: "noindex, nofollow" }');
  });

  it("versiona il runtime Netlify senza adapter manuale", () => {
    const netlify = leggi("../netlify.toml");
    expect(netlify).toInclude('base = "frontend-next"');
    expect(netlify).toInclude('command = "bun run build"');
    expect(netlify).toInclude('publish = ".next"');
    expect(netlify).toInclude('BUN_VERSION = "1.3.14"');
    expect(netlify).toInclude('NODE_VERSION = "22"');
    expect(netlify).not.toInclude("@netlify/plugin-nextjs");
  });

  it("allinea MIN_TESTS al conteggio della suite estesa", () => {
    expect(leggi("../.github/workflows/ci.yml")).toInclude('MIN_TESTS: "2467"');
  });

  // Lo script si prova da solo in `protected-paths-guard.test.sh`; qui si prova
  // che sia collegato. Uno script corretto ma non invocato non ha fermato nulla,
  // ed e esattamente cosi che i quattro file personali sono finiti nel commit
  // 2015a4d: nessun controllo si opponeva. Servono tre condizioni insieme: la
  // guardia eseguita, gli SHA dell'evento (su pull_request HEAD del checkout e
  // il merge commit di prova, non il vero HEAD della branch) e la cronologia
  // completa, senza la quale il range della branch non e ispezionabile.
  it("invoca la guardia sui file personali in CI su tutta la cronologia della branch", () => {
    const ci = leggi("../.github/workflows/ci.yml");
    expect(ci).toInclude("bash .github/scripts/protected-paths-guard.sh");
    expect(ci).toInclude("bash .github/scripts/protected-paths-guard.test.sh");
    expect(ci).toInclude("fetch-depth: 0");
    expect(ci).toInclude(
      "GUARDIA_BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}",
    );
    expect(ci).toInclude(
      "GUARDIA_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.event.after }}",
    );
    expect(ci).not.toInclude("fetch-depth: 2");
  });

  it("non trasforma secret o gate server in variabili pubbliche", () => {
    const env = leggi(".env.example");
    for (const vietata of [
      "NEXT_PUBLIC_AI_ENABLED",
      "NEXT_PUBLIC_PAYMENTS_ENABLED",
      "NEXT_PUBLIC_PACKAGING_SERVER_ENABLED",
      "NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY",
      "NEXT_PUBLIC_OPENAI_API_KEY",
      "NEXT_PUBLIC_STRIPE_SECRET_KEY",
    ]) {
      expect(env).not.toInclude(vietata);
    }
  });

  it("non mantiene successi finti nelle superfici ripulite", () => {
    const report = leggi("src/components/vinea/ReportDialog.tsx");
    expect(report).not.toInclude("setTimeout");
    expect(report).not.toInclude("mock-");
    expect(report).toInclude("await createSupabaseModerationService");
    // La riga sul club diceva `toInclude("notFound()")`, cioe che /community
    // era irraggiungibile. Dal 12a e raggiungibile e legge dati reali, quindi
    // quella riga passerebbe ancora - il dettaglio ha un notFound() vero per
    // lo slug assente - ma misurando un'altra cosa. Qui si asserisce cio che
    // il test voleva davvero dire: nessun finto successo su quella superficie.
    const club = [
      leggi("src/app/community/page-client.tsx"),
      leggi("src/app/community/[slug]/page-client.tsx"),
    ].join("\n");
    expect(club).not.toInclude("setTimeout");
    expect(club).toInclude("useClubFollow");
  });
});
