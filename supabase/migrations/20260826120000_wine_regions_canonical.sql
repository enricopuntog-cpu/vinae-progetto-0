-- D2 — Fondazione canonica della Regione del vino.
--
-- Migrazione additiva. Non modifica nessun file gia distribuito: le funzioni
-- storiche che devono cambiare comportamento vengono sostituite qui con
-- `create or replace`, come prescrive la costituzione per un file gia spinto.
--
-- IL PROBLEMA CHE CHIUDE. `public.wines.regione` e sempre stato `text not null`
-- con il solo vincolo `length(trim(regione)) > 0`: qualunque stringa non vuota
-- era una regione valida. Il wizard `/vendi` la raccoglie come testo libero,
-- `/esplora` filtra su una lista cablata nel componente, e le due liste non si
-- sono mai parlate. Il risultato misurabile in produzione e che esistono righe
-- come `Toscanaa` e `ciao`: la prima e un refuso che spezza il filtro della
-- regione giusta, la seconda non e una regione. Nessuna delle due e visibile
-- come difetto finche qualcuno non filtra.
--
-- COSA FA, IN ORDINE E PER UNA RAGIONE:
--   [1] crea la tassonomia persistente `public.wine_regions`;
--   [2] la popola con le sole regioni gia sostenute dal prodotto;
--   [3] normalizza i valori legacy deterministici;
--   [4] verifica che non resti nulla di non canonico, e ABORTISCE se resta;
--   [5] vincola `wines.regione` alla tassonomia con una FK VALIDATA;
--   [6] insegna al writer autorevole a canonicalizzare invece di far esplodere
--       una violazione di chiave esterna in faccia al wizard.
--
-- L'ordine non e estetico. La FK del punto [5] non puo essere validata prima
-- del backfill del punto [3], e il punto [4] esiste perche una migrazione che
-- si limitasse a normalizzare i due valori noti fallirebbe in modo oscuro alla
-- validazione se in produzione, nel frattempo, fosse comparso un terzo valore
-- non previsto. Meglio un errore che dice quale.
--
-- COSA NON FA, DELIBERATAMENTE. Nessun selettore in `/vendi`, nessun cambio al
-- filtro di `/esplora`, nessuna modifica alla ricerca testuale e nessuna
-- traduzione delle regioni suggerite dall'AI (`Tuscany` resta `Tuscany` e viene
-- rifiutata): quella e la superficie del pacchetto successivo, che poggera su
-- questa tassonomia invece di crearne una seconda. Il campo regione del wizard
-- resta un campo di testo libero fino ad allora.
--
-- COSA NON TOCCA. RLS, policy e GRANT di `wines`, `bottle_units` e `listings`
-- restano esattamente quelli che erano: nessun privilegio allargato, nessuna
-- policy riscritta. Una chiave esterna non richiede privilegi al chiamante —
-- il controllo di integrita referenziale gira per conto del proprietario del
-- vincolo e non passa dalla RLS — quindi vincolare la colonna non ha richiesto
-- di aprire nulla.

-- ---------------------------------------------------------------------------
-- [1] wine_regions — la tassonomia canonica
-- ---------------------------------------------------------------------------
-- TABELLA E NON ENUM, e la scelta e il punto di tutto il pacchetto. Un tipo
-- enumerato sembra il modo naturale di dire "solo questi valori", ma allargarlo
-- costa una migrazione ogni volta, e questa lista e destinata a crescere: oggi
-- copre l'Italia piu Champagne perche e cio che il prodotto sostiene davvero,
-- domani coprira le denominazioni che il catalogo incontrera. Con una tabella,
-- aggiungere una regione e un INSERT; con un enum sarebbe un ALTER TYPE.
--
-- IL NOME E LA CHIAVE PRIMARIA, non un id sintetico con un nome accanto. E la
-- forma che rende possibile vincolare `wines.regione` — che e `text` e resta
-- `text` — senza aggiungere una colonna alla tabella, senza riscrivere le
-- cinque viste pubbliche che gia proiettano `w.regione`, e senza toccare il
-- contratto TypeScript in cui la regione e una stringa. Una chiave sintetica
-- avrebbe imposto una JOIN a ogni lettura per ottenere lo stesso testo.
--
-- La chiave testuale distingue pero `Toscana` da `toscana`, mentre il writer le
-- considera equivalenti. L'indice univoco sull'espressione `lower(nome)` chiude
-- quella fessura allo stesso livello del dato: non possono esistere due forme
-- canoniche che il resolver non saprebbe distinguere.

