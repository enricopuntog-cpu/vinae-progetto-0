# VPM-018-DB-GRID-02 — Controllo globale delle funzioni SECURITY DEFINER (4 novembre 2026)

Chiude GAP-010 sul piano della prova. **Nessuna migrazione, nessuna funzione modificata, Production non toccata.** Stack dedicato
`vinea_e2e`, 108 migrazioni. La griglia ha trovato un difetto, R-DB-01, che resta aperto: correggerlo richiede una migrazione, e un merge la
applica a Production.

## 1. Cosa mancava

I controlli su `prosecdef` e `proconfig` erano sparsi nelle griglie di dominio (10b, 12m, 12o, 12p, 12s…12y): ognuna guarda le proprie funzioni,
nessuna ne vede una nuova di un altro dominio. Con 490 funzioni, una dimenticanza non si notava.

## 2. La griglia `12zv`

`supabase/tests/12zv_vpm_018_definer_globale.sql`, nel gate `Supabase DB regression`, tutto in `ROLLBACK`. Esito: **18/18**. Vale solo per lo
stack effimero: crea funzioni di prova e rifiuta un database con utenti reali.

| Caso | Controllo |
|---|---|
| 1 | Perimetro non vuoto: almeno 400 funzioni esaminate (490) |
| 2 | Ogni funzione ha un `search_path` fissato |
| 3 | `search_path` non vuoto solo per `handle_new_user`, `club_crea`, `rls_auto_enable`: gli altri 487 sono `""` |
| 4 | `anon` e `authenticated` non creano oggetti in `public` e `private`: è ciò che rende sicuro il caso 3 |
| 5 | Nessuna funzione di `public` eseguibile da `PUBLIC` |
| 6 | LIMITE NOTO R-DB-01: in `private` esattamente le 7 funzioni sotto |
| 7, 8, 9 | Elenchi chiusi: `private` per `anon` (11) e `authenticated` (24), `public` per `anon` (28). Una porta nuova va dichiarata |
| 14 | Le oltre 250 porte di `public` per `authenticated` non hanno un elenco: è chiuso solo l'elenco delle 12 con un parametro che indica un utente |
| 15 | Elenco chiuso delle 35 viste con i privilegi del proprietario (GAP-024), allineato a `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md` |
| 10-13, 16, 17 | Controlli negativi: funzione senza `search_path`, con `search_path` largo, con `EXECUTE` a `PUBLIC`, porta nuova per `anon`, funzione di confronto, ACL NULL in `private`. Tutti rilevati |
| 18 | Numero dei casi fissato: togliere un caso fa fallire il gate |

Il perimetro esclude le funzioni delle estensioni. Le funzioni `SECURITY INVOKER` non sono controllate: girano con i privilegi del chiamante.

## 3. R-DB-01 (P3): 7 funzioni di `private` eseguibili da chiunque

`private` concede `USAGE` ad `anon` e `authenticated`, necessario alle policy di Storage e a `vinea_check_request`. Le funzioni create senza una
revoca hanno il default di PostgreSQL, `EXECUTE` a `PUBLIC`:

| Funzione | Tipo | Effetto se chiamata |
|---|---|---|
| `private.sommelier_contesto_leggi(uuid,text,integer)` | Definer, proprietario e sessione come parametri | **Legge la chat AI di un altro**, se se ne conoscono proprietario e `session_id`, generato dal client e non elencato da alcuna funzione |
| `private.sommelier_scambio_registra(uuid,text,text,text)` | Definer, proprietario come parametro | **Scrive nella chat AI di un altro**: basta il proprietario per una conversazione nuova, e salta i controlli di `ai-gate` |
| `private.seller_enabled_sync()`, `orders_tracking_sync()`, `disputes_invariante()`, `club_post_owner_only_guard()`, `club_risposta_owner_only_guard()` | Funzioni di trigger | Non invocabili direttamente |

**Sfruttabile oggi? No, per quanto verificato.** Con il ruolo `anon` in SQL diretto la chiamata riesce (righe 0, provato), ma un client non ha SQL
diretto: PostgREST espone solo `public,graphql_public` (`PGRST_DB_SCHEMAS` dello stack, `config.toml`). La protezione dipende quindi da quell'unica
impostazione. Se `private` venisse esposto, le prime due diventerebbero un accesso anonimo a dati privati. È una difesa mancante, contraria
all'invariante di `CLAUDE.md` sui diritti larghi ad `anon`, non una vulnerabilità sfruttata. In Production gli schemi esposti risultavano così
l'11 ottobre 2026 (`private` → 406, `CHANGES.log`); da rileggere con VER-PROD-01.

**Correzione proposta, non applicata.** Migrazione di una sola istruzione, provata a secco in `ROLLBACK` sullo stack dedicato:

```sql
revoke execute on function
  private.seller_enabled_sync(), private.orders_tracking_sync(), private.disputes_invariante(),
  private.club_post_owner_only_guard(), private.club_risposta_owner_only_guard(),
  private.sommelier_contesto_leggi(uuid,text,integer), private.sommelier_scambio_registra(uuid,text,text,text)
from public, anon, authenticated;
```

Esito a secco: `anon` riceve 42501 sulla chiamata, un aggiornamento come `service_role` non dà errori di privilegi su `orders` (PostgreSQL controlla
`EXECUTE` del trigger alla creazione; le altre tre tabelle non sono state provate). Il percorso `ai-sommelier` non dipende da `PUBLIC`: le porte `public`
concesse a `service_role` sono `SECURITY DEFINER` e chiamano la funzione privata come proprietario, quindi non serve alcun `grant`. **La griglia 10b e
`ai-sommelier` non girano nel gate DB**: all'applicazione la 10b va eseguita a mano sullo stack locale, oppure agganciata a `12g_ci_run.sh` nella stessa PR.
Insieme alla migrazione vanno aggiornati i casi 6, 7 e 8 di `12zv`.

**Decisione del titolare**: autorizzare la migrazione, che il merge applica a Production. Consigliata: rischio basso, nessun cambiamento per i client.

## 4. Limiti

- Provato sullo stack costruito dai file. Corpi e privilegi in Production non sono letti. La griglia **non** si esegue lì: VER-PROD-01 deve usare
  letture dedicate (`docs/VPM_018_VER_PROD_01.md` § 2).
- Una porta di `public` per `authenticated` con un parametro di nome diverso da quelli previsti non è fermata dal caso 14: è un filtro, non una prova.
- Gli elenchi chiusi dicono chi può eseguire, non se la funzione controlla bene chiamante e stato: resta compito delle griglie di dominio.
- `search_path = public` su `handle_new_user` e `club_crea` è sicuro finché vale il caso 4; non è stato cambiato.
