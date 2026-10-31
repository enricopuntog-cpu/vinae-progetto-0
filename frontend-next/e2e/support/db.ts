import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { CARTELLA_TEST_SQL, fileMigrazioni, risolviBersaglio } from "./stack";
import { IsolamentoNonProvato, confrontaLedger, versioniMigrazioni } from "./target";

/**
 * Esegue SQL nel container del database LOCALE (mai un URL: il bersaglio è il
 * nome del container, validato da `garantisciBersaglioIsolato`). La password
 * della fixture viaggia su stdin come variabile psql, non negli argomenti e non
 * su disco.
 */
export const eseguiSql = (sql: string, variabili: Record<string, string> = {}): string => {
  const { dbContainer } = risolviBersaglio();
  const intestazione = Object.entries(variabili)
    .map(([nome, valore]) => {
      if (!/^[A-Za-z0-9_]+$/.test(nome) || !/^[A-Za-z0-9_.-]*$/.test(valore)) {
        throw new Error("Variabile psql non ammessa.");
      }
      return `\\set ${nome} '${valore}'`;
    })
    .join("\n");
  return execFileSync(
    "docker",
    ["exec", "-i", dbContainer, "psql", "-U", "postgres", "-X", "-q", "-At", "-F", " ", "-v", "ON_ERROR_STOP=1", "-f", "-"],
    { input: `${intestazione}\n${sql}`, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"], timeout: 120_000 },
  ).trim();
};

const leggiSqlDiTest = (nome: string): string => readFileSync(path.join(CARTELLA_TEST_SQL, nome), "utf8");

/** Come in CI: il segnaposto della fixture diventa una variabile psql. */
const conPasswordComeVariabile = (sql: string): string => sql.replace(/'__E2E_PASSWORD__'/g, ":'e2e_password'");

export const generaPasswordFixture = (): string => randomBytes(24).toString("hex");

/** Il ledger dello stack deve coincidere con i file di questo commit. */
export const verificaLedgerCoincideConFile = (): number => {
  const ledger = eseguiSql("select version from supabase_migrations.schema_migrations order by 1;")
    .split(/\s+/)
    .filter(Boolean);
  const { mancanti, inPiu } = confrontaLedger(ledger, versioniMigrazioni(fileMigrazioni()));
  if (mancanti.length || inPiu.length) {
    throw new IsolamentoNonProvato(
      `il ledger non coincide con le migrazioni del commit (mancanti ${mancanti.length}, in più ${inPiu.length})`,
    );
  }
  return ledger.length;
};

/**
 * Riga di residui attesa dopo la pulizia: nove zeri, i tre interruttori della
 * pulizia 12zk spenti e, in coda, la visibilità pubblica della Cantina
 * Accessori, che quella pulizia non azzera e che azzeriamo qui.
 */
export const RESIDUI_ATTESI = "0 0 0 0 0 0 0 0 0 false false false false";

export const utentiFixturePresenti = (): number =>
  Number(eseguiSql("select count(*) from auth.users where email like '%@e2e-12zk.test';"));

/** Riusa la pulizia 12zk della CI; ritorna la riga dei residui. */
export const puliziaFixture = (): string => {
  const uscita = eseguiSql(leggiSqlDiTest("12zk_vpm_015b3_e2e_cleanup.sql"));
  const residui = uscita.split(/\r?\n/).filter(Boolean).pop() ?? "";
  // Solo si spegne (mai si accende): la guardia di accensione non si applica.
  const visibilita = eseguiSql(
    `update private.cantina_accessori_impostazioni set visibilita_pubblica = false, aggiornato_da = null;
     select visibilita_pubblica::text from private.cantina_accessori_impostazioni;`,
  )
    .split(/\r?\n/)
    .filter(Boolean)
    .pop();
  return `${residui} ${visibilita ?? "?"}`;
};

/** Riusa la fixture 12zk della CI (cinque utenti, due amministratori). */
export const creaFixture = (password: string): void => {
  eseguiSql(conPasswordComeVariabile(leggiSqlDiTest("12zk_vpm_015b3_e2e_fixture.sql")), { e2e_password: password });
};

/**
 * Riporta il database a uno stato noto: pulizia di un eventuale residuo di una
 * corsa interrotta, poi fixture nuova. La fixture rifiuta da sola un database
 * con utenti estranei, interruttori accesi o dati Accessori.
 */
export const ripristinaFixture = (password: string): void => {
  if (utentiFixturePresenti() > 0) puliziaFixture();
  creaFixture(password);
};

export const verificaResidui = (): string => {
  const residui = puliziaFixture();
  if (residui !== RESIDUI_ATTESI) {
    throw new Error(`Residui o interruttori dopo la pulizia: "${residui}" (attesi "${RESIDUI_ATTESI}").`);
  }
  return residui;
};
