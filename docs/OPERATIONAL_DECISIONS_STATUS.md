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
- Club chiusi al pubblico dietro i due gate `CLUBS_ENABLED=false` e
  `NEXT_PUBLIC_CLUBS_ENABLED=false`, oltre ai grant pubblici revocati fino a un
  lancio deliberato;
- pagamenti, payout e funzioni AI lasciati spenti.

## Verificato in produzione

- PR #126 integrata in `main` al commit `e11d0d4`; CI e deploy Netlify verdi;
- ledger Supabase a 57 migrazioni, incluse le tre di questa consegna;
- auto-rilascio dei nuovi ordini a 2 giorni, bucket `dispute-evidence` privato
  con limite 5 MiB e tutte le nuove tabelle/funzioni presenti;
- zero incidenti attivi, zero utenti `emergency_delegate` e zero grant diretti
  per `anon`/`authenticated` sulle quattro viste pubbliche Club;
- produzione: home HTTP 200, `/community` e `/community/*` HTTP 404,
  `/continuita` riservata tramite login e callback sul dominio stabile;
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
| Flussi Club completi | Pronti lato dati, UI chiusa | Costruire UI proposta/revisione/ingresso/regole/link, testarla con fixture reali, poi concedere le viste pubbliche e accendere la flag. |
| Indici Club suggeriti dagli advisor | Rinviata al pre-lancio | Riesaminare con query e volumi reali le chiavi esterne non coperte; aggiungere soltanto gli indici utili prima di aprire i Club. |
| Supporto operativo | Bloccata esternamente | Definire persone e casella responsabile delle contestazioni prima dei pagamenti reali. |
| Packaging e inviti beta | Bloccata commercialmente | Scegliere partner/fornitura e lista invitati; nessun valore è inventato nel codice. |
| Referral e premi invito | Esclusa per ora | Nessun premio o meccanismo è stato definito; non implementare finché non esiste una decisione commerciale. |
| Club premium, sync social, professionisti | Futuro escluso dall'MVP | Struttura predisposta senza abbonamenti o sincronizzazioni automatiche; requisiti e adempimenti B2C/B2B restano da decidere. |
| Revisione professionale | Bloccata esternamente | Revisione legale/fiscale/privacy e sicurezza indipendente prima di denaro reale. |

## Gate che restano chiusi

- `PAYMENTS_ENABLED=false` e azioni di pagamento disabilitate;
- `AI_ENABLED=false` e azioni IA disabilitate;
- `NEXT_PUBLIC_CLUBS_ENABLED=false`;
- `CLUBS_ENABLED=false`;
- `BACKUP_OFFSITE_ENABLED=false` finché il primo bucket non è configurato e
  verificato;
- nessun utente riceve automaticamente `emergency_delegate`.
