// Adattatore verso PostgreSQL con il client integrato di Bun (nessuna dipendenza da installare).
// Una sola connessione, così `set role catalog_loader` vale per tutte le istruzioni successive.
import { assertLocalDatabaseUrl } from './paths.mjs';

export async function connectLocal(url, { role = 'catalog_loader' } = {}) {
  assertLocalDatabaseUrl(url);
  if (typeof Bun === 'undefined' || typeof Bun.SQL !== 'function') {
    throw new Error('Il caricatore usa il client PostgreSQL integrato di Bun: eseguire con `bun tools/wine-catalog/lwin-load.mjs`.');
  }
  const sql = new Bun.SQL({ url, max: 1 });
  const db = {
    async query(text, params = []) {
      const rows = await sql.unsafe(text, params);
      return { rows: Array.from(rows) };
    },
    async close() {
      await sql.close();
    },
  };
  if (role) {
    if (!/^[a-z_][a-z0-9_]*$/.test(role)) throw new Error('Nome ruolo non valido.');
    await db.query(`set role ${role}`);
  }
  return db;
}
