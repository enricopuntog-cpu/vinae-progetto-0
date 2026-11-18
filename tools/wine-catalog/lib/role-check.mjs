// Verifica del ruolo PostgreSQL effettivo della sessione (WI-001B). Indipendente da Bun: riceve una funzione
// `query(text, params) → { rows }`, così è provabile con un database finto nei test Node.

/**
 * Controlla che la sessione stia davvero operando come `expected` e con i soli privilegi previsti:
 *  - current_user = expected (un `set role` perso dopo una riconnessione si vede qui);
 *  - il ruolo non è superuser, non ha BYPASSRLS, CREATEROLE, CREATEDB, REPLICATION e non può fare login;
 *  - non è (nemmeno per eredità) membro di anon / authenticated / service_role;
 *  - ha USAGE sullo schema catalog e nessun privilegio sullo schema public (il caricatore non tocca il resto).
 * Lancia con un messaggio che nomina il controllo fallito.
 */
export async function assertEffectiveRole(query, expected) {
  const r = await query(
    `select current_user::text as cu,
            (select rolsuper from pg_roles where rolname = current_user) as su,
            (select rolbypassrls from pg_roles where rolname = current_user) as bypass,
            (select rolcreaterole or rolcreatedb or rolreplication from pg_roles where rolname = current_user) as powers,
            (select rolcanlogin from pg_roles where rolname = current_user) as can_login,
            (select count(*)::int from pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role') and pg_has_role(current_user, x.oid, 'member')) as client_roles,
            has_schema_privilege(current_user, 'catalog', 'USAGE') as catalog_usage,
            coalesce(has_schema_privilege(current_user, 'public', 'CREATE'), false) as public_create`,
  );
  const row = r.rows[0];
  if (!row) throw new Error('Verifica del ruolo: nessuna risposta dal database.');
  const fail = (why) => { throw new Error(`Verifica del ruolo fallita (${why}): operazione privilegiata rifiutata.`); };
  if (row.cu !== expected) fail(`ruolo effettivo "${row.cu}" invece di "${expected}"`);
  if (row.su) fail('il ruolo è superuser');
  if (row.bypass) fail('il ruolo ha BYPASSRLS');
  if (row.powers) fail('il ruolo ha CREATEROLE/CREATEDB/REPLICATION');
  if (row.can_login) fail('il ruolo può fare login');
  if (Number(row.client_roles) > 0) fail('il ruolo è membro di anon/authenticated/service_role');
  if (!row.catalog_usage) fail('manca USAGE sullo schema catalog');
  if (row.public_create) fail('il ruolo può creare oggetti in public');
  return row;
}