create table public.wine_regions (
  nome text primary key check (length(btrim(nome)) > 0 and nome = btrim(nome)),
  -- Ordinamento stabile per la UI che verra. Non e unico di proposito: se un
  -- domani una regione va inserita fra due esistenti, con un vincolo di
  -- unicita bisognerebbe rinumerare la tabella per fare posto. Le letture
  -- ordinano per `(ordine, nome)`, quindi due valori uguali restano comunque
  -- deterministici.
  ordine smallint not null default 1000 check (ordine >= 0),
  created_at timestamptz not null default now()
);

create unique index wine_regions_nome_lower_key
  on public.wine_regions (lower(nome));

comment on table public.wine_regions is
  'Tassonomia canonica delle regioni del vino. Unica fonte di verita per la '
  'regione di una scheda vino: `public.wines.regione` la referenzia con una '
  'chiave esterna validata. Cresce per INSERT, mai per ALTER di tipo.';
comment on column public.wine_regions.nome is
  'Nome canonico, chiave primaria. E il valore letterale memorizzato in '
  'public.wines.regione: nessuna JOIN necessaria per leggerlo.';
comment on column public.wine_regions.ordine is
  'Ordinamento di presentazione. Non unico: le letture ordinano per '
  '(ordine, nome), che resta deterministico anche a parita di ordine.';

-- I privilegi si azzerano prima di concederli, per la stessa ragione della
-- Fase 6a: nei progetti Supabase esistono ALTER DEFAULT PRIVILEGES che
-- assegnerebbero automaticamente ad `anon` e `authenticated` ogni permesso su
-- una nuova tabella di `public`. Senza questa revoca il GRANT mirato qui sotto
-- sarebbe decorativo e il browser avrebbe INSERT sulla tassonomia.
revoke all on public.wine_regions from anon, authenticated;
grant select on public.wine_regions to anon, authenticated;
-- Nessun INSERT, UPDATE o DELETE a nessun ruolo client, e nemmeno allo staff.
-- La tassonomia si estende con una migrazione, che e revisionabile, non con una
-- scrittura dal browser. Il privilegio assente e la barriera vera: la policy
-- qui sotto e la seconda, non la prima.

alter table public.wine_regions enable row level security;

create policy "wine_regions_select_public"
  on public.wine_regions for select
  to anon, authenticated
  using (true);

-- Nessuna policy di scrittura. Con la RLS attiva e senza policy permissive,
-- ogni INSERT/UPDATE/DELETE di un ruolo non proprietario e negato anche se un
-- domani qualcuno concedesse il privilegio per distrazione: fail-closed su
-- entrambi i livelli.

-- ---------------------------------------------------------------------------
-- [2] Popolamento iniziale
-- ---------------------------------------------------------------------------
-- LA LISTA NON E INVENTATA: e esattamente quella gia cablata in
-- `frontend-next/src/app/esplora/page-client.tsx`, meno lo pseudo-valore `Tutte`
-- che non e una regione ma il modo in cui quel filtro dice "nessun filtro". Le
-- posizioni conservano l'ordine di quella lista, cosi la UI del pacchetto
-- successivo potra leggere la tassonomia senza che l'elenco mostrato all'utente
-- cambi ordine da sotto.
--
-- Il catalogo mondiale delle regioni vinicole NON viene importato qui. Ogni
-- riga in piu sarebbe una scelta di prodotto — quali denominazioni Vinea
-- sostiene — presa di nascosto dentro una migrazione tecnica.
--
-- Copertura verificata sul progetto reale prima di scrivere questo file: tutti
-- i valori validi presenti in produzione (Champagne, Emilia-Romagna, Lombardia,
-- Piemonte, Toscana) sono in questa lista, e cosi le quattro regioni del
-- catalogo staff seminato dalla 20260728194500.

insert into public.wine_regions (nome, ordine) values
  ('Piemonte',              10),
  ('Toscana',               20),
  ('Veneto',                30),
  ('Sicilia',               40),
  ('Friuli-Venezia Giulia', 50),
  ('Trentino-Alto Adige',   60),
  ('Abruzzo',               70),
  ('Emilia-Romagna',        80),
  ('Lombardia',             90),
  ('Campania',             100),
  ('Puglia',               110),
  ('Marche',               120),
  ('Umbria',               130),
  ('Liguria',              140),
  ('Sardegna',             150),
  ('Lazio',                160),
  ('Champagne',            170);

