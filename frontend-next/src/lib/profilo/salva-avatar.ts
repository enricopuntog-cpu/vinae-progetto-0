import {
  percorsoAvatarPersonale,
  riferimentoAvatarSicuro,
} from "@/lib/profilo/avatar";
import type { ProfiloCorrente, ProfiloModifica, Result } from "@/services/types";

export type OperazioniSalvataggioAvatar = {
  caricaFoto(file: File): Promise<Result<string>>;
  aggiornaProfilo(patch: ProfiloModifica): Promise<Result<ProfiloCorrente>>;
  eliminaFoto(percorso: string): Promise<Result<void>>;
};

export type EsitoSalvataggioAvatar = Result<{
  profilo: ProfiloCorrente;
  avvisoPulizia: string | null;
}>;

/**
 * Coordina Storage e profilo senza fingere una transazione fra i due sistemi.
 * La foto nuova diventa autorevole soltanto dopo l'UPDATE del profilo; quella
 * vecchia viene rimossa dopo. Se l'UPDATE fallisce, l'upload appena creato viene
 * compensato. Un errore sulla pulizia finale non annulla uno stato profilo già
 * valido e viene restituito come avviso separato.
 */
export async function salvaProfiloConAvatar(
  opzioni: {
    profiloId: string;
    avatarPrecedente: string;
    nuovaFoto: File | null;
    patch: ProfiloModifica;
  },
  operazioni: OperazioniSalvataggioAvatar,
): Promise<EsitoSalvataggioAvatar> {
  const vecchioPercorso = percorsoAvatarPersonale(
    opzioni.avatarPrecedente,
    opzioni.profiloId,
  );
  let nuovoPercorso: string | null = null;
  let avatarUrl = opzioni.patch.avatarUrl ?? opzioni.avatarPrecedente;

  if (opzioni.nuovaFoto) {
    const caricamento = await operazioni.caricaFoto(opzioni.nuovaFoto);
    if (!caricamento.ok) return caricamento;
    nuovoPercorso = riferimentoAvatarSicuro(caricamento.data, opzioni.profiloId);
    if (!nuovoPercorso) {
      const pulizia = await operazioni.eliminaFoto(caricamento.data);
      return {
        ok: false,
        error: pulizia.ok
          ? "Il caricamento ha restituito un percorso non valido."
          : "Il caricamento ha restituito un percorso non valido e non è stato possibile eliminarlo.",
      };
    }
    avatarUrl = nuovoPercorso;
  }

  const aggiornamento = await operazioni.aggiornaProfilo({
    ...opzioni.patch,
    avatarUrl,
  });
  if (!aggiornamento.ok) {
    if (nuovoPercorso) {
      const pulizia = await operazioni.eliminaFoto(nuovoPercorso);
      if (!pulizia.ok) {
        return {
          ok: false,
          error: `${aggiornamento.error} Inoltre non è stato possibile eliminare il nuovo upload non salvato.`,
        };
      }
    }
    return aggiornamento;
  }

  const daEliminare =
    vecchioPercorso && vecchioPercorso !== avatarUrl ? vecchioPercorso : null;
  if (!daEliminare) {
    return { ok: true, data: { profilo: aggiornamento.data, avvisoPulizia: null } };
  }

  const pulizia = await operazioni.eliminaFoto(daEliminare);
  return {
    ok: true,
    data: {
      profilo: aggiornamento.data,
      avvisoPulizia: pulizia.ok
        ? null
        : "Il profilo è aggiornato, ma non è stato possibile eliminare la foto precedente.",
    },
  };
}
