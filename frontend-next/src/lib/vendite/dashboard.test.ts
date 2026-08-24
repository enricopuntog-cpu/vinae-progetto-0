import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  andamentoMensile,
  andamentoVuoto,
  distribuzionePerStato,
  MESI_ANDAMENTO,
  ordinaAnnunciPerGestione,
  PRIORITA_ANNUNCIO,
  riepilogoVenditore,
  STATI_DA_GESTIRE,
  type AnnuncioRiepilogo,
  type OrdineRiepilogo,
} from "@/lib/vendite/dashboard";
import { ETICHETTE_STATO_VENDITORE, sellerStatusDaOrdine } from "@/lib/orders/seller-status";
import { ETICHETTA_STATO, type ListingStato } from "@/services/listing-service";
import type { OrderStatus, SellerOrderStatus } from "@/services/types";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const ordine = (patch: Partial<OrdineRiepilogo> = {}): OrdineRiepilogo => ({
  stato: "pagato",
  preparazione_avviata_at: null,
  prezzo_cents: 10_000,
  created_at: "2026-08-10T09:00:00.000Z",
  ...patch,
});

const annuncio = (stato: ListingStato): AnnuncioRiepilogo => ({ stato });

/** Un ordine per ciascuno dei nove stati venditore raggiungibili. */
const unoPerStato: Record<SellerOrderStatus, OrdineRiepilogo> = {
  nuovo: ordine({ stato: "pagato", preparazione_avviata_at: null }),
  da_preparare: ordine({ stato: "pagato", preparazione_avviata_at: "2026-08-11T09:00:00.000Z" }),
  da_spedire: ordine({ stato: "in_preparazione" }),
  spedito: ordine({ stato: "spedito" }),
  consegnato: ordine({ stato: "consegnato" }),
  completato: ordine({ stato: "completato" }),
  contestato: ordine({ stato: "contestato" }),
  rimborsato: ordine({ stato: "rimborsato" }),
  annullato: ordine({ stato: "annullato" }),
};

const TUTTI_GLI_ORDINI = Object.values(unoPerStato);

describe("riepilogoVenditore", () => {
  it("conta solo gli annunci in stato attivo", () => {
    const annunci = [
      annuncio("attivo"),
      annuncio("attivo"),
      annuncio("bozza"),
      annuncio("sospeso"),
      annuncio("venduto"),
    ];
    expect(riepilogoVenditore([], annunci).annunciAttivi).toBe(2);
  });

  it("conta come «da gestire» esattamente gli stati di STATI_DA_GESTIRE", () => {
    const riepilogo = riepilogoVenditore(TUTTI_GLI_ORDINI, []);
    expect(riepilogo.ordiniDaGestire).toBe(STATI_DA_GESTIRE.length);
  });

  it("non chiede al venditore un gesto su ordini che aspettano il compratore", () => {
    // `spedito` e `consegnato` sono in mano al compratore: confermare la
    // ricezione o lasciare scadere l'auto-rilascio. Non sono «da gestire».
    const riepilogo = riepilogoVenditore([unoPerStato.spedito, unoPerStato.consegnato], []);
    expect(riepilogo.ordiniDaGestire).toBe(0);
  });

  it("non conta come da gestire ciò che è chiuso", () => {
    const chiusi = [unoPerStato.completato, unoPerStato.rimborsato, unoPerStato.annullato];
    expect(riepilogoVenditore(chiusi, []).ordiniDaGestire).toBe(0);
  });

  it("somma prezzo_cents dei soli ordini completati", () => {
    const ordini = [
      ordine({ stato: "completato", prezzo_cents: 4_500 }),
      ordine({ stato: "completato", prezzo_cents: 5_500 }),
      // Rimborsato e spedito NON entrano: il primo è denaro tornato indietro,
      // il secondo non è ancora una vendita chiusa.
      ordine({ stato: "rimborsato", prezzo_cents: 99_900 }),
      ordine({ stato: "spedito", prezzo_cents: 99_900 }),
    ];
    const riepilogo = riepilogoVenditore(ordini, []);
    expect(riepilogo.venditeCompletate).toBe(2);
    expect(riepilogo.valoreVenditeCompletateCents).toBe(10_000);
  });

  it("su nessun dato restituisce zeri e non NaN", () => {
    expect(riepilogoVenditore([], [])).toEqual({
      annunciAttivi: 0,
      ordiniDaGestire: 0,
      venditeCompletate: 0,
      valoreVenditeCompletateCents: 0,
    });
  });

  it("resta d'accordo con sellerStatusDaOrdine su ogni stato ordine", () => {
    // Se un giorno la derivazione cambia, «da gestire» deve cambiare con lei e
    // non per conto proprio.
    for (const riga of TUTTI_GLI_ORDINI) {
      const atteso = STATI_DA_GESTIRE.includes(sellerStatusDaOrdine(riga)) ? 1 : 0;
      expect(riepilogoVenditore([riga], []).ordiniDaGestire).toBe(atteso);
    }
  });
});

