const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const eUuidValido = (valore: string): boolean => UUID.test(valore);

/**
 * Una foto della Cantina che non sta nel bucket si riusa così com'è solo se è un'illustrazione
 * nostra o un file del nostro Storage. La colonna `immagini` è scritta dal proprietario: un indirizzo
 * qualunque non deve arrivare a un annuncio che vedono gli altri (GAP-020).
 */
export const fotoDirettaAmmessa = (origine: string, urlSupabase: string | undefined): boolean => {
  if (origine.startsWith("/")) {
    return origine.startsWith("/images/") && !/\/\/|\\|\.\./.test(origine);
  }
  if (!urlSupabase) return false;
  try {
    return new URL(origine).origin === new URL(urlSupabase).origin;
  } catch {
    return false;
  }
};
