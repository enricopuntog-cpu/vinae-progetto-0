# Product Marketing Context — Vinea

**BOZZA — NON APPROVATA DAL TITOLARE**
**Versione:** bozza 1 · **Redatta il:** 31 ottobre 2026 · **Approvazione:** nessuna

## Come devono usarlo le skill

Questo file è un **orientamento**, non una fonte di claim definitivi. Finché questa riga
di stato dice «NON APPROVATA», ogni voce sotto è un fatto del repository (con la sua
fonte) oppure un'ipotesi dichiarata. Nessuna affermazione di qui può finire in testi
pubblici senza il passaggio di approvazione del titolare. Regole fisse:

- Usa solo le voci con etichetta `[VERIFICATO]` come fatti; tutto il resto è `CLAIM DA PROVARE`.
- Non descrivere come disponibile ciò che è `[BETA]`, `[SPENTO]` o `[PIANIFICATO]`.
- Vinea tratta bevande alcoliche: ogni testo promozionale richiede `REVISIONE LEG OBBLIGATORIA`.
- Non indicare numeri di mercato, utenti, ordini, recensioni o risparmi: non esistono dati.
- L'unica lingua è l'italiano; il nome del prodotto è «Vinea» (marchio esteso «Vinea Wine Club»).

Etichette: `[VERIFICATO]` presente nel repository o in `CHANGES.log` alla data indicata ·
`[BETA]` esiste nella beta ma non è dichiarato pronto al lancio · `[SPENTO]` costruito
ma disattivato da una flag · `[PIANIFICATO]` non realizzato · `[IPOTESI]` interpretazione
non documentata dal titolare · `[LEG]` richiede parere professionale.

## 1. Panoramica del prodotto

- **Cos'è** `[VERIFICATO]` — Il README descrive Vinea come «una web app italiana per catalogare una cantina personale, scoprire vini, partecipare ai club tematici e simulare flussi marketplace tra privati» (`README.md`). La Home pubblica la presenta come «il marketplace sociale italiano per il vino tra privati» (`frontend-next/src/app/page.tsx`).
- **Frase della Home** `[VERIFICATO]` — «Ogni bottiglia ha una storia. Trova la prossima.» e «Compra, vendi e cataloga vini tra appassionati italiani.» (`frontend-next/src/app/page-client.tsx`). Approvata come testo del sito, non come promessa commerciale.
- **Categoria** `[VERIFICATO]` — vino; il catalogo è «dedicato esclusivamente alle bottiglie di vino» (barra di fiducia della Home). Gli Accessori Vinea sono un dominio separato in Beta.
- **Tipo di prodotto** `[VERIFICATO]` — applicazione web (non app nativa); la beta pubblica è `https://vineawineclub.com` (`docs/BETA_NETLIFY.md`).
- **Modello di business** `[IPOTESI]` — commissione sulle vendite fra utenti; esistono classi economiche (privato, Partner) con valori decisi dal titolare e configurati lato server (`CHANGES.log`, VP-D). Le percentuali sono interne e **non vanno comunicate**: non risultano approvate per la comunicazione. Nessun ricavo esiste: ordini, indirizzi e Partner in produzione erano 0, 0, 0 al 13 ottobre 2026 (`docs/RESOCONTO_PRE_LANCIO_BUSINESS_PLAN.md`).

## 2. Stato reale delle funzioni (da non confondere)

