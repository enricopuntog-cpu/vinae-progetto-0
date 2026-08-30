/**
 * La sezione «Attività di vendita» dell'Account.
 *
 * Due cose vanno dimostrate, e sono di natura diversa.
 *
 * La prima è che i numeri siano quelli giusti, e per quella basta chiamare
 * `riepilogoVenditore()`: è la stessa funzione che alimenta `/vendite`, ha già
 * i suoi test, e quello che si aggiunge qui è il caso che l'Account rende
 * possibile — un account senza nessuna attività.
 *
 * La seconda è che l'Account *riusi* quella funzione invece di riscriverla, che
 * legga due volte e non otto, che non chiami «saldo» un prezzo e che il modulo
 * di modifica del profilo non dipenda da questa lettura. Sono affermazioni sul
 * codice, non sul risultato di una chiamata, e si verificano leggendo il
 * sorgente — la stessa forma dei contratti già in uso nel progetto
 * (`lib/vendite/dashboard.test.ts`, `lib/profilo/ingressi-profilo-pubblico.test.ts`).
 * Il pacchetto non ha una libreria DOM e questo lavoro non è una ragione per
 * introdurne una.
 */

import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  riepilogoVenditore,
  type AnnuncioPrezzo,
  type AnnuncioRiepilogo,
  type OrdineRiepilogo,
} from "@/lib/vendite/dashboard";
import { createListingService } from "@/services/listing-service";
import { routes } from "@/config/routes";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

// Un contratto che vieta una parola deve guardare il codice, non i commenti:
// altrimenti spiegare perché quella parola è vietata fa fallire la verifica.
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*[\s\S]*?\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const PERCORSO_SEZIONE = "src/app/account/attivita-vendita.tsx";
const PERCORSO_PAGINA = "src/app/account/page-client.tsx";
const PERCORSO_DASHBOARD = "src/app/vendite/page-client.tsx";

const sezione = leggi(PERCORSO_SEZIONE);
const sezioneNuda = senzaCommenti(sezione);
const pagina = leggi(PERCORSO_PAGINA);
const paginaNuda = senzaCommenti(pagina);
const dashboard = leggi(PERCORSO_DASHBOARD);

const ordine = (patch: Partial<OrdineRiepilogo> = {}): OrdineRiepilogo => ({
  stato: "pagato",
  preparazione_avviata_at: null,
  prezzo_cents: 10_000,
  created_at: "2026-08-10T09:00:00.000Z",
  ...patch,
});

const annuncio = (stato: AnnuncioRiepilogo["stato"], prezzo = 0): AnnuncioPrezzo => ({
  stato,
  wine: { prezzo },
});

// ---------------------------------------------------------------------------
// I numeri
// ---------------------------------------------------------------------------

