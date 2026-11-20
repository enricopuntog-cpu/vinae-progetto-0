-- ============================================================================
-- WI-005B — annotazioni personali sui vini della propria Cantina.
-- ============================================================================
--
-- AUTORIZZAZIONE. Migration additiva autorizzata per nome dal task VPM-WI-005B
-- (20 novembre 2026), a condizione che non modifichi l'identita' condivisa dei
-- vini, non alteri migration distribuite, abbia RLS owner-only, privilegi
-- minimi e test di isolamento, e non introduca costi o servizi nuovi.
--
-- PERCHE' UNA TABELLA E NON LE COLONNE ESISTENTI. `bottle_units` ha gia' le
-- colonne personali per UNITA': `note_personali` (testo libero), `override_*`
-- (finestra di bevuta, che questo file NON duplica) e `override_nota`. Mancano
-- cose che sono del VINO e non della singola bottiglia, e che non stanno in un
-- testo libero senza perdere il tipo: abbinamenti sperimentati, temperatura e
-- decantazione preferite, calice, e le dichiarazioni sull'identita' (annata,
-- non millesimato, denominazione, regione). Una riga per (proprietario, vino)
-- evita di ripeterle su ogni bottiglia dello stesso vino.
--
-- COSA NON E'. Non e' una seconda anagrafica dei vini e non tocca `public.wines`:
-- un vino puo' essere condiviso da piu' utenti e nessuno puo' cambiarlo per
-- tutti. Ogni valore qui e' una DICHIARAZIONE PERSONALE: privata, mai certificata,
-- mai pubblicata, mai proposta al catalogo senza un'azione esplicita che oggi non
-- esiste. Nessuna vista pubblica la legge e `public_bottle_units` non cambia.
--
-- ESPOSIZIONE. Nessun grant di scrittura al client: la sola porta in scrittura
-- sono due funzioni SECURITY DEFINER che verificano `auth.uid()` e che l'utente
-- possieda davvero una bottiglia di quel vino. In lettura `authenticated` vede le
-- sole proprie righe (RLS); `anon` non ha alcun privilegio.
-- ============================================================================

create table public.wine_personal_notes (
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  wine_id uuid not null
    references public.wines (id) on delete cascade,
  abbinamenti text[] not null default '{}',
  temperatura_servizio_c smallint,
  decantazione_minuti smallint,
  calice text not null default '',
  annata_dichiarata smallint,
  non_millesimato boolean not null default false,
  denominazione_dichiarata text not null default '',
  regione_dichiarata text not null default '',
  osservazioni text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wine_personal_notes_pkey primary key (owner_id, wine_id),
  constraint wine_personal_notes_temperatura check (temperatura_servizio_c between 0 and 25),
  constraint wine_personal_notes_decantazione check (decantazione_minuti between 0 and 600),
  constraint wine_personal_notes_annata check (annata_dichiarata between 1800 and 2100),
  constraint wine_personal_notes_annata_o_nv check (not (non_millesimato and annata_dichiarata is not null)),
  constraint wine_personal_notes_n_abbinamenti check (coalesce(cardinality(abbinamenti), 0) <= 8),
  constraint wine_personal_notes_calice check (char_length(calice) <= 40),
  constraint wine_personal_notes_denominazione check (char_length(denominazione_dichiarata) <= 120),
  constraint wine_personal_notes_regione check (char_length(regione_dichiarata) <= 80),
  constraint wine_personal_notes_osservazioni check (char_length(osservazioni) <= 1000)
);

comment on table public.wine_personal_notes is
  'Dichiarazioni personali del proprietario su un vino della sua Cantina '
  '(abbinamenti, servizio, identita'' dichiarata, osservazioni). PRIVATE: RLS del '
  'solo proprietario, scrittura solo via cellar_nota_vino_salva/elimina. Non '
  'modificano public.wines, non sono dati certificati, non sono pubbliche.';

create trigger wine_personal_notes_set_updated_at
  before update on public.wine_personal_notes
  for each row
  execute function extensions.moddatetime('updated_at');

alter table public.wine_personal_notes enable row level security;

create policy "wine_personal_notes_select_own"
  on public.wine_personal_notes for select
  to authenticated
  using (owner_id = auth.uid());

-- Nessuna policy di INSERT/UPDATE/DELETE e nessun grant di scrittura: le
-- scritture passano dalle funzioni qui sotto, che bypassano la RLS in modo
-- controllato (verificano proprietario e possesso).
revoke all on public.wine_personal_notes from public, anon, authenticated;
grant select on public.wine_personal_notes to authenticated;

-- ---------------------------------------------------------------------------
-- cellar_nota_vino_salva — l'unica porta in scrittura
-- ---------------------------------------------------------------------------
-- Una nota completamente vuota CANCELLA la riga: «nessuna annotazione» non e'
-- una riga di stringhe vuote. Il resto e' un upsert per (utente, vino).

