# Verifica di sicurezza dopo la PR 120

Misure del 18 settembre 2026 sulla beta `https://vineawineclub.com`, progetto
Supabase `pijnmcllmfgjmgsvtcej`. Non è una certificazione né un audit esterno.
`security.TXT` e `task.TXT` sono fonti da verificare, non nuove autorizzazioni.
La richiesta corrente autorizza le correzioni tecniche; non apre pagamenti,
Fase 11, nuove funzionalità o cutover Fase 13.

## Allineamento verificato

- PR #119 e #120 entrambe unite. Base di questa verifica:
  `09690c39289e80e9389f8fd3f67ef32bd57b1dba` (merge #120).
- Netlify aveva pubblicato esattamente quel commit nel deploy
  `6aad296a00d5f5000819d6d5`, il 18 settembre alle 12:08 UTC.
- Ledger produzione: 54 migrazioni, ultima `20260918102406_step_up_auth_prelievi`.
- Griglia step-up statica: **9/9 PASSA**. Griglia marketplace: **16/16 PASSA**.
- Nuova griglia `supabase/tests/security_hardening_grants_static.sql`:
  **7/7 PASSA** in produzione, senza creare utenti o dati.
  La vecchia `security_hardening_grants.sql` è per anteprima: crea fixture Auth
  e non va proposta come controllo in sola lettura in produzione.

## Correzioni e controlli chiusi

| Area | Evidenza / intervento |
| --- | --- |
| Dipendenze | Next.js ed eslint-config-next da 16.2.12 a 16.3.3; lockfile rigenerato con Bun 1.3.14 entro i vincoli esistenti. L'audit iniziale segnalava nove pacchetti, incluso Next.js con advisory critici. `bun audit --json` finale: `{}`, exit 0. Audit aggiunto alla CI della beta. |
| Auth | Secure email change e protezione password compromesse già ON. Secure password change attivato, salvato e verificato ON. Require current password resta OFF per gli account OAuth. |
| Password scaduta | Gli errori `reauthentication_needed` / `reauthentication_not_valid` spiegano come uscire e accedere di nuovo o usare il recupero; niente retry senza via d'uscita. Test della mappatura incluso. |
| Grant/RLS | RLS sulle 46 tabelle public; profiles con FORCE RLS, zero privilegi anon, SELECT authenticated e UPDATE sulle sole otto colonne previste. Config pubblica sola lettura. |
| REST anonimo | profiles rifiutato (401/42501); public_marketplace_config 200 con 800/209/25/14. |
| CSRF | Route handler esistenti: callback PKCE e webhook Stripe. Nessuna mutazione di dominio autorizzata dal solo cookie. Webhook firmato e fail-closed; nuovo reporter senza auth, database o provider. La sessione usa cookie SSR, non localStorage. |
| XSS | Nessun nuovo sink utente rilevato; il CSS di ChartStyle riceve configurazioni costanti nei callsite esaminati. Questo non equivale a una prova esaustiva di assenza di XSS. |
| HTTP | Header PR119 misurati sul dominio reale; callback senza codice torna al dominio stabile. PR123 aggiunge CSP completa enforcing con nonce per richiesta e HTML non cacheabile. |
| CSP osservabile | `report-uri` + `report-to` / `Reporting-Endpoints` verso endpoint locale. Registra solo categorie chiuse di direttiva e risorsa; scarta URL, query, token, frammenti, utenti e IP dal payload applicativo. |
| Reporter | Massimo 16 KiB anche senza Content-Length, 10 voci, 30 richieste/minuto per istanza calda, tipi MIME dedicati, cross-site rifiutato e cache disattivata. I log infrastrutturali restano separati. Il limite locale non è una protezione DDoS globale. |
| Indicizzazione | robots.txt vieta la scansione, coerente con noindex della beta. Non è controllo di accesso. |
| Privacy | Resend indicato come SMTP già in uso. Testi ancora in bozza e da validare professionalmente. |
| Gate | Con origine localhost ammessa e chiave anon: payments-checkout e connect-onboarding 503 «Pagamenti non attivi»; tre ai-* 503 «Funzioni AI non attive». Webhook pubblico 503. Nessuna chiamata al provider o movimento di denaro. |

Advisory Next.js verificati:
[GHSA-p293-qw3h-jr36](https://github.com/advisories/GHSA-p293-qw3h-jr36) e
[GHSA-2xp9-vwfh-vxw4](https://github.com/advisories/GHSA-2xp9-vwfh-vxw4).
Nomi hash dei bundle e assenza di sourcemap non dimostrano dipendenze sicure.
Il primo advisory riguarda host Windows; il secondo l'ottimizzatore immagini.
Non si presume sfruttabilità identica in ogni deployment.

## Residui reali

1. **Restrizione Realtime chiusa; smoke autenticato residuo.** Dopo la richiesta
   esplicita dell'utente di eseguire le operazioni manuali residue, disabilitato
   «Allow public access to channels» nella dashboard di produzione. Salvataggio
   riuscito, servizio ON e flag OFF confermati dopo reload. Il servizio ha
   disconnesso i client durante il salvataggio. Prova WebSocket anonima reale:
   pubblico `CHANNEL_ERROR: PrivateOnly`, privato `CHANNEL_ERROR: Unauthorized`.
   Nessun messaggio inviato o dato scritto. L'app usa `private: true` e policy
   per proprietario/membro; il flusso con due partecipanti e un estraneo è stato
   provato sulla copia isolata il 19 settembre.
   Il precedente blocco automatico è risolto, senza ricorrere ad API alternative.
2. **CSP script enforcing chiusa in PR123.** Nonce server per richiesta,
   `strict-dynamic`, `script-src-attr 'none'`; smoke autenticati Realtime e
   Storage firmato conclusi. Resta `style-src 'unsafe-inline'`.
3. **OAuth Google reale provato** con nuova sessione e ritorno `/account`;
   Facebook non è esposto dalla UI e il retry economico resta subordinato al gate.
4. **Backup/restore tecnico provato il 19 settembre.** Restore isolato identico
   per schema/dati/Auth; 11 oggetti Storage salvati localmente con hash/eTag;
   copia isolata eliminata. Il runbook tecnico è in
   `CONTINUITY_AND_BACKUP_RUNBOOK.md`; restano quattro decisioni del titolare.
5. **Allowlist Edge e scheduler chiusi il 19 settembre.** Le cinque porte da
   `Origin: https://vineawineclub.com` e da localhost rispondono 503 del gate
   con `Access-Control-Allow-Origin` esatto. Le run `35450587237` e
   `35450783027` hanno invocato davvero `payouts-release`: `enabled=false`,
   zero trasferimenti e zero bloccati. Nessun gate è stato acceso.
6. `i.pravatar.cc` è stato rimosso dalla CSP; i dati demo residui non sono
   montati nelle route pubbliche. Valutare CAPTCHA integrato e MFA/passkey
   secondo roadmap, senza toggle isolati.

Gli advisor non sono tutti verdi: 18 segnalazioni informative RLS senza policy,
16 viste SECURITY DEFINER (eccezione architetturale già documentata), tre RPC
anonime pubbliche intenzionali (`profilo_pubblico`, `recensioni_pubbliche_elenco`,
`reputazione_pubblica`) e 68 RPC SECURITY DEFINER autenticate da mantenere sotto
revisione. Nessun `function_search_path_mutable`. Non rimuovere le porte di
dominio soltanto per azzerare il contatore degli advisor.

## Validazione del cambiamento

Installazione con lockfile congelato riuscita; audit zero segnalazioni;
1.566 test PASS, typecheck PASS, lint 0 errori / 12 warning preesistenti,
build Next 16.3.3 PASS (26 pagine statiche). Smoke locale del reporter:
204 e log con sole categorie, senza token della richiesta di prova.
I controlli pubblici e le griglie statiche non sostituiscono gli smoke autenticati.

PR121 unita: `848518f3a4e8a2cd95db2ccbf91e6e88c44eb24d`, quattro job CI verdi.
Deploy produzione `6aad86afdd098e0008a93edf` Published il 18 settembre alle
18:46 UTC sullo stesso commit. Smoke reale: home 200, header nuovi e robots
presenti, reporter 204, callback 307 verso il dominio stabile; porte AI e
pagamenti ancora 503. Desktop aggiornato conservando quattro file personali
e staging, con nuovo branch e vecchia storia preservata.

Riconciliazione della checklist: [PRELAUNCH_TASK_RECONCILIATION.md](PRELAUNCH_TASK_RECONCILIATION.md).
