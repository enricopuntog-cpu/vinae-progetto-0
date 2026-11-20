# WI-005 — Consigli dalla tua Cantina

Data: 20 novembre 2026 · Base: `main` `595ef1d` (WI-004, PR #306) · Stato: consegnato.

## Che cosa è

Una sola sezione, «Consigli dalla tua Cantina», in `/cantina` (sotto la striscia del Sommelier, sopra le schede). Sceglie e **motiva la singola bottiglia**; non ripete i contatori già presenti (Pronte da bere, Da attendere, Da bere presto, aperture, contabilità). Funziona interamente sui dati già caricati dai servizi della Cantina: nessuna chiamata AI, nessuna rete, nessuna scrittura, nessuna migration, nessuna Edge Function, nessuna lettura con `service_role`.

Tre criteri:

| Criterio | Cosa fa |
|---|---|
| Cosa apro stasera | Shortlist (3, poi «Mostra altri») di bottiglie apribili con una finestra di bevuta dichiarata, con motivo e origine. |
| Cosa abbino a cena | Categoria (solo da abbinamenti **registrati**) o piatto libero (≥3 caratteri). Distingue abbinamento registrato / generico di ripiego / nessuno. |
| Completa i dati | Per gruppo: annata, regione, denominazione, finestra di bevuta, abbinamenti; `mancante` ≠ `di ripiego`. |

## Moduli

- `frontend-next/src/lib/cantina/consigli.ts` — motore puro e tipizzato (+ `consigli.test.ts`).
- `frontend-next/src/components/vinea/ConsigliCantina.tsx` — sezione (+ `ConsigliCantina.test.tsx`).
- `frontend-next/e2e/consigli-cantina.e2e.ts` — caso browser su dati reali dello stack isolato.
- `page-client.tsx` — monta la sezione e aggiunge `id="gruppo-<chiave>"` alle schede per il collegamento.

Riusati: `computeDrinkPhase`, `eMetaDiRipiego`, `costruisciIntelligenzaVino` (WI-003), `chiaveCantina`, `WineMetaProvider`/`useCercaMeta`, `phaseShort`. Il modello concettuale di WI-004 (motivi espliciti, provenienza, dati mancanti dichiarati) è ripreso, non importato: il browser non dipende dalle funzioni Deno.

## Regole

- Una bottiglia è una riga `bottle_units`. È **apribile** solo se `stato = chiusa`, non venduta, non in vendita, non riservata e senza annuncio che blocchi `bottiglia_apri`. Uno stato non dichiarato non vale «chiusa». Le bottiglie dello stesso vino e formato sono un gruppo, contate una volta.
- La finestra personale (`override`) vale **solo per l'unità che la porta**. Se non indica l'apice, l'apice generale si eredita solo se cade nella finestra personale (difetto trovato dal test e corretto; la fusione per vino della pagina non è stata toccata).
- Ordine «stasera»: fase (`presto` > `ideale` > `pronto` > `oltre`), poi affidabilità della fonte (personale, editoriale, proprietario, IA), poi fine finestra più vicina, poi id. Fasi `attesa`/`quasi` e finestra assente non sono mai consigliate: si contano e si dichiarano. Nessun punteggio è mostrato; nessuna percentuale.
- «Cena»: registrato prima del ripiego, poi livello (ideale/ottimo/possibile), poi fase. Un abbinamento di ripiego è etichettato «generico, non verificato».
- Riproducibile: stesso insieme di dati → stesso ordine, indipendente dall'ordine d'ingresso (testato).

## Privacy

Legge solo `bottiglieCantina`/`viniCantina` dell'utente autenticato, già filtrati dal servizio e dalle RLS. Un test verifica l'assenza di `fetch`, Supabase, `service_role` e provider AI nel modulo e nel componente. Nessun dato lascia il browser.

## Prove

| Livello | Esito |
|---|---|
| Unitari motore (30) + DOM sezione (8) | passano; suite completa `frontend-next` 3746/3746; soglia CI 3708 → 3746 (e i due test che la citano) |
| typecheck, lint, build | puliti (lint: 5 warning preesistenti) |
| Browser su stack locale | NON ESEGUITO: lo stack `vinea_e2e` locale è bloccato dalla guardia (ledger indietro di 5 migrazioni); la guardia non è stata aggirata |
| Browser in CI (`e2e-browser`, @smoke, Chromium desktop) | PR #307: 3 casi nuovi passati sulla testa `2ff008c`; residui 0. Due rossi precedenti erano asserzioni sbagliate del test (plurale dell'avviso; bottiglia senza finestra ancora apribile), non difetti dell'app |
| Suite `completa` (workflow_dispatch, stessa testa) | 280 passati, 0 inattesi, 0 instabili, 4 saltati: Chromium desktop, Chromium 375 px, WebKit; nessuno scorrimento orizzontale, controlli a11y, pulizia a zero residui |

## Limiti

- «Vai alla bottiglia» è un'àncora: se la scheda non è nella vista attuale (filtro diverso da «Tutte») la sezione lo dice con un avviso invece di non fare nulla.
- La finestra personale oggi viene scritta dal pulsante della scheda su tutte le unità del vino al momento del salvataggio; il motore la legge comunque unità per unità (le unità aggiunte dopo non la ereditano) e lo dichiara con un limite neutro.
- Una finestra personale parziale (solo apice o un estremo) non diventa «tua»: mantiene la fonte di base.
- Solo la finestra di bevuta ha un comando reale per essere completata (`Personalizza finestra` nella scheda annuncio, quindi solo con un annuncio collegato). Annata, regione, denominazione e abbinamenti non hanno una via di modifica da qui: la sezione lo dice.
- I dati registrati sono quelli del database Vinea, non certificati. Finché LWIN non è importato l'identità resta `database_vinea`.
- Il consiglio per stasera non tiene conto di occasione, numero di ospiti o gusti: usa finestra, fonte e disponibilità.

## Handoff per l'espansione di Wine Intelligence

1. Con il catalogo canonico (WI-001C B) la fonte documentata alzerebbe l'affidabilità e il rango per fonte in `consigli.ts`.
2. Il Sommelier (WI-004) potrebbe ricevere la shortlist come contesto, senza dipendenza: il motore è indipendente.
3. Un editor di annata/abbinamenti permetterebbe di dare un comando reale alla scheda «Completa i dati».
