-- WI-008 — selezione PERSONALE di una scheda del catalogo canonico per un vino della propria Cantina.
--
-- Tre cose diverse, qui c'è solo la prima:
--   * selezione personale confermata dall'utente: privata, reversibile, vale solo per chi l'ha fatta;
--   * proposta di collegamento: NON introdotta (chi la conferma è una decisione di governance ancora aperta);
--   * collegamento canonico autorevole: `catalog.wine_links`, invariata, scrivibile solo dalle porte del curatore
--     (richiede un'annata canonica che solo il curatore crea).
-- La scelta non modifica `public.wines`, le bottiglie né il catalogo, e nessun'altra superficie la usa come fatto.
--
-- Verifica server-side: il codice viene risolto con la stessa porta della ricerca (`vini_canonici_cerca`), quindi
-- valgono interruttore della proiezione (spento = nessuna scelta possibile), fonte autorizzata, vino promosso e
-- attivo, risoluzione dei Combined e limite per identità. Nessuna seconda regola di visibilità, nessun backfill.

create table public.wine_catalog_selections (
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  wine_id uuid not null
    references public.wines (id) on delete cascade,
  lwin7 text not null check (lwin7 ~ '^[0-9]{7}$'),
  selected_at timestamptz not null default now(),
  constraint wine_catalog_selections_pkey primary key (owner_id, wine_id)
);

create index wine_catalog_selections_wine_idx on public.wine_catalog_selections (wine_id);

comment on table public.wine_catalog_selections is
  'WI-008. Scheda del catalogo (LWIN-7) che il proprietario dice di intendere per un vino della sua Cantina. PRIVATA: '
  'RLS del solo proprietario, scrittura solo via cellar_catalogo_scegli/rimuovi. Non è un collegamento canonico, non '
  'è verificata da un curatore e non modifica public.wines né le bottiglie.';

alter table public.wine_catalog_selections enable row level security;

create policy "wine_catalog_selections_select_own"
  on public.wine_catalog_selections for select
  to authenticated
  using (owner_id = (select auth.uid()));

revoke all on public.wine_catalog_selections from public, anon, authenticated;
grant select on public.wine_catalog_selections to authenticated;

create or replace function public.cellar_catalogo_scegli(p_wine_slug text, p_lwin7 text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_wine uuid;
  v_lwin7 text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_lwin7 is null or p_lwin7 !~ '^[0-9]{7}$' then
    raise exception 'Codice del catalogo non valido.' using errcode = 'P0001';
  end if;

  -- Un solo messaggio per «non esiste» e «non è nella tua Cantina»: nessun modo di sondare i vini altrui.
  select w.id into v_wine
    from public.wines w
   where w.slug = p_wine_slug
     and exists (select 1 from public.bottle_units bu
                  where bu.owner_id = v_uid and bu.wine_id = w.id and bu.deleted_at is null);
  if v_wine is null then
    raise exception 'Puoi collegare solo i vini presenti nella tua Cantina.' using errcode = 'P0001';
  end if;

  select c.lwin7 into v_lwin7
    from public.vini_canonici_cerca('', '', 1, p_lwin7) c
   where c.livello = 'identificativo';
  if v_lwin7 is null then
    raise exception 'La scheda del catalogo non è disponibile.' using errcode = 'P0001';
  end if;

  insert into public.wine_catalog_selections (owner_id, wine_id, lwin7)
  values (v_uid, v_wine, v_lwin7)
  on conflict (owner_id, wine_id) do update set lwin7 = excluded.lwin7, selected_at = now();

  return v_lwin7;
end;
$$;

-- Rimozione sempre possibile al proprietario della scelta, anche a catalogo spento o a bottiglia ceduta.
create or replace function public.cellar_catalogo_rimuovi(p_wine_slug text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_righe integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  delete from public.wine_catalog_selections s
   using public.wines w
   where s.owner_id = v_uid and s.wine_id = w.id and w.slug = p_wine_slug;
  get diagnostics v_righe = row_count;
  return v_righe > 0;
end;
$$;

comment on function public.cellar_catalogo_scegli(text, text) is
  'WI-008. Salva la scelta personale di una scheda del catalogo per un vino della propria Cantina, dopo averla risolta '
  'con la ricerca canonica. Non crea collegamenti canonici.';
comment on function public.cellar_catalogo_rimuovi(text) is
  'WI-008. Rimuove la propria scelta di scheda del catalogo per un vino.';

revoke all on function public.cellar_catalogo_scegli(text, text), public.cellar_catalogo_rimuovi(text) from public, anon;
grant execute on function public.cellar_catalogo_scegli(text, text), public.cellar_catalogo_rimuovi(text) to authenticated;

-- Il solo fatto «il catalogo è consultabile», per non mostrare comandi che non possono funzionare. Nessun dato del
-- catalogo. STABLE: via PostgREST è una lettura (nessun contatore).
create or replace function public.catalogo_canonico_disponibile()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.enabled from catalog.public_projection_settings s), false);
$$;

comment on function public.catalogo_canonico_disponibile() is
  'WI-008. Vero solo se la proiezione pubblica del catalogo è accesa. Nessun altro dato.';

revoke all on function public.catalogo_canonico_disponibile() from public, anon;
grant execute on function public.catalogo_canonico_disponibile() to authenticated;

notify pgrst, 'reload schema';
