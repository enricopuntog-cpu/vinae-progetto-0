import { describe, expect, it } from "bun:test";
import {
  AVVISO_ACQUISTI_NON_DISPONIBILI,
  MAX_PREZZO_CENTS,
  MIN_PREZZO_CENTS,
  STATI_ANNUNCIO_ACCESSORIO,
  annuncioAperto,
  centesimiDaEuro,
  messaggioStatoAnnuncio,
  statoModificabile,
  messaggioErroreAnnunci,
  messaggioVenditoreNonAmmesso,
  moduloAnnuncioVuoto,
  moduloDaAnnuncio,
  parseAnnuncioAccessorio,
  parsePreventivoAnnuncio,
  parsePreventivoEconomico,
  parseStatoInterruttoreAnnunci,
  parseStatoVendita,
  percentualeDaBps,
  quantitaMassimaAnnuncio,
  validaModuloAnnuncio,
} from "./annunci-accessori";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

const annuncioJson = (extra: Record<string, unknown> = {}) => ({
  id: U1,
  cantina_id: U2,
  stato: "bozza",
  quantita: 2,
  prezzo_unitario_cents: 1200,
  condizione: "come_nuovo",
  descrizione: "Due calici.",
  conforme: true,
  spedizione: { peso_g: 420, lunghezza_mm: 90, larghezza_mm: 90, altezza_mm: 230, fragile: true },
  posseduti: 6,
  impegnati: 2,
  disponibili: 4,
  foto: 1,
  ritirato_at: null,
  created_at: "2026-10-21T10:00:00Z",
  updated_at: "2026-10-21T10:00:00Z",
  pubblicato_at: null,
  versione: 0,
  pubblico: false,
  moderazione: null,
  ...extra,
});

const moderazioneJson = (extra: Record<string, unknown> = {}) => ({
  provvedimento: "sospensione",
  motivo: "Foto da verificare",
  aggiornato_at: "2026-10-22T09:00:00Z",
  ...extra,
});

// Preventivo come lo dà il database: 24,00 € richiesti, margine 10%.
const preventivoJson = (extra: Record<string, unknown> = {}) => ({
  dominio: "accessori_enologici",
  classe: "privato",
  configId: 3,
  margineConfigId: 1,
  quantita: 2,
  prezzoUnitarioCents: 1200,
  subtotaleCents: 2400,
  commissioneCents: 322,
  totaleCents: 2722,
  margineObiettivoBps: 1000,
  riferimentoPercentualeBps: 209,
  riferimentoFissoCents: 25,
  costoPagamentoRiferimentoCents: 82,
  quotaVineaCents: 240,
  spedizioneCents: null,
  coperturaPagamentoSpedizioneCents: null,
  addebitoTotaleCents: null,
  ...extra,
});

const rispostaPreventivo = (extra: Record<string, unknown> = {}) => ({
  dominio: "accessori_enologici",
  classe: "privato",
  venditore_ammesso: true,
  motivo: null,
  vendite_attive: false,
  disponibili: 4,
  preventivo: preventivoJson(),
  spedizione: {
    disponibile: false,
    motivi: ["tariffa_accessori_non_configurata"],
    pagata_da: "acquirente",
    commissione_su_spedizione: false,
    imballaggio_a_cura_del: "venditore",
  },
  ...extra,
});

