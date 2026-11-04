# VPM-018-DB-GRID-01 — Superfici anonime: rate limit e capability (4 novembre 2026)

Chiude GAP-009 sul piano della prova. Nessuna migrazione e nessuna funzione modificata;
Production non letta né scritta. Tutte le prove girano su stack locali dedicati.

## 1. Cosa copriva già il repository

Lettura delle griglie `12r`…`12w`, tutte già nel gate `Supabase DB regression`:

| Controllo | Prima | Dove |
|---|---|---|
| Capability errata su `event_record` e completamento MV1 | **coperto** | `12r` casi 11-13 |
| Capability non trasferibile su `session_start` | **coperto** | `12r` caso 8 |
| Capability isolata tra sessioni QV2 (lettura e risposta) | **coperto** | `12t` caso 14, `12v` caso 11 |
| Evento con capability diversa | **coperto** | `12w` caso 3 |
| Helper private chiuse ai client | **coperto** | `12r` caso 33 |
| Capability errata su `finish_pre` e `finish_post` | **ASSENTE** | le griglie le chiamano solo con la capability giusta |
| **Superamento di un limite su qualunque porta anonima** | **ASSENTE** | nessuna griglia nomina `rate_limit` |

Il codice dei limiti esisteva già in tutte le porte. Mancava ogni prova che funzionasse.

## 2. Griglia aggiunta: `12zu_vpm_018_superfici_anonime.sql`

Agganciata a `12g_ci_run.sh`, con transazione chiusa da `ROLLBACK` e guard sugli utenti.

| Casi | Cosa prova |
|---|---|
| 1 | Elenco chiuso delle 7 porte anonime che scrivono, tutte con limitatore: una porta nuova fa fallire la griglia |
| 2-8 | Oltre soglia ciascuna delle 7 porte risponde 429 `rate_limit_exceeded` con il proprio scope e limite, senza scrivere |
| 9-10 | Conteggio reale senza semina: 12 passano e la 13ª è rifiutata; 120 e la 121ª |
| 11-12 | Il limite di una capability non blocca le altre; i bucket conservano solo l'impronta |
| 13-18 | Capability errata o malformata su ogni porta legata alla sessione, senza scritture |
| 19 | Una capability MV1 non apre una sessione QV2 |
| 20 | Limitatore, bucket e sessioni chiusi ad `anon` e `authenticated` |
| 21, 26 | Tetto globale per IP sul percorso reale, e montato davvero su `authenticator` |
| 22-24, 27 | **Limiti noti** (§ 3): descrivono lo stato attuale e diventano rossi quando vengono corretti |
| 25 | Un passo sotto la soglia nessuna porta rifiuta: insieme ai casi 2-8 prova il limite esatto |

Le altre funzioni eseguibili da `anon` sono `stable`, quindi di sola lettura: 21 funzioni
elencate dalla stessa interrogazione del caso 1, fuori da questa griglia.

## 3. Rischi verificati, non corretti

Misure via PostgREST con la chiave anon, sullo stack dedicato (gateway locale 55321):

| Misura | Esito |
|---|---|
| `qv2_start` dallo stesso IP, capability sempre nuova | 120 risposte 200, **primo 429 alla chiamata 121** |
| Soggetto registrato dal tetto globale | `postgrest:/rpc/beta_validation_qv2_start`, `ip:172.20.0.1` (percorso con la barra) |
| `x-forwarded-for` del client sempre diverso, 140 chiamate | 140 risposte 200, **140 soggetti distinti, nessun 429** |
| 140 chiamate che falliscono (capability errata), stesso IP | 140 risposte 401, nessun 429, **0 righe nei bucket** |

**R-MV-01 — P3, provvisorio — Le sessioni anonime del Beta Test non hanno un tetto complessivo.**
Il limite delle porte è per capability, e la capability è un UUID scelto dal client: cambiandola
il limite riparte (caso 22, con 40 sessioni; un eventuale tetto globale più alto lascerebbe
verde il caso). `beta_validation_qv2_start` assegna il primo codice libero fra V001 e V999;
`session_start` consuma codici scelti dal chiamante.

