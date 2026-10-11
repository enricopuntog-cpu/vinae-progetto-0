-- ===========================================================================
-- Vinea Partner — Blocco A: fondazione (inviti, identita aziendale, stati)
-- ===========================================================================
--
-- Ammissione: decisione organizzativa esplicita del titolare dell'11 ottobre
-- 2026 (filone «Vinea Partner + Quantita multiple», blocchi A-F; questo file
-- realizza soltanto il Blocco A). Registrata in docs/ROADMAP_V1.md.
--
-- SOSTITUISCE la bozza non committata `20261011120000_partner_program_blocco_a.sql`
-- lasciata da un'esecuzione precedente: quel file non era applicabile (sintassi
-- invalida, policy su colonne inesistenti, marcatore delle qualifiche
-- riutilizzato, `email = p_code`, `least(..., 0)`), non e mai stato spinto ne
-- applicato e non e la base di questo. L'esito della verifica punto per punto
-- e in CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md.
--
-- Che cosa NON fa, di proposito:
--   - non tocca `public.marketplace_config`, `order_checkout_reserve` ne alcun
--     calcolo economico: il margine Partner (1500 bps) e una decisione
--     commerciale registrata, non ancora un parametro applicato;
--   - non scrive `public.user_roles`: la classe commerciale Partner si deriva
--     dallo stato del Partner e non e un ruolo assegnabile. Le qualifiche
--     personali (`professional_qualifications`, marcatore `vinea.pq_review`)
--     restano un dominio separato e non sono lette ne scritte qui;
--   - non apre nessun checkout professionale. Al contrario: un Partner attivo
--     o sospeso non puo essere il venditore di un nuovo ordine (gate [9]),
--     finche i blocchi dipendenti non esistono;
--   - non invia email e non contatta fornitori: il link d'invito lo consegna
--     l'amministratore a mano.
--
-- Modello di sicurezza, in tre strati (forma della D1 20260827160000):
--   1. tabelle in `private`, RLS attiva, nessun grant client: nessuna
--      scrittura o lettura diretta da cui difendersi;
--   2. porte `SECURITY DEFINER` che risolvono identita e ruolo dal database
--      (`auth.uid()`, `public.user_roles`), mai da argomenti del chiamante;
--   3. trigger che pretendono un marcatore di transazione DEDICATO
--      (`vinea.partner_porta`), legato alla singola riga e al tipo di porta.
--      Vincolano anche `service_role` e una UPDATE scritta a mano.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- [1] Tipi
-- ---------------------------------------------------------------------------

create type public.partner_stato as enum (
  'invitato',
  'in_verifica',
  'attivo',
  'sospeso',
  'revocato'
);

comment on type public.partner_stato is
  'Ciclo di vita di un Partner Vinea. invitato: invito accettato, dati '
  'aziendali in compilazione dal titolare. in_verifica: dati consegnati e '
  'congelati, in attesa dell amministrazione. attivo: approvato. sospeso: '
  'temporaneamente fermato dall amministrazione. revocato: terminale, senza '
  'uscite. Transizioni in private.partners_guard().';

create type public.partner_tipologia as enum (
  'enoteca',
  'ristorazione',
  'cantina_produttore',
  'distribuzione',
  'altro'
);

comment on type public.partner_tipologia is
  'Tipologia di attivita dichiarata dal Partner. Elenco minimo con uscita '
  '`altro`: ampliarlo e un add value in una migrazione separata.';

-- ---------------------------------------------------------------------------
-- [2] Funzioni di validazione
-- ---------------------------------------------------------------------------