describe("distribuzionePerStato", () => {
  it("omette gli stati senza ordini", () => {
    const fette = distribuzionePerStato([unoPerStato.spedito, unoPerStato.spedito]);
    expect(fette).toEqual([{ stato: "spedito", ordini: 2 }]);
  });

  it("copre tutti e nove gli stati quando ci sono", () => {
    const fette = distribuzionePerStato(TUTTI_GLI_ORDINI);
    expect(fette).toHaveLength(9);
    expect(fette.every((f) => f.ordini === 1)).toBe(true);
  });

  it("mantiene l'ordine delle schede di OrderList", () => {
    const fette = distribuzionePerStato([
      unoPerStato.completato,
      unoPerStato.nuovo,
      unoPerStato.spedito,
    ]);
    expect(fette.map((f) => f.stato)).toEqual(["nuovo", "spedito", "completato"]);
  });

  it("su nessun ordine non restituisce niente da disegnare", () => {
    expect(distribuzionePerStato([])).toEqual([]);
  });

  it("nomina solo stati che hanno un'etichetta", () => {
    for (const fetta of distribuzionePerStato(TUTTI_GLI_ORDINI)) {
      expect(ETICHETTE_STATO_VENDITORE[fetta.stato]).toBeTruthy();
    }
  });
});

describe("andamentoMensile", () => {
  const riferimento = new Date("2026-08-24T12:00:00.000Z");

  it("restituisce una finestra di sei mesi che finisce con quello di riferimento", () => {
    const finestra = andamentoMensile([], riferimento);
    expect(finestra).toHaveLength(MESI_ANDAMENTO);
    expect(finestra.map((c) => c.mese)).toEqual([
      "2026-03",
      "2026-04",
      "2026-05",
      "2026-06",
      "2026-07",
      "2026-08",
    ]);
  });

  it("attraversa il capodanno senza saltare un mese", () => {
    const finestra = andamentoMensile([], new Date("2026-02-15T00:00:00.000Z"), 4);
    expect(finestra.map((c) => c.mese)).toEqual(["2025-11", "2025-12", "2026-01", "2026-02"]);
  });

  it("colloca l'ordine nel mese UTC di created_at", () => {
    const finestra = andamentoMensile(
      [ordine({ created_at: "2026-06-02T00:00:00.000Z" })],
      riferimento,
    );
    expect(finestra.find((c) => c.mese === "2026-06")?.ordini).toBe(1);
    expect(finestra.find((c) => c.mese === "2026-07")?.ordini).toBe(0);
  });

  it("non lascia che il fuso locale sposti un ordine di fine mese", () => {
    // Il 31 luglio alle 23:30 UTC è agosto in molti fusi. La chiave si legge
    // dalla stringa ISO, quindi resta luglio ovunque il test giri.
    const finestra = andamentoMensile(
      [ordine({ created_at: "2026-07-31T23:30:00.000Z" })],
      riferimento,
    );
    expect(finestra.find((c) => c.mese === "2026-07")?.ordini).toBe(1);
    expect(finestra.find((c) => c.mese === "2026-08")?.ordini).toBe(0);
  });

  it("ignora gli ordini fuori dalla finestra", () => {
    const finestra = andamentoMensile(
      [ordine({ created_at: "2025-01-05T00:00:00.000Z" }), ordine({ created_at: "2026-08-01T00:00:00.000Z" })],
      riferimento,
    );
    expect(finestra.reduce((n, c) => n + c.ordini, 0)).toBe(1);
  });

  it("conta i completati come sottoinsieme dei ricevuti dello stesso mese", () => {
    const finestra = andamentoMensile(
      [
        ordine({ stato: "completato", created_at: "2026-05-04T00:00:00.000Z" }),
        ordine({ stato: "spedito", created_at: "2026-05-06T00:00:00.000Z" }),
      ],
      riferimento,
    );
    const maggio = finestra.find((c) => c.mese === "2026-05");
    expect(maggio?.ordini).toBe(2);
    expect(maggio?.completati).toBe(1);
    expect(finestra.every((c) => c.completati <= c.ordini)).toBe(true);
  });

  it("etichetta il mese in italiano abbreviato con l'anno a due cifre", () => {
    const finestra = andamentoMensile([], new Date("2026-01-10T00:00:00.000Z"), 2);
    expect(finestra.map((c) => c.etichetta)).toEqual(["dic 25", "gen 26"]);
  });

  it("riconosce una finestra senza nessun ordine", () => {
    expect(andamentoVuoto(andamentoMensile([], riferimento))).toBe(true);
    expect(
      andamentoVuoto(andamentoMensile([ordine({ created_at: "2026-08-02T00:00:00.000Z" })], riferimento)),
    ).toBe(false);
  });
});

