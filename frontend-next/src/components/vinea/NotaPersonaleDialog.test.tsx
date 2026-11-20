import { afterAll, afterEach, describe, expect, it } from "bun:test";
import { notaVuota, type NotaPersonaleVino } from "@/lib/cantina/note-personali";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-005B — l'editor «Completa le informazioni» nel DOM simulato. NON è una prova nel browser:
 * il percorso completo con dati reali è nell'E2E `note-personali-cantina.e2e.ts`.
 */
apriDom();
const { cleanup, fireEvent, render, screen, waitFor, within } = await import("@testing-library/react");
const { NotaPersonaleDialog } = await import("./NotaPersonaleDialog");

afterEach(cleanup);
afterAll(() => chiudiDom());

const VINO = {
  produttore: "Cascina Prova",
  nome: "Barolo Prova",
  annata: 2015,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  formato: "0,75 L",
  wineSlug: "barolo-prova-2015",
};

type Ok = { ok: true; data: undefined };
const ok = (): Ok => ({ ok: true, data: undefined });

function monta(opzioni: {
  nota?: NotaPersonaleVino;
  vino?: typeof VINO;
  salva?: (slug: string, nota: NotaPersonaleVino) => Promise<Ok | { ok: false; error: string }>;
  elimina?: (slug: string) => Promise<Ok | { ok: false; error: string }>;
}) {
  const salvate: { slug: string; nota: NotaPersonaleVino }[] = [];
  const eliminate: string[] = [];
  const chiusure: boolean[] = [];
  render(
    <NotaPersonaleDialog
      vino={opzioni.vino ?? VINO}
      nota={opzioni.nota}
      open
      onOpenChange={(o) => chiusure.push(o)}
      onSalva={async (slug, nota) => {
        salvate.push({ slug, nota });
        return opzioni.salva ? opzioni.salva(slug, nota) : ok();
      }}
      onElimina={async (slug) => {
        eliminate.push(slug);
        return opzioni.elimina ? opzioni.elimina(slug) : ok();
      }}
    />,
  );
  return { salvate, eliminate, chiusure };
}

const campo = (id: string) => screen.getByTestId(id) as HTMLInputElement | HTMLTextAreaElement;
const scrivi = (id: string, valore: string) => fireEvent.change(campo(id), { target: { value: valore } });
const clic = (id: string) => fireEvent.click(screen.getByTestId(id));

describe("NotaPersonaleDialog — modifica", () => {
  it("dichiara subito che le informazioni sono private, personali e non certificate", () => {
    monta({});
    const testo = screen.getByTestId("nota-privacy").textContent ?? "";
    expect(testo).toMatch(/privat/i);
    expect(testo).toMatch(/non (sono )?certificat/i);
    expect(testo).toMatch(/non cambiano/i);
  });

  it("mostra i dati del database Vinea in sola lettura, distinti dalle proprie dichiarazioni", () => {
    monta({});
    const catalogo = screen.getByTestId("nota-catalogo");
    expect(catalogo.textContent).toContain("2015");
    expect(catalogo.textContent).toContain("Piemonte");
    expect(catalogo.textContent).toContain("Barolo DOCG");
    expect(catalogo.querySelector("input, textarea")).toBeNull();
  });

  it("vino senza annata: lo mostra come tale, senza trattarlo da errore", () => {
    monta({ vino: { ...VINO, annata: 0 } });
    expect(screen.getByTestId("nota-catalogo").textContent).toMatch(/senza annata|non indicata/i);
  });

  it("senza nulla da salvare e senza una nota esistente non si può procedere", () => {
    monta({});
    expect((screen.getByTestId("nota-rivedi") as HTMLButtonElement).disabled).toBe(true);
  });

  it("precompila i campi dalla nota salvata", () => {
    monta({
      nota: { ...notaVuota(), abbinamenti: ["Brasato", "Risotto"], temperaturaC: 16, calice: "Ballon", osservazioni: "Mia" },
    });
    expect(campo("nota-abbinamenti").value).toBe("Brasato\nRisotto");
    expect(campo("nota-temperatura").value).toBe("16");
    expect(campo("nota-calice").value).toBe("Ballon");
    expect(campo("nota-osservazioni").value).toBe("Mia");
  });
});

