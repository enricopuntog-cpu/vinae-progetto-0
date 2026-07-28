/**
 * Validazione 18+ lato client.
 *
 * IMPORTANTE — natura del controllo: questa è la verifica *client* di una
 * DICHIARAZIONE AUTO-RIFERITA di data di nascita raccolta al momento della
 * registrazione (checkbox "Confermo di essere maggiorenne"). Non è, e non
 * sostituisce, una verifica documentale dell'identità o dell'età: nessun
 * documento viene caricato o controllato.
 *
 * La barriera autoritativa è lato server, nel CHECK su public.profiles.dob
 * (vedi supabase/migrations/20260728000545_auth_profiles_roles.sql), che
 * respinge la creazione del profilo per date di nascita che indichino un'età
 * inferiore a 18 anni anche se questo controllo client venisse aggirato.
 * Le due regole sono volutamente identiche nella semantica
 * (`dob <= current_date - interval '18 years'`).
 *
 * L'intero meccanismo richiede validazione legale dedicata prima di un
 * lancio pubblico reale (vendita di alcolici, tutela dei minori, privacy):
 * vedi "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.
 */

/**
 * Vero se `dob` (formato YYYY-MM-DD) corrisponde ad almeno 18 anni compiuti
 * alla data `oggi`. Usa aritmetica di calendario, non una divisione per
 * 365.25 giorni, per coincidere esattamente con il CHECK SQL.
 *
 * Nota: `oggi` è la data locale del browser mentre il server usa
 * `current_date` (UTC). Uno scostamento di un giorno a cavallo della
 * mezzanotte è possibile; è irrilevante perché il database resta la fonte
 * autoritativa e questo controllo serve solo al feedback immediato in UI.
 */
export function isMaggiorenne(dob: string, oggi: Date): boolean {
  const nascita = Date.parse(`${dob}T00:00:00Z`);
  if (Number.isNaN(nascita)) return false;

  const soglia = Date.UTC(oggi.getFullYear() - 18, oggi.getMonth(), oggi.getDate());
  return nascita <= soglia;
}