describe("parseAnnuncioAccessorio", () => {
  it("legge un annuncio coerente", () => {
    const a = parseAnnuncioAccessorio(annuncioJson());
    expect(a?.quantita).toBe(2);
    expect(a?.prezzoUnitarioCents).toBe(1200);
    expect(a?.impegnati).toBe(2);
    expect(a?.disponibili).toBe(4);
    expect(a?.spedizione.fragile).toBe(true);
  });

  it("scarta stati che non esistono: né «attivo», né acquistabile, né la vecchia «in_revisione»", () => {
    for (const stato of ["attivo", "venduto", "riservato", "acquistabile", "in_revisione"]) {
      expect(parseAnnuncioAccessorio(annuncioJson({ stato }))).toBeNull();
    }
    expect([...STATI_ANNUNCIO_ACCESSORIO]).toEqual([
      "bozza", "pubblicato", "modifiche_richieste", "oscurato", "ritirato",
    ]);
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "bozza" }))?.stato).toBe("bozza");
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "ritirato" }))?.stato).toBe("ritirato");
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "pubblicato", pubblico: true, pubblicato_at: "2026-10-22T08:00:00Z" }))?.pubblico).toBe(true);
  });

  it("l'esito della moderazione c'è se e solo se Vinea è intervenuta", () => {
    const mod = moderazioneJson();
    const oscurato = parseAnnuncioAccessorio(annuncioJson({ stato: "oscurato", moderazione: mod }));
    expect(oscurato?.moderazione).toEqual({
      provvedimento: "sospensione", motivo: "Foto da verificare", aggiornatoAt: "2026-10-22T09:00:00Z",
    });
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "modifiche_richieste", moderazione: moderazioneJson({ provvedimento: null }) }))?.moderazione?.provvedimento).toBeNull();
    // oscurato senza motivo, o un esito su un annuncio che non è in moderazione: risposta guasta
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "oscurato" }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "bozza", moderazione: mod }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "oscurato", moderazione: moderazioneJson({ provvedimento: "ban" }) }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "oscurato", moderazione: "Foto" }))).toBeNull();
  });

  it("visibile solo se pubblicato: un annuncio in altro stato che si dichiara pubblico è guasto", () => {
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "bozza", pubblico: true }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ stato: "oscurato", pubblico: true, moderazione: moderazioneJson() }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ versione: -1 }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ pubblico: "si" }))).toBeNull();
  });

  it("scarta quantità e prezzi fuori dai limiti del database", () => {
    expect(parseAnnuncioAccessorio(annuncioJson({ quantita: 0 }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ quantita: 121 }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ prezzo_unitario_cents: MIN_PREZZO_CENTS - 1 }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ prezzo_unitario_cents: MAX_PREZZO_CENTS + 1 }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ prezzo_unitario_cents: 12.5 }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ id: "non-uuid" }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ condizione: "rotto" }))).toBeNull();
    expect(parseAnnuncioAccessorio(null)).toBeNull();
    expect(parseAnnuncioAccessorio([])).toBeNull();
  });

  it("accetta misure nulle e rifiuta spedizione malformata", () => {
    const vuota = { peso_g: null, lunghezza_mm: null, larghezza_mm: null, altezza_mm: null, fragile: false };
    expect(parseAnnuncioAccessorio(annuncioJson({ spedizione: vuota }))?.spedizione.pesoG).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ spedizione: { ...vuota, fragile: "no" } }))).toBeNull();
    expect(parseAnnuncioAccessorio(annuncioJson({ spedizione: { ...vuota, peso_g: "420" } }))).toBeNull();
  });
});

describe("parseStatoVendita", () => {
  const base = {
    abilitata: true, pubblicazione_aperta: false, vendite_attive: false, classe: "privato",
    venditore_ammesso: true, motivo: null,
  };

  it("legge lo stato e conserva il motivo del Partner", () => {
    expect(parseStatoVendita(base)?.abilitata).toBe(true);
    expect(parseStatoVendita(base)?.pubblicazioneAperta).toBe(false);
    expect(parseStatoVendita({ ...base, pubblicazione_aperta: true })?.pubblicazioneAperta).toBe(true);
    expect(parseStatoVendita({ ...base, pubblicazione_aperta: undefined })).toBeNull();
    const p = parseStatoVendita({ ...base, classe: "partner", venditore_ammesso: false, motivo: "partner_percorso_non_consentito" });
    expect(p?.venditoreAmmesso).toBe(false);
    expect(p?.classe).toBe("partner");
  });

  it("una risposta che dichiara le vendite attive non è quella promessa: sezione chiusa", () => {
    expect(parseStatoVendita({ ...base, vendite_attive: true })).toBeNull();
    expect(parseStatoVendita({ ...base, vendite_attive: undefined })).toBeNull();
    expect(parseStatoVendita({ ...base, classe: "admin" })).toBeNull();
  });
});

