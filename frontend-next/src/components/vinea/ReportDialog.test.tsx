import { afterAll, afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * La segnalazione, eseguita: il dialogo si apre e si percorre con i suoi comandi, la
 * richiesta arriva a un client finto al posto di Supabase. Sostituiscono le asserzioni
 * sul testo dei sorgenti, che non provano quale chiamata parte né cosa vede l'utente.
 */
apriDom();
const { cleanup, fireEvent, render, waitFor, within } = await import("@testing-library/react");
const vineaReale = await import("@/lib/vinea-store");

type Rpc = { nome: string; argomenti: Record<string, unknown> };
const ID_SEGNALAZIONE = "11111111-1111-4111-8111-111111111111";
const rpc: Rpc[] = [];
const viste: string[] = [];
let erroreRpc: { message: string; code?: string } | null = null;
let attesaRpc: Promise<void> | null = null;
let clientAttivo = true;
let utente: { email: string; userId: string } | null = { email: "a@vinea.test", userId: "u-1" };
let inTest = false;

const clientFinto = {
  rpc: async (nome: string, argomenti: Record<string, unknown>) => {
    rpc.push({ nome, argomenti });
    if (attesaRpc) await attesaRpc;
    return { data: erroreRpc ? null : ID_SEGNALAZIONE, error: erroreRpc };
  },
  // Rilettura della riga canonica dalla proiezione del segnalante.
  from: (vista: string) => ({
    select: () => ({
      eq: () => ({
        maybeSingle: async () => {
          viste.push(vista);
          return { data: { id: ID_SEGNALAZIONE, target_tipo: "annuncio", motivo: "m", stato: "aperta" }, error: null };
        },
      }),
    }),
  }),
};

mock.module("@/lib/supabase/client", () => ({
  getSupabaseClient: () => (inTest && clientAttivo ? clientFinto : null),
}));
mock.module("@/lib/vinea-store", () => ({
  ...vineaReale,
  useVinea: () => (inTest ? { authUser: utente } : vineaReale.useVinea()),
}));

const { ReportDialog } = await import("./ReportDialog");

const pagina = () => within(document.body);

/** Apre il dialogo e arriva al passo della descrizione. */
const finoAllaDescrizione = () => {
  fireEvent.click(pagina().getByRole("button", { name: /segnala/i }));
  fireEvent.click(pagina().getByRole("button", { name: /continua/i }));
};
const invia = () => fireEvent.click(pagina().getByRole("button", { name: "Invia segnalazione" }));

const ID_ANNUNCIO = "22222222-2222-4222-8222-222222222222";

beforeEach(() => {
  inTest = true;
  rpc.length = 0;
  viste.length = 0;
  erroreRpc = null;
  attesaRpc = null;
  clientAttivo = true;
  utente = { email: "a@vinea.test", userId: "u-1" };
});

afterEach(() => {
  cleanup();
  inTest = false;
});

afterAll(async () => {
  await chiudiDom();
});

describe("ReportDialog", () => {
  it("è chiuso finché non lo si apre, e allora mostra titolo e bersaglio", () => {
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo 2016" />);
    expect(pagina().queryByRole("dialog")).toBeNull();

    fireEvent.click(pagina().getByRole("button", { name: /segnala/i }));

    const dialogo = within(pagina().getByRole("dialog"));
    expect(dialogo.getByRole("heading", { name: "Segnala annuncio" })).toBeTruthy();
    expect(dialogo.getByText(/Barolo 2016/)).toBeTruthy();
    expect(dialogo.getByRole("radiogroup", { name: "Motivo della segnalazione" })).toBeTruthy();
    expect(rpc).toEqual([]);
  });

  it("invia una sola richiesta con il motivo scelto e conferma all'utente", async () => {
    const riuscita = mock(() => undefined);
    render(
      <ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo 2016" onSuccess={riuscita} />,
    );
    fireEvent.click(pagina().getByRole("button", { name: /segnala/i }));
    const motivi = pagina().getAllByRole("radio");
    expect(motivi.length).toBeGreaterThan(1);
    fireEvent.click(motivi[1]!);
    fireEvent.click(pagina().getByRole("button", { name: /continua/i }));
    fireEvent.change(pagina().getByLabelText("Descrizione facoltativa"), {
      target: { value: "Foto copiata da un altro sito" },
    });
    invia();

    await waitFor(() => expect(pagina().getByRole("heading", { name: "Segnalazione inviata" })).toBeTruthy());
    expect(rpc.length).toBe(1);
    expect(viste).toEqual(["my_reports"]);
    expect(rpc[0]!.nome).toBe("segnalazione_invia");
    const corpo = JSON.stringify(rpc[0]!.argomenti);
    expect(corpo).toContain(ID_ANNUNCIO);
    expect(corpo).toContain("Foto copiata da un altro sito");
    expect(corpo).toContain("Foto non veritiere o riciclate");
    expect(riuscita).toHaveBeenCalledTimes(1);
    expect(pagina().getByRole("link", { name: "Segui lo stato" }).getAttribute("href")).toBe("/segnalazioni");
  });

  it("un doppio clic durante l'invio non manda una seconda segnalazione", async () => {
    let sblocca: () => void = () => undefined;
    attesaRpc = new Promise((risolvi) => {
      sblocca = risolvi;
    });
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();
    await waitFor(() => expect(pagina().getByRole("button", { name: "Invio…" }).hasAttribute("disabled")).toBe(true));
    fireEvent.click(pagina().getByRole("button", { name: "Invio…" }));
    sblocca();

    await waitFor(() => expect(pagina().getByRole("heading", { name: "Segnalazione inviata" })).toBeTruthy());
    expect(rpc.length).toBe(1);
  });

  it("senza sessione non parte alcuna richiesta e chiede di accedere", async () => {
    utente = null;
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();

    expect((await pagina().findByRole("alert")).textContent).toBe("Accedi prima di inviare una segnalazione.");
    expect(rpc).toEqual([]);
  });

  it("senza bersaglio non parte alcuna richiesta", async () => {
    render(<ReportDialog targetType="annuncio" targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();

    expect((await pagina().findByRole("alert")).textContent).toBe("Questo contenuto non può essere segnalato.");
    expect(rpc).toEqual([]);
  });

  it("senza configurazione lo dice senza nominare dettagli tecnici", async () => {
    clientAttivo = false;
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();

    expect((await pagina().findByRole("alert")).textContent).toBe(
      "Il servizio segnalazioni non è disponibile in questa configurazione.",
    );
  });

  it("una segnalazione doppia lo spiega, e il testo del database non arriva all'utente", async () => {
    erroreRpc = { message: "Esiste gia una segnalazione aperta", code: "P0001" };
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();

    expect((await pagina().findByRole("alert")).textContent).toBe(
      "Hai già una segnalazione aperta per questo contenuto.",
    );
  });

  it("un guasto sconosciuto resta un messaggio generico e si può riprovare", async () => {
    erroreRpc = { message: 'relation "private.reports" does not exist', code: "42P01" };
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();

    const avviso = await pagina().findByRole("alert");
    expect(avviso.textContent).toBe("Invio non riuscito. Riprova più tardi.");
    expect(document.body.textContent).not.toContain("private.reports");

    erroreRpc = null;
    invia();
    await waitFor(() => expect(pagina().getByRole("heading", { name: "Segnalazione inviata" })).toBeTruthy());
    expect(rpc.length).toBe(2);
  });

  it("chiudendolo e riaprendolo riparte dal primo passo, senza il testo precedente", () => {
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    fireEvent.change(pagina().getByLabelText("Descrizione facoltativa"), { target: { value: "bozza" } });
    fireEvent.click(pagina().getByRole("button", { name: "Indietro" }));
    fireEvent.click(pagina().getByRole("button", { name: "Annulla" }));
    expect(pagina().queryByRole("dialog")).toBeNull();

    fireEvent.click(pagina().getByRole("button", { name: /segnala/i }));
    fireEvent.click(pagina().getByRole("button", { name: /continua/i }));
    expect((pagina().getByLabelText("Descrizione facoltativa") as HTMLTextAreaElement).value).toBe("");
  });

  it("dopo un invio riuscito, chiudendo e riaprendo si vede di nuovo il modulo", async () => {
    render(<ReportDialog targetType="annuncio" targetId={ID_ANNUNCIO} targetLabel="Barolo" />);
    finoAllaDescrizione();
    invia();
    await waitFor(() => expect(pagina().getByRole("heading", { name: "Segnalazione inviata" })).toBeTruthy());

    fireEvent.click(pagina().getByRole("button", { name: "Chiudi" }));
    expect(pagina().queryByRole("dialog")).toBeNull();

    fireEvent.click(pagina().getByRole("button", { name: /segnala/i }));
    expect(pagina().getByRole("heading", { name: "Segnala annuncio" })).toBeTruthy();
    expect(pagina().getByRole("radiogroup", { name: "Motivo della segnalazione" })).toBeTruthy();
  });

  it("un Club si segnala per slug, senza id", async () => {
    render(<ReportDialog targetType="club" clubSlug="circolo-vinea" targetLabel="Circolo Vinea" />);
    finoAllaDescrizione();
    invia();

    await waitFor(() => expect(pagina().getByRole("heading", { name: "Segnalazione inviata" })).toBeTruthy());
    expect(JSON.stringify(rpc[0]!.argomenti)).toContain("circolo-vinea");
  });
});
