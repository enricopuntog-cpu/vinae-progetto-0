// WI-016 — esecuzione periodica indipendente dall'ospite (contenitore, macchina virtuale o servizio di sistema).
// Un errore isolato non ferma il ciclo; errori di fila lo fermano con uscita diversa da zero, cosi l'ospite riavvia e
// avvisa invece di lasciare un processo vivo che non fa nulla.

/** Minuti fra due giri: da 5 a 1440. Un valore mancante o fuori limite non ha un valore di ripiego. */
export const intervalloMs = (minuti) => {
  const n = Number(minuti);
  return Number.isInteger(n) && n >= 5 && n <= 1440 ? n * 60_000 : null;
};

export async function cicloPeriodico({ giro, attendi, intervallo, maxErroriDiFila = 3, continua }) {
  let giri = 0;
  let errori = 0;
  while (continua()) {
    giri++;
    try {
      await giro();
      errori = 0;
    } catch {
      errori++;
      if (errori >= maxErroriDiFila) return { esito: "troppi_errori", giri };
    }
    if (!continua()) break;
    await attendi(intervallo);
  }
  return { esito: "arrestato", giri };
}
