// Adattatore verso PostgreSQL con il client integrato di Bun (nessuna dipendenza da installare).
// Una sola connessione. Il ruolo `catalog_loader` NON si imposta con un `set role` dopo la connessione (andrebbe perso se
// il client si ricollega): lo si passa come parametro di AVVIO della sessione, quindi vale per ogni connessione che il
// client apre. In più `assertRole()` verifica il ruolo effettivo prima di ogni operazione privilegiata.
import { assertLocalDatabaseUrl } from './paths.mjs';
import { assertEffectiveRole } from './role-check.mjs';

export async function connectLocal(url, { role = 'catalog_loader' } = {}) {
  assertLocalDatabaseUrl(url);
  if (typeof Bun === 'undefined' || typeof Bun.SQL !== 'function') {
    throw new Error('Il caricatore usa il client PostgreSQL integrato di Bun: eseguire con `bun tools/wine-catalog/lwin-load.mjs`.');
  }
  if (!role || !/^[a-z_][a-z0-9_]*$/.test(role)) throw new Error('Ruolo mancante o non valido: il caricatore non opera mai con il ruolo di connessione.');
  const sql = new Bun.SQL({ url, max: 1, connection: { role } });
  const db = {
    async query(text, params = []) {
      const rows = await sql.unsafe(text, params);
      return { rows: Array.from(rows) };
    },
    async close() {
      await sql.close();
    },
    /** Verifica il ruolo EFFETTIVO della sessione corrente (da chiamare prima di ogni operazione privilegiata). */
    async assertRole() {
      await assertEffectiveRole((t, p) => db.query(t, p), role);
    },
  };
  await db.assertRole();
  return db;
}
