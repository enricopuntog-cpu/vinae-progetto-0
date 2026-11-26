# WI-011 / WI-012 — Living Wine Catalog

Il catalogo non è più solo il LWIN importato: riceve proposte dalle attività del sito, gestisce vini che LWIN non ha,
conserva provenienza e storico e si amministra dal sito. **Non è un secondo catalogo**: si estende `catalog.*`.
Il Company Brain (WI-013) è in [`../COMPANY_BRAIN.md`](../COMPANY_BRAIN.md).

Tutto nasce **spento**: proiezione pubblica, proposte degli utenti, acquisizione dagli annunci, chiusura automatica.
La regola di promozione resta `draft`; nessun vino è stato promosso.

## 1. Identità

| Cosa | Dove | Note |
|---|---|---|
| Identità stabile | `catalog.wines.id` (UUID) | vale anche senza LWIN; non viene mai sostituita |
| Vino base | `catalog.wines` | `origin = promotion` (dalla fonte) o `manual` (nativo Vinea) |
| Annata | `catalog.wine_vintages` | nasce solo se dichiarata (anno, oppure «non millesimato» esplicito); mai fittizia |
| Formato | `catalog.wine_formats` | solo se dichiarato e con un'annata |
| Bottiglia fisica, proprietario, annuncio | `public.bottle_units`, `public.listings` | invariati, mai copiati nel catalogo |
| Attributi | `catalog.attribute_claims` | proposti → accettati/rifiutati; fonte `VINEA-CURATORE` per il curatore |
| Collegamento app ↔ catalogo | `catalog.wine_links` | proposto, poi approvato: due decisioni |

**Codice della scheda** (client, ricerca, Cantina, Sommelier): il LWIN-7 se c'è, altrimenti l'UUID. La route resta
`/vino-catalogo/{codice}`; i link per LWIN-7 continuano a funzionare. Nessun codice LWIN è inventato.

**Visibilità di un nativo:** servono insieme la proiezione pubblica accesa **e** la pubblicazione del curatore
(`native_published_at`). La ricerca non richiede annunci in vendita.

**LWIN arrivato dopo:** `catalog.assign_official_lwin` scrive il codice sulla **stessa** riga, solo se il record di
fonte è `Live`, autorizzato e porta quel codice e nessun altro vino lo ha. `wines_guard` ammette solo il passaggio
assente → ufficiale, una volta, anche per il proprietario del database. UUID, annate, collegamenti, scelte in Cantina e
storico restano. La promozione considera quel record già canonico (nessun doppione). Se la fonte viene revocata, il
codice non si mostra più ma la scheda nativa resta.

## 2. Acquisizione dal sito

| Origine | Come entra | Interruttore (`catalog.intake_settings`) |
|---|---|---|
| Bottiglia in Cantina | «Proponi al catalogo Vinea», consenso esplicito per quella richiesta | `user_proposals_enabled` |
| Correzione | stesso modulo con un campo modificato (origine `correzione`) | idem |
| Inserimento manuale / OCR (WI-015) | nell'ultimo passo del wizard, per un vino nuovo in Cantina: casella di consenso (mai preselezionata); origine `ocr` solo per dati **confermati** dall'etichetta; la bozza e l'OCR non confermato non inviano nulla; invio dopo la creazione, che non dipende dall'esito; ripetuto solo per errori di rete (massimo 3), poi si può rimandare dalla Cantina | idem |
| Annuncio Marketplace | acquisizione **asincrona** dagli annunci già pubblici, dall'admin o dal lavoro `proposte_dagli_annunci` dello scheduler comune (spento); nessun trigger sul flusso di pubblicazione. La partecipazione è il checkpoint; un annuncio che fallisce si ritenta al massimo `harvest_max_attempts` volte (`catalog.intake_failures`) | `listing_harvest_enabled` |
| Curatore / produttore | pannello admin. Un accesso diretto per produttori e partner **non esiste** | — |

- Elenco **chiuso** di campi (produttore, nome, paese, regione, denominazione, tipologia, annata, non millesimato,
  formato, LWIN dichiarato). Note, prezzi, foto, indirizzi, descrizioni non hanno un posto; testi con indirizzi di posta,
  collegamenti o marcatori sono rifiutati.