describe("NotaPersonaleDialog — conferma e salvataggio", () => {
  it("non salva nulla finché l'utente non conferma", async () => {
    const { salvate } = monta({});
    scrivi("nota-abbinamenti", "Brasato al Barolo\n  brasato   al barolo \nTagliatelle");
    scrivi("nota-temperatura", "16");
    clic("nota-rivedi");
    expect(screen.getByTestId("nota-conferma")).toBeTruthy();
    expect(salvate).toEqual([]);
  });

  it("la revisione elenca le dichiarazioni come tue e private, con duplicati normalizzati", () => {
    monta({});
    scrivi("nota-abbinamenti", "Brasato al Barolo\n  brasato   al barolo \nTagliatelle");
    scrivi("nota-temperatura", "16");
    clic("nota-rivedi");
    const rev = screen.getByTestId("nota-conferma");
    expect(rev.textContent).toContain("Brasato al Barolo · Tagliatelle");
    expect(rev.textContent).toContain("16 °C");
    expect(rev.textContent).toMatch(/dichiarat/i);
    expect(rev.textContent).toMatch(/privat/i);
  });

  it("«Conferma e salva» salva una volta sola, con i valori normalizzati, e chiude", async () => {
    const { salvate, chiusure } = monta({});
    scrivi("nota-abbinamenti", "Brasato\nRisotto");
    scrivi("nota-decantazione", "45");
    scrivi("nota-osservazioni", "Regalo di Marco");
    clic("nota-rivedi");
    clic("nota-salva");
    await waitFor(() => expect(salvate).toHaveLength(1));
    expect(salvate[0].slug).toBe("barolo-prova-2015");
    expect(salvate[0].nota).toMatchObject({
      abbinamenti: ["Brasato", "Risotto"],
      decantazioneMinuti: 45,
      osservazioni: "Regalo di Marco",
      annataDichiarata: null,
      nonMillesimato: false,
    });
    await waitFor(() => expect(chiusure).toContain(false));
  });

  it("un errore di salvataggio resta in vista, non chiude e non dice 'salvato'", async () => {
    const { chiusure } = monta({ salva: async () => ({ ok: false, error: "Non è stato possibile completare l'operazione. Riprova." }) });
    scrivi("nota-osservazioni", "x");
    clic("nota-rivedi");
    clic("nota-salva");
    const errore = await screen.findByRole("alert");
    expect(errore.textContent).toContain("Riprova");
    expect(chiusure).not.toContain(false);
    expect(screen.getByTestId("nota-conferma")).toBeTruthy();
  });

  it("«Torna a modificare» riporta ai campi senza perdere quanto scritto", () => {
    monta({});
    scrivi("nota-osservazioni", "da non perdere");
    clic("nota-rivedi");
    clic("nota-indietro");
    expect(campo("nota-osservazioni").value).toBe("da non perdere");
  });

  it("«Annulla» chiude senza salvare", () => {
    const { salvate, chiusure } = monta({});
    scrivi("nota-osservazioni", "x");
    clic("nota-annulla");
    expect(salvate).toEqual([]);
    expect(chiusure).toContain(false);
  });

  it("svuotare tutto e confermare rimuove le annotazioni: la nota vuota viene inviata", async () => {
    const { salvate } = monta({ nota: { ...notaVuota(), osservazioni: "vecchia" } });
    scrivi("nota-osservazioni", "");
    clic("nota-rivedi");
    expect(screen.getByTestId("nota-conferma").textContent).toMatch(/rimoss|rimuov/i);
    clic("nota-salva");
    await waitFor(() => expect(salvate).toHaveLength(1));
    expect(salvate[0].nota.osservazioni).toBe("");
  });
});

describe("NotaPersonaleDialog — validazione e conflitti", () => {
  it("valori non validi: messaggio sul campo, nessun passaggio alla conferma", () => {
    monta({});
    scrivi("nota-temperatura", "99");
    clic("nota-rivedi");
    expect(screen.queryByTestId("nota-conferma")).toBeNull();
    expect(screen.getByTestId("nota-errore-temperaturaC").textContent).toMatch(/temperatura/i);
    expect(campo("nota-temperatura").getAttribute("aria-invalid")).toBe("true");
  });

  it("annata dichiarata e non millesimato insieme: rifiutato", () => {
    monta({ vino: { ...VINO, annata: 0 } });
    scrivi("nota-annata", "2015");
    clic("nota-nv");
    clic("nota-rivedi");
    expect(screen.queryByTestId("nota-conferma")).toBeNull();
    expect(screen.getByTestId("nota-errore-annataDichiarata").textContent).toMatch(/non millesimato/i);
  });

  it("più di 8 abbinamenti: rifiutato con il limite scritto", () => {
    monta({});
    scrivi("nota-abbinamenti", Array.from({ length: 9 }, (_, i) => `Piatto ${i + 1}`).join("\n"));
    clic("nota-rivedi");
    expect(screen.getByTestId("nota-errore-abbinamenti").textContent).toMatch(/8/);
  });

  it("quando la dichiarazione contraddice il catalogo, la revisione mostra entrambi e dice che il catalogo non cambia", () => {
    monta({});
    scrivi("nota-regione", "Toscana");
    scrivi("nota-annata", "2016");
    clic("nota-rivedi");
    const conflitti = screen.getByTestId("nota-conflitti");
    expect(conflitti.textContent).toContain("Toscana");
    expect(conflitti.textContent).toContain("Piemonte");
    expect(conflitti.textContent).toContain("2016");
    expect(conflitti.textContent).toContain("2015");
    expect(conflitti.textContent).toMatch(/non cambia/i);
  });

  it("nessun conflitto mostrato quando coincide", () => {
    monta({});
    scrivi("nota-regione", "piemonte");
    scrivi("nota-osservazioni", "x");
    clic("nota-rivedi");
    expect(screen.queryByTestId("nota-conflitti")).toBeNull();
  });
});

describe("NotaPersonaleDialog — eliminazione", () => {
  it("non appare senza una nota salvata", () => {
    monta({});
    expect(screen.queryByTestId("nota-elimina")).toBeNull();
  });

  it("richiede una seconda conferma prima di cancellare", async () => {
    const { eliminate, chiusure } = monta({ nota: { ...notaVuota(), osservazioni: "x" } });
    clic("nota-elimina");
    expect(eliminate).toEqual([]);
    clic("nota-elimina-conferma");
    await waitFor(() => expect(eliminate).toEqual(["barolo-prova-2015"]));
    await waitFor(() => expect(chiusure).toContain(false));
  });

  it("la prima pressione si può annullare", () => {
    const { eliminate } = monta({ nota: { ...notaVuota(), osservazioni: "x" } });
    clic("nota-elimina");
    clic("nota-elimina-annulla");
    expect(eliminate).toEqual([]);
    expect(within(screen.getByTestId("nota-azioni")).queryByTestId("nota-elimina-conferma")).toBeNull();
  });
});
