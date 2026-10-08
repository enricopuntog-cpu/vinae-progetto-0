/**
 * Superficie pubblica e isolata della Market Validation. Il tester è
 * identificato soltanto da codice Vxxx + capability anonima, verificati dalle
 * RPC dedicate: nessun account, login o sessione Supabase Auth è richiesto, e
 * una sessione Vinea eventualmente presente nel browser non deve influire.
 *
 * Per questo le guardie globali sull'account (AgeGate: attesa della sessione,
 * completamento profilo, errore di lettura) non si applicano qui. Non allarga
 * nulla: le porte server e le RPC restano le stesse, e /admin/beta-validation
 * non fa parte di questa superficie.
 */
export const PERCORSI_MARKET_VALIDATION_ANONIMI: readonly string[] = ["/beta-test"] as const;

// Stesso confronto di `percorsoAttivo` della shell: la rotta o una sua
// sottorotta, mai un prefisso nudo come /beta-testing.
export const superficieMarketValidationAnonima = (pathname: string | null | undefined): boolean =>
  typeof pathname === "string" &&
  PERCORSI_MARKET_VALIDATION_ANONIMI.some(
    (percorso) => pathname === percorso || pathname.startsWith(`${percorso}/`),
  );
