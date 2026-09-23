# Delegato di emergenza — mandato, onboarding, prova e revoca

Stato al 23 settembre 2026: **PREPARATO / persona non ancora nominata.**

Pronti: capability applicativa verificata, MFA `aal2` imposta dal database
per il ruolo, pagina `/account/sicurezza` per collegare l'app authenticator,
`main` protetto da ruleset e CODEOWNERS, environment GitHub limitati a
`main`, matrice degli accessi, Incident Card, checklist di riapertura,
procedura di revoca, drill periodico e destinatari configurabili dell'allarme
backup. Mancano lo spostamento dei valori dei secret negli environment
(autorizzazione di Enrico), la scelta fra i modelli di disaster recovery A e B
(matrice, ultima sezione) e la persona. Nessun nuovo codice serve per
l'onboarding.
Il capitolo si chiude quando esiste una persona reale nominata da Enrico, con
MFA attiva e accessi provati secondo la checklist sotto, firmata e datata.

Documenti collegati:

- [`EMERGENCY_DELEGATE_ACCESS_MATRIX.md`](EMERGENCY_DELEGATE_ACCESS_MATRIX.md) —
  che cosa concedere per ogni servizio, rischi residui e prerequisiti;
- [`EMERGENCY_DELEGATE_INCIDENT_CARD.md`](EMERGENCY_DELEGATE_INCIDENT_CARD.md) —
  procedura breve durante un incidente e checklist di riapertura;
- [`CONTINUITY_AND_BACKUP_RUNBOOK.md`](CONTINUITY_AND_BACKUP_RUNBOOK.md) —
  fonte tecnica completa (backup, restore, failover);
- [`../status-page/README.md`](../status-page/README.md) — aggiornare la
  status page.

## 1. Mandato

### Autorità ordinaria di Enrico

Enrico resta il solo titolare di prodotto, account e decisioni: modello di
business, prezzi e commissioni, provider, policy legali e commerciali,
funzionalità, pagamenti reali, spese, nomina e revoca di admin e delegati,
retention e backup. Può sempre riprendere il controllo di un incidente: da
quel momento il delegato esegue solo ciò che Enrico chiede.

### Autorità temporanea del delegato

Vale soltanto durante un incidente reale **e** con Enrico non raggiungibile
secondo la Incident Card (due tentativi su due canali diversi, 30 minuti senza
risposta; subito per un incidente di sicurezza in corso). Termina al
passaggio di consegne con Enrico.

In quella finestra il delegato **può**:

- pubblicare, aggiornare e ritirare il banner globale in `/continuita`;
- aggiornare la status page;
- verificare lo stato di Vinea e dei provider;
- bloccare i deploy automatici e fare un rollback documentato: su Netlify,
  pubblicare di nuovo l'ultimo deploy già verificato;
- lanciare a mano il backup e il freshness watch da GitHub Actions;
- seguire il runbook per la verifica dei backup e il restore **isolato**;
- mettere il servizio in manutenzione con il banner e, se previsto dal
  runbook, bloccando i deploy;
- eseguire gli smoke test documentati;
- riaprire il servizio solo dopo la checklist di riapertura completa;
- comunicare aggiornamenti operativi tramite banner e status page.

### Che cosa il delegato non può fare autonomamente

- cambiare modello di business, prezzi, commissioni o `marketplace_config`;
- attivare pagamenti reali o AI (`PAYMENTS_ENABLED`, `AI_ENABLED`, gate
  collegati);
- cambiare provider, se non come passo di recovery già scritto nel runbook;
- cancellare dati reali non previsti dal runbook, eliminare backup protetti,
  modificare retention, Object Lock o Lifecycle Rules;
- creare admin, assegnare ruoli, nominare altri delegati;
- cambiare policy legali o commerciali, approvare funzionalità di prodotto;
- effettuare spese, cambiare piani o sottoscrivere servizi a pagamento;
- inviare email di massa agli utenti (la procedura Resend non è approvata).

### Azioni che richiedono escalation

Richiedono Enrico o, se Enrico resta irraggiungibile, un consulente tecnico
indicato da Enrico nella scheda contatti. Senza nessuno dei due il delegato
mantiene il servizio in manutenzione e aspetta:

- restore dei dati **in produzione**, cambio del progetto Supabase servito o
  modifica delle variabili Supabase/Netlify;
