# Incident Card — delegato di emergenza

Una pagina da seguire sotto pressione. Mandato completo in
[`EMERGENCY_DELEGATE_ONBOARDING.md`](EMERGENCY_DELEGATE_ONBOARDING.md);
dettagli tecnici in
[`CONTINUITY_AND_BACKUP_RUNBOOK.md`](CONTINUITY_AND_BACKUP_RUNBOOK.md).
Pagamenti e AI restano **spenti**, qualunque cosa succeda.

## Link

- Banner Vinea: `https://vineawineclub.com/continuita`
- Status page: `https://status.vineawineclub.com`, riserva
  `https://vinea-status.pages.dev`; procedura in `status-page/README.md`
- Allarmi backup: issue con etichetta `backup-freshness-alert` nel repository
  GitHub; tabella delle categorie nel runbook, sezione "Freschezza del backup"
- Contatti: scheda contatti nel password manager (non nel repository)

## STOP — fermati e chiama Enrico o il consulente

Non procedere da solo se:

- serve un restore **in produzione**, un nuovo progetto Supabase servito, un
  cambio DNS o di variabili Supabase/Netlify;
- sospetti un accesso non autorizzato, un secret esposto o un account
  compromesso;
- possono essere coinvolti dati personali (possibile data breach);
- un passo del runbook fallisce o dà un risultato che non capisci;
- l'unica soluzione che vedi è cancellare, sovrascrivere o spendere;
- la checklist di riapertura ha anche una sola voce non verificata.

Nel frattempo: banner e status page aggiornati, servizio in manutenzione,
nessuna modifica. Aspettare costa meno che rompere.

## Flusso

1. **Ricevi** l'allarme o la segnalazione. Annota ora (con fuso), sintomo,
   fonte. Niente token, cookie o dati personali negli appunti.
2. **Chiama Enrico**: due tentativi su due canali diversi. Se risponde entro
   30 minuti, da quel momento esegui le sue istruzioni. Incidente di
   sicurezza in corso: non aspettare per i passi 4 e 5.
3. **Classifica:**
   - *manutenzione*: lavoro pianificato;
   - *degrado*: il servizio funziona in parte;
   - *incidente*: servizio giù o dati non disponibili;
   - *sicurezza*: accesso sospetto, dati esposti, secret compromesso → STOP
     dopo i passi 4 e 5.
4. **Comunica:** banner in `/continuita` con la categoria, un messaggio breve
   (10-500 caratteri) senza dettagli tecnici, e URL
   `https://status.vineawineclub.com`. Status page su *Investigazione in
   corso*. Se Vinea non si apre, basta la status page.
5. **Preserva le evidenze:** screenshot, URL e id dei run GitHub, id dei deploy
   Netlify, orari. Non cancellare log, issue, deploy o backup.
6. **Niente modifiche distruttive premature.** Prima capire, poi agire.
7. **Identifica il componente:**

   | Sintomo | Componente | Dove guardare |
   | --- | --- | --- |
   | sito non si apre o pagina bianca, API ok | frontend | Netlify → Deploys; ultimo deploy e log di build |
   | dominio non risolve, `vinea-status.pages.dev` sì | DNS | stato Netlify; STOP per ogni modifica DNS |
   | login, dati o foto non funzionano | Supabase | stato Supabase; log del progetto |
   | issue `backup-freshness-alert` o run di backup rosso | backup | run GitHub e categoria nel runbook |
   | tutto giù insieme o un provider segnala un guasto | provider | pagine di stato dei provider |

8. **Applica solo procedure scritte:**
   - frontend: *Lock* dei deploy automatici e *Publish deploy* dell'ultimo
     deploy già verificato;
   - backup: *Run workflow* sul backup, poi sul freshness watch; se fallisce di
     nuovo, lascia l'issue aperta e chiama Enrico;
   - provider: attendi il ripristino del provider e comunica;
   - tutto il resto: STOP.
9. **Rollback o restore:** il rollback Netlify rientra nel mandato. Il restore
   dei dati si fa solo in un ambiente **isolato** e solo per verificare; il
   passaggio in produzione è sempre STOP.
10. **Smoke test:** home, ricerca, login con il tuo account, una pagina
    annuncio, `/community`, una foto; nessuna scrittura non necessaria.
11. **Checklist di riapertura** qui sotto: tutte le voci.
12. **Aggiorna** status page (*Aggiornamento* o *Risolto*) e banner: ritiralo
    o lascia un avviso di chiusura per qualche ora.
13. **Passaggio di consegne a Enrico:** cronologia, azioni fatte, evidenze,
    cose non risolte, accessi o secret che hai visto.
14. **Post-incidente:** entro 48 ore, con Enrico: causa, intervallo di dati
    coinvolto, verifiche, modifiche al runbook; aggiornamento di
    `CHANGES.log`.

## Checklist di riapertura

**Autorità:** Enrico sempre. Il delegato solo se Enrico non è raggiungibile e
il caso rientra nel mandato (nessun restore in produzione, nessun cambio DNS,
di variabili o di provider, nessun sospetto di sicurezza aperto).

Tutte le voci verificate e annotate:

- [ ] sito raggiungibile sul dominio stabile, via HTTPS;
- [ ] Auth: login e logout funzionanti;
- [ ] database coerente: dati recenti presenti, nessun errore nei log; se c'è
      stato un restore, backup scelto anteriore all'incidente con hash validi
      e ledger, RLS, policy e funzioni confrontati con la versione Git
      approvata;
- [ ] nessuna corruzione evidente: conteggi e pagine principali come prima;
- [ ] backup disponibile: freshness watch verde o ultimo backup completo
      recente;
- [ ] Storage: foto pubbliche visibili e URL firmati privati funzionanti;
- [ ] servizi chiave: ricerca, annunci, messaggi e Realtime, `/community`;
- [ ] incidente contenuto: causa rimossa o isolata, nessun sintomo da 30
      minuti;
- [ ] nessun rischio noto non accettabile;
- [ ] pagamenti e AI ancora OFF (`PAYMENTS_ENABLED=false`,
      `AI_ENABLED=false`); se un giorno saranno attivi, restano spenti finché
      ogni ordine non è riconciliato con il provider e i payout dubbi bloccati;
- [ ] status page e banner aggiornati; email solo agli utenti direttamente
      coinvolti e solo con procedura approvata;
- [ ] decisione di riapertura registrata con nome, data, ora e verifiche.
