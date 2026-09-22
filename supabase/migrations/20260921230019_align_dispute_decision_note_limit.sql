-- Allinea il campo storico alla motivazione versionata della decisione Vinea.
-- La RPC moderazione_contestazione_decidi accetta fino a 2000 caratteri.
alter table public.disputes
  drop constraint if exists disputes_esito_nota_check;

alter table public.disputes
  add constraint disputes_esito_nota_check
  check (esito_nota is null or length(esito_nota) <= 2000);
