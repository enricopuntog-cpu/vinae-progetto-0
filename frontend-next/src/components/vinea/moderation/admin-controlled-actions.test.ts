// Operazioni Admin — le azioni controllate.
//
// Il punto di questi test non e che i pulsanti esistano, ma che non esista
// niente di piu: il back-office puo cambiare la visibilita di un annuncio e
// chiudere una contestazione, e nient'altro. Ogni assenza qui sotto — rimborso,
// payout, provider, sospensione account, cancellazione di un Club — e una
// decisione, e un test che la sorveglia e cio che la tiene tale.

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  TRANSIZIONE_UX,
  transizioniAmmesse,
} from "@/components/vinea/moderation/ListingModerationActions";

const root = join(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(join(root, path), "utf8");
// I commenti dichiarano cosa resta fuori — «finche refund e provider restano
// spenti» — e cercare quelle parole nel testo integrale troverebbe la promessa
// invece del codice. Le assenze si verificano sul codice.
const soloCodice = (sorgente: string) =>
  sorgente
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
const panel = read("src/components/vinea/moderation/ModerationPanelClient.tsx");
const search = read("src/components/vinea/moderation/AdminOperationsSearch.tsx");
const azioni = read("src/components/vinea/moderation/ListingModerationActions.tsx");
const migration = read("../supabase/migrations/20260810180000_phase_9b_moderation_actions.sql");

// Gli stati ammessi non si leggono dal componente ma dalla migrazione che li
// impone: se un giorno la porta SQL si restringe e il componente no, il test
// deve rompersi dalla parte del componente.
const originiDaSql = (funzione: string): string[] => {
  const inizio = migration.indexOf(`create or replace function public.${funzione}(`);
  expect(inizio).toBeGreaterThan(-1);
  const corpo = migration.slice(inizio, migration.indexOf("$$;", inizio));
  const array = corpo.slice(corpo.indexOf("array["), corpo.indexOf("]::public.listing_stato[]"));
  return [...array.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
};

const RPC_PER_TRANSIZIONE = {
  in_revisione: "moderazione_annuncio_in_revisione",
  modifiche_richieste: "moderazione_annuncio_modifiche_richieste",
  sospeso: "moderazione_annuncio_sospendi",
  rifiutato: "moderazione_annuncio_rifiuta",
  attivo: "moderazione_annuncio_ripristina",
} as const;

describe("Annuncio — transizioni ammesse", () => {
  it("propone esattamente cio che la porta SQL accetta, stato per stato", () => {
    const stati = ["bozza", "in_revisione", "modifiche_richieste", "attivo", "sospeso", "rifiutato"];
    for (const stato of stati) {
      const attese = (Object.keys(RPC_PER_TRANSIZIONE) as Array<keyof typeof RPC_PER_TRANSIZIONE>)
        .filter((transizione) => originiDaSql(RPC_PER_TRANSIZIONE[transizione]).includes(stato))
        .sort();
      expect(transizioniAmmesse(stato).sort()).toEqual(attese);
    }
  });

  it("non propone nulla su un annuncio venduto o riservato, che il motore rifiuta", () => {
    // private.moderazione_annuncio_transizione li respinge sempre: proporre un
    // comando li equivarrebbe a promettere un errore.
    expect(transizioniAmmesse("venduto")).toEqual([]);
    expect(transizioniAmmesse("riservato")).toEqual([]);
    expect(migration).toContain("rifiuta riservato e venduto");
  });

  it("non propone nulla quando lo stato non e noto", () => {
    expect(transizioniAmmesse(null)).toEqual([]);
    expect(transizioniAmmesse(undefined)).toEqual([]);
    expect(transizioniAmmesse("")).toEqual([]);
  });

  it("copre le cinque transizioni e nessun comando in piu", () => {
    expect(Object.keys(TRANSIZIONE_UX).sort()).toEqual(
      ["attivo", "in_revisione", "modifiche_richieste", "rifiutato", "sospeso"].sort(),
    );
    for (const voce of Object.values(TRANSIZIONE_UX)) {
      // Nome, effetto dichiarato e conferma: un pulsante che non dice cosa fa
      // non e un comando controllato.
      expect(voce.nome.length).toBeGreaterThan(0);
      expect(voce.effetto.length).toBeGreaterThan(0);
      expect(voce.cta.length).toBeGreaterThan(0);
    }
    expect(TRANSIZIONE_UX.sospeso.sensibile).toBe(true);
    expect(TRANSIZIONE_UX.rifiutato.sensibile).toBe(true);
  });

  it("non espone cancellazione, vendita forzata o prenotazione forzata", () => {
    for (const vietata of ["venduto", "riservato", "elimina", "delete", "cancella"]) {
      expect(azioni.toLowerCase()).not.toContain(`admin-listing-action-${vietata}`);
    }
    expect(azioni).not.toContain("window.confirm");
  });
});

describe("Annuncio — pratica aperta contro azione diretta", () => {
  it("con una pratica aperta manda alla segnalazione esatta, senza azioni a lato", () => {
    expect(search).toContain('const aperte = reports.filter(praticaAperta);');
    expect(search).toContain('report.stato !== "risolta" && report.stato !== "respinta"');
    expect(search).toContain('aperte.length > 0 ? "Gestisci segnalazione"');
    // Il focus e sull'annuncio esatto, non sulla coda intera.
    expect(search).toContain('onFocusReports({ kind: "annuncio", id: entity.id, label: entity.title })');
    // Il ramo con pratica aperta non monta le azioni dirette.
    expect(search).toContain('data-testid="admin-listing-actions-via-report"');
  });

  it("senza pratica aperta monta le azioni dirette sull'annuncio", () => {
    expect(search).toContain("<ListingModerationActions");
    expect(search).toContain("stato={entity.status}");
    expect(search).toContain("onTransizione={onTransizioneAnnuncio}");
  });

  it("riusa il dialogo di moderazione esistente invece di duplicarlo", () => {
    // Nessun secondo sistema: la lavorazione della pratica resta quella del
    // pannello, e la scheda Annunci ci rimanda invece di riscriverla.
    expect(search).not.toContain("DialogoAzioni");
    expect(search).not.toContain("azionePratica");
    expect(panel.match(/const DialogoAzioni =/g)?.length).toBe(1);
    expect(azioni).not.toContain("azionePratica");
  });
});

describe("Annuncio — conferma, concorrenza, aggiornamento", () => {
  it("richiede una motivazione prima di poter confermare", () => {
    expect(azioni).toContain("const pronta = motivazione.trim().length > 0;");
    expect(azioni).toContain("disabled={!pronta || occupato}");
    expect(azioni).toContain("Motivazione (obbligatoria)");
  });

  it("chiede conferma in un dialogo, con l'effetto dichiarato e l'avviso sulle azioni gravi", () => {
    expect(azioni).toContain('data-testid="admin-listing-action-dialog"');
    expect(azioni).toContain("{TRANSIZIONE_UX[scelta].effetto}");
    expect(azioni).toContain('data-testid="admin-listing-action-warning"');
  });

  it("blocca il doppio invio prima ancora del render disabilitato", () => {
    expect(azioni).toContain("const invioLocale = useRef(false);");
    expect(azioni).toContain("if (!scelta || !onTransizione || !pronta || occupato || invioLocale.current) return;");
    expect(azioni).toContain("const occupato = invio || inCorso !== null;");
  });

  it("rilegge la scheda dopo un'azione riuscita", () => {
    expect(azioni).toContain("aggiornato = await onAggiorna();");
    expect(search).toContain("const aggiornaDettaglio = async (): Promise<boolean> => {");
    expect(search).toContain("onAggiorna={aggiornaDettaglio}");
  });

  it("se la rilettura fallisce lo dice e non ripete la scrittura", () => {
    expect(azioni).toContain("Azione eseguita, aggiornamento dei dati non riuscito");
    // La mutazione sta in un try che esce con `return` sull'errore: dopo il
    // punto di non ritorno non c'e nessun secondo `onTransizione`.
    expect(azioni.match(/await onTransizione\(/g)?.length).toBe(1);
    expect(azioni).not.toContain("retry");
  });

  it("un'azione dalla scheda passa dal controller, cosi coda e audit si rileggono", () => {
    // `transizioneAnnuncio` del controller rilegge tutto: audit compreso. Se la
    // scheda chiamasse direttamente il servizio, la tab Audit resterebbe vecchia.
    expect(panel).toContain("onTransizioneAnnuncio={transizioneAnnuncio}");
    expect(panel).toContain("inCorso={inCorso}");
    expect(search).not.toContain("azioneAnnuncio(");
    expect(azioni).not.toContain("audit_registra");
    expect(azioni).not.toContain("moderation_audit_log");
  });
});

describe("Contestazioni — due esiti e nessuna leva manuale di pagamento", () => {
  it("dall'ordine si arriva alla contestazione esatta", () => {
    expect(search).toContain('data-testid="admin-focus-order-dispute"');
    expect(search).toContain("Gestisci contestazione");
    expect(search).toContain("onFocusDispute({ orderId: entity.id");
    expect(panel).toContain("contestazioni.filter((riga) => riga.orderId === focusContestazione.orderId)");
  });

  it("mostra i dati su cui si decide, ordine per esteso compreso", () => {
    for (const campo of [
      "{riga.orderId}",
      "{riga.ordineStato}",
      "{riga.apertaDaUsername}",
      "{riga.sellerUsername}",
      "{riga.motivo}",
      "{riga.descrizione}",
      "{euro(riga.totaleCents)}",
      "{euro(riga.addebitoTotaleCents)}",
      "payout {riga.ordinePayoutStato}",
      "{data(riga.aperturaAt)}",
      "Esito: {riga.esitoNota}",
    ]) {
      expect(panel).toContain(campo);
    }
  });

  it("offre Risolvi e Respingi, entrambi con motivazione obbligatoria", () => {
    const scheda = panel.slice(
      panel.indexOf("const RigaContestazione ="),
      panel.indexOf("const RigaAudit ="),
    );
    expect(scheda).toContain('void esegui("risolta")');
    expect(scheda).toContain('void esegui("respinta")');
    expect(scheda).toContain("const pronta = nota.trim().length > 0;");
    // I due pulsanti e nessun terzo: entrambi fermi senza motivazione.
    expect(scheda.match(/disabled=\{!pronta \|\| occupato\}/g)?.length).toBe(2);
    expect(scheda.match(/void esegui\(/g)?.length).toBe(2);
  });

  it("non inventa un terzo esito e blocca il doppio invio", () => {
    expect(panel).not.toContain('esegui("rimborsata")');
    expect(panel).toContain("if (!onRisolvi || !pronta || occupato || invioLocale.current) return;");
  });

  it("su una pratica terminale non offre alcuna decisione", () => {
    expect(panel).toContain(
      'riga.stato === "aperta" || riga.stato === "in_valutazione"',
    );
    expect(panel).toContain("Pratica chiusa: non ammette altre decisioni.");
  });

  it("non espone rimborso, payout, incasso o chiamate al provider", () => {
    const superficie = soloCodice(`${panel}\n${search}\n${azioni}`).toLowerCase();
    for (const vietato of [
      "refund",
      "rimborsa",
      "capture",
      "payout_release",
      "rilascia_payout",
      "stripe",
      "transfer_data",
      "on_behalf_of",
      '"rimborsata"',
    ]) {
      expect(superficie).not.toContain(vietato);
    }
    // L'unica RPC di contestazione raggiunta e quella dei due esiti.
    expect(superficie).not.toContain("ordine_contestazione_risolvi");
    // La UI non nega gli effetti D10 sull'ordine: dichiara solo che non offre
    // leve manuali separate di rimborso o pagamento.
    expect(panel).toContain("Il rimborso non si dispone da qui");
    expect(search).toContain("La decisione chiude la contestazione secondo il workflow esistente");
    expect(search).toContain("Il rimborso e le operazioni");
  });
});

describe("Utenti e Club — nessuna mutazione", () => {
  // Le due schede mostrano ruolo e modalita di pubblicazione: cercare quelle
  // parole troverebbe cio che si legge, non cio che si comanda. Il comando in
  // una scheda e un `onClick`, quindi si contano quelli.
  const comandi = (blocco: string) => blocco.match(/onClick=/g) ?? [];

  it("il dettaglio utente non offre alcun comando sull'account", () => {
    const blocco = soloCodice(
      search.slice(search.indexOf("const DettaglioUtente"), search.indexOf("const DettaglioAnnuncio")),
    );
    // Un solo comando: il rimando alle segnalazioni correlate. Il profilo
    // pubblico e un link, non un'azione.
    expect(comandi(blocco).length).toBe(1);
    expect(blocco).toContain('onFocusReports({ kind: "profilo"');
    expect(blocco).toContain("Profilo pubblico");
    for (const vietato of ["rpc(", "update(", "sospendi", "banna", "elimina", "setRole", "qualifica"]) {
      expect(blocco).not.toContain(vietato);
    }
  });

  it("il dettaglio club non offre azioni distruttive", () => {
    const blocco = soloCodice(
      search.slice(search.indexOf("const DettaglioClub"), search.indexOf("const risultatiPerScope")),
    );
    expect(comandi(blocco).length).toBe(1);
    expect(blocco).toContain('onFocusReports({ kind: "club"');
    for (const vietato of ["rpc(", "update(", "elimina", "sospendi", "banna", "espelli", "ownerId ="]) {
      expect(blocco).not.toContain(vietato);
    }
  });

  it("sul Club la pratica resta limitata a informazioni e chiusura", () => {
    expect(panel).toContain(
      'if (report.targetType === "club") return ["info_richieste", "chiusura"];',
    );
  });
});

describe("Errori e cancello", () => {
  it("non lascia arrivare il messaggio grezzo del database", () => {
    // Phase9Error ferma gia il testo di Postgres; qui si aggiunge solo la
    // lettura dei codici voluti.
    expect(azioni).toContain("if (errore instanceof Phase9Error)");
    expect(azioni).toContain('if (errore.code === "42501")');
    expect(azioni).toContain('if (errore.code === "22023")');
    expect(azioni).toContain('if (errore.code === "P0001")');
    expect(azioni).toContain("Lo stato e cambiato oppure la pratica e gia chiusa");
    expect(azioni).toContain("Azione non riuscita. Controlla la connessione e riprova.");
    for (const superficie of [azioni, search]) {
      expect(superficie).not.toContain("error.message");
      expect(superficie).not.toContain("errore.message");
      expect(superficie).not.toContain("PGRST");
    }
    // L'errore non viene mai scambiato per un successo.
    expect(azioni).toContain("setErrore(messaggioAzione(e));");
    expect(panel).toContain("setErrore(messaggioAzione(e));");
  });

  it("mantiene il cancello Admin reale davanti a tutta la superficie", () => {
    const gate = panel.indexOf("if (!moderatore) {");
    expect(gate).toBeGreaterThan(-1);
    expect(panel).toContain('const moderatore = authRuolo === "admin";');
    for (const superficie of ["<AdminOperationsSearch", "onTransizioneAnnuncio={transizioneAnnuncio}"]) {
      expect(panel.indexOf(superficie)).toBeGreaterThan(gate);
    }
  });

  it("senza servizio non mostra comandi", () => {
    expect(azioni).toContain('data-testid="admin-listing-actions-unavailable"');
    expect(azioni).toContain("Le azioni non sono disponibili in questa configurazione.");
  });
});
