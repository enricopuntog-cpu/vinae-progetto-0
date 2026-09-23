# Stato decisioni operative, contestazioni e Club

Aggiornato il 23 settembre 2026. Questo file è la lista persistente dei lavori
conclusi e dei residui che dipendono da account, persone o decisioni esterne.

## Completato nel repository

- banner globale di incidente con registro append-only e pannello riservato ad
  `admin` o `emergency_delegate`;
- status page statica in `status-page/site/`, validata in CI e pubblicata su
  Cloudflare Pages (piano gratuito) a `https://status.vineawineclub.com`;
- workflow giornaliero per backup cifrato Supabase database/Auth e Storage su
  Backblaze B2, con SHA-256, Object Lock e finestre 30/84/366 giorni per le
  copie giornaliere/settimanali/mensili; il conteggio esatto dipende dalle
  Lifecycle Rules e dalla loro corsa quotidiana;
- verifica e preparazione sicura di un archivio offsite per restore isolato;
- contestazioni entro 48 ore dalla consegna, motivi oggettivi, prove fotografiche
  private ricodificate senza EXIF, risposta del venditore entro 48 ore, timeline
  append-only e presa in carico della documentazione;
- coda amministratore con prove firmate temporaneamente, risposta venditore e
  comando per segnare la documentazione completa;
- fondamenta Club per proposta e approvazione, accesso aperto/chiuso, richieste
  di ingresso, moderatori, regolamento versionato, link esterni e audit;
- lancio Club nella PR #128: viste pubbliche limitate ai Club approvati,
  proposta soggetta a revisione, ingresso aperto o su richiesta, uscita tramite
  RPC e pubblicazione consentita soltanto ai membri;
- completamento governance Club: revisione amministrativa di proposte,
  richieste e regolamenti; gestione di membri, moderatori e link esterni da
  parte dei ruoli autorizzati; versioni del regolamento con precedente versione
  valida fino all'approvazione; audit append-only;
- completamento logico delle contestazioni: presa in carico, revisione,
  note amministrative private, decisione motivata, correzione versionata e
  timeline visibile alle parti senza includere le note private; nessuna RPC
  di decisione modifica ordini, pagamenti o payout;
- pagamenti, payout e funzioni AI lasciati spenti.

## Verificato in produzione e in locale

- PR #126 integrata in `main` al commit `e11d0d4`; CI e deploy Netlify verdi;
- PR #128 integrata in `main` al commit `c3e218b`; CI, preview e controlli locali
  verdi con 1582 test;
- ledger Supabase a 60 migrazioni, incluse le due migrazioni di completamento
  `20260921170806` e `20260921230019`;
- verifiche del completamento: 10/10 invarianti SQL passati e quattro
  rifiuti comportamentali verificati in transazione per utente normale e anon;
  1601 test frontend, typecheck e build passati; lint senza errori e con 12
  warning preesistenti; pagina Club pubblica verificata a 320, 375 e 1440 px;
- auto-rilascio dei nuovi ordini a 2 giorni, bucket `dispute-evidence` privato
  con limite 5 MiB e tutte le nuove tabelle/funzioni presenti;
- zero incidenti attivi e zero utenti `emergency_delegate`;
- viste Club con soli grant `SELECT` per `anon`/`authenticated`, un Club
  approvato visibile e zero Club non approvati esposti; le RPC proposta,
  ingresso e uscita restano eseguibili soltanto da utenti autenticati;
- deploy Netlify `6ab117825eacaf1d344142ed` pronto con entrambe le flag Club
  attive in produzione e preview;
- produzione: `/community`, `/community/circolo-vinea`, Home, Ricerca,
  Cantina, Vendita, Messaggi, Account, Centro legale e Continuita si caricano
  senza errori; in sessione autenticata si aprono i moduli proposta Club e
  nuova discussione senza effettuare scritture;
- `payments-checkout` e `connect-onboarding` rispondono HTTP 503; le tre
  funzioni AI rispondono HTTP 503.

Le nuove migrazioni sono applicate in produzione Supabase. La PR #130 è
integrata al commit `8e13f84`; CI su `main` verde, Supabase Preview verde e Netlify Published sul medesimo commit. In sessione autenticata
owner/admin si aprono i pannelli Club e le code amministrative senza errori
browser. Le controversie reali sono zero: la decisione su una pratica non è
stata provata con dati persistenti.

La PR #131 di preflight B2 è integrata al commit `07d77fb` con CI su `main`
verde. Il dispatch manuale `35695015354` del workflow offsite sul commit di
merge ha saltato il job senza eseguire step, con il gate `false`. La produzione
Netlify è rimasta sul Published `8e13f84`, perché il cambiamento non tocca
il frontend. Questo è il record del preflight: dal 22 settembre il gate B2 è
`true`. Dopo i fix nelle PR #133/#134, il primo backup reale `35736812313`
è riuscito; la PR #135 ha aggiunto il download S3 cifrato e il run
`35738026438` ha verificato SHA-256, metadata e Object Lock. A quella verifica
il bucket conteneva due coppie `.age`/`.sha256` sotto `daily/2026/09/`, senza
archivio in chiaro né artifact GitHub. Dettagli nel runbook.

Il restore reale dal run `35738026438` e stato completato in una branch
Supabase isolata con database/Auth/Storage e smoke 5/5, poi eliminata. Il primo
run schedulato con il gate attivo, `35833711496`, e riuscito il 23 settembre:
pipeline completa, readback S3, SHA-256/sidecar/metadata e Object Lock
`GOVERNANCE` verificati, zero artifact. Il capitolo B2/DR e chiuso; la rotazione
least privilege della key principale resta hardening non bloccante.

