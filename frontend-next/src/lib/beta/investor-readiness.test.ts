import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Prontezza delle superfici critiche.
 *
 * Non è una prova di bellezza né una seconda copia di `prelaunch-contract`:
 * quella suite difende i flag, i ruoli e i link visibili. Qui si difende ciò
 * che una demo mostra per primo quando qualcosa va storto — una rotta che non
 * esiste, un caricamento che non si vede, un elenco vuoto senza una frase, e
 * soprattutto un errore del database o della configurazione stampato in
 * pagina. L'ultimo è quello che è già successo: /account rendeva
 * `authError` così com'era, e `profile-service` restituiva `errore.message`
 * per tutto ciò che non aveva tradotto.
 *
 * Le prove leggono il codice invece di renderlo per la stessa ragione delle
 * altre suite di contratto: quasi tutto quello che va garantito qui è
 * un'assenza, e un'assenza non si dimostra rendendo il caso a cui si è
 * pensato.
 */

const leggi = (percorso: string) => readFileSync(join(process.cwd(), percorso), "utf8");
const esiste = (percorso: string) => existsSync(join(process.cwd(), percorso));

/** I divieti valgono sul codice vivo, non sui commenti che li spiegano. */
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

/**
 * Le superfici che una demo attraversa. `annuncio` e `profilo` hanno il
 * segmento fisico `[id]`: nel primo contiene lo slug dell'annuncio (la forma di
 * URL precedente alla migrazione, conservata per non rompere i link), nel
 * secondo l'UUID del profilo. Il nome del segmento non è il suo contenuto.
 */
const ROTTE_CRITICHE = [
  "src/app/page.tsx",
  "src/app/registrati/page.tsx",
  "src/app/accedi/page.tsx",
  "src/app/legale/page.tsx",
  "src/app/esplora/page.tsx",
  "src/app/annuncio/[id]/page.tsx",
  "src/app/profilo/[id]/page.tsx",
  "src/app/home/page.tsx",
  "src/app/account/page.tsx",
  "src/app/cantina/page.tsx",
  "src/app/vendi/page.tsx",
  "src/app/vendite/page.tsx",
  "src/app/messaggi/page.tsx",
  "src/app/community/page.tsx",
  "src/app/admin/page.tsx",
] as const;

/**
 * I servizi che alimentano quelle superfici. Sono la porta da cui un testo
 * tecnico entra in pagina: la superficie mostra la stringa che riceve.
 */
const SERVIZI_CRITICI = [
  "src/services/profile-service.ts",
  "src/services/public-profile-service.ts",
  "src/services/professional-qualification-service.ts",
  "src/services/wine-regions-service.ts",
  "src/services/phase7/shared.ts",
] as const;

describe("le rotte critiche esistono", () => {
  for (const percorso of ROTTE_CRITICHE) {
    it(`${percorso}`, () => {
      expect(esiste(percorso)).toBe(true);
    });
  }
});