create or replace function public.cellar_nota_vino_salva(
  p_wine_slug text,
  p_abbinamenti text[],
  p_temperatura smallint,
  p_decantazione smallint,
  p_calice text,
  p_annata smallint,
  p_non_millesimato boolean,
  p_denominazione text,
  p_regione text,
  p_osservazioni text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_wine uuid;
  v_abb text[] := '{}';
  v_voce text;
  v_chiavi text[] := '{}';
  v_calice text := btrim(coalesce(p_calice, ''), E' \t\r\n');
  v_den text := btrim(coalesce(p_denominazione, ''), E' \t\r\n');
  v_reg text := btrim(coalesce(p_regione, ''), E' \t\r\n');
  v_oss text := btrim(coalesce(p_osservazioni, ''), E' \t\r\n');
  v_nv boolean := coalesce(p_non_millesimato, false);
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  select w.id into v_wine from public.wines w where w.slug = p_wine_slug;
  if v_wine is null then
    raise exception 'Vino non trovato.' using errcode = 'P0001';
  end if;

  -- Solo per i vini che si possiedono: niente annotazioni su vini altrui e
  -- nessun modo di verificare dall'esterno se un vino esiste in una Cantina.
  if not exists (
    select 1 from public.bottle_units bu
    where bu.owner_id = v_uid and bu.wine_id = v_wine and bu.deleted_at is null
  ) then
    raise exception 'Puoi annotare solo i vini presenti nella tua Cantina.' using errcode = 'P0001';
  end if;

  -- Abbinamenti: spazi compattati, vuoti scartati, duplicati (senza distinguere
  -- le maiuscole) scartati, ordine d'ingresso mantenuto.
  foreach v_voce in array coalesce(p_abbinamenti, '{}') loop
    v_voce := btrim(regexp_replace(coalesce(v_voce, ''), '\s+', ' ', 'g'));
    if v_voce = '' then continue; end if;
    if v_voce ~ '[[:cntrl:]\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]' then
      raise exception 'Un abbinamento contiene caratteri non ammessi.' using errcode = 'P0001';
    end if;
    if char_length(v_voce) < 2 or char_length(v_voce) > 60 then
      raise exception 'Ogni abbinamento deve avere da 2 a 60 caratteri.' using errcode = 'P0001';
    end if;
    if lower(v_voce) = any (v_chiavi) then continue; end if;
    v_chiavi := v_chiavi || lower(v_voce);
    v_abb := v_abb || v_voce;
  end loop;
  if cardinality(v_abb) > 8 then
    raise exception 'Indica al massimo 8 abbinamenti.' using errcode = 'P0001';
  end if;

  if v_calice ~ '[[:cntrl:]\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]' or v_den ~ '[[:cntrl:]\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]' or v_reg ~ '[[:cntrl:]\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]' then
    raise exception 'Il testo contiene caratteri non ammessi.' using errcode = 'P0001';
  end if;
  -- Le osservazioni ammettono a capo e tab, non gli altri caratteri di controllo.
  if v_oss ~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]' then
    raise exception 'Il testo contiene caratteri non ammessi.' using errcode = 'P0001';
  end if;
  if char_length(v_calice) > 40 or char_length(v_den) > 120
     or char_length(v_reg) > 80 or char_length(v_oss) > 1000 then
    raise exception 'Un testo supera la lunghezza consentita.' using errcode = 'P0001';
  end if;
  if p_temperatura is not null and p_temperatura not between 0 and 25 then
    raise exception 'La temperatura deve essere compresa fra 0 e 25 gradi.' using errcode = 'P0001';
  end if;
  if p_decantazione is not null and p_decantazione not between 0 and 600 then
    raise exception 'La decantazione deve essere compresa fra 0 e 600 minuti.' using errcode = 'P0001';
  end if;
  if p_annata is not null and p_annata not between 1800 and 2100 then
    raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
  end if;
  if v_nv and p_annata is not null then
    raise exception 'Scegli: o indichi un''annata o dichiari il vino non millesimato.' using errcode = 'P0001';
  end if;

  -- Nessun contenuto: la nota non esiste.
  if cardinality(v_abb) = 0 and p_temperatura is null and p_decantazione is null
     and v_calice = '' and p_annata is null and not v_nv
     and v_den = '' and v_reg = '' and v_oss = '' then
    delete from public.wine_personal_notes where owner_id = v_uid and wine_id = v_wine;
    return;
  end if;

  insert into public.wine_personal_notes as n (
    owner_id, wine_id, abbinamenti, temperatura_servizio_c, decantazione_minuti,
    calice, annata_dichiarata, non_millesimato, denominazione_dichiarata,
    regione_dichiarata, osservazioni
  ) values (
    v_uid, v_wine, v_abb, p_temperatura, p_decantazione,
    v_calice, p_annata, v_nv, v_den, v_reg, v_oss
  )
  on conflict (owner_id, wine_id) do update set
    abbinamenti = excluded.abbinamenti,
    temperatura_servizio_c = excluded.temperatura_servizio_c,
    decantazione_minuti = excluded.decantazione_minuti,
    calice = excluded.calice,
    annata_dichiarata = excluded.annata_dichiarata,
    non_millesimato = excluded.non_millesimato,
    denominazione_dichiarata = excluded.denominazione_dichiarata,
    regione_dichiarata = excluded.regione_dichiarata,
    osservazioni = excluded.osservazioni;
end;
$$;

comment on function public.cellar_nota_vino_salva(
  text, text[], smallint, smallint, text, smallint, boolean, text, text, text
) is
  'Salva (upsert) le annotazioni personali del chiamante su un vino che possiede. '
  'Tutti i campi vuoti cancellano la riga. Non tocca public.wines.';

revoke execute on function public.cellar_nota_vino_salva(
  text, text[], smallint, smallint, text, smallint, boolean, text, text, text
) from public, anon;
grant execute on function public.cellar_nota_vino_salva(
  text, text[], smallint, smallint, text, smallint, boolean, text, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- cellar_nota_vino_elimina — cancellazione esplicita, idempotente
-- ---------------------------------------------------------------------------

create or replace function public.cellar_nota_vino_elimina(p_wine_slug text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  delete from public.wine_personal_notes n
  using public.wines w
  where w.slug = p_wine_slug
    and n.wine_id = w.id
    and n.owner_id = v_uid;
end;
$$;

comment on function public.cellar_nota_vino_elimina(text) is
  'Cancella le annotazioni personali del chiamante su un vino. Idempotente.';

revoke execute on function public.cellar_nota_vino_elimina(text) from public, anon;
grant execute on function public.cellar_nota_vino_elimina(text) to authenticated;