- Dato **dichiarato**, mai «verificato»: `dichiarato_utente`, `ocr_confermato_utente`, `annuncio_pubblico`.
- Idempotenza: una proposta per identità dichiarata (`identity_hash`), un invio per utente e origine, un evento di
  sistema per `source_ref`; blocco consultivo sulla stessa identità (provato con sei sessioni simultanee).
- Consenso revocabile finché nessuno ha deciso (`catalogo_proposta_ritira`); cancellato l'account, cadono i suoi invii.
  L'admin vede i dati del vino, non chi li ha mandati. Limite per utente: `user_daily_limit` (10 al giorno).
- Corrispondenze: `autorevole` **solo** con un collegamento già approvato; LWIN dichiarato o nome identico =
  `probabile`; più identità = `ambiguo`; altrimenti `sconosciuto` (con eventuali nomi simili come suggerimento).
  Si segnala anche il record LWIN non ancora canonico con la stessa chiave. **Nessuna fusione e nessun collegamento dal
  solo nome o dalla somiglianza.**

## 3. Revisione a livelli

Sempre automatico (non modifica il catalogo): normalizzazione, controllo dei formati, deduplicazione degli eventi,
rilevazione dei campi mancanti, ricerca delle identità.

Una sola regola automatica che chiude una proposta, **spenta** (`auto_close_known_enabled`): corrispondenza autorevole,
stessa annata, nessun formato o dato nuovo, non una correzione. Registra l'evento `regola:auto_close_known` e non crea
nulla.

Sempre umano: nuove identità, ambiguità, collegamenti, attributi, duplicati, pubblicazione. Creare un vino nativo con
la stessa chiave di un vino canonico o di un record LWIN richiede una conferma esplicita e motivata. Nessun potere
all'AI.

## 4. Gestione dal sito (`/admin/catalogo`)

Stesso accesso del sito e ruolo reale `admin`, verificato da ogni porta (`private.catalog_admin_richiedi`). Nessun
privilegio nuovo sulle tabelle. Liste paginate sul server (≤ 50 righe; il conteggio si ferma a 1.000). Funzioni:
panoramica, ricerca, scheda con storico, inserimento manuale, proposte con confronto, annate e formati, attributi
(valore attuale contro proposto), collegamenti, possibili duplicati, pubblicazione, associazione LWIN, ricerca nella
fonte, fonti e importazioni, conflitti.

**Non sono sul web, di proposito:** fusioni e annullamento, ritiro definitivo, regola e interruttori di promozione,
proiezione pubblica, interruttori di acquisizione, budget AI.

## 5. Attivazione (decisioni del founder, SQL dal proprietario)

Ogni riga è indipendente e reversibile con lo stesso comando e `false`.

```sql
-- proposte dagli utenti (compare il comando in Cantina)
update catalog.intake_settings set user_proposals_enabled = true, updated_at = now();
-- acquisizione dagli annunci pubblici (il pulsante del pannello inizia a leggere)
update catalog.intake_settings set listing_harvest_enabled = true, updated_at = now();
```

La proiezione pubblica (`catalog.public_projection_settings`) resta la decisione separata del runbook di promozione:
accenderla rende ricercabili i nativi **pubblicati** e i vini promossi. Prima di accenderla vale quanto scritto in
`PROMOZIONE_CANONICA_RUNBOOK.md` §6.

## 6. Aggiornamento periodico LWIN

**Distribuzione ufficiale** (pagine Liv-ex rilette il 26 novembre 2026): il database si scarica gratuitamente da
`liv-ex.com/lwin` con licenza CC BY 4.0. Non sono pubblicate una cadenza né un numero di versione; è citata una
sincronizzazione automatica senza API né condizioni pubbliche. Quindi: **il file lo scarica il founder**, nessuno
scraping o download automatico, versione identificata da `sha256`. Una sincronizzazione automatica richiederebbe un
accordo con Liv-ex.

Si usa **solo il runner esistente** (`tools/wine-catalog/lwin-load.mjs`); nessun nuovo importatore.

1. Registrare il file: nome, data, `sha256` (`certutil -hashfile <file> SHA256`), origine.
2. Manifest: `IMPORT_MANIFEST.json` descrive il file originale; per un file nuovo si passa `--expected-sha256` e
   `--expected-rows` e si aggiorna il manifest in una PR (il file non si committa mai).