describe("i KPI dell'Account escono da ordini e annunci reali", () => {
  it("deriva le quattro misure dalle due letture, senza altre sorgenti", () => {
    const riepilogo = riepilogoVenditore(
      [
        ordine({ stato: "pagato", preparazione_avviata_at: null }), // nuovo → da gestire
        ordine({ stato: "in_preparazione" }), // da_spedire → da gestire
        ordine({ stato: "spedito" }), // palla al compratore: non da gestire
        ordine({ stato: "completato", prezzo_cents: 4_500 }),
        ordine({ stato: "completato", prezzo_cents: 5_500 }),
      ],
      [annuncio("attivo"), annuncio("attivo"), annuncio("bozza"), annuncio("venduto")],
    );

    expect(riepilogo.annunciAttivi).toBe(2);
    expect(riepilogo.ordiniDaGestire).toBe(2);
    expect(riepilogo.venditeCompletate).toBe(2);
    expect(riepilogo.valoreVenditeCompletateCents).toBe(10_000);
  });

  it("zero attività è uno stato valido, non un vuoto", () => {
    // Un account normale che non ha mai venduto nulla ha una risposta vera alla
    // domanda, e sono quattro zeri. Non un errore, non una sezione assente.
    expect(riepilogoVenditore([], [])).toEqual({
      annunciAttivi: 0,
      valoreIndicativoAttiviCents: 0,
      ordiniDaGestire: 0,
      venditeCompletate: 0,
      valoreVenditeCompletateCents: 0,
    });
  });

  it("un account con annunci ma nessun ordine non inventa vendite", () => {
    const riepilogo = riepilogoVenditore([], [annuncio("attivo"), annuncio("in_revisione")]);
    expect(riepilogo.annunciAttivi).toBe(1);
    expect(riepilogo.ordiniDaGestire).toBe(0);
    expect(riepilogo.venditeCompletate).toBe(0);
    expect(riepilogo.valoreVenditeCompletateCents).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Il valore indicativo
// ---------------------------------------------------------------------------

describe("«Valore indicativo» somma i prezzi richiesti dei soli annunci attivi", () => {
  it("somma gli attivi e nient'altro", () => {
    const riepilogo = riepilogoVenditore(
      [],
      [
        annuncio("attivo", 120),
        annuncio("attivo", 45.5),
        annuncio("bozza", 900),
        annuncio("in_revisione", 900),
        annuncio("sospeso", 900),
        annuncio("venduto", 900),
      ],
    );
    expect(riepilogo.valoreIndicativoAttiviCents).toBe(16_550);
    expect(riepilogo.annunciAttivi).toBe(2);
  });

  it("non si mescola con il denaro degli ordini", () => {
    // Le due misure di denaro rispondono a due domande diverse: la vetrina di
    // adesso e le vendite chiuse. Un annuncio attivo non deve toccare la
    // seconda, e un ordine completato non deve toccare la prima.
    const riepilogo = riepilogoVenditore(
      [ordine({ stato: "completato", prezzo_cents: 7_000 })],
      [annuncio("attivo", 30)],
    );
    expect(riepilogo.valoreIndicativoAttiviCents).toBe(3_000);
    expect(riepilogo.valoreVenditeCompletateCents).toBe(7_000);
  });

  it("resta esatto al centesimo su più righe", () => {
    // `wine.prezzo` arriva in euro: sommare 0.1 + 0.2 in virgola mobile e
    // convertire alla fine darebbe 30.000000000000004 centesimi. Si arrotonda
    // per riga, e il totale resta un intero di centesimi.
    const riepilogo = riepilogoVenditore(
      [],
      [annuncio("attivo", 0.1), annuncio("attivo", 0.2), annuncio("attivo", 19.99)],
    );
    expect(riepilogo.valoreIndicativoAttiviCents).toBe(2_029);
    expect(Number.isInteger(riepilogo.valoreIndicativoAttiviCents)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Il riuso
// ---------------------------------------------------------------------------

describe("la sezione riusa la dashboard invece di riscriverla", () => {
  it("chiama `riepilogoVenditore` e non ne tiene una copia", () => {
    expect(sezioneNuda).toInclude('from "@/lib/vendite/dashboard"');
    expect(sezioneNuda).toInclude("riepilogoVenditore(righe, schede)");
    // Una sola chiamata: nessun secondo calcolo accanto al primo.
    expect(sezioneNuda.match(/riepilogoVenditore\(/g) ?? []).toHaveLength(1);
  });

  it("non duplica nessuna delle regole che decidono i quattro numeri", () => {
    // Ognuna di queste è una riga di `dashboard.ts`. Se ricomparisse qui, le
    // due superfici potrebbero divergere sulla stessa domanda.
    for (const regola of [
      "STATI_DA_GESTIRE",
      "sellerStatusDaOrdine",
      "prezzo_cents",
      'stato === "completato"',
      '=== "attivo"',
      ".reduce(",
    ]) {
      expect(sezioneNuda).not.toInclude(regola);
    }
  });

  it("riusa il componente KPI e le rotte esistenti, senza markup proprio", () => {
    expect(sezioneNuda).toInclude('from "@/components/vinea/Layout"');
    expect(sezioneNuda).toInclude("<Kpi");
    expect(sezioneNuda).toInclude('from "@/config/routes"');
  });

  it("usa le stesse etichette e lo stesso hint della dashboard", () => {
    // Non un vincolo estetico: due nomi diversi per la stessa misura sono due
    // misure, agli occhi di chi legge. Vale per le misure che le due superfici
    // condividono — «Da gestire» non è più fra queste, perché l'Account l'ha
    // sostituita e in `/vendite` continua a vivere accanto alla sua azione.
    for (const etichetta of [
      '"Annunci attivi"',
      '"Vendite completate"',
      '"Valore completate"',
      '"Ordini chiusi come completati"',
      '"Prezzo venditore, non un incassato"',
    ]) {
      expect(sezioneNuda).toInclude(etichetta);
      expect(senzaCommenti(dashboard)).toInclude(etichetta);
    }
  });

  it("mostra «Valore indicativo» al posto di «Da gestire», senza ricalcolarlo", () => {
    expect(sezioneNuda).toInclude('label="Valore indicativo"');
    expect(sezioneNuda).toInclude("riepilogo.valoreIndicativoAttiviCents");
    // L'Account non è più il posto in cui si guarda cosa aspetta un gesto.
    expect(sezioneNuda).not.toInclude('"Da gestire"');
    expect(sezioneNuda).not.toInclude("riepilogo.ordiniDaGestire");
    // …ma `/vendite` sì, e lì la misura resta accanto al pulsante che la chiude.
    expect(senzaCommenti(dashboard)).toInclude('label="Da gestire"');
  });

  it("dice che il valore indicativo non è denaro incassato", () => {
    // Un numero in euro dentro un Account viene letto come un saldo, se nessuno
    // dice il contrario. Qui il contrario è scritto nell'hint, non in un
    // commento: deve arrivare a chi guarda la pagina.
    const hint = /hint="[^"]*non è un saldo, un incassato o un payout[^"]*"/;
    expect(sezioneNuda).toMatch(hint);
    for (const parola of ["Saldo", "Incassato", "Payout", "Guadagn"]) {
      // Nessuna di queste può essere l'etichetta della misura.
      expect(sezioneNuda).not.toMatch(new RegExp(`label="[^"]*${parola}`, "i"));
    }
  });
});

// ---------------------------------------------------------------------------
// Le letture
// ---------------------------------------------------------------------------

describe("una visita a /account fa due letture, non una per KPI", () => {
  it("legge gli ordini una volta e gli annunci una volta", () => {
    expect(sezioneNuda.match(/\.vendite\(\)/g) ?? []).toHaveLength(1);
    expect(sezioneNuda.match(/\.mieiAnnunciConEsito\(\)/g) ?? []).toHaveLength(1);
    expect(sezioneNuda).toInclude("Promise.all([");
  });

  it("chiede la lettura annunci che distingue l'errore dall'elenco vuoto", () => {
    // `mieiAnnunci()` collassa errore e vuoto sullo stesso `[]`. Preso così,
    // un fallimento della lettura diventerebbe «annunci attivi: 0», cioè un
    // numero falso presentato come un fatto.
    expect(sezioneNuda).toInclude("mieiAnnunciConEsito()");
    expect(sezioneNuda).not.toMatch(/\.mieiAnnunci\(\)/);
  });

  it("non apre nessuna tabella, RPC o vista propria", () => {
    for (const vietato of [".from(", ".rpc(", "supabase.from"]) {
      expect(sezioneNuda).not.toInclude(vietato);
    }
  });

  it("non legge `profiles` né aggiunge una lettura del profilo", () => {
    expect(sezioneNuda).not.toInclude("profiles");
    expect(sezioneNuda).not.toInclude("profile-service");
    expect(sezioneNuda).not.toInclude("profilo_pubblico");
  });

  it("non decide chi è venditore: nessun ruolo, nessuna certificazione", () => {
    for (const gate of [
      "seller_verificato",
      "venditoreVerificato",
      "certificazioni",
      "user_roles",
      "has_role",
      "isVenditore",
    ]) {
      expect(sezioneNuda).not.toInclude(gate);
    }
  });
});

// ---------------------------------------------------------------------------
// Errore di lettura annunci ≠ nessun annuncio
// ---------------------------------------------------------------------------

/**
 * Un client che risponde una cosa sola alla query degli annunci del
 * proprietario, con una sessione valida: quello che cambia fra i casi è
 * soltanto se PostgREST ha risposto righe o un errore.
 */
const clientAnnunci = (risposta: { data: unknown; error: unknown }): SupabaseClient => {
  const query = {
    select: () => query,
    eq: () => query,
    order: (
      _colonna: string,
      _opzioni: unknown,
    ): Promise<{ data: unknown; error: unknown }> => Promise.resolve(risposta),
  };

  return {
    auth: { getUser: async () => ({ data: { user: { id: UTENTE } } }) },
    from: () => query,
  } as unknown as SupabaseClient;
};

const UTENTE = "11111111-1111-4111-8111-111111111111";

describe("una lettura annunci fallita non diventa «zero annunci»", () => {
  it("`mieiAnnunci()` da solo non permette di distinguere i due casi", async () => {
    // Non è un difetto del metodo: è il suo contratto, giusto per la gestione
    // annunci, dove quel vuoto lo si vede. È però la ragione per cui l'Account
    // non può usarlo per produrre un numero.
    const vuoto = createListingService(clientAnnunci({ data: [], error: null }));
    const rotto = createListingService(
      clientAnnunci({ data: null, error: { code: "42501", message: "permission denied" } }),
    );

    expect(await vuoto.mieiAnnunci()).toEqual([]);
    expect(await rotto.mieiAnnunci()).toEqual([]);
  });

  it("`mieiAnnunciConEsito()` tiene separati elenco vuoto ed errore", async () => {
    const vuoto = createListingService(clientAnnunci({ data: [], error: null }));
    expect(await vuoto.mieiAnnunciConEsito()).toEqual({ ok: true, data: [] });

    const messaggioDatabase = "permission denied for table listings";
    const rotto = createListingService(
      clientAnnunci({
        data: null,
        error: { code: "42501", details: "interno", message: messaggioDatabase },
      }),
    );
    const esito = await rotto.mieiAnnunciConEsito();

    expect(esito.ok).toBe(false);
    // Il messaggio di PostgreSQL resta nei log, non arriva alla pagina.
    if (!esito.ok) expect(esito.error).not.toContain(messaggioDatabase);
  });

  it("resta una query sola: il collasso è l'unica differenza fra le due firme", () => {
    const servizio = leggi("src/services/listing-service.ts");
    const nudo = senzaCommenti(servizio);
    // Una sola `from("listings")` con il filtro del proprietario, condivisa.
    expect(nudo.match(/\.eq\("seller_id", user\.id\)/g) ?? []).toHaveLength(1);
    expect(nudo).toInclude("mieiAnnunciConEsito: leggiMieiAnnunci");
    expect(nudo).toInclude("esito.ok ? esito.data : []");
  });

  it("la sezione mostra l'errore, non quattro zeri, se una lettura fallisce", () => {
    // Entrambe le letture devono riuscire perché i numeri siano veri: gli
    // annunci alimentano «annunci attivi», gli ordini le altre tre misure.
    expect(sezioneNuda).toInclude("if (!esitoOrdini.ok) setErrore(esitoOrdini.error);");
    expect(sezioneNuda).toInclude("else if (!esitoAnnunci.ok) setErrore(esitoAnnunci.error);");
    // I dati si scrivono solo nel ramo in cui nessuna delle due è fallita.
    const successo = sezioneNuda.slice(sezioneNuda.indexOf("else {"));
    expect(successo).toInclude("setOrdini(esitoOrdini.data);");
    expect(successo).toInclude("setAnnunci(esitoAnnunci.data);");
  });
});

// ---------------------------------------------------------------------------
// Caricamento, zero, errore
// ---------------------------------------------------------------------------

describe("caricamento, zero ed errore sono tre stati distinti", () => {
  it("non mostra nessun KPI finché la risposta non è arrivata", () => {
    // Uno zero mostrato durante l'attesa è un'affermazione, e per chi ha
    // davvero venduto è falsa per il tempo di una risposta di rete.
    expect(sezioneNuda).toInclude("const caricamento = ordini === null && errore === null");
    const guardia = sezioneNuda.indexOf("caricamento ?");
    const primoKpi = sezioneNuda.indexOf("<Kpi");
    expect(guardia).toBeGreaterThan(-1);
    expect(primoKpi).toBeGreaterThan(guardia);
  });

  it("l'errore non diventa uno zero e non espone il messaggio del servizio", () => {
    const ramo = sezioneNuda.slice(sezioneNuda.indexOf("errore !== null ?"));
    const fineRamo = ramo.indexOf("<Kpi");
    const testoErrore = ramo.slice(0, fineRamo);
    expect(testoErrore).toInclude("Non siamo riusciti a leggere");
    // Il messaggio grezzo del servizio resta fuori dalla pagina.
    expect(testoErrore).not.toInclude("{errore}");
  });

  it("nessuna soglia nasconde la sezione a chi ha zero attività", () => {
    // Nessun `return null`, nessun ramo che spegne la sezione: la sezione
    // esiste per qualunque account autenticato.
    expect(sezioneNuda).not.toInclude("return null");
    expect(sezioneNuda).not.toMatch(/if \(.*length === 0\)/);
  });
});

// ---------------------------------------------------------------------------
// Il confine con il modulo profilo
// ---------------------------------------------------------------------------

describe("il fallimento della sezione non tocca il modulo profilo", () => {
  it("la pagina non conosce ordini, annunci né il loro esito", () => {
    for (const dipendenza of [
      "order-service",
      "listing-service",
      "lib/vendite/dashboard",
      ".vendite()",
      ".mieiAnnunci()",
    ]) {
      expect(paginaNuda).not.toInclude(dipendenza);
    }
  });

  it("la sezione è un fratello del modulo, non un blocco al suo interno", () => {
    expect(paginaNuda).toInclude("<AttivitaVendita />");
    expect(paginaNuda.indexOf("<AttivitaVendita />")).toBeGreaterThan(
      paginaNuda.indexOf("Salva modifiche"),
    );
  });

  it("lo stato della lettura vive solo dentro la sezione", () => {
    expect(sezioneNuda).toInclude("const [errore, setErrore]");
    // `setErroreFoto` del modulo avatar resta, ed è un'altra cosa.
    expect(paginaNuda).not.toInclude("setErrore(");
  });
});

// ---------------------------------------------------------------------------
// Il percorso verso /vendite
// ---------------------------------------------------------------------------

describe("l'Account apre la porta verso le vendite", () => {
  it("porta alla dashboard riusando la rotta di configurazione", () => {
    expect(routes.vendite).toBe("/vendite");
    expect(sezioneNuda).toInclude("routes.vendite");
    expect(sezioneNuda).toInclude("Vai alle mie vendite");
    // La rotta non è riscritta a mano accanto alla costante.
    expect(sezioneNuda).not.toInclude('href="/vendite"');
  });

  it("non ricostruisce la dashboard dentro l'Account", () => {
    for (const pezzo of [
      "recharts",
      "BarChart",
      "OrderListView",
      "andamentoMensile",
      "distribuzionePerStato",
    ]) {
      expect(sezioneNuda).not.toInclude(pezzo);
    }
  });
});

// ---------------------------------------------------------------------------
// Niente semantica Balance
// ---------------------------------------------------------------------------

describe("nessun numero promette una disponibilità economica", () => {
  it("non chiama saldo, incassato o payout un prezzo venditore", () => {
    // Stessa lista del contratto di `/vendite`: quei fatti vivono nella 7b e
    // questi dati non li dimostrano.
    for (const promessa of [
      "Incassato",
      "Incassi",
      "Payout",
      "payout_stato",
      "Saldo",
      "Disponibile",
      "Guadagn",
      "Ricavi",
      "Balance",
      "Credito",
      "Prelievo",
    ]) {
      expect(sezioneNuda).not.toInclude(promessa);
    }
    // E lo dice a chi legge la pagina, non solo a chi legge il codice.
    expect(sezioneNuda).toInclude("non un incassato");
  });
});

// ---------------------------------------------------------------------------
// La vecchia scheda
// ---------------------------------------------------------------------------

describe("la vecchia scheda Certificazioni", () => {
  it("non è più renderizzata nell'Account", () => {
    for (const residuo of [
      "Certificazioni",
      "vociCertificazione",
      "RigaCertificazione",
      "certificazione-",
      "ShieldCheck",
    ]) {
      expect(paginaNuda).not.toInclude(residuo);
    }
  });

  it("è sostituita da una sezione con un nome proprio", () => {
    expect(sezioneNuda).toInclude("Attività di vendita");
  });

  it("non porta via con sé il dominio delle certificazioni", () => {
    // Sparisce una superficie dell'Account, non i dati né la derivazione: la
    // futura area Professional Qualifications è un altro work package.
    expect(existsSync(join(progetto, "src/lib/profilo/certificazioni.ts"))).toBe(true);
    expect(leggi("src/lib/profilo/certificazioni.ts")).toInclude(
      "export function vociCertificazione",
    );
    expect(leggi("src/services/profile-service.ts")).toInclude("my_certifications");
  });

  it("non introduce badge professionali al suo posto", () => {
    for (const fuoriScopo of [
      "qualifica",
      "Qualification",
      "badge",
      "verificato",
      "documento",
    ]) {
      expect(sezioneNuda.toLowerCase()).not.toInclude(fuoriScopo.toLowerCase());
    }
  });
});
