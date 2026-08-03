/**
 * Decisione di rilascio dei fondi trattenuti.
 *
 * **Questa non è l'autorità.** L'autorità è `payout_prepara`, che decide in
 * transazione, con la riga dell'ordine bloccata, e `ordine_auto_rilascio_esegui`,
 * che reclama con `for update … skip locked`. Nessuna schermata e nessun job
 * può aggirarle.
 *
 * Serve a due cose che quelle non possono fare:
 *
 * - dire a un'interfaccia *perché* un rilascio non è possibile, senza chiedere
 *   al database di provarci;
 * - rendere verificabile con un test la tavola delle decisioni, che in SQL
 *   esiste ma non è eseguibile in postazione.
 *
 * Le due implementazioni vanno cambiate insieme, e i test di questo file
 * rileggono la migrazione vera per accorgersene quando non succede.
 */

export type StatoPayout =
  | "trattenuto"
  | "in_attesa"
  | "in_corso"
  | "trasferito"
  | "bloccato"
  | "fallito";

export type EsitoRilascio = "da_trasferire" | "gia_trasferito" | "bloccato" | "non_dovuto";

export type MotivoBlocco =
  | "ordine_contestato"
  | "incasso_non_valido"
  | "venditore_non_abilitato";

export type IstantaneaRilascio = {
  payoutStato: StatoPayout;
  contestatoAt: string | null;
  /** Stato della riga `payments`. Solo `paid` autorizza un trasferimento. */
  pagamentoStato: string;
  rimborsatoCents: number;
  /** `charges_enabled` **e** `payouts_enabled` sull'account del venditore. */
  venditoreAbilitato: boolean;
};

export type DecisioneRilascio =
  | { esito: "da_trasferire" }
  | { esito: "gia_trasferito" }
  | { esito: "non_dovuto"; motivo: StatoPayout }
  | { esito: "bloccato"; motivo: MotivoBlocco };

/**
 * L'ordine dei controlli è lo stesso di `payout_prepara`, e non è arbitrario:
 *
 * 1. **già trasferito** viene per primo — è l'uscita idempotente, e deve valere
 *    anche per un ordine contestato dopo il trasferimento, dove il denaro è
 *    uscito e non c'è più niente da decidere;
 * 2. **contestazione** viene prima dell'incasso: un ordine contestato non si
 *    rilascia nemmeno se l'incasso è perfetto;
 * 3. lo stato del payout esclude ciò che non è ancora dovuto (`trattenuto`);
 * 4. incasso e abilitazione del venditore chiudono.
 */
export const decidiRilascio = (istantanea: IstantaneaRilascio): DecisioneRilascio => {
  if (istantanea.payoutStato === "trasferito") return { esito: "gia_trasferito" };

  if (istantanea.contestatoAt !== null || istantanea.payoutStato === "bloccato") {
    return { esito: "bloccato", motivo: "ordine_contestato" };
  }

  if (!["in_attesa", "in_corso", "fallito"].includes(istantanea.payoutStato)) {
    return { esito: "non_dovuto", motivo: istantanea.payoutStato };
  }

  if (istantanea.pagamentoStato !== "paid" || istantanea.rimborsatoCents > 0) {
    return { esito: "bloccato", motivo: "incasso_non_valido" };
  }

  if (!istantanea.venditoreAbilitato) {
    return { esito: "bloccato", motivo: "venditore_non_abilitato" };
  }

  return { esito: "da_trasferire" };
};

export type IstantaneaAutoRilascio = {
  ordineStato: string;
  payoutStato: StatoPayout;
  contestatoAt: string | null;
  autoRilascioScadenza: string | null;
  pagamentoStato: string;
};

/** Gli stati da cui l'auto-rilascio può partire: consegna dichiarata, non oltre. */
const STATI_AUTO_RILASCIABILI = new Set(["consegnato", "verifica"]);

/**
 * Vero solo per un ordine che nessuna esecuzione precedente ha già reclamato.
 *
 * La condizione che porta il peso è `payoutStato === "trattenuto"`: appena la
 * prima esecuzione lo porta a `in_attesa`, questa funzione — come la `where` di
 * `ordine_auto_rilascio_esegui` — smette di vederlo. È ciò che impedisce a due
 * esecuzioni ravvicinate del job di rilasciare due volte lo stesso ordine, e
 * vale anche se la seconda parte prima che la prima abbia creato il Transfer.
 */
export const deveAutoRilasciare = (
  istantanea: IstantaneaAutoRilascio,
  adesso: Date,
): boolean =>
  STATI_AUTO_RILASCIABILI.has(istantanea.ordineStato) &&
  istantanea.payoutStato === "trattenuto" &&
  istantanea.contestatoAt === null &&
  istantanea.pagamentoStato === "paid" &&
  istantanea.autoRilascioScadenza !== null &&
  new Date(istantanea.autoRilascioScadenza).getTime() <= adesso.getTime();

/**
 * Scadenza dell'auto-rilascio a partire dalla consegna. Congelata sulla riga al
 * momento della consegna: cambiare la configurazione dopo non sposta le
 * scadenze già decise.
 */
export const scadenzaAutoRilascio = (consegnatoAt: Date, giorni: number): Date => {
  if (!Number.isInteger(giorni) || giorni < 1 || giorni > 180) {
    throw new RangeError("La finestra di verifica deve essere un intero fra 1 e 180 giorni.");
  }
  return new Date(consegnatoAt.getTime() + giorni * 24 * 60 * 60 * 1000);
};
