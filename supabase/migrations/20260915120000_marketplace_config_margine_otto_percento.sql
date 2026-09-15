-- ===========================================================================
-- Nuova riga di configurazione economica del marketplace.
--
-- Non modifica nulla della Fase 7b: la migrazione
-- 20260803150000_phase_7b_stripe_connect_marketplace.sql è distribuita e
-- quindi congelata. La formula `private.marketplace_totale_cents` NON viene
-- toccata: cambiano soltanto i parametri che riceve, che è esattamente la
-- ragione per cui `marketplace_config` è versionata invece che costante.
--
-- Due parametri si muovono insieme, e vanno letti insieme.
--
--   [1] `riferimento_stripe_percentuale_bps` 150 -> 209. I 150 bps sono la
--       tariffa Stripe per le carte SEE standard, non il costo del pagamento:
--       mancava la commissione Stripe Connect dello 0,25% che la piattaforma
--       paga perché applica tariffe proprie, e mancava il peso delle carte più
--       care. Con 150 bps il margine dichiarato non si realizzava mai — 4,75%
--       con sole carte standard, 3,35% con carta premium, 4,38% sul mix atteso.
--       209 bps è il costo reale ponderato su quel mix, Connect inclusa:
--       0,75×1,50% + 0,20×2,80% + 0,05×3,15% + 0,25% = 2,0925%, ricondotto ai
--       punti base interi.
--
--   [2] `margine_obiettivo_bps` 500 -> 800, per decisione commerciale del
--       14 settembre 2026.
--
--   Corretti insieme, il parametro torna a significare ciò che dichiara: su un
--   prezzo del venditore di 4500 centesimi il compratore paga 4990, la fee di
--   riferimento proiettata vale 129 e il margine netto della piattaforma 361,
--   cioè l'8,02% del prezzo del venditore.
--
-- `riferimento_stripe_fisso_cents` (25) e `auto_rilascio_giorni` (14) non
-- cambiano: sono riportati per intero perché una riga di configurazione è
-- autosufficiente, non un delta sulla precedente.
--
-- Gli ordini già nati non si muovono: i tre parametri sono congelati su
-- `public.orders` alla creazione e non si rileggono da qui. Alla scrittura di
-- questa migrazione `public.orders` è comunque a zero righe, verificato in sola
-- lettura sul progetto `pijnmcllmfgjmgsvtcej` il 15 settembre 2026.
--
-- Il timestamp è successivo all'ultima riga del ledger di produzione,
-- `20260831130000 professional_qualification_delete`, cinquantunesima e ultima,
-- riletta con `list_migrations` il 15 settembre 2026.
-- ===========================================================================

-- L'indice unico `marketplace_config_una_corrente` ammette al più una riga con
-- `valida_fino` nulla. La chiusura deve perciò precedere l'inserimento, e le
-- due devono stare nella stessa transazione: fra le due istruzioni non esiste
-- alcuna riga corrente, e nessun lettore deve poter vedere quel vuoto. `now()`
-- è l'istante della transazione, uguale per entrambe: la riga vecchia si chiude
-- esattamente quando la nuova si apre, senza scoperto né sovrapposizione.
begin;

update public.marketplace_config
   set valida_fino = now()
 where valida_fino is null;

insert into public.marketplace_config (
  margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
  riferimento_stripe_fisso_cents, auto_rilascio_giorni, valida_da, nota
)
values (800, 209, 25, 14, now(),
  'Dal 15 settembre 2026: margine obiettivo 8% per decisione commerciale del '
  '14 settembre 2026, e fee di riferimento portata al costo reale ponderato del '
  'pagamento, 2,09% — mix atteso 75% carte SEE standard, 20% SEE premium, 5% '
  'internazionali — con lo 0,25% di Stripe Connect che i 150 bps precedenti non '
  'contenevano.');

-- Il commento non è ornamento: questi parametri sono esposti pubblicamente
-- dalla vista `public.public_marketplace_config` proprio perché il rincaro sia
-- spiegabile a chi lo paga, e un commento fuorviante è un difetto quanto un
-- valore sbagliato. La colonna non aveva alcun commento a livello di database;
-- il testo sorgente della 7b, che la descrive come «la quota percentuale della
-- carta SEE», resta dov'è perché quel file è congelato.
comment on column public.marketplace_config.riferimento_stripe_percentuale_bps is
  'Quota percentuale della fee di RIFERIMENTO: il costo medio ponderato del '
  'pagamento sul mix atteso dei metodi, commissione Stripe Connect inclusa, non '
  'la tariffa di un singolo tipo di carta. Resta una proiezione usata per '
  'calcolare il rincaro, non una misura: la fee davvero trattenuta si riconcilia '
  'a parte e non entra in alcuna decisione di rilascio fondi.';

commit;