describe("ordinaAnnunciPerGestione", () => {
  it("mette in cima ciò su cui il venditore può agire adesso", () => {
    const ordinati = ordinaAnnunciPerGestione([
      annuncio("venduto"),
      annuncio("attivo"),
      annuncio("modifiche_richieste"),
      annuncio("bozza"),
    ]);
    expect(ordinati.map((a) => a.stato)).toEqual([
      "modifiche_richieste",
      "bozza",
      "attivo",
      "venduto",
    ]);
  });

  it("non riordina annunci nello stesso stato", () => {
    const primo = { stato: "attivo" as ListingStato, id: 1 };
    const secondo = { stato: "attivo" as ListingStato, id: 2 };
    expect(ordinaAnnunciPerGestione([primo, secondo]).map((a) => a.id)).toEqual([1, 2]);
  });

  it("non modifica l'array ricevuto", () => {
    const originale = [annuncio("venduto"), annuncio("bozza")];
    ordinaAnnunciPerGestione(originale);
    expect(originale.map((a) => a.stato)).toEqual(["venduto", "bozza"]);
  });

  it("copre tutti e nove gli stati annuncio, con priorità distinte", () => {
    const stati = Object.keys(PRIORITA_ANNUNCIO) as ListingStato[];
    expect(stati).toHaveLength(9);
    // Ogni stato dell'enum ha un'etichetta e una priorità: se la Fase 9 ne
    // aggiungesse uno, questo caso lo direbbe invece di lasciarlo `undefined`
    // dentro una `sort`, dove diventerebbe `NaN` e un ordine arbitrario.
    for (const stato of Object.keys(ETICHETTA_STATO) as ListingStato[]) {
      expect(PRIORITA_ANNUNCIO[stato]).toBeTypeOf("number");
    }
    expect(new Set(Object.values(PRIORITA_ANNUNCIO)).size).toBe(9);
  });
});