describe("parsePreventivoEconomico", () => {
  it("legge un preventivo coerente e ne espone le parti", () => {
    const p = parsePreventivoEconomico(preventivoJson());
    expect(p).toMatchObject({
      subtotaleCents: 2400, totaleCents: 2722, commissioneCents: 322,
      quotaVineaCents: 240, costoPagamentoCents: 82, margineObiettivoBps: 1000,
    });
  });

  it("scarta una somma che non torna invece di mostrarla", () => {
    expect(parsePreventivoEconomico(preventivoJson({ subtotaleCents: 2399 }))).toBeUndefined();
    expect(parsePreventivoEconomico(preventivoJson({ totaleCents: 2723 }))).toBeUndefined();
    expect(parsePreventivoEconomico(preventivoJson({ quotaVineaCents: 241 }))).toBeUndefined();
    expect(parsePreventivoEconomico(preventivoJson({ margineObiettivoBps: 9000 }))).toBeUndefined();
    expect(parsePreventivoEconomico(preventivoJson({ classe: "admin" }))).toBeUndefined();
    expect(parsePreventivoEconomico("12")).toBeUndefined();
  });

  it("questa build non conosce tariffe di spedizione: se ne compare una, non si mostra", () => {
    expect(parsePreventivoEconomico(preventivoJson({ spedizioneCents: 0 }))).toBeUndefined();
    expect(parsePreventivoEconomico(preventivoJson({ addebitoTotaleCents: 2722 }))).toBeUndefined();
    expect(parsePreventivoEconomico(preventivoJson({ coperturaPagamentoSpedizioneCents: 0 }))).toBeUndefined();
  });

  it("nullo resta nullo (venditore non ammesso)", () => {
    expect(parsePreventivoEconomico(null)).toBeNull();
  });
});

describe("parsePreventivoAnnuncio", () => {
  it("legge preventivo e spedizione indisponibile", () => {
    const r = parsePreventivoAnnuncio(rispostaPreventivo());
    expect(r?.preventivo?.totaleCents).toBe(2722);
    expect(r?.spedizione.disponibile).toBe(false);
    expect(r?.spedizione.motivi).toEqual(["tariffa_accessori_non_configurata"]);
    expect(r?.disponibili).toBe(4);
  });

  it("un Partner non riceve preventivo: né dal database né dal parser", () => {
    const ok = parsePreventivoAnnuncio(
      rispostaPreventivo({ classe: "partner", venditore_ammesso: false, motivo: "partner_percorso_non_consentito", preventivo: null }),
    );
    expect(ok?.preventivo).toBeNull();
    expect(
      parsePreventivoAnnuncio(rispostaPreventivo({ classe: "partner", venditore_ammesso: false, preventivo: preventivoJson() })),
    ).toBeNull();
  });

  it("rifiuta risposte fuori contratto: dominio diverso, vendite attive, spedizione disponibile", () => {
    expect(parsePreventivoAnnuncio(rispostaPreventivo({ dominio: "vino" }))).toBeNull();
    expect(parsePreventivoAnnuncio(rispostaPreventivo({ vendite_attive: true }))).toBeNull();
    expect(
      parsePreventivoAnnuncio(rispostaPreventivo({ spedizione: { disponibile: true, motivi: [] } })),
    ).toBeNull();
    expect(parsePreventivoAnnuncio(rispostaPreventivo({ preventivo: preventivoJson({ totaleCents: 1 }) }))).toBeNull();
  });
});

