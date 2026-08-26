/**
 * L'analitica di Cantina: dal fatto grezzo della RPC al numero che si mostra.
 *
 * È un modulo puro — niente Supabase, niente rete, niente orologio — perché le
 * regole contabili che applica sono quelle in cui un errore non si vede:
 *
 * - **`null` è sconosciuto, zero è noto.** Un esborso mancante non entra nel
 *   capitale e non diventa zero; un rimborso totale è un esborso noto di zero.
 * - **L'ordine batte il dato manuale.** Per un acquisto Vinea il costo è
 *   l'esborso netto del pagamento autorevole; il costo manuale non si somma,
 *   o il denaro verrebbe contato due volte.
 * - **Incassa solo ciò che è stato trasferito.** Il prezzo dell'ordine di
 *   vendita non è un incasso: lo è soltanto il payout arrivato al venditore.
 * - **Il valore è solo il riferimento D3-A.** Niente prezzi degli annunci
 *   collegati, niente stime: se un vino non ha uno snapshot, la sua quota di
 *   valore non esiste e la copertura lo dichiara.
 * - **La storia va solo in avanti.** La serie nasce dal primo snapshot reale;
 *   una posizione entra dal suo `acquiredAt` ed esce al suo primo confine di
 *   ciclo di vita (consumo, eliminazione, cessione).
 */

// ---- Forma della risposta RPC ----------------------------------------------
// Rispecchiano una a una le chiavi di `public.cellar_portfolio_analitica()`:
// l'adattatore le valida, questo modulo le interpreta.

export type PosizionePortafoglioRow = {
  bottleUnitId: string;
  wineId: string;
  wineSlug: string;
  produttore: string;
  nome: string;
  annata: number;
  tipo: string;
  formato: string;
  stato: string;
  acquiredAt: string | null;
  acquisizioneFonte: "sconosciuta" | "manuale" | "acquisto_vinea";
  costoManualeCents: number | null;
  ordineAcquistoId: string | null;
  acquistoPrezzoVenditoreCents: number | null;
  acquistoLordoCents: number | null;
  acquistoRimborsoCents: number | null;
  acquistoNettoCents: number | null;
  ordineVenditaId: string | null;
  venditaStato: string | null;
  venditaPayoutStato: string | null;
  venditaIncassoCents: number | null;
  venditaIncassoAt: string | null;
  cedutaAt: string | null;
  deletedAt: string | null;
  consumedAt: string | null;
  riferimentoCents: number | null;
  riferimentoComparabili: number | null;
  riferimentoAt: string | null;
};

export type StoricoRiferimentoRow = {
  wineId: string;
  formato: string;
  medianaCents: number | null;
  comparabili: number;
  observedAt: string;
};

export type PortfolioAnaliticaRisposta = {
  generatoAt: string;
  posizioni: PosizionePortafoglioRow[];
  storico: StoricoRiferimentoRow[];
};

// ---- Risultato per l'interfaccia --------------------------------------------

export type CoperturaPortafoglio = "completa" | "parziale" | "non_disponibile";

export type PuntoValorePortafoglio = {
  at: string;
  valoreCents: number;
  /** Posizioni in cantina a quell'istante con un riferimento disponibile. */
  coperte: number;
  /** Posizioni in cantina a quell'istante senza riferimento: non valgono zero. */
  scoperte: number;
};

export type AnaliticaPortafoglio = {
  generatoAt: string;
  /** Somma dei riferimenti D3-A delle sole posizioni correnti che ne hanno uno. */
  valoreRiferimentoCents: number;
  posizioniCorrenti: number;
  posizioniConRiferimento: number;
  coperturaValore: CoperturaPortafoglio;
  /** Esborsi noti: manuali e netti Vinea. Gli sconosciuti restano fuori. */
  capitaleNotoCents: number;
  posizioniTotali: number;
  posizioniConCosto: number;
  /** Solo payout trasferiti al venditore. */
  incassiTrasferitiCents: number;
  /** `null` quando nessun esborso è noto: la performance non si inventa. */
  performanceCents: number | null;
  /** Solo con esborsi noti maggiori di zero: dividere per zero non è un dato. */
  performancePercentuale: number | null;
  coperturaPerformance: CoperturaPortafoglio;
  /** Storico del riferimento, solo in avanti dal primo snapshot reale. */
  serieValore: PuntoValorePortafoglio[];
};

// ---- Regole -----------------------------------------------------------------

/** Una posizione è corrente finché non ha incontrato alcun confine di uscita. */
const èCorrente = (p: PosizionePortafoglioRow): boolean =>
  p.cedutaAt === null && p.deletedAt === null && p.consumedAt === null;

/**
 * L'esborso noto di una posizione, o `null` se nessuna fonte autorevole lo
 * conosce. Per un acquisto Vinea il pagamento è l'unica fonte: un pagamento
 * non autorevole lascia il fatto sconosciuto, non lo azzera.
 */
const esborsoNoto = (p: PosizionePortafoglioRow): number | null =>
  p.ordineAcquistoId !== null ? p.acquistoNettoCents : p.costoManualeCents;

/**
 * Un importo diventa incasso solo insieme ai due fatti che lo rendono
 * definitivo: payout trasferito e data effettiva del trasferimento.
 */