describe("contratto della dashboard", () => {
  const pagina = leggi("src/app/vendite/page-client.tsx");

  it("non chiama incassato o payout un valore che i dati non dimostrano", () => {
    const senzaCommenti = pagina
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    // Nessuna etichetta afferma un incasso, un payout o un saldo: quei fatti
    // vivono nella 7b e questi dati non li dimostrano.
    for (const promessa of ["Incassato", "Incassi", "Payout", "Saldo", "Guadagn", "Ricavi"]) {
      expect(senzaCommenti).not.toInclude(promessa);
    }
    // E il KPI monetario lo dice esplicitamente a chi legge, non solo a chi
    // legge il codice.
    expect(senzaCommenti).toInclude("non un incassato");
  });

  it("legge gli ordini una volta sola e li passa alla lista", () => {
    // Due letture dello stesso elenco possono divergere: i KPI direbbero un
    // numero e la lista sotto un altro.
    expect(pagina).toInclude("OrderListView");
    expect(pagina).not.toInclude("<OrderList ");
    expect(pagina.match(/\.vendite\(\)/g) ?? []).toHaveLength(1);
  });

  it("non attribuisce i completamenti al mese in cui sarebbero avvenuti", () => {
    // Entrambe le serie sono raggruppate per mese di ricezione. Chiamare la
    // seconda «Completati» e basta la farebbe leggere come «completati in quel
    // mese», che è un fatto che nessuna colonna leggibile dal client dimostra.
    expect(pagina).toInclude("Di cui oggi completati");
    expect(pagina).not.toInclude('completati: { label: "Completati"');
    expect(pagina).toInclude("non i completamenti avvenuti in quel");
  });

  it("non introduce transizioni di ciclo di vita sull'annuncio", () => {
    for (const scrittura of ["pubblica(", "sospendi(", "scadi(", "aggiorna("]) {
      expect(pagina).not.toInclude(scrittura);
    }
  });

  it("non aggiunge una libreria di grafici: usa quella già in package.json", () => {
    expect(pagina).toInclude('from "recharts"');
    const dipendenze = JSON.parse(leggi("package.json")) as {
      dependencies: Record<string, string>;
    };
    expect(dipendenze.dependencies.recharts).toBeTruthy();
  });
});

describe("la guardia di /vendite", () => {
  const route = leggi("src/app/vendite/page.tsx");
  const senzaCommenti = route
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

  it("verifica la sessione sul server, prima di rendere la dashboard", () => {
    // La verifica deve stare nella route (server), non nel page-client: un
    // controllo fatto dopo il primo paint e' un cartello, non una guardia.
    expect(senzaCommenti).toInclude("getSupabaseServerClient()");
    expect(senzaCommenti).toMatch(/auth\.getUser\(\)/);
    const guardia = senzaCommenti.indexOf("if (!utente)");
    const render = senzaCommenti.indexOf("<VenditePageClient />");
    expect(guardia).toBeGreaterThan(-1);
    expect(guardia).toBeLessThan(render);
  });

  it("manda l'anonimo ad /accedi, e non gli mostra un testo d'errore", () => {
    // Il comportamento precedente: la route rendeva comunque, e `vendite()`
    // senza sessione produceva il proprio errore. Una pagina privata che si
    // presenta come rotta invece che come chiusa.
    expect(senzaCommenti).toInclude('from "next/navigation"');
    expect(senzaCommenti).toInclude('const PERCORSO_ACCESSO = "/accedi"');
    expect(senzaCommenti).toInclude("redirect(PERCORSO_ACCESSO)");
  });

  it("non inventa un `?next=`, perche' /accedi non lo legge", () => {
    // `percorsoRelativoSicuro` esiste, ma la convenzione vale per
    // /auth/callback: dopo il login /accedi manda sempre a /home. Un parametro
    // che nessuno legge sarebbe un redirect che sembra funzionare e non
    // funziona.
    expect(senzaCommenti).not.toInclude("next=");
    expect(senzaCommenti).not.toInclude("percorsoRelativoSicuro");
    expect(leggi("src/app/accedi/page-client.tsx")).not.toInclude("percorsoRelativoSicuro");
  });

  it("chiude anche il ramo in cui Supabase non e' configurato", () => {
    // `getSupabaseServerClient()` torna null senza variabili d'ambiente. Su una
    // pagina privata quel ramo deve cadere nello stesso redirect: nessuna
    // sessione verificabile significa nessun accesso, non accesso libero.
    expect(senzaCommenti).toMatch(/client \?[\s\S]*?: null/);
  });

  it("ferma il prerender, altrimenti il redirect verrebbe cotto nella build", () => {
    // In CI `bun run build` gira senza variabili d'ambiente: senza questo, il
    // ramo `client === null` valuterebbe `redirect()` durante la generazione
    // statica e /vendite rimanderebbe ad /accedi anche a sessione valida.
    expect(senzaCommenti).toInclude("await connection()");
    expect(senzaCommenti).toInclude('from "next/server"');
  });

  it("non introduce un middleware globale per una route sola", () => {
    // Un intercettore su ogni richiesta del sito per risolvere un percorso solo.
    for (const file of ["src/middleware.ts", "middleware.ts", "src/proxy.ts", "proxy.ts"]) {
      expect(existsSync(join(progetto, file))).toBe(false);
    }
  });

  it("non tocca KPI, grafici o ciclo di vita: la dashboard e' invariata", () => {
    // La route ora decide chi entra. Che cosa si vede una volta entrati resta
    // esattamente dov'era, cioe' nel page-client.
    for (const estraneo of ["Kpi", "recharts", "OrderService", "ListingService", "riepilogoVenditore"]) {
      expect(senzaCommenti).not.toInclude(estraneo);
    }
  });
});

