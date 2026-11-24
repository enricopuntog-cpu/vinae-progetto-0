import { eseguiSql } from "./db";
import { leggiDalDatabase } from "./vino";

/**
 * WI-007 / FIX-03C — fixture del catalogo canonico per la prova browser + PostgREST su dati reali dello stack E2E dedicato.
 *
 * Il catalogo canonico in uno stack nuovo è VUOTO e `catalog.*` non è raggiungibile dai ruoli API: le righe «promosse» le
 * scrive il database come proprietario, con i trigger spenti (come la griglia SQL wi007), per non approvare la regola
 * `lwin-conservative-v1` né accendere la promozione: nessuna promozione e nessuna regola cambiano. La chiave di ricerca
 * la calcola il fixture con `vini_normalizza`, la stessa funzione del trigger (provato dalla griglia wi007b).
 *
 * Tutto ciò che qui nasce si toglie in `rimuoviCanonico` (idempotente, con verifica dei residui). Le guardie rifiutano di
 * toccare un catalogo che non sia vuoto: mai dati altrui. Interruttore e stato della fonte tornano ai valori di partenza.
 * Limite noto: se la corsa viene uccisa a metà, la pulizia gira alla corsa successiva di questo spec (`beforeAll`); gli
 * spec che la precedono non la vedono, ma nessuno di loro usa il catalogo canonico.
 * Solo stack effimero dedicato (`eseguiSql` verifica identità e possesso). Mai Production.
 */

/** Produttore delle schede canoniche: lo stesso delle bottiglie della suite, così il confronto è a pari nome. */
export const PRODUTTORE_CANONICO = "Cantina E2E-CRIT";
/** LWIN-7 sintetici riservati alla prova (fuori da ogni intervallo reale usato nelle altre griglie). */
export const LWIN_GEMELLO_A = "9100001";
export const LWIN_GEMELLO_B = "9100002";
export const LWIN_SINGOLO = "9100003";

const CORSA = /^[0-9a-f]{6}$/;

const conteggi = (): string =>
  leggiDalDatabase(
    `select concat_ws(' ', (select count(*) from catalog.wines), (select count(*) from catalog.producers),
       (select count(*) from catalog.source_records), (select count(*) from catalog.territories),
       (select count(*) from catalog.entity_aliases), (select count(*) from catalog.canonical_events),
       (select enabled::text from catalog.public_projection_settings),
       (select authorization_status::text from catalog.sources where code = 'LIVEX-LWIN7'));`,
  );

/** Stato atteso a catalogo pulito: nessuna riga, interruttore spento, fonte autorizzata. */
/** Righe di wines, producers, source_records, territories, entity_aliases e canonical_events, poi interruttore e fonte. */
export const CATALOGO_PULITO = "0 0 0 0 0 0 false authorized";

/** Interruttore della proiezione pubblica (solo il database lo muove, come farebbe la migration autorizzata). */
export const impostaProiezione = (accesa: boolean): void => {
  eseguiSql(`update catalog.public_projection_settings set enabled = ${accesa ? "true" : "false"};`);
};

/** Stato di autorizzazione della fonte LWIN (prova della fonte revocata). */
export const impostaFonte = (stato: "authorized" | "restricted" | "revoked"): void => {
  eseguiSql(`update catalog.sources set authorization_status = '${stato}' where code = 'LIVEX-LWIN7';`);
};

/** Crea tre schede canoniche: due con lo STESSO nome e LWIN diversi (identità ambigua), una singola. */
export const creaCanonico = (corsa: string): void => {
  if (!CORSA.test(corsa)) throw new Error("Etichetta di corsa non valida.");
  const prima = conteggi();
  if (prima !== CATALOGO_PULITO) {
    throw new Error(`Il catalogo canonico non è pulito (${prima}): la prova non scrive su dati altrui.`);
  }
  eseguiSql(`begin;
  set local session_replication_role = replica;
  do $f$
  declare
    v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
    v_run uuid := gen_random_uuid();
    v_it bigint; v_pie bigint; v_tos bigint; v_rec bigint; v_prod uuid; r record;
  begin
    insert into catalog.territories (source_id, kind, name, name_key, natural_key)
      values (v_src, 'country', 'Italia', 'italia', 'wi007c') returning id into v_it;
    insert into catalog.territories (source_id, kind, name, name_key, natural_key)
      values (v_src, 'region', 'Piemonte', 'piemonte', 'wi007c|piemonte') returning id into v_pie;
    insert into catalog.territories (source_id, kind, name, name_key, natural_key)
      values (v_src, 'region', 'Toscana', 'toscana', 'wi007c|toscana') returning id into v_tos;
    insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
      values (v_src, '9100000', 'Live', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('e', 64), v_run, v_run) returning id into v_rec;
    insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
      values ('${PRODUTTORE_CANONICO}', catalog.fold_text('${PRODUTTORE_CANONICO}'), v_it,
              catalog.fold_text('${PRODUTTORE_CANONICO}') || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec)
      returning id into v_prod;
    for r in select * from (values
      ('${LWIN_GEMELLO_A}', 'Gemello ${corsa}', v_pie, 'Barolo DOCG'),
      ('${LWIN_GEMELLO_B}', 'Gemello ${corsa}', v_tos, 'Chianti Classico DOCG'),
      ('${LWIN_SINGOLO}',   'Singolo ${corsa}', v_pie, 'Langhe DOC')
    ) as t(lwin, vino, terr, den)
    loop
      insert into catalog.source_records (source_id, external_id, status, scope, territory_id, payload, raw, content_hash, first_seen_run, changed_in_run)
        values (v_src, r.lwin, 'Live', 'wine', r.terr, '{}'::jsonb, '{}'::jsonb, repeat('e', 64), v_run, v_run) returning id into v_rec;
      insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, designation, territory_id,
                                 origin, status, source_id, source_record_id, search_key)
        values (r.lwin, v_prod, r.vino, catalog.fold_text(r.vino), 'Red', 'Still', r.den, r.terr,
                'promotion', 'active', v_src, v_rec, public.vini_normalizza('${PRODUTTORE_CANONICO} ' || r.vino));
    end loop;
  end $f$;
  commit;`);
};

/**
 * Toglie ogni riga creata da `creaCanonico` e riporta interruttore e fonte ai valori di partenza.
 * Idempotente: si può chiamare anche dopo una corsa interrotta. Cancella solo righe con LWIN 91000xx, il produttore
 * della prova e i territori `wi007c`, mai altro. Ritorna lo stato finale (atteso `CATALOGO_PULITO`).
 */
export const rimuoviCanonico = (): string => {
  eseguiSql(`begin;
  set local session_replication_role = replica;
  update catalog.public_projection_settings set enabled = false;
  update catalog.sources set authorization_status = 'authorized' where code = 'LIVEX-LWIN7';
  delete from catalog.entity_aliases where wine_id in (select id from catalog.wines where lwin7 like '91000__');
  delete from catalog.wines where lwin7 like '91000__';
  delete from catalog.producers where name = '${PRODUTTORE_CANONICO}' and origin = 'promotion'
    and source_id = (select id from catalog.sources where code = 'LIVEX-LWIN7');
  delete from catalog.source_records where external_id like '91000__' and status = 'Live';
  delete from catalog.territories where natural_key like 'wi007c%';
  commit;`);
  return conteggi();
};
