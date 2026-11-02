import type { AccessoriPostvenditaService, Result } from "@/services/types";
import type { PostVenditaAccessorio } from "./postvendita";
export { contestazioneComeFascicolo } from "./postvendita";

export type FascicoloAccessorio = {
  postvendita: PostVenditaAccessorio;
  foto: { acquirente: string[]; venditore: string[] };
};

/** Solo letture autorizzate dal DB; un errore non abilita azioni di post-vendita. */
export function dettaglioAccessorioDisponibile(commercioAperto: boolean, fascicolo: Result<FascicoloAccessorio>,
  ordine: { stato: string; pagamentoSimulato: boolean }) {
  return commercioAperto || (fascicolo.ok ? fascicolo.data.postvendita.incassato
    : ordine.stato === "pagato" && !ordine.pagamentoSimulato);
}

export async function caricaFascicolo(
  servizio: Pick<AccessoriPostvenditaService, "leggi" | "firmaProve">,
  ordineId: string,
): Promise<Result<FascicoloAccessorio>> {
  try {
    const letto = await servizio.leggi(ordineId);
    if (!letto.ok) return letto;
    if (letto.data.ordineId !== ordineId) return { ok: false, error: "Fascicolo non disponibile. Riprova." };
    const c = letto.data.contestazione;
    const [acquirente, venditore] = await Promise.all([
      servizio.firmaProve(c?.foto ?? []),
      servizio.firmaProve(c?.risposta?.foto ?? []),
    ]);
    if (acquirente.length !== (c?.foto.length ?? 0) || venditore.length !== (c?.risposta?.foto.length ?? 0)) {
      return { ok: false, error: "Non è stato possibile caricare tutte le prove. Riprova." };
    }
    return { ok: true, data: { postvendita: letto.data, foto: { acquirente, venditore } } };
  } catch {
    return { ok: false, error: "Il post-vendita non è disponibile in questo momento. Riprova." };
  }
}

/** L'invalidazione sincrona copre anche l'input manuale prima del prossimo render. */
export function creaCaricatoreFascicolo() {
  let versione = 0;
  return {
    invalida() { versione += 1; },
    async carica(servizio: Pick<AccessoriPostvenditaService, "leggi" | "firmaProve">, id: string,
      applica: (esito: Result<FascicoloAccessorio>) => void) {
      const corrente = ++versione;
      const esito = await caricaFascicolo(servizio, id);
      if (corrente === versione) applica(esito);
    },
  };
}
