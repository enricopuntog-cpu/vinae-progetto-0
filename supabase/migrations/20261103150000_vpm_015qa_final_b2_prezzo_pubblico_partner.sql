-- VPM-015QA-FINAL-B2-COMPLETION — il prezzo pubblico di un annuncio Partner è quello del checkout.
--
-- Difetto trovato dal collaudo browser sul percorso Partner: la forma pubblica di un annuncio
-- (`private.annuncio_accessorio_pubblico_json`, B3) calcola `prezzo_acquirente_cents` con la classe
-- 'privato' scritta nel sorgente. Per un annuncio commerciale di un Vinea Partner la vetrina e il dettaglio
-- mostravano 22,73 € (margine 10%) mentre preventivo, prenotazione e pagamento usano la classe `partner`
-- (1500 bps): 23,75 € per un pezzo da 20,00 €. L'acquirente vedeva un prezzo e ne pagava un altro.
--
-- Correzione: la classe si legge dal venditore PER ARTICOLO (`annuncio_accessorio_venditore(seller, cantina)`,
-- VPM-015C), la stessa fonte di preventivo e checkout. Nessuna tabella, nessuna policy, nessun privilegio
-- cambia: `create or replace` mantiene i grant (nessuno ad anon/authenticated). Patch puntuale con asserzione,
-- come la 015C: se il testo da sostituire non compare esattamente una volta, la migrazione si ferma.

create function pg_temp.patch_b2c(p_sig regprocedure, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_sig);
  v_n integer := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception 'patch_b2c: % occorrenze di % in %', v_n, p_old, p_sig;
  end if;
  execute replace(v_def, p_old, p_new);
end;
$$;

select pg_temp.patch_b2c('private.annuncio_accessorio_pubblico_json(uuid)'::regprocedure,
  '''privato''::public.classe_venditore,',
  'coalesce((select v.classe from private.annuncio_accessorio_venditore(a.seller_id, a.cantina_accessorio_id) v),
            ''privato''::public.classe_venditore),');

-- Difesa in profondita: i privilegi restano chiusi (CREATE OR REPLACE li conserva; qui si riaffermano).
revoke all on function private.annuncio_accessorio_pubblico_json(uuid) from public, anon, authenticated;

comment on function private.annuncio_accessorio_pubblico_json(uuid) is
  'Forma pubblica chiusa di un annuncio Accessori. VPM-015QA-FINAL-B2: il prezzo per l''acquirente usa la classe del venditore PER ARTICOLO (privato 10%, Partner 15%), la stessa di preventivo e checkout.';
