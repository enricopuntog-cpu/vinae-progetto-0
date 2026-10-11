import { describe, expect, it } from "bun:test";
import {
  BUCKET_PARTNER_VETRINE,
  MAX_DESCRIZIONE,
  MAX_PRESENTAZIONE,
  classeCommerciale,
  etichettaTipologia,
  localitaVetrina,
  mediaNonPiuUsati,
  nuovoPercorsoMedia,
  parseVetrinaMia,
  parseVetrinaPubblica,
  percorsoMediaVetrina,
  urlMediaVetrina,
  validaTestiVetrina,
} from "@/lib/partner/vetrina";

const T = "11111111-1111-4111-8111-111111111111";
const P = "22222222-2222-4222-8222-222222222222";
const ALTRO = "33333333-3333-4333-8333-333333333333";
const F = (n: number) => `${T}/${P}/4444444${n}-4444-4444-8444-444444444444.webp`;

const riga = {
  partner_id: P,
  titolare_id: T,
  nome_commerciale: "Enoteca Alba",
  tipologia: "enoteca",
  sede_citta: "Alba",
  sede_provincia: "CN",
  paese: "IT",
  attivo_dal: "2026-10-11T10:00:00Z",
  presentazione: "Vini di Langa",
  descrizione: "Dal 1998.",
  logo_path: F(1),
  copertina_path: F(2),
  foto_paths: [F(3), F(4)],
  aggiornata_at: "2026-10-11T11:00:00Z",
};

describe("percorsi dei media", () => {
  it("accetta solo la cartella <titolare>/<partner>/<uuid>.webp di questa vetrina", () => {
    expect(percorsoMediaVetrina(F(1), T, P)).toBe(F(1));
    expect(percorsoMediaVetrina(F(1), ALTRO, P)).toBeNull();
    expect(percorsoMediaVetrina(F(1), T, ALTRO)).toBeNull();
    expect(percorsoMediaVetrina(F(1).replace(".webp", ".png"), T, P)).toBeNull();
    expect(percorsoMediaVetrina(`${T}/${P}/../${ALTRO}/x.webp`, T, P)).toBeNull();
    expect(percorsoMediaVetrina("https://esempio.test/logo.webp", T, P)).toBeNull();
    expect(percorsoMediaVetrina(F(1).toUpperCase(), T, P)).toBeNull();
    expect(percorsoMediaVetrina(null, T, P)).toBeNull();
  });

  it("compone l'URL pubblico dalla configurazione, mai dal dato", () => {
    expect(urlMediaVetrina(F(1), T, P, "https://progetto.supabase.co/qualcosa")).toBe(
      `https://progetto.supabase.co/storage/v1/object/public/${BUCKET_PARTNER_VETRINE}/${F(1)}`,
    );
    expect(urlMediaVetrina(F(1), T, P, "javascript:alert(1)")).toBeNull();
    expect(urlMediaVetrina(F(1), T, P, "")).toBeNull();
    expect(urlMediaVetrina(F(1), ALTRO, P, "https://progetto.supabase.co")).toBeNull();
  });

  it("un file nuovo nasce solo nella cartella indicata dal server", () => {
    const uuid = "55555555-5555-4555-8555-555555555555";
    expect(nuovoPercorsoMedia(`${T}/${P}`, uuid)).toBe(`${T}/${P}/${uuid}.webp`);
    expect(nuovoPercorsoMedia(`${T}/${P}/..`, uuid)).toBeNull();
    expect(nuovoPercorsoMedia(`${T}`, uuid)).toBeNull();
    expect(nuovoPercorsoMedia(`${T}/${P}`, "non-un-uuid")).toBeNull();
  });

  it("cancella dopo il salvataggio solo i file che la vetrina non usa più", () => {
    const prima = { logoPath: F(1), copertinaPath: F(2), fotoPaths: [F(3), F(4)] };
    const dopo = { logoPath: F(5), copertinaPath: F(2), fotoPaths: [F(4)] };
    expect(mediaNonPiuUsati(prima, dopo).sort()).toEqual([F(1), F(3)].sort());
    expect(mediaNonPiuUsati(prima, prima)).toEqual([]);
    // Un file spostato da foto a copertina non è «non più usato».
    expect(mediaNonPiuUsati(prima, { logoPath: F(1), copertinaPath: F(3), fotoPaths: [F(2), F(4)] })).toEqual(
      [],
    );
  });
});

