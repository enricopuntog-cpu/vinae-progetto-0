# VPM-015B5A — Checkout Accessori privati e inventario transazionale

Contratto del sotto-blocco 015B5A (2 novembre 2026), costruito su
[VPM-015B2](VPM_015B2_ANNUNCI_ACCESSORI.md), [VPM-015B3](VPM_015B3_PUBBLICAZIONE_ACCESSORI.md)
e [VPM-015B4](VPM_015B4_LOGISTICA_ACCESSORI.md) (preventivo logistico congelato a uso unico).
Il blocco successivo (B5B: pagamento reale) **non** è avviato.

**Che cosa NON è.** Nessun pagamento reale, nessuna chiamata a Stripe o alle Edge Function dei
pagamenti, nessun payout, nessuna spedizione, nessuna etichetta, nessun carrello
multi-venditore o misto vino/accessori. Il «pagamento» è una funzione **privata e simulata**
che nessun ruolo client può eseguire. Nessun interruttore viene acceso dalla migrazione.

## 1. Quando una quantità è prenotata, venduta, di nuovo disponibile

| Momento | Che cosa succede | Quantità scritte |
| --- | --- | --- |
| **Prenotata** — checkout confermato | nasce un ordine `in_attesa_pagamento` con scadenza (15 minuti, parametro 5-60) | **nessuna** |
| **Venduta** — conferma del pagamento (simulato) | l'ordine diventa `pagato`; annuncio e Cantina scendono di N, una sola volta | annuncio −N, Cantina −N |
| **Di nuovo disponibile** — annullamento dell'acquirente, scadenza, annuncio non più pubblicato (oscurato, modifiche richieste, ritirato, riportato in bozza) | l'ordine esce da `in_attesa_pagamento` | **nessuna** |

La disponibilità è sempre **derivata**, mai una colonna:

```
disponibili = annuncio.quantita − Σ quantita(ordini in_attesa_pagamento con scade_at > now())
```

Per questo non esistono sottrazioni anticipate né doppie sottrazioni: finché non c'è una vendita le
quantità di annuncio e Cantina non si toccano, e la vendita le tocca in un solo punto
(`private.accessori_ordine_segna_pagato`), dopo che l'ordine è uscito da «in attesa».

**Esempio obbligatorio** (6 calici in Cantina, 4 in annuncio, 2 acquistati), come «Cantina / annuncio /
disponibili»:

```
prima                         6 / 4 / 4
prenotati 2                   6 / 4 / 2     (nessuna quantità scritta)
pagati 2 (simulato)           4 / 2 / 2     (una sola sottrazione; ripetere il pagamento non sottrae)
annullo o scadenza (invece)   6 / 4 / 4
```

Quando l'ultimo pezzo dell'annuncio è venduto l'annuncio si ritira per esaurimento (la sua
quantità resta come storia). Quando l'ultimo pezzo posseduto è venduto la riga di Cantina scende a 0
e si **archivia** (privata): una riga a 0 è ammessa solo se archiviata
(`cantina_accessori_esaurito_archiviato`).

## 2. Modello dati

- `private.accessori_ordini` — un ordine = un annuncio, un venditore, 1-120 pezzi. Nessuna chiave
  esterna verso `orders`, `listings`, `payments`, `proposals`, annuncio, accessorio o preventivo
  (l'ordine sopravvive alla loro cancellazione; solo `buyer_id`/`seller_id` → `profiles`,
  `on delete restrict`, come gli ordini del vino). Articolo, prezzi, commissione, copertura della fee
  di pagamento, logistica, classe, margine e parametri di riferimento sono **congelati** dal
  preventivo B4 e immutabili anche per un writer privilegiato (trigger). Vincoli: totale = prezzo +
  commissione + copertura + logistica; subtotale = unitario × quantità.
- Indici unici: `(buyer_id, chiave_idempotenza)`, `preventivo_id`, e una sola prenotazione aperta per
  `(buyer_id, annuncio_id)` (parziale su `in_attesa_pagamento`).
- `private.accessori_checkout_impostazioni` — `checkout_attivo` (**false**), `prenotazione_min` (15),
  `versione`. L'accensione richiede il ruolo `accessori_release` anche per i writer privilegiati;
  spegnere è di ogni admin. Il checkout è «aperto» solo se la logistica è aperta (cantina, preparazione,
  pubblicazione e logistica accese) **e** `checkout_attivo`.
- Ordini: nascono solo dal checkout (marcatore `vinae.accessori_ordine_crea`), cambiano stato solo dalle
  porte dell'ordine (marcatore `vinae.accessori_ordine_transizione`); un ordine chiuso non si riapre; non
  si cancellano (salvo la pulizia delle fixture di prova).

## 3. Porte (tutte `SECURITY DEFINER`, `search_path` vuoto, nessuna esecuzione a `service_role`)

