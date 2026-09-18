# Checklist pre-lancio riconciliata

18 settembre 2026. Fonte: `task.TXT` versione 1.3 fornita dall'utente.
Stati verificati nel [follow-up sicurezza](SECURITY_FOLLOWUP_PR120.md).
Le assegnazioni «C» nel documento non aprono da sole nuove funzionalità o fasi.

| Blocco / voce | Stato e prossimo passo |
| --- | --- |
| A: recupero build in Git | Già chiuso dalla PR116; il deploy letto corrisponde al merge PR120. |
| A: dominio e configurazione documentati | Già presenti; aggiornate qui le misure Netlify al 18 settembre. |
| A: ledger e marketplace_config | 54 migrazioni; griglia 16/16 e valori 800/209/25/14. Ripetere prima dei pagamenti. |
| A: Realtime privato | Divieto globale salvato e verificato in produzione: pubblico rifiutato PrivateOnly, privato anonimo Unauthorized, servizio ON. Resta smoke con due utenti autorizzati. Nessun intervento dashboard richiesto a Enrico. |
| A: interruttori Auth | Secure email change, secure password change, leaked password protection ON. Current password OFF. |
| A: gate fail-closed | Porte AI/pagamenti 503; webhook 503. Verifica scheduler/configurazione completa ancora necessaria prima dell'accensione. |
| A: backup completo ripristinabile | Aperto. Prossimo lavoro tecnico indipendente: copia protetta e restore in ambiente isolato, includendo Storage. |
| A: club e contenuti veri | Una riga attuale. Servono nomi, territori, responsabili e contenuti approvati da Enrico prima del seed. |
| A: contestazioni, imballaggio, inviti, supporto | Decisioni Enrico; possiamo redigere le procedure dopo tempi, responsabilità e promesse di servizio. |
| A: commercialista, marchio, MBE, altre offerte, enoteche | Attività esterne Enrico/professionisti. Nessun invio o acquisto eseguito. |
| B: forma/società/IVA/conto, fondo | Decisioni e adempimenti esterni ancora aperti. |
| B: termini/privacy/cookie/registro/DPIA/DAC7/età | Revisione professionale aperta. Resend corretto come fatto tecnico; non dichiarata conformità legale. |
| B: Stripe e scheduler | Prima dell'abilitazione: onboarding verificato e almeno due esecuzioni scheduler riuscite osservate, con configurazione approvata. |
| B: prelievo OAuth | Bloccante prima dei pagamenti. Provare nuova autenticazione e rientro con account reale; nessun denaro necessario per verificare l'identità. |
| B: continuità | Da scrivere insieme alla prova backup/restore: custodia, delega, tempi e ordini durante indisponibilità. |
| B: ordine reale e PAYMENTS_ENABLED | L'ordine scritto è circolare: un pagamento reale richiede il gate attivo. Prima test isolato con provider test; poi finestra controllata di attivazione e importo minimo, esplicitamente concordata. Nessuna accensione in questo task. |
| C: CSP e dati demo | Reporter e direttive di base aggiunti; script con nonce e rimozione avatar demo ancora aperti. |
| C: accessi senza password | Recupero disponibile; flusso magic-link dedicato da definire quando usato davvero. |
| C: marchio, audit esterno, go/no-go, metriche carte/tempo/club, logistica, stato | Non chiusi da test tecnici. Richiedono professionisti, dati beta o decisioni Enrico. |
| D: multi-bottiglia, vetrina, contestazioni automatiche | Non implementati da questa checklist: verificare ammissione e dipendenze roadmap. Vetrina già progettata, restano decisioni commerciali. |
| D: CAPTCHA, MFA/passkey | Fattibili tecnicamente come lavori coordinati separati, con provider/percorso scelto. Non attivare CAPTCHA senza token frontend. |
| D: marketing e Fase13 | Decisioni Enrico. Nessun cutover automatico. |
| E: Europa | Accise, OSS, contratti locali, logistica, traduzioni e riserva restano programma futuro, non autorizzazione operativa. |

## Ordine proposto per proseguire

1. Eseguire smoke autenticati (OAuth, messaggi, immagini private),
   mantenendo pagamenti e AI spenti.
2. Eseguire backup/restore isolato e scrivere il piano di continuità; usare i
   report CSP per preparare la policy completa con nonce.
3. Enrico chiude contenuti club, regole operative e interlocuzioni professionali;
   solo dopo pianificare il gate pagamenti con scheduler e test controllato.

La beta non è dichiarata pronta ai pagamenti o al lancio pubblico.

## Che cosa richiede davvero Enrico

Il blocco manuale della dashboard Realtime è chiuso dall'agente. Backup/restore,
CSP e preparazione degli smoke sono lavori tecnici eseguibili dall'agente.
Per OAuth serve collaborazione soltanto se il provider richiede una password,
un codice, una conferma sul telefono o un'altra verifica personale che l'agente
non può completare. Non occorre inviare password nella chat. Decisioni su club,
procedure, fornitori e adempimenti restano quelle di prodotto/organizzazione
elencate sopra; non bloccano l'esecuzione dei prossimi controlli tecnici.