describe("nessun errore di configurazione o di database raggiunge una superficie critica", () => {
  it("nessun servizio critico nomina le variabili d'ambiente o il file che le contiene", () => {
    for (const percorso of SERVIZI_CRITICI) {
      const codice = senzaCommenti(leggi(percorso));
      expect(codice).not.toInclude("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      expect(codice).not.toInclude(".env.local");
    }
  });

  it("il profilo non restituisce più il messaggio del server per un errore non tradotto", () => {
    const codice = senzaCommenti(leggi("src/services/profile-service.ts"));
    // Le tre traduzioni restano: sono errori che l'utente può correggere.
    expect(codice).toInclude("Questo nome utente è già in uso. Scegline un altro.");
    expect(codice).toInclude("Devi avere almeno 18 anni per usare Vinea.");
    expect(codice).toInclude("L'avatar scelto non è valido.");
    // Il resto no: il ramo finale è una frase nostra, e la forma esatta va nei log.
    expect(codice).not.toMatch(/return errore\.message/);
    expect(codice).toInclude("ERRORE_GENERICO_PROFILO");
  });

  it("/vendi non dice all'utente che manca una connessione al provider", () => {
    const codice = senzaCommenti(leggi("src/hooks/useSellWizard.ts"));
    expect(codice).not.toInclude("Connessione a Supabase non configurata.");
    expect(codice).toInclude("Il caricamento delle foto non è disponibile in questo momento.");
  });

  it("il saldo mostrato su /account non nomina il provider quando il client manca", () => {
    const codice = senzaCommenti(leggi("src/services/phase7/shared.ts"));
    expect(codice).not.toInclude("Connessione a Supabase non configurata.");
    // E un errore RPC senza codice riconosciuto resta una frase nostra.
    expect(codice).toInclude("Non è stato possibile completare l'operazione. Riprova.");
  });
});

describe("le superfici asincrone dicono che stanno caricando, e cosa fare quando non c'è nulla", () => {
  it("/messaggi ha caricamento, errore con riprova e stato vuoto", () => {
    const codice = leggi("src/components/vinea/messaging/MessagesPageClient.tsx");
    expect(codice).toInclude("<LoadingBlock");
    expect(codice).toInclude("<ErrorState");
    expect(codice).toInclude("onRetry=");
    expect(codice).toInclude("<EmptyState");
    expect(codice).toInclude("Nessuna conversazione");
  });

  it("/community distingue «ancora nessun club» da «nessun club con questi filtri»", () => {
    const codice = leggi("src/app/community/page-client.tsx");
    expect(codice).toInclude("<ErrorState");
    expect(codice).toInclude("Nessun club pubblicato, per ora.");
    expect(codice).toInclude("Nessun club con questi filtri.");
  });

  it("/esplora ha uno stato vuoto invece di una griglia muta", () => {
    expect(leggi("src/app/esplora/page-client.tsx")).toInclude("Nessuna bottiglia trovata");
  });

  it("/account, /cantina e /vendi mostrano la verifica della sessione prima di decidere", () => {
    for (const percorso of [
      "src/app/account/page-client.tsx",
      "src/app/cantina/page-client.tsx",
      "src/app/vendi/page-client.tsx",
    ]) {
      const codice = senzaCommenti(leggi(percorso));
      expect(codice).toInclude("authLoading");
    }
  });

  it("chi non è autenticato trova un invito che torna dove stava", () => {
    // `next` statico e relativo: la destinazione è nota qui e non arriva dall'URL.
    expect(leggi("src/app/account/page-client.tsx")).toInclude("%2Faccount");
    expect(leggi("src/app/cantina/page-client.tsx")).toInclude("%2Fcantina");
    expect(leggi("src/app/vendi/page-client.tsx")).toInclude("%2Fvendi");
  });
});

describe("le destinazioni delle CTA principali esistono", () => {
  it("le pagine legali hanno le ancore a cui puntano registrazione e footer", () => {
    const legale = leggi("src/app/legale/page.tsx");
    expect(legale).toInclude('id="termini"');
    expect(legale).toInclude('id="privacy"');
    expect(leggi("src/app/registrati/page-client.tsx")).toInclude('href="/legale#termini"');
    expect(leggi("src/app/registrati/page-client.tsx")).toInclude('href="/legale#privacy"');
  });

  it("il ritorno dopo il recupero password è una rotta vera e non indicizzabile", () => {
    expect(esiste("src/app/reimposta-password/page.tsx")).toBe(true);
    expect(leggi("src/app/reimposta-password/page.tsx")).toInclude(
      "robots: { index: false, follow: false }",
    );
  });
});

describe("provider e pagamenti restano spenti, e si vede senza rompersi", () => {
  it("i due flag si accendono solo con la stringa esatta «true»", () => {
    const codice = senzaCommenti(leggi("src/config/features.ts"));
    expect(codice).toMatch(
      /PAGAMENTI_UI_ABILITATI\s*=\s*valoreFlagEsattamenteTrue\(\s*process\.env\.NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED/,
    );
    expect(codice).toMatch(
      /AZIONI_PAGAMENTO_ABILITATE\s*=\s*valoreFlagEsattamenteTrue\(\s*process\.env\.NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED/,
    );
  });

  it("con i pagamenti spenti l'annuncio non mostra «Compra ora» e non lascia un buco", () => {
    const codice = senzaCommenti(leggi("src/app/annuncio/[id]/page-client.tsx"));
    expect(codice).toInclude("PAGAMENTI_UI_ABILITATI ? (");
    // La griglia si richiude: una colonna sola invece di tre con due vuote.
    expect(codice).toMatch(/PAGAMENTI_UI_ABILITATI \? "grid-cols-3" : "grid-cols-1"/);
    // La proposta resta: la superficie continua a fare qualcosa.
    expect(codice).toInclude("<ProposalAction");
  });

  it("il prelievo su /account passa dal cancello prima di costruire il servizio", () => {
    const codice = senzaCommenti(leggi("src/app/account/saldo-vinea.tsx"));
    const inizio = codice.indexOf("const richiediPrelievo =");
    // Fine al gesto successivo: nel file c'è anche il `return () =>` di una
    // cleanup, che sta prima di questo handler e produrrebbe una fetta vuota.
    const corpo = codice.slice(inizio, codice.indexOf("annullaPrelievo(", inizio));
    const cancello = corpo.indexOf("eseguiAzioneBeta(");
    const servizio = corpo.indexOf("createBalanceService(");
    expect(cancello).toBeGreaterThan(-1);
    expect(servizio).toBeGreaterThan(cancello);
    expect(corpo).toInclude("AZIONI_PAGAMENTO_ABILITATE");
  });
});

describe("il ruolo demo resta una presentazione", () => {
  it("/admin decide da `user_roles` letto con la sessione vera, e fallisce chiuso", () => {
    const codice = senzaCommenti(leggi("src/app/admin/page.tsx"));
    expect(codice).toInclude('from("user_roles")');
    expect(codice).toInclude("eAdminReale(");
    expect(codice).toInclude("notFound()");
    // Nessun ruolo demo e nessuna chiave di servizio in questa decisione.
    expect(codice).not.toMatch(/DEMO|service_?role|SERVICE_ROLE/);
  });

  it("la voce Admin in navigazione guarda il ruolo autenticato, non lo switcher", () => {
    const codice = senzaCommenti(leggi("src/components/vinea/Layout.tsx"));
    expect(codice).toMatch(/authRuolo === "admin"/);
    expect(codice).not.toMatch(/\bruolo === "admin"/);
  });
});