-- ---------------------------------------------------------------------------
-- [3] Normalizzazione dei valori legacy
-- ---------------------------------------------------------------------------
-- SOLO MAPPING DETERMINISTICI, e ciascuno con la sua evidenza. Un valore che
-- non si sa dove mandare non viene indovinato: fa fallire il punto [4], che e
-- il comportamento giusto.
--
-- Entrambi gli UPDATE sono condizionati sul valore corrente e non solo sulla
-- riga. Se qualcuno avesse gia corretto una di queste righe a mano fra l'audit
-- e l'applicazione, la condizione non matcha, l'UPDATE tocca zero righe e la
-- migrazione prosegue: nessuna correzione altrui viene sovrascritta con
-- un'assunzione vecchia di ore.

-- `Toscanaa` e un refuso di battitura di `Toscana`, e non c'e una seconda
-- lettura possibile: nessuna regione vinicola si chiama cosi. La riga nota e
-- `test-qa-vinea-bottiglia-test-ricerca-2020`, ma la condizione e sul valore e
-- non sullo slug, cosi la correzione vale anche se il refuso fosse stato
-- ribattuto altrove nel frattempo.
update public.wines
set regione = 'Toscana'
where regione = 'Toscanaa';

-- `ciao` non e un refuso: e un campo compilato a caso durante una prova, e il
-- valore da solo non dice niente. La regione corretta viene dal vino, non dalla
-- stringa: `I Rifugi` di I Sabbioni e un Romagna Sangiovese prodotto a
-- Castiglione di Forli, quindi Emilia-Romagna. Poiche la deduzione vale per
-- QUESTA scheda e non per il valore `ciao` in generale, la condizione porta
-- anche lo slug: se domani un altro vino avesse `ciao`, questa riga non lo
-- toccherebbe e il punto [4] lo fermerebbe, che e esattamente cio che si vuole.
update public.wines
set regione = 'Emilia-Romagna'
where slug = 'sabbioni-i-rifugi-2017'
  and regione = 'ciao';

-- NESSUN DELETE, in nessuna forma. Le righe legacy conservano id, proprietario
-- e ogni relazione: le `bottle_units` collegate e i `listings` che ne
-- discendono non vengono ne ricreati ne rinumerati, perche un UPDATE di una
-- colonna di testo non tocca la chiave primaria e quindi non tocca nulla di
-- cio che vi punta. La cronologia degli annunci resta quella che era.

-- ---------------------------------------------------------------------------
-- [4] Cancello: nessun valore residuo non mappabile
-- ---------------------------------------------------------------------------
-- Il punto [5] fallirebbe comunque, ma con un errore di violazione di chiave
-- esterna che nomina il vincolo e non i dati. Qui l'errore dice quali valori
-- hanno fermato la migrazione e su quante righe, che e l'unica informazione con
-- cui si decide se aggiungere una regione alla tassonomia o correggere una riga.
--
-- Se questo blocco solleva un'eccezione la migrazione va fermata e il valore
-- riportato, non aggiunto d'ufficio alla lista: decidere che `Tuscany` o
-- `Borgogna` fanno parte del catalogo sostenuto e una scelta di prodotto.

do $$
declare
  v_residui text;
begin
  select string_agg(format('%L (%s righe)', t.regione, t.n), ', ' order by t.regione)
  into v_residui
  from (
    select w.regione, count(*) as n
    from public.wines w
    where not exists (
      select 1 from public.wine_regions r where r.nome = w.regione
    )
    group by w.regione
  ) t;

  if v_residui is not null then
    raise exception
      'D2: valori di wines.regione non canonici e non mappabili: %. '
      'Aggiungere la regione a public.wine_regions con una nuova migrazione '
      'oppure normalizzare la riga, poi riapplicare.', v_residui
      using errcode = 'P0001';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- [5] L'invariante: wines.regione referenzia la tassonomia
-- ---------------------------------------------------------------------------
-- UNA CHIAVE ESTERNA E NON UN CHECK CON LA LISTA DENTRO. Un `check (regione in
-- (...))` duplicherebbe la tassonomia dentro la definizione della tabella:
-- due elenchi da tenere allineati, e ogni regione nuova diventerebbe un ALTER
-- TABLE con riscansione completa invece di un INSERT.
--
-- `on update cascade` perche se un nome canonico venisse corretto la correzione
-- deve propagarsi alle schede, non spezzarle. `on delete restrict` perche una
-- regione ancora usata da un vino non deve poter sparire: la cancellazione
-- fallisce e chi la tenta scopre perche.
--
-- NOT VALID e poi VALIDATE, in due passi, e non un vincolo validato in un colpo
-- solo: il primo passo prende un lock breve e mette subito in guardia le
-- scritture nuove, il secondo verifica le righe esistenti sotto un lock piu
-- leggero. Su una tabella piccola la differenza non si misura, ma la forma
-- resta quella giusta quando il catalogo sara cresciuto.
--
-- LO STATO FINALE E VALIDATO. Un `NOT VALID` lasciato li sembra un vincolo e
-- non lo e: PostgreSQL non garantirebbe nulla sulle righe preesistenti, e una
-- riga sporca sopravvissuta al backfill resterebbe invisibile fino al giorno in
-- cui qualcuno la aggiorna.

