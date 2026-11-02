-- VPM-015QA-FINAL-A: l'annullamento ordinario non si incrocia con un pagamento aperto.
--
-- Difetto (B5D): `accessori_ordine_annulla` rifiutava solo l'ordine gia pagato. Con un
-- PaymentIntent collegato e ancora confermabile l'acquirente poteva annullare l'ordine
-- chiamando la RPC direttamente (la UI nasconde «Annulla», ma non e un controllo): l'incasso
-- arrivato dopo finiva in `refund_due`. Il denaro non restava senza uscita, ma l'esito
-- dipendeva da una corsa evitabile.
--
-- Regola (decisa dal database, nessuna evidenza dal browser):
--   - pagamento `processing` (fondi in transito): annullo rifiutato (`pagamento_in_corso`)
--     fino all'ora che segue la scadenza, la stessa finestra in cui la pulizia lo protegge;
--   - pagamento `checkout_pending` COLLEGATO a una sessione del fornitore e prenotazione non
--     scaduta: annullo rifiutato (`pagamento_in_corso`); il blocco finisce da solo con
--     l'evento firmato (paid / failed / expired) o con la scadenza della prenotazione
--     (al piu `prenotazione_min` minuti): nessun blocco permanente;
--   - pagamento `checkout_pending` NON collegato (l'Edge Function non ha ancora collegato
--     l'intento) o prenotazione scaduta: annullo ammesso e il pagamento passa a `expired`
--     (`ordine_annullato`), cosi `accessori_pagamento_collega` non puo piu agganciare
--     un intento a un ordine chiuso. L'Edge Function risponde 502 senza restituire il
--     `client_secret`: l'eventuale PaymentIntent orfano non e confermabile dal browser.
--     Se comunque venisse incassato, il webhook non troverebbe il pagamento (nessuna riga
--     `refund_due`): residuo noto, da chiudere annullando l'intento orfano nell'Edge Function.
--     Un incasso tardivo di un intento COLLEGATO prende invece la via `refund_due`.
-- Lock: ordine -> pagamento, come apri / applica_evento / rimborsi (nessuna inversione).
-- Funzione gia distribuita: sostituita con CREATE OR REPLACE (stessi grant), nessuna
-- migrazione precedente modificata.

create or replace function public.accessori_ordine_annulla(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  o private.accessori_ordini%rowtype;
  p private.accessori_pagamenti%rowtype;
begin
  perform private.rate_limit_consume('accessori_checkout:annulla', 'user:' || v_uid::text, 20, 60);
  select * into o from private.accessori_ordini where id = p_id and buyer_id = v_uid for update;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if o.stato = 'pagato' then
    raise exception 'Un ordine pagato non si annulla da qui.'
      using errcode = '22023', hint = 'ordine_pagato';
  end if;
  if o.stato = 'in_attesa_pagamento' then
    select * into p from private.accessori_pagamenti where ordine_id = o.id for update;
    if p.id is not null and (
         (p.stato = 'processing' and o.scade_at > now() - interval '1 hour')
         or (p.stato = 'checkout_pending' and p.provider_session_id is not null and o.scade_at > now())) then
      raise exception 'Il pagamento e in corso: attendi l''esito.'
        using errcode = '22023', hint = 'pagamento_in_corso';
    end if;
    perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
    update private.accessori_ordini
    set stato = case when scade_at <= now() then 'scaduto' else 'annullato' end,
        motivo_chiusura = case when scade_at <= now() then 'scadenza' else 'acquirente' end
    where id = o.id returning * into o;
    perform set_config('vinae.accessori_ordine_transizione', '', true);
    if p.id is not null and p.stato = 'checkout_pending' then
      update private.accessori_pagamenti set stato = 'expired', motivo = 'ordine_annullato' where id = p.id;
    end if;
  end if;
  return private.accessori_ordine_json(o, 'acquirente');
end;
$$;

comment on function public.accessori_ordine_annulla(uuid) is
  'VPM-015B5A/QA-FINAL-A: l''acquirente annulla la propria prenotazione non pagata; i pezzi tornano disponibili. '
  'Rifiutato con pagamento in corso (pagamento_in_corso); un pagamento non collegato si chiude (expired).';