describe("parseStatoInterruttoreAnnunci", () => {
  const ok = {
    preparazione_attiva: false, pubblicazione_attiva: false, cantina_funzione_attiva: true,
    puo_rilasciare: false, categorie_pubblicabili: 0,
  };

  it("legge i due interruttori e il conteggio delle categorie approvate", () => {
    const s = parseStatoInterruttoreAnnunci(ok);
    expect(s).toEqual({
      preparazioneAttiva: false, pubblicazioneAttiva: false, cantinaFunzioneAttiva: true,
      puoRilasciare: false, categoriePubblicabili: 0,
    });
    expect(parseStatoInterruttoreAnnunci({ ...ok, pubblicazione_attiva: true, categorie_pubblicabili: 2 })?.pubblicazioneAttiva).toBe(true);
  });

  it("rifiuta risposte incomplete o incoerenti", () => {
    expect(parseStatoInterruttoreAnnunci({ ...ok, categorie_pubblicabili: -1 })).toBeNull();
    expect(parseStatoInterruttoreAnnunci({ ...ok, categorie_pubblicabili: "2" })).toBeNull();
    expect(parseStatoInterruttoreAnnunci({ ...ok, pubblicazione_attiva: "no" })).toBeNull();
    expect(parseStatoInterruttoreAnnunci(null)).toBeNull();
  });
});

describe("stato e messaggi per il venditore", () => {
  it("si corregge in bozza, con modifiche richieste o da pubblicato; mai oscurato o ritirato", () => {
    expect(STATI_ANNUNCIO_ACCESSORIO.filter(statoModificabile)).toEqual(["bozza", "pubblicato", "modifiche_richieste"]);
  });

  it("aperto è tutto ciò che non è ritirato (impegna i pezzi dell'accessorio)", () => {
    expect(STATI_ANNUNCIO_ACCESSORIO.filter((stato) => annuncioAperto({ stato }))).toEqual([
      "bozza", "pubblicato", "modifiche_richieste", "oscurato",
    ]);
  });

  it("il messaggio dice sempre la verità sulla visibilità e che non si può ancora comprare", () => {
    const visibile = messaggioStatoAnnuncio({ stato: "pubblicato", pubblico: true, moderazione: null });
    expect(visibile).toContain("chiunque può vederlo");
    expect(visibile).toContain(AVVISO_ACQUISTI_NON_DISPONIBILI);
    const nascosto = messaggioStatoAnnuncio({ stato: "pubblicato", pubblico: false, moderazione: null });
    expect(nascosto).toContain("non è visibile al pubblico");
    expect(nascosto).not.toContain("chiunque può vederlo");
    const mod = { provvedimento: "sospensione" as const, motivo: "Foto da verificare", aggiornatoAt: null };
    expect(messaggioStatoAnnuncio({ stato: "oscurato", pubblico: false, moderazione: mod })).toContain("Foto da verificare");
    expect(messaggioStatoAnnuncio({ stato: "oscurato", pubblico: false, moderazione: mod })).toContain("non puoi riaprirlo da solo");
    expect(messaggioStatoAnnuncio({ stato: "modifiche_richieste", pubblico: false, moderazione: mod })).toContain("Foto da verificare");
    expect(messaggioStatoAnnuncio({ stato: "bozza", pubblico: false, moderazione: null })).toContain("la vedi solo tu");
    expect(messaggioStatoAnnuncio({ stato: "ritirato", pubblico: false, moderazione: null })).toContain("non è più in vetrina");
  });

  it("i nuovi errori della pubblicazione sono frasi, non codici", () => {
    for (const hint of [
      "categoria_non_pubblicabile", "contenuto_non_ammesso", "ripubblicazione_bloccata",
      "modifiche_non_effettuate", "moderazione_riservata", "annuncio_pubblicato",
    ]) {
      const m = messaggioErroreAnnunci({ hint }, "ricaduta");
      expect(m).not.toBe("ricaduta");
      expect(m).not.toContain("_");
    }
    expect(messaggioErroreAnnunci({ hint: "ripubblicazione_bloccata" }, "x")).toContain("rimosso da Vinea");
  });
});

