import { describe, expect, it } from "bun:test";
import { vociCertificazione } from "@/lib/profilo/certificazioni";
import type { CertificazioniProfilo } from "@/services/types";

const certificazioni = (patch: Partial<CertificazioniProfilo> = {}): CertificazioniProfilo => ({
  emailConfermata: false,
  identitaVerificata: false,
  venditoreVerificato: false,
  ...patch,
});

const voce = (c: CertificazioniProfilo, chiave: "email" | "identita" | "venditore") =>
  vociCertificazione(c).find((v) => v.chiave === chiave)!;

/** Tutto il testo di una voce, per cercarci dentro una parola vietata. */
const testo = (c: CertificazioniProfilo, chiave: "email" | "identita" | "venditore") => {
  const v = voce(c, chiave);
  return `${v.titolo} ${v.etichetta} ${v.dettaglio}`;
};

describe("sezione Certificazioni di /account", () => {
  it("mostra le tre voci, sempre e nello stesso ordine", () => {
    const voci = vociCertificazione(certificazioni());
    expect(voci.map((v) => v.chiave)).toEqual(["email", "identita", "venditore"]);
  });

  it("con l'email confermata dice «Confermata», non «Verificato»", () => {
    const c = certificazioni({ emailConfermata: true });
    expect(voce(c, "email").stato).toBe("confermata");
    expect(voce(c, "email").etichetta).toBe("Confermata");
    // La parola pesante resta per l'identità: chiamare «verificato» chi ha solo
    // aperto un link è esattamente l'abuso che questa schermata deve evitare.
    expect(testo(c, "email")).not.toInclude("Verificat");
  });

  it("l'email confermata non accende nessuna delle altre due voci", () => {
    const c = certificazioni({ emailConfermata: true });
    expect(voce(c, "identita").stato).not.toBe("confermata");
    expect(voce(c, "venditore").stato).not.toBe("confermata");
  });

  it("un profilo senza certificazioni non mostra nessuno stato positivo", () => {
    const voci = vociCertificazione(certificazioni());
    expect(voci.filter((v) => v.stato === "confermata")).toHaveLength(0);
  });

  it("l'identità non verificata è «non disponibile», non un compito dell'utente", () => {
    const c = certificazioni({ emailConfermata: true });
    // `assente` suonerebbe come «ti manca un passo»: qui manca il percorso a
    // noi, non un'azione a chi legge.
    expect(voce(c, "identita").stato).toBe("non_disponibile");
    expect(voce(c, "identita").dettaglio).toInclude("beta");
    expect(voce(c, "identita").dettaglio).toInclude("niente che tu debba fare");
  });

  it("nessuna voce propone un'azione: non c'è niente da chiamare", () => {
    const casi = [
      certificazioni(),
      certificazioni({ emailConfermata: true }),
      certificazioni({ emailConfermata: true, identitaVerificata: true }),
    ];
    for (const c of casi) {
      for (const v of vociCertificazione(c)) {
        expect(`${v.etichetta} ${v.dettaglio}`).not.toMatch(
          /verifica ora|inizia la verifica|carica un documento|invia il documento/i,
        );
      }
    }
  });

  it("il venditore senza identità rimanda all'identità, non a un pulsante", () => {
    const c = certificazioni({ emailConfermata: true });
    expect(voce(c, "venditore").stato).toBe("non_disponibile");
    expect(voce(c, "venditore").dettaglio).toInclude("identità verificata");
  });

  it("con l'identità verificata ma senza abilitazione il venditore resta spento", () => {
    const c = certificazioni({ emailConfermata: true, identitaVerificata: true });
    expect(voce(c, "identita").stato).toBe("confermata");
    expect(voce(c, "venditore").stato).toBe("assente");
    expect(voce(c, "venditore").etichetta).toBe("Non attivo");
  });

  it("solo con entrambe le certificazioni il venditore risulta attivo", () => {
    const c = certificazioni({
      emailConfermata: true,
      identitaVerificata: true,
      venditoreVerificato: true,
    });
    expect(voce(c, "venditore").stato).toBe("confermata");
    expect(voce(c, "venditore").etichetta).toBe("Attivo");
  });

  it("nessuna voce mostra email, data di nascita, fonte o date della verifica", () => {
    const voci = vociCertificazione(
      certificazioni({
        emailConfermata: true,
        identitaVerificata: true,
        venditoreVerificato: true,
      }),
    );
    const tutto = voci.map((v) => `${v.titolo} ${v.etichetta} ${v.dettaglio}`).join(" ");
    // Le voci sono testo fisso: nessun campo del profilo, e nessun dato della
    // certificazione, ci finisce dentro.
    expect(tutto).not.toMatch(/@|\d{4}-\d{2}-\d{2}|verifica_interna|scade/i);
  });
});
