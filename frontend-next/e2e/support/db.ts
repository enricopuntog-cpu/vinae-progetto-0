import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { CARTELLA_TEST_SQL, fileMigrazioni, leggiIdentita, risolviBersaglio } from "./stack";
import { IsolamentoNonProvato, NOME_VARIABILE_CORSA, confrontaLedger, corsaPerSql, sqlProtetto, versioniMigrazioni } from "./target";

/**
 * Esegue SQL nel container dello stack E2E DEDICATO (mai un URL, mai un
 * container scelto dall'ambiente). Ogni chiamata rilegge bersaglio e identità e
 * antepone la verifica del marcatore nella stessa sessione psql: se il database
 * non è lo stack di questa copia di lavoro, o la corsa non lo possiede più,
 * nessuna istruzione parte. La password della fixture viaggia su stdin come
 * variabile psql, non negli argomenti e non su disco.
 */
export const eseguiSql = (
  sql: string,
  variabili: Record<string, string> = {},
  { primaDelPossesso = false }: { primaDelPossesso?: boolean } = {},
): string => {
  const { dbContainer } = risolviBersaglio();
  const { nonce } = leggiIdentita();
  const corsa = corsaPerSql(process.env[NOME_VARIABILE_CORSA], primaDelPossesso);
  return execFileSync(
    "docker",
    ["exec", "-i", dbContainer, "psql", "-U", "postgres", "-X", "-q", "-At", "-F", " ", "-v", "ON_ERROR_STOP=1", "-f", "-"],
    { input: sqlProtetto(sql, variabili, { nonce, corsa }), encoding: "utf8", stdio: ["pipe", "pipe", "pipe"], timeout: 120_000 },
  ).trim();
};

/** Il setup prende possesso dello stack: una corsa precedente ancora viva non passa più la guardia. */
export const rivendicaStack = (corsa: string): void => {
  eseguiSql("update vinea_e2e.identita set corsa = :'e2e_corsa_nuova';", { e2e_corsa_nuova: corsa }, { primaDelPossesso: true });
};

/** Utenti Auth estranei alla fixture, comprese le righe senza email. */
export const utentiEstranei = (): number =>
  Number(
    eseguiSql("select count(*) from auth.users where coalesce(email, '') not like '%@e2e-12zk.test';", {}, { primaDelPossesso: true }),
  );

const leggiSqlDiTest = (nome: string): string => readFileSync(path.join(CARTELLA_TEST_SQL, nome), "utf8");

/** Come in CI: il segnaposto della fixture diventa una variabile psql. */
const conPasswordComeVariabile = (sql: string): string => sql.replace(/'__E2E_PASSWORD__'/g, ":'e2e_password'");

export const generaPasswordFixture = (): string => randomBytes(24).toString("hex");

export const generaTokenCorsa = (): string => randomBytes(16).toString("hex");

/** Il ledger dello stack deve coincidere con i file di questo commit. */
export const verificaLedgerCoincideConFile = (): number => {
  const ledger = eseguiSql("select version from supabase_migrations.schema_migrations order by 1;", {}, { primaDelPossesso: true })
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

/**
 * Residui delle tabelle figlie che la riga di 12zk non conta (la CI la confronta alla lettera, quindi non si
 * cambia): ordini, pagamenti, post-vendita, rimborsi, resi, movimenti, Partner e inviti, e le prove private e gli eventi del fornitore simulati.
 * Atteso: tutti zero. Righe senza genitore contano come residuo.
 */
export const RESIDUI_FIGLI_ATTESI = "0 0 0 0 0 0 0 0 0";

const residuiFigli = (): string =>
  eseguiSql(`select
    (select count(*) from private.accessori_ordini),
    (select count(*) from private.accessori_pagamenti),
    (select count(*) from private.accessori_postvendita),
    (select count(*) from private.accessori_contestazioni),
    (select count(*) from private.accessori_rimborsi) + (select count(*) from private.accessori_resi),
    (select count(*) from private.accessori_partner_movimenti),
    (select count(*) from private.partners) + (select count(*) from private.partner_inviti),
    (select count(*) from storage.objects where bucket_id = 'dispute-evidence' and name like '%/12ab2000-%'),
    (select count(*) from public.payment_provider_events where event_id like 'evt_e2e\_%');`)
    .split(/\r?\n/)
    .filter(Boolean)
    .pop() ?? "?";

export const verificaResidui = (): string => {
  const residui = puliziaFixture();
  if (residui !== RESIDUI_ATTESI) {
    throw new Error(`Residui o interruttori dopo la pulizia: "${residui}" (attesi "${RESIDUI_ATTESI}").`);
  }
  const figli = residuiFigli();
  if (figli !== RESIDUI_FIGLI_ATTESI) {
    throw new Error(`Residui nelle tabelle figlie dopo la pulizia: "${figli}" (attesi "${RESIDUI_FIGLI_ATTESI}").`);
  }
  return residui;
};