3. **Dry-run** (`--dry-run`): nessuna scrittura; delta di nuovi, aggiornati, invariati, accorpati (nuovi/aggiornati),
   spariti dal file, conflitti. Delta inatteso = stop.
4. Import secondo `CLOUD_IMPORT_RUNBOOK.md` (decisione e finestra del founder, gate disco). Storico, `Combined` e
   `Deleted` sono conservati (`source_record_events`); lo stesso file non si rielabora; un record sparito è solo
   segnalato. L'import non tocca `catalog.wines` nativi, attributi, proposte o collegamenti.
5. `tools/wine-catalog/aggiornamento/delta_canonico.sql` (sola lettura): canonici il cui record non è più `Live`,
   nativi che la nuova versione conosce, contributi Vinea, impronta e digest.
6. Conflitti con i nativi: **prima** di promuovere, associare il LWIN (stesso UUID) o aprire un possibile duplicato.
7. Promozione delle sole differenze: il motore promuove i soli record `Live` non ancora canonici, con la procedura a
   lotti WI-009. Se impronta o digest differiscono da quelli approvati, o la regola deve cambiare: nuova versione della
   regola, nuova simulazione, nuova approvazione.

Limite noto: un vino promosso il cui record diventa `Deleted` o `Combined` resta canonico finché il curatore non
interviene (punto 5). Non c'è rimozione automatica, di proposito.

Nessuna nuova importazione in Production è stata eseguita con WI-011.

## 7. Prove

| Prova | Dove |
|---|---|
| Ciclo di vita, privacy, proprietà, separazione utenti, porte non autorizzate, duplicati, conflitti, fonte revocata, retry, interruttori spenti | `supabase/tests/wi011_ciclo_vita_catalogo.sql` |
| Sei eventi simultanei, evento ripetuto in parallelo, due decisioni concorrenti | `supabase/tests/wi011_concorrenza.sh` |
| Superficie definer del catalogo (19 funzioni, 17 porte con attore ed evento) | `12zs`, `12zy` |
| Consumer con identità senza LWIN, consenso in Cantina, porte del pannello | test `frontend-next` |

**Non provato:** il percorso nel browser (pannello admin e proposta) con login reale; prestazioni della ricerca e
dell'elenco admin su un catalogo popolato (in Production è vuoto); l'indice di corrispondenza sui 212.894 record si
misura solo dopo la distribuzione.

## 8. Price Intelligence (WI-014, sole fondamenta) e Authenticity

**Prezzi.** `frontend-next/src/lib/prezzi/valutazione.ts`: modulo puro, **non collegato a nessuna pagina**. Distingue
prezzo `richiesto` e `realizzato`; stima solo da almeno 5 transazioni concluse con stesso vino, annata, formato e
valuta negli ultimi 24 mesi (mediana, quartili, numero, periodo, fonti, incertezza); altrimenti «dati insufficienti».
Niente conversioni o correzioni inventate; l'osservazione non ha campi per acquirente o venditore. Il riferimento di
Cantina D3-A (mediana dei prezzi **richiesti**, almeno 3 annunci) resta invariato e distinto. **Manca** la porta che
estrae le transazioni concluse dagli ordini: richiede una migration, una decisione sul trattamento dei dati degli
ordini e, per avere risultati, transazioni reali. Nessuna API o dataset acquistato.

**Authenticity: non costruita.** I livelli da tenere separati (identificazione del vino, qualità della foto, anomalie
visive, provenienza, verifica documentale, valutazione di un esperto, certificazione) richiedono prima: consenso e
diritti sulle immagini per questa finalità, una procedura di verifica con responsabilità umana e una decisione legale
sul linguaggio ammesso. L'AI potrà solo segnalare anomalie; nessuna bottiglia dichiarata autentica in automatico.
Nessuna tabella vuota è stata creata.

## 9. Rilascio e delta per l'audit indipendente

Rilasciato il 26 novembre 2026 con la PR #323 (`ca719f1`), migration `20261128100000`–`20261128130000`. Letture di
Production dopo il merge: ledger 136; impronta `64e038526a78f44070a54498fd0ff607`, digest invariato; regola `draft`;
promozione, proiezione, proposte, acquisizione e chiusura automatica spente; 0 agenti; Sentinel non pianificato;
0 violazioni di superficie; hash di `public.wines`, `bottle_units` e `listings` identici a prima; indice dei record di
fonte usato (7,5 ms contro 14.153 ms della scansione), +9 MB. Una esecuzione di Sentinel a scopo di verifica: 11
controlli, 0 non eseguiti, 0 problemi.