- `accessori_disponibilita(annuncio)` — **anon + authenticated**: pezzi prenotabili di un annuncio visibile.
- `accessori_checkout_crea(preventivo, chiave)` — authenticated. **Due soli argomenti**: nessun importo,
  quantità, venditore, annuncio o costo di spedizione dal client; tutto viene dal preventivo congelato
  (B4) e dal database. Sotto lock `Cantina → annuncio` verifica visibilità, venditore ammesso, non proprio
  annuncio, account attivo, nessuna prenotazione aperta dello stesso acquirente, disponibilità; poi
  *consuma* il preventivo (uso unico) e scrive l'ordine. Idempotente: la stessa chiave o lo stesso preventivo
  restituiscono lo stesso ordine; la stessa chiave con un altro preventivo è rifiutata (`chiave_riusata`).
  Rate limit 10/minuto.
- `accessori_ordine_annulla(ordine)` — l'acquirente annulla la propria prenotazione (idempotente; un ordine
  pagato non si annulla da qui).
- `accessori_ordine_leggi(ordine)` e `accessori_ordini_elenca(ruolo)` — solo le due parti, ciascuna vede solo
  il proprio lato: l'acquirente il totale e le voci; il venditore ciò che incassa e il nome pubblico
  dell'acquirente. Mai margine, servizio, tariffa, identificativi di Cantina.
- Admin: `accessori_checkout_admin_stato`, `accessori_checkout_admin_imposta(attivo, motivo)`.
- **Privata**: `private.accessori_ordine_segna_pagato(ordine)` — pagamento simulato e applicazione della
  vendita, idempotente; nessun ruolo client può eseguirla. B5B la chiamerà da un webhook firmato.

## 4. Sicurezza e invarianti

- Quantità, importi, identità del venditore e costo logistico sono autoritativi nel database; il browser
  invia un preventivo e una chiave. Commissione degli Accessori privati: 10% (1000 bps, da
  `marketplace_margini_dominio`), invariata; `marketplace_config` e le aliquote del vino non si toccano.
- **Ordine dei lock**: accessorio di Cantina → annuncio → ordine, lo stesso di `annunci_accessori_salva`
  e della guardia B3; l'annullamento e le scadenze toccano solo righe d'ordine. Nessuna inversione nota.
- **Un solo conteggio**: ultima unità contesa, doppio click e overbooking sono provati su sessioni
  PostgreSQL separate con barriera (§6).
- **Il pagamento già avvenuto non si ferma** per moderazione o interruttori spenti: la guardia
  `annunci_accessori_guard` (B3) ha un solo ramo aggiunto, riservato al marcatore di vendita confermata,
  che permette soltanto di scendere di pezzi o ritirare l'annuncio esaurito, senza controlli di
  pubblicazione (CLAUDE.md, *Money*). Le prenotazioni **non** pagate, invece, si liberano quando l'annuncio
  smette di essere pubblicato.
- Il venditore non scende sotto i pezzi prenotati (`quantita_prenotata`).
- **Production fail-closed**: finché non esistono servizio, rete PUDO, tariffa `active` con fonte e
  `checkout_attivo`, `accessori_checkout_crea` risponde `checkout_non_attivo` o il preventivo non esiste;
  nessun ordine acquistabile e nessun pagamento. La flag server `ACCESSORI_ORDINI_ENABLED` (spenta) nasconde
  anche la UI.
- Errori senza dettagli interni (nessun nome di vincolo: la corsa su indice unico diventa
  `prenotazione_aperta`).

## 5. Frontend (`frontend-next`)

