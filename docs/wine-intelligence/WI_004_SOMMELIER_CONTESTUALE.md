# WI-004 — Sommelier contestuale

Stato: consegnato nel branch `feature/wi-004-sommelier-contestuale` (base `origin/main` `3c52891`). Nessuna migration, nessun
provider o chiave nuovi, nessuna chiamata AI a pagamento: `AI_ENABLED` e le azioni AI restano spenti.

## Cosa fa

Tre modalità sullo stesso Sommelier (`SommelierChat`, `ai-sommelier`):

| Modalità | Come si apre | Cosa vede il Sommelier |
| --- | --- | --- |
| Generale | pulsante di sempre | niente di più di prima (stesso prompt di sistema, streaming, storico, rate limit) |
| Vino | «Chiedi al Sommelier di questo vino» in `/annuncio/[id]` (solo annunci con uuid) | la scheda del vino riletta dal server: identità, annata e formato, dati enologici, provenienza e stato di ogni attributo, lacune, contraddizioni. Mai prezzo, venditore, storia dell'annuncio |
| Cantina | «Chiedi al Sommelier della mia Cantina» in `/cantina`, poi un gesto esplicito nel pannello | un elenco limitato dei vini realmente posseduti, con quantità, finestra di consumo (editoriale/personale/dichiarata/generica), abbinamenti registrati, lacune |

## Flusso

Domanda → il client invia `contesto` (solo una richiesta) → `apriPorta` (flag, token, stato utente, rate limit) → validazione
del contesto (consenso `=== true`, uuid) → lettura dal database con il client di servizio e filtro sull'utente del token →
motore `_shared/sommelier-contesto.ts` (intento, selezione deterministica, limiti, pulizia) → blocco dati JSON su una
riga, separato da istruzioni di sistema, storico e domanda → provider esistente (`ai-provider`, nessuno nuovo) → risposta in
streaming. Il contesto non viene salvato né registrato nei log: lo storico contiene solo domanda e risposta.

## Consenso alla Cantina

- Spento all'apertura; aprire dalla Cantina non lo concede. Si concede con «Autorizza il Sommelier a usare la mia Cantina».
- Solo in memoria (mai `localStorage`), legato alla coppia (utente, sessione di chat). Si azzera a: chiusura del pannello,
  logout, cambio account, nuova richiesta dalla pagina, «Torna al Sommelier generale», «Cancella conversazione».
- Il server lo ripretende a ogni richiesta; senza, risponde 400 (`consenso_richiesto`) e non legge nulla. Non esiste un registro
  del consenso lato server (richiederebbe una migration).
- Con le azioni AI spente (Beta) il pannello lo dice e non offre un consenso che non autorizzerebbe nulla.

## Selezione e limiti

Intento riconosciuto in modo deterministico dalla domanda: produttore (nome presente fra quelli posseduti), abbinamento
(cibo, ricerca testuale per inizio di parola sugli abbinamenti registrati), finestra («stasera», «aprire», «pronto»…).
Punteggio: produttore 100; abbinamento ideale/ottimo/possibile 30/20/10; finestra in apice/in finestra 25/15 (solo se la
finestra non è una stima), prima/oltre −5/−10; solo bottiglie aperte −20. Spareggio totale (produttore, nome, annata, formato).

| Limite | Valore |
| --- | --- |
| Righe `bottle_units` lette | 1000 (`letturaLimitata` se di più) |
| Gruppi (vino + formato) inviati | 12 |
| Abbinamenti per gruppo / per vino | 4 / 6 |
| Lunghezza di una stringa del database | 80 caratteri |
| Blocco dati serializzato | 8000 caratteri (~2300 token stimati a 3,5 caratteri per token) |

Il campione parziale è dichiarato nel contesto (`troncato`, `motivoTroncamento`, `letturaLimitata`): con la lettura limitata i
totali e l'elenco dei produttori sono parziali e il modello deve dirlo.

## Contratto WI-003 riutilizzato ed esteso

Stesso vocabolario (registrato/dichiarato/stimato, origine, lacune, segnalazioni). `usabileComeFatto` ora è vero SOLO con una
fonte documentata (`fonte_documentata`): un dato «registrato» (presente nel database Vinea) o «dichiarato» (scritto da un utente)
non è un dato verificato; oggi nessun attributo lo è. Aggiunto `affidabilita` (documentata/registrata/dichiarata/non_verificata).
Il motore lato server estende il contratto con: elenco delle bottiglie, quantità distinte per unità e gruppi, abbinamenti reali
(piatto e livello) invece del loro numero, finestra con fase rispetto all'anno corrente, segnalazioni di incoerenza.
`costruisciContestoSommelier` (client) resta come contratto di forma e per anteprime: non alimenta il provider.

## Prove

- `sommelier-contesto.test.ts` (motore), `sommelier-edge.test.ts` (la vera Edge Function con database e provider finti: sola
  consultazione, nessun altro host, owner falsificato, isolamento fra utenti, consenso, Cantina vuota/molte bottiglie, injection,
  errori, log), `sommelier-contesto-ui.test.ts`, `supabase-ai-service-contesto.test.ts`, `SommelierChat.contesto.test.tsx` e
  `.beta.test.tsx` (pannello nel DOM simulato), `sommelier-griglia.test.ts`.
- Griglia SQL `supabase/tests/wi004_sommelier_cantina_lettura.sql`, agganciata a `12g_ci_run.sh`: colonne e privilegi di
  `service_role`, isolamento fra utenti sulla forma SQL equivalente, filtro esplicito come unica barriera. Prima esecuzione in CI.
- Difetto preesistente trovato e corretto: con le azioni AI spente `invia` usciva prima di mostrare l'avviso Beta perché la
  sessione non veniva mai creata.

## Non verificato

- Prova nel browser reale con due account su stack isolato e comportamento reale di PostgREST (embedding `wines!inner`, `count`,
  `limit`): le griglie SQL non passano da PostgREST.
- Comportamento del modello vero (nessuna chiamata a pagamento): provider finto.
- Informativa privacy verso il provider AI per i dati della Cantina (decisione del titolare prima dell'attivazione).

## Debiti

1. Porta `SECURITY DEFINER` a colonne chiuse per la lettura della Cantina (oggi `service_role` + filtro esplicito), con migration.
2. Registro del consenso lato server, se si vorrà un consenso persistente e revocabile da altri dispositivi.
3. Le risposte che citano la Cantina restano nello storico (TTL 30 giorni) finché non si cancella la conversazione.
4. Ricerca degli abbinamenti lessicale (nessun sinonimo); campione per `created_at` crescente oltre 1000 righe.
5. `supabase-db-gate-scope.sh` non elenca `supabase/tests/wi004_*`: una modifica alla sola griglia non fa partire il gate.

## Handoff per WI-005

Il contesto funziona sui dati Vinea e potrà usare il catalogo WI-001C B senza riscrivere la chat: basta che `_shared/sommelier-contesto.ts`
riceva righe con `origine: fonte_documentata` (allora `usabileComeFatto` diventa vero). Attivare l'AI richiede, separatamente,
`AI_ENABLED=true`, `OPENAI_API_KEY`, `NEXT_PUBLIC_AI_UI_ENABLED` e `NEXT_PUBLIC_AI_ACTIONS_ENABLED`, con limite di spesa sul conto del
provider.
