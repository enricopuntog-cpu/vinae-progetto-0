# Router del contesto durevole Vinea

Ultimo aggiornamento del router: **20 ottobre 2026**.

Questa cartella conserva memoria strutturale e storia datata. Non è il bootstrap
obbligatorio e non sostituisce le fonti vive.

## Lettura obbligatoria a inizio sessione

Fuori da questa cartella:

1. [`../CLAUDE.md`](../CLAUDE.md) — costituzione operativa corrente;
2. [`../CHANGES.log`](../CHANGES.log) — stato e handoff corrente;
3. stato Git del branch/worktree.

[`../AGENTS.md`](../AGENTS.md) è solo il router minimo che porta a quei file.
Non contiene una seconda costituzione.

## Lettura su richiesta

Aprire soltanto ciò che serve al task:

- [`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md) — dossier cronologico di misure e
  stati verificati; l'apertura è una fotografia del 9 agosto 2026, non lo stato
  corrente. L'ultima voce è del 23 settembre 2026: backup B2 attivo, readback
  cifrato e checksum verificati, decrypt e restore Supabase isolato confermati,
  branch e file temporanei eliminati, e primo run schedulato con il gate attivo
  `35833711496` riuscito con pipeline completa e Object Lock.
  Residui e checklist in
  `../docs/SECURITY_FOLLOWUP_PR120.md` e `../docs/PRELAUNCH_TASK_RECONCILIATION.md`.
- La regola delle porte che fanno uscire denaro — riautenticazione recente
  dopo il ramo di replay — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- L'eccezione accettata sulle viste `SECURITY DEFINER` (lint 0010) e i grant
  correnti di `public.profiles` sono in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- La Cantina pubblica del profilo, la regola «l'annuncio pubblico lo dichiara
  `public.public_listings` e nessun altro» e la decisione del 25 settembre 2026
  sulla visibilità per bottiglia o per vino sono in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- Il valore di riferimento della Cantina pubblica (opt-in, default OFF, solo
  aggregati D3 della collezione esposta, storico della collezione attuale) è in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- «Segui una Cantina» — si segue la Cantina e non l'utente, grafo privato del
  follower, nessun conteggio di follower, notifiche dalla Fase 8 con
  destinazione `cellar`, deduplica per pubblicazione e nessun recupero del
  passato — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- La fondazione economica della logistica — tabelle autoritative in `private`,
  `public.packaging_options` che resta il dominio 7c, una sola autorità sull'8%
  con la commissione come componente separata, rotte generiche `pudo`/`domicilio`
  e preventivo immutabile — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- L'instradamento logistico della Beta — né acquirente né venditore scelgono il
  corriere, Vinea assegna provider e servizio, capability come dati e mai come
  ramo, destinazione sempre a punto di ritiro, messaggistica non autorevole,
  due prove obbligatorie congelate alla conferma,
  `private.logistics_label_ready` come unica autorità, `ShipmentProvider`
  distinto da `PackagingProvider`, adattatore solo finto, etichetta del
  fornitore stampata com'è e checkout rinviato a WP7 — è in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`. Lì c'è anche la lettura del prezzo «a una
  data» e la trappola che ne deriva nelle griglie SQL, dove una riga appena
  versionata non si applica alla transazione che l'ha scritta: da leggere prima
  di toccare un lettore versionato o un caso di griglia che passa da una porta
  di versionamento.
- L'approvvigionamento dell'imballaggio — tre prezzi diversi in tre domini
  separati (costo d'acquisto, contributo della transazione, economia della
  spedizione), nome del fornitore come dato in un unico blocco di seme e mai
  come ramo, metadati d'acquisto (pallet, MOQ, scorta pianificata, riordino)
  fuori da ogni decisione di rotta, scorta pianificata distinta dalla giacenza
  reale e nessuna stima inventata dove il dato manca — è in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- La separazione Market Validation — codice partecipante pseudonimo e non
  account, capability anonima in forma hash, niente fingerprinting o identità
  IP, dataset `mv_demo_*` fuori dal marketplace, costo shipping solo demo; MV2
  single-route con buyer+seller obbligatori, foto seller solo locale e preview
  statiche AI/Club facoltative; MV3 admin read-only sui ruoli esistenti, CSV a
  una riga per codice senza capability/PII, URL e QR deterministici, doppia flag
  di attivazione e kill switch server; questionario QV1 dietro il flag server
  `MARKET_VALIDATION_QUESTIONNAIRE_V2_ENABLED` con guida legacy a flag spento — è in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- Vinea Partner VP-A (11 ottobre 2026) — classe commerciale separata dalle
  qualifiche personali e mai ruolo in `user_roles`, marcatore dedicato
  `vinea.partner_porta` legato alla riga, inviti monouso legati all'email
  confermata con token solo nel frammento, porte admin con anti-autoapprovazione,
  audit append-only, gate che blocca gli ordini con venditore Partner finché il
  checkout professionale non esiste, e verifica dei 13 rilievi della bozza
  Codex — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- Vinea Partner VP-B (11-12 ottobre 2026) — vetrina come profilo pubblico con
  proiezione chiusa a 14 chiavi, contenuti in `private.partner_vetrine`, bucket
  `partner-vetrine` solo WebP nella cartella del titolare, gate anche sulle
  proposte, classe dell'interfaccia a tre esiti (privato/commerciale/errore),
  catalogo vuoto e contatto diretto differiti fino ai prodotti di VP-C — è in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- Quantità multiple VP-C (12 ottobre 2026) — una quantità è un conteggio di
  righe di `bottle_units`, formato per unità, lotti idempotenti, un solo
  motore per patrimonio personale e inventario commerciale del Partner mai
  convertiti, interruttori `ordini_multi_unita`/`vendita_partner` spenti — è
  in `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto completo in
  `../docs/VP_C_QUANTITA_MULTIPLE.md`.
- Classi economiche VP-D (12 ottobre 2026) — una riga di `marketplace_config`
  per classe (privati 800 bps, Partner 1500 bps), stessa formula, classe
  decisa e congelata dal database, preventivi autorevoli per le superfici,
  nessun ripiego all'8% — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto
  completo in `../docs/VP_D_CLASSI_ECONOMICHE.md`.
- Logistica multi-collo VP-E (12 ottobre 2026) — più bottiglie spedite esigono
  il preventivo logistico (fail-closed con i motivi), colli pieni con un
  servizio per ordine, `logistica_cents` congelata nell'addebito e fuori dalla
  commissione, piano WP6B che conosce i colli, domicilio preventivabile ma non
  ordinabile — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto completo in
  `../docs/VP_E_LOGISTICA_MULTI_COLLO.md`.
- Accessori Vinea VPM-015A (20 ottobre 2026) — catalogo e bozze in `private`,
  nessun campo economico né percorso di transazione, tre chiavi di visibilità
  (flag pubblica, flag server, interruttore nel database spento di default),
  anteprima solo per l'admin reale, letture pubbliche a 8 chiavi, Partner non
  creatori — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto completo in
  `../docs/VPM_015A_ACCESSORI.md`.
- Cantina Accessori personale VPM-015B1 (21 ottobre 2026) — accessori posseduti
  dagli utenti in `private.cantina_accessori` (privati alla nascita, esposti solo
  per scelta, categoria dalla tassonomia Vinea), due interruttori nel database
  spenti di default (funzione ed esposti, distinti dal catalogo 015A), proiezione
  pubblica a 10 chiavi, bucket Storage privato per proprietario, nessuna vendita —
  è in `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto completo in
  `../docs/VPM_015B1_CANTINA_ACCESSORI.md`.
- Annunci Accessori VPM-015B2 (21 ottobre 2026) — margini per dominio e classe
  (accessori privato 10%, Partner 15%, vino invariato 8%/15%) con una sola formula e
  i parametri di pagamento letti da `marketplace_config`, annunci in sole bozze
  (nessuno stato acquistabile, pubblicazione chiusa anche via RPC), quantità offerta
  sempre sotto lock dell'accessorio, Partner esclusi dal percorso personale,
  categorie fail-closed, spedizione indisponibile senza tariffa reale — è in
  `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto completo in
  `../docs/VPM_015B2_ANNUNCI_ACCESSORI.md`.
- Pubblicazione automatica e moderazione degli annunci Accessori VPM-015B3 (22
  ottobre 2026) — pubblicazione senza approvazione preventiva e moderazione
  successiva sul sistema esistente (`reports`, `audit_log`), interruttore di
  pubblicazione spento con accensione solo dal ruolo `accessori_release`, categorie
  pubblicabili separate da `vendibile` (nessun backfill), snapshot pubblico e foto nel
  bucket privato, oscuramento immediato, nessuna ripubblicazione autonoma, nessun
  acquisto — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`; contratto completo in
  `../docs/VPM_015B3_PUBBLICAZIONE_ACCESSORI.md`.
- Ambiente Claude Code di progetto VPM-LAB-002 (29 ottobre 2026) — 6 agenti e 6
  skill versionati in `.claude/`, solo due agenti con shell in worktree isolato
  dietro una guardia a lista bianca con canarino, guardia dei segreti, plugin
  `frontend-design` fissato da un lock con hash, bootstrap solo locale e verifica
  statica in CI — è in `../docs/CLAUDE_CODE_SETUP.md`.
- [`02_STORIA_FASI.md`](02_STORIA_FASI.md) — cronologia delle fasi e delle PR.
- [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md) —
  architettura durevole, invarianti e debiti. Le regole operative correnti sono
  comunque in `CLAUDE.md`.
- [`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md) — procedure non ovvie per
  ricerca, Supabase e fixture tecniche.
- [`05_INDICE_PR_E_FONTI.md`](05_INDICE_PR_E_FONTI.md) — indice PR e fonti
  storiche.
- [`06_PROMPT_CHAT_OPERATIVE.md`](06_PROMPT_CHAT_OPERATIVE.md) — prompt storici,
  conservati come record e non come policy corrente.
- Delegato di emergenza (PREPARATO, persona non nominata; MFA `aal2` imposta,
  `main` protetto, secret solo negli environment, disaster recovery modello A):
  `../docs/EMERGENCY_DELEGATE_ONBOARDING.md`,
  `../docs/EMERGENCY_DELEGATE_ACCESS_MATRIX.md` e
  `../docs/EMERGENCY_DELEGATE_INCIDENT_CARD.md`; la regola del ruolo di sola
  continuità è in `03_ARCHITETTURA_REGOLE_DEBITI.md`, la cronaca del 23–24
  settembre 2026 in `01_STATO_ATTUALE.md`.
- [`07_BACKUP_DR_HANDOFF.md`](07_BACKUP_DR_HANDOFF.md) — handoff finale del
  capitolo Backup/Disaster Recovery B2 chiuso il 23 settembre 2026.
- [`context-manifest.json`](context-manifest.json) — snapshot machine-readable
  ricostruito il 13 agosto 2026; è datato e non autorevole.

## Gerarchia delle fonti

In caso di contrasto:

1. istruzioni correnti dell'utente e perimetro del task;
2. `CLAUDE.md`;
3. `CHANGES.log`;
4. codice, migrazioni, Git/CI e fatti runtime misurati;
5. ADR, roadmap e documenti correnti di sicurezza/ambiente;
6. questa cartella, specifiche datate, verbali, report e prompt archiviati.

Un verbale storico resta vero come record della sua data, ma non può imporre
oggi un vecchio gate di conferma contraddetto dalla costituzione corrente. Non
va riscritto come se la decisione precedente non fosse mai esistita.

## Coordinate correnti essenziali

- `frontend/` + `backend/` restano la versione servita.
- La beta pubblica `frontend-next` è separata e non è il cutover.
- Fase 11: estensioni AI ammesse per eccezione; implementazione non aperta finché
  non sono soddisfatti i prerequisiti della specifica.
- Vetrina a successo e aliquota per classe di venditore: ammesse per eccezione e
  per nome il 14 settembre 2026. La vetrina è progettata e non implementata
  (`docs/VETRINA_A_SUCCESSO_SPEC.md`); l'aliquota per classe è implementata da
  VP-D con la strada A e il margine Partner a 1500 bps: il 16% di
  `docs/ALIQUOTA_PER_CLASSE_VENDITORE_SPEC.md` è superato e quel documento
  resta storico. L'elenco completo delle eccezioni è in `docs/ROADMAP_V1.md`.
- Fase 12: Club/Community; checkpoint 12a/12b/12c mersi e in produzione.
- `public.clubs` contiene `circolo-vinea` dal 19 agosto 2026; il seed dei sette
  club non è stato eseguito.
- Fase 13: cutover; non iniziata e soggetta a decisione separata.
- Dominio pubblico della beta: **`https://vineawineclub.com`**, di proprietà,
  dal 14 settembre 2026. L'host `timely-lokum-43a12e.netlify.app` non è più
  l'indirizzo pubblico: risponde `308` verso il dominio proprio conservando il
  percorso, ed è ancora una destinazione ammessa nei Redirect URLs di Supabase.
  Il nome del sito Netlify è invariato, quindi le Deploy Preview conservano la
  vecchia forma.
- Email di Auth: **SMTP proprio Resend**, mittente
  `Vinea Wine Club <noreply@vineawineclub.com>`, in uso dal 14 settembre 2026.
  Il mailer di prova incorporato in Supabase e il suo `over_email_send_rate_limit`
  non sono più la strada in uso. La chiave vive nel progetto Supabase, non nel
  repository.
- Conferma email di registrazione: dal 9 ottobre 2026 il link è un
  `token_hash` verificato dal server su `/auth/confirm`, non il `code` PKCE di
  `/auth/callback`, che dipendeva dal browser della registrazione. Causa,
  template versionato (`supabase/templates/confirm-signup.html`), ordine di
  attivazione e rollback in `../docs/ENVIRONMENT.md`. Gli asset di `/brand/*`
  sono serviti con `Cross-Origin-Resource-Policy: cross-origin` perché il logo
  si carica dentro i client di posta; stato DMARC/BIMI del mittente nello
  stesso documento.
- Recupero password e magic link: dal 19 ottobre 2026 (VPM-001, PR #231) usano
  route `token_hash` proprie, `/auth/recupero` e `/auth/accesso`, valide in
  qualunque browser; template «Reset password» e «Magic link» pubblicati a mano
  nel dashboard e provati dal titolare (conferma in chat). Policy password
  unica (6 caratteri, minuscola, maiuscola, numero, simbolo) in
  `frontend-next/src/lib/auth/requisiti-password.ts`. Dettagli e limiti in
  `../docs/EMAIL_AUTH_TEMPLATES.md`.
- Ledger di produzione: **60 migrazioni verificate** al 22 settembre 2026.
  Il restore isolato del 22 settembre dal backup B2 ha confermato le 60
  migrazioni correnti, le policy, le funzioni e i dati delle 91 tabelle del dump.
  L'elenco esatto è in [`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md).
  Un merge non prova che una nuova migrazione sia stata applicata, e un merge
  senza migrazioni può averne distribuite di altrui: rileggere sempre il ledger.
- Chiusura tecnica pre-lancio del 19 settembre 2026: restore isolato concluso
  ed eliminato, backup Storage verificato fuori Git/OneDrive, CSP script con
  nonce in produzione, allowlist Edge verificata 10/10 e scheduler provato con
  due invocazioni reali. `AI_ENABLED` e `PAYMENTS_ENABLED` restano `false`.
  Stato operativo in `../docs/PRELAUNCH_TASK_RECONCILIATION.md` e runbook in
  `../docs/CONTINUITY_AND_BACKUP_RUNBOOK.md`.
- Decisioni operative aggiornate al 22 settembre: fondamenta per backup B2,
  banner incidente/delegato, governance Club e contestazioni fino alla decisione
  logica sono in `../docs/OPERATIONAL_DECISIONS_STATUS.md`. I residui esterni
  restano elencati lì. Club pubblici approvati sono attivi; pagamenti e IA
  restano chiusi dietro i rispettivi gate.
- Rilascio Netlify: il sito è collegato al repository e costruisce una Deploy
  Preview per ogni PR, ma **un merge su `main` non ha ricostruito la produzione**
  — misurato il 15 settembre 2026 sui merge `aca86ac` e `344ad45`. Il motivo è
  un dato della dashboard Netlify e resta una domanda aperta. Fino al 15
  settembre 2026 l'artefatto pubblicato conteneva codice assente da
  `origin/main`; la PR di recupero lo riporta in Git.
- L'integrazione `Supabase Preview` parte a **ogni** push su `main`, anche senza
  file sotto `supabase/migrations/`. Sulle PR con migrazioni può creare un ramo
  temporaneo ed eseguire la suite; sulle PR senza migrazioni può risultare
  `skipped`. Verificare sempre la testa esatta e il ledger dopo il merge.
- Il capitolo Backup/Disaster Recovery B2 è chiuso: gate `true`, run automatico
  `35833711496` verificato, restore reale isolato riuscito e runbook per un
  progetto nuovo completato. Run, oggetti, retention e fonti di ripristino sono
  in `../docs/CONTINUITY_AND_BACKUP_RUNBOOK.md`. Resta solo la rotazione least
  privilege della Application Key come hardening non bloccante; non riaprire il
  capitolo senza una nuova evidenza di guasto, incidente o requisito.

Per ogni fatto più volatile, rileggere `CHANGES.log` e misurare di nuovo.