describe("testi", () => {
  it("rispetta i limiti del server, dopo il trim", () => {
    expect(validaTestiVetrina({ presentazione: "a".repeat(MAX_PRESENTAZIONE), descrizione: "" })).toEqual({});
    expect(validaTestiVetrina({ presentazione: `  ${"a".repeat(MAX_PRESENTAZIONE)}  `, descrizione: "" })).toEqual({});
    expect(validaTestiVetrina({ presentazione: "a".repeat(MAX_PRESENTAZIONE + 1), descrizione: "" }).presentazione).toBeTruthy();
    expect(validaTestiVetrina({ presentazione: "", descrizione: "b".repeat(MAX_DESCRIZIONE + 1) }).descrizione).toBeTruthy();
  });
});

describe("parsing della vetrina pubblica", () => {
  it("mappa l'elenco chiuso di campi", () => {
    expect(parseVetrinaPubblica(riga)).toEqual({
      partnerId: P,
      titolareId: T,
      nomeCommerciale: "Enoteca Alba",
      tipologia: "enoteca",
      sedeCitta: "Alba",
      sedeProvincia: "CN",
      paese: "IT",
      attivoDal: "2026-10-11T10:00:00Z",
      aggiornataAt: "2026-10-11T11:00:00Z",
      presentazione: "Vini di Langa",
      descrizione: "Dal 1998.",
      logoPath: F(1),
      copertinaPath: F(2),
      fotoPaths: [F(3), F(4)],
    });
  });

  it("non porta con sé campi amministrativi anche se arrivassero", () => {
    const vetrina = parseVetrinaPubblica({
      ...riga,
      partita_iva: "12345678903",
      ragione_sociale: "Segreta Srl",
      sede_indirizzo: "Via Segreta 1",
      email_commerciale: "x@y.it",
      ultimo_motivo: "interno",
    });
    const testo = JSON.stringify(vetrina);
    expect(testo).not.toMatch(/12345678903|Segreta|x@y\.it|interno/);
  });

  it("scarta percorsi estranei, tipologie sconosciute e foto oltre quattro", () => {
    const vetrina = parseVetrinaPubblica({
      ...riga,
      tipologia: "casinò",
      logo_path: `${ALTRO}/${P}/44444441-4444-4444-8444-444444444444.webp`,
      foto_paths: [F(3), "https://esempio.test/x.webp", F(4), F(5), F(6), F(7)],
    });
    expect(vetrina?.tipologia).toBeNull();
    expect(vetrina?.logoPath).toBeNull();
    expect(vetrina?.fotoPaths).toEqual([F(3), F(4), F(5), F(6)]);
  });

  it("senza identità minima non è una vetrina", () => {
    expect(parseVetrinaPubblica(null)).toBeNull();
    expect(parseVetrinaPubblica([])).toBeNull();
    expect(parseVetrinaPubblica({ ...riga, nome_commerciale: null })).toBeNull();
    expect(parseVetrinaPubblica({ ...riga, titolare_id: "" })).toBeNull();
  });
});

describe("parsing della vetrina del titolare", () => {
  const mia = { ...riga, stato: "in_verifica", modificabile: true, cartella: `${T}/${P}` };

  it("porta stato, modificabilità e cartella", () => {
    const v = parseVetrinaMia(mia);
    expect(v?.stato).toBe("in_verifica");
    expect(v?.modificabile).toBe(true);
    expect(v?.cartella).toBe(`${T}/${P}`);
  });

  it("modificabile solo se il server dice esattamente true", () => {
    expect(parseVetrinaMia({ ...mia, modificabile: "true" })?.modificabile).toBe(false);
  });

  it("rifiuta una cartella che non è quella del titolare e del Partner", () => {
    expect(parseVetrinaMia({ ...mia, cartella: `${ALTRO}/${P}` })).toBeNull();
    expect(parseVetrinaMia({ ...mia, stato: "boh" })).toBeNull();
  });

  it("un Partner in bozza senza nome commerciale ha comunque la sua vetrina", () => {
    expect(parseVetrinaMia({ ...mia, nome_commerciale: null })?.nomeCommerciale).toBeNull();
  });
});

describe("classe commerciale e presentazione", () => {
  it("è lo stesso predicato dei gate: attivo e sospeso", () => {
    expect(classeCommerciale("attivo")).toBe(true);
    expect(classeCommerciale("sospeso")).toBe(true);
    for (const stato of ["invitato", "in_verifica", "revocato"] as const) {
      expect(classeCommerciale(stato)).toBe(false);
    }
    expect(classeCommerciale(null)).toBe(false);
  });

  it("località e tipologia leggibili, mai l'indirizzo", () => {
    expect(localitaVetrina("Alba", "CN")).toBe("Alba (CN)");
    expect(localitaVetrina("Alba", null)).toBe("Alba");
    expect(localitaVetrina(null, " ")).toBeNull();
    expect(etichettaTipologia("cantina_produttore")).toBe("Cantina / produttore");
    expect(etichettaTipologia(null)).toBeNull();
  });
});
