import { randomBytes, randomUUID } from "node:crypto";
import { accedi, rpc, type Ruolo } from "./api";
import { eseguiSql } from "./db";

/**
 * Fixture dei domini critici (VPM-018-E2E-CRIT-01): vino in Cantina e annunci
 * preparati con le porte REALI del venditore (`cellar_bottiglie_aggiungi`,
 * `listing_crea_da_bottiglia`, `listing_logistica_dichiara`, `listing_pubblica`),
 * le stesse del wizard `/vendi`. Nessuna scrittura diretta sulle tabelle: un
 * annuncio che il database non pubblicherebbe non nasce nemmeno qui.
 *
 * Identificatori tracciabili: produttore `Cantina E2E-CRIT` e un'etichetta di
 * corsa nel nome del vino. La pulizia (`pulizia-domini-critici.sql`) parte dagli
 * utenti della fixture, non dai nomi.
 */

export const PRODUTTORE_E2E = "Cantina E2E-CRIT";

/** Etichetta breve e casuale per i nomi sintetici di una corsa. */
export const etichettaCorsa = (): string => randomBytes(3).toString("hex");

/** Gli id finiscono nelle letture di controllo: si accettano solo UUID. */
export const uuid = (valore: unknown): string => {
  if (typeof valore !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(valore)) {
    throw new Error("Identificatore inatteso: non è un UUID.");
  }
  return valore;
};

export interface BottigliaPreparata {
  wineId: string;
  bottleUnitIds: string[];
}

interface EsitoLotto {
  wineId: string;
  bottleUnitIds: string[];
}

export const preparaBottigliaInCantina = async (
  ruolo: Ruolo,
  dati: { nome: string; annata?: number; quantita?: number; costoAcquistoCents?: number },
): Promise<BottigliaPreparata> => {
  const sessione = await accedi(ruolo);
  const esito = await rpc<EsitoLotto>(
    "cellar_bottiglie_aggiungi",
    {
      p_produttore: PRODUTTORE_E2E,
      p_nome: dati.nome,
      p_annata: dati.annata ?? 2016,
      p_regione: "Piemonte",
      p_tipo: "Rosso",
      p_formato: "0,75 L",
      p_quantita: dati.quantita ?? 1,
      p_idempotency_key: `e2e-crit-${randomUUID()}`,
      p_visibilita: "privata",
      p_immagini: [],
      p_acquisition_cost_cents: dati.costoAcquistoCents ?? null,
      p_acquired_at: null,
    },
    sessione,
  );
  if (!esito.ok || !esito.body?.wineId) throw new Error(`Bottiglia non aggiunta in Cantina: HTTP ${esito.status}`);
  return { wineId: uuid(esito.body.wineId), bottleUnitIds: esito.body.bottleUnitIds.map(uuid) };
};

export interface AnnuncioVino {
  listingId: string;
  slug: string;
}

/** Annuncio attivo di una bottiglia: bozza → dichiarazione di consegna → pubblicazione, come il wizard. */
export const pubblicaAnnuncioVino = async (
  ruolo: Ruolo,
  bottleUnitId: string,
  prezzoCents: number,
): Promise<AnnuncioVino> => {
  const sessione = await accedi(ruolo);
  const bozza = await rpc<{ annuncio_id: string; annuncio_slug: string }[]>(
    "listing_crea_da_bottiglia",
    {
      p_bottle_unit_id: bottleUnitId,
      p_prezzo_cents: prezzoCents,
      p_condizione: "Ottimo",
      p_conservazione: "Cantina interrata a temperatura costante.",
      p_storia: "",
      p_immagini: [],
    },
    sessione,
  );
  const riga = bozza.body?.[0];
  if (!bozza.ok || !riga) throw new Error(`Bozza dell'annuncio non creata: HTTP ${bozza.status}`);
  const dichiarata = await rpc(
    "listing_logistica_dichiara",
    {
      p_listing_id: riga.annuncio_id,
      p_confezione_originale_tipo: "nessuna_confezione_originale",
      p_confezione_originale_foto: [],
      p_handoff_venditore: "dropoff_pudo",
    },
    sessione,
  );
  if (!dichiarata.ok) throw new Error(`Consegna non dichiarata: HTTP ${dichiarata.status}`);
  const pubblicata = await rpc("listing_pubblica", { p_listing_id: riga.annuncio_id }, sessione);
  if (!pubblicata.ok) throw new Error(`Annuncio non pubblicato: HTTP ${pubblicata.status}`);
  return { listingId: uuid(riga.annuncio_id), slug: riga.annuncio_slug };
};

/**
 * Ordine IN ATTESA DI PAGAMENTO creato dalla porta autorevole del checkout
 * (`order_checkout_reserve`, eseguibile solo da `service_role`) con il ruolo del
 * server, come lo creerebbe la Edge Function `payments-checkout`: stessi
 * controlli (annuncio attivo, non proprio, classe vendibile, prezzo dal
 * database). Nessun provider e nessun incasso: la porta registra una riga
 * `payments` IN ATTESA (mai pagata), l'ordine resta non pagato e la pulizia dei
 * domini critici li elimina. Ritorna l'id dell'ordine.
 */
export const prenotaOrdineComeServer = (acquirenteId: string, listingId: string): string => {
  const uscita = eseguiSql(
    `begin;
     set local role service_role;
     select (public.order_checkout_reserve(:'e2e_acquirente'::uuid, :'e2e_annuncio'::uuid, null,
             'consegna_mano'::public.delivery_mode, :'e2e_chiave', null)) ->> 'order_id';
     commit;`,
    { e2e_acquirente: acquirenteId, e2e_annuncio: listingId, e2e_chiave: `e2e-crit-${randomUUID()}` },
  );
  const id = uscita.split(/\r?\n/).filter(Boolean).pop() ?? "";
  return uuid(id);
};

/**
 * Una lettura di controllo sul database dello stack dedicato (stessa guardia di
 * identità e possesso di ogni SQL della suite). Solo `select`: le verifiche
 * dicono che cosa è successo, non lo cambiano.
 */
export const leggiDalDatabase = (sql: string): string => {
  if (!/^\s*select\s/i.test(sql)) throw new Error("Solo letture di controllo.");
  // Transazione di sola lettura: anche un `select …; delete …` interpolato per errore non scrive.
  return eseguiSql(`begin transaction read only;\n${sql}\nrollback;`).split(/\r?\n/).filter(Boolean).pop() ?? "";
};

export const UUID_INESISTENTE = "00000000-0000-4000-8000-0000000e2e00";
