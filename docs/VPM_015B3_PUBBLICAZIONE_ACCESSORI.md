# VPM-015B3 — Annunci Accessori: pubblicazione automatica e moderazione successiva

Contratto del sotto-blocco 015B3 (22 ottobre 2026), costruito su
[VPM-015A](VPM_015A_ACCESSORI.md) (catalogo),
[VPM-015B1](VPM_015B1_CANTINA_ACCESSORI.md) (Cantina Accessori personale) e
[VPM-015B2](VPM_015B2_ANNUNCI_ACCESSORI.md) (annunci in preparazione).

**Decisione del titolare (vincolante):** gli annunci conformi si pubblicano
automaticamente, **senza approvazione manuale preventiva**; la moderazione opera
**dopo**, da segnalazioni e controlli amministrativi.

**Che cosa NON è:** la decisione riguarda il *modello*, non il *rilascio*. Questo
blocco costruisce la fondazione e la lascia **spenta**: nessuna categoria è
pubblicabile, nessun ruolo di rilascio è assegnato, gli interruttori sono falsi in
Production. E soprattutto **visibile non vuol dire acquistabile**: non esiste
checkout, ordine, prenotazione, pagamento, payout né spedizione di Accessori, né
uno stato che li renda possibili.

## 1. Stati e flusso

| Stato | Chi lo imposta | Visibile | Note |
| --- | --- | --- | --- |
| `bozza` | venditore | no | modificabile; nasce così |
| `pubblicato` | venditore (`annunci_accessori_pubblica`) o riapertura admin | **sì**, se rilascio, categoria e venditore lo consentono | l'offerta è congelata; si cambia con l'aggiornamento controllato |
| `modifiche_richieste` | amministrazione | no | il venditore corregge e ripubblica **solo cambiando davvero qualcosa** |
| `oscurato` | amministrazione (sospensione o rimozione) | no | il venditore non lo riapre in nessun modo; può solo ritirarlo |
| `ritirato` | venditore | no | terminale; libera i pezzi |

`in_revisione` (B2) **non esiste più**: la migrazione riporta in `bozza` le righe
che lo avevano (nessuna è cancellata; provato su dati reali di B2). Nessuna
approvazione manuale è nascosta: non c'è un destinatario della "revisione".

Flusso del venditore: Cantina → «Prepara annuncio» → prezzo e quantità →
dichiarazione di conformità → almeno una foto → «Salva bozza» → **«Pubblica
annuncio»**. Il database verifica i requisiti; se tutti sono soddisfatti e il
rilascio è abilitato l'annuncio diventa visibile, senza passaggi intermedi.

### Requisiti verificati dal database (nella guardia, per ogni writer)

