/**
 * Pre-lancio: rubrica degli indirizzi e scelta della consegna nel checkout.
 *
 * Il database resta l'autorità (porte `indirizzo_*`, `checkout_consegna_imposta`,
 * checkout con firma invariata). Questi test fissano che l'interfaccia ripeta
 * gli stessi controlli con le stesse frasi, calcoli il totale sulla
 * destinazione davvero scelta, chiuda la conferma negli stessi casi in cui il
 * database la rifiuterebbe e registri la destinazione prima della prenotazione.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  accessoriCheckout,
  bloccoConsegna,
  creaDatiCheckout,
  logisticaAddebitata,
  logisticaInTotale,
  riepilogoCheckout,
  ritiroVenditoreMancante,
} from "@/lib/beta/checkout";
import {
  consegnaPredefinita,
  daIndirizzo,
  indirizzoConsegnaProposto,
  indirizzoVuoto,
  rigaIndirizzo,
  ritiroPredefinito,
  titoloIndirizzo,
  validaIndirizzo,
} from "@/lib/indirizzi/rubrica";
import { rigaSedePartner } from "@/components/vinea/indirizzi/SedePartnerRitiro";
import type { Indirizzo } from "@/services/types";

const radice = join(import.meta.dir, "../../../..");
const leggi = (p: string) => readFileSync(join(radice, p), "utf8");
const senzaCommenti = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
const migrazione = leggi("supabase/migrations/20261013160000_logistica_indirizzi_api.sql");

const indirizzo = (id: string, extra: Partial<Indirizzo> = {}): Indirizzo => ({
  id,
  etichetta: null,
  destinatario: "Ada Vigna",
  via: "Via Roma 1",
  cap: "10121",
  citta: "Torino",
  provincia: "TO",
  paese: "IT",
  telefono: null,
  note: null,
  predefinitoRitiro: false,
  predefinitoConsegna: false,
  ...extra,
});

const valido = indirizzoVuoto({
  destinatario: "Ada Vigna",
  via: "Via Roma 1",
  cap: "10121",
  citta: "Torino",
  provincia: "to",
});

describe("Rubrica — controlli d'ingresso uguali alla porta", () => {
  it("un indirizzo italiano completo passa, la provincia in minuscolo compresa", () => {
    expect(validaIndirizzo(valido)).toEqual({});
  });

  it("i campi obbligatori vuoti danno le frasi della porta", () => {
    expect(validaIndirizzo(indirizzoVuoto())).toEqual({
      destinatario: "Indica il nome del destinatario.",
      via: "Indica via e numero civico.",
      cap: "Il CAP deve avere 5 cifre.",
      citta: "Indica la città.",
      provincia: "La provincia è la sigla di due lettere.",
    });
  });

  it("telefono, note ed etichetta seguono i limiti del database", () => {
    expect(validaIndirizzo({ ...valido, telefono: "333-123" }).telefono).toBe(
      "Il telefono contiene caratteri non validi.",
    );
    expect(validaIndirizzo({ ...valido, telefono: "+39 333 1234567" })).toEqual({});
    expect(validaIndirizzo({ ...valido, note: "x".repeat(201) }).note).toBeDefined();
    expect(validaIndirizzo({ ...valido, etichetta: "x".repeat(61) }).etichetta).toBeDefined();
    expect(validaIndirizzo({ ...valido, cap: "1012" }).cap).toBeDefined();
    expect(validaIndirizzo({ ...valido, provincia: "TOR" }).provincia).toBeDefined();
  });

  it("ogni frase del client è la stessa di indirizzo_salva", () => {
    const porta = migrazione.slice(migrazione.indexOf("create function public.indirizzo_salva("));
    const frasi = Object.values(validaIndirizzo({ ...indirizzoVuoto(), telefono: "?", note: "x".repeat(201), etichetta: "x".repeat(61) }));
    expect(frasi).toHaveLength(8);
    for (const f of frasi) expect(porta).toInclude(f!.replace("L'etichetta", "L''etichetta"));
  });

  it("modifica: il modulo parte dai valori salvati, campi facoltativi vuoti", () => {
    const i = indirizzo("a", { etichetta: "Casa", predefinitoRitiro: true });
    expect(daIndirizzo(i)).toEqual({
      etichetta: "Casa",
      destinatario: "Ada Vigna",
      via: "Via Roma 1",
      cap: "10121",
      citta: "Torino",
      provincia: "TO",
      telefono: "",
      note: "",
      predefinitoRitiro: true,
      predefinitoConsegna: false,
    });
    expect(titoloIndirizzo(i)).toBe("Casa");
    expect(titoloIndirizzo(indirizzo("b"))).toBe("Ada Vigna");
    expect(rigaIndirizzo(i)).toBe("Via Roma 1, 10121 Torino (TO)");
  });
});

describe("Rubrica — predefiniti", () => {
  const rubrica = [
    indirizzo("a"),
    indirizzo("b", { predefinitoConsegna: true }),
    indirizzo("c", { predefinitoRitiro: true }),
  ];

  it("un predefinito di consegna e uno di ritiro, distinti", () => {
    expect(consegnaPredefinita(rubrica)?.id).toBe("b");
    expect(ritiroPredefinito(rubrica)?.id).toBe("c");
    expect(ritiroPredefinito([indirizzo("a")])).toBeNull();
  });

  it("il checkout propone la scelta valida, poi il predefinito, poi il primo", () => {
    expect(indirizzoConsegnaProposto(rubrica, "c")?.id).toBe("c");
    expect(indirizzoConsegnaProposto(rubrica, "archiviato")?.id).toBe("b");
    expect(indirizzoConsegnaProposto(rubrica, null)?.id).toBe("b");
    expect(indirizzoConsegnaProposto([indirizzo("a"), indirizzo("c")], null)?.id).toBe("a");
    expect(indirizzoConsegnaProposto([], null)).toBeNull();
  });

  it("la porta toglie il predefinito agli altri e l'archiviazione lo azzera", () => {
    const porta = migrazione.slice(migrazione.indexOf("create function public.indirizzo_salva("));
    expect(porta).toInclude("update private.indirizzi set predefinito_consegna = false");
    expect(porta).toInclude("update private.indirizzi set predefinito_ritiro = false");
    expect(migrazione).toInclude("set archiviato_at = now(), predefinito_ritiro = false, predefinito_consegna = false");
  });
});

describe("Checkout — destinazione e totale", () => {
  // Opzioni come le restituisce `listing_logistica_preventivo` (valori di prova).
  const opzione = (destinazione: "pudo" | "home", ordinabile: boolean, totaleCents: number | null, fee: number | null, mancanti: { packagingFormat: null; motivi: string[] }[] = []) => ({
    destinazione,
    ordinabile,
    totaleCents,
    feePagamentoCents: fee,
    mancanti,
  });
  const logistica = (pudo: ReturnType<typeof opzione>, home: ReturnType<typeof opzione>) => ({
    opzioni: [pudo, home],
    imballaggioAnnuncioCents: 450,
    feePagamentoSenzaLogisticaCents: 9,
  });
  const economico = {
    classe: "privato" as const,
    quantita: 1,
    prezzoUnitarioCents: 4500,
    subtotaleCents: 4500,
    commissioneCents: 490,
    totaleCents: 4990,
    margineObiettivoBps: 800,
    riferimentoPercentualeBps: 209,
    riferimentoFissoCents: 25,
  };
  const entrambe = logistica(opzione("pudo", true, 600, 20), opzione("home", true, 900, 26));

  it("una bottiglia al punto di ritiro: nessuna logistica, copertura del solo imballaggio", () => {
    expect(logisticaInTotale(1, "spedizione", "pudo")).toBe(false);
    expect(accessoriCheckout(1, "spedizione", entrambe, "pudo")).toEqual({
      imballaggioCents: 450,
      logisticaCents: 0,
      feePagamentoCents: 9,
    });
  });

  it("una bottiglia a domicilio: la logistica è sempre addebitata, con la sua copertura", () => {
    expect(logisticaInTotale(1, "spedizione", "home")).toBe(true);
    const a = accessoriCheckout(1, "spedizione", entrambe, "home");
    expect(a).toEqual({ imballaggioCents: 450, logisticaCents: 900, feePagamentoCents: 26 });
    // Stessa identità di `totaleOrdineDomicilioCents`: mercato + 7c + domicilio + copertura.
    const r = riepilogoCheckout(economico, a!.imballaggioCents, a!.logisticaCents, a!.feePagamentoCents);
    expect(r?.totaleCents).toBe(4990 + 450 + 900 + 26);
  });

  it("cambiare destinazione ricalcola il totale dal preventivo della destinazione", () => {
    const pudo = accessoriCheckout(3, "spedizione", entrambe, "pudo")!;
    const home = accessoriCheckout(3, "spedizione", entrambe, "home")!;
    expect(pudo).toEqual({ imballaggioCents: 450, logisticaCents: 600, feePagamentoCents: 20 });
    expect(home).toEqual({ imballaggioCents: 450, logisticaCents: 900, feePagamentoCents: 26 });
  });

  it("consegna a mano: nessuna logistica qualunque sia la destinazione rimasta selezionata", () => {
    expect(logisticaAddebitata(3, "consegna_mano", null, "home")).toBe(0);
    expect(accessoriCheckout(3, "consegna_mano", entrambe, "home")).toEqual({
      imballaggioCents: 450,
      logisticaCents: 0,
      feePagamentoCents: 9,
    });
  });

  it("domicilio non ordinabile: nessun prezzo inventato", () => {
    const senzaHome = logistica(opzione("pudo", true, 600, 20), opzione("home", false, null, null));
    expect(logisticaAddebitata(1, "spedizione", senzaHome.opzioni[1], "home")).toBeNull();
    expect(accessoriCheckout(1, "spedizione", senzaHome, "home")).toBeNull();
    // Il punto di ritiro della stessa risposta resta calcolabile.
    expect(accessoriCheckout(2, "spedizione", senzaHome, "pudo")?.logisticaCents).toBe(600);
  });

  it("le firme precedenti valgono per il punto di ritiro", () => {
    expect(logisticaAddebitata(8, "spedizione", { ordinabile: true, totaleCents: 1822 })).toBe(1822);
    expect(accessoriCheckout(2, "spedizione", entrambe)).toEqual(accessoriCheckout(2, "spedizione", entrambe, "pudo"));
  });
});

describe("Checkout — conferma fail-closed", () => {
  const ok = { destinazione: "pudo" as const, ordinabile: true, totaleCents: 600, mancanti: [] };
  const homeOk = { ...ok, destinazione: "home" as const, totaleCents: 900 };
  const nonConfigurata = (destinazione: "pudo" | "home", motivi: string[]) => ({
    destinazione,
    ordinabile: false,
    totaleCents: null,
    mancanti: [{ packagingFormat: null, motivi }],
  });
  const dati = (extra: Partial<ReturnType<typeof creaDatiCheckout>> = {}) => ({ ...creaDatiCheckout(), ...extra });

  it("ritiro concordato: mai bloccato dalla logistica", () => {
    expect(bloccoConsegna(3, dati({ deliveryMode: "consegna_mano" }), { opzioni: [] })).toBeNull();
  });

  it("una bottiglia al punto di ritiro senza servizi: il percorso storico resta aperto", () => {
    const l = { opzioni: [nonConfigurata("pudo", ["servizio_mancante"]), nonConfigurata("home", ["servizio_mancante"])] };
    expect(bloccoConsegna(1, dati(), l)).toBeNull();
  });

  it("più bottiglie senza servizi logistici attivi: conferma chiusa con i motivi", () => {
    const l = { opzioni: [nonConfigurata("pudo", ["servizio_mancante", "tariffa_mancante"]), homeOk] };
    expect(bloccoConsegna(3, dati(), l)).toEqual({
      motivo: "logistica",
      mancanti: [{ packagingFormat: null, motivi: ["servizio_mancante", "tariffa_mancante"] }],
    });
    // Preventivo non leggibile: chiusa, senza motivi inventati.
    expect(bloccoConsegna(3, dati(), null)).toEqual({ motivo: "logistica", mancanti: [] });
  });

  it("domicilio: serve un indirizzo, poi un servizio ordinabile", () => {
    expect(bloccoConsegna(1, dati({ destinazione: "home" }), { opzioni: [ok, homeOk] })).toEqual({
      motivo: "indirizzo_consegna",
    });
    expect(bloccoConsegna(1, dati({ destinazione: "home", indirizzoId: "a" }), { opzioni: [ok, homeOk] })).toBeNull();
    expect(
      bloccoConsegna(1, dati({ destinazione: "home", indirizzoId: "a" }), {
        opzioni: [ok, nonConfigurata("home", ["capability_mancante"])],
      })?.motivo,
    ).toBe("logistica");
  });

  it("ritiro del venditore senza indirizzo: chiusa anche per una bottiglia (indirizzo_ritiro_mancante)", () => {
    const l = { opzioni: [nonConfigurata("pudo", ["indirizzo_ritiro_mancante"]), homeOk] };
    expect(ritiroVenditoreMancante(l.opzioni[0])).toBe(true);
    expect(bloccoConsegna(1, dati(), l)).toEqual({ motivo: "ritiro_venditore" });
    expect(migrazione).toInclude("'motivi', jsonb_build_array('indirizzo_ritiro_mancante')");
  });
});

describe("Superfici — rubrica, checkout e ritiro", () => {
  const hook = senzaCommenti(leggi("frontend-next/src/app/checkout/[id]/use-beta-checkout.ts"));
  const consegna = senzaCommenti(leggi("frontend-next/src/app/checkout/[id]/consegna-step.tsx"));

  it("la destinazione va al database dentro il gate pagamento, prima della prenotazione", () => {
    const gate = hook.indexOf('eseguiAzioneBeta("pagamento"');
    const imposta = hook.indexOf(".impostaConsegna(");
    const prenota = hook.indexOf("createPaymentService(getSupabaseClient()).creaCheckout");
    expect(gate).toBeGreaterThan(-1);
    expect(imposta).toBeGreaterThan(gate);
    expect(prenota).toBeGreaterThan(imposta);
    expect(hook).toInclude("if (!consegna.ok) return consegna;");
    expect(hook).toInclude('dati.destinazione === "home" ? dati.indirizzoId : null');
  });

  it("il punto di ritiro è la scelta predefinita e nessun corriere si sceglie", () => {
    expect(creaDatiCheckout().destinazione).toBe("pudo");
    for (const nome of ["inpost", "sda", "brt", "poste", "gls", "dhl", "ups"]) {
      expect(new RegExp(`\\b${nome}\\b`).test(consegna.toLowerCase())).toBe(false);
    }
    expect(consegna).not.toMatch(/servizio_id|serviceId|corriere\s*:/);
  });

  it("i componenti della rubrica passano solo dalle porte del servizio", () => {
    for (const f of [
      "RubricaIndirizzi.tsx",
      "FormIndirizzo.tsx",
      "IndirizzoRitiroVenditore.tsx",
      "useRubrica.ts",
      "SedePartnerRitiro.tsx",
    ]) {
      const s = senzaCommenti(leggi(`frontend-next/src/components/vinea/indirizzi/${f}`));
      expect(s).not.toInclude(".from(");
      expect(s).not.toInclude(".rpc(");
    }
    expect(leggi("frontend-next/src/components/vinea/indirizzi/useRubrica.ts")).toInclude("creaIndirizziService(");
  });

  it("rubrica in /account, ritiro a domicilio nel wizard, sede del Partner mai copiata in rubrica", () => {
    expect(leggi("frontend-next/src/app/account/page-client.tsx")).toInclude("<RubricaIndirizzi />");
    expect(senzaCommenti(leggi("frontend-next/src/app/vendi/page-client.tsx"))).toInclude(
      '{handoffVenditore === "ritiro_domicilio" ? <IndirizzoRitiroVenditore /> : null}',
    );
    expect(senzaCommenti(leggi("frontend-next/src/components/vinea/partner/PubblicazioneProdottoPartner.tsx"))).toInclude(
      '<SedePartnerRitiro variante="prodotto" />',
    );
    const sede = senzaCommenti(leggi("frontend-next/src/components/vinea/indirizzi/SedePartnerRitiro.tsx"));
    expect(sede).toInclude(".mio()");
    expect(sede).not.toMatch(/useRubrica|salva\(|creaIndirizziService/);
  });

  it("la sede si descrive solo se completa", () => {
    expect(rigaSedePartner({ sedeIndirizzo: "Via Po 2", sedeCap: "10123", sedeCitta: "Torino", sedeProvincia: "TO" })).toBe(
      "Via Po 2, 10123 Torino (TO)",
    );
    expect(rigaSedePartner({ sedeIndirizzo: null, sedeCap: "10123", sedeCitta: "Torino", sedeProvincia: "TO" })).toBeNull();
  });

  it("il vecchio modulo d'indirizzo libero del checkout non esiste più", () => {
    const passi = leggi("frontend-next/src/app/checkout/[id]/checkout-steps.tsx");
    expect(passi).not.toInclude("checkout-destinatario");
    expect(passi).not.toInclude("export const ConsegnaStep");
  });
});