Il 23 settembre 2026 la PR #141 ha chiuso la verifica end-to-end con
fixture isolate sul branch Preview `julqmamwwidaqmjhoodx`: owner, moderatore
distinto, membro, richiedente, outsider, compratore, venditore, compratore di un
altro ordine e admin. Quattro difetti riprodotti prima della correzione e chiusi
dalla migrazione `20260923160000_club_dispute_e2e_audit_fixes`: prove ed eventi
di base invisibili all'admin non coinvolto, pratica indecidibile dopo una
risposta del venditore arrivata a revisione avviata, prove depositate
cancellabili dalle parti, etichetta di link approvato pubblicata senza
revisione. Nessun movimento economico, nessun provider chiamato. Dettagli in
`CONTESTO_IA/01_STATO_ATTUALE.md`.

Gli advisor Supabase continuano a classificare come `SECURITY DEFINER` le viste
strette e le RPC accessibili agli utenti autenticati, e come "RLS senza policy"
le tabelle raggiungibili soltanto dalle RPC. In questo disegno è intenzionale:
i grant diretti sono revocati e ogni vista/RPC applica l'identità o il ruolo al
suo interno. Gli indici mancanti suggeriti dall'advisor prestazioni sulle nuove
chiavi esterne vanno rivalutati con le query e i volumi reali prima del lancio
dei Club; non aprono accessi e non bloccano la beta chiusa.

## Da completare quando arrivano prerequisiti esterni

| Attività | Stato | Prerequisito / prossima azione |
| --- | --- | --- |
| Backup B2 / DR | Chiuso tecnicamente | Run reale `35738026438` decifrato e ripristinato in isolamento; primo run automatico `35833711496` riuscito con readback e Object Lock. Il runbook copre le tre fonti del failover da zero. Resta solo la rotazione least privilege della key, non bloccante. |
| Pagina di stato indipendente | CHIUSA | Pubblicata il 23/09/2026 su `https://status.vineawineclub.com` (Cloudflare Pages `vinea-status`, piano gratuito, riserva `https://vinea-status.pages.dev`). Unico record DNS aggiunto: `CNAME` `status` → `vinea-status.pages.dev`. HTTPS, header e 375 px verificati live. Aggiornamenti durante un incidente: `status-page/README.md`. |
| Delegato di emergenza | Bloccata esternamente | Nominare una persona, abilitarle MFA e assegnare `emergency_delegate`; provare accesso a `/continuita`. |
| Accessi del delegato | Bloccata esternamente | Concedere alla persona nominata accessi individuali e minimi a GitHub, Supabase, Netlify, DNS e backup; il ruolo applicativo da solo abilita soltanto il banner. |
| Email di incidente | Bloccata da dati e procedura | Definire destinatari, base giuridica, modello approvato e responsabile invio tramite Resend; evitare broadcast per micro-interruzioni. |
| RTO/RPO definitivo | Rinviata prima dei pagamenti | Riesaminare l'obiettivo temporaneo 24h/24h dopo la prima prova B2. |
| Verifica E2E Club/moderatore e contestazioni | Chiusa (PR #141, `e42c14e`, ledger 61) | Moderatore distinto, isolamento cross-Club, contestazione completa fino a decisione e correzione verificati con JWT reali sul branch Preview, 177/177 dopo quattro correzioni; fixture rimosse. Resta facoltativo uno smoke UI autenticato eseguito da una persona. |
| Contenuti iniziali Club | Bloccata editorialmente | In produzione resta il Club approvato `circolo-vinea`; creare altri Club soltanto con nomi, descrizioni e responsabili reali. |
| Indici Club suggeriti dagli advisor | Monitoraggio beta | Riesaminare con query e volumi reali le chiavi esterne non coperte; aggiungere soltanto gli indici dimostrati utili. |
| Supporto operativo | Bloccata esternamente | Definire persone e casella responsabile delle contestazioni prima dei pagamenti reali. |
| Packaging e inviti beta | Bloccata commercialmente | Scegliere partner/fornitura e lista invitati; nessun valore è inventato nel codice. |
| Referral e premi invito | Esclusa per ora | Nessun premio o meccanismo è stato definito; non implementare finché non esiste una decisione commerciale. |
| Club premium, sync social, professionisti | Futuro escluso dall'MVP | Struttura predisposta senza abbonamenti o sincronizzazioni automatiche; requisiti e adempimenti B2C/B2B restano da decidere. |
| Revisione professionale | Bloccata esternamente | Revisione legale/fiscale/privacy e sicurezza indipendente prima di denaro reale. |

## Gate operativi

- `PAYMENTS_ENABLED=false` e azioni di pagamento disabilitate;
- `AI_ENABLED=false` e azioni IA disabilitate;
- i Club sono aperti con `NEXT_PUBLIC_CLUBS_ENABLED=true` e
  `CLUBS_ENABLED=true`; le viste pubbliche mostrano esclusivamente Club
  approvati e le scritture passano dalle RPC autenticate;
- `BACKUP_OFFSITE_ENABLED=true`; il workflow B2 è attivo e fallisce chiuso
  se configurazione, retention o readback non sono validi;
- nessun utente riceve automaticamente `emergency_delegate`.
