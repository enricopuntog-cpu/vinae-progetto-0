// Price Intelligence 1A - adapter Supabase, SOLA LETTURA.
//
// Un solo metodo, e per ora e giusto cosi: la 1A non ha una interfaccia e non
// deve averne una. Questo file esiste perche il prossimo task non debba
// scegliere da capo QUALE oggetto interrogare, e la risposta e: la vista, mai
// la tabella.
//
// Quattro punti che vincolano chi tocca questo file:
//
//   * la lettura passa SEMPRE da `public.wine_price_history`. La tabella base
//     `public.wine_price_observations` non ha alcun grant per `anon` e
//     `authenticated`: una select diretta non e "meno elegante", e un 42501.
//     La barriera e la vista e non la RLS perche la RLS filtra righe e non
//     colonne, e la colonna da non far uscire - `origine_ref`, che porta a un
//     annuncio o a un ordine - sta sulla stessa riga del prezzo;
//   * questo file NON SCRIVE. Non esiste un metodo di scrittura da aggiungere:
//     le osservazioni nascono da due trigger nel database, e la porta di
//     ingresso - `private.price_observation_registra` - ha EXECUTE revocato a
//     `public`, `anon` e `authenticated`. Se un giorno servisse scrivere da
//     qui, la risposta quasi certamente non e "aggiungere un metodo", e
//     "capire quale transizione di dominio e stata dimenticata";
//   * nessun metodo accetta un identificativo di utente, e il tipo di ritorno
//     non ne contiene: la vista non li espone;
//   * `storico` non aggrega. Ordina per `observed_at` decrescente e basta.
//     Media, fascia, tendenza e prezzo suggerito sono la 1B, e vanno decisi
//     con i dati davanti, non qui.

import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  PriceIntelligenceService,
  PriceObservationFonte,
  PriceObservationTipo,
  Result,
  WinePriceObservation,
} from "@/services/types";

type ServiceError = { code?: string; message?: string };

export const noPriceIntelligenceClient = <T>(): Result<T> => ({
  ok: false,
  error: "Connessione a Supabase non configurata.",
});

// Il dettaglio resta in console con il solo codice, come nelle Fasi 8, 9 e 12:
// un messaggio di PostgreSQL puo contenere nomi di colonne e di vincoli.
export const priceIntelligenceError = <T>(
  operazione: string,
  error: ServiceError,
): Result<T> => {
  console.error(`[PriceIntelligence] ${operazione} fallita`, { code: error.code });
  return { ok: false, error: "Storico prezzi non disponibile. Riprova." };
};

type PriceHistoryRow = {
  wine_id: string;
  wine_slug: string;
  produttore: string;
  nome: string;
  annata: number;
  formato: string;
  tipo: PriceObservationTipo;
  fonte: PriceObservationFonte;
  prezzo_cents: number;
  valuta: string;
  observed_at: string;
};

export const mapObservation = (row: PriceHistoryRow): WinePriceObservation => ({
  wineId: row.wine_id,
  wineSlug: row.wine_slug,
  produttore: row.produttore,
  nome: row.nome,
  annata: row.annata,
  formato: row.formato,
  tipo: row.tipo,
  fonte: row.fonte,
  prezzoCents: row.prezzo_cents,
  valuta: row.valuta,
  observedAt: row.observed_at,
});

// Un tetto esiste perche una serie senza tetto e una promessa che il database
// non ha fatto: un vino molto movimentato puo avere centinaia di righe, e
// nessun chiamante della 1A ne ha bisogno per intero. Il valore e alto perche
// tagliare la storia e peggio che leggerla tutta.
const LIMITE_PREDEFINITO = 500;
const LIMITE_MASSIMO = 1000;

export const createSupabasePriceIntelligenceService = (
  client: SupabaseClient | null,
): PriceIntelligenceService => ({
  async storico(input) {
    if (!client) return noPriceIntelligenceClient();

    const { formato, limite } = input;
    const richiesto = limite ?? LIMITE_PREDEFINITO;
    const tetto = Math.min(Math.max(1, Math.trunc(richiesto)), LIMITE_MASSIMO);

    // `formato` si applica solo se e una stringa non vuota: una stringa vuota
    // significa "non lo so", non "il formato senza nome", e filtrarci sopra
    // restituirebbe zero righe facendo sembrare vuota una storia che non lo e.
    const formatoNormalizzato = formato?.trim();

    // Uno dei due, mai entrambi: il tipo dell'input lo impone e qui si legge
    // nello stesso ordine. Lo slug e la via che usa /annuncio/[id], dove
    // l'UUID del vino non arriva mai fino alla pagina; l'UUID resta per chi
    // parte da una riga di catalogo e ce l'ha gia in mano. Entrambe le colonne
    // sono esposte dalla vista, quindi nessuno dei due rami tocca la tabella
    // base.
    //
    // Si sceglie su una stringa non vuota, e senza chiave non si interroga
    // affatto: un identificativo vuoto che scivola nell'altro ramo
    // interrogherebbe `wine_slug = ''`, cioe una colonna che il chiamante non
    // ha mai nominato, e tornerebbe zero righe. Una storia vuota e una
    // risposta; qui la risposta vera e "non so di quale vino stai parlando", e
    // la pagina la mostra gia come storico non disponibile.
    const wineId = input.wineId?.trim();
    const wineSlug = input.wineSlug?.trim();

    let chiaveVino: { colonna: string; valore: string };
    if (wineId) chiaveVino = { colonna: "wine_id", valore: wineId };
    else if (wineSlug) chiaveVino = { colonna: "wine_slug", valore: wineSlug };
    else return priceIntelligenceError("storico", { code: "vino_non_identificato" });

    let query = client
      .from("wine_price_history")
      .select(
        "wine_id, wine_slug, produttore, nome, annata, formato, tipo, fonte, prezzo_cents, valuta, observed_at",
      )
      .eq(chiaveVino.colonna, chiaveVino.valore);

    if (formatoNormalizzato) query = query.eq("formato", formatoNormalizzato);

    const { data, error } = await query
      .order("observed_at", { ascending: false })
      .limit(tetto);

    if (error) return priceIntelligenceError("storico", error);

    return { ok: true, data: ((data ?? []) as PriceHistoryRow[]).map(mapObservation) };
  },
});