Proprietario; account attivo; venditore ammesso (privato; Partner attivo/sospeso e
Partner revocato esclusi, come in B2); categoria **pubblicabile**; quantità
disponibile (nessuna sovra-allocazione, sotto lock dell'accessorio); prezzo valido
e calcolabile; almeno una fotografia; condizione dichiarata; dichiarazione di
conformità; assenza di termini vietati; nessun blocco amministrativo
sull'annuncio, sull'accessorio o sul venditore; nessuna ripubblicazione di un
articolo rimosso.

**Filtro tecnico minimo, dichiarato:** i controlli automatici non garantiscono che
un contenuto sia lecito. Il solo filtro testuale è un elenco fisso e verificabile
di termini che indicano gli articoli esclusi dal titolare (sciabole, armi:
`private.annuncio_accessorio_testo_vietato`); alcolici e articoli regolamentati
restano esclusi dal gate di categoria e dalla dichiarazione. **Nessun classificatore
AI** decide sul contenuto.

## 2. Gate di rilascio e categorie

- **Interruttore di pubblicazione** `private.annunci_accessori_impostazioni.pubblicazione_attiva`:
  `false` di default (il vincolo `CHECK` di B2 è tolto da una migrazione nuova).
  Si accende **solo** con il ruolo `accessori_release` tramite la porta di rilascio
  (motivo obbligatorio, registro `accessori_registro`, conferma scritta `ATTIVA`
  nell'interfaccia) **e anche** da SQL diretto serve il marcatore transazionale
  del rilascio: un UPDATE privilegiato senza rilascio è rifiutato
  (`rilascio_non_autorizzato`). Spegnere è consentito a ogni admin e **nasconde
  subito** tutti gli annunci.
- **Pubblicazione aperta** = Cantina Accessori accesa **e** preparazione accesa
  **e** pubblicazione accesa. Una qualunque spenta chiude pubblicazione e letture.
- **Categorie pubblicabili**: tabella separata
  `private.annunci_accessori_categorie_pubblicabili`. `annunci_accessori_categorie.vendibile`
  resta **soltanto** un filtro di preparazione delle bozze: **nessun backfill**,
  nessuna riga per default, nessuna categoria nuova autorizzata. Approvare richiede
  il rilascio, una categoria vendibile alla preparazione e il genitore già approvato;
  Set regalo, Pulizia e Altri accessori **non si possono approvare**. Revocare (ogni
  admin) nasconde subito gli annunci della categoria.
- Nessun ruolo `accessori_release` è assegnato da questa migrazione (provato).

## 3. Snapshot e fotografie

I dati **privati** della Cantina (`note_private`, descrizione privata, quantità
posseduta, legame col catalogo) non diventano mai pubblici. Alla pubblicazione il
database scrive uno **snapshot** (`private.annunci_accessori_snapshot`: nome,
marchio, categoria, percorsi delle foto), separato dalla Cantina e protetto da un
marcatore: nessuno lo scrive o lo cancella da solo. L'offerta (prezzo, quantità,
condizione, descrizione) vive sull'annuncio ed è **congelata** mentre è pubblicato.

- Una modifica privata della Cantina **non altera** l'annuncio pubblicato.
- Il venditore aggiorna con `annunci_accessori_salva` su un annuncio pubblicato:
  aggiornamento **controllato** (versione +1, requisiti ricontrollati, snapshot
  rifatto dalla Cantina). Il sistema non permette altri percorsi.
- Alla **riapertura** di un annuncio oscurato lo snapshot **non** si rifà: vale ciò
  che l'amministrazione ha giudicato, non le modifiche successive.
- **Nessuna duplicazione fisica**: lo snapshot custodisce i percorsi nel bucket
  privato `cantina-accessori-foto`. Il bucket resta privato; le foto si leggono con
  URL firmate concesse da policy di Storage **solo** per (a) il proprietario, (b)
  accessori esposti (B1), (c) foto di uno snapshot di un annuncio **visibile**, (d)
  un admin reale per gli annunci in moderazione. Un file citato da un annuncio non
  ritirato **non si cancella** (anche se l'utente lo toglie dalla Cantina); a
  ritiro avvenuto torna cancellabile.
- Annuncio oscurato, categoria revocata, venditore sospeso, pubblicazione spenta:
  **le nuove letture e le nuove firme cessano subito**.
- Il percorso di una foto contiene `<id proprietario>/<id accessorio>/…`: l'id del
  proprietario è già pubblico (profilo), l'id dell'accessorio non apre nulla (tabella
  senza grant). Il dettaglio pubblico non contiene altri id interni.

## 4. Moderazione successiva: componenti riusati

Nessun sistema parallelo. Riutilizzati: `reports`, `report_events`, `report_reasons`,
`audit_log` (append-only), `mod_action`, il ruolo `admin`, `private.moderazione_attore`,
`private.moderazione_pratica`, `private.audit_registra`, la coda `moderation_report_queue`,
`my_reports`, `ReportDialog`, le notifiche, e le quattro azioni sulla pratica
(`moderazione_richiesta_modifiche`, `_sospensione`, `_rimozione`, `_ripristino`), che
ora sanno agire sul nuovo bersaglio `annuncio_accessorio` (senza il ramo avrebbero
scritto un audit senza effetto).

Aggiunto, con un'estensione minima: valore `annuncio_accessorio` di `report_target_tipo`
(migrazione a parte, come per i Club), colonna `reports.target_annuncio_accessorio_id`
(`on delete set null`: la segnalazione sopravvive all'annuncio), sette motivi
standardizzati, priorità *alta* per «regolamentato», il motore
`private.moderazione_annuncio_accessorio_transizione` e la porta diretta
`annunci_accessori_admin_modera` (oscura, rimuovi, richiedi modifiche, ripristina),
più l'elenco e il dettaglio admin (snapshot, segnalazioni, storico delle decisioni).

| Azione | Da | A | Note |
| --- | --- | --- | --- |
| oscura (sospensione) | pubblicato, modifiche richieste | `oscurato` | motivazione obbligatoria, audit, notifica al venditore |
| rimuovi (rimozione) | pubblicato, modifiche richieste, oscurato(sospensione) | `oscurato` | blocca la ricreazione dell'articolo |
| richiedi modifiche | pubblicato | `modifiche_richieste` | ripubblica solo se il contenuto è cambiato (impronta) |
| ripristina | oscurato, modifiche richieste | stato precedente | snapshot giudicato; i requisiti si ricontrollano |

**Il venditore** vede stato, provvedimento e motivo (mai chi ha deciso), può ritirare
sempre, corregge un annuncio con modifiche richieste, riceve una notifica.

**Anti-elusione (proporzionata):** un annuncio rimosso o sospeso e poi ritirato non
si ricrea per lo stesso accessorio; né per un altro accessorio dello stesso
venditore con stesso nome e categoria entro 90 giorni da una rimozione; né si
ripubblica cambiando foto o descrizione (l'oscurato non si riapre da sé). Limite
noto: un venditore determinato può rinominare l'articolo; la risposta è la
sospensione dell'account (`moderazione_sospensione` su un profilo), già blocca la
pubblicazione.

## 5. Segnalazioni

Pulsante «Segnala annuncio» nel dettaglio pubblico (`ReportDialog` →
`segnalazione_annuncio_accessorio_invia`: identità da `auth.uid()`, solo annunci
visibili, non il proprio, motivo da elenco chiuso, una pratica aperta per utente,
10/ora). **Le segnalazioni anonime non sono supportate** (verificato): `reports`
richiede `reporter_id` e il rate limit è per utente; una porta anonima sarebbe una
porta di spam. Un visitatore non autenticato vede «Accedi per segnalare».
*Dipendenza LEG:* se la normativa applicabile richiedesse un canale di segnalazione
senza account, va progettato a parte (captcha/verifica, rate limit per origine);
**non si dichiara qui alcuna conformità** (DSA, e-commerce): serve la revisione LEG.

## 6. Interfaccia

- Venditore: dialogo con stato comprensibile («Pubblicato», «Vinea ha chiesto
  modifiche: …», «Oscurato da Vinea: …»), «Pubblica annuncio», «Aggiorna annuncio»,
  «Togli dalla vetrina», «Ritira annuncio»; avviso permanente *«Gli acquisti non
  sono ancora disponibili»*.
- Pubblico: `/accessori/annunci` e `/accessori/annunci/[id]` (stesso gate del
  catalogo: flag `ACCESSORI_ENABLED` + `NEXT_PUBLIC_ACCESSORI_ENABLED` spente in
  Production → 404), schede con foto 4:5 `object-contain` (oggetti verticali interi),
  prezzo indicativo per pezzo spedizione esclusa, **nessun pulsante d'acquisto**.
  La navigazione mobile (Accessori al posto di Home) non è toccata.
- Admin (`/admin/accessori`): due interruttori con conferma `ATTIVA` e motivo,
  approvazione delle categorie, elenco annunci (filtri: tutti, pubblicati,
  segnalati, oscurati, modifiche) e dettaglio con foto firmate, segnalazioni, storico
  e azioni; le pratiche si chiudono dalla coda di moderazione esistente.

## 7. Sicurezza: RLS, RPC, privilegi

Tabelle nuove in `private`, RLS attiva, **nessun grant** ai ruoli client. Funzioni
`security definer` con `search_path` vuoto. `anon` esegue **solo** le due letture
pubbliche (vuote a pubblicazione chiusa). Il resto è per `authenticated` e ricontrolla
ruolo e proprietà dentro la funzione. Nessuna `execute` a `service_role`. Le
transizioni riservate alla moderazione, i campi di esito, la versione e lo snapshot
sono protetti da marcatori transazionali e dalla guardia anche per i writer
privilegiati. Lock sempre nello stesso ordine: accessorio della Cantina, poi annuncio.

## 8. Prove

- Griglia `supabase/tests/12zk_vpm_015b3_pubblicazione_accessori.sql` (39 casi, nel gate
  `Supabase DB regression`): spento/chiuso di default; rilascio; categorie; requisiti;
  pubblicazione automatica; privato vs pubblico; quantità; snapshot e aggiornamento
  controllato; Storage; segnalazioni; oscuramento immediato; nessuna ripubblicazione
  autonoma; richiesta di modifiche; rimozione e anti-elusione; interruttori e
  visibilità condizionata; admin; escalation; separazione dall'acquisto; inventario
  delle funzioni; cancellazione account.
- `12zk_vpm_015b3_concorrenza.sh` (7 prove su sessioni PostgreSQL separate: due
  pubblicazioni dello stesso annuncio, oscuramento vs pubblicazione, aggiornamento vs
  oscuramento, doppio oscuramento, archiviazione e riduzione di quantità vs
  pubblicazione).
- `12zk_vpm_015b3_e2e.mjs` (38 controlli con token **reali** di GoTrue, **PostgREST** e
  **Storage** reali, fixture `@e2e-12zk.test` con pulizia e verifica dei residui):
  interruttori e rilascio, approvazione delle categorie, pubblicazione automatica,
  vetrina anonima a chiavi chiuse, URL firmate (anonimo sì sulle foto dello snapshot,
  no sulle altre, no sul bucket pubblico), segnalazione (anonimo escluso), oscuramento
  con effetto immediato, **limite di revoca misurato** (una URL già firmata resta
  valida fino a scadenza), nessuna riapertura da parte del venditore, ripristino
  dell'admin, spegnimento.
- Griglie aggiornate (invarianti superate, non eliminate): 12zh caso 25, 12zi caso 33,
  12zj casi 11, 12, 19, 24, 25, 26, 31, 33, 34, 38 (39/39), concorrenza 12zj.
- **Mutazioni di controllo** (stack locale): 12 regole rotte di proposito (interruttore
  ignorato, filtro `vendibile` ignorato, visibilità senza categoria, snapshot rifatto
  alla riapertura, venditore che riapre un oscurato, anti-elusione, firma Storage senza
  visibilità, accensione senza rilascio, ripubblicazione senza modifiche, offerta
  pubblicata modificabile, cambio categoria con annuncio pubblicato, vetrina senza
  venditore ammesso): ognuna rende rosso almeno un caso.
- Compatibilità dei dati: una bozza `in_revisione` creata con le migrazioni B2 diventa
  `bozza` applicando B3, con quantità e dati intatti.
- `frontend-next`: parser e servizi (client finto), contratti (`annunci-accessori-contratto`
  e `annunci-accessori-pubblicazione-contratto`: stati, RPC ammesse, nessun comando
  d'acquisto, hash delle migrazioni già distribuite, forma delle migrazioni), render
  dei componenti.

## 9. Limiti e rischi residui

- Una URL firmata già emessa resta valida fino a scadenza (900 s) anche dopo
  l'oscuramento: l'oscuramento ferma le **nuove** letture e firme.
- I file in Storage di un account cancellato non vengono rimossi (le righe cadono in
  cascata, i file no): pulizia da pianificare (come per B1). Le segnalazioni
  conservano l'etichetta ma non l'evidenza fotografica dopo la cancellazione.
- Nessuna pre-moderazione: un contenuto illecito è visibile fino alla segnalazione o
  al controllo. L'elenco di termini non è un classificatore.
- L'anti-elusione si aggira rinominando l'articolo; mitigazione: sospensione account.
- L'oscuramento di un annuncio non chiude da solo le pratiche aperte (si chiudono
  dalla coda).
- Segnalazioni anonime non supportate (vedi §5).

## 10. Dipendenze e decisioni ancora aperte

1. **Titolare**: catalogo definitivo delle categorie commerciali (quali approvare),
   assegnazione del ruolo `accessori_release`, momento dell'accensione.
2. **LEG**: obblighi di segnalazione e notice-and-action, informativa sulla
   moderazione, termini d'uso per gli annunci, trattamento dei dati di segnalanti e
   venditori, retention dei contenuti rimossi.
3. **OPS/FIN**: tariffa di spedizione per accessori, IVA e condizioni di vendita di
   beni non-vino, procedura operativa di moderazione (chi, tempi, escalation).
4. Futuri blocchi (non avviati): checkout, ordini, pagamenti, spedizioni, vendita
   Partner Accessori. Quando esisterà un acquisto, una vendita parziale dovrà ridurre
   Cantina e annuncio nella stessa transazione e sotto lo stesso lock (vedi B2 §4).

## 11. Rollback e spegnimento

Spegnere `pubblicazione_attiva` (qualunque admin, `/admin/accessori`) nasconde
subito tutti gli annunci e le foto alle nuove letture, senza toccare i dati. Le flag
`ACCESSORI_ENABLED` / `NEXT_PUBLIC_ACCESSORI_ENABLED` spente mantengono le rotte
pubbliche in 404.
