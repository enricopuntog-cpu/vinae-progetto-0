import { RESIDUI_ATTESI, verificaResidui } from "./support/db";

/** Pulizia finale e prova dei residui: fixture, dati Accessori e interruttori a zero. */
export default async function globalTeardown(): Promise<void> {
  const residui = verificaResidui();
  console.log(`[e2e] pulizia completata, residui e interruttori: "${residui}" (attesi "${RESIDUI_ATTESI}")`);
}
