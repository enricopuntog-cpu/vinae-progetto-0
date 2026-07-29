-- ===========================================================================
-- Fase 6d-1 — PREFLIGHT. Da eseguire PRIMA della migrazione
-- 20260729230000_security_invariants.sql, nel SQL Editor del progetto.
--
-- PERCHÉ ESISTE. Il punto G introduce l'indice
-- `listings_un_solo_annuncio_non_terminale`, che estende il vincolo dai due
-- stati vivi ('attivo', 'riservato') a tutti e cinque quelli non terminali,
-- bozze comprese. Un indice unico si crea DOPO che i dati esistono: se il
-- database contiene già due bozze sulla stessa bottiglia, la CREATE fallisce e
-- la migrazione non passa.
--
-- Quello stato è raggiungibile davvero, non in teoria: `listing_crea` dichiara
-- esplicitamente di non controllare gli annunci già esistenti per l'unità
-- ("Nessun controllo sugli annunci già esistenti per questa unità: una bozza in
-- più non fa danno", 20260729210000_listing_crea_da_bottiglia.sql). Ogni prova
-- della 6c-2 in cui si è cliccato due volte "metti in vendita" sulla stessa
-- bottiglia ha lasciato due bozze.
--
-- NON si è scelto un indice tollerante che ammetta le violazioni preesistenti:
-- sarebbe una bugia permanente nello schema, e fra sei mesi nessuno ricorderebbe
-- perché è scritto così.
--
-- ORDINE: [1] rilevamento → se zero righe, applica la migrazione.
--         [2] bonifica    → solo se [1] ha restituito righe.
--         [3] riverifica  → deve restituire zero righe.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [1] RILEVAMENTO — la migrazione è applicabile?
-- ---------------------------------------------------------------------------
-- Zero righe = precondizione rispettata, si procede.
-- Una o più righe = leggere [2] prima di fare qualunque cosa.

select
  l.bottle_unit_id,
  count(*)                                as annunci_non_terminali,
  array_agg(l.slug order by l.created_at) as slug,
  array_agg(l.stato::text order by l.created_at) as stati
from public.listings l
where l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
group by l.bottle_unit_id
having count(*) > 1
order by count(*) desc, l.bottle_unit_id;


-- ---------------------------------------------------------------------------
-- [2] BONIFICA — caso peggiore
-- ---------------------------------------------------------------------------
-- Da eseguire SOLO se [1] ha restituito righe. Conserva un annuncio per
-- bottiglia e porta gli altri a 'sospeso', che è uno stato terminale ai fini
-- dell'indice e significa esattamente ciò che è successo: l'annuncio è stato
-- ritirato dalla circolazione.
--
-- QUALE SI CONSERVA. Il più avanzato lungo il percorso di pubblicazione, perché
-- è quello su cui c'è più lavoro e, se è 'attivo' o 'riservato', anche
-- l'aspettativa di qualcuno che lo sta guardando o comprando. A parità di
-- stato, il più recente: è quello che il venditore stava compilando.
--
--   attivo, riservato       4   già pubblico, mai da sospendere in favore di una bozza
--   modifiche_richieste     3   già passato da una revisione
--   in_revisione            2   già inviato
--   bozza                   1
--
-- NON si cancella nulla: `listings` è storico, e una riga cancellata porterebbe
-- via anche la traccia di ciò che il venditore aveva scritto.
--
-- Togliere il commento per eseguire.

/*
with classifica as (
  select
    l.id,
    row_number() over (
      partition by l.bottle_unit_id
      order by
        case l.stato
          when 'attivo'              then 4
          when 'riservato'           then 4
          when 'modifiche_richieste' then 3
          when 'in_revisione'        then 2
          else                            1
        end desc,
        l.created_at desc,
        l.id
    ) as posto
  from public.listings l
  where l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
)
update public.listings l
set stato               = 'sospeso',
    stato_motivo        = 'Ritirato dalla bonifica 6d-1: una bottiglia può avere un solo annuncio non terminale.',
    stato_aggiornato_at = now()
from classifica c
where c.id = l.id
  and c.posto > 1
returning l.id, l.slug, l.bottle_unit_id, l.stato;
*/


-- ---------------------------------------------------------------------------
-- [3] RIVERIFICA — deve restituire zero righe
-- ---------------------------------------------------------------------------

select
  l.bottle_unit_id,
  count(*) as annunci_non_terminali
from public.listings l
where l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
group by l.bottle_unit_id
having count(*) > 1;


-- ---------------------------------------------------------------------------
-- [4] SECONDA PRECONDIZIONE — bottiglie non idonee con annunci vivi
-- ---------------------------------------------------------------------------
-- Il trigger `listings_bottiglia_idonea` rifiuta ogni annuncio non terminale su
-- una bottiglia aperta, consumata o cancellata. È un trigger e non un vincolo,
-- quindi NON viene validato sulle righe già esistenti e la migrazione passa
-- comunque: nessun rischio di fallimento.
--
-- Va però guardato lo stesso, perché quelle righe diventano immodificabili — un
-- qualunque UPDATE successivo su quell'annuncio farebbe scattare il trigger.
-- Zero righe è la situazione attesa: fino a oggi `listing_crea` è l'unico
-- scrittore di `bottle_units` e le crea sempre 'chiusa'.

select
  l.id   as listing_id,
  l.slug,
  l.stato::text as stato_annuncio,
  bu.id  as bottle_unit_id,
  bu.stato::text as stato_bottiglia,
  bu.deleted_at
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
where l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
  and (bu.stato <> 'chiusa' or bu.deleted_at is not null)
order by l.created_at;