const incassoTrasferito = (p: PosizionePortafoglioRow): number | null =>
  p.venditaPayoutStato === "trasferito" &&
  p.venditaIncassoAt !== null &&
  p.venditaIncassoCents !== null
    ? p.venditaIncassoCents
    : null;

const copertura = (noti: number, totali: number): CoperturaPortafoglio =>
  totali === 0 || noti === 0 ? "non_disponibile" : noti === totali ? "completa" : "parziale";

/** Il primo confine di uscita raggiunto, o `null` se la posizione è corrente. */
const uscitaAt = (p: PosizionePortafoglioRow): string | null =>
  [p.cedutaAt, p.deletedAt, p.consumedAt]
    .filter((t): t is string => t !== null)
    .sort()[0] ?? null;

export function calcolaAnaliticaPortafoglio(
  risposta: PortfolioAnaliticaRisposta,
): AnaliticaPortafoglio {
  const { posizioni, storico } = risposta;

  const correnti = posizioni.filter(èCorrente);
  const conRiferimento = correnti.filter((p) => p.riferimentoCents !== null);
  const valoreRiferimentoCents = conRiferimento.reduce(
    (s, p) => s + (p.riferimentoCents ?? 0),
    0,
  );

  const esborsi = posizioni.map(esborsoNoto);
  const noti = esborsi.filter((e): e is number => e !== null);
  const capitaleNotoCents = noti.reduce((s, e) => s + e, 0);
  const incassiTrasferitiCents = posizioni.reduce(
    (s, p) => s + (incassoTrasferito(p) ?? 0),
    0,
  );

  // La copertura della performance guarda tutte le posizioni — gli esborsi
  // passati contano anche per le bottiglie uscite — e chiede in più che ogni
  // cessione abbia il suo incasso trasferito e ogni posizione corrente abbia
  // un riferimento. Un fatto assente non vale zero: abbassa la copertura.
  const cessioniIncomplete = posizioni.filter(
    (p) => p.cedutaAt !== null && incassoTrasferito(p) === null,
  ).length;
  const riferimentiMancanti = correnti.length - conRiferimento.length;
  const fattiNoti = noti.length;
  const coperturaPerformance: CoperturaPortafoglio =
    posizioni.length === 0 || fattiNoti === 0
      ? "non_disponibile"
      : fattiNoti === posizioni.length &&
          cessioniIncomplete === 0 &&
          riferimentiMancanti === 0
        ? "completa"
        : "parziale";

  const performanceCents =
    fattiNoti === 0
      ? null
      : valoreRiferimentoCents + incassiTrasferitiCents - capitaleNotoCents;
  const performancePercentuale =
    performanceCents !== null && capitaleNotoCents > 0
      ? (performanceCents / capitaleNotoCents) * 100
      : null;

  return {
    generatoAt: risposta.generatoAt,
    valoreRiferimentoCents,
    posizioniCorrenti: correnti.length,
    posizioniConRiferimento: conRiferimento.length,
    coperturaValore: copertura(conRiferimento.length, correnti.length),
    capitaleNotoCents,
    posizioniTotali: posizioni.length,
    posizioniConCosto: fattiNoti,
    incassiTrasferitiCents,
    performanceCents,
    performancePercentuale,
    coperturaPerformance,
    serieValore: serieDelValore(posizioni, storico),
  };
}

/**
 * La serie nasce dal primo snapshot reale e non retrocede mai: senza snapshot
 * è vuota, anche se in cantina c'è valore oggi. A ogni istante osservato la
 * posizione conta solo se era già entrata e non era ancora uscita, e vale il
 * riferimento più recente conosciuto a quell'istante — mai uno futuro.
 */
function serieDelValore(
  posizioni: PosizionePortafoglioRow[],
  storico: StoricoRiferimentoRow[],
): PuntoValorePortafoglio[] {
  if (storico.length === 0 || posizioni.length === 0) return [];

  const viniPosseduti = new Set(posizioni.map((p) => p.wineId));
  const perChiave = new Map<string, StoricoRiferimentoRow[]>();
  for (const s of storico) {
    if (!viniPosseduti.has(s.wineId)) continue;
    const chiave = `${s.wineId}${s.formato}`;
    const punti = perChiave.get(chiave) ?? [];
    punti.push(s);
    perChiave.set(chiave, punti);
  }
  for (const punti of perChiave.values()) {
    punti.sort((a, b) => a.observedAt.localeCompare(b.observedAt));
  }

  const istanti = Array.from(new Set(storico.map((s) => s.observedAt))).sort();

  return istanti.map((at) => {
    let valoreCents = 0;
    let coperte = 0;
    let scoperte = 0;

    for (const p of posizioni) {
      // Senza data di acquisizione nota la posizione si considera presente:
      // escluderla fingerebbe uno storico più povero del reale.
      if (p.acquiredAt !== null && p.acquiredAt > at) continue;
      const uscita = uscitaAt(p);
      if (uscita !== null && uscita <= at) continue;

      const punti = perChiave.get(`${p.wineId}${p.formato}`);
      const riferimento = punti?.filter((s) => s.observedAt <= at).at(-1);
      if (riferimento?.medianaCents !== null && riferimento?.medianaCents !== undefined) {
        valoreCents += riferimento.medianaCents;
        coperte += 1;
      } else {
        scoperte += 1;
      }
    }

    return { at, valoreCents, coperte, scoperte };
  });
}
