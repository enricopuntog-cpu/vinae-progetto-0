/**
 * Le derivazioni della dashboard del venditore.
 *
 * Qui non si legge nulla e non si scrive nulla: entrano gli ordini che
 * `OrderService.vendite()` ha già portato e gli annunci che
 * `ListingService.mieiAnnunci()` ha già portato, esce ciò che la pagina mostra.
 * Tenerle separate dal componente ha una ragione precisa: un numero mostrato in
 * cima a una pagina viene creduto, e queste sono le uniche righe del percorso
 * che un test può interrogare senza montare React né parlare con Supabase.
 *
 * ## Cosa questi numeri NON dicono
 *
 * Nessuna misura qui è un incassato, un payout o un saldo. Il rilascio dei
 * fondi al venditore è una conseguenza della conferma di ricezione eseguita
 * server-side (Fase 7b) e `payout_stato` non è la stessa cosa dello stato
 * dell'ordine. Un valore chiamato «incassato» sarebbe una promessa che questi
 * dati non mantengono: qui si somma `prezzo_cents`, cioè il prezzo venditore
 * congelato sull'ordine, e l'etichetta lo dice.
 *
 * `prezzo_cents` è la colonna giusta perché è già quella che `OrderList` mostra
 * al lato vendite; `addebito_totale_cents` include commissione e imballaggio,
 * che sono del compratore e della piattaforma, non del venditore.
 */

import { sellerStatusDaOrdine, type IstantaneaVenditore } from "@/lib/orders/seller-status";
import type { ListingStato } from "@/services/listing-service";
import type { SellerOrderStatus } from "@/services/types";

/** Il minimo che serve a queste derivazioni: nessuna vuole l'ordine intero. */
export type OrdineRiepilogo = IstantaneaVenditore & {
  prezzo_cents: number;
  created_at: string;
};

/** Il minimo che serve dalla lista annunci del proprietario. */
export type AnnuncioRiepilogo = { stato: ListingStato };

// ---------------------------------------------------------------------------
// Riepilogo (KPI)
// ---------------------------------------------------------------------------

/**
 * Gli stati venditore che aspettano un gesto **del venditore**.
 *
 * `spedito` e `consegnato` restano fuori: la palla è al compratore, che deve
 * confermare la ricezione o lasciare scadere l'auto-rilascio. `completato`,
 * `rimborsato` e `annullato` sono chiusi. `contestato` è dentro perché una
 * contestazione aperta è esattamente ciò che il venditore deve guardare per
 * primo, anche quando a deciderla sarà la moderazione.
 */
export const STATI_DA_GESTIRE: readonly SellerOrderStatus[] = [
  "nuovo",
  "da_preparare",
  "da_spedire",
  "contestato",
];

const DA_GESTIRE = new Set<SellerOrderStatus>(STATI_DA_GESTIRE);

export type RiepilogoVenditore = {
  /** Annunci in stato `attivo`, cioè visibili nel catalogo pubblico. */
  annunciAttivi: number;
  /** Ordini il cui stato venditore è in `STATI_DA_GESTIRE`. */
  ordiniDaGestire: number;
  /** Ordini il cui stato venditore è `completato`. */
  venditeCompletate: number;
  /** Somma di `prezzo_cents` dei soli ordini completati. Non è un incassato. */
  valoreVenditeCompletateCents: number;
};

export const riepilogoVenditore = (
  ordini: readonly OrdineRiepilogo[],
  annunci: readonly AnnuncioRiepilogo[],
): RiepilogoVenditore => {
  let ordiniDaGestire = 0;
  let venditeCompletate = 0;
  let valoreVenditeCompletateCents = 0;

  for (const ordine of ordini) {
    const stato = sellerStatusDaOrdine(ordine);
    if (DA_GESTIRE.has(stato)) ordiniDaGestire += 1;
    if (stato === "completato") {
      venditeCompletate += 1;
      valoreVenditeCompletateCents += ordine.prezzo_cents;
    }
  }

  return {
    annunciAttivi: annunci.filter((a) => a.stato === "attivo").length,
    ordiniDaGestire,
    venditeCompletate,
    valoreVenditeCompletateCents,
  };
};

// ---------------------------------------------------------------------------
// Distribuzione per stato
// ---------------------------------------------------------------------------

/**
 * L'ordine in cui gli stati vengono mostrati: lo stesso delle schede di
 * `OrderList`, così il grafico e la lista sotto non raccontano due sequenze
 * diverse. `rimborsato` e `annullato` chiudono, e non hanno una scheda propria
 * lato venditore, ma esistono come stato e qui non si nascondono.
 */
export const ORDINE_STATI_VENDITORE: readonly SellerOrderStatus[] = [
  "nuovo",
  "da_preparare",
  "da_spedire",
  "spedito",
  "consegnato",
  "completato",
  "contestato",
  "rimborsato",
  "annullato",
];

export type FettaStato = { stato: SellerOrderStatus; ordini: number };

/**
 * Quanti ordini per stato venditore, nell'ordine sopra.
 *
 * Gli stati a zero non entrano: una barra di altezza nulla con un'etichetta
 * sotto occupa spazio e non dice niente. Se non c'è nessun ordine l'elenco è
 * vuoto, ed è il chiamante a decidere cosa mostrare al posto del grafico.
 */
export const distribuzionePerStato = (ordini: readonly OrdineRiepilogo[]): FettaStato[] => {
  const conteggi = new Map<SellerOrderStatus, number>();
  for (const ordine of ordini) {
    const stato = sellerStatusDaOrdine(ordine);
    conteggi.set(stato, (conteggi.get(stato) ?? 0) + 1);
  }

  return ORDINE_STATI_VENDITORE.filter((stato) => (conteggi.get(stato) ?? 0) > 0).map((stato) => ({
    stato,
    ordini: conteggi.get(stato) ?? 0,
  }));
};