`lib/accessori-ordini/ordine.ts` (parser rigido, messaggi italiani), `services/accessori-ordini-service.ts`
(cinque RPC, nessuna tabella, nessun argomento economico), `components/vinea/ordini-accessori/*`,
pagine `/ordini-accessori` e `/ordini-accessori/[id]` (noindex, 404 se la flag è spenta o per chi non è parte
dell'ordine), e il blocco «Prenotazione» sulla scheda `/accessori/annunci/[id]` **solo** con
`ACCESSORI_ORDINI_ENABLED=true` (server). Flusso: quantità → *Prepara il riepilogo* (congela il preventivo B4)
→ riepilogo completo (prezzo, commissione, spedizione per colli, costo di pagamento, totale) → *Conferma la
prenotazione* (chiave di idempotenza per gesto: il doppio click non duplica) → ordine «Prenotato, in attesa
di pagamento», *Annulla la prenotazione*. La UI dichiara che non c'è alcun addebito. Consegna: solo punto di
ritiro (B4: il domicilio non è ordinabile).

## 6. Prove

- Griglia `supabase/tests/12zn_vpm_015b5a_checkout_accessori.sql` (**32 casi**, nel gate `Supabase DB regression`):
  stato iniziale e privilegi; fail-closed con checkout spento; accensione e rilascio; esempio 6/4/2 (prenotazione →
  vendita → annullo/scadenza); economia congelata con formula indipendente; acquisto singolo e multiplo; disponibilità
  insufficiente; retry; doppio click; ultima unità; prenotazione scaduta; pagamento che ignora moderazione e
  interruttori; quantità prenotata del venditore; ritiro e oscuramento; venditore e acquirente sospesi; preventivo
  logistico non disponibile; preventivo scaduto o cambiato; alterazioni; RLS e ruoli; forma delle risposte;
  invarianti (nessuna quantità negativa, nessun duplicato); vino invariato; limite di richieste; volatilità.
- `12zn_vpm_015b5a_concorrenza.sh` (**7 prove su sessioni reali** con barriera advisory): ultima unità contesa da due
  acquirenti, doppio click, due preventivi dello stesso acquirente, overbooking (3 pezzi, tre richieste da 2),
  pagamento contro annullamento (3 giri), pagamento contro riduzione del venditore, invarianti finali.
- Mutazioni di controllo sul database locale (ognuna rende rosso almeno un caso): disponibilità che ignora le
  prenotazioni, scadenza che non libera, doppia sottrazione dalla Cantina, rilascio all'oscuramento rimosso,
  venditore sotto il prenotato, acquirente sospeso ammesso, chiave riusata accettata, scadenza ignorata dal
  pagamento, importi mutabili, interruttore ignorato, esecuzione ad `anon`, preventivo non consumato, prenotazione
  doppia, proprio annuncio. Per la concorrenza: lock di Cantina e annuncio tolti → overbooking e tre prove rosse.
  Restano equivalenti (difesa doppia) il replay per preventivo prima del lock (c'è anche dopo) e il controllo del
  venditore ammesso (già nella visibilità dell'annuncio).
- `frontend-next`: parser, servizio con client finto, viste, contratto statico (nessun pagamento, nessun Stripe,
  cinque sole RPC senza argomenti economici, forma della migrazione). E2E Playwright
  (`e2e/accessori-prenotazione.e2e.ts`): Chromium desktop, Chromium 375 px, WebKit.

## 7. Integrazioni ancora mancanti (B5B e oltre)

1. **Pagamento reale**: Stripe Checkout/PaymentIntent per questi ordini, webhook firmato e deduplicato che chiami
   `accessori_ordine_segna_pagato`, gestione del pagamento arrivato dopo la scadenza (oggi: `prenotazione_scaduta`,
   serve il rimborso), `PAYMENTS_ENABLED`.
2. **Rimborso / reso / contestazione** di un ordine pagato (oggi `ordine_pagato`, nessun ripristino delle quantità).
3. **Liquidazione al venditore** (trasferimento separato al rilascio), payout, saldo.
4. **Spedizione**: adattatori dei corrieri, etichette, tracking, prenotazione del ritiro; scelta del punto PUDO e
   consegna a domicilio (B4: non ordinabile).
5. **Configurazione operativa e commerciale** non decisa né fornita: servizio reale, rete PUDO, tariffe per collo con
   fonte, eventuale assicurazione, accensione di `logistica_attiva`, `checkout_attivo` e `ACCESSORI_ORDINI_ENABLED`
   (`accessori_release`).
6. Notifiche all'acquirente e al venditore, fatturazione/IVA dei beni non-vino, condizioni di vendita (LEG/FIN/OPS).
7. **Riserva e pagamento (decisione per B5B, dall'audit di sicurezza)**: oggi una prenotazione scade in 15 minuti e si
   libera per moderazione; un pagamento reale arrivato dopo non sarebbe applicabile. B5B deve legare la riserva alla sessione
   di pagamento (scadenza estesa alla creazione della sessione, nessun rilascio per moderazione mentre una sessione è aperta)
   oppure prevedere il percorso «pagato ma non applicabile» con rimborso automatico (CLAUDE.md, *Money*: un pagamento
   completato non deve restare senza uscita).
8. **Cancellazione dell'account**: `buyer_id`/`seller_id` sono `on delete restrict` (come gli ordini del vino); dopo il primo
   ordine l'account non si elimina finché non esiste una procedura di anonimizzazione, da decidere prima del cutover.
9. **Accaparramento**: oltre al tetto di prenotazioni aperte per acquirente (`max_prenotazioni_aperte`, 3) restano da valutare
   un periodo di attesa dopo un annullo ripetuto dello stesso annuncio e il controllo per dispositivo, prima di accendere
   `checkout_attivo`.
10. Pulizia periodica opzionale delle prenotazioni scadute (oggi si chiudono alla lettura e al checkout; la
   disponibilità non ne dipende), UI admin dell'interruttore, riattivazione di un accessorio esaurito.
