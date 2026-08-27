import type { MovimentoSaldo, MovimentoSaldoTipo, PrelievoSaldoStato } from "@/services/types";
import { formatEUR } from "@/lib/format";

/**
 * Il vocabolario italiano del saldo Vinea (D1).
 *
 * I tipi di movimento e gli stati dei prelievi escono dal database come etichette
 * di macchina: questa mappa è l'unico posto in cui diventano parole. Un tipo che
 * non ha un'etichetta non viene indovinato — si mostra il codice così com'è, che
 * è meglio di una frase inventata sul denaro di qualcuno.
 */

export const ETICHETTE_MOVIMENTO: Record<MovimentoSaldoTipo, string> = {
  vendita_pending: "Vendita in attesa di rilascio",
  vendita_disponibile: "Vendita diventata disponibile",
  vendita_storno: "Storno di una vendita rimborsata",
  rettifica_rimborso: "Rettifica per rimborso dopo il rilascio",
  acquisto_prenotato: "Saldo impegnato per un acquisto",
  acquisto_addebito: "Saldo usato per un acquisto",
  acquisto_rilascio: "Saldo liberato da un ordine annullato",
  acquisto_rimborso: "Saldo restituito da un rimborso",
  prelievo_prenotato: "Saldo impegnato per un prelievo",
  prelievo_eseguito: "Prelievo trasferito",
  prelievo_annullato: "Prelievo annullato",
};

export const ETICHETTE_STATO_PRELIEVO: Record<PrelievoSaldoStato, string> = {
  richiesto: "Richiesto",
  in_corso: "In trasferimento",
  trasferito: "Trasferito",
  fallito: "Non riuscito",
  annullato: "Annullato",
};

export const etichettaMovimento = (tipo: string): string =>
  ETICHETTE_MOVIMENTO[tipo as MovimentoSaldoTipo] ?? tipo;

export const etichettaStatoPrelievo = (stato: string): string =>
  ETICHETTE_STATO_PRELIEVO[stato as PrelievoSaldoStato] ?? stato;

const euroDaCents = (cents: number): string => formatEUR(cents / 100);

const conSegno = (cents: number): string =>
  cents > 0 ? `+${euroDaCents(cents)}` : cents < 0 ? `−${euroDaCents(-cents)}` : euroDaCents(0);

/**
 * La cifra da mostrare accanto a un movimento. Un movimento può toccare più di
 * una delle tre quantità (il rilascio di una vendita sposta da in attesa a
 * disponibile): si elencano solo le quantità che si sono mosse davvero, perché
 * uno zero accanto a un movimento di denaro è un'affermazione falsa.
 */
export const deltaLeggibili = (movimento: MovimentoSaldo): string[] => {
  const parti: string[] = [];
  if (movimento.deltaPendingCents !== 0) {
    parti.push(`${conSegno(movimento.deltaPendingCents)} in attesa`);
  }
  if (movimento.deltaAvailableCents !== 0) {
    parti.push(`${conSegno(movimento.deltaAvailableCents)} disponibili`);
  }
  if (movimento.deltaReservedCents !== 0) {
    parti.push(`${conSegno(movimento.deltaReservedCents)} impegnati`);
  }
  return parti;
};