Da rivalidare, oltre a F-01–F-08 di WI-009:

1. `catalog.wines_guard` (unico passaggio ammesso sul LWIN) e i vincoli `wines_manual_origin`,
   `wines_native_publication`;
2. `public.vini_canonici_cerca`: visibilità dei nativi, identificativo per UUID, LWIN nascosto a fonte revocata;
3. `catalog.contribution_identity` / `contribution_register` / `harvest_listings`: privacy, consenso, deduplicazione;
4. le 11 porte `catalogo_admin_*` e le 6 `azienda_admin_*` (`SECURITY DEFINER`, ruolo verificato in ciascuna);
5. schema `brain`: privilegi, `brain_worker`, lease; limite dell'identità dell'agente;
6. `ai-sommelier`: interruttore alimentato solo dagli errori letti dal fornitore (corretto in #321) e codice UUID.

## 10. WI-015 — correzioni dell'audit indipendente (migration `20261129100000`)

- **A-01 (vini nativi e promozione).** `catalog.add_manual_wine` prende il lock del motore in modo condiviso e senza
  attesa: con un lotto aperto il nativo non nasce (`55P03`) e, mentre nasce, il lotto non parte. `02` e `03` (sotto
  lock) si fermano se `catalog.lwin_native_conflicts(1)` ha righe; `00` riporta `nativi` e `conflitti_nativi`. Nessuna
  fusione automatica: il curatore associa il LWIN, ritira il nativo oppure dichiara l'omonimia
  (`catalogo_admin_distingui_lwin`, motivo obbligatorio, riga in `catalog.native_lwin_distinct` ed evento). La funzione
  non è nell'impronta, che **resta `64e038526a78f44070a54498fd0ff607`**.
- **B-01.** Ritiro, decisione, invio e cancellazione dell'account usano lo stesso ordine di lock (prima la proposta);
  un trigger sulle partecipazioni mantiene contatore e stato. Una proposta decisa non torna ritirata.
- **B-02.** Un invio non valido risponde `non_valida` (un errore annullerebbe anche il consumo) e conta nella quota.
- **B-03.** Il LWIN assegnato a un nativo si trova per codice e si mostra solo se la fonte è autorizzata e il record è
  ancora Live.
- **B-04.** Predisposta e spenta: `intake_settings.user_link_retention_days` (NULL = nessuna azione) e
  `catalog.minimize_decided_submissions` (solo proprietario, nessuno scheduler). Il periodo lo sceglie il founder.

## 11. WI-015B — acquisizione, lavoro del curatore e aggiornamenti dal pannello (migration `20261129110000`)

- **Dalla proposta al curatore:** il lavoro `lavoro_catalogo` crea un task per ogni proposta aperta (una volta) e chiude
  quelli superati; il Catalog Manager allega l'evidenza e propone; il Data Quality segnala i problemi (vedi
  `docs/COMPANY_BRAIN.md` §3). Nessuna decisione automatica.
- **Aggiornamento LWIN dal pannello** (`/admin/catalogo` → Fonti e import, porta `catalogo_admin_aggiornamento`):
  ultima importazione e hash; schede il cui record è Combined, Deleted o tolto dal file (con la destinazione);
  attributi diversi nella nuova versione (proposte: si accettano con le rivendicazioni, senza sovrascrivere i
  contributi Vinea); conflitti con i nativi e omonimie dichiarate. Nulla viene cancellato o aggiornato in automatico.
  Scaricare il file, il dry-run, l'import e la promozione incrementale restano del runner amministrativo con le sue
  guardie (§6); nessuna credenziale passa dal browser. La procedura non è stata provata su una versione LWIN nuova:
  il file lo fornisce il founder.
- **Prezzi (WI-014):** predisposto il contratto di acquisizione `lib/prezzi/acquisizione.ts`, spento e non collegato a
  nessun dominio: campi chiusi (una riga con dati in più è scartata), fonte autorizzata e con finalità dichiarata.
