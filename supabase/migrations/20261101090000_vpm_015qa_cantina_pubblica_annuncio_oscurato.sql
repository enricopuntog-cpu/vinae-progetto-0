-- VPM-015QA / M1 - la moderazione degli annunci Accessori non si aggira ne dalla
-- Cantina pubblica ne con una nuova pubblicazione.
--
-- DIFETTO MISURATO (griglia 12zl, prima di questa migrazione): la moderazione di un
-- annuncio Accessori (B3: sospensione, rimozione, richiesta di modifiche) agisce solo
-- su `private.annunci_accessori`. L'accessorio di Cantina da cui nasce resta
-- `cantina_pubblica`, quindi la proiezione B1 continua a mostrarlo, con le stesse
-- foto, a chiunque e per le firme dello Storage: un percorso alternativo che
-- neutralizza il provvedimento. Il filtro sui termini vietati e la porta di categoria
-- valgono solo per l'annuncio, non per la Cantina. Sfruttabile solo con i due
-- interruttori della Cantina accesi (spenti di default).
--
-- PARTE 1 - FILTRO DERIVATO nella sola vista pubblicabile. Le due porte pubbliche
-- (profilo e firme Storage) leggono entrambe quella vista, quindi un solo punto le
-- chiude. L'accessorio esce dalla Cantina pubblica quando un suo annuncio e:
--   - `oscurato` (sospensione o rimozione);
--   - `modifiche_richieste`: finche il venditore non lo corregge e l'annuncio non
--     torna `pubblicato`;
--   - `ritirato` con un provvedimento (`provvedimento` non nullo): il ritiro non
--     cancella il provvedimento. Un annuncio ritirato dopo un provvedimento e
--     terminale (la guardia B3 non lo riapre), coerentemente con il blocco di
--     ripubblicazione `ripubblicazione_bloccata`;
--   - `ritirato` dopo una richiesta di modifiche, finche il contenuto dell'accessorio
--     (offerta congelata dell'annuncio + nome, marchio e foto della Cantina) coincide
--     con quello per cui l'amministrazione aveva chiesto di cambiare (impronta
--     `hash_richiesta`): quando cambia davvero qualcosa il blocco cessa da solo.
-- Dopo un ripristino legittimo che riporta l'annuncio a `pubblicato` (`provvedimento`
-- azzerato) il filtro cessa da solo; se l'annuncio era stato oscurato mentre era in
-- `modifiche_richieste`, il ripristino lo riporta a `modifiche_richieste` (B3) e
-- l'accessorio resta nascosto fino a un secondo ripristino o alla correzione del
-- venditore. Un ritiro volontario senza provvedimento ne richiesta di modifiche non
-- nasconde nulla.
--
-- PARTE 2 - NUOVA PUBBLICAZIONE CON LO STESSO CONTENUTO. B3 rifiuta di ripubblicare lo
-- stesso annuncio senza cambiare nulla (`modifiche_non_effettuate`), ma non un NUOVO
-- annuncio per lo stesso accessorio dopo il ritiro: il venditore poteva ritirare e
-- ripubblicare il contenuto identico. Il trigger `annunci_accessori_richiesta_modifiche_guard`
-- estende la stessa regola (la stessa impronta, nessun modello nuovo) agli altri annunci
-- dello stesso accessorio. Non agisce sulle azioni dell'amministrazione (marcatore di
-- moderazione) e non rende permanente nulla: basta cambiare davvero qualcosa.
--
-- Nessuna scrittura di moderazione sulla Cantina: la scelta di visibilita del proprietario
-- non viene riscritta, i dati di inventario non cambiano e il proprietario continua a
-- vedere tutto nella propria Cantina (porta del proprietario e policy Storage "proprie").
--
-- Colonne, ordine, opzioni e privilegi della vista non cambiano (CREATE OR REPLACE;
-- `revoke all` riaffermato). Le migrazioni B1 e B3 non sono toccate.
--
-- LIMITI NOTI (docs/VPM_015B3_PUBBLICAZIONE_ACCESSORI.md, §3 bis e §9): la Cantina
-- pubblica non ha moderazione propria, quindi un accessorio NUOVO e diverso (duplicato
-- con altro id, foto ricaricate) non e raggiunto dal provvedimento; eliminare l'accessorio
-- cancella a cascata anche il provvedimento (modello B3). Sono debiti di B3, non regressioni.

