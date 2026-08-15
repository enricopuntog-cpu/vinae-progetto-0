import type { SuperficieIA } from "@/lib/phase10/etichette-ia";

/**
 * Feature flag di dominio.
 *
 * Due variabili per flag, e la coppia non è ridondanza:
 *
 * - la variabile **pubblica** (`NEXT_PUBLIC_*`) decide soltanto se una
 *   schermata compare. È nel bundle del browser, quindi chiunque può leggerla e
 *   chiunque può fingerla: non autorizza niente;
 * - la variabile **server** è il gate autoritativo, letto dove il client non
 *   arriva. È quella che conta.
 *
 * Il frontend non è un confine di fiducia, e queste due righe sono il posto in
 * cui è più facile dimenticarselo.
 */

export const valoreFlagEsattamenteTrue = (valore: string | undefined): boolean => valore === "true";

/**
 * Pre-lancio beta — sole superfici UI della Fase 10.
 *
 * Questa flag è pubblica e quindi modificabile da chi controlla il browser:
 * decide esclusivamente se montare i pannelli, non autorizza una chiamata IA.
 * Anche quando è `true`, restano autoritativi `AI_ENABLED`, autenticazione,
 * stato utente e rate limit nelle Edge Function.
 *
 * L'inventario tipizzato evita che una delle tre superfici possa seguire un
 * default diverso dalle altre. Solo la stringa esatta `true` le rende visibili.
 */
const aiUiAbilitata = valoreFlagEsattamenteTrue(process.env.NEXT_PUBLIC_AI_UI_ENABLED);

export const AI_UI: Readonly<Record<SuperficieIA, boolean>> = Object.freeze({
  sommelier: aiUiAbilitata,
  catalogazione: aiUiAbilitata,
  abbinamento: aiUiAbilitata,
});

/**
 * Fase 7 — pagamenti. Kill switch di **tutta** la verticale: checkout,
 * onboarding Connect e rilascio fondi.
 */
export const PAGAMENTI_UI_ABILITATI = valoreFlagEsattamenteTrue(
  process.env.NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED,
);

/**
 * Fase 7c — selezione dell'imballaggio.
 *
 * **Indipendente da quella dei pagamenti, in entrambe le direzioni.** È un
 * requisito esplicito della fase: l'imballaggio può restare visibile con i
 * pagamenti spenti, e i pagamenti possono accendersi senza che l'imballaggio
 * compaia. Legarle sembrerebbe più ordinato e toglierebbe l'unica cosa per cui
 * la flag esiste.
 *
 * Conseguenza da non perdere di vista: con questa accesa e i pagamenti spenti,
 * un ordine nasce con `addebito_totale_cents` più alto di `totale_cents` e
 * nessun addebito reale dietro. È coerente — nessun addebito reale esiste
 * comunque oggi — ma è uno stato che va conosciuto, non scoperto.
 */
export const IMBALLAGGIO_UI_ABILITATO = valoreFlagEsattamenteTrue(
  process.env.NEXT_PUBLIC_PACKAGING_ENABLED,
);

/**
 * Gate server-side dell'imballaggio. Da leggere solo in codice che gira sul
 * server: in un componente client `process.env.PACKAGING_ENABLED` è
 * `undefined`, quindi risulterebbe spento e non acceso — il verso giusto in cui
 * sbagliare, ma comunque un errore.
 */
export const imballaggioAbilitatoServer = (): boolean =>
  valoreFlagEsattamenteTrue(process.env.PACKAGING_ENABLED);
