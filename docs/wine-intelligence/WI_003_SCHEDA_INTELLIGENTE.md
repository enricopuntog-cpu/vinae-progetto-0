# WI-003 — Scheda Wine Intelligence e contratto per il Sommelier

Stato: consegnato il 20 novembre 2026. Nessuna migration, nessun costo, nessuna
chiamata AI, nessuna modifica a pagamenti, Stripe o logistica. LWIN non importato.

## Cosa fa

Una scheda riutilizzabile (`frontend-next/src/components/vinea/WineIntelligenceCard.tsx`)
che mostra, per un vino, **cosa si sa e con quale grado di certezza**:

- identità (produttore, vino, annata, regione, denominazione, tipologia, formato);
- informazioni enologiche (finestra di bevuta, temperatura, calice, decantazione,
  abbinamenti, occasione);
- per ogni campo: stato (`registrato`, `dichiarato`, `stimato`, `mancante`) e origine;
- qualità: campi noti / stimati / mancanti (conteggi, mai percentuali) e segnalazioni
  di incoerenza;
- rimandi alle sezioni esistenti («Quando berlo», «Abbinamenti», Price Intelligence).
  Non le duplica.

Dove si prova: scheda `/annuncio/[id]` (prima di «Quando berlo», versione completa) e
`/cantina` (sotto ogni vino, versione compatta «Scheda intelligente», richiusa).

## Come si determinano stato e origine

| Caso | Stato | Origine |
| --- | --- | --- |
| Identità, scheda staff | registrato | database_vinea (non certifica ogni campo) |
| Identità, scheda utente | dichiarato | dichiarato_utente |
| Identità, `catalogSource` assente | registrato | non_attribuibile |
| Finestra `editorial` | registrato | database_vinea |
| Finestra `personal` / `owner` | dichiarato | dichiarato_utente |
| Finestra `ai` | stimato | non_attribuibile |
| Finestra `unavailable` o senza anni | mancante | mancante |
| Temperatura / calice / abbinamenti / decantazione da `DEFAULT_META` o da campo vuoto della riga | stimato | non_attribuibile |
| Gli stessi campi da una riga con valore | registrato | database_vinea |

Il ripiego generico di `getWineMeta()` (`DEFAULT_META`) resta, perché evita una
regressione visiva (vedi `services/wine-meta.ts`), ma non è più presentato come
verificato: `eMetaDiRipiego()` e il campo opzionale `WineVintageMeta.ripiego` lo
rendono riconoscibile. `fonte_documentata` non è assegnata a nessun attributo: è
riservata a fonti con riferimento verificabile (catalogo WI-001C B, LWIN).

Segnalazioni: annata implausibile, finestra invertita, apice invertito o fuori
finestra, finestra precedente all'annata, finestra personale diversa dal dato Vinea,
finestra stimata dall'IA, provenienza della scheda sconosciuta, scheda utente, dati di
ripiego. La completezza non è affidabilità: la scheda lo dice.

## Contratto per WI-004 (`lib/wine-intelligence/sommelier.ts`)

`costruisciContestoSommelier({ intelligenza, annuncio?, cantina?, consenso? })`,
funzione pura. Tre contesti separati: `pubblico` (scheda del vino), `annuncio` (quattro
campi pubblici dichiarati dal venditore), `cantinaPrivata` (conteggi di bottiglie,
presenza di finestra personale, preferenza). La Cantina privata entra **solo** con
`consenso.cantinaPrivata === true` (booleano esatto) e i campi sono copiati uno a uno:
note, posizione e prezzo d'acquisto non esistono nel tipo e non passano. I campi
`mancante` finiscono in `lacune`; gli `stimato` hanno `usabileComeFatto: false`.
Edge Function `ai-sommelier` non toccata; WI-004 deve ancora scegliere come invocarlo.

## Compatibilità con il catalogo futuro

`IntelligenzaVino.catalogo` porta `catalogWineId` e `lwin` opzionali (oggi sempre
assenti, `non_collegato`). Quando WI-001C B sarà distribuito basterà valorizzarli e
aggiungere attributi con origine `fonte_documentata`: la scheda funziona già senza.
Non esiste un secondo database canonico.

## Prove

Test in `lib/wine-intelligence/*.test.ts` e `WineIntelligenceCard.test.tsx`. Verifica
nel browser integrato (Next dev, pagina temporanea non committata che montava il
componente con dati dimostrativi) su 375 px e desktop: nessuno scorrimento orizzontale,
dettaglio apribile. **Non** provata nel browser l'integrazione su dati reali di
`/annuncio` e `/cantina` (richiedono Supabase e una sessione): copertura affidata ai
test di struttura, al typecheck e alla CI.

## Limiti aperti

- Lo stato per campo non è tracciato nel database: `registrato` significa «presente in
  `wines`», non «verificato».
- Nessuna foto autorizzata né scheda di annata (previste nel modello solo come estensioni).
- La finestra personale vale solo nello stato locale dell'utente.
