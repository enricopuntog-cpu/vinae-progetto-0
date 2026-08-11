// Fase 10c — identificativo di conversazione del Sommelier.
//
// Lo genera il client, come in `frontend/` (`frontend/src/components/vinea/
// SommelierChat.tsx:12-26`), e non il server. Non è una svista di parità: quel
// valore non porta nessuna autorità. La vista `my_sommelier_messages` filtra su
// `(owner_id, session_id)` e prende `owner_id` da `auth.uid()` al proprio
// interno, quindi indovinare il `session_id` di un altro non serve a leggerne
// niente — al massimo si scrive nella propria conversazione con un nome scelto
// male. È la ragione per cui la vista non filtra mai sul solo `session_id`.
//
// Il formato deve però passare due controlli scritti altrove, e questo file è
// l'unico posto in cui viene costruito:
//   * il `check` della colonna
//     (`supabase/migrations/20260811160000_phase_10b_sommelier_storico.sql`,
//     `session_id ~ '^[A-Za-z0-9_-]{4,64}$'`);
//   * la stessa espressione nella Edge Function
//     (`supabase/functions/ai-sommelier/index.ts`).
// Un identificativo fuori formato non dà un errore comprensibile: dà un 400
// dalla function o un 23514 dal database, cioè una conversazione che non parte
// senza dire perché.

export const SESSION_ID_VALIDO = /^[A-Za-z0-9_-]{4,64}$/;

const CHIAVE = "vinea:sommelier:session";

/**
 * Forma identica a quella del legacy: `s-<base36 casuale>-<base36 del tempo>`.
 *
 * `Math.random().toString(36).slice(2)` può restituire stringa vuota (per
 * `Math.random() === 0` il testo è `"0"` e `slice(2)` non lascia niente): la
 * lunghezza minima resta comunque soddisfatta dalla parte temporale, ed è il
 * motivo per cui il test verifica il formato su molte estrazioni invece che su
 * una sola.
 */
export const nuovoSessionId = (): string =>
  `s-${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`;

/** Il minimo di `localStorage` che serve qui, per poterlo sostituire nei test. */
export type Deposito = {
  getItem(chiave: string): string | null;
  setItem(chiave: string, valore: string): void;
};

/**
 * Riprende l'identificativo già depositato, o ne conia uno e lo deposita.
 *
 * Ogni accesso al deposito è protetto: in navigazione privata `localStorage`
 * esiste ma solleva, e una conversazione senza memoria è un difetto minore di
 * un pannello che non si apre. Un valore depositato che non passa il formato
 * viene sostituito invece che riusato — è il caso di chi ha un residuo di una
 * versione precedente.
 */
export const sessionIdPersistente = (deposito: Deposito | null): string => {
  try {
    const salvato = deposito?.getItem(CHIAVE);
    if (salvato && SESSION_ID_VALIDO.test(salvato)) return salvato;
  } catch {
    /* deposito non leggibile */
  }
  const coniato = nuovoSessionId();
  try {
    deposito?.setItem(CHIAVE, coniato);
  } catch {
    /* deposito non scrivibile: l'identificativo vive quanto la scheda */
  }
  return coniato;
};

/** Il deposito del browser, o `null` quando non c'è (render sul server). */
export const depositoBrowser = (): Deposito | null =>
  typeof window === "undefined" ? null : window.localStorage;
