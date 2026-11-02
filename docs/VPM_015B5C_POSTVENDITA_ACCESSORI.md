# VPM-015B5C — Post-vendita Accessori

## Perimetro e stato

Recupero dell'implementazione esistente nel commit `67bca11`, non un nuovo blocco di sviluppo. Migrazione additiva `20261102150000_vpm_015b5c_postvendita_accessori.sql`, successiva a B5A e B5B. Nessuna attivazione commerciale, nessun pagamento, rimborso o payout reale eseguito. Interruttori Accessori e `PAYMENTS_ENABLED` devono restare spenti.

La correttiva `20261102170000_vpm_015b5c_riconciliazione_code.sql` aggiunge evidenze dei singoli rimborsi firmati e riconciliazione in entrambi gli ordini di arrivo, selezione dei ricavi ammissibili prima del limite e retry con backoff senza abbandono al decimo tentativo. Le richieste con invio ambiguo oltre la finestra prudenziale di 23 ore restano obblighi visibili, senza reinvio automatico: occorre prova firmata o riconciliazione con il provider. Un errore di rete non dimostra mancato invio; solo la configurazione mancante prima della chiamata è trattata come tale. Esecuzione SQL della correttiva NON VERIFICATA.

Il codice è in verifica sul branch `vpm-015b5c-postvendita-accessori`, PR #256: questo documento non certifica merge, deployment né applicazione remota. Prima CI sulla testa `01dc55d`: frontend, backend, payout runner, continuità, Preview ed E2E Accessori verdi. Gate DB fermo sulla classificazione della porta mista `accessori_postvendita_leggi` nel caso 16 di 12h; `f2c9594` corregge la sola classificazione admin-only, conservando matrice delegato/utente e prove di dominio. Nuova esecuzione ancora in attesa; nessuna prova 12zp/12zq dichiarata verde. Produzione non interrogata o modificata durante il recupero.

## Riuso e autorità

- Ordini e pagamenti restano quelli di B5A/B5B; gli adapter post-vendita vivono in `private`, senza concedere letture dirette ai client.
- Contestazioni: vocabolario `dispute_stato` e `dispute_seller_response_kind`, bucket privato `dispute-evidence` e validatore dei percorsi esistenti. Tabelle Accessori separate perché la FK delle contestazioni vino punta a `public.orders`.
- Ricavo: stesso libro Vinea `balance_accounts` / `balance_movimenti`, da pending a disponibile. Nessun Transfer diretto dal rilascio Accessori; l'uscita segue il prelievo esistente.
- Rimborso: stessa Edge Function `payouts-release`, stesso scheduler e token; adapter `RefundProvider` nello stesso modulo del provider Transfer. Nessun secondo job.
- Riconciliazione: webhook Stripe firmato e deduplicato; il PaymentIntent viene riconosciuto nel database. La risposta positiva alla richiesta di rimborso non prova il rimborso eseguito: è `charge.refunded` a confermarlo.

## Ciclo dell'ordine

1. Solo la vendita applicata in modo `provider` apre il post-vendita e il ricavo pending. La vendita simulata B5A non lo apre.
2. La consegna può essere registrata da una porta service-role per il vettore oppure dall'admin. La registrazione manuale non viene presentata come prova del vettore.
3. L'acquirente può aprire una contestazione entro 48 ore dalla consegna registrata. La risposta del venditore ha una propria finestra di 48 ore; l'admin decide dopo risposta o scadenza.
4. Una decisione di rimborso accoda l'importo entro il residuo rimborsabile, comprese le richieste già aperte. Preparazione e retry riusano una chiave stabile.
5. Il rilascio scaduto richiede pagamento valido, nessuna contestazione aperta, nessun rimborso pendente e venditore attivo. Usa lock di dominio, movimento ed evento unici.
6. Il rimborso confermato storna il ricavo, anche dopo l'accredito. Il libro resta l'autorità per la quadratura.
7. Solo l'admin registra un rientro fisico riutilizzabile, una volta per ordine e non oltre la quantità acquistata. I pezzi tornano in Cantina privata: l'annuncio non viene ripubblicato. Articoli rotti o non rientrati non vengono reintegrati automaticamente.

## Superfici e autorizzazioni

- Dettaglio `/ordini-accessori/[id]`: letture e comandi delle parti autorizzate dal database.
- `/admin/accessori-postvendita`: coda e decisioni, con verifica admin server-side e nelle RPC.
- Le porte operative del provider sono riservate a `service_role`; il gate `PAYMENTS_ENABLED` dell'esecutore resta fail-closed.
- Le prove fotografiche restano nel bucket privato condiviso, con policy specifiche per le parti dell'ordine Accessori.
- Nessuna variabile d'ambiente nuova; nessuna modifica ai prezzi o alle commissioni del vino.

