import { describe, expect, it } from "bun:test";
import { statoEtaProfilo, type ProfiloInMemoria } from "@/lib/store/real-auth-domain";
import type { ProfiloCorrente } from "@/services/types";

const profilo = (dob: string | null): ProfiloCorrente => ({
  userId: "u1",
  email: "utente@esempio.it",
  username: "utente",
  bio: "",
  citta: "",
  provincia: "",
  esperienza: "curioso",
  avatarUrl: "",
  dob,
  certificazioni: {
    emailConfermata: true,
    identitaVerificata: false,
    venditoreVerificato: false,
  },
});

const letto = (parziale: Partial<ProfiloInMemoria>): ProfiloInMemoria => ({
  userId: "u1",
  profilo: null,
  stato: "letto",
  ...parziale,
});

describe("statoEtaProfilo", () => {
  it("non blocca chi non ha una sessione", () => {
    expect(statoEtaProfilo(null, null)).toBe("nessuna_sessione");
    // Anche con una lettura residua in memoria: senza sessione non c'è nulla
    // da verificare, e l'ospite naviga come prima.
    expect(statoEtaProfilo(null, letto({ profilo: profilo("1990-01-01") }))).toBe(
      "nessuna_sessione",
    );
  });

  it("resta in verifica finché la riga non è stata letta", () => {
    expect(statoEtaProfilo("u1", null)).toBe("in_verifica");
    expect(statoEtaProfilo("u1", letto({ stato: "in_verifica" }))).toBe("in_verifica");
  });

  it("non eredita la lettura di un'altra sessione", () => {
    const altro = letto({ userId: "u2", profilo: profilo("1990-01-01") });
    expect(statoEtaProfilo("u1", altro)).toBe("in_verifica");
  });

  it("manda a completare il profilo soltanto dopo una lettura riuscita senza dob", () => {
    expect(statoEtaProfilo("u1", letto({ profilo: profilo(null) }))).toBe("da_completare");
  });

  it("lascia passare una lettura riuscita con dob", () => {
    expect(statoEtaProfilo("u1", letto({ profilo: profilo("1990-01-01") }))).toBe("completo");
  });

  /**
   * Il caso che il vecchio "sconosciuto" sbagliava: una lettura fallita non è
   * un profilo incompleto e non è un profilo valido. È il proprio stato, e
   * chiude l'accesso invece di aprirlo o di mandare a ridichiarare l'età.
   */
  it("tiene la lettura fallita come stato a sé, né completo né da completare", () => {
    const guasto = letto({ stato: "errore_lettura" });
    expect(statoEtaProfilo("u1", guasto)).toBe("errore_lettura");
    expect(statoEtaProfilo("u1", guasto)).not.toBe("da_completare");
    expect(statoEtaProfilo("u1", guasto)).not.toBe("completo");
  });

  it("torna allo stato giusto dopo un nuovo tentativo, riuscito o fallito", () => {
    // Riprova: si riparte da in_verifica...
    expect(statoEtaProfilo("u1", letto({ stato: "in_verifica" }))).toBe("in_verifica");
    // ...e il nuovo esito sostituisce il precedente in entrambi i versi.
    expect(statoEtaProfilo("u1", letto({ profilo: profilo("1990-01-01") }))).toBe("completo");
    expect(statoEtaProfilo("u1", letto({ stato: "errore_lettura" }))).toBe("errore_lettura");
  });
});
