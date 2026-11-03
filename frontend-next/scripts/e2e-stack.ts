#!/usr/bin/env bun
// Stack Supabase E2E DEDICATO per la suite browser (VPM-LAB-003, VPM-018-FIX-E2E-01).
//
//   bun run e2e:stack up      avvia il progetto riservato `vinea_e2e` (porte 553xx) con le migrazioni del checkout
//   bun run e2e:stack status  stato dei container (senza stampare le chiavi)
//   bun run e2e:stack down --conferma   DISTRUGGE (--no-backup) solo lo stack dedicato di questa copia di lavoro
//
// Mai il progetto di sviluppo di `supabase/config.toml`, mai un progetto ospitato.
// Le guardie sono in `e2e/support/target.ts` (pure, con test in `bun test`).

import { spawnSync, type SpawnSyncOptions } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, rmSync, writeFileSync } from "node:fs";
import { FILE_IDENTITA, RADICE_REPO, garantisciGatewayDelProgetto, leggiIdentita, projectIdSviluppo } from "../e2e/support/stack";
import {
  CONTAINER_DB_E2E,
  ETICHETTA_PROGETTO,
  IsolamentoNonProvato,
  PORTE_E2E,
  PROJECT_ID_E2E,
  SQL_MARCATORE,
  SUPABASE_CLI_VERSION,
  ambienteStackE2E,
  decidiDown,
  decidiUp,
  type IdentitaStack,
} from "../e2e/support/target";

const ESCLUSI = "realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor";
const RISORSE_NON_RIMOSSE =
  `Le risorse del progetto \`${PROJECT_ID_E2E}\` non vengono rimosse da qui ` +
  "(potrebbero essere di un'altra copia di lavoro avviata nello stesso momento). " +
  "Solo dopo aver verificato che nessun altro worktree abbia `frontend-next/e2e/.stack-e2e.json`: " +
  `npx --yes supabase@${SUPABASE_CLI_VERSION} stop --no-backup --project-id ${PROJECT_ID_E2E}`;

const supabase = (args: string[], opzioni: SpawnSyncOptions = { stdio: "inherit" }) =>
  spawnSync("npx", ["--yes", `supabase@${SUPABASE_CLI_VERSION}`, ...args], {
    cwd: RADICE_REPO,
    shell: process.platform === "win32",
    ...opzioni,
    env: {
      ...process.env,
      ...ambienteStackE2E(),
      SUPABASE_INTERNAL_IMAGE_REGISTRY: process.env.SUPABASE_INTERNAL_IMAGE_REGISTRY ?? "public.ecr.aws",
    },
  });

const docker = (args: string[], input?: string): { ok: boolean; out: string } => {
  const esito = spawnSync("docker", args, { encoding: "utf8", input, stdio: ["pipe", "pipe", "pipe"] });
  return { ok: esito.status === 0, out: (esito.stdout ?? "").trim() };
};

const righe = (testo: string): string[] => testo.split(/\r?\n/).map((r) => r.trim()).filter(Boolean);

/** Container e volumi del progetto riservato, per etichetta della CLI e per nome. */
const risorseDelProgettoE2E = (): string[] => {
  const nomi = new Set<string>();
  for (const filtro of [`label=${ETICHETTA_PROGETTO}=${PROJECT_ID_E2E}`, `name=_${PROJECT_ID_E2E}`]) {
    righe(docker(["ps", "-a", "--filter", filtro, "--format", "{{.Names}}"]).out).forEach((n) => nomi.add(n));
    righe(docker(["volume", "ls", "--filter", filtro, "--format", "{{.Name}}"]).out).forEach((n) => nomi.add(n));
  }
  return [...nomi].sort();
};

const etichettaDelContainer = (container: string): string | null => {
  const esito = docker(["inspect", "-f", `{{.State.Running}} {{index .Config.Labels "${ETICHETTA_PROGETTO}"}}`, container]);
  if (!esito.ok) return null;
  const [inEsecuzione, progetto] = esito.out.split(" ");
  return inEsecuzione === "true" ? (progetto ?? null) : null;
};

/** Sola lettura: il nonce scritto da `up` nel database del container riservato. */
const nonceNelDatabase = (): string | null => {
  const esito = docker([
    "exec", CONTAINER_DB_E2E, "psql", "-U", "postgres", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1",
    "-c", "select nonce from vinea_e2e.identita;",
  ]);
  return esito.ok && esito.out ? esito.out : null;
};

