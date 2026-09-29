import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ID_IMBALLAGGIO,
  PROVE_SPEDIZIONE,
  VOCI_IMBALLAGGIO,
  checklistCompleta,
  preparazioneConfermabile,
} from "@/lib/orders/imballaggio-checklist";
import type { VoceChecklist } from "@/services/types";

const RADICE = join(import.meta.dir, "../../..");

const leggi = (percorso: string) => readFileSync(join(RADICE, percorso), "utf8");

const MIGRAZIONE = readFileSync(
  join(RADICE, "../supabase/migrations/20260928210000_shipping_evidence_gate.sql"),
  "utf8",
);

const completa = (): VoceChecklist[] =>
  VOCI_IMBALLAGGIO.map((v) => ({ id: v.id, label: v.label, done: true }));

describe("i due tipi di prova", () => {
  it("sono esattamente due, e sono quelli che il database accetta", () => {
    expect(PROVE_SPEDIZIONE.map((p) => p.kind)).toEqual(["collo_finale", "interno_pre_chiusura"]);
    // Il vincolo della tabella è l'elenco autorevole: un terzo tipo qui
    // verrebbe rifiutato con 23514 al primo caricamento.
    expect(MIGRAZIONE).toContain(
      "check (evidence_kind in ('collo_finale', 'interno_pre_chiusura'))",
    );
  });

  it("collo_finale è obbligatoria e porta la copy prescritta", () => {
    const collo = PROVE_SPEDIZIONE.find((p) => p.kind === "collo_finale");
    expect(collo?.obbligatoria).toBe(true);
    expect(collo?.aiuto).toBe("Fotografa il collo finale già chiuso e pronto alla spedizione.");
  });

  it("interno_pre_chiusura è facoltativa e non entra nel cancello", () => {
    const interno = PROVE_SPEDIZIONE.find((p) => p.kind === "interno_pre_chiusura");
    expect(interno?.obbligatoria).toBe(false);
    expect(interno?.aiuto).toBe("Facoltativa, ma utile in caso di contestazione.");
    expect(preparazioneConfermabile(completa(), ["interno_pre_chiusura"])).toBe(false);
    expect(preparazioneConfermabile(completa(), ["collo_finale"])).toBe(true);
  });
});

describe("le sei voci canoniche", () => {
  it("sono gli stessi sei ID di private.imballaggio_checklist_voci()", () => {
    const elenco = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("function private.imballaggio_checklist_voci()"),
      MIGRAZIONE.indexOf("comment on function private.imballaggio_checklist_voci()"),
    );
    const idSql = [...elenco.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
    expect(idSql).toEqual([...ID_IMBALLAGGIO]);
    expect(idSql).toHaveLength(6);
  });

  it("non sono più le quattro voci fotografiche della 7c", () => {
    // Erano spunte che affermavano una fotografia senza che ne esistesse una.
    for (const vecchia of ["foto_frontale", "foto_capsula", "foto_livello", "foto_imballaggio"]) {
      expect(ID_IMBALLAGGIO).not.toContain(vecchia);
    }
  });

  it("ogni voce ha un'etichetta in italiano, distinta dall'ID", () => {
    for (const voce of VOCI_IMBALLAGGIO) {
      expect(voce.label.length).toBeGreaterThan(voce.id.length - 10);
      expect(voce.label).not.toBe(voce.id);
    }
  });
});

describe("checklistCompleta", () => {
  it("è vera solo con tutte e sei spuntate", () => {
    expect(checklistCompleta(completa())).toBe(true);
  });

  it("una checklist incompleta non è pronta, e resta comunque salvabile", () => {
    const parziale = completa().map((v, i) => (i === 0 ? { ...v, done: false } : v));
    expect(checklistCompleta(parziale)).toBe(false);
    expect(preparazioneConfermabile(parziale, ["collo_finale"])).toBe(false);

    const mancante = completa().slice(1);
    expect(checklistCompleta(mancante)).toBe(false);
  });

  it("un ID inventato non sostituisce quello che manca, nemmeno in più", () => {
    const sostituito = [
      ...completa().slice(1),
      { id: "imballaggio_perfetto", label: "Inventata", done: true },
    ];
    expect(sostituito).toHaveLength(6);
    expect(checklistCompleta(sostituito)).toBe(false);

    const inPiu = [...completa(), { id: "extra", label: "Extra", done: true }];
    expect(checklistCompleta(inPiu)).toBe(false);
  });

  it("una voce ripetuta non vale per due", () => {
    const ripetuta = [...completa().slice(0, 5), { ...completa()[0]! }];
    expect(ripetuta).toHaveLength(6);
    expect(checklistCompleta(ripetuta)).toBe(false);
  });

  it("rispecchia la regola SQL, che conta totale, distinti e spuntati", () => {
    expect(MIGRAZIONE).toContain("return v_totale = array_length(v_voci, 1)");
    expect(MIGRAZIONE).toContain("and v_distinti = array_length(v_voci, 1)");
    expect(MIGRAZIONE).toContain("and v_spuntate = array_length(v_voci, 1)");
  });
});

describe("il pannello del venditore", () => {
  const PANNELLO = leggi("src/components/vinea/orders/SellerPrepPanel.tsx");

  it("mostra entrambi gli slot dalla stessa definizione, senza riscriverli", () => {
    expect(PANNELLO).toContain("PROVE_SPEDIZIONE.map");
    expect(PANNELLO).toContain("VOCI_IMBALLAGGIO.map");
    // Nessun elenco locale che possa divergere da quello canonico.
    expect(PANNELLO).not.toMatch(/const (VOCI|PROVE)\s*[:=]/);
  });

  it("spegne «Segna come spedito» finché la preparazione non è confermata", () => {
    expect(PANNELLO).toContain("!puoSpedire(ordine)");
    // La condizione passa l'ordine, non lo stato: `pagato` da solo non basta
    // più e una firma su `OrderStatus` non saprebbe dirlo.
    expect(PANNELLO).not.toContain("puoSpedire(ordine.stato)");
  });

  it("mostra la conferma con il suo istante, e regge un ordine che non ce l'ha", () => {
    expect(PANNELLO).toContain("confermataAt !== null");
    expect(PANNELLO).toContain("Preparazione confermata il");
    // `new Date(null)` non viene mai costruita: il ramo nullo è un altro testo.
    expect(PANNELLO).toContain("new Date(confermataAt).toLocaleString");
  });

  it("non tratta imballaggio_foto come autorità né la scrive", () => {
    expect(PANNELLO).not.toContain("imballaggio_foto");
    // La preparazione parte senza percorsi: le prove le registra la loro porta.
    expect(PANNELLO).toContain("onPrepara(checklist())");
  });

  it("non genera etichette, QR, né chiama un fornitore logistico", () => {
    for (const vietato of [
      "createShipment",
      "generateLabel",
      "getDropoffPoints",
      "proofOfDelivery",
      "cancelShipment",
      "Sendcloud",
      "ShippyPro",
      "QR",
      "assicurazione",
    ]) {
      expect(PANNELLO).not.toContain(vietato);
    }
  });
});
