import { describe, expect, it } from "bun:test";
import {
  STATO_INIZIALE,
  azioneFollow,
  descrizioneFollow,
  etichettaFollow,
  followAbilitato,
  followOccupato,
  statoDaEsitoIniziale,
  statoDaEsitoMutazione,
  statoInMutazione,
  type StatoFollow,
} from "@/lib/cantina/segui-cantina-stato";

const NON_SEGUITA: StatoFollow = { fase: "non_seguita" };
const SEGUITA: StatoFollow = { fase: "seguita" };

describe("lettura iniziale dello stato del follow", () => {
  it("parte in verifica e non finge di conoscere la risposta", () => {
    expect(STATO_INIZIALE.fase).toBe("verifica");
    // Il punto: in attesa il comando non dice «Segui», che sarebbe una risposta.
    expect(etichettaFollow(STATO_INIZIALE)).toBe("Verifica…");
    expect(followAbilitato(STATO_INIZIALE)).toBe(false);
    expect(followOccupato(STATO_INIZIALE)).toBe(true);
    expect(azioneFollow(STATO_INIZIALE)).toBeNull();
  });

  it("legge `false` come «non la segui»", () => {
    expect(statoDaEsitoIniziale({ ok: true, data: false })).toEqual({ fase: "non_seguita" });
  });

  it("legge `true` come «la segui»", () => {
    expect(statoDaEsitoIniziale({ ok: true, data: true })).toEqual({ fase: "seguita" });
  });

  it("su errore NON diventa «non la segui»", () => {
    // L'invariante 1. Con `non_seguita` il comando inviterebbe a seguire una
    // Cantina che forse è già seguita, e il click manderebbe una scrittura
    // decisa su un'informazione che non c'è.
    const stato = statoDaEsitoIniziale({ ok: false, error: "guasto" });
    expect(stato.fase).toBe("non_disponibile");
    expect(stato.fase).not.toBe("non_seguita");
    expect(followAbilitato(stato)).toBe(false);
    expect(azioneFollow(stato)).toBeNull();
    expect(etichettaFollow(stato)).toBe("Segui non disponibile");
  });
});

describe("quale scrittura chiede il click", () => {
  it("da «non seguita» chiede il follow", () => {
    expect(azioneFollow(NON_SEGUITA)).toBe("segui");
  });

  it("da «seguita» chiede l'unfollow", () => {
    expect(azioneFollow(SEGUITA)).toBe("smetti");
  });

  it("non chiede niente mentre una scrittura è già in volo", () => {
    expect(azioneFollow({ fase: "in_corso", seguita: false })).toBeNull();
    expect(azioneFollow({ fase: "in_corso", seguita: true })).toBeNull();
  });
});

describe("scrittura in volo", () => {
  it("conserva lo stato di partenza", () => {
    expect(statoInMutazione(NON_SEGUITA)).toEqual({ fase: "in_corso", seguita: false });
    expect(statoInMutazione(SEGUITA)).toEqual({ fase: "in_corso", seguita: true });
  });

  it("disabilita il comando e lo dichiara occupato", () => {
    const stato = statoInMutazione(NON_SEGUITA);
    expect(followAbilitato(stato)).toBe(false);
    expect(followOccupato(stato)).toBe(true);
  });

  it("non anticipa l'etichetta dell'altro stato", () => {
    // Scrivere «Seguita» prima della risposta sarebbe un successo raccontato in
    // anticipo, e su un rifiuto l'etichetta tornerebbe indietro da sola.
    expect(etichettaFollow(statoInMutazione(NON_SEGUITA))).toBe("Segui");
    expect(etichettaFollow(statoInMutazione(SEGUITA))).toBe("Seguita");
  });

  it("non parte da verifica, da non_disponibile o da una scrittura già in volo", () => {
    expect(statoInMutazione({ fase: "verifica" })).toEqual({ fase: "verifica" });
    expect(statoInMutazione({ fase: "non_disponibile" })).toEqual({ fase: "non_disponibile" });
    const inVolo: StatoFollow = { fase: "in_corso", seguita: true };
    expect(statoInMutazione(inVolo)).toEqual(inVolo);
  });
});

