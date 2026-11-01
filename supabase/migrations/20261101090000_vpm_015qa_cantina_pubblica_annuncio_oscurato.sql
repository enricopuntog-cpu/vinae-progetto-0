-- VPM-015QA / M1 — la Cantina pubblica non espone un accessorio il cui annuncio
-- e stato oscurato dall'amministrazione.
--
-- DIFETTO MISURATO (griglia 12zl, casi 3 e 4, prima di questa migrazione):
-- l'oscuramento o la rimozione di un annuncio Accessori (B3) agisce solo su
-- `private.annunci_accessori`. L'accessorio di Cantina da cui nasce resta
-- `cantina_pubblica`, quindi la proiezione B1 continua a mostrarlo, con le
-- stesse foto, a chiunque e per le firme dello Storage. Il filtro sui termini
-- vietati e la porta di categoria valgono solo per l'annuncio, non per la
-- Cantina: l'esposizione B1 li aggirava. Sfruttabile solo con i due interruttori
-- della Cantina accesi (spenti di default).
--
-- CORREZIONE: un filtro DERIVATO nella sola vista pubblicabile. Le due porte
-- pubbliche (profilo e firme Storage) leggono entrambe quella vista, quindi un
-- solo punto le chiude. Nessuna scrittura di moderazione sulla Cantina: la
-- scelta di visibilita del proprietario non viene riscritta e il ripristino
-- dell'annuncio riapre da solo l'esposizione che il proprietario aveva scelto.
-- Il proprietario continua a vedere tutto in Cantina (porta del proprietario).
--
-- Colonne, ordine, opzioni e privilegi della vista non cambiano (CREATE OR
-- REPLACE; `revoke all` riaffermato). La migrazione B1 non e toccata.

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
      and n.stato = 'oscurato'
  );

comment on view private.cantina_accessori_pubblica is
  'Proiezione pubblicabile degli accessori esposti di un profilo visibile. Esclude gli accessori '
  'con un annuncio oscurato dall''amministrazione (VPM-015QA/M1). Nessun privilegio per '
  'anon/authenticated: la sola porta e public.cantina_accessori_pubblica_profilo(uuid, int, int, boolean).';

revoke all on private.cantina_accessori_pubblica from public, anon, authenticated;