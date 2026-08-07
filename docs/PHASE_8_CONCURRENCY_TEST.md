# Fase 8 - prove concorrenti PostgreSQL

## Esecuzione verificata - PR #27

Eseguite il 7 agosto 2026 sulla Supabase Preview isolata
`jggjaqcdbcbxdxhnggio` della draft PR #27, con due chiamate SQL indipendenti
avviate nello stesso intervallo. Produzione non è stata usata.

| Caso | Esito | Evidenza |
| --- | --- | --- |
| C1 - doppia apertura | PASSA | entrambe le sessioni hanno restituito lo stesso UUID; 1 conversazione e 2 partecipanti |
| C2 - stessa chiave e stesso payload | PASSA | stesso `message.id`; 1 messaggio, 1 notifica e un solo token consumato in entrambi i bucket |
| C3 - stessa chiave e payload diverso | PASSA | un inserimento canonico; l'altra sessione ha restituito SQLSTATE `22023`; 1 notifica |
| C4 - cursore ultimo messaggio | PASSA | `last_message_id` e `last_message_at` coincidono con il massimo di `(created_at, id)` |
| C5 - evento sistema duplicato | PASSA | stesso `message.id`; 1 messaggio sistema e 1 notifica |

Il cleanup finale ha restituito zero residui in tutte le nove classi controllate:
`auth.users`, `profiles`, `conversations`, `messages`, `notifications`,
`listings`, `bottle_units`, `wines` e `private.rate_limit_buckets`.

Queste prove sono separate dalla griglia sequenziale. Richiedono un database
PostgreSQL ricostruito dalle migrazioni oppure una Preview isolata esplicitamente
autorizzata, le fixture di
`supabase/tests/8_messaging_notifications.sql` mantenute vive per la durata
della prova e due connessioni indipendenti. Non vanno eseguite su produzione
senza autorizzazione fixture esplicita.

Ogni sessione deve impersonare un partecipante con la stessa procedura
`request.jwt.claims` usata dalla griglia. Le due chiamate partono nello stesso
intervallo dopo un `pg_advisory_lock` di barriera controllato dalla sessione di
coordinamento.

## C1 - doppia apertura

Sessione A e sessione B chiamano contemporaneamente:

```sql
select public.conversation_open(:listing_id, null);
```

Atteso:

- entrambe restituiscono lo stesso UUID;
- esiste una sola riga per `(listing_id, participant_low, participant_high)`;
- esistono esattamente due partecipanti.

La serializzazione e affidata a `pg_advisory_xact_lock` sulla chiave stabile
annuncio-coppia e al vincolo UNIQUE come difesa finale.

## C2 - doppio invio con la stessa chiave

Le due sessioni chiamano contemporaneamente:

```sql
select *
from public.message_send(:conversation_id, 'retry concorrente', :same_uuid);
```

Atteso:

- stesso `message.id` in entrambe le risposte;
- una sola riga messaggio per la chiave;
- una sola notifica per il destinatario;
- il retry non consuma un secondo rate-limit token.

## C3 - stessa chiave, payload diverso

Sessione A usa testo `payload A`; sessione B usa testo `payload B` con lo stesso
UUID idempotente.

Atteso:

- una sola transazione inserisce;
- l'altra fallisce con `22023` e il messaggio sulla chiave gia usata;
- la riga e la notifica canoniche corrispondono al solo payload vincitore.

## C4 - cursore ultimo messaggio

Le sessioni usano chiavi diverse e inviano contemporaneamente. Dopo il commit:

```sql
select c.last_message_id, c.last_message_at, m.created_at
from public.conversations c
join public.messages m on m.id = c.last_message_id
where c.id = :conversation_id;
```

Atteso:

- `last_message_id` appartiene alla conversazione;
- `last_message_at = messages.created_at`;
- la tupla salvata e il massimo di `(created_at, id)` fra i due messaggi.

## C5 - deduplicazione notifica sistema

Due sessioni `service_role` chiamano contemporaneamente:

```sql
select private.conversation_system_event(
  :conversation_id,
  'order-event:' || :event_id,
  'Aggiornamento ordine.',
  :recipient_id,
  'order_updated'
);
```

Atteso:

- stesso `message.id` in entrambe le risposte;
- un solo messaggio sistema per `source_event_key`;
- una sola notifica per `recipient_id + dedupe_key`.

## Evidenza da conservare

Per ogni caso salvare output di entrambe le sessioni, conteggi finali, SQLSTATE
degli errori attesi e query di cleanup. Un timeout, deadlock o residuo non e un
PASSA. La prova e considerata chiusa soltanto con tutte le fixture rimosse.
