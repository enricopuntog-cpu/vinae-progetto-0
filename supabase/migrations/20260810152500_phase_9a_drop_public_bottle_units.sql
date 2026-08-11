-- Fase 9a - rimozione di public_bottle_units e della cantina pubblica per
-- singola bottiglia (decisione organizzativa 7.7 del 10 agosto 2026).
--
-- File separato dalla migrazione di schema perche e una decisione separata:
-- non ha nulla a che vedere con la moderazione, e solo il backlog imponeva di
-- chiuderla entro la Fase 9
-- (docs/MIGRATION_PHASE_1_BACKLOG.md, «public_bottle_units non ha consumatori»).
--
-- CONTROLLO DI NON REGRESSIONE, eseguito prima di scrivere questo file:
--   - zero occorrenze di `public_bottle_units` in frontend/src e
--     frontend-next/src (nessun .ts, nessun .tsx);
--   - le sole occorrenze fuori da supabase/migrations sono documentali, piu
--     le due griglie 6d-1 in supabase/tests/ (vedi in fondo);
--   - la Fase 8 e chiusa e non l'ha usata: le sue quattro tabelle sono
--     conversations, conversation_participants, messages, notifications.
--
-- PERCHE IL DROP DELLA VISTA RIMUOVE DAVVERO IL CONCETTO, E NON SOLO LA VISTA.
-- Letto da pg_policy sul progetto reale prima di scrivere: public.bottle_units
-- ha esattamente tre policy, bottle_units_select_own, bottle_units_insert_own e
-- bottle_units_update_own, tutte vincolate a owner_id = auth.uid(). La policy
-- bottle_units_select_cantina_pubblica della 6c-1 era gia stata eliminata dalla
-- 6d-1 (20260729230000:1066). Questa vista e quindi l'unico percorso per cui un
-- non proprietario possa leggere una riga di bottle_units: rimuoverla non
-- nasconde la cantina pubblica, la elimina.
--
-- COSA QUESTO FILE NON FA, DELIBERATAMENTE.
-- Non tocca la colonna bottle_units.visibilita ne l'enum
-- public.bottle_unit_visibilita. Non e una dimenticanza:
--   - la colonna e scritta da public.bottiglia_crea, il cui sesto parametro e
--     `p_visibilita public.bottle_unit_visibilita`
--     (20260731120340:313, :373-383): rimuoverla cambierebbe la firma di una
--     RPC gia in produzione, che non e nel perimetro di questa fase;
--   - la scrivono frontend-next/src/services/cellar-service.ts:531 e
--     frontend-next/src/hooks/useSellWizard.ts:207, e l'etichetta
--     `cantina_pubblica` e nel tipo SaleStatus di frontend/src/data/cellar.ts:49,
--     cioe nella versione servita, che resta congelata fino alla Fase 11;
--   - un drop di colonna e distruttivo su dati reali.
-- Dopo questo file la colonna resta scrivibile dal proprietario e non produce
-- piu alcun effetto osservabile da terzi: e un residuo inerte, e come tale va
-- sulla lista di cutover della Fase 11, accanto alla voce «protezione» che la
-- 7d ha trattato allo stesso modo.

drop view if exists public.public_bottle_units;

-- Il commento sulla 6c-1 in 20260731120340:141 diceva che gli asset pubblici di
-- un annuncio «non compaiono in public_bottle_units». La vista non esiste piu:
-- il commento resta vero ma cita un oggetto morto, quindi lo si riscrive.
comment on column public.bottle_units.immagini is
  'Immagini della singola unita in cantina. Restano private al proprietario: '
  'dalla Fase 9a non esiste piu alcuna proiezione che mostri una bottle_unit a '
  'un non proprietario.';

comment on column public.bottle_units.visibilita is
  'RESIDUO INERTE dalla Fase 9a. La cantina pubblica per singola bottiglia e '
  'stata rimossa con la decisione 7.7: dopo il drop di public_bottle_units '
  'nessun percorso mostra una bottle_unit a chi non ne e proprietario, quindi '
  'il valore cantina_pubblica non ha piu alcun effetto osservabile. La colonna '
  'sopravvive perche e un parametro di public.bottiglia_crea ed e scritta da '
  'frontend-next e da frontend, che restano congelati fino alla Fase 11: la '
  'sua rimozione appartiene alla lista di cutover, non a questa fase.';

comment on type public.bottle_unit_visibilita is
  'RESIDUO INERTE dalla Fase 9a: vedi il commento su bottle_units.visibilita. '
  'Nessun valore di questo enum produce piu una lettura da parte di terzi.';

-- Nota sulle due griglie 6d-1 versionate in supabase/tests/.
-- supabase/tests/6d-1_invarianti_sicurezza.sql (casi alle righe 296-312 e 433)
-- e supabase/tests/6d-1_verifica.sql (188-242) interrogano public_bottle_units
-- e da qui in avanti non sono piu eseguibili come scritte. Non vengono
-- modificate: sono il verbale di un'esecuzione avvenuta, e riscriverle
-- significherebbe riscrivere un verbale. La conseguenza e registrata nel
-- rapporto di fase invece che nascosta in una modifica silenziosa.

notify pgrst, 'reload schema';