| Funzione | Stato | Fonte |
|---|---|---|
| Registrazione e accesso con verifica email | `[BETA]` in produzione | `CHANGES.log` (PR #202-#204, #231) |
| Cantina personale (`/cantina`, privata: cataloga le bottiglie con quantità e stato per unità) | `[BETA]` | `docs/VP_C_QUANTITA_MULTIPLE.md` §8, `CHANGES.log` (VP-C) |
| Esplora il catalogo e annunci fra privati | `[BETA]` | Home, `CHANGES.log` |
| Club tematici e Community | `[BETA]`, flag Club attive in produzione al 23 settembre 2026 | `docs/OPERATIONAL_DECISIONS_STATUS.md` |
| Vetrina Partner su invito | `[BETA]`, nessun Partner reale in produzione | `CHANGES.log` (VP-A/B) |
| Accessori (cantina e annunci) | `[BETA]` solo vetrina, nessuna vendita | `CHANGES.log` (VPM-015A/B1/B2/B3) |
| Contestazioni con prove, segnalazioni | `[BETA]` | `docs/OPERATIONAL_DECISIONS_STATUS.md` |
| Messaggistica e notifiche | `[BETA]` (rotte `/messaggi`, `/notifiche`); stato operativo da riverificare prima di citarlo | `docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md` |
| Pagamenti reali | `[SPENTO]` (`PAYMENTS_ENABLED=false`) | `frontend-next/.env.example`, `docs/PRELAUNCH_TASK_RECONCILIATION.md` |
| Spedizioni e ritiro reali | `[SPENTO]` / fail-closed: manca la configurazione operativa e contrattuale | `CHANGES.log` (VP-E, BLOCKERS) |
| Funzioni AI (Sommelier e simili) | `[SPENTO]` | `docs/OPERATIONAL_DECISIONS_STATUS.md` |
| Vendita Partner, ordini con più bottiglie | `[SPENTO]` (`vendita_partner`, `ordini_multi_unita`) | `CHANGES.log` |
| Mercati esteri | `[PIANIFICATO]`: solo predisposizione, oggi IT/EUR | `CHANGES.log` (VP-F) |

Conseguenza per la comunicazione: oggi non si può dire che sia possibile **comprare**
una bottiglia sulla piattaforma, né che sia disponibile un Sommelier AI, né
promettere consegne. La stessa Home dichiara «Beta trasparente: le azioni non ancora
operative sono indicate prima dell'uso». Il README definisce lo stato «pre-release
tecnica» e vieta di attivare pagamenti reali e vendita di alcolici senza validazione
legale e operativa.

## 3. Pubblico

- **Documentato** `[VERIFICATO]` — «appassionati italiani» di vino, maggiorenni (almeno 18 anni; la data di nascita è dichiarata, non verificata con documento: `frontend-next/src/lib/legal/contenuti.ts`).
- **Chi ha già visto il prodotto** `[VERIFICATO]` — un test di validazione di mercato anonimo (`/beta-test`, questionario con prove guidate) è predisposto e in corso di collaudo; **nessun risultato è registrato** nel repository (`CHANGES.log`, NEXT STEPS). Pilot previsto con 5 tester.
- **Personas, ruoli decisionali, lavori da svolgere** `[IPOTESI]` — non documentati dal titolare. Da compilare solo dopo i risultati della validazione. Candidati da confermare: collezionista privato che cataloga la cantina; appassionato che vende o scambia bottiglie; produttore o rivenditore professionale come Partner su invito.
- **Anti-persona** `[IPOTESI]` — minorenni (esclusi per regola); acquirenti che si aspettano un e-commerce con magazzino proprio (Vinea è tra privati e Partner, non è venditore diretto).

## 4. Problema e differenziazione

- **Problema centrale** `[IPOTESI]` — non c'è una fonte che lo enunci. Il README indica solo i bisogni coperti (catalogare, scoprire, club, mercato fra privati).
- **Concorrenti** `[NON DOCUMENTATO]` — nessun confronto competitivo nel repository. Non scrivere confronti con altri servizi finché non esiste una ricerca verificata.
- **Elementi distintivi documentati** `[VERIFICATO]`, da usare come descrizioni di funzione e non come superiorità:
  - dati di provenienza e conservazione dichiarati dal venditore e attribuiti a lui (barra di fiducia della Home);
  - catalogo solo vino;
  - cantina personale privata (`/cantina`);
  - il compratore vede il costo totale prima dell'acquisto (preventivo con scomposizione per classe, VP-D) — solo dove l'acquisto sarà possibile;
  - trasparenza della beta: le azioni non operative sono segnalate.
- **Perché è meglio / perché ci scelgono** `[NON DOCUMENTATO]` — nessuna prova. Vietato dichiararlo.

## 5. Obiezioni e dinamiche di cambio

`[NON DOCUMENTATO]`. Possibili obiezioni da esplorare nella validazione (non risposte): fiducia
nella provenienza fra privati, sicurezza dei pagamenti, tempi e costi di spedizione di bottiglie,
età minima. Le risposte non vanno scritte senza fatti: per i pagamenti e le spedizioni oggi
le funzioni sono spente.

## 6. Linguaggio, tono e identità

- **Nome** `[VERIFICATO]` — Vinea / Vinea Wine Club. Titolo del sito: «Vinea — Ogni bottiglia ha una storia». Anteprima social: «Vinea — Marketplace sociale del vino» (`frontend-next/src/lib/brand/metadata.ts`).
- **Lessico già in uso** `[VERIFICATO]` — Cantina, Club, annunci, appassionati, Partner (solo con «Partner Vinea · Venditore professionale» come badge ufficiale).
- **Palette e stile** `[VERIFICATO]` — bordeaux, crema, oro, antracite, salvia; titoli serif; la registrazione grafica è nel codice del frontend. Le regole di tono di voce **non sono documentate**: `[IPOTESI]` sobrio, italiano, senza enfasi superlativa, coerente con «dati dichiarati» e «beta trasparente».
- **Parole da evitare** `[IPOTESI]` — «garantito», «autentico certificato», «investimento», «migliore», «risparmio», «gratis», termini che suggeriscano esperienza di acquisto già attiva o consigli sul bere.

## 7. Claim ancora da approvare (`CLAIM DA PROVARE`)

Nessuno dei seguenti è a oggi dimostrato nel repository; non vanno usati:

1. qualsiasi promessa di autenticità, qualità o provenienza verificata di una bottiglia (Vinea riporta dati dichiarati dal venditore);
2. «acquisto sicuro», «pagamento protetto», «tutela dell'acquirente» (i pagamenti sono spenti);
3. spedizione, tempi, costi, corrieri, punti di ritiro (non operativi);
4. Sommelier AI e consigli personalizzati (spenti);
5. numeri di utenti, bottiglie, club, venditori, risparmi o conversioni;
6. confronti con altri marketplace;
7. commissioni e prezzi per classe di venditore;
8. «primo/unico/leader» e simili.

## 8. Questioni legali sulla comunicazione del vino `[LEG]`

Tutte aperte; nessuna conformità è dichiarata (`docs/PRELAUNCH_TASK_RECONCILIATION.md`: revisione professionale di termini, privacy, cookie, età e adempimenti aperta).

- Pubblicità e promozione di bevande alcoliche: limiti, avvertenze e destinatari; nessun contenuto rivolto a minori o che incoraggi l'abuso.
- Vendita a distanza di alcolici, accise, IVA e requisiti dell'operatore: non risolti; mercati esteri rinviati (VP-F).
- Verifica dell'età: oggi dichiarazione della data di nascita, non verifica documentale.
- Marchio «Vinea», termini d'uso, informativa, cookie e obblighi sulle piattaforme (DAC7): in revisione professionale.
- Ruolo della piattaforma fra privati e Partner (intermediazione, responsabilità sui dati dichiarati): da definire con il professionista.

## 9. Cosa manca prima di poter approvare questo documento

1. Il titolare conferma o corregge la sezione 1 (frase di sintesi, categoria, modello di business).
2. Risultati reali della validazione di mercato (`/beta-test`) per compilare personas, problema, obiezioni.
3. Decisione del titolare sul tono di voce e sulle parole da evitare (sezione 6).
4. Parere legale sulla sezione 8 prima di qualsiasi testo promozionale.
5. Eventuale ricerca competitiva verificata (sezione 4).

Quando il titolare approva, la riga di stato in alto va sostituita con la data e il nome
dell'approvazione; le voci `[IPOTESI]` approvate vengono promosse a `[VERIFICATO]` una per una.
