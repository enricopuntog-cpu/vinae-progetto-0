# VPM-015QA-FINAL-B2-COMPLETION — chiusura del collaudo integrato Accessori

Data: 3 novembre 2026. Baseline: `main` = `7de7075` (PR #263). Riprende `docs/VPM_015QA_FINAL_B2.md` senza rifare
le prove già verdi (58 casi privati).

## Esito

**QA-FINAL-B2: TECNICO INTERNO COMPLETATO — STRIPE TEST MODE BLOCCATO.** Il collaudo interno ha trovato e
corretto un difetto P1 reale; la certificazione Stripe in test mode **non è stata eseguita** (nessuna credenziale
in un ambiente autorizzato) ed è **NON VERIFICATA e BLOCCANTE PRIMA DEL LIVE**. Il live non è dichiarato pronto.

## Difetto trovato e corretto (P1)

Il collaudo del percorso Partner nel browser ha mostrato due cose che nessuna griglia SQL né test unitario poteva
vedere:

1. **Prezzo pubblico sbagliato per i Partner.** Vetrina e dettaglio di un annuncio commerciale mostravano
   **22,73 €** (margine 10% dei privati) mentre preventivo, prenotazione e pagamento usano la classe `partner`
   (1500 bps): **23,75 €** per un pezzo da 20,00 €. `private.annuncio_accessorio_pubblico_json` (B3) calcolava il
   prezzo con `'privato'` scritto nel sorgente. Corretto con la migrazione additiva
   `20261103150000_vpm_015qa_final_b2_prezzo_pubblico_partner.sql` (patch puntuale con asserzione di una sola
   occorrenza, come la 015C; classe letta con `annuncio_accessorio_venditore(seller, cantina)`; privilegi
   invariati, nessuno ad `anon`/`authenticated`). Prova prima/dopo: griglia `12zr` caso 24 = **24/25 → 25/25**; lo
   spec Partner riceveva «22,73 € a pezzo» prima della migrazione e passa dopo.
2. **Pannello annuncio assente per le scorte commerciali.** `/partner/accessori` dichiarava «Prepara un annuncio
   dalla scheda», ma la scheda mostrava solo «la vendita professionale arriverà con il catalogo Partner»: lo stato
   per-account (`partner_percorso_non_consentito`) vale per gli accessori personali e nascondeva il comando anche
   alle scorte commerciali. `VenditaAccessorio` riceve ora `commerciale`; l'ammissione resta decisa dal database
   per articolo (preventivo, bozza, pubblicazione).

## Browser

Stack Supabase **nuovo, effimero e isolato** (`vinea_b2c_e2e`, porte 554xx, 108 migrazioni da zero, ledger = file;
lo stack condiviso non è stato toccato). Nuovi spec riusano harness, fixture e helper esistenti:

| Spec | Coperto |
| --- | --- |
| `accessori-partner.e2e.ts` | Partner attivo riconosciuto dal database; pagina Partner e spiegazione al privato; scorta commerciale nuova da 10 con foto e scheda di catalogo; annuncio di 6 con il pannello della UI; `vendita_partner` spento (nessuna vetrina né prenotazione); vetrina con badge «Venditore professionale» e **23,75 €**; prenotazione di 3 + pagamento simulato = vendita parziale 7/3/3, ordine con classe `partner` e 1500 bps; separazione dalla Cantina privata; Partner sospeso (scorte consultabili, modifica rifiutata dal database, nessuna nuova vendita; l'ordine già prenotato si completa e apre il post-vendita); revocato; accessi di privato, altro Partner e anonimo |
| `accessori-postvendita.e2e.ts` | Pannello admin (anonimo → accedi; privato e Partner → 404; admin senza ruolo di rilascio ok; RPC rifiutate agli altri); intenti orfani e rimborsi dovuti con checkout e `vendita_partner` spenti; annullo con pagamento in corso (`pagamento_in_corso`); sessione scaduta; consegna manuale; contestazione con foto privata; risposta del Partner; decisione admin con rimborso parziale; stato finale solo dall'evento firmato (duplicato e ritentativo senza doppio rimborso); `refund_due` che esce dal pannello solo con `charge.refunded` firmato |

Provider: **mock**. Gli eventi del fornitore sono simulati con la stessa porta del webhook firmato
(`accessori_pagamento_applica_evento`), il job dei rimborsi con `accessori_rimborso_prepara`/`registra_esito`:
prova il database e l'interazione utente/admin, **non Stripe**.

Risultato completo (suite intera, tre progetti): vedi la sezione «Esecuzione» in fondo.

## Difetto trovato dalla CI (P2, corretto)

Il primo giro della CI ha fallito su un solo caso: la pagina dell'ordine di un Partner con una contestazione
dava `Minified React error #418` (idratazione). `DisputePanel` (condiviso con il vino) formattava le date con
`toLocale*String("it-IT")` senza fuso: il server gira in UTC, il browser in Europe/Rome, quindi HTML del server e
del client differivano. Riprodotto in locale con `TZ=UTC` (prima: caso 7 rosso; dopo: 12/12) e corretto fissando
`timeZone: "Europe/Rome"`, come già fa il resto dei pannelli; test di contratto `dispute-panel-fuso.test.ts`.
Sulla macchina di sviluppo (fuso di Roma) il difetto non si vedeva: soglia dei test portata a 3324.

## Pannello admin (solo lettura)

`/admin/accessori-postvendita` esteso, nessuna seconda dashboard e nessuna nuova RPC:

- **Intenti orfani** (`accessori_pagamenti_intenti_orfani`): ordine, stato (`da annullare`/`incerto`), fornitore e
  id del PaymentIntent, importo e valuta, stato del pagamento, motivo, data; «Apri nel fascicolo» carica l'ordine
  nelle operazioni esistenti; testo per il controllo manuale nel pannello del fornitore.
- **Rimborsi dovuti** (`accessori_pagamenti_rimborso_dovuto`, ogni `refund_due`, anche senza una richiesta di
  rimborso già accodata): ordine, importo, valuta, già rimborsato, motivo, data. Si chiudono solo con
  `charge.refunded` firmato.
- Nessun pulsante di annullo, rimborso o riconciliazione; nessuna promessa di automatismi. Se una lettura fallisce
  mostra l'errore («Elenco non disponibile… non significa che non ci siano…»), mai un elenco vuoto.
- Accesso: guardia server sul ruolo reale (`user_roles`), RPC con `accessori_admin_richiesto()`. Funziona con
  checkout e `vendita_partner` spenti (provato nel browser).

## Pulizia delle fixture

`12zk_vpm_015b3_e2e_cleanup.sql` svuota ora anche le tabelle figlie (pagamenti, post-vendita, contestazioni,
rimborsi, resi, evidenze, movimenti Partner, Partner e inviti, schede di catalogo di prova, eventi `evt_e2e_*`) con
una funzione `pg_temp` ricorsiva sulle chiavi esterne, a partire dalle sole righe della fixture; riporta anche
`vendita_partner` e la visibilità del catalogo a falso. L'output finale per la CI è invariato. I trigger append-only
restano sospesi **solo** in quella transazione (`session_replication_role = replica`), dietro la guardia «nessun
utente estraneo». Il runner verifica in più 9 contatori di residui delle tabelle figlie (attesi tutti 0) e gli
interruttori (attesi tutti falsi).

## Stripe test mode (Fase E): BLOCCATA DA CONFIGURAZIONE ESTERNA — NON VERIFICATA

Nell'ambiente dell'agente `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` e `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`
sono **assenti** (controllata solo l'esistenza, nessun valore letto). Nessuna prova reale. I 16 punti della Fase E
sono tutti **NON VERIFICATI con Stripe reale**; le sole prove disponibili sono **mock** (test della Edge Function
con provider finto, runtime del Refund provider con `fetch` finto, griglie DB, spec browser con eventi simulati).

### Checklist unica di configurazione

| Cosa | Dove | Come |
| --- | --- | --- |
| `STRIPE_SECRET_KEY` = `sk_test_…` | secret delle Edge Function `payments-checkout` e `payouts-release` del **solo** progetto Supabase di prova (o branch isolato) | Stripe Dashboard in **modalità test** → Developers → API keys; mai in Production, mai in chat |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` = `pk_test_…` e `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED=true` | variabili dell'app di prova (build locale o deploy isolato) | stessa pagina; solo `pk_test_…` fuori produzione |
| `STRIPE_WEBHOOK_SECRET` = `whsec_…` di **test**, `SUPABASE_SERVICE_ROLE_KEY` del progetto di prova, `PAYMENTS_ENABLED=true` | ambiente **server** dell'app di prova (Route Handler `POST /api/public/webhooks/stripe`) e secret `PAYMENTS_ENABLED` delle Edge Function di prova | Dashboard test → Developers → Webhooks → endpoint `https://<app-di-prova>/api/public/webhooks/stripe`, eventi gestiti dal codice: `payment_intent.succeeded`, `.processing`, `.payment_failed`, `.canceled`, `checkout.session.completed`, `.expired`, `.async_payment_succeeded`, `.async_payment_failed`, `charge.refunded`, `account.updated`; in locale: `stripe listen --forward-to http://127.0.0.1:3100/api/public/webhooks/stripe` e il `whsec_` stampato dalla CLI |
| Origini e CORS | secret Edge Function `PAYMENT_ALLOWED_ORIGINS`, `PAYMENT_REDIRECT_ALLOWED_ORIGINS`, `PAYMENT_REDIRECT_ORIGIN` (origine completa dell'app di prova) | mai `*`, mai l'origine di produzione |
| Separazione da Production | progetto/branch Supabase diverso da `pijnmcllmfgjmgsvtcej`; `PAYMENTS_ENABLED` resta `false` in Production | `supabase secrets list --project-ref <ref-di-prova>` (solo nomi, mai valori) |

Comandi di verifica (solo presenza, nessun valore): `supabase secrets list --project-ref <ref-di-prova>`;
`stripe config --list` in modalità test; raggiungibilità dell'endpoint con un evento firmato di test
(`stripe trigger payment_intent.succeeded` verso `stripe listen`).

Prove da eseguire dopo la configurazione, una per scenario e con esito per scenario: creazione PaymentIntent;
Payment Element; carta `4242…` accettata; `4000 0000 0000 0002` rifiutata; `4000 0025 0000 3155` 3D Secure;
ritorno dal provider (non conferma); webhook firmato; conferma dell'ordine solo dal database; evento duplicato e
ritentativo; annullo di un PaymentIntent orfano; incasso tardivo → `refund_due`; rimborso totale e parziale;
`charge.refunded`; metadata di dominio su PaymentIntent **e** Charge (da verificare la copia sulla Charge);
coerenza di importo, valuta e ordine; nessun rilascio anticipato dei fondi al venditore.

## Rischi residui

| Livello | Rilievo | Stato |
| --- | --- | --- |
| P1 | Stripe test mode non eseguita (provider reale, `charge.refunded`, metadata Charge, annullo orfano reale) | aperto, **bloccante live**, richiede credenziali di test in ambiente autorizzato |
| P1 (corretto) | Prezzo pubblico Partner = privato; pannello annuncio assente per le scorte commerciali | corretti in questa PR |
| P1 (corretto) | Nessuna visibilità admin degli intenti orfani e dei `refund_due` senza richiesta accodata | corretta (sola lettura) |
| P2 | Route Handler del webhook firmato e job dei rimborsi non eseguiti end-to-end contro i servizi reali (nel browser si prova solo la porta DB con eventi simulati) | aperto, coperto dal punto Stripe |
| P2 | Metodi di pagamento asincroni vs finestra di prenotazione di 15 minuti | da decidere con la scelta dei metodi |
| P3 | Notifiche post-vendita non collegate; nessuna azione guidata sul pannello (volutamente) | aperto |

## Decisioni riservate al titolare

- Se e quando eseguire la certificazione Stripe in test mode (prerequisito del live) e in quale ambiente isolato.
- Se estendere il pannello oltre la sola lettura (azioni su orfani/rimborsi): nuova funzione, non ammessa qui.
- Regole di reso e recesso, IVA, ripartizione del rimborso fra articolo e logistica, metodi di pagamento.

## Esecuzione e verifiche

- **Browser, suite completa** su Chromium desktop, Chromium 375 px e WebKit contro lo stack isolato a 108
  migrazioni: **130/130** (Chromium desktop 54, Chromium 375 px 38, WebKit 38; i 58 casi preesistenti più i 24 nuovi per progetto). I flussi funzionali Partner e post-vendita girano su tutti e
  tre i progetti (`@cross`), più i controlli di viewport, accessibilità di base e assenza di overflow. Residui: 9
  contatori delle tabelle di prova a 0, 9 contatori delle tabelle figlie a 0, interruttori tutti falsi (compresi
  `vendita_partner` e visibilità del catalogo).
- **Griglia `12zr`**: caso 24 **fallisce prima** della migrazione (24/25, dettaglio `2273`) e passa dopo (**25/25**).
- **Unit/contract**: 3324 test, 0 falliti (soglia CI alzata da 3310 a 3324); lint 0 errori; typecheck e build puliti.
- **Mutazioni**: togliere il ramo d'errore dell'elenco admin o accettare qualunque `stato_intento` fa fallire i test
  unitari. Togliere la guardia di ruolo dalla *pagina* NON fa fallire il caso browser: l'ammissione è nella RPC
  `accessori_postvendita_admin_elenco` (e nelle due nuove), per cui la pagina risponde comunque 404; la guardia di
  pagina è difesa in profondità, il confine è il database (provato: privato e Partner ricevono 404 e le RPC rifiutano).
- **Review indipendente** (`vinea-code-reviewer`, una volta): nessun difetto di prodotto; corretti i falsi verdi dei
  nuovi spec (spazio non separabile nel prezzo, assenze senza controllo positivo, asserzioni sul ricavo troppo
  deboli, commento sulla firma Storage), il testo del pannello sul «totale pagato» e l'aggiornamento degli elenchi
  admin dopo un'azione. **Audit di sicurezza** (`vinea-security-auditor`, una volta): nessun P0/P1/P2; applicati la
  guardia `coalesce(email, '')` e il `raise` oltre il limite di profondità nella pulizia (resa anche sicura sui cicli
  Partner↔inviti), il `revoke` esplicito nella migrazione. Restano P3 dichiarati: elenco degli intenti orfani senza
  `limit`; un Partner sospeso vede il comando «Prepara annuncio» (il database rifiuta); `coalesce(..., 'privato')`
  nella migrazione non scatta mai (l'overload assegna sempre la classe); nessun `has_function_privilege('anon', …)`
  esplicito per `intenti_orfani` nella griglia 12zt.
- Non eseguite in questa sessione: le griglie SQL diverse da `12zr` (invariate), Stripe reale, `payouts-release`
  reale. Nessun dato o risorsa di Production letto o scritto.
