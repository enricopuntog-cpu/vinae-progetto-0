# Stato decisioni operative, contestazioni e Club

Aggiornato il 21 settembre 2026. Questo file è la lista persistente dei lavori
conclusi e dei residui che dipendono da account, persone o decisioni esterne.

## Completato nel repository

- banner globale di incidente con registro append-only e pannello riservato ad
  `admin` o `emergency_delegate`;
- artefatto statico `status-page/`, pronto per un hosting indipendente;
- workflow giornaliero per backup cifrato Supabase database/Auth e Storage su
  Backblaze B2, con SHA-256, Object Lock e retention 30 giornalieri, 12
  settimanali, 12 mensili;
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
- pagamenti, payout e funzioni AI lasciati spenti.

## Verificato in produzione

- PR #126 integrata in `main` al commit `e11d0d4`; CI e deploy Netlify verdi;
- PR #128 integrata in `main` al commit `c3e218b`; CI, preview e controlli locali
  verdi con 1582 test;
- ledger Supabase a 58 migrazioni, inclusa `20260921111621_launch_clubs`;
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
| Attivare backup B2 | Bloccata esternamente | Creare bucket EU Central con Object Lock, chiave limitata, recipient `age`, variabili e secret GitHub; poi prima esecuzione e verifica oggetti. |
| Pagina di stato indipendente | Bloccata esternamente | Scegliere account/progetto e dominio separati; distribuire `status-page/`, poi inserire l'URL HTTPS nel banner. |
| Delegato di emergenza | Bloccata esternamente | Nominare una persona, abilitarle MFA e assegnare `emergency_delegate`; provare accesso a `/continuita`. |
| Accessi del delegato | Bloccata esternamente | Concedere alla persona nominata accessi individuali e minimi a GitHub, Supabase, Netlify, DNS e backup; il ruolo applicativo da solo abilita soltanto il banner. |
| Email di incidente | Bloccata da dati e procedura | Definire destinatari, base giuridica, modello approvato e responsabile invio tramite Resend; evitare broadcast per micro-interruzioni. |
| RTO/RPO definitivo | Rinviata prima dei pagamenti | Riesaminare l'obiettivo temporaneo 24h/24h dopo la prima prova B2. |
| Flussi Club amministrativi | Parziali | Il frontend utenti copre proposta, ingresso, uscita e discussioni. Restano UI di revisione proposte/richieste, gestione moderatori, versioni del regolamento e link esterni. |
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
- `BACKUP_OFFSITE_ENABLED=false` finché il primo bucket non è configurato e
  verificato;
- nessun utente riceve automaticamente `emergency_delegate`.
