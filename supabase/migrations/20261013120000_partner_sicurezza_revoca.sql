-- Pre-lancio — Sicurezza Partner: revoca, riabilitazione, sospensione annunci
-- e spegnimento di emergenza delle vendite Partner.
--
-- Decisione definitiva del titolare (13 ottobre 2026), che chiude la decisione
-- aperta di docs/VP_D_CLASSI_ECONOMICHE.md §4.1: un Partner revocato non puo
-- effettuare nuove vendite, nemmeno private, fino a una nuova approvazione
-- esplicita di Vinea.
--
-- Che cosa fa questa migrazione:
--   [1] `private.partner_riabilitazioni`: registro append-only delle
--       riabilitazioni amministrative (chi, quando, perche); nessun grant
--       client; un writer privilegiato e vincolato come la porta (Partner
--       revocato, titolare coerente);
--   [2] `private.venditore_vendite_bloccate(venditore)`: il venditore ha un
--       Partner revocato non seguito da una riabilitazione e nessun Partner
--       attivo o sospeso. E l'unica regola, letta da risolutore, gate, vista
--       pubblica, specchio e pubblicazione;
--   [3] il risolutore unico VP-D (`private.venditore_classe_di`) rende non
--       vendibile ogni annuncio personale del venditore bloccato
--       (`partner_revocato`), anche se preesistente: checkout, proposte e
--       preventivi lo seguono senza modifiche; i prodotti commerciali del
--       revocato restavano e restano `partner_non_attivo`;
--   [4] gate degli ordini e delle proposte senza annuncio, specchio
--       `acquisto_da_venditore_disponibile` e `public_listings` con la stessa
--       regola;
--   [5] annunci: nessun ingresso in revisione o in vendita per un venditore
--       bloccato, da qualsiasi porta (anche la moderazione `ripristina`);
--       l'interruttore `vendita_partner` blocca solo l'APERTURA alla vendita
--       di un prodotto commerciale, non piu le transizioni degli ordini gia
--       esistenti (riservato → venduto/attivo), che a interruttore spento
--       facevano fallire liquidazione, consegna e rilascio;
--   [6] porte admin: `partner_admin_vendite_riabilita` (nuova abilitazione
--       esplicita, distinta dal nuovo invito che resta il percorso per tornare
--       Partner), `partner_admin_annunci_sospendi` (sospensione amministrativa
--       di annunci e prodotti del Partner con la moderazione esistente, a
--       interruttore acceso o spento), `partner_admin_vendita_partner_spegni`
--       (spegnimento di emergenza, solo verso `false`, con registro);
--   [7] `partner_json` espone `vendite_bloccate` al titolare e all'admin.
--
-- Che cosa NON fa: non tocca ordini, pagamenti, spedizioni, contestazioni,
-- rimborsi, saldo o liquidazioni esistenti, ne i loro snapshot economici; non
-- accende `vendita_partner` ne `ordini_multi_unita`; non tocca
-- `PAYMENTS_ENABLED`, tariffe o condizioni commerciali; non modifica la
-- macchina a stati del Partner (la revoca resta terminale, il nuovo invito
-- resta ammesso).

-- ---------------------------------------------------------------------------
-- [1] Registro delle riabilitazioni
-- ---------------------------------------------------------------------------

create table private.partner_riabilitazioni (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references private.partners (id) on delete restrict,
  titolare_id uuid not null references public.profiles (id) on delete restrict,
  admin_id uuid not null references public.profiles (id) on delete restrict,
  motivo text not null,
  created_at timestamptz not null default now(),
  constraint partner_riabilitazioni_motivo_forma
    check (length(btrim(motivo)) between 1 and 500),
  constraint partner_riabilitazioni_non_se_stesso check (admin_id <> titolare_id),
  -- Una riabilitazione per revoca: legata al Partner revocato, non a un
  -- confronto di orari (una nuova revoca di un nuovo Partner riblocca).
  constraint partner_riabilitazioni_una_per_partner unique (partner_id)
);

