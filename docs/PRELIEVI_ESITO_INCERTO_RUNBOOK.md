# Prelievi dall'esito incerto — procedura di risoluzione

VPM-FIN-001 (G-12). Per chi gestisce i pagamenti di Vinea. Nessun segreto in questo file.

## Che cosa è successo, in una riga

Un prelievo `esito_incerto` è un prelievo il cui Transfer **può essere già partito** verso il
venditore senza che il nostro stato lo sappia (timeout, risposta 5xx, risposta illeggibile,
esecutore morto a metà). Il sistema **non libera mai i centesimi da solo** e il titolare **non può
annullarlo**: lo farebbe uscire due volte.

| Stato | Significato | Annullabile dal titolare | Ritentato in automatico |
| --- | --- | --- | --- |
| `richiesto` | mai tentato | sì | sì |
| `in_corso` | un esecutore lo sta eseguendo | no | no (un solo esecutore per volta) |
| `esito_incerto` | il Transfer può esistere | **no** | solo entro 20 ore, con la stessa chiave |
| `fallito` | il fornitore ha **rifiutato** (provato) | sì | sì, salvo se riconciliato |
| `trasferito` | Transfer confermato, prenotazione consumata | no | no |
| `annullato` | prenotazione rilasciata dal titolare | — | no |

## Come ti accorgi che c'è un incerto

Il workflow schedulato «Phase 7 - auto-release payouts» (ogni 6 ore) fallisce a **ogni** giro finché
esiste anche un solo prelievo `esito_incerto`, anche dopo che è uscito dalla coda automatica. Vale
solo con `PAYOUTS_SCHEDULER_ENABLED=true`: a scheduler spento il job esce prima di ogni richiesta e
non segnala nulla, quindi **prima di accenderlo** controlla l'elenco qui sotto. Con `PAYMENTS_ENABLED`
spento l'esecutore non marca gli orfani `in_corso` (vedi più sotto) e il conteggio riguarda solo
gli `esito_incerto`:

```text
Prelievi con esito incerto da riconciliare: N
```

Il titolare vede il prelievo come «In verifica» in *Saldo Vinea*, con i centesimi ancora impegnati.

## Elenco degli incerti (sola lettura)

```sql
select w.id, w.amount_cents, w.provider, w.destination_account_id, w.tentativi,
       w.ultimo_errore, w.esito_incerto_dal,
       now() - w.esito_incerto_dal as da_quanto_tempo
from public.balance_withdrawals w
where w.stato = 'esito_incerto'
order by w.esito_incerto_dal;
```

> **NON VERIFICATO in Stripe Test Mode.** Tutto ciò che questa procedura afferma sul comportamento di
> Stripe è tratto dalla sua documentazione e non è mai stato provato contro il fornitore: che la stessa
> chiave restituisca l'esito originale (anche un 5xx, che quindi può ripresentarsi identico a ogni
> ritentativo senza mai risolversi), che le chiavi vengano rimosse non prima di 24 ore, che un
> 401/403 non passi dalla chiave. Le soglie di 20 e 24 ore sono scelte prudenziali, non garanzie.

## Che cosa fare, per età dell'incertezza

| Da quanto è incerto | Azione |
| --- | --- |
| meno di **20 ore** | Niente. Lo scheduler ritenta con la **stessa** chiave di idempotenza: Stripe, se la ricorda, restituisce l'esito vero. Se il ritentativo riesce diventa `trasferito`. **Un rifiuto non chiude l'incertezza**: un 401/403, una chiave segreta assente o un errore di validazione non passano dalla chiave e non dicono nulla sul tentativo originale. Il prelievo resta `esito_incerto` fino a un successo o alla riconciliazione. |
| fra **20 e 24 ore** | Niente. Il ritentativo è ormai vietato (la chiave può non esistere più e Stripe eseguirebbe un Transfer **nuovo**) e la verifica negativa non è ancora ammessa. |
| **24 ore o più** | Verifica su Stripe (sotto) e riconcilia. |

## Verifica su Stripe (24 ore o più)

1. Dashboard Stripe → **Transfers**, filtra per la destinazione (`destination_account_id` del
   prelievo) e per data dal giorno del tentativo.
2. Cerca un Transfer con **metadata `order_id` uguale all'id del prelievo** (il campo si chiama
   `order_id` anche per i prelievi: contiene l'id del prelievo), importo uguale a `amount_cents`,
   valuta EUR.
3. Se compaiono **due** Transfer per lo stesso prelievo: fermati, non riconciliare, escala. È una
   doppia uscita già avvenuta e non si risolve con questa procedura.

