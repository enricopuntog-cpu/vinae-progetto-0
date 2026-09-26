/**
 * La traduzione fra la porta pubblica e ciò che si disegna.
 *
 * È un adattatore puro, e l'unica cosa che può fare di male è inventare: dire
 * «zero euro» dove il database ha detto «non misurato», o disegnare una linea
 * dove c'è una sola osservazione. Le prove qui sotto sono su valori, non su
 * testo sorgente, perché qui c'è aritmetica vera da sbagliare.
 */

import { describe, expect, it } from "bun:test";
import { euro } from "@/lib/cantina/presentazione";
import {
  presentaValoreCantinaPubblica,
  puntiValorePubblico,
} from "@/lib/cantina/valore-pubblico";
import type { ValoreCantinaPubblica } from "@/services/types";

const acceso = (over: Partial<ValoreCantinaPubblica> = {}): ValoreCantinaPubblica => ({
  visibile: true,
  generatoAt: "2026-09-25T22:00:00.000Z",
  valoreRiferimentoCents: 128000,
  bottigliePubbliche: 10,
  bottiglieConRiferimento: 8,
  copertura: "parziale",
  serie: [],
  ...over,
});

describe("puntiValorePubblico", () => {
  it("porta avanti i punti misurati così come sono", () => {
    expect(
      puntiValorePubblico([
        { at: "2026-08-01T00:00:00.000Z", valoreCents: 90000, coperte: 5, scoperte: 5 },
        { at: "2026-09-01T00:00:00.000Z", valoreCents: 120000, coperte: 7, scoperte: 3 },
      ]),
    ).toEqual([
      { at: "2026-08-01T00:00:00.000Z", valoreCents: 90000, coperte: 5, scoperte: 5 },
      { at: "2026-09-01T00:00:00.000Z", valoreCents: 120000, coperte: 7, scoperte: 3 },
    ]);
  });

  it("scarta l'istante non misurato invece di chiamarlo zero", () => {
    // `valoreCents: null` con `coperte: 0` è ciò che il database dice quando a
    // quell'istante nessuna bottiglia esposta aveva un riferimento noto.
    // Convertirlo con `?? 0` disegnerebbe un crollo a zero euro che non è mai
    // avvenuto.
    const punti = puntiValorePubblico([
      { at: "2026-07-01T00:00:00.000Z", valoreCents: null, coperte: 0, scoperte: 10 },
      { at: "2026-08-01T00:00:00.000Z", valoreCents: 90000, coperte: 5, scoperte: 5 },
    ]);

    expect(punti).toHaveLength(1);
    expect(punti[0]!.at).toBe("2026-08-01T00:00:00.000Z");
    expect(punti.map((p) => p.valoreCents)).not.toContain(0);
  });

  it("una serie vuota resta vuota, e non diventa un punto inventato", () => {
    expect(puntiValorePubblico([])).toEqual([]);
  });
});

describe("presentaValoreCantinaPubblica — valore noto", () => {
  it("formatta gli euro con il formattatore monetario esistente", () => {
    const v = presentaValoreCantinaPubblica(acceso({ valoreRiferimentoCents: 128000 }));
    // Lo stesso helper della Cantina privata, non una formattazione nuova: i
    // centesimi non arrivano mai grezzi in interfaccia.
    expect(v.valore).toBe(euro(128000));
    expect(v.valore).toInclude("1.280");
    expect(v.valore).not.toInclude("128000");
    expect(v.assenza).toBeNull();
  });

  it("copertura parziale dice quante su quante, e che le altre non contano come zero", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({ copertura: "parziale", bottigliePubbliche: 10, bottiglieConRiferimento: 8 }),
    );
    expect(v.parziale).toBe(true);
    expect(v.copertura).toInclude("8 bottiglie su 10");
    expect(v.copertura).toInclude("non contano come zero");
  });

  it("copertura completa non parla di parzialità", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({ copertura: "completa", bottigliePubbliche: 10, bottiglieConRiferimento: 10 }),
    );
    expect(v.parziale).toBe(false);
    expect(v.copertura).toInclude("tutte le 10 bottiglie esposte");
  });

  it("una bottiglia sola si dice al singolare", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({ copertura: "completa", bottigliePubbliche: 1, bottiglieConRiferimento: 1 }),
    );
    expect(v.copertura).toInclude("l'unica bottiglia esposta");
    expect(v.copertura).not.toInclude("bottiglie");
  });

  it("conteggi assenti non diventano numeri: si dice meno, non si inventa", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({ bottigliePubbliche: null, bottiglieConRiferimento: null }),
    );
    expect(v.copertura).not.toMatch(/\d/);
    expect(v.valore).toBe(euro(128000));
  });
});

describe("presentaValoreCantinaPubblica — valore non misurato", () => {
  it("non mostra € 0,00: mostra l'assenza, e la spiega", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({
        valoreRiferimentoCents: null,
        bottigliePubbliche: 10,
        bottiglieConRiferimento: 0,
        copertura: "non_disponibile",
      }),
    );

    expect(v.valore).toBeNull();
    expect(v.parziale).toBe(false);
    expect(v.copertura).toInclude("Nessuna delle 10 bottiglie esposte");
    expect(v.assenza).toInclude("tre comparabili");
  });

  it("una Cantina esposta ma vuota non racconta bottiglie che non ci sono", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({
        valoreRiferimentoCents: null,
        bottigliePubbliche: 0,
        bottiglieConRiferimento: 0,
        copertura: "non_disponibile",
      }),
    );

    expect(v.valore).toBeNull();
    expect(v.copertura).toBe("Nessuna bottiglia con un riferimento Vinea disponibile.");
  });
});

describe("presentaValoreCantinaPubblica — la serie passa dal grafico esistente", () => {
  it("zero osservazioni: nessun punto, e il grafico dirà da sé che non c'è storia", () => {
    expect(presentaValoreCantinaPubblica(acceso({ serie: [] })).serie).toEqual([]);
  });

  it("una sola osservazione resta una sola: non si finge un andamento", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({
        serie: [{ at: "2026-09-01T00:00:00.000Z", valoreCents: 120000, coperte: 7, scoperte: 3 }],
      }),
    );
    expect(v.serie).toHaveLength(1);
  });

  it("più osservazioni arrivano tutte, nell'ordine in cui il database le ha date", () => {
    const v = presentaValoreCantinaPubblica(
      acceso({
        serie: [
          { at: "2026-07-01T00:00:00.000Z", valoreCents: 80000, coperte: 4, scoperte: 6 },
          { at: "2026-08-01T00:00:00.000Z", valoreCents: 90000, coperte: 5, scoperte: 5 },
          { at: "2026-09-01T00:00:00.000Z", valoreCents: 120000, coperte: 7, scoperte: 3 },
        ],
      }),
    );
    expect(v.serie.map((p) => p.valoreCents)).toEqual([80000, 90000, 120000]);
  });

  it("la serie esiste anche quando il valore corrente non è misurabile", () => {
    // Le bottiglie coperte ieri possono non esserlo oggi: la storia osservata
    // resta, e non va cancellata perché l'ultimo dato manca.
    const v = presentaValoreCantinaPubblica(
      acceso({
        valoreRiferimentoCents: null,
        bottiglieConRiferimento: 0,
        copertura: "non_disponibile",
        serie: [{ at: "2026-08-01T00:00:00.000Z", valoreCents: 90000, coperte: 5, scoperte: 5 }],
      }),
    );
    expect(v.valore).toBeNull();
    expect(v.serie).toHaveLength(1);
  });
});
