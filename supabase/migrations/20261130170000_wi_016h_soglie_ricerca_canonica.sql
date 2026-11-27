-- WI-016 H — correzione delle soglie di nascita di WI-016F (migration già pubblicata, quindi non modificata).
--
-- La ricerca canonica ha un contratto stabilito da WI-008: 40 ricerche al minuto per utente, applicato dentro la
-- funzione. La raffica comune di F (15 in 10 secondi) lo restringeva: la griglia wi008d, che chiede 40 ricerche di
-- seguito, ne vedeva servite 15. Per la ricerca canonica la protezione comune AGGIUNGE tetto globale, posti di
-- concorrenza e limite orario; raffica e minuto per utente non scendono sotto il contratto di WI-008.
-- La ricerca dei vini (`ricerca_vini`) non cambia. Nulla viene acceso.

update private.protezione_letture
   set utente_raffica = 40, utente_minuto = 60
 where superficie = 'ricerca_canonica';

do $verifica$
begin
  if not exists (select 1 from private.protezione_letture p
                  where p.superficie = 'ricerca_canonica' and p.utente_raffica >= 40 and p.utente_minuto >= 40) then
    raise exception 'WI-016H: soglie della ricerca canonica non applicate';
  end if;
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016H: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;