- modifiche DNS;
- rotazione di chiavi o secret, sospetto di compromissione di un account;
- qualunque azione distruttiva o irreversibile;
- incidente che coinvolge dati personali (possibile data breach: valutazione
  e notifica non spettano al delegato);
- riapertura quando anche una sola voce della checklist non è verificata.

## 2. Checklist di onboarding

Da eseguire dopo la scelta della persona, nell'ordine. Enrico concede gli
accessi con i propri account; il delegato attiva la propria MFA. Nessun
valore segreto va scritto in questo file o nel repository: qui si annotano
solo date, esiti e iniziali.

### Prima dell'invito (Enrico)

- [x] ruleset `main-protection` su `main` e `.github/CODEOWNERS` attivi
      (23 settembre 2026);
- [ ] secret spostati negli environment `production-backup` e
      `production-payouts`, `gh secret list` vuoto a livello di repository,
      poi dispatch di prova di backup e freshness watch riusciti;
- [ ] modello di disaster recovery scelto: **A** operativo limitato o **B**
      break-glass completo (matrice, ultima sezione);
- [ ] decisione sulla chiave `age` registrata (nessun accesso / copia
      sigillata / secondo destinatario);
- [ ] decisione Supabase registrata (*Developer* con rischio accettato,
      oppure nessun accesso);
- [ ] posto Netlify disponibile senza spese non approvate;
- [ ] scheda contatti compilata fuori dal repository (vedi sezione 6).

### Identità

- [ ] persona approvata da Enrico, con nome e data della nomina;
- [ ] account individuali della persona per GitHub, Supabase, Netlify,
      Cloudflare e Vinea, ciascuno con la sua email;
- [ ] almeno un contatto alternativo scambiato in entrambe le direzioni
      (telefono e un secondo canale);
- [ ] disponibilità concordata: finestre di reperibilità, ferie, tempi di
      risposta attesi;
- [ ] la persona ha letto mandato, matrice e Incident Card e li accetta.

### Sicurezza

