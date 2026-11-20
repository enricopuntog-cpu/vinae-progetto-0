# WI-005B — Dati personali e arricchimento delle schede vino

Data: 20 novembre 2026 · Base: `main` `a88334d` (WI-005, PR #307) · Stato: consegnato con la PR di questo ramo.

## Che cosa è

Nella Cantina l'utente può **completare le informazioni** di un vino che possiede («Completa le informazioni» sulla scheda, oppure da «Consigli dalla tua Cantina → Completa i dati»). Sono **dichiarazioni personali**: private, non certificate, mai pubblicate e **mai scritte nel catalogo condiviso**.

Percorso: Cantina → Completa i dati → Modifica → Rivedi → Conferma e salva → scheda aggiornata. Nulla viene salvato prima di «Conferma e salva».

## Che cosa si può dichiarare

| Campo | Vincolo |
|---|---|
| Abbinamenti | fino a 8, 2–60 caratteri ciascuno, uno per riga, senza duplicati (maiuscole ignorate) |
| Temperatura di servizio | intero 0–25 °C |
| Decantazione | intero 0–600 minuti |
| Calice | fino a 40 caratteri |
| Annata dichiarata **oppure** «non millesimato» | 1800–2100; i due si escludono |
| Denominazione, Regione dichiarate | fino a 120 / 80 caratteri |
| Osservazioni | fino a 1000 caratteri |

Una nota **senza alcun contenuto** equivale a «nessuna annotazione» e cancella la riga. L'eliminazione esplicita chiede una seconda conferma. Per i vini non millesimati l'annata assente **non è un errore**: si può dichiararlo e il campo risulta completato.

La **finestra di bevuta personale** non è duplicata: resta il comando esistente (`override_*` su `bottle_units`, «Personalizza finestra»).

## Dove stanno i dati

Tabella additiva `public.wine_personal_notes` (migration `20261120120000_wi_005b_wine_personal_notes.sql`), chiave `(owner_id, wine_id)`: una riga per proprietario e per vino. Il vino è quello condiviso `public.wines`, **non modificato**.

- RLS: `SELECT` solo delle proprie righe (`owner_id = auth.uid()`); `anon` nessun privilegio.
- **Nessun privilegio di scrittura al client.** Le scritture passano da due funzioni `SECURITY DEFINER` (`search_path` vuoto, `auth.uid()` obbligatorio, 42501 senza sessione):
  - `cellar_nota_vino_salva(...)`: richiede che il chiamante possieda una bottiglia non eliminata di quel vino; normalizza e valida; upsert.
  - `cellar_nota_vino_elimina(p_wine_slug)`: cancella solo la riga del chiamante; idempotente.
- Nessuna vista, RPC di lettura o Edge Function legge la tabella: `public_*`, `my_*`, `moderation_*` e l'elenco chiuso del Sommelier non cambiano.

## Provenienza e affidabilità

Ogni valore della tabella è per definizione `dichiarato` / `dichiarato_utente`. La scheda WI-003 lo mostra in un blocco a parte, «Le tue dichiarazioni · private», con l'etichetta «Dichiarato da te», **distinto** dai dati condivisi (`identita` ed `enologia` restano quelli del database). Se una dichiarazione contraddice il catalogo, la revisione prima del salvataggio e la scheda mostrano entrambi i valori («Il database non cambia…»): nessuno dei due viene dichiarato corretto.

Le dichiarazioni **non** diventano `fonte_documentata`. Non esiste (né è stato creato) un processo di proposta di correzione del catalogo: una correzione condivisa sarebbe un'azione esplicita e separata, con verifica, oggi non disponibile. L'interfaccia non offre azioni non implementate.

## Integrazione con WI-003 e WI-005

- `costruisciIntelligenzaVino` accetta `personale` e produce `IntelligenzaVino.personale` (dichiarazioni, campi `completati`, conflitti) più `qualita.mancantiPersonali`. `qualita.mancanti` resta il quadro dei dati **condivisi**. La scheda riassume «N completati da te».
- Cena: un abbinamento dichiarato corrisponde a un piatto cercato in testo libero; ordine **registrato → dichiarato → ripiego**; mai «registrato» e mai usato come categoria. Etichetta «Abbinamento dichiarato da te» e limite «non verificato, visibile solo a te».
- «Completa i dati»: i campi completati dall'utente (annata o non millesimato, regione, denominazione, abbinamenti) non sono più elencati come mancanti; resta il comando esistente per la finestra. «Cosa apro stasera» non dipende dalle note.
- **«Vai alla bottiglia»** ora mostra «Tutte» (le schede sono un filtro controllato dalla pagina) e porta alla scheda anche con un altro filtro attivo; se non riesce lo dice.

## Sommelier AI e provider esterni

Le dichiarazioni **non** passano al Sommelier: `costruisciContestoSommelier` legge solo `identita`/`enologia` (test: nessuna stringa personale nel contesto, nemmeno con il consenso alla Cantina), e `ai-sommelier` non legge `wine_personal_notes`. Un eventuale uso futuro richiederebbe consenso e campi espliciti e un task a parte. Nessuna chiamata AI, nessun provider, nessun costo.

## Prove

| Livello | Esito |
|---|---|
| Unitari (puri) | validazione e confronto col catalogo; WI-003 con note; consigli con note; servizio con client finto (nessuna scrittura diretta) |
| DOM (simulato) | editor (modifica, conferma, errori, conflitti, eliminazione), scheda, consigli e navigazione |
| SQL (`supabase/tests/wi005b_note_vino_isolamento.sql`) | 32 casi: RLS, grant, privilegi delle funzioni, due utenti sullo stesso vino, scritture dirette negate, validazioni, catalogo intatto |
| API (`wi005b_note_vino_postgrest.sh`) | PostgREST e Auth reali, due utenti, token veri: isolamento, nuovo accesso, scritture dirette 401/403, catalogo invariato |
| Browser (`e2e/note-personali-cantina.e2e.ts`) | percorso completo autenticato su dati reali dello stack isolato; nessuna chiamata a Edge Function |

## Limiti

- Le note sono **per vino** (non per formato né per bottiglia): lo stesso vino in due formati condivide le annotazioni.
- Nessuna condivisione e nessuna proposta di correzione del catalogo.
- Gli abbinamenti dichiarati si cercano solo per testo libero, non per categoria.
- Annata, regione e denominazione dichiarate **non** modificano consigli o finestre: completano soltanto il quadro «dati mancanti» e la scheda dell'utente.
- Il JWT resta valido fino alla scadenza anche dopo l'uscita (comportamento di Supabase Auth): la prova API verifica persistenza e separazione, non la revoca del token.

## Preparazione al futuro WI-006 (catalogo)

`wine_personal_notes` è già agganciata a `wines.id`; con il catalogo canonico (WI-001C B) il collegamento può spostarsi o affiancarsi a `catalog.wines` senza toccare le dichiarazioni. Il blocco `IntelligenzaVino.personale` e il confronto `confrontaConCatalogo` sono il punto in cui una futura fonte documentata renderebbe visibile il conflitto con un dato verificato; una proposta di correzione verso il catalogo andrà progettata lì, con verifica umana.