describe("centesimiDaEuro", () => {
  it("accetta importi scritti con virgola o punto e al massimo due decimali", () => {
    expect(centesimiDaEuro("12")).toBe(1200);
    expect(centesimiDaEuro("12,5")).toBe(1250);
    expect(centesimiDaEuro("12,50")).toBe(1250);
    expect(centesimiDaEuro("12.05")).toBe(1205);
    expect(centesimiDaEuro(" 0,99 ")).toBe(99);
    expect(centesimiDaEuro("10000")).toBe(1_000_000);
  });

  it("rifiuta tutto il resto invece di indovinare", () => {
    for (const x of ["", " ", "-5", "+5", "1,234", "1.234,56", "12,505", "12,", ",50", "abc", "12 €", "1e3", "12,5,0", "99999999"]) {
      expect(centesimiDaEuro(x)).toBeNull();
    }
  });
});

describe("percentualeDaBps", () => {
  it("rende i punti base come percentuale", () => {
    expect(percentualeDaBps(1000)).toBe("10%");
    expect(percentualeDaBps(1500)).toBe("15%");
    expect(percentualeDaBps(209)).toBe("2,09%");
  });
});

describe("validaModuloAnnuncio", () => {
  const valido = () => ({ ...moduloAnnuncioVuoto("usato"), quantita: "2", prezzo: "12,50", conforme: true });

  it("produce i dati per la porta: prezzo in centesimi interi", () => {
    const v = validaModuloAnnuncio(valido(), U2, 6);
    expect(v.ok).toBe(true);
    if (v.ok) {
      expect(v.dati).toMatchObject({ cantinaId: U2, quantita: 2, prezzoUnitarioCents: 1250, condizione: "usato", conforme: true });
      expect(v.dati.spedizione).toEqual({ pesoG: null, lunghezzaMm: null, larghezzaMm: null, altezzaMm: null, fragile: false });
    }
  });

  it("la quantità non supera i pezzi disponibili né il limite di 120", () => {
    const sopra = validaModuloAnnuncio({ ...valido(), quantita: "7" }, U2, 6);
    expect(sopra.ok).toBe(false);
    if (!sopra.ok) expect(sopra.errori.quantita).toContain("al massimo 6 pezzi");
    expect(validaModuloAnnuncio({ ...valido(), quantita: "6" }, U2, 6).ok).toBe(true);
    expect(validaModuloAnnuncio({ ...valido(), quantita: "121" }, U2, 999).ok).toBe(false);
    expect(validaModuloAnnuncio({ ...valido(), quantita: "120" }, U2, 999).ok).toBe(true);
    const nessuno = validaModuloAnnuncio(valido(), U2, 0);
    expect(nessuno.ok).toBe(false);
    if (!nessuno.ok) expect(nessuno.errori.quantita).toContain("già tutti impegnati");
    for (const q of ["0", "", "1,5", "-1", "abc"]) {
      expect(validaModuloAnnuncio({ ...valido(), quantita: q }, U2, 6).ok).toBe(false);
    }
  });

  it("il prezzo è obbligatorio e resta fra 1 € e 10.000 €", () => {
    for (const p of ["", "0", "0,99", "10000,01", "dodici", "-3"]) {
      const v = validaModuloAnnuncio({ ...valido(), prezzo: p }, U2, 6);
      expect(v.ok).toBe(false);
      if (!v.ok) expect(v.errori.prezzo).toBeTruthy();
    }
    expect(validaModuloAnnuncio({ ...valido(), prezzo: "1" }, U2, 6).ok).toBe(true);
    expect(validaModuloAnnuncio({ ...valido(), prezzo: "10000" }, U2, 6).ok).toBe(true);
  });

  it("le misure del pacco vanno tutte e tre o nessuna", () => {
    const parziale = validaModuloAnnuncio({ ...valido(), lunghezzaMm: "100" }, U2, 6);
    expect(parziale.ok).toBe(false);
    if (!parziale.ok) expect(parziale.errori.lunghezzaMm).toContain("tutte e tre");
    const tutte = validaModuloAnnuncio(
      { ...valido(), pesoG: "420", lunghezzaMm: "100", larghezzaMm: "90", altezzaMm: "230", fragile: true }, U2, 6,
    );
    expect(tutte.ok).toBe(true);
    if (tutte.ok) expect(tutte.dati.spedizione).toEqual({ pesoG: 420, lunghezzaMm: 100, larghezzaMm: 90, altezzaMm: 230, fragile: true });
    expect(validaModuloAnnuncio({ ...valido(), pesoG: "0" }, U2, 6).ok).toBe(false);
    expect(validaModuloAnnuncio({ ...valido(), pesoG: "30001" }, U2, 6).ok).toBe(false);
    expect(validaModuloAnnuncio({ ...valido(), lunghezzaMm: "1501", larghezzaMm: "1", altezzaMm: "1" }, U2, 6).ok).toBe(false);
  });

  it("i dati inviati non contengono classe, margine, commissione, totale o stato", () => {
    const v = validaModuloAnnuncio(valido(), U2, 6);
    expect(v.ok).toBe(true);
    if (v.ok) {
      const chiavi = Object.keys(v.dati).sort();
      expect(chiavi).toEqual(["cantinaId", "condizione", "conforme", "descrizione", "prezzoUnitarioCents", "quantita", "spedizione"]);
    }
  });
});