// ---------------------------------------------------------------------------
// Andamento temporale
// ---------------------------------------------------------------------------

/** Quante mensilità mostra il grafico quando il chiamante non lo dice. */
export const MESI_ANDAMENTO = 6;

const ETICHETTE_MESE = [
  "gen",
  "feb",
  "mar",
  "apr",
  "mag",
  "giu",
  "lug",
  "ago",
  "set",
  "ott",
  "nov",
  "dic",
];

export type MeseVendite = {
  /** Chiave `YYYY-MM` in UTC. */
  mese: string;
  /** Etichetta breve per l'asse, per esempio `mar 26`. */
  etichetta: string;
  /** Ordini **ricevuti** in quel mese, in qualunque stato si trovino oggi. */
  ordini: number;
  /** Quanti di quegli ordini sono oggi `completato`. */
  completati: number;
};

/**
 * Il mese in cui l'ordine è nato, letto in UTC.
 *
 * `created_at` arriva da PostgREST come ISO 8601 in UTC, e i primi sette
 * caratteri sono già `YYYY-MM`. Passare da `new Date()` e dai getter locali
 * sposterebbe di un mese ogni ordine creato negli ultimi (o primi) minuti utili
 * del fuso di chi guarda, e renderebbe il test dipendente dalla macchina che lo
 * esegue.
 */
const chiaveMese = (isoUtc: string): string => isoUtc.slice(0, 7);

const chiaveDa = (anno: number, meseZeroBased: number): string =>
  `${anno}-${String(meseZeroBased + 1).padStart(2, "0")}`;

/**
 * Gli ordini ricevuti mese per mese, sulla finestra che finisce con il mese di
 * `riferimento`.
 *
 * **Il bucket è il mese di creazione, non quello di completamento**, e la
 * differenza è sostanziale: un ordine di gennaio completato a marzo conta in
 * gennaio in entrambe le serie. Non è una scelta di stile — non esiste una
 * colonna di completamento leggibile dal client. `ricezione_confermata_at`
 * copre solo la conferma esplicita e resta nullo quando a chiudere l'ordine è
 * l'auto-rilascio, quindi userebbe un istante che per una parte delle righe non
 * c'è. Meglio un asse onesto che una data inventata.
 *
 * `riferimento` è un parametro e non `new Date()` interno perché una funzione
 * che legge l'orologio non è verificabile due volte con lo stesso esito.
 */
export const andamentoMensile = (
  ordini: readonly OrdineRiepilogo[],
  riferimento: Date,
  mesi: number = MESI_ANDAMENTO,
): MeseVendite[] => {
  const finestra: MeseVendite[] = [];

  for (let indietro = mesi - 1; indietro >= 0; indietro -= 1) {
    // `Date.UTC` normalizza da sé un mese negativo riportandosi all'anno
    // precedente, quindi la finestra attraversa il capodanno senza casi
    // speciali.
    const inizio = new Date(
      Date.UTC(riferimento.getUTCFullYear(), riferimento.getUTCMonth() - indietro, 1),
    );
    const meseZeroBased = inizio.getUTCMonth();
    const anno = inizio.getUTCFullYear();
    finestra.push({
      mese: chiaveDa(anno, meseZeroBased),
      etichetta: `${ETICHETTE_MESE[meseZeroBased]} ${String(anno).slice(2)}`,
      ordini: 0,
      completati: 0,
    });
  }

  const indice = new Map(finestra.map((cella) => [cella.mese, cella]));

  for (const ordine of ordini) {
    const cella = indice.get(chiaveMese(ordine.created_at));
    if (!cella) continue;
    cella.ordini += 1;
    if (sellerStatusDaOrdine(ordine) === "completato") cella.completati += 1;
  }

  return finestra;
};

/** Vero quando la finestra non contiene nessun ordine: niente da disegnare. */
export const andamentoVuoto = (andamento: readonly MeseVendite[]): boolean =>
  andamento.every((cella) => cella.ordini === 0);

// ---------------------------------------------------------------------------
// Ordinamento degli annunci
// ---------------------------------------------------------------------------

/**
 * Con quale urgenza un annuncio chiede attenzione al suo proprietario.
 *
 * Non introduce nessuna transizione: è solo l'ordine in cui le schede
 * compaiono. In cima ciò su cui il venditore può agire adesso — una richiesta
 * di modifiche, una bozza mai pubblicata — poi ciò che è vivo, infine ciò che
 * è chiuso e si guarda solo come storico.
 */
export const PRIORITA_ANNUNCIO: Record<ListingStato, number> = {
  modifiche_richieste: 0,
  bozza: 1,
  in_revisione: 2,
  attivo: 3,
  riservato: 4,
  sospeso: 5,
  scaduto: 6,
  rifiutato: 7,
  venduto: 8,
};

/**
 * Ordina per urgenza mantenendo, a parità di stato, l'ordine di arrivo — che
 * `mieiAnnunci()` consegna già dal più recente. `toSorted` non è usato perché
 * il target di compilazione non lo garantisce: si copia e si ordina.
 */
export const ordinaAnnunciPerGestione = <T extends AnnuncioRiepilogo>(
  annunci: readonly T[],
): T[] =>
  [...annunci].sort((a, b) => PRIORITA_ANNUNCIO[a.stato] - PRIORITA_ANNUNCIO[b.stato]);
