import { describe, expect, it } from "bun:test";
import { salvaProfiloConAvatar } from "@/lib/profilo/salva-avatar";
import type { ProfiloCorrente, ProfiloModifica, Result } from "@/services/types";

const PROPRIETARIO = "11111111-1111-4111-8111-111111111111";
const VECCHIA_FOTO = `${PROPRIETARIO}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp`;
const NUOVA_FOTO = `${PROPRIETARIO}/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.webp`;
const PRESET = "/avatar/calice.svg";
const FILE = new File(["webp"], "avatar.webp", { type: "image/webp" });

const profilo = (avatarUrl: string): ProfiloCorrente => ({
  userId: PROPRIETARIO,
  email: "elena@esempio.it",
  username: "elena",
  bio: "",
  citta: "Milano",
  provincia: "MI",
  esperienza: "appassionato",
  avatarUrl,
  dob: "1990-01-01",
  // Il salvataggio dell'avatar non tocca le certificazioni: qui stanno spente
  // perché nessuna delle prove sotto ha bisogno di accenderle.
  certificazioni: {
    emailConfermata: true,
    identitaVerificata: false,
    venditoreVerificato: false,
  },
});

const scenario = (opzioni?: {
  caricamento?: Result<string>;
  aggiornamento?: Result<ProfiloCorrente>;
  eliminaFalliscePer?: string;
}) => {
  const eventi: string[] = [];
  const patchRicevuti: ProfiloModifica[] = [];
  return {
    eventi,
    patchRicevuti,
    operazioni: {
      async caricaFoto(): Promise<Result<string>> {
        eventi.push("upload");
        return opzioni?.caricamento ?? { ok: true, data: NUOVA_FOTO };
      },
      async aggiornaProfilo(patch: ProfiloModifica): Promise<Result<ProfiloCorrente>> {
        eventi.push("update");
        patchRicevuti.push(patch);
        return opzioni?.aggiornamento ?? {
          ok: true,
          data: profilo(patch.avatarUrl ?? ""),
        };
      },
      async eliminaFoto(percorso: string): Promise<Result<void>> {
        eventi.push(`delete:${percorso}`);
        return percorso === opzioni?.eliminaFalliscePer
          ? { ok: false, error: "pulizia fallita" }
          : { ok: true, data: undefined };
      },
    },
  };
};

describe("salvataggio del profilo con foto personale", () => {
  it("passa da foto personale a preset aggiornando prima e cancellando dopo", async () => {
    const prova = scenario();
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: VECCHIA_FOTO,
        nuovaFoto: null,
        patch: { avatarUrl: PRESET },
      },
      prova.operazioni,
    );

    expect(esito.ok).toBe(true);
    expect(prova.eventi).toEqual(["update", `delete:${VECCHIA_FOTO}`]);
    expect(prova.patchRicevuti[0]?.avatarUrl).toBe(PRESET);
  });

  it("passa da foto personale alle iniziali aggiornando prima e cancellando dopo", async () => {
    const prova = scenario();
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: VECCHIA_FOTO,
        nuovaFoto: null,
        patch: { avatarUrl: "" },
      },
      prova.operazioni,
    );

    expect(esito.ok).toBe(true);
    expect(prova.eventi).toEqual(["update", `delete:${VECCHIA_FOTO}`]);
    expect(prova.patchRicevuti[0]?.avatarUrl).toBe("");
  });

  it("sostituisce la foto nell'ordine upload, update, cancellazione precedente", async () => {
    const prova = scenario();
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: VECCHIA_FOTO,
        nuovaFoto: FILE,
        patch: { bio: "Aggiornata" },
      },
      prova.operazioni,
    );

    expect(esito.ok).toBe(true);
    expect(prova.eventi).toEqual(["upload", "update", `delete:${VECCHIA_FOTO}`]);
    expect(prova.patchRicevuti[0]?.avatarUrl).toBe(NUOVA_FOTO);
  });

  it("compensa il nuovo upload quando l'update del profilo fallisce", async () => {
    const prova = scenario({ aggiornamento: { ok: false, error: "update fallito" } });
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: VECCHIA_FOTO,
        nuovaFoto: FILE,
        patch: {},
      },
      prova.operazioni,
    );

    expect(esito).toEqual({ ok: false, error: "update fallito" });
    expect(prova.eventi).toEqual(["upload", "update", `delete:${NUOVA_FOTO}`]);
  });

  it("segnala sia l'update fallito sia la compensazione fallita", async () => {
    const prova = scenario({
      aggiornamento: { ok: false, error: "update fallito" },
      eliminaFalliscePer: NUOVA_FOTO,
    });
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: "",
        nuovaFoto: FILE,
        patch: {},
      },
      prova.operazioni,
    );

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toContain("update fallito");
    expect(esito.error).toContain("nuovo upload non salvato");
  });

  it("mantiene il profilo aggiornato e restituisce un avviso se la vecchia foto resta", async () => {
    const prova = scenario({ eliminaFalliscePer: VECCHIA_FOTO });
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: VECCHIA_FOTO,
        nuovaFoto: null,
        patch: { avatarUrl: PRESET },
      },
      prova.operazioni,
    );

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.profilo.avatarUrl).toBe(PRESET);
    expect(esito.data.avvisoPulizia).toContain("profilo è aggiornato");
  });

  it("rifiuta un percorso di upload non canonico e prova a cancellarlo", async () => {
    const percorsoNonValido = "https://evil.example/avatar.webp";
    const prova = scenario({ caricamento: { ok: true, data: percorsoNonValido } });
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: PROPRIETARIO,
        avatarPrecedente: "",
        nuovaFoto: FILE,
        patch: {},
      },
      prova.operazioni,
    );

    expect(esito.ok).toBe(false);
    expect(prova.eventi).toEqual(["upload", `delete:${percorsoNonValido}`]);
  });
});