describe("mieiAnnunci", () => {
  const servizio = leggi("src/services/listing-service.ts");

  it("filtra per seller_id invece di affidarsi alla sola RLS", () => {
    const corpo = servizio.slice(
      servizio.indexOf("async mieiAnnunci"),
      servizio.indexOf("/** bozza | modifiche_richieste → attivo. */"),
    );
    expect(corpo).toInclude('.eq("seller_id", user.id)');
  });

  it("non interroga la tabella senza sessione", () => {
    const corpo = servizio.slice(servizio.indexOf("async mieiAnnunci"));
    const guardia = corpo.indexOf("if (!user) return []");
    const query = corpo.indexOf('.from("listings")');
    expect(guardia).toBeGreaterThan(-1);
    expect(guardia).toBeLessThan(query);
  });

  it("chiede solo colonne che il GRANT per authenticated concede", () => {
    // `revoke select on public.listings from authenticated` più un GRANT a
    // elenco chiuso: una colonna fuori da quell'elenco fa fallire l'intera
    // select con 42501, non la restituisce vuota.
    const migrazione = readFileSync(
      join(progetto, "../supabase/migrations/20260729230000_security_invariants.sql"),
      "utf8",
    );
    const grant = migrazione.slice(
      migrazione.indexOf("grant select (", migrazione.indexOf("revoke select on public.listings")),
    );
    const concesse = new Set(
      grant
        .slice(grant.indexOf("(") + 1, grant.indexOf(")"))
        .split(",")
        .map((c) => c.trim()),
    );
    expect(concesse.has("seller_id")).toBe(true);
    expect(concesse.has("created_at")).toBe(true);
    // Le colonne della traccia di moderazione restano fuori, e la dashboard
    // non deve averle riaperte.
    for (const privata of ["stato_motivo", "stato_aggiornato_da", "stato_aggiornato_at"]) {
      expect(concesse.has(privata)).toBe(false);
      expect(servizio.slice(servizio.indexOf("const COLONNE_PROPRIETARIO"))).not.toInclude(
        `"${privata}"`,
      );
    }
  });
});

describe("copertura degli stati", () => {
  it("nomina ogni stato ordine del dominio", () => {
    const stati: OrderStatus[] = [
      "in_attesa_pagamento",
      "pagato",
      "in_preparazione",
      "spedito",
      "consegnato",
      "verifica",
      "completato",
      "contestato",
      "rimborsato",
      "annullato",
    ];
    for (const stato of stati) {
      const riga = ordine({ stato });
      expect(() => riepilogoVenditore([riga], [])).not.toThrow();
      expect(distribuzionePerStato([riga])).toHaveLength(1);
    }
  });
});