describe("modulo da annuncio", () => {
  it("ricostruisce il form con il prezzo in euro con virgola", () => {
    const a = parseAnnuncioAccessorio(annuncioJson({ prezzo_unitario_cents: 1250 }));
    expect(a).not.toBeNull();
    const m = moduloDaAnnuncio(a!);
    expect(m.prezzo).toBe("12,5");
    expect(centesimiDaEuro(m.prezzo)).toBe(1250);
    expect(m.pesoG).toBe("420");
    expect(m.fragile).toBe(true);
  });
});

describe("quantità e messaggi", () => {
  it("la quantità massima dipende solo da posseduti e impegnati da altri", () => {
    expect(quantitaMassimaAnnuncio(6, 0)).toBe(6);
    expect(quantitaMassimaAnnuncio(6, 4)).toBe(2);
    expect(quantitaMassimaAnnuncio(6, 9)).toBe(0);
    expect(quantitaMassimaAnnuncio(999, 0)).toBe(120);
  });

  it("gli errori del database diventano frasi leggibili, senza esporre interni", () => {
    expect(messaggioErroreAnnunci({ hint: "quantita_non_disponibile" }, "x")).toContain("pezzi disponibili");
    expect(messaggioErroreAnnunci({ hint: "annuncio_gia_aperto" }, "x")).toContain("già un annuncio aperto");
    expect(messaggioErroreAnnunci({ hint: "pubblicazione_chiusa" }, "x")).toContain("non è ancora aperta");
    expect(messaggioErroreAnnunci({ code: "42501", message: "permission denied for table x" }, "x")).toBe("Operazione non consentita.");
    expect(messaggioErroreAnnunci({ code: "XX000", message: "secret internals" }, "ricaduta")).toBe("ricaduta");
    expect(messaggioErroreAnnunci(null, "ricaduta")).toBe("ricaduta");
  });

  it("il motivo di un venditore non ammesso è spiegato", () => {
    expect(messaggioVenditoreNonAmmesso(null)).toBeNull();
    expect(messaggioVenditoreNonAmmesso("partner_percorso_non_consentito")).toContain("Partner");
    expect(messaggioVenditoreNonAmmesso("boh")).toContain("non può preparare annunci");
  });
});