- **Impatto**: un anonimo può inquinare i dati della validazione e, esauriti i codici, impedire
  le **nuove** sessioni QV2. Chi ha già una sessione la riprende. A codici esauriti `qv2_start`
  fallisce senza consumare contatori, dopo un lock globale e una scansione dei codici. Nessun
  dato personale, denaro o dominio commerciale coinvolti (griglie `12r`).
- **Quanto è facile**: con un solo IP, circa 8 minuti a 120 richieste al minuto, meno usando
  anche `session_start` che ha un proprio tetto (calcolo dalla misura). Se `x-forwarded-for`
  fosse accettato anche in Production, il tetto per IP non frenerebbe nulla.
- **Non verificato**: Production, compresi raggiungibilità e trattamento dell'intestazione: la
  misura vale per il gateway locale. Per questo P3 è provvisorio.
- **Correzione possibile, non applicata**: serve una migrazione e una scelta di prodotto. Opzioni:
  tetto globale di nuove sessioni per ora nel database; codici di invito; chiudere le porte a
  fine campagna.

**R-RL-01 — P3 — Il tetto di 60 richieste al minuto per le RPC non scatta mai.**
`private.vinea_check_request` confronta `request.path` con `rpc/%`, ma PostgREST lo passa come
`/rpc/…`: tutte le RPC di scrittura hanno di fatto il tetto generico di 120 (caso 27 e misura
sopra). Difetto reale di poco conto, fissato come «limite noto». La correzione è una migrazione di
una riga che dimezza il tetto effettivo su tutte le scritture RPC di tutti gli utenti, quindi va
provata a parte e non in questa PR di soli test.

**x-forwarded-for (già GAP-024).** Ora è misurato sul gateway locale. Va riletto su Production
insieme a VER-PROD-01.

**Le chiamate fallite non contano (caso 24 e misura).** L'errore annulla anche i contatori, della
porta e del tetto globale, perché sono nella stessa transazione. Non scrivono nulla e una
capability a 122 bit non si indovina, ma nessun limite frena un volume di richieste invalide.

## 4. Prove

Stack dedicato `vinea_e2e`, 108 migrazioni, `ROLLBACK` per la griglia; le sessioni create dalla
sonda via PostgREST sono state cancellate a fine misura.

| Prova | Esito |
|---|---|
| Griglia sul codice attuale | **27/27** |
| Residui dopo la corsa | `rate_limit_buckets` 0, `beta_validation_sessions` 0 |
| M1 `qv2_start` senza limite | rossi casi 1, 2 |
| M2 `qv2_answer` senza limite | rossi casi 1, 4 |
| M3 `session_start` senza limite | rossi casi 1, 8, 9 |
| M4 nuova porta anonima di scrittura | rosso caso 1 |
| M5 limitatore aperto ad `anon` | rosso caso 20 |
| M6 capability ignorata in QV2 | rossi casi 13, 14, 15, 16, 18 |
| M7 tetto globale spento | rosso caso 21 |
| M8 controllo delle richieste smontato | rosso caso 26 |
| M9 soglia di `qv2_read` a 60 | rossi casi 10, 25 |
| M10 percorso del ramo RPC corretto (R-RL-01) | rosso caso 27 |

Limiti: i casi SQL usano `set local role anon` e non passano da PostgREST; il percorso reale e
`x-forwarded-for` sono provati dalla sonda, non dal gate. Il gate CI esegue la griglia sullo stack
effimero costruito dalle migrazioni del commit. Le porte non vedono le tabelle scritte direttamente:
il caso 1 guarda solo le funzioni di `public`, e la ricerca di altre vie di scrittura anonima non è
esaustiva.
