import { IsolamentoNonProvato, NOME_VARIABILE_CORSA, type BersaglioE2E } from "./support/target";
import {
  RESIDUI_ATTESI,
  generaPasswordFixture,
  generaTokenCorsa,
  puliziaFixture,
  rivendicaStack,
  utentiEstranei,
  utentiFixturePresenti,
  verificaLedgerCoincideConFile,
  verificaResidui,
} from "./support/db";
import { garantisciGatewayDelProgetto, risolviBersaglio } from "./support/stack";

export interface DipendenzeSetup {
  risolviBersaglio: () => BersaglioE2E;
  garantisciGateway: () => void;
  verificaLedger: () => number;
  utentiEstranei: () => number;
  rivendicaStack: (corsa: string) => void;
  utentiFixturePresenti: () => number;
  puliziaFixture: () => string;
  verificaResidui: () => string;
  generaCorsa: () => string;
  generaPassword: () => string;
  env: Record<string, string | undefined>;
}

/**
 * Prima di qualsiasi browser: stack E2E dedicato di questa copia di lavoro
 * (identità, porta del gateway, ledger = file del commit, nessun utente
 * estraneo), poi presa di possesso con un token di corsa, pulizia di un
 * eventuale residuo e password nuova (solo in memoria: i worker la ereditano).
 *
 * La pulizia finale NON è un `globalTeardown`: Playwright lo esegue anche quando
 * il setup fallisce. È la funzione restituita qui, che Playwright chiama solo se
 * questo setup è arrivato in fondo, nello stesso processo; ripete la verifica di
 * identità e possesso a ogni SQL (`eseguiSql`).
 */
export const preparaCorsa = (d: DipendenzeSetup): (() => Promise<void>) => {
  // Un token ereditato dalla shell non vale: il possesso si prende solo qui sotto.
  delete d.env[NOME_VARIABILE_CORSA];

  const bersaglio = d.risolviBersaglio();
  d.garantisciGateway();
  const migrazioni = d.verificaLedger();
  const estranei = d.utentiEstranei();
  if (estranei > 0) {
    throw new IsolamentoNonProvato(`il database contiene ${estranei} utenti Auth estranei alla fixture`);
  }

  const corsa = d.generaCorsa();
  d.rivendicaStack(corsa);
  d.env[NOME_VARIABILE_CORSA] = corsa;
  if (d.utentiFixturePresenti() > 0) d.puliziaFixture();

  d.env.E2E_PASSWORD = d.generaPassword();
  console.log(`[e2e] stack dedicato ${bersaglio.apiUrl}, ${migrazioni} migrazioni = file del commit, 0 utenti estranei`);

  return async () => {
    d.env[NOME_VARIABILE_CORSA] = corsa;
    const residui = d.verificaResidui();
    console.log(`[e2e] pulizia completata, residui e interruttori: "${residui}" (attesi "${RESIDUI_ATTESI}")`);
  };
};

export default async function globalSetup(): Promise<() => Promise<void>> {
  return preparaCorsa({
    risolviBersaglio,
    garantisciGateway: garantisciGatewayDelProgetto,
    verificaLedger: verificaLedgerCoincideConFile,
    utentiEstranei,
    rivendicaStack,
    utentiFixturePresenti,
    puliziaFixture,
    verificaResidui,
    generaCorsa: generaTokenCorsa,
    generaPassword: generaPasswordFixture,
    env: process.env,
  });
}