comment on table private.partner_riabilitazioni is
  'Riabilitazioni amministrative alle vendite del titolare di un Partner '
  'revocato. Append-only, una per Partner revocato: il blocco di '
  'private.venditore_vendite_bloccate cade quando ogni Partner revocato del '
  'titolare ha la sua riga.';

create index partner_riabilitazioni_titolare_idx
  on private.partner_riabilitazioni (titolare_id);

alter table private.partner_riabilitazioni enable row level security;
revoke all on table private.partner_riabilitazioni from public, anon, authenticated;

create function private.partner_riabilitazioni_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'Il registro delle riabilitazioni e append-only.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from private.partners p
    where p.id = new.partner_id
      and p.titolare_id = new.titolare_id
      and p.stato = 'revocato'::public.partner_stato
  ) then
    raise exception 'Si riabilita solo il titolare di un Partner revocato.'
      using errcode = '42501', hint = 'partner_non_revocato';
  end if;
  new.created_at := now();
  return new;
end;
$$;

revoke execute on function private.partner_riabilitazioni_guard() from public, anon, authenticated;

create trigger partner_riabilitazioni_guard
  before insert or update or delete on private.partner_riabilitazioni
  for each row execute function private.partner_riabilitazioni_guard();

create trigger partner_riabilitazioni_no_truncate
  before truncate on private.partner_riabilitazioni
  for each statement execute function private.partner_no_truncate();

-- Registro degli spegnimenti di emergenza di `vendita_partner`.
create table private.vendita_partner_spegnimenti (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles (id) on delete restrict,
  motivo text not null,
  era_acceso boolean not null,
  created_at timestamptz not null default now(),
  constraint vendita_partner_spegnimenti_motivo_forma
    check (length(btrim(motivo)) between 1 and 500)
);

comment on table private.vendita_partner_spegnimenti is
  'Spegnimenti di emergenza di vendita_partner (porta admin). Append-only. '
  'L''accensione resta una decisione del titolare fuori da questa porta.';

alter table private.vendita_partner_spegnimenti enable row level security;
revoke all on table private.vendita_partner_spegnimenti from public, anon, authenticated;

create function private.vendita_partner_spegnimenti_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro degli spegnimenti e append-only.' using errcode = '42501';
end;
$$;

revoke execute on function private.vendita_partner_spegnimenti_append_only() from public, anon, authenticated;

create trigger vendita_partner_spegnimenti_append_only
  before update or delete on private.vendita_partner_spegnimenti
  for each row execute function private.vendita_partner_spegnimenti_append_only();

create trigger vendita_partner_spegnimenti_no_truncate
  before truncate on private.vendita_partner_spegnimenti
  for each statement execute function private.partner_no_truncate();

-- ---------------------------------------------------------------------------
-- [2] La regola, in un posto solo
-- ---------------------------------------------------------------------------

create function private.venditore_vendite_bloccate(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1 from private.partners r
      where r.titolare_id = p_seller_id
        and r.stato = 'revocato'::public.partner_stato
        and not exists (
          select 1 from private.partner_riabilitazioni x
          where x.partner_id = r.id)
    )
    and not exists (
      select 1 from private.partners a
      where a.titolare_id = p_seller_id
        and a.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
    );
$$;

comment on function private.venditore_vendite_bloccate(uuid) is
  'Decisione del titolare del 13 ottobre 2026: il titolare di un Partner '
  'revocato non vende (nemmeno annunci personali) finche Vinea non lo '
  'riabilita (una riga di partner_riabilitazioni per ogni Partner revocato) o non approva un '
  'nuovo Partner (attivo/sospeso: valgono allora le regole Partner). Un nuovo '
  'invito o un Partner in verifica non bastano.';