-- Indice per il filtro: l'indice unico parziale B3 copre solo gli annunci non ritirati;
-- gli annunci con un provvedimento (oscurati e ritirati dopo un provvedimento, pochi)
-- hanno un indice proprio, cosi la proiezione pubblica non scansiona la tabella per ogni
-- accessorio. Tabella in `private`, senza grant ai ruoli client.
create index if not exists annunci_accessori_provvedimento_idx
  on private.annunci_accessori (cantina_accessorio_id)
  where provvedimento is not null;

-- Idem per le richieste di modifiche ancora ricordate da un annuncio ritirato.
create index if not exists annunci_accessori_hash_richiesta_idx
  on private.annunci_accessori (cantina_accessorio_id)
  where hash_richiesta is not null;

create or replace view private.cantina_accessori_pubblica
with (security_invoker = off, security_barrier = true)
as
select
  a.id          as accessorio_id,
  a.owner_id    as user_id,
  a.nome,
  a.descrizione,
  a.marchio,
  a.condizione,
  a.quantita,
  a.immagini,
  a.created_at  as aggiunto_at,
  c.slug        as categoria_slug,
  c.nome        as categoria_nome,
  g.nome        as genitore_nome
from private.cantina_accessori a
  join private.accessori_categorie c on c.id = a.categoria_id
  left join private.accessori_categorie g on g.id = c.parent_id
  join private.profili_pubblici pp on pp.user_id = a.owner_id
where a.visibilita = 'cantina_pubblica'
  and a.archiviato_at is null
  and not exists (
    select 1
    from private.annunci_accessori n
    where n.cantina_accessorio_id = a.id
      and (n.stato in ('oscurato', 'modifiche_richieste')
           or n.provvedimento is not null
           or (n.stato = 'ritirato'
               and n.hash_richiesta is not null
               and n.hash_richiesta = private.annuncio_accessorio_contenuto_hash(
                     n.quantita, n.prezzo_unitario_cents, n.condizione, n.descrizione,
                     n.peso_g, n.lunghezza_mm, n.larghezza_mm, n.altezza_mm, n.fragile,
                     a.nome, a.marchio, a.immagini)))
  );

comment on view private.cantina_accessori_pubblica is
  'Proiezione pubblicabile degli accessori esposti di un profilo visibile. Esclude gli accessori '
  'il cui annuncio e oscurato, con modifiche richieste, ritirato dopo un provvedimento o ritirato '
  'con il contenuto per cui erano state chieste modifiche (VPM-015QA/M1). Nessun privilegio per '
  'anon/authenticated: la sola porta e public.cantina_accessori_pubblica_profilo(uuid, int, int, boolean).';

revoke all on private.cantina_accessori_pubblica from public, anon, authenticated;

-- Parte 2: un nuovo annuncio non ripubblica il contenuto per cui l'amministrazione ha
-- chiesto modifiche su un altro annuncio dello stesso accessorio.
create function private.annunci_accessori_richiesta_modifiche_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item private.cantina_accessori%rowtype;
  v_hash text;
begin
  if new.stato = 'pubblicato'
     and (old.stato <> 'pubblicato' or new.versione <> old.versione)
     and coalesce(current_setting('vinae.annuncio_accessorio_moderazione', true), '')
         <> 'ok:' || new.id::text
     and exists (
       select 1 from private.annunci_accessori x
       where x.cantina_accessorio_id = new.cantina_accessorio_id
         and x.id <> new.id
         and x.hash_richiesta is not null) then
    select * into v_item from private.cantina_accessori where id = new.cantina_accessorio_id;
    v_hash := private.annuncio_accessorio_contenuto_hash(
      new.quantita, new.prezzo_unitario_cents, new.condizione, new.descrizione,
      new.peso_g, new.lunghezza_mm, new.larghezza_mm, new.altezza_mm, new.fragile,
      v_item.nome, v_item.marchio, v_item.immagini);
    if exists (
         select 1 from private.annunci_accessori x
         where x.cantina_accessorio_id = new.cantina_accessorio_id
           and x.id <> new.id
           and x.hash_richiesta = v_hash) then
      raise exception 'Modifica l''annuncio come richiesto prima di ripubblicarlo.'
        using errcode = '22023', hint = 'modifiche_non_effettuate';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.annunci_accessori_richiesta_modifiche_guard()
  from public, anon, authenticated;

comment on function private.annunci_accessori_richiesta_modifiche_guard() is
  'VPM-015QA/M1: rifiuta la pubblicazione di un annuncio il cui contenuto coincide con quello per cui '
  'l''amministrazione aveva chiesto modifiche su un altro annuncio dello stesso accessorio.';

create trigger annunci_accessori_richiesta_modifiche_guard
  before update on private.annunci_accessori
  for each row execute function private.annunci_accessori_richiesta_modifiche_guard();