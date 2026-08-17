-- Fase 12c - i due valori mancanti di report_target_tipo.
--
-- QUESTO FILE ESISTE PER UNA RAGIONE DI TRANSAZIONE, NON PER UNA DECISIONE.
-- Non aggiungetelo alla 12b e non fondetelo con la migrazione che lo segue.
--
-- Il brief della sessione chiedeva di "estendere il check constraint di
-- report_target_tipo". Non e un check constraint: e un ENUM
-- (20260810152000_phase_9a_moderation_schema.sql:36). La differenza non e
-- terminologica e decide la forma della migrazione.
--
-- In PostgreSQL 12+ `alter type ... add value` puo stare dentro un blocco di
-- transazione, ma IL VALORE NUOVO NON E UTILIZZABILE NELLA STESSA TRANSAZIONE
-- CHE LO AGGIUNGE. Supabase applica ogni file di migrazione nella propria
-- transazione. Quindi aggiungere 'post' e 'commento' e usarli - in un
-- `insert into report_reasons`, in un `check`, dentro un `case` di funzione -
-- nello stesso file non e uno stile discutibile: e un errore a tempo di
-- applicazione. Il file successivo, 20260817121000, e tutto cio che li USA.
--
-- La decisione 7.6a li aveva esclusi «finche i club non hanno schema
-- Supabase»: un bersaglio che non puo essere risolto in una riga non e un
-- bersaglio. La 12a ha dato schema ai club ma non ai post, quindi la
-- decisione era ancora soddisfatta. La 12b da schema ai post e alle risposte,
-- e con questo la condizione posta da quella decisione e esaurita: i due
-- valori hanno finalmente una tabella in cui risolversi
-- (public.club_posts e public.club_post_risposte). La 7.6a non viene
-- riaperta - viene adempiuta.
--
-- `if not exists` non e superfluo benche i due valori oggi non esistano: un
-- ambiente che avesse gia registrato questa versione come applicata non
-- rieseguirebbe il file, ma un ambiente ricostruito da zero potrebbe
-- attraversarlo dopo un ripristino parziale. Costa nulla e toglie una classe
-- di fallimento.

alter type public.report_target_tipo add value if not exists 'post';
alter type public.report_target_tipo add value if not exists 'commento';

comment on type public.report_target_tipo is
  'Bersagli segnalabili. Sette, come i sette del mock in '
  'frontend/src/data/moderation.ts:22-23: la 9a ne aveva cinque perche la '
  'decisione 7.6a escludeva `post` e `commento` finche i club non avevano '
  'schema. La 12b glielo da, e la 12c li aggiunge qui. Aggiungere un valore a '
  'un enum in uso richiede una migrazione nuova, e usarlo ne richiede una '
  'ancora successiva: il valore non e utilizzabile nella transazione che lo '
  'crea.';