- [ ] MFA attiva su GitHub, Supabase, Netlify e Cloudflare (verificata a vista
      nelle impostazioni dell'account, non dichiarata);
- [ ] **Enforce MFA** attivo sull'organizzazione Supabase;
- [ ] codici di recupero salvati dalla persona nel proprio password manager;
- [ ] password manager in uso; password dell'account Vinea unica e lunga;
- [ ] app authenticator collegata all'account Vinea da `/account/sicurezza`
      (dopo l'assegnazione del ruolo): QR inquadrato o chiave inserita a mano,
      primo codice confermato. La chiave TOTP resta solo nell'app della
      persona;
- [ ] nessuna password, token o codice condiviso con Enrico o con altri;
- [ ] dispositivo affidabile, personale, con blocco schermo e disco cifrato;
- [ ] sistema operativo e browser aggiornati.

### Accessi (Enrico concede, uno per servizio)

- [ ] GitHub: collaboratore del repository; invito accettato;
- [ ] Supabase: membro *Developer* dell'organizzazione (o nessun accesso);
- [ ] Netlify: *Developer* sul solo progetto Vinea; esito della verifica DNS
      annotato nella matrice;
- [ ] Cloudflare: membro con *Workers Platform (Read-only)*;
- [ ] B2: nessuno; application key read-only solo se decisa;
- [ ] alert: variabile di repository `BACKUP_ALERT_EXTRA_MENTIONS` = login
      GitHub del delegato; la persona imposta *Watch → Custom → Issues* e le
      notifiche email per le menzioni;
- [ ] Vinea: ruolo assegnato da Enrico:
      `insert into public.user_roles (user_id, role) values ('<uuid>', 'emergency_delegate');`
      poi `select user_id from public.user_roles where role =
      'emergency_delegate';` deve restituire **una** riga.

### Test (con la persona, senza incidenti pubblici)

- [ ] login a Vinea con la sola password: `/continuita` porta a
      `/account/sicurezza` (enrollment se è il primo accesso, codice se il
      fattore esiste); dopo il codice `/continuita` si apre. Il primo
      enrollment riuscito è anche la prova che TOTP è attivo sul progetto di
      produzione;
- [ ] un codice sbagliato viene rifiutato e `/continuita` resta chiusa;
- [ ] `/admin` risponde 404 per la persona;
- [ ] pubblicazione di un banner di prova **solo in un ambiente non
      pubblico**: branch Supabase di anteprima o stack locale con un account
      di prova, mai in produzione. In produzione si prova solo l'apertura del
      pannello senza salvare;
- [ ] lettura della procedura status page; PR di prova su un branch **senza
      merge**, chiusa subito (il deploy di anteprima è pubblico: testo neutro);
- [ ] apertura di GitHub Actions, lettura dell'ultimo run di backup e del
      freshness watch;
- [ ] riconoscimento di un allarme: lettura della issue #149 (prova del 23
      settembre 2026) e della tabella delle categorie nel runbook;
- [ ] lancio manuale del freshness watch (*Run workflow*, soglia vuota) e
      lettura dell'esito; il backup manuale si lancia solo se Enrico lo
      chiede, perché crea una copia protetta da Object Lock per 30 giorni;
- [ ] lettura guidata del runbook: freschezza, restore, riapertura;
- [ ] verifica di ciò che la persona **non** può fare: nessun accesso a
      secret e impostazioni GitHub, nessuna impostazione del progetto
      Supabase, nessuna gestione membri su Netlify e Cloudflare, `/admin`
      negato.

### Chiusura

| Voce | Valore |
| --- | --- |
| Persona nominata (nome) | |
| Data della nomina | |
| Checklist completata il | |
| Firma o conferma scritta di Enrico | |
| Firma o conferma scritta del delegato | |
| Data ultima prova (drill) | |
| Data prossima revisione | |

Dopo la chiusura aggiornare `docs/OPERATIONAL_DECISIONS_STATUS.md` (voce
Delegato → chiusa), `CHANGES.log` e il runbook. Le prove si registrano nella
tabella del drill.

## 3. Drill periodico non distruttivo

**Frequenza per la Beta:** entro 7 giorni dall'onboarding, poi **ogni tre
mesi**, dopo ogni modifica agli accessi e dopo ogni incidente reale. Durata
attesa: circa 45 minuti. Revisione completa della matrice ogni sei mesi.

Regole: nessun restore distruttivo, nessun banner pubblico in produzione,
nessun incidente pubblico, nessuna modifica a configurazioni.

1. Login del delegato a Vinea: dopo la password `/continuita` chiede il
   codice dell'app authenticator; con il codice si apre (senza salvare).
   `/admin` deve rispondere 404.
2. Login a GitHub, Supabase, Netlify e Cloudflare con MFA; per ogni servizio
   la persona indica dove vedrebbe un guasto.
3. Lettura della status page e della sua procedura; spiegare in 2 minuti come
   si pubblica un aggiornamento.
4. Scenario da tavolo: Enrico mostra un run di backup fallito o una issue
   `backup-freshness-alert` (anche storica); la persona classifica la
   categoria e dice la prima azione del runbook.
5. Lancio manuale del freshness watch e lettura dell'esito.
6. Percorso della Incident Card su uno scenario fittizio, fino al punto di
   STOP corretto.
7. Controllo delle capability extra: nessun accesso a secret, impostazioni,
   gestione membri; confronto degli accessi effettivi con la matrice; in
   Supabase `select user_id, role from public.user_roles where role in
   ('admin','emergency_delegate');` restituisce solo le persone attese.
8. Il gate CI `Supabase DB regression` deve essere verde sulla testa di
   `main` per l'ultima modifica a migrazioni: include la matrice 12h e la
   prova REST MFA.
9. GitHub: `rules/branches/main` mostra ancora ruleset e check obbligatori,
   `gh secret list` a livello di repository è vuoto, CODEOWNERS senza errori.

| Data | Partecipanti | Esito | Problemi | Prossimo drill |
| --- | --- | --- | --- | --- |
| | | | | |

## 4. Offboarding

### Revoca ordinaria

Per fine collaborazione o cambio di delegato. Enrico esegue, in quest'ordine:

1. Vinea: `delete from public.user_roles where user_id = '<uuid>' and role =
   'emergency_delegate';` poi revoca delle sessioni dell'utente da Supabase
   Auth e rimozione dei suoi fattori MFA (Authentication → utente → *Factors*,
   o `auth.admin.mfa.deleteFactor`), così un eventuale nuovo ruolo richiede
   un nuovo enrollment.
2. GitHub: rimozione del collaboratore; chiusura o riassegnazione delle PR
   aperte; nessuna deploy key o webhook della persona.
3. Supabase: rimozione dall'organizzazione; nessun access token della persona.
4. Netlify: rimozione dal team e dal progetto; nessun accesso DNS residuo.
5. Cloudflare: rimozione dall'account.
6. B2: cancellazione dell'eventuale application key del delegato.
7. Alert: rimozione del login da `BACKUP_ALERT_EXTRA_MENTIONS`.
8. Secret: se la persona ha visto un valore segreto durante un incidente,
   rotazione di quel secret (task dedicato).
9. Audit: rilettura di `incident_notice_events` per l'ultimo periodo e dei
   registri di GitHub (Actions, PR), Netlify (deploy) e Supabase (log)
   relativi alla persona.
10. **Conferma di zero accessi residui:** rilettura dell'elenco membri di ogni
    servizio e della query sui ruoli; annotare data e verifiche nella tabella
    sotto.

### Revoca urgente

In caso di perdita o furto del dispositivo, sospetto di compromissione di un
account, fine improvvisa della collaborazione o comportamento anomalo:

1. **Subito:** passi 1, 2, 3 e 4 sopra, anche prima di aver chiarito i fatti.
   La revoca si annulla facilmente, un abuso no.
2. Controllare se, nella finestra sospetta, sono cambiati banner, status page,
   variabili Netlify, deploy pubblicati, dati o impostazioni Supabase, run o
   workflow GitHub.
3. Se la persona poteva leggere secret (per esempio prima dei prerequisiti
   GitHub): ruotare service role Supabase, password del database, key B2 e
   token coinvolti.
4. Completare i passi 5-10 e trattare l'evento secondo la Incident Card
   (categoria sicurezza).
5. Informare la persona della revoca, se non è compromessa.

| Data | Motivo | Revoca eseguita da | Accessi residui verificati = 0 |
| --- | --- | --- | --- |
| | | | |

## 5. Stato della preparazione tecnica

- Capability applicativa verificata il 23 settembre 2026 con la griglia
  [`12h_emergency_delegate_matrix.sql`](../supabase/tests/12h_emergency_delegate_matrix.sql)
  su uno stack Supabase locale costruito dalle 61 migrazioni: 18/18. Il
  delegato pubblica, modifica e ritira il banner con URL della status page e
  lascia audit append-only; le 17 RPC riservate agli admin lo rifiutano con
  `42501` mentre l'admin supera il controllo; sulle altre 88 RPC e sulle 52
  tabelle o viste leggibili ha gli stessi esiti di un utente normale. Un
  controllo negativo con un controllo di ruolo volutamente generico ha fatto
  fallire la griglia. La griglia gira nel gate CI `Supabase DB regression`.
- Catalogo di produzione riletto in sola lettura lo stesso giorno: il ruolo
  compare soltanto in `public.incident_notice_set`, nessuna policy o vista lo
  cita, nessun controllo legge `user_roles` senza un ruolo letterale, zero
  utenti con il ruolo.
- Allarme backup: variabile `BACKUP_ALERT_EXTRA_MENTIONS` supportata dal
  freshness watch, non impostata.
- MFA del ruolo (23 settembre 2026): migrazione
  `20260923200000_incident_notice_delegate_aal2.sql`; griglia 12h a 21
  controlli (delegato `aal1` o senza claim rifiutato senza scritture, utente
  normale rifiutato anche in `aal2`, admin invariato); prova REST
  `12h_delegate_mfa_e2e.mjs` 13/13 con token reali di GoTrue e PostgREST
  (enrollment, QR/secret, challenge, verify, publish/edit/withdraw in `aal2`,
  rifiuto `aal1` con hint `aal2_required`), audit `3 1`, zero residui.
  Controllo prima/dopo: con il corpo precedente della funzione la griglia
  falliva il controllo 19 e la prova REST 3 casi. Percorso UI provato su stack
  locale: login, rimando a `/account/sicurezza`, enrollment con QR, banner
  pubblicato e ritirato, nuova sessione con challenge, codice errato
  rifiutato, utente normale 404.
- GitHub (23 settembre 2026): ruleset e CODEOWNERS attivi, environment creati
  e collegati ai workflow; valori dei secret ancora a livello di repository.

## 6. Scheda contatti

Non si versiona. Enrico la tiene nel proprio password manager e ne consegna
una copia al delegato al momento della nomina. Contiene: telefono ed email di
Enrico e un secondo canale, contatto del delegato, eventuale consulente
tecnico di escalation, pagine di stato dei provider (GitHub, Supabase,
Netlify, Cloudflare, Backblaze), link a Incident Card e runbook.