describe("risposta alla scrittura", () => {
  it("passa a «seguita» solo dopo che il database ha risposto `true`", () => {
    const inVolo = statoInMutazione(NON_SEGUITA);
    expect(inVolo.fase).toBe("in_corso");
    expect(statoDaEsitoMutazione(inVolo, { ok: true, data: true })).toEqual({ fase: "seguita" });
  });

  it("passa a «non seguita» dopo che l'unfollow ha risposto `false`", () => {
    // `cantina_smetti_di_seguire` restituisce lo stato finale, non «ho
    // cancellato una riga»: `false` è il successo.
    const inVolo = statoInMutazione(SEGUITA);
    expect(statoDaEsitoMutazione(inVolo, { ok: true, data: false })).toEqual({
      fase: "non_seguita",
    });
  });

  it("segue il database anche quando contraddice il click", () => {
    // Un follow che risponde `false` non diventa «seguita» perché il click
    // sperava in quello.
    const inVolo = statoInMutazione(NON_SEGUITA);
    expect(statoDaEsitoMutazione(inVolo, { ok: true, data: false })).toEqual({
      fase: "non_seguita",
    });
  });

  it("su follow rifiutato torna a «non seguita», senza falso successo", () => {
    const inVolo = statoInMutazione(NON_SEGUITA);
    const dopo = statoDaEsitoMutazione(inVolo, { ok: false, error: "rifiutato" });
    expect(dopo).toEqual({ fase: "non_seguita" });
    expect(followAbilitato(dopo)).toBe(true);
    expect(azioneFollow(dopo)).toBe("segui");
  });

  it("su unfollow rifiutato resta «seguita», senza perdere la relazione", () => {
    // L'invariante 2 nel verso che fa più danno: mostrare «Segui» dopo un
    // unfollow rifiutato racconterebbe che la relazione non c'è più.
    const inVolo = statoInMutazione(SEGUITA);
    const dopo = statoDaEsitoMutazione(inVolo, { ok: false, error: "rifiutato" });
    expect(dopo).toEqual({ fase: "seguita" });
    expect(followAbilitato(dopo)).toBe(true);
    expect(azioneFollow(dopo)).toBe("smetti");
  });

  it("ignora una risposta che arriva mentre non si stava scrivendo", () => {
    expect(statoDaEsitoMutazione({ fase: "verifica" }, { ok: true, data: true })).toEqual({
      fase: "verifica",
    });
    expect(statoDaEsitoMutazione(SEGUITA, { ok: true, data: false })).toEqual(SEGUITA);
    expect(
      statoDaEsitoMutazione({ fase: "non_disponibile" }, { ok: true, data: true }),
    ).toEqual({ fase: "non_disponibile" });
  });

  it("riabilita il comando qualunque sia l'esito", () => {
    for (const partenza of [NON_SEGUITA, SEGUITA]) {
      const inVolo = statoInMutazione(partenza);
      for (const esito of [
        { ok: true, data: true } as const,
        { ok: true, data: false } as const,
        { ok: false, error: "x" } as const,
      ]) {
        expect(followAbilitato(statoDaEsitoMutazione(inVolo, esito))).toBe(true);
        expect(followOccupato(statoDaEsitoMutazione(inVolo, esito))).toBe(false);
      }
    }
  });
});

describe("lo stato non è affidato al colore", () => {
  it("ogni fase ha un'etichetta e un nome accessibile diversi da quelli delle altre", () => {
    const fasi: StatoFollow[] = [
      { fase: "verifica" },
      NON_SEGUITA,
      SEGUITA,
      { fase: "non_disponibile" },
    ];
    const etichette = fasi.map(etichettaFollow);
    expect(new Set(etichette).size).toBe(fasi.length);
    for (const testo of etichette) expect(testo.trim()).not.toBe("");
  });

  it("«Seguita» ha un nome accessibile che descrive l'azione, non lo stato", () => {
    expect(etichettaFollow(SEGUITA)).toBe("Seguita");
    expect(descrizioneFollow(SEGUITA)).toBe("Smetti di seguire questa Cantina");
  });

  it("dà un nome accessibile anche alle fasi in cui il comando è disabilitato", () => {
    expect(descrizioneFollow({ fase: "verifica" }).trim()).not.toBe("");
    expect(descrizioneFollow({ fase: "non_disponibile" }).trim()).not.toBe("");
  });
});
