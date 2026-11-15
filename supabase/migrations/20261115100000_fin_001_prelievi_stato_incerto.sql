-- VPM-FIN-001, parte 1 di 2: lo stato `esito_incerto` per i prelievi (G-12).
--
-- Un'etichetta nuova di un enum non si puo usare nella transazione che la crea
-- (SQLSTATE 55P04): per questo e un file a se. Tutta la logica che la usa e nella
-- migrazione successiva, `20261115100100_fin_001_prelievi_esito_incerto.sql`.
--
-- `esito_incerto` e lo stato di un prelievo il cui Transfer puo essere gia partito senza che il
-- nostro stato lo sappia (timeout, risposta 5xx, risposta illeggibile, esecutore morto a meta).
-- Non e `fallito`: `fallito` dice «il fornitore ha rifiutato, nulla e partito» e libera la via
-- dell'annullamento; `esito_incerto` non la libera mai.
--
-- Additiva: nessun dato esistente cambia, nessuna funzione cambia.

alter type public.withdrawal_stato add value if not exists 'esito_incerto';