## Prove di recupero (2 novembre 2026)

| Controllo | Esito verificato |
| --- | --- |
| Identità del lavoro | HEAD iniziale `67bca11`, branch dedicato; commit originale preservato |
| Frontend-next, Bun 1.3.14 | 3256/3256 test, 0 fallimenti, 195 file, 30.495 asserzioni; soglia CI e due contratti allineati a 3256 |
| Typecheck dopo allineamento dei contratti CI | PASS |
| Lint precedente nello stesso recupero | 0 errori, 12 avvisi preesistenti |
| Build dopo correzioni frontend | PASS, Next.js 16.4.3: compilazione, TypeScript e generazione 41/41 pagine |
| `bash -n` runner e concorrenza 12zp | PASS |
| Griglia SQL 12zp nel gate | Cablata; esecuzione del gate sul commit finale NON VERIFICATA |
| Concorrenza 12zp | 8 casi predisposti; esecuzione e pulizia effettiva NON VERIFICATE |
| Browser | NON VERIFICATO in questo recupero |
| Revisione frontend indipendente | Tre difetti corretti e 19 regressioni aggiunte: fascicolo admin con prove, controllo selezioni obsolete, accesso post-vendita incassato a gate spenti, errore con riprova. Prove di logica/contratto, non browser |
| Revisione di correttezza SQL | Due P1 (webhook prima dell'esito del rimborso; starvation della coda ricavi) e un P2 (rimborso escluso dopo dieci tentativi) corretti nella migrazione successiva, con 25 controlli nella nuova griglia 12zq; revisione statica successiva senza ulteriori rilievi bloccanti, esecuzione SQL ancora NON VERIFICATA |
| Audit indipendente di sicurezza | Concluso: nessun rilievo concreto nella revisione statica; SQL/PostgREST, concorrenza, Stripe e deployment non verificati dall'audit |

I due fallimenti iniziali della suite erano asserzioni di contratto rimaste a `MIN_TESTS: "3206"`; allineate alla soglia B5C già presente `3233`. Nessuna soglia abbassata e nessuna asserzione di comportamento rimossa.

### Gate database

`supabase/tests/12g_ci_run.sh` esegue ora la griglia `12zp_vpm_015b5c_postvendita_accessori.sql` e lo script `12zp_vpm_015b5c_concorrenza.sh`. Segue la nuova griglia `12zq_vpm_015b5c_riconciliazione_code.sql` con 25 controlli di recupero. La griglia 12zp conserva i suoi scenari: i casi 4/5 ora verificano backoff e retry dopo tempo sintetico, i casi 7/10/24 portano prove individuali del rimborso. La concorrenza richiede un solo invio e un concorrente bloccato, anziché due invii simultanei. Nessuna asserzione eliminata per nascondere un errore; aggregate-only e prove non attribuibili sono coperti da 12zq. Il gate completo verifica anche le regressioni B5A/B5B e dei domini precedenti, su stack effimero CI costruito dalle migrazioni del checkout, senza segreti di produzione.

Le otto prove concorrenti coprono preparazione duplicata, webhook contro rilascio, rilascio duplicato, contestazione contro rilascio a finestra aperta/scaduta, retry con chiave stabile, storno dopo accredito e quadratura. Le sessioni usano una barriera advisory e fixture `@conc-12zp.test`. Il trap arresta le sole sessioni del run, pulisce le fixture e confronta gli snapshot degli interruttori; non modifica flag. Esito richiesto: **8/8, residui 0, flag invariati**. Un esito atteso non è prova eseguita.

## Chiusura e limiti

Prima del merge: recepire audit, ottenere tutti i check richiesti verdi sullo SHA esatto e verificare lo stato mergeable. La review Code Owner non autoapprovabile può essere il solo motivo del merge amministrativo previsto da `CLAUDE.md`; nessun bypass di CI.

Dopo il merge: verificare `origin/main`, integrazione e ledger separatamente dal merge, corpi/ACL/policy effettivi e stato fail-closed delle Edge Function, nonché eliminazione dell'eventuale Preview. Le verifiche remote vanno eseguite soltanto nel perimetro autorizzato: il recupero non autorizza accesso o scritture in produzione né operazioni finanziarie reali.

Non sono dimostrati da test unitari o griglie SQL: consegna reale del vettore, regolamento bancario, conformità legale dei resi, funzionamento del provider con credenziali reali o comportamento del browser. Qualsiasi attivazione live resta distinta dalla chiusura tecnica.
