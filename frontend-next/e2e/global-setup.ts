import { IsolamentoNonProvato } from "./support/target";
import { eseguiSql, generaPasswordFixture, puliziaFixture, utentiFixturePresenti, verificaLedgerCoincideConFile } from "./support/db";
import { risolviBersaglio } from "./support/stack";

/**
 * Prima di qualsiasi browser: bersaglio isolato, stack costruito da questo
 * commit, nessun utente estraneo. Poi password nuova per la corsa (solo in
 * memoria: i worker la ereditano dall'ambiente) e pulizia di un eventuale
 * residuo di una corsa interrotta.
 */
export default async function globalSetup(): Promise<void> {
  const bersaglio = risolviBersaglio();
  const migrazioni = verificaLedgerCoincideConFile();

  const estranei = Number(eseguiSql("select count(*) from auth.users where email not like '%@e2e-12zk.test';"));
  if (estranei > 0) {
    throw new IsolamentoNonProvato(`il database contiene ${estranei} utenti Auth estranei alla fixture`);
  }
  if (utentiFixturePresenti() > 0) puliziaFixture();

  process.env.E2E_PASSWORD = generaPasswordFixture();
  console.log(`[e2e] bersaglio isolato ${bersaglio.apiUrl}, ${migrazioni} migrazioni = file del commit, 0 utenti estranei`);
}