alter table public.wines
  add constraint wines_regione_fkey
  foreign key (regione)
  references public.wine_regions (nome)
  on update cascade
  on delete restrict
  not valid;

alter table public.wines
  validate constraint wines_regione_fkey;

comment on constraint wines_regione_fkey on public.wines is
  'La regione di una scheda vino esiste nella tassonomia canonica. Sostituisce '
  'il solo `length(trim(regione)) > 0` della Fase 6a, che accettava qualunque '
  'stringa non vuota.';

-- `regione` resta NOT NULL: la chiave esterna non lo implica — una colonna
-- nullabile con FK accetta NULL — e indebolire quel vincolo mentre se ne
-- aggiunge un altro sarebbe uno scambio, non un rafforzamento. Il CHECK
-- `length(trim(regione)) > 0` della Fase 6a resta anch'esso: e ora ridondante
-- rispetto alla FK, ma toglierlo non guadagna niente e lo rimetterebbe in
-- discussione se un domani la FK cambiasse forma.
--
-- `wines_regione_idx` resta: e ancora l'indice giusto per il filtro per regione
-- di `/esplora`, e la colonna referenziante di una FK ne beneficia comunque nei
-- controlli di integrita al variare della tabella referenziata.

-- ---------------------------------------------------------------------------
-- [6] Canonicalizzazione al confine autorevole
-- ---------------------------------------------------------------------------
-- IL PROBLEMA CHE RISOLVE. Da questo momento un INSERT in `wines` con una
-- regione sconosciuta viene rifiutato da PostgreSQL con `23503`, violazione di
-- chiave esterna. Quel codice NON e fra i `CODICI_LEGGIBILI` del servizio
-- (`P0001`, `42501`), quindi arriverebbe all'utente come "Non e stato possibile
-- completare l'operazione. Riprova." — un messaggio che invita a ripetere
-- esattamente l'azione che non puo riuscire. Peggio: il wizard non saprebbe
-- dire QUALE campo e sbagliato.
--
-- La funzione qui sotto sposta il rifiuto un gradino prima, dove si puo ancora
-- dire cosa e successo, e ne approfitta per accettare cio che e chiaramente lo
-- stesso valore scritto diversamente.

create function private.regione_canonica(p_regione text)
returns text
language sql
security definer
set search_path = ''
stable
as $$
  select r.nome
  from public.wine_regions r
  where lower(r.nome) = lower(btrim(coalesce(p_regione, '')))
  limit 1;
$$;

comment on function private.regione_canonica(text) is
  'Riconduce una regione scritta dall''utente al nome canonico: ignora spazi '
  'ai bordi e differenze di maiuscole. Restituisce NULL se il valore non e '
  'nella tassonomia. Helper interno: non e una RPC client.';