const identitaSeEsiste = (): IdentitaStack | null => {
  try {
    return leggiIdentita();
  } catch {
    return null;
  }
};

const esci = (messaggio: string, codice = 2): never => {
  console.error(messaggio);
  process.exit(codice);
};

const comando = process.argv[2];

try {
  if (PROJECT_ID_E2E === projectIdSviluppo()) esci("Il progetto E2E coincide con quello di sviluppo: rifiutato.");

  if (comando === "up") {
    if (!docker(["info"]).ok) {
      esci("Docker non è in esecuzione: avviare Docker Desktop e riprovare. Senza stack isolato i casi sono NON VERIFICATI.");
    }
    decidiUp(risorseDelProgettoE2E());

    // L'output di `supabase start` contiene le chiavi dello stack: non lo mostriamo.
    const esito = supabase(["start", "--exclude", ESCLUSI], { encoding: "utf8" });
    if (esito.status !== 0) {
      const filtrato = `${esito.stdout}\n${esito.stderr}`
        .split(/\r?\n/)
        .filter((r) => !/key|secret|jwt|token|password|postgres(ql)?:\/\//i.test(r))
        .slice(-20)
        .join("\n");
      console.error(filtrato);
      esci(`Stack non avviato. ${RISORSE_NON_RIMOSSE}`, esito.status ?? 1);
    }

    // Da qui uno stack esiste ma non ha ancora un proprietario. Non lo si ferma da solo: con due `up`
    // concorrenti il secondo fallirebbe sul marcatore e distruggerebbe lo stack del primo.
    try {
      // La CLI ha davvero usato il progetto e le porte riservati?
      if (etichettaDelContainer(CONTAINER_DB_E2E) !== PROJECT_ID_E2E) {
        throw new IsolamentoNonProvato(`dopo l'avvio manca il container \`${CONTAINER_DB_E2E}\``);
      }
      garantisciGatewayDelProgetto();

      // Marcatore di possesso: `create schema` senza `if not exists` fallisce su uno stack non nuovo.
      const nonce = randomBytes(16).toString("hex");
      const marcatore = docker(
        ["exec", "-i", CONTAINER_DB_E2E, "psql", "-U", "postgres", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", "-"],
        `\\set e2e_nonce '${nonce}'\n${SQL_MARCATORE}\n`,
      );
      if (!marcatore.ok || nonceNelDatabase() !== nonce) {
        throw new IsolamentoNonProvato("marcatore dello stack E2E non scritto: lo stack non era nuovo");
      }
      writeFileSync(
        FILE_IDENTITA,
        `${JSON.stringify({ projectId: PROJECT_ID_E2E, nonce, creatoIl: new Date().toISOString() }, null, 2)}\n`,
      );
    } catch (errore) {
      if (errore instanceof IsolamentoNonProvato) esci(`${errore.message}. ${RISORSE_NON_RIMOSSE}`);
      throw errore;
    }
    console.log(`Stack E2E dedicato \`${PROJECT_ID_E2E}\` avviato (API 127.0.0.1:${PORTE_E2E.api}) con le migrazioni del checkout.`);
  } else if (comando === "down") {
    const argomenti = decidiDown({
      conferma: process.argv.includes("--conferma"),
      identita: identitaSeEsiste(),
      etichettaContainer: etichettaDelContainer(CONTAINER_DB_E2E),
      nonceNelDatabase: nonceNelDatabase(),
    });
    const esito = supabase(argomenti);
    if (esito.status !== 0) esci("Arresto dello stack E2E non riuscito.", esito.status ?? 1);
    rmSync(FILE_IDENTITA, { force: true });
    console.log(`Stack E2E dedicato \`${PROJECT_ID_E2E}\` distrutto.`);
  } else if (comando === "status") {
    const esito = docker(["ps", "--filter", "name=supabase_", "--format", "{{.Names}} {{.Status}}"]);
    console.log(esito.out || "Nessun container supabase_* in esecuzione.");
    console.log(
      existsSync(FILE_IDENTITA)
        ? `Stack E2E dedicato di questa copia di lavoro: \`${PROJECT_ID_E2E}\` (file di identità presente).`
        : "Nessuno stack E2E dedicato creato da questa copia di lavoro.",
    );
  } else {
    esci("Uso: bun run e2e:stack up|status|down --conferma");
  }
} catch (errore) {
  if (errore instanceof IsolamentoNonProvato) esci(errore.message);
  throw errore;
}
