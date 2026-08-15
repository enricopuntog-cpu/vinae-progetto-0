import { describe, expect, it, mock } from "bun:test";
import { eseguiAzioneBeta, MESSAGGI_AZIONI_BETA } from "@/lib/beta/external-actions";

describe("confine locale delle azioni esterne beta", () => {
  it("blocca IA senza valutare il callback", async () => {
    const azione = mock(async () => "risposta");
    const esito = await eseguiAzioneBeta("ia", false, azione);

    expect(azione).not.toHaveBeenCalled();
    expect(esito).toEqual({ eseguita: false, messaggio: MESSAGGI_AZIONI_BETA.ia });
  });

  it("blocca il pagamento senza ordine o addebito", async () => {
    const azione = mock(async () => "checkout");
    const esito = await eseguiAzioneBeta("pagamento", false, azione);

    expect(azione).not.toHaveBeenCalled();
    expect(esito).toEqual({ eseguita: false, messaggio: MESSAGGI_AZIONI_BETA.pagamento });
  });

  it("blocca la prenotazione logistica senza provider", async () => {
    const azione = mock(async () => "etichetta");
    const esito = await eseguiAzioneBeta("spedizione", false, azione);

    expect(azione).not.toHaveBeenCalled();
    expect(esito).toEqual({ eseguita: false, messaggio: MESSAGGI_AZIONI_BETA.spedizione });
  });

  it("esegue una sola volta il callback soltanto con gate già abilitato", async () => {
    const azione = mock(async () => ({ id: "locale" }));
    const esito = await eseguiAzioneBeta("pagamento", true, azione);

    expect(azione).toHaveBeenCalledTimes(1);
    expect(esito).toEqual({ eseguita: true, valore: { id: "locale" } });
  });

  it("usa copy univoci che dichiarano l'assenza dell'effetto esterno", () => {
    expect(MESSAGGI_AZIONI_BETA.ia).toInclude("Nessun dato è stato inviato");
    expect(MESSAGGI_AZIONI_BETA.pagamento).toInclude("Nessun addebito");
    expect(MESSAGGI_AZIONI_BETA.spedizione).toInclude("non è ancora attiva");
  });
});
