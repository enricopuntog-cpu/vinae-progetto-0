-- Destinazione `cellar` per le notifiche — soltanto la label dell'enum.
--
-- PERCHE UN FILE DA SOLO. PostgreSQL vieta di *usare* un valore appena aggiunto
-- a un enum nella stessa unita transazionale che lo aggiunge (55P02, «unsafe use
-- of new value of enum type»): il CHECK di forma e le funzioni che nominano
-- 'cellar' non possono stare qui. Il CLI Supabase applica ogni file di
-- migrazione nella propria transazione, quindi la separazione in due file e
-- esattamente la separazione transazionale richiesta. La 20260926091000 usa la
-- label; questo file la crea e nient'altro.
--
-- `if not exists` rende il file rieseguibile su un database che ha gia la label
-- (per esempio un branch Preview ricostruito) senza rompere l'applicazione.

alter type public.notification_destination_kind add value if not exists 'cellar';