-- IL CONTRATTO, detto per esteso perche la prossima persona non debba dedurlo:
--   `  toscana  `  ->  `Toscana`   accettato e ricondotto
--   `TOSCANA`      ->  `Toscana`   accettato e ricondotto
--   `Toscanaa`     ->  rifiutato   (un refuso non e un'equivalenza)
--   `Tuscany`      ->  rifiutato   (una traduzione nemmeno)
--   `ciao`         ->  rifiutato
--
-- Spazi ai bordi e maiuscole sono differenze di BATTITURA sullo stesso nome, e
-- riconoscerle non richiede di sapere niente sul vino. Un refuso e una
-- traduzione richiedono di indovinare l'intenzione: `Toscanaa` potrebbe essere
-- `Toscana`, ma stabilirlo con una distanza di edit significa accettare che un
-- giorno la stessa regola trasformi silenziosamente una regione in un'altra.
-- La traduzione delle regioni suggerite dall'AI (`Tuscany` -> `Toscana`)
-- appartiene al pacchetto UI/AI successivo, dove sara una scelta visibile
-- all'utente e non una sostituzione muta nel database.

revoke execute on function private.regione_canonica(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Il writer autorevole usa la canonicalizzazione
-- ---------------------------------------------------------------------------
-- IL PERCORSO REALE, verificato: `/vendi` -> `useSellWizard.datiBottiglia()` ->
-- `CellarService.aggiungiBottiglia` -> RPC `public.cellar_bottiglia_aggiungi`
-- -> `private.catalogo_risolvi_vino_utente`, che e l'unica funzione da cui un
-- client autenticato puo far nascere una riga in `wines`. E li che va messo il
-- controllo, non nella RPC di facciata: qualunque altra porta che un domani
-- risolvesse un vino utente passera comunque da qui.
--
-- (`public.listing_crea` ha un ramo che inserisce anch'esso in `wines`, ma la
-- 20260731120340 ne ha revocato l'EXECUTE ad `authenticated` e l'unica porta
-- rimasta, `listing_crea_da_bottiglia`, passa sempre una bottle_unit esistente:
-- quel ramo non e raggiungibile da nessun ruolo client. La FK del punto [5] lo
-- vincola comunque, quindi non puo introdurre una regione arbitraria neppure se
-- venisse riaperto per errore.)
--
-- Il corpo e quello della 20260731120340 — che resta congelata, come prescrive
-- la costituzione per un file gia distribuito — con una sola differenza: la
-- regione passa da `private.regione_canonica` prima di essere scritta, e un
-- valore non riconosciuto solleva `P0001` invece di arrivare alla chiave
-- esterna. `P0001` e fra i codici che `messaggioPerUtente` lascia passare, e il
-- wizard mostra quel testo in un toast.

create or replace function private.catalogo_risolvi_vino_utente(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_wine     uuid;
  v_base     text;
  v_slug     text;
  v_n        integer := 1;
  v_regione  text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if coalesce(trim(p_produttore), '') = '' then
    raise exception 'Il produttore è obbligatorio.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome del vino è obbligatorio.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_regione), '') = '' then
    raise exception 'La regione è obbligatoria.' using errcode = 'P0001';
  end if;
  if p_annata is null or p_annata < 1800 or p_annata > 2100 then
    raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
  end if;
  if p_tipo is null or p_tipo not in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce') then
    raise exception 'Tipologia non valida.' using errcode = 'P0001';
  end if;

  -- Il cancello della regione. Sta dopo gli altri controlli di campo e prima di
  -- qualunque scrittura: quando fallisce, non e ancora nato niente — ne la
  -- scheda vino ne l'unita — quindi non c'e nessun residuo da ripulire.
  v_regione := private.regione_canonica(p_regione);
  if v_regione is null then
    raise exception 'Regione non riconosciuta: %. Scegli una delle regioni disponibili.',
      btrim(p_regione)
      using errcode = 'P0001';
  end if;

  select w.id into v_wine
  from public.wines w
  where w.produttore = trim(p_produttore)
    and w.nome = trim(p_nome)
    and w.annata = p_annata::smallint;

  if v_wine is not null then
    return v_wine;
  end if;

  v_base := public.slugifica(
    trim(p_produttore) || ' ' || trim(p_nome) || ' ' || p_annata::text
  );

  loop
    v_slug := case when v_n = 1 then v_base else v_base || '-' || v_n end;
    begin
      insert into public.wines (
        slug, produttore, nome, annata, regione, tipo, provenienza, creato_da
      )
      values (
        v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint,
        v_regione, p_tipo, 'utente', v_uid
      )
      on conflict (produttore, nome, annata) do nothing
      returning id into v_wine;
    exception when unique_violation then
      v_wine := null;
    end;

    if v_wine is not null then
      return v_wine;
    end if;

    select w.id into v_wine
    from public.wines w
    where w.produttore = trim(p_produttore)
      and w.nome = trim(p_nome)
      and w.annata = p_annata::smallint;

    if v_wine is not null then
      return v_wine;
    end if;

    v_n := v_n + 1;
    if v_n > 100 then
      raise exception 'Non è stato possibile assegnare un identificatore al vino. Riprova.'
        using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

comment on function private.catalogo_risolvi_vino_utente(text, text, integer, text, text) is
  'Helper interno: riusa la tripletta esistente o crea una scheda con '
  'provenienza utente. Dalla D2 la regione viene ricondotta al nome canonico '
  'di public.wine_regions e un valore non riconosciuto e rifiutato con P0001. '
  'Non e una RPC client.';

-- I privilegi della funzione non cambiano — restano quelli fissati dalla
-- 20260731120340 — ma vengono riaffermati perche `create or replace` su una
-- funzione esistente li conserva e su una ricreata da zero no: ripeterli rende
-- il file corretto in entrambi gli scenari, compreso un ambiente usa-e-getta
-- costruito da zero.
revoke execute on function private.catalogo_risolvi_vino_utente(
  text, text, integer, text, text
) from public, anon, authenticated;