-- Partita IVA italiana: 11 cifre con cifra di controllo. Nessuna apertura
-- verso l'estero (decisione commerciale), quindi nessun formato straniero.
create function private.partita_iva_valida(p_valore text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_somma integer := 0;
  v_cifra integer;
  i integer;
begin
  if p_valore is null or p_valore !~ '^[0-9]{11}$' then
    return false;
  end if;

  for i in 1..10 loop
    v_cifra := substr(p_valore, i, 1)::integer;
    if i % 2 = 0 then
      v_cifra := v_cifra * 2;
      if v_cifra > 9 then
        v_cifra := v_cifra - 9;
      end if;
    end if;
    v_somma := v_somma + v_cifra;
  end loop;

  return (10 - v_somma % 10) % 10 = substr(p_valore, 11, 1)::integer;
end;
$$;

revoke execute on function private.partita_iva_valida(text)
  from public, anon, authenticated;

create function private.partner_email_valida(p_valore text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_valore is not null
    and length(p_valore) <= 254
    and p_valore = lower(btrim(p_valore))
    and p_valore ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$';
$$;

revoke execute on function private.partner_email_valida(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Tabelle
-- ---------------------------------------------------------------------------

-- Inviti: MONOUSO. Nessun contatore di utilizzi: un invito apre al massimo un
-- Partner, e un secondo uso dello stesso token e rifiutato. Il token in chiaro
-- non e mai memorizzato: resta solo l'hash sha256, il chiaro esce una volta
-- sola dalla porta di creazione.
create table private.partner_inviti (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  token_hash text not null,
  nota_admin text,
  creato_da uuid not null,
  scade_at timestamptz not null,
  revocato_at timestamptz,
  revocato_da uuid,
  motivo_revoca text,
  usato_at timestamptz,
  usato_da uuid,
  partner_id uuid,
  created_at timestamptz not null default now(),

  constraint partner_inviti_token_hash_unico unique (token_hash),
  constraint partner_inviti_token_hash_forma check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint partner_inviti_email_forma check (private.partner_email_valida(email)),
  constraint partner_inviti_nota_forma check (nota_admin is null or length(nota_admin) <= 500),
  constraint partner_inviti_motivo_forma check (motivo_revoca is null or length(motivo_revoca) <= 500),
  constraint partner_inviti_scadenza check (
    scade_at > created_at and scade_at <= created_at + interval '30 days'
  ),
  constraint partner_inviti_esito_unico check (not (usato_at is not null and revocato_at is not null)),
  constraint partner_inviti_uso_coerente check (
    (usato_at is null and usato_da is null and partner_id is null)
    or (usato_at is not null and usato_da is not null and partner_id is not null)
  ),
  constraint partner_inviti_revoca_coerente check (
    (revocato_at is null and revocato_da is null and motivo_revoca is null)
    or (revocato_at is not null and revocato_da is not null)
  )
);

comment on table private.partner_inviti is
  'Inviti Partner, monouso, creati solo dall amministrazione Vinea. Legati a '
  'un indirizzo email: li accetta solo un account con quella email confermata. '
  'Token in chiaro mai memorizzato (solo sha256). Scrivibile solo dalle porte '
  'partner_* tramite il marcatore vinea.partner_porta; mai cancellabile.';

create index partner_inviti_email_idx on private.partner_inviti (email, created_at desc);
create index partner_inviti_created_idx on private.partner_inviti (created_at desc);

create table private.partners (
  id uuid primary key default gen_random_uuid(),
  titolare_id uuid not null references public.profiles (id) on delete restrict,
  invito_id uuid not null references private.partner_inviti (id) on delete restrict,
  stato public.partner_stato not null default 'invitato',

  -- Identita aziendale dichiarata dal titolare. Nulli ammessi solo in bozza
  -- (`invitato`); il vincolo partners_dati_completi li pretende altrove.
  ragione_sociale text,
  nome_commerciale text,
  partita_iva text,
  paese text not null default 'IT',
  sede_indirizzo text,
  sede_cap text,
  sede_citta text,
  sede_provincia text,
  email_commerciale text,
  tipologia public.partner_tipologia,

  -- Marcature del ciclo di vita: le scrive il trigger, non le porte.
  inviato_verifica_at timestamptz,
  attivo_dal timestamptz,
  sospeso_at timestamptz,
  revocato_at timestamptz,
  ultimo_motivo text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint partners_invito_unico unique (invito_id),
  constraint partners_paese_italia check (paese = 'IT'),
  constraint partners_ragione_sociale_forma check (
    ragione_sociale is null or length(btrim(ragione_sociale)) between 2 and 200),
  constraint partners_nome_commerciale_forma check (
    nome_commerciale is null or length(btrim(nome_commerciale)) between 2 and 120),
  constraint partners_partita_iva_forma check (
    partita_iva is null or private.partita_iva_valida(partita_iva)),
  constraint partners_sede_indirizzo_forma check (
    sede_indirizzo is null or length(btrim(sede_indirizzo)) between 3 and 200),
  constraint partners_sede_cap_forma check (sede_cap is null or sede_cap ~ '^[0-9]{5}$'),
  constraint partners_sede_citta_forma check (
    sede_citta is null or length(btrim(sede_citta)) between 2 and 100),
  constraint partners_sede_provincia_forma check (
    sede_provincia is null or sede_provincia ~ '^[A-Z]{2}$'),
  constraint partners_email_commerciale_forma check (
    email_commerciale is null or private.partner_email_valida(email_commerciale)),
  constraint partners_motivo_forma check (ultimo_motivo is null or length(ultimo_motivo) <= 500),
  constraint partners_dati_completi check (
    stato = 'invitato'::public.partner_stato
    or (ragione_sociale is not null and nome_commerciale is not null
        and partita_iva is not null and sede_indirizzo is not null
        and sede_cap is not null and sede_citta is not null
        and sede_provincia is not null and email_commerciale is not null
        and tipologia is not null)
  )
);

comment on table private.partners is
  'Partner Vinea (operatori commerciali). Un amministratore per attivita: il '
  'titolare. Classe commerciale distinta dalle qualifiche personali. Nessun '
  'grant client; letture e scritture solo dalle porte partner_*.';

-- Un solo Partner non revocato per titolare; dopo una revoca si puo essere
-- invitati di nuovo.
create unique index partners_titolare_aperto_unico
  on private.partners (titolare_id)
  where stato <> 'revocato'::public.partner_stato;

-- Una partita IVA appartiene a un solo Partner consegnato e non revocato.
create unique index partners_partita_iva_unica
  on private.partners (partita_iva)
  where stato in ('in_verifica'::public.partner_stato,
                  'attivo'::public.partner_stato,
                  'sospeso'::public.partner_stato);

create index partners_stato_idx on private.partners (stato, updated_at desc);

alter table private.partner_inviti
  add constraint partner_inviti_partner_fk
  foreign key (partner_id) references private.partners (id) on delete restrict;

-- Registro append-only: ogni creazione, uso, revoca di invito e ogni
-- movimento di stato o di dati di un Partner. Lo scrivono i trigger, quindi
-- anche un writer privilegiato lascia traccia.
create table private.partner_eventi (
  id bigint generated always as identity primary key,
  partner_id uuid references private.partners (id) on delete restrict,
  invito_id uuid references private.partner_inviti (id) on delete restrict,
  evento text not null,
  da_stato public.partner_stato,
  a_stato public.partner_stato,
  attore_id uuid,
  porta text,
  motivo text,
  dettagli jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint partner_eventi_evento_forma check (evento in (
    'invito_creato', 'invito_usato', 'invito_revocato',
    'partner_creato', 'dati_aggiornati', 'stato_cambiato'
  )),
  constraint partner_eventi_porta_forma check (porta is null or porta in ('admin', 'titolare')),
  constraint partner_eventi_soggetto check (partner_id is not null or invito_id is not null),
  constraint partner_eventi_dettagli_oggetto check (jsonb_typeof(dettagli) = 'object')
);

comment on table private.partner_eventi is
  'Audit append-only del programma Partner. Non contiene valori dei dati '
  'aziendali: per dati_aggiornati registra solo i nomi dei campi cambiati.';

create index partner_eventi_partner_idx on private.partner_eventi (partner_id, created_at);
create index partner_eventi_invito_idx on private.partner_eventi (invito_id, created_at);

alter table private.partner_inviti enable row level security;
alter table private.partners enable row level security;
alter table private.partner_eventi enable row level security;

revoke all on private.partner_inviti from public, anon, authenticated;
revoke all on private.partners from public, anon, authenticated;
revoke all on private.partner_eventi from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Marcatore dedicato della porta
-- ---------------------------------------------------------------------------
--
-- `vinea.partner_porta` vale `<porta>:<oggetto>:<uuid>`, per esempio
-- `admin:partner:<id>` o `titolare:invito:<id>`. Lo imposta solo una porta,
-- con `set_config(..., true)` (vita: la transazione), immediatamente prima
-- della sua scrittura, e lo azzera subito dopo. Il trigger lo confronta con
-- la riga che sta scrivendo: un marcatore aperto per una riga non autorizza
-- un'altra riga, e un marcatore da titolare non autorizza un esito admin.
-- Non e `vinea.pq_review`: quel marcatore appartiene alle qualifiche personali
-- e non apre nulla qui.

create function private.partner_porta_corrente()
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(current_setting('vinea.partner_porta', true), '');
$$;

revoke execute on function private.partner_porta_corrente()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [5] Guardiani
-- ---------------------------------------------------------------------------

create function private.partner_inviti_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_porta text := private.partner_porta_corrente();
begin
  if tg_op = 'DELETE' then
    raise exception 'Un invito Partner non si cancella.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if v_porta <> 'admin:invito:' || new.id::text then
      raise exception 'Un invito Partner si crea solo con partner_admin_invito_crea.'
        using errcode = '42501';
    end if;
    if new.usato_at is not null or new.revocato_at is not null then
      raise exception 'Un invito nasce valido.' using errcode = '42501';
    end if;
    new.created_at := now();
    return new;
  end if;

  -- UPDATE. I dati d'origine non cambiano mai.
  if (new.id, new.email, new.token_hash, new.creato_da, new.scade_at,
      new.created_at, new.nota_admin)
     is distinct from
     (old.id, old.email, old.token_hash, old.creato_da, old.scade_at,
      old.created_at, old.nota_admin)
  then
    raise exception 'I dati di un invito Partner non si modificano.' using errcode = '42501';
  end if;

  -- Un esito e definitivo: un invito usato o revocato non si tocca piu.
  if old.usato_at is not null or old.revocato_at is not null then
    raise exception 'Invito gia usato o revocato.' using errcode = '42501';
  end if;

  if new.usato_at is not null then
    if v_porta <> 'titolare:invito:' || new.id::text then
      raise exception 'Un invito si usa solo con partner_invito_accetta.' using errcode = '42501';
    end if;
    new.usato_at := now();
  elsif new.revocato_at is not null then
    if v_porta <> 'admin:invito:' || new.id::text then
      raise exception 'Un invito si revoca solo con partner_admin_invito_revoca.' using errcode = '42501';
    end if;
    new.revocato_at := now();
  else
    raise exception 'Aggiornamento di invito senza esito non ammesso.' using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function private.partner_inviti_guard() from public, anon, authenticated;

create trigger partner_inviti_guard
  before insert or update or delete on private.partner_inviti
  for each row execute function private.partner_inviti_guard();

create function private.partners_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_porta text := private.partner_porta_corrente();
  v_admin boolean;
  v_titolare boolean;
  v_da public.partner_stato;
  v_a public.partner_stato;
  v_dati_cambiati boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'Un Partner non si cancella: si revoca.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if v_porta <> 'titolare:partner:' || new.id::text then
      raise exception 'Un Partner nasce solo da partner_invito_accetta.' using errcode = '42501';
    end if;
    if new.stato <> 'invitato'::public.partner_stato
       or new.inviato_verifica_at is not null or new.attivo_dal is not null
       or new.sospeso_at is not null or new.revocato_at is not null
       or new.ultimo_motivo is not null
    then
      raise exception 'Un Partner nasce invitato e senza esiti.' using errcode = '42501';
    end if;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  v_admin := v_porta = 'admin:partner:' || old.id::text;
  v_titolare := v_porta = 'titolare:partner:' || old.id::text;
  v_da := old.stato;
  v_a := new.stato;

  if not (v_admin or v_titolare) then
    raise exception 'Un Partner si modifica solo dalle porte partner_*.' using errcode = '42501';
  end if;

  if (new.id, new.titolare_id, new.invito_id, new.created_at)
     is distinct from (old.id, old.titolare_id, old.invito_id, old.created_at)
  then
    raise exception 'Identita del Partner immutabile.' using errcode = '42501';
  end if;

  if v_da = 'revocato'::public.partner_stato then
    raise exception 'Un Partner revocato non si modifica.' using errcode = '42501';
  end if;

  -- Le marcature non si scrivono dalle porte: le gestisce questo trigger.
  if (new.inviato_verifica_at, new.attivo_dal, new.sospeso_at, new.revocato_at)
     is distinct from
     (old.inviato_verifica_at, old.attivo_dal, old.sospeso_at, old.revocato_at)
  then
    raise exception 'Le marcature del ciclo di vita non si scrivono a mano.' using errcode = '42501';
  end if;

  v_dati_cambiati :=
    (new.ragione_sociale, new.nome_commerciale, new.partita_iva, new.paese,
     new.sede_indirizzo, new.sede_cap, new.sede_citta, new.sede_provincia,
     new.email_commerciale, new.tipologia)
    is distinct from
    (old.ragione_sociale, old.nome_commerciale, old.partita_iva, old.paese,
     old.sede_indirizzo, old.sede_cap, old.sede_citta, old.sede_provincia,
     old.email_commerciale, old.tipologia);

  if v_titolare then
    -- Il titolare compila i dati solo in bozza e puo soltanto consegnarli.
    if v_dati_cambiati and v_da <> 'invitato'::public.partner_stato then
      raise exception 'I dati aziendali consegnati non si modificano.' using errcode = '42501';
    end if;
    if v_a <> v_da and not (v_da = 'invitato'::public.partner_stato
                            and v_a = 'in_verifica'::public.partner_stato) then
      raise exception 'Transizione non ammessa per il titolare: da % a %.', v_da, v_a
        using errcode = '42501';
    end if;
    if new.ultimo_motivo is distinct from old.ultimo_motivo then
      raise exception 'Il motivo lo scrive solo l amministrazione.' using errcode = '42501';
    end if;
  else
    -- L'amministrazione decide lo stato, non riscrive la dichiarazione.
    if v_dati_cambiati then
      raise exception 'L amministrazione non modifica i dati dichiarati.' using errcode = '42501';
    end if;
    if not (
      (v_da = 'in_verifica'::public.partner_stato
        and v_a in ('attivo'::public.partner_stato, 'invitato'::public.partner_stato))
      or (v_da = 'attivo'::public.partner_stato and v_a = 'sospeso'::public.partner_stato)
      or (v_da = 'sospeso'::public.partner_stato and v_a = 'attivo'::public.partner_stato)
      or (v_a = 'revocato'::public.partner_stato)
    ) then
      raise exception 'Transizione non ammessa per l amministrazione: da % a %.', v_da, v_a
        using errcode = '42501';
    end if;
  end if;

  -- Marcature, scritte qui e solo qui.
  if v_a <> v_da then
    case v_a
      when 'in_verifica'::public.partner_stato then
        new.inviato_verifica_at := now();
      when 'invitato'::public.partner_stato then
        new.inviato_verifica_at := null;
      when 'attivo'::public.partner_stato then
        new.attivo_dal := coalesce(old.attivo_dal, now());
        new.sospeso_at := null;
      when 'sospeso'::public.partner_stato then
        new.sospeso_at := now();
      when 'revocato'::public.partner_stato then
        new.revocato_at := now();
    end case;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

comment on function private.partners_guard() is
  'Ciclo di vita autoritativo del Partner. Pretende il marcatore dedicato '
  'vinea.partner_porta legato alla riga e alla porta (titolare/admin), ammette '
  'solo le transizioni dichiarate, congela i dati dopo la consegna e rende '
  'revocato terminale. Vincola anche service_role.';

revoke execute on function private.partners_guard() from public, anon, authenticated;

create trigger partners_guard
  before insert or update or delete on private.partners
  for each row execute function private.partners_guard();

-- Truncate: stessa regola, per l'intera tabella.
create function private.partner_no_truncate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Le tabelle del programma Partner non si svuotano.' using errcode = '42501';
end;
$$;

revoke execute on function private.partner_no_truncate() from public, anon, authenticated;

create trigger partner_inviti_no_truncate
  before truncate on private.partner_inviti
  for each statement execute function private.partner_no_truncate();
create trigger partners_no_truncate
  before truncate on private.partners
  for each statement execute function private.partner_no_truncate();
create trigger partner_eventi_no_truncate
  before truncate on private.partner_eventi
  for each statement execute function private.partner_no_truncate();

create function private.partner_eventi_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro Partner e append-only.' using errcode = '42501';
end;
$$;

revoke execute on function private.partner_eventi_append_only() from public, anon, authenticated;

create trigger partner_eventi_no_update
  before update or delete on private.partner_eventi
  for each row execute function private.partner_eventi_append_only();

-- ---------------------------------------------------------------------------
-- [6] Audit scritto dai trigger
-- ---------------------------------------------------------------------------

create function private.partner_porta_tipo()
returns text
language sql
stable
set search_path = ''
as $$
  select case split_part(private.partner_porta_corrente(), ':', 1)
           when 'admin' then 'admin'
           when 'titolare' then 'titolare'
         end;
$$;

revoke execute on function private.partner_porta_tipo() from public, anon, authenticated;

create function private.partner_inviti_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into private.partner_eventi (invito_id, evento, attore_id, porta, dettagli)
    values (new.id, 'invito_creato', auth.uid(), private.partner_porta_tipo(),
            jsonb_build_object('scade_at', new.scade_at));
  elsif new.usato_at is not null and old.usato_at is null then
    insert into private.partner_eventi (invito_id, partner_id, evento, attore_id, porta)
    values (new.id, new.partner_id, 'invito_usato', auth.uid(), private.partner_porta_tipo());
  elsif new.revocato_at is not null and old.revocato_at is null then
    insert into private.partner_eventi (invito_id, evento, attore_id, porta, motivo)
    values (new.id, 'invito_revocato', auth.uid(), private.partner_porta_tipo(), new.motivo_revoca);
  end if;
  return null;
end;
$$;

revoke execute on function private.partner_inviti_audit() from public, anon, authenticated;

create trigger partner_inviti_audit
  after insert or update on private.partner_inviti
  for each row execute function private.partner_inviti_audit();

create function private.partners_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campi text[] := array[]::text[];
begin
  if tg_op = 'INSERT' then
    insert into private.partner_eventi (partner_id, invito_id, evento, a_stato, attore_id, porta)
    values (new.id, new.invito_id, 'partner_creato', new.stato, auth.uid(), private.partner_porta_tipo());
    return null;
  end if;

  if new.ragione_sociale is distinct from old.ragione_sociale then v_campi := array_append(v_campi, 'ragione_sociale'::text); end if;
  if new.nome_commerciale is distinct from old.nome_commerciale then v_campi := array_append(v_campi, 'nome_commerciale'::text); end if;
  if new.partita_iva is distinct from old.partita_iva then v_campi := array_append(v_campi, 'partita_iva'::text); end if;
  if new.sede_indirizzo is distinct from old.sede_indirizzo then v_campi := array_append(v_campi, 'sede_indirizzo'::text); end if;
  if new.sede_cap is distinct from old.sede_cap then v_campi := array_append(v_campi, 'sede_cap'::text); end if;
  if new.sede_citta is distinct from old.sede_citta then v_campi := array_append(v_campi, 'sede_citta'::text); end if;
  if new.sede_provincia is distinct from old.sede_provincia then v_campi := array_append(v_campi, 'sede_provincia'::text); end if;
  if new.email_commerciale is distinct from old.email_commerciale then v_campi := array_append(v_campi, 'email_commerciale'::text); end if;
  if new.tipologia is distinct from old.tipologia then v_campi := array_append(v_campi, 'tipologia'::text); end if;

  if cardinality(v_campi) > 0 then
    insert into private.partner_eventi (partner_id, evento, attore_id, porta, dettagli)
    values (new.id, 'dati_aggiornati', auth.uid(), private.partner_porta_tipo(),
            jsonb_build_object('campi', to_jsonb(v_campi)));
  end if;

  if new.stato <> old.stato then
    insert into private.partner_eventi (partner_id, evento, da_stato, a_stato, attore_id, porta, motivo)
    values (new.id, 'stato_cambiato', old.stato, new.stato, auth.uid(), private.partner_porta_tipo(),
            new.ultimo_motivo);
  end if;

  return null;
end;
$$;

revoke execute on function private.partners_audit() from public, anon, authenticated;

create trigger partners_audit
  after insert or update on private.partners
  for each row execute function private.partners_audit();

-- ---------------------------------------------------------------------------
-- [7] Aiutanti delle porte
-- ---------------------------------------------------------------------------

-- Identita admin dal database, non da un claim. Stessa forma delle porte MV3.
create function private.partner_admin_richiesto()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_uid and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

revoke execute on function private.partner_admin_richiesto() from public, anon, authenticated;

create function private.partner_motivo_pulito(p_motivo text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if v is not null and length(v) > 500 then
    raise exception 'Motivo troppo lungo (massimo 500 caratteri).' using errcode = '22023';
  end if;
  return v;
end;
$$;

revoke execute on function private.partner_motivo_pulito(text) from public, anon, authenticated;

-- Proiezione del Partner per il titolare e per l'amministrazione.
create function private.partner_json(p private.partners)
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
    'updated_at', p.updated_at
  );
$$;

revoke execute on function private.partner_json(private.partners) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [8] Porte
-- ---------------------------------------------------------------------------

-- 8.1 Amministrazione: crea un invito. Restituisce il token in chiaro UNA
-- volta; non si recupera piu.
create function public.partner_admin_invito_crea(
  p_email text,
  p_validita_giorni integer default 14,
  p_nota text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
  v_id uuid := gen_random_uuid();
  v_token text;
  v_scade timestamptz;
begin
  if not private.partner_email_valida(v_email) then
    raise exception 'Email non valida.' using errcode = '22023';
  end if;
  if p_validita_giorni is null or p_validita_giorni not between 1 and 30 then
    raise exception 'La validita va da 1 a 30 giorni.' using errcode = '22023';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'Nota troppo lunga (massimo 500 caratteri).' using errcode = '22023';
  end if;

  -- Nessun invito a se stessi: un amministratore non apre il proprio Partner.
  if exists (select 1 from auth.users u where u.id = v_admin and lower(u.email) = v_email) then
    raise exception 'Un amministratore non invita il proprio indirizzo.' using errcode = '42501';
  end if;

  -- Serializza le creazioni concorrenti per la stessa email.
  perform pg_advisory_xact_lock(hashtextextended('vinea.partner_invito:' || v_email, 0));

  if exists (
    select 1 from private.partner_inviti i
    where i.email = v_email and i.usato_at is null and i.revocato_at is null
      and i.scade_at > now()
  ) then
    raise exception 'Esiste gia un invito valido per questa email: revocalo prima.'
      using errcode = 'P0001', hint = 'invito_gia_valido';
  end if;

  if exists (
    select 1 from private.partners p
    join auth.users u on u.id = p.titolare_id
    where lower(u.email) = v_email and p.stato <> 'revocato'::public.partner_stato
  ) then
    raise exception 'Questo indirizzo ha gia un Partner aperto.'
      using errcode = 'P0001', hint = 'partner_gia_presente';
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_scade := now() + make_interval(days => p_validita_giorni);

  perform set_config('vinea.partner_porta', 'admin:invito:' || v_id::text, true);
  insert into private.partner_inviti (id, email, token_hash, nota_admin, creato_da, scade_at)
  values (v_id, v_email, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_nota, v_admin, v_scade);
  perform set_config('vinea.partner_porta', '', true);

  return jsonb_build_object('invito_id', v_id, 'token', v_token, 'scade_at', v_scade, 'email', v_email);
end;
$$;

comment on function public.partner_admin_invito_crea(text, integer, text) is
  'Solo admin (user_roles). Crea un invito Partner monouso legato all email, '
  'valido 1-30 giorni. Il token in chiaro esce solo qui, una volta.';

-- 8.2 Amministrazione: revoca un invito non ancora usato. Idempotente.
create function public.partner_admin_invito_revoca(
  p_invito_id uuid,
  p_motivo text default null
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
  v_motivo text := private.partner_motivo_pulito(p_motivo);
  v_invito private.partner_inviti%rowtype;
begin
  select * into v_invito from private.partner_inviti where id = p_invito_id for update;
  if v_invito.id is null then
    raise exception 'Invito non trovato.' using errcode = 'P0001', hint = 'invito_non_trovato';
  end if;
  if v_invito.revocato_at is not null then
    return 'revocato';
  end if;
  if v_invito.usato_at is not null then
    raise exception 'Invito gia usato: si revoca il Partner, non l invito.'
      using errcode = 'P0001', hint = 'invito_usato';
  end if;

  perform set_config('vinea.partner_porta', 'admin:invito:' || v_invito.id::text, true);
  update private.partner_inviti
  set revocato_at = now(), revocato_da = v_admin, motivo_revoca = v_motivo
  where id = v_invito.id;
  perform set_config('vinea.partner_porta', '', true);

  return 'revocato';
end;
$$;

-- 8.3 Amministrazione: elenco inviti. Mai il token ne il suo hash.
create function public.partner_admin_inviti(p_limite integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
begin
  return coalesce((
    select jsonb_agg(x.riga order by x.created_at desc)
    from (
      select i.created_at, jsonb_build_object(
        'id', i.id,
        'email', i.email,
        'stato', case
                   when i.revocato_at is not null then 'revocato'
                   when i.usato_at is not null then 'usato'
                   when i.scade_at <= now() then 'scaduto'
                   else 'valido'
                 end,
        'scade_at', i.scade_at,
        'created_at', i.created_at,
        'usato_at', i.usato_at,
        'revocato_at', i.revocato_at,
        'motivo_revoca', i.motivo_revoca,
        'nota_admin', i.nota_admin,
        'partner_id', i.partner_id
      ) as riga
      from private.partner_inviti i
      order by i.created_at desc
      limit greatest(1, least(coalesce(p_limite, 100), 500))
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 8.4 Amministrazione: elenco Partner con titolare.
create function public.partner_admin_elenco(
  p_stato public.partner_stato default null,
  p_limite integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
begin
  return coalesce((
    select jsonb_agg(x.riga order by x.updated_at desc)
    from (
      select p.updated_at,
        private.partner_json(p) || jsonb_build_object(
          'titolare_id', p.titolare_id,
          'titolare_email', u.email,
          'titolare_username', pr.username,
          'invito_email', i.email
        ) as riga
      from private.partners p
      join private.partner_inviti i on i.id = p.invito_id
      left join auth.users u on u.id = p.titolare_id
      left join public.profiles pr on pr.id = p.titolare_id
      where p_stato is null or p.stato = p_stato
      order by p.updated_at desc
      limit greatest(1, least(coalesce(p_limite, 200), 500))
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 8.5 Amministrazione: decisione sullo stato di un Partner.
--   approva      in_verifica -> attivo
--   restituisci  in_verifica -> invitato   (motivo obbligatorio)
--   sospendi     attivo      -> sospeso    (motivo obbligatorio)
--   riattiva     sospeso     -> attivo
--   revoca       qualunque non revocato -> revocato (motivo obbligatorio)
-- Una ripetizione verso lo stato gia raggiunto risponde senza scrivere; ogni
-- altra combinazione e rifiutata, mai ignorata.
create function public.partner_admin_decidi(
  p_partner_id uuid,
  p_azione text,
  p_motivo text default null
)
returns public.partner_stato
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.partner_admin_richiesto();
  v_motivo text := private.partner_motivo_pulito(p_motivo);
  v_p private.partners%rowtype;
  v_da public.partner_stato[];
  v_a public.partner_stato;
begin
  case p_azione
    when 'approva' then
      v_da := array['in_verifica']::public.partner_stato[]; v_a := 'attivo';
    when 'restituisci' then
      v_da := array['in_verifica']::public.partner_stato[]; v_a := 'invitato';
    when 'sospendi' then
      v_da := array['attivo']::public.partner_stato[]; v_a := 'sospeso';
    when 'riattiva' then
      v_da := array['sospeso']::public.partner_stato[]; v_a := 'attivo';
    when 'revoca' then
      v_da := array['invitato', 'in_verifica', 'attivo', 'sospeso']::public.partner_stato[];
      v_a := 'revocato';
    else
      raise exception 'Azione non riconosciuta.' using errcode = '22023';
  end case;

  if p_azione in ('restituisci', 'sospendi', 'revoca') and v_motivo is null then
    raise exception 'Questa azione richiede un motivo.' using errcode = '22023';
  end if;

  select * into v_p from private.partners where id = p_partner_id for update;
  if v_p.id is null then
    raise exception 'Partner non trovato.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;

  -- Anti-autoapprovazione: nessun amministratore decide sul proprio Partner.
  if v_p.titolare_id = v_admin then
    raise exception 'Non puoi decidere sul tuo stesso Partner.' using errcode = '42501';
  end if;

  if v_p.stato = v_a then
    return v_p.stato;
  end if;

  if not (v_p.stato = any (v_da)) then
    raise exception 'Azione % non ammessa da stato %.', p_azione, v_p.stato
      using errcode = 'P0001', hint = 'transizione_non_ammessa';
  end if;

  if v_a = 'attivo'::public.partner_stato
     and private.utente_stato_di(v_p.titolare_id) = 'rimosso'::public.utente_stato then
    raise exception 'Il titolare e rimosso: il Partner non si attiva.'
      using errcode = 'P0001', hint = 'titolare_rimosso';
  end if;

  perform set_config('vinea.partner_porta', 'admin:partner:' || v_p.id::text, true);
  update private.partners
  set stato = v_a, ultimo_motivo = v_motivo
  where id = v_p.id;
  perform set_config('vinea.partner_porta', '', true);

  return v_a;
end;
$$;

comment on function public.partner_admin_decidi(uuid, text, text) is
  'Unica porta degli esiti amministrativi Partner. Solo admin, mai sul proprio '
  'Partner. Azioni chiuse; transizioni non ammesse rifiutate, non ignorate.';

-- 8.6 Titolare: accetta un invito. Il destinatario e l'account con la stessa
-- email, confermata. Concorrenza: l'invito e bloccato `for update`, quindi due
-- accettazioni parallele dello stesso token si serializzano e la seconda trova
-- l'invito usato.
create function public.partner_invito_accetta(p_token text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_token text := lower(btrim(coalesce(p_token, '')));
  v_invito private.partner_inviti%rowtype;
  v_email text;
  v_confermata timestamptz;
  v_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;
  if v_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Invito non valido.' using errcode = 'P0001', hint = 'invito_non_valido';
  end if;

  select * into v_invito
  from private.partner_inviti
  where token_hash = encode(sha256(convert_to(v_token, 'UTF8')), 'hex')
  for update;

  if v_invito.id is null then
    raise exception 'Invito non valido.' using errcode = 'P0001', hint = 'invito_non_valido';
  end if;

  -- Replay del destinatario legittimo: risponde con il Partner gia aperto.
  if v_invito.usato_at is not null then
    if v_invito.usato_da = v_uid then
      return v_invito.partner_id;
    end if;
    raise exception 'Invito gia utilizzato.' using errcode = 'P0001', hint = 'invito_usato';
  end if;
  if v_invito.revocato_at is not null then
    raise exception 'Invito revocato.' using errcode = 'P0001', hint = 'invito_revocato';
  end if;
  if v_invito.scade_at <= now() then
    raise exception 'Invito scaduto.' using errcode = 'P0001', hint = 'invito_scaduto';
  end if;

  select lower(u.email), u.email_confirmed_at into v_email, v_confermata
  from auth.users u where u.id = v_uid;

  if v_confermata is null then
    raise exception 'Conferma prima il tuo indirizzo email.'
      using errcode = '42501', hint = 'email_non_confermata';
  end if;
  if v_email is distinct from v_invito.email then
    raise exception 'Questo invito e intestato a un altro indirizzo email.'
      using errcode = '42501', hint = 'invito_email_diversa';
  end if;
  if private.utente_stato_di(v_uid) = 'rimosso'::public.utente_stato then
    raise exception 'Account non attivo.' using errcode = '42501';
  end if;
  if exists (
    select 1 from private.partners p
    where p.titolare_id = v_uid and p.stato <> 'revocato'::public.partner_stato
  ) then
    raise exception 'Hai gia un Partner aperto.' using errcode = 'P0001', hint = 'partner_gia_presente';
  end if;

  perform set_config('vinea.partner_porta', 'titolare:partner:' || v_id::text, true);
  insert into private.partners (id, titolare_id, invito_id) values (v_id, v_uid, v_invito.id);

  perform set_config('vinea.partner_porta', 'titolare:invito:' || v_invito.id::text, true);
  update private.partner_inviti
  set usato_at = now(), usato_da = v_uid, partner_id = v_id
  where id = v_invito.id;
  perform set_config('vinea.partner_porta', '', true);

  return v_id;
end;
$$;

-- 8.7 Titolare: il proprio Partner (aperto, altrimenti l'ultimo revocato).
create function public.partner_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;
  return (
    select private.partner_json(p)
    from private.partners p
    where p.titolare_id = v_uid
    order by (p.stato = 'revocato'::public.partner_stato), p.created_at desc
    limit 1
  );
end;
$$;

-- 8.8 Titolare: compila i dati aziendali, solo in bozza. Salvataggio parziale
-- ammesso; i valori presenti devono essere validi.
create function public.partner_dati_aggiorna(
  p_ragione_sociale text,
  p_nome_commerciale text,
  p_partita_iva text,
  p_email_commerciale text,
  p_tipologia public.partner_tipologia,
  p_sede_indirizzo text,
  p_sede_cap text,
  p_sede_citta text,
  p_sede_provincia text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p private.partners%rowtype;
  v_piva text := nullif(regexp_replace(coalesce(p_partita_iva, ''), '[[:space:]]', '', 'g'), '');
  v_email text := nullif(lower(btrim(coalesce(p_email_commerciale, ''))), '');
  v_prov text := nullif(upper(btrim(coalesce(p_sede_provincia, ''))), '');
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select * into v_p from private.partners
  where titolare_id = v_uid and stato <> 'revocato'::public.partner_stato
  for update;

  if v_p.id is null then
    raise exception 'Nessun Partner aperto.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  if v_p.stato <> 'invitato'::public.partner_stato then
    raise exception 'I dati si modificano solo prima della consegna.'
      using errcode = 'P0001', hint = 'dati_congelati';
  end if;

  if v_piva is not null and v_piva like 'IT%' then
    v_piva := substr(v_piva, 3);
  end if;
  if v_piva is not null and not private.partita_iva_valida(v_piva) then
    raise exception 'Partita IVA non valida.' using errcode = '22023';
  end if;
  if v_email is not null and not private.partner_email_valida(v_email) then
    raise exception 'Email commerciale non valida.' using errcode = '22023';
  end if;

  perform set_config('vinea.partner_porta', 'titolare:partner:' || v_p.id::text, true);
  begin
    update private.partners
    set ragione_sociale = nullif(btrim(coalesce(p_ragione_sociale, '')), ''),
        nome_commerciale = nullif(btrim(coalesce(p_nome_commerciale, '')), ''),
        partita_iva = v_piva,
        email_commerciale = v_email,
        tipologia = p_tipologia,
        sede_indirizzo = nullif(btrim(coalesce(p_sede_indirizzo, '')), ''),
        sede_cap = nullif(btrim(coalesce(p_sede_cap, '')), ''),
        sede_citta = nullif(btrim(coalesce(p_sede_citta, '')), ''),
        sede_provincia = v_prov
    where id = v_p.id
    returning * into v_p;
  exception when check_violation then
    raise exception 'Dati aziendali non validi.' using errcode = '22023';
  end;
  perform set_config('vinea.partner_porta', '', true);

  return private.partner_json(v_p);
end;
$$;

-- 8.9 Titolare: consegna i dati alla verifica.
create function public.partner_invia_verifica()
returns public.partner_stato
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p private.partners%rowtype;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select * into v_p from private.partners
  where titolare_id = v_uid and stato <> 'revocato'::public.partner_stato
  for update;

  if v_p.id is null then
    raise exception 'Nessun Partner aperto.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  if v_p.stato = 'in_verifica'::public.partner_stato then
    return v_p.stato;
  end if;
  if v_p.stato <> 'invitato'::public.partner_stato then
    raise exception 'Richiesta gia esaminata.' using errcode = 'P0001', hint = 'transizione_non_ammessa';
  end if;

  perform set_config('vinea.partner_porta', 'titolare:partner:' || v_p.id::text, true);
  begin
    update private.partners set stato = 'in_verifica' where id = v_p.id;
  exception
    when check_violation then
      raise exception 'Completa tutti i dati aziendali prima di inviarli.'
        using errcode = '22023', hint = 'dati_incompleti';
    when unique_violation then
      raise exception 'Questa partita IVA e gia registrata per un altro Partner.'
        using errcode = 'P0001', hint = 'partita_iva_gia_registrata';
  end;
  perform set_config('vinea.partner_porta', '', true);

  return 'in_verifica'::public.partner_stato;
end;
$$;

-- Grant: tutte le porte a `authenticated` soltanto. Le porte admin rifiutano
-- da sole chi non e admin; anon e service_role non le eseguono.
do $$
declare
  v_firma text;
begin
  foreach v_firma in array array[
    'public.partner_admin_invito_crea(text, integer, text)',
    'public.partner_admin_invito_revoca(uuid, text)',
    'public.partner_admin_inviti(integer)',
    'public.partner_admin_elenco(public.partner_stato, integer)',
    'public.partner_admin_decidi(uuid, text, text)',
    'public.partner_invito_accetta(text)',
    'public.partner_me()',
    'public.partner_dati_aggiorna(text, text, text, text, public.partner_tipologia, text, text, text, text)',
    'public.partner_invia_verifica()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_firma);
    execute format('grant execute on function %s to authenticated', v_firma);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- [9] Gate: nessun checkout professionale prima dei blocchi dipendenti
-- ---------------------------------------------------------------------------
--
-- Stessa forma di private.commercio_rimosso_guard (Fase 9): un trigger sulla
-- tabella invece di riscrivere order_checkout_reserve. Un Partner attivo o
-- sospeso e un operatore commerciale; venderebbe alle condizioni dei privati
-- (8%), che non sono le sue. Finche il checkout professionale non esiste, il
-- suo nuovo ordine e rifiutato prima di qualunque pagamento. Gli ordini gia
-- esistenti non sono toccati; i privati, gli invitati e chi e in verifica non
-- sono toccati.

create function private.partner_checkout_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.partners p
    where p.titolare_id = new.seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  ) then
    raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
      using errcode = '42501', hint = 'partner_checkout_non_disponibile';
  end if;
  return new;
end;
$$;

comment on function private.partner_checkout_gate() is
  'Blocco A Partner: nessun nuovo ordine con venditore Partner attivo o '
  'sospeso finche il checkout professionale (blocchi successivi) non esiste.';

revoke execute on function private.partner_checkout_gate() from public, anon, authenticated;

create trigger orders_partner_checkout_gate
  before insert on public.orders
  for each row execute function private.partner_checkout_gate();

-- ---------------------------------------------------------------------------
-- [10] Superficie pubblicabile
-- ---------------------------------------------------------------------------
--
-- Separazione fra dati pubblicabili e amministrativi: solo i Partner attivi,
-- elenco colonne chiuso, nessun titolare, nessuna partita IVA, nessun
-- indirizzo. `security_invoker = off` come le altre viste public_* (eccezione
-- lint 0010 accettata e registrata in CONTESTO_IA/03).

create view public.public_partners
with (security_invoker = off, security_barrier = true)
as
select
  p.id,
  p.nome_commerciale,
  p.tipologia,
  p.sede_citta,
  p.sede_provincia,
  p.paese,
  p.attivo_dal
from private.partners p
where p.stato = 'attivo'::public.partner_stato;

comment on view public.public_partners is
  'Partner attivi, colonne pubblicabili chiuse. Una colonna aggiunta a '
  'private.partners resta privata finche non viene esposta qui di proposito.';

revoke all on public.public_partners from public, anon, authenticated;
grant select on public.public_partners to anon, authenticated;

notify pgrst, 'reload schema';