## Riconciliare: trasferimento TROVATO

La prova deve combaciare con il prelievo: il database rifiuta importo, destinazione o
identificativo che non coincidono, un id che non è `tr_…`, e un Transfer già associato ad altro.

```sql
select public.prelievo_riconcilia(
  '<id prelievo>'::uuid, 'trasferito',
  'tr_...',            -- identificativo del Transfer letto su Stripe
  <importo in centesimi>,
  'acct_...',          -- destinazione del Transfer letta su Stripe
  'Dashboard Stripe: transfer tr_... presente, importo e destinazione coincidono');
```

Esito `transferred`: prelievo `trasferito`, prenotazione consumata **una sola volta**, un solo
movimento `prelievo_eseguito`. Ripetere la chiamata risponde `duplicate` senza addebitare di nuovo.

## Riconciliare: trasferimento NON TROVATO

Ammesso **solo dopo 24 ore** dall'inizio dell'incertezza e solo con una nota di prova.

```sql
select public.prelievo_riconcilia(
  '<id prelievo>'::uuid, 'non_eseguito', null, null, null,
  'Dashboard Stripe: nessun transfer verso acct_... per questo prelievo, verificato il <data>');
```

Esito `not_executed`: il prelievo diventa `fallito` **riconciliato**. Non rientra nella coda
automatica (nessun ritentativo con la chiave vecchia). Il titolare può **annullarlo** e i centesimi
tornano spendibili, una volta sola; per riprovare chiede un prelievo nuovo, con una chiave nuova.
I centesimi restano impegnati finché il titolare non annulla.

## Se non sei sicuro

**Non riconciliare.** Il prelievo resta `esito_incerto`, i fondi restano bloccati e il job continua
a segnalarlo: è lo stato sicuro. Un blocco che dura è un costo; un Transfer pagato due volte non si
recupera in automatico (non esiste un transfer reversal nel codice).

## Titolare sospeso o rimosso

La riconciliazione non dipende dallo stato del profilo: l'operatore può chiudere l'incertezza anche
per un titolare `sospeso` o `rimosso`. Il titolare non può annullare (né prima né dopo la
verifica) se la moderazione gli impedisce l'accesso: i centesimi di un prelievo `fallito`
riconciliato restano impegnati finché la moderazione non decide, come per ogni altro fondo di quel
profilo.

## Che cosa NON fare

- Non modificare lo stato del prelievo, la prenotazione o il libro con SQL diretto.
- Non rilasciare i centesimi «a mano» perché il prelievo è vecchio.
- Non scrivere nella nota dati personali, né credenziali o chiavi.
- Non cancellare le righe `balance_withdrawals`.

## Prelievi precedenti alla correzione

La migrazione `20261115100100` ha riclassificato come `esito_incerto` ogni prelievo `fallito` con
almeno un tentativo (prima ogni errore diventava `fallito`, quindi non provava la non esecuzione).
Compaiono nell'elenco sopra: l'età dell'incertezza parte da `created_at` del prelievo, quindi uno creato
meno di 20 ore prima della migrazione può essere ancora ritentato con la vecchia chiave, uno più
vecchio no. Si trattano con la stessa procedura.

Un prelievo che prima della correzione era già `in_corso` e aveva più di un tentativo ha come
attesa di riferimento l'ultimo aggiornamento, non il primo tentativo: se ne trovi uno, trattalo come
incerto da verificare su Stripe senza fidarti della finestra di 20 ore.

Audit consigliato: i prelievi passati da `fallito` ad `annullato` PRIMA di questa correzione possono
aver generato un doppio pagamento. Controlla su Stripe i Transfer per ciascuno, con la stessa
ricerca di sopra.

## Orfani `in_corso`

Un esecutore che muore a metà lascia il prelievo `in_corso`. Dopo 15 minuti il passo di bonifica
lo marca `esito_incerto` (solo quando l'esecutore gira, cioè con `PAYMENTS_ENABLED=true`) e da lì
vale la procedura sopra. Finché non viene marcato è bloccato e non annullabile.

## Che cosa il sistema NON fa ancora

- Non legge Stripe per riconciliare da solo: la verifica è umana e la nota è la prova.
- Non crea il Payout verso la banca (G-1, lavoro separato).
- Non gestisce il caso «Transfer esistente su un prelievo annullato». Con questa correzione non
  dovrebbe poter accadere (un prelievo incerto non si annulla mai e un rifiuto non chiude
  un'incertezza aperta), ma non è dimostrabile senza Stripe: se compare, l'esecutore lo registra
  come anomalia (`prelievi_falliti`, log `ANOMALIA`) e va trattato a mano.
