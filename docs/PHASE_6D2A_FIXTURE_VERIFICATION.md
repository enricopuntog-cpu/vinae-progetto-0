# Fase 6d-2a — verifica fixture remota

Data: 31 luglio 2026. Progetto Supabase: `pijnmcllmfgjmgsvtcej`.

## Preflight

- HEAD della PR prima delle evidenze: `e6329a5e192e8c85223b45b61d47c20998112ee4`.
- Migrazione remota presente: `20260731120340 catalog_cellar_paths`.
- File eseguito una sola volta: `supabase/tests/6d-2a_catalog_cellar_paths.sql`.
- SHA-256 verificato: `6ed78d2dfa163cdf98c73a51599d16400c40a6cabbdfb9e0b099d4d49991d951`.
- Perimetro verificato: due utenti `vinea-test-6d2a-*`, profili collegati,
  produttore `Test6D2A`, due bottiglie, un annuncio, ambiente
  `Ambiente Test 6d-2a` e dipendenze create dalle RPC della prova.
- CI #43, run `30629492177`: `success` sullo stesso HEAD.

## Griglia completa

| # | Caso | Atteso | Esito |
| --- | --- | --- | --- |
| 1 | Le otto righe seed sono curate dallo staff | valore = 8 | PASSA |
| 2 | La scheda utente conserva autore e provenienza | provenienza utente e `creato_da` owner | PASSA |
| 3 | Il proprietario legge il proprio vino utente | valore = 1 | PASSA |
| 4 | Un altro utente non legge il vino utente dalla tabella base | valore = 0 | PASSA |
| 5 | La vendita non conia una seconda `bottle_unit` privata | valore = 1 | PASSA |
| 6 | L’aggiunta pubblica non crea annunci | valore = 1 | PASSA |
| 7 | La vecchia via `listing_crea` non è eseguibile dal client | errore con `permission denied` | PASSA |
| 8 | La vendita riusa la `bottle_unit` esistente | valore = 1 | PASSA |
| 9 | Un altro utente non vende la bottiglia del proprietario | errore con `non è nella tua cantina` | PASSA |
| 10 | Il client non inserisce `bottle_units` direttamente | errore con `permission denied` | PASSA |
| 11 | L’inizializzazione atomica crea ambiente e modulo | valore = 1 | PASSA |
| 12 | Il client non inserisce ambienti senza modulo | errore con `permission denied` | PASSA |
| 13 | Il client non inserisce moduli fuori dalla RPC atomica | errore con `permission denied` | PASSA |
| 14 | Il bucket Cantina è privato | valore = 1 | PASSA |
| 15 | La vista pubblica espone la provenienza senza autore | valore = 1 | PASSA |
| 16 | `creato_da` non è leggibile da un ruolo client | errore con `permission denied` | PASSA |
| 17 | Solo la nuova RPC di vendita è eseguibile da `authenticated` | valore = 1 | PASSA |
| 18 | La pulizia finale non lascia residui fixture 6d-2a | residui = 0 | PASSA |

Output integrale restituito dal connettore per l’ultimo result set:

```json
[{"passa":18,"fallisce":0,"totale":18}]
```

Il connettore ha restituito soltanto il riepilogo finale, non il result set
precedente con le 18 righe. La tabella è trascritta dal file immutato verificato
con SHA-256; il riepilogo prova che tutte le sue 18 righe sono `PASSA`, quindi
non esiste una riga 99.

## Residui indipendenti

La query read-only successiva ha controllato utenti, profili, vini, bottiglie,
annunci, ambienti, moduli e oggetti Storage marcati 6d-2a:

```json
[
  {"categoria":"auth_users","residui":"0"},
  {"categoria":"bottle_units","residui":"0"},
  {"categoria":"cellar_environments","residui":"0"},
  {"categoria":"cellar_modules","residui":"0"},
  {"categoria":"listings","residui":"0"},
  {"categoria":"profiles","residui":"0"},
  {"categoria":"storage_objects_6d2a","residui":"0"},
  {"categoria":"totale","residui":"0"},
  {"categoria":"wines","residui":"0"}
]
```

## Smoke Storage autenticato

Lo smoke è stato tentato senza dati personali usando due account tecnici, una
PNG 1×1 generata in memoria e le sole Auth/Storage API:

- il primo tentativo è stato respinto da Auth perché il TLD `.invalid` non è
  accettato; nessun utente è stato creato;
- il secondo e ultimo tentativo con `example.com` è stato respinto dal rate
  limit Auth con HTTP 429, prima della creazione di sessioni;
- non è stato eseguito alcun upload e non è stato inserito alcun oggetto con SQL;
- il cleanup difensivo non ha trovato utenti da eliminare;
- la verifica finale riporta `utenti_storage = 0`, `profili_storage = 0` e
  `oggetti_cantina = 0` per l’intero bucket.

Per completare manualmente lo smoke dopo il reset del rate limit servono due
sessioni Auth tecniche: upload via Storage API nella cartella del proprietario,
creazione e lettura della signed URL, rifiuto della lettura con il secondo JWT,
cancellazione via Storage API e nuova verifica di zero utenti, profili e oggetti.

## Advisor finali

### Security

- Nessun errore nuovo.
- Restano i due errori preesistenti e deliberati `security_definer_view` per
  `public.public_bottle_units` e `public.public_listings`: sono le viste
  pubbliche a colonne chiuse con `security_invoker=off` previste dal modello.
- Restano sette warning preesistenti per RPC `SECURITY DEFINER` applicative.
- Sono attesi dalla 6d-2a i tre warning per `cellar_ambiente_crea`,
  `cellar_bottiglia_aggiungi` e `listing_crea_da_bottiglia`: l’accesso
  `authenticated` è intenzionale e ogni RPC ricava l’identità da `auth.uid()`.
- Resta il warning Auth preesistente `auth_leaked_password_protection`.

### Performance

- Restano sei indici preesistenti segnalati come inutilizzati:
  `listings_stato_aggiornato_da_idx`, `wines_regione_idx`, `wines_tipo_idx`,
  `wines_ricerca_trgm_idx`, `listings_seller_idx` e `wines_finestra_idx`.
- Resta l’avviso atteso della 6d-2a `multiple_permissive_policies` sulle policy
  SELECT `wines_select_curated` e `wines_select_own_user`.
- `wines_creato_da_idx`, segnalato subito dopo la migrazione, non compare più
  dopo l’esecuzione della griglia. Nessun avviso performance realmente nuovo.

Non sono state rieseguite le griglie 33/33, 11/11 o 13/13 e non sono state
applicate altre migrazioni.