revoke execute on function private.venditore_vendite_bloccate(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Risolutore unico: annunci personali del venditore bloccato
-- ---------------------------------------------------------------------------
--
-- Ricreato dalla definizione VP-D con la sola aggiunta del ramo
-- `partner_revocato` dopo quello del Partner aperto. Classe `privato`: e la
-- classe che l'annuncio riavra con la riabilitazione; non e mai vendibile
-- finche il blocco dura. I prodotti commerciali non cambiano.

create or replace function private.venditore_classe_di(
  p_listing_id uuid,
  out classe public.classe_venditore,
  out vendibile boolean,
  out motivo text,
  out partner_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_partner_unita uuid;
  v_p private.partners%rowtype;
  v_aperto private.partners%rowtype;
begin
  select * into v_l from public.listings where id = p_listing_id;
  if v_l.id is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001',
      hint = 'annuncio_non_trovato';
  end if;

  select * into v_aperto from private.partners p
  where p.titolare_id = v_l.seller_id
    and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato);

  if v_l.inventario = 'commerciale'::public.inventario_classe then
    classe := 'partner';
    select bu.partner_id into v_partner_unita
    from public.bottle_units bu where bu.id = v_l.bottle_unit_id;
    partner_id := v_partner_unita;

    if v_partner_unita is null or exists (
      select 1 from private.listing_unita m
      join public.bottle_units u on u.id = m.bottle_unit_id
      where m.listing_id = v_l.id and m.ritirata_at is null
        and (u.inventario <> 'commerciale'::public.inventario_classe
             or u.partner_id is distinct from v_partner_unita)
    ) then
      vendibile := false; motivo := 'partner_incoerente'; return;
    end if;

    select * into v_p from private.partners p where p.id = v_partner_unita;
    if v_p.id is null or v_p.titolare_id <> v_l.seller_id then
      vendibile := false; motivo := 'partner_incoerente'; return;
    end if;
    if v_p.stato = 'sospeso'::public.partner_stato then
      vendibile := false; motivo := 'partner_sospeso'; return;
    end if;
    if v_p.stato <> 'attivo'::public.partner_stato then
      vendibile := false; motivo := 'partner_non_attivo'; return;
    end if;
    if private.utente_stato_di(v_l.seller_id) <> 'attivo'::public.utente_stato then
      vendibile := false; motivo := 'titolare_non_attivo'; return;
    end if;
    if not private.inventario_flag('vendita_partner') then
      vendibile := false; motivo := 'partner_vendita_non_disponibile'; return;
    end if;
    vendibile := true; motivo := null; return;
  end if;

  if v_aperto.id is not null then
    classe := 'partner'; vendibile := false;
    motivo := 'partner_annuncio_personale'; partner_id := v_aperto.id;
    return;
  end if;

  if private.venditore_vendite_bloccate(v_l.seller_id) then
    classe := 'privato'; vendibile := false; motivo := 'partner_revocato';
    select p.id into partner_id from private.partners p
    where p.titolare_id = v_l.seller_id and p.stato = 'revocato'::public.partner_stato
    order by p.revocato_at desc nulls last, p.id
    limit 1;
    return;
  end if;

  classe := 'privato'; vendibile := true; motivo := null; partner_id := null;
end;
$$;

comment on function private.venditore_classe_di(uuid) is
  'VP-D: classe economica e vendibilita di un annuncio, dal database, in sola '
  'lettura (preventivi, catalogo). Partner revocato (decisione del 13 ottobre '
  '2026): prodotti commerciali mai vendibili, annunci personali non vendibili '
  '(partner_revocato) fino a riabilitazione o nuovo Partner approvato.';

create or replace function private.venditore_classe_messaggio(p_motivo text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_motivo
    when 'partner_vendita_non_disponibile' then
      'Gli acquisti da Partner Vinea non sono ancora disponibili.'
    when 'partner_sospeso' then
      'Questo Partner Vinea è temporaneamente sospeso: i suoi prodotti non sono acquistabili.'
    when 'partner_non_attivo' then
      'Questo prodotto non è più in vendita.'
    when 'titolare_non_attivo' then
      'Questo prodotto non è acquistabile in questo momento.'
    when 'partner_incoerente' then
      'Questo prodotto non è acquistabile.'
    when 'partner_annuncio_personale' then
      'Gli acquisti da Partner Vinea non sono ancora disponibili.'
    when 'partner_revocato' then
      'Questo venditore non può vendere su Vinea in questo momento.'
    else 'Questo annuncio non è acquistabile.'
  end;
$$;

-- ---------------------------------------------------------------------------
-- [4] Gate senza annuncio, specchio e vista pubblica
-- ---------------------------------------------------------------------------

-- I gate di ordini e proposte usano questa funzione solo quando l'annuncio non
-- esiste (l'inserimento fallirebbe comunque sul vincolo): il venditore
-- bloccato riceve il rifiuto del gate come un Partner aperto.
create or replace function private.venditore_partner_aperto(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.partners p
    where p.titolare_id = p_seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  )
  or private.venditore_vendite_bloccate(p_seller_id);
$$;

comment on function private.venditore_partner_aperto(uuid) is
  'Il venditore non riceve ordini o proposte per la regola Partner: Partner '
  'attivo o sospeso, oppure Partner revocato non riabilitato.';

create or replace function public.acquisto_da_venditore_disponibile(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not private.venditore_partner_aperto(p_seller_id);
$$;

-- `public_listings`: colonne e ordine invariati. Un annuncio del venditore
-- bloccato non e in vetrina. Stessa regola di private.venditore_vendite_bloccate,
-- inline: in una vista l'EXECUTE di una funzione si verifica sul lettore.
create or replace view public.public_listings
with (security_invoker = off, security_barrier = true)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  d.disponibili as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id as wine_id,
  w.slug as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  bu.formato,
  (w.produttore || ' '::text) || w.nome as ricerca,
  p.id as seller_id,
  p.username as seller_username,
  p.citta as seller_citta,
  p.avatar_url as seller_avatar_url,
  w.provenienza as wine_provenienza,
  l.imballaggio_codice,
  (exists (select 1 from private.certificazioni_valide v
           where v.user_id = p.id and v.tipo = 'identita'::public.certificazione_tipo))
  and (exists (select 1 from private.certificazioni_valide v
               where v.user_id = p.id and v.tipo = 'venditore'::public.certificazione_tipo))
    as seller_verificato,
  l.confezione_originale_tipo,
  l.confezione_originale_foto,
  case
    when l.inventario = 'commerciale'::public.inventario_classe then 'partner'::public.classe_venditore
    when exists (select 1 from private.partners pa
                 where pa.titolare_id = l.seller_id
                   and pa.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato))
      then 'partner'::public.classe_venditore
    else 'privato'::public.classe_venditore
  end as venditore_classe
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
  cross join lateral (
    select count(*)::integer as disponibili
    from private.listing_unita m
    join public.bottle_units u on u.id = m.bottle_unit_id
    where m.listing_id = l.id and m.ritirata_at is null
      and u.ceduta_at is null and u.deleted_at is null
      and u.stato = 'chiusa'::public.bottle_unit_stato and u.owner_id = l.seller_id
      and not exists (
        select 1 from private.listing_allocazioni a
        where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null
          and a.ceduta_at is null and a.scadenza > now())
  ) d
where l.stato = 'attivo'::public.listing_stato
  and (l.expires_at is null or l.expires_at > now())
  and bu.stato = 'chiusa'::public.bottle_unit_stato
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.owner_id = l.seller_id
  and d.disponibili > 0
  and (l.inventario = 'personale'::public.inventario_classe
       or (exists (select 1 from private.inventario_impostazioni i
                   where i.id and i.vendita_partner)
           and exists (select 1 from private.partners pa
                       where pa.id = bu.partner_id and pa.titolare_id = l.seller_id
                         and pa.stato = 'attivo'::public.partner_stato)
           and p.stato_utente = 'attivo'::public.utente_stato))
  and not (
    exists (select 1 from private.partners r
            where r.titolare_id = l.seller_id
              and r.stato = 'revocato'::public.partner_stato
              and not exists (
                select 1 from private.partner_riabilitazioni x
                where x.partner_id = r.id))
    and not exists (select 1 from private.partners a
                    where a.titolare_id = l.seller_id
                      and a.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato))
  )
  and p.stato_utente <> 'rimosso'::public.utente_stato
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'::public.utente_stato
  );

-- ---------------------------------------------------------------------------
-- [5] Annunci: apertura alla vendita
-- ---------------------------------------------------------------------------
--
-- Un annuncio "si apre" quando entra in revisione o diventa attivo da uno
-- stato che non lo era (o nasce cosi). Riservato → attivo non e un'apertura:
-- e il rilascio di un ordine annullato o scaduto. Riservato → venduto e la
-- conclusione di un ordine gia pagato. Nessuna delle due va mai bloccata.

create function private.listing_si_apre(
  p_op text, p_vecchio public.listing_stato, p_nuovo public.listing_stato)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_nuovo = 'attivo'::public.listing_stato then
      p_op = 'INSERT' or p_vecchio not in ('attivo'::public.listing_stato, 'riservato'::public.listing_stato)
    when p_nuovo = 'in_revisione'::public.listing_stato then
      p_op = 'INSERT' or p_vecchio <> 'in_revisione'::public.listing_stato
    when p_nuovo in ('riservato'::public.listing_stato, 'venduto'::public.listing_stato) then
      p_op = 'INSERT'
    else false
  end;
$$;

revoke execute on function private.listing_si_apre(text, public.listing_stato, public.listing_stato)
  from public, anon, authenticated;

-- Ricreata dalla definizione corrente (20261012150000) con la sola modifica
-- del controllo sull'interruttore: prima rifiutava OGNI scrittura di un
-- prodotto commerciale in revisione/attivo/riservato/venduto a interruttore
-- spento, quindi anche la liquidazione o il rilascio di un ordine gia pagato.
create or replace function public.listings_bottiglia_idonea()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
  v_classe  public.inventario_classe;
begin
  if tg_op = 'UPDATE' and new.inventario is distinct from old.inventario then
    raise exception 'La classe di un annuncio non cambia.'
      using errcode = '42501', hint = 'annuncio_classe_immutabile';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at, bu.inventario
  into v_owner, v_stato, v_deleted, v_ceduta, v_classe
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if not found then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;

  if v_owner is distinct from new.seller_id then
    raise exception 'Il venditore deve essere il proprietario della bottiglia.'
      using errcode = '42501';
  end if;

  if v_classe is distinct from new.inventario then
    raise exception 'I prodotti Partner non si mettono in vendita da qui.'
      using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
  end if;

  if new.inventario = 'commerciale'
     and private.listing_si_apre(tg_op, case when tg_op = 'UPDATE' then old.stato end, new.stato)
     and not private.inventario_flag('vendita_partner') then
    raise exception 'La vendita dei prodotti Partner non è ancora disponibile.'
      using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
  end if;

  if new.stato not in (
    'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
  ) then
    return new;
  end if;

  if v_deleted is not null then
    raise exception 'Questa bottiglia non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_stato <> 'chiusa' then
    raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- Venditore bloccato: nessun annuncio si apre, da nessuna porta (wizard,
-- pubblicazione, moderazione `ripristina`, writer privilegiati).
create function private.listings_venditore_abilitato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.listing_si_apre(tg_op, case when tg_op = 'UPDATE' then old.stato end, new.stato)
     and private.venditore_vendite_bloccate(new.seller_id) then
    raise exception 'Questo account non può mettere in vendita finché Vinea non lo riabilita.'
      using errcode = '42501', hint = 'partner_revocato';
  end if;
  return new;
end;
$$;

revoke execute on function private.listings_venditore_abilitato() from public, anon, authenticated;

create trigger listings_venditore_abilitato
  before insert or update of stato on public.listings
  for each row execute function private.listings_venditore_abilitato();

-- ---------------------------------------------------------------------------
-- [6] Porte amministrative
-- ---------------------------------------------------------------------------

-- Nuova abilitazione esplicita alle vendite private del titolare di un
-- Partner revocato. Il Partner resta revocato: tornare Partner richiede un
-- nuovo invito, la verifica e l'approvazione (governance invariata).
create function public.partner_admin_vendite_riabilita(p_partner_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
  v_motivo text := private.partner_motivo_pulito(p_motivo);
  v_p private.partners%rowtype;
  v_n integer;
begin
  if v_motivo is null then
    raise exception 'La riabilitazione richiede un motivo.' using errcode = '22023';
  end if;

  select * into v_p from private.partners where id = p_partner_id;
  if v_p.id is null then
    raise exception 'Partner non trovato.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  if v_p.titolare_id = v_admin then
    raise exception 'Non puoi decidere sul tuo stesso Partner.' using errcode = '42501';
  end if;

  -- Stesso ordine di blocco del risolutore (FOR SHARE per id): un acquisto
  -- concorrente attende o precede la riabilitazione, mai a meta.
  perform 1 from private.partners p
  where p.titolare_id = v_p.titolare_id
  order by p.id
  for update;

  select * into v_p from private.partners where id = p_partner_id;
  if v_p.stato <> 'revocato'::public.partner_stato then
    raise exception 'Si riabilitano solo le vendite del titolare di un Partner revocato.'
      using errcode = 'P0001', hint = 'transizione_non_ammessa';
  end if;
  if private.utente_stato_di(v_p.titolare_id) = 'rimosso'::public.utente_stato then
    raise exception 'Il titolare e rimosso: le vendite non si riabilitano.'
      using errcode = 'P0001', hint = 'titolare_rimosso';
  end if;

  if not private.venditore_vendite_bloccate(v_p.titolare_id) then
    return jsonb_build_object('partnerId', v_p.id, 'venditeBloccate', false, 'giaRiabilitato', true);
  end if;

  -- Una riga per ogni Partner revocato del titolare ancora senza
  -- riabilitazione: la decisione riguarda la persona, il registro le revoche.
  insert into private.partner_riabilitazioni (partner_id, titolare_id, admin_id, motivo)
  select r.id, r.titolare_id, v_admin, v_motivo
  from private.partners r
  where r.titolare_id = v_p.titolare_id
    and r.stato = 'revocato'::public.partner_stato
    and not exists (select 1 from private.partner_riabilitazioni x where x.partner_id = r.id)
  order by r.id;
  get diagnostics v_n = row_count;

  return jsonb_build_object(
    'partnerId', v_p.id,
    'venditeBloccate', private.venditore_vendite_bloccate(v_p.titolare_id),
    'giaRiabilitato', false,
    'revocheRiabilitate', v_n);
end;
$$;

comment on function public.partner_admin_vendite_riabilita(uuid, text) is
  'Admin: riabilita alle vendite private il titolare di un Partner revocato. '
  'Motivo obbligatorio, mai sul proprio Partner, idempotente; registro in '
  'private.partner_riabilitazioni. Non riattiva il Partner.';

revoke execute on function public.partner_admin_vendite_riabilita(uuid, text) from public, anon, service_role;
grant execute on function public.partner_admin_vendite_riabilita(uuid, text) to authenticated;

-- Sospensione amministrativa di tutti gli annunci aperti del titolare
-- (prodotti commerciali e annunci personali), in qualsiasi stato del Partner
-- e a interruttore acceso o spento. Usa la transizione della moderazione
-- (audit per annuncio); gli annunci riservati o venduti hanno un ordine e non
-- si toccano. Il ripristino passa dalla moderazione ed e soggetto agli stessi
-- gate (Partner attivo, interruttore, venditore non bloccato).
create function public.partner_admin_annunci_sospendi(p_partner_id uuid, p_motivo text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
  v_motivo text := private.partner_motivo_pulito(p_motivo);
  v_p private.partners%rowtype;
  v_id uuid;
  v_n integer := 0;
begin
  if v_motivo is null then
    raise exception 'La sospensione degli annunci richiede un motivo.' using errcode = '22023';
  end if;
  select * into v_p from private.partners where id = p_partner_id;
  if v_p.id is null then
    raise exception 'Partner non trovato.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  if v_p.titolare_id = v_admin then
    raise exception 'Non puoi decidere sul tuo stesso Partner.' using errcode = '42501';
  end if;

  for v_id in
    select l.id from public.listings l
    where l.seller_id = v_p.titolare_id
      and l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo')
      and (l.inventario = 'personale'::public.inventario_classe
           or exists (select 1 from public.bottle_units bu
                      where bu.id = l.bottle_unit_id and bu.partner_id = v_p.id))
    order by l.id
  loop
    perform private.moderazione_annuncio_transizione(
      v_admin, v_id,
      'sospeso'::public.listing_stato,
      'sospensione'::public.mod_action,
      v_motivo,
      array['bozza', 'in_revisione', 'modifiche_richieste', 'attivo']::public.listing_stato[]
    );
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

comment on function public.partner_admin_annunci_sospendi(uuid, text) is
  'Admin: sospende gli annunci aperti (bozza, revisione, modifiche, attivo) '
  'del titolare del Partner, prodotti e annunci personali, con la '
  'transizione e l''audit della moderazione. Non tocca annunci con ordini.';

revoke execute on function public.partner_admin_annunci_sospendi(uuid, text) from public, anon, service_role;
grant execute on function public.partner_admin_annunci_sospendi(uuid, text) to authenticated;

-- Spegnimento di emergenza: solo verso `false`. Le vendite Partner nuove si
-- fermano subito (checkout, proposte, pubblicazione, vetrina, Esplora); gli
-- ordini gia creati proseguono (liquidazione, consegna, contestazioni,
-- rimborsi, saldo), perche nessuno di quei percorsi rilegge l'interruttore.
create function public.partner_admin_vendita_partner_spegni(p_motivo text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
  v_motivo text := private.partner_motivo_pulito(p_motivo);
  v_era boolean;
begin
  if v_motivo is null then
    raise exception 'Lo spegnimento richiede un motivo.' using errcode = '22023';
  end if;

  select i.vendita_partner into v_era
  from private.inventario_impostazioni i where i.id for update;

  update private.inventario_impostazioni
  set vendita_partner = false, aggiornato_at = now()
  where id;

  insert into private.vendita_partner_spegnimenti (admin_id, motivo, era_acceso)
  values (v_admin, v_motivo, coalesce(v_era, false));

  return false;
end;
$$;

comment on function public.partner_admin_vendita_partner_spegni(text) is
  'Admin: spegnimento di emergenza di vendita_partner (solo false), con '
  'registro. Non tocca ordini esistenti. L''accensione non passa da qui.';

revoke execute on function public.partner_admin_vendita_partner_spegni(text) from public, anon, service_role;
grant execute on function public.partner_admin_vendita_partner_spegni(text) to authenticated;

-- ---------------------------------------------------------------------------
-- [7] Il titolare e l'admin vedono il blocco
-- ---------------------------------------------------------------------------

create or replace function private.partner_json(p private.partners)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'stato', p.stato,
    'ragione_sociale', p.ragione_sociale,
    'nome_commerciale', p.nome_commerciale,
    'partita_iva', p.partita_iva,
    'paese', p.paese,
    'sede_indirizzo', p.sede_indirizzo,
    'sede_cap', p.sede_cap,
    'sede_citta', p.sede_citta,
    'sede_provincia', p.sede_provincia,
    'email_commerciale', p.email_commerciale,
    'tipologia', p.tipologia,
    'inviato_verifica_at', p.inviato_verifica_at,
    'attivo_dal', p.attivo_dal,
    'sospeso_at', p.sospeso_at,
    'revocato_at', p.revocato_at,
    'ultimo_motivo', p.ultimo_motivo,
    'created_at', p.created_at,
    'updated_at', p.updated_at,
    'vendite_bloccate', p.stato = 'revocato'::public.partner_stato
                        and private.venditore_vendite_bloccate(p.titolare_id)
  );
$$;

notify pgrst, 'reload schema';
