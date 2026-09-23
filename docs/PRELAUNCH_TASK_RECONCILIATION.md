# Checklist pre-lancio riconciliata

Aggiornata il 23 settembre 2026. Fonte iniziale: `task.TXT` versione 1.3 fornita dall'utente.
Stati verificati nel [follow-up sicurezza](SECURITY_FOLLOWUP_PR120.md).
Le assegnazioni «C» nel documento non aprono da sole nuove funzionalità o fasi.

| Blocco / voce | Stato e prossimo passo |
| --- | --- |
| A: recupero build in Git | Chiuso. PR #123 unita; produzione e checkout Desktop verificati sul merge `f3c7c3a`. |
| A: dominio e configurazione documentati | Già presenti; aggiornate qui le misure Netlify al 18 settembre. |
| A: ledger e marketplace_config | 60 migrazioni verificate al 22 settembre; griglie e valori operativi vanno comunque riletti prima dei pagamenti. |
| A: Realtime privato | Chiuso: pubblico rifiutato, canale privato ammesso ai partecipanti e negato a estraneo/anonimo; broadcast database ricevuto dal partecipante. |
| A: interruttori Auth | Secure email change, secure password change, leaked password protection ON. Current password OFF. |
| A: gate fail-closed | Chiuso: le cinque porte AI/pagamenti rispondono 503 con CORS esatto sia dal dominio stabile sia da localhost; webhook 503. AI e pagamenti restano OFF. |
| A: backup completo ripristinabile | Chiuso tecnicamente sul backup B2 reale del run `35738026438`: decrypt, database/Auth/Storage, 11/11 blob SHA-256 e smoke 5/5 in ambiente isolato, poi eliminato. Il primo run schedulato `35833711496` ha completato export, cifratura, upload, readback e Object Lock. |
| A: club e contenuti veri | Una riga attuale. Servono nomi, territori, responsabili e contenuti approvati da Enrico prima del seed. |
| A: contestazioni, imballaggio, inviti, supporto | Decisioni Enrico; possiamo redigere le procedure dopo tempi, responsabilità e promesse di servizio. |
| A: commercialista, marchio, MBE, altre offerte, enoteche | Attività esterne Enrico/professionisti. Nessun invio o acquisto eseguito. |
| B: forma/società/IVA/conto, fondo | Decisioni e adempimenti esterni ancora aperti. |
| B: termini/privacy/cookie/registro/DPIA/DAC7/età | Revisione professionale aperta. Resend corretto come fatto tecnico; non dichiarata conformità legale. |
| B: Stripe e scheduler | Scheduler chiuso tecnicamente: URL, token e chiave pubblica configurati; run `35450587237` e `35450783027` hanno invocato davvero la function con `enabled=false`, zero trasferimenti e zero bloccati. Onboarding Stripe resta successivo. |
| B: prelievo OAuth | Google reale: nuova autenticazione, ritorno `/account` e nuova sessione verificati. Retry economico non eseguito con gate OFF; Facebook non esposto dalla UI. |
| B: continuità | Backup B2 e DR tecnico chiusi; il runbook distingue archivio, repository e configurazioni esterne per un progetto nuovo. Restano delegato, pagina di stato indipendente, procedura avvisi e revisione RTO/RPO prima dei pagamenti. |
| B: ordine reale e PAYMENTS_ENABLED | L'ordine scritto è circolare: un pagamento reale richiede il gate attivo. Prima test isolato con provider test; poi finestra controllata di attivazione e importo minimo, esplicitamente concordata. Nessuna accensione in questo task. |
| C: CSP e dati demo | CSP script enforcing con nonce chiusa in PR #123. La nuova chiusura rimuove `i.pravatar.cc` dalle policy; i file demo non sono montati nelle route pubbliche. Resta `style-src 'unsafe-inline'`, richiesto dagli stili React/Radix correnti. |
| C: accessi senza password | Recupero disponibile; flusso magic-link dedicato da definire quando usato davvero. |
| C: marchio, audit esterno, go/no-go, metriche carte/tempo/club, logistica, stato | Non chiusi da test tecnici. Richiedono professionisti, dati beta o decisioni Enrico. |
| D: multi-bottiglia, vetrina, contestazioni automatiche | Non implementati da questa checklist: verificare ammissione e dipendenze roadmap. Vetrina già progettata, restano decisioni commerciali. |
| D: CAPTCHA, MFA/passkey | Fattibili tecnicamente come lavori coordinati separati, con provider/percorso scelto. Non attivare CAPTCHA senza token frontend. |
| D: marketing e Fase13 | Decisioni Enrico. Nessun cutover automatico. |
| E: Europa | Accise, OSS, contratti locali, logistica, traduzioni e riserva restano programma futuro, non autorizzazione operativa. |

## Ordine proposto per proseguire

1. Enrico completa le decisioni organizzative di continuità rimaste nel runbook;
   non riaprire il capitolo tecnico B2/DR senza un guasto, incidente o requisito nuovo.
2. Enrico chiude contenuti club, regole operative e interlocuzioni professionali;
   solo dopo pianificare il gate pagamenti con scheduler e test controllato.
3. Le funzioni di prodotto opzionali restano lavori separati da ammettere in roadmap.

La beta non è dichiarata pronta ai pagamenti o al lancio pubblico.

## Che cosa richiede davvero Enrico

Il blocco manuale della dashboard Realtime è chiuso dall'agente. Backup/restore,
CSP e preparazione degli smoke sono lavori tecnici eseguibili dall'agente.
Per OAuth serve collaborazione soltanto se il provider richiede una password,
un codice, una conferma sul telefono o un'altra verifica personale che l'agente
non può completare. Non occorre inviare password nella chat. Decisioni su club,
procedure, fornitori e adempimenti restano quelle di prodotto/organizzazione
elencate sopra. Tutti i controlli tecnici eseguibili in questa chiusura sono stati completati.
