// Log limitati e senza segreti (WI-001C). Nessuna riga di dato del catalogo, nessuna URL con credenziali,
// numero massimo di righe e lunghezza massima per riga: un import da 212.894 record non deve produrre un log enorme.

const URL_CREDENTIALS = /\b(postgres(?:ql)?:\/\/)([^\s/@]+)@/gi;

/** Maschera credenziali in URL e ogni segreto noto passato esplicitamente. */
export function redact(text, secrets = []) {
  let out = String(text ?? '').replace(URL_CREDENTIALS, '$1***@');
  for (const s of secrets) {
    if (s && String(s).length >= 4) out = out.split(String(s)).join('***');
  }
  return out;
}

export function limitLine(text, max = 300) {
  const s = String(text);
  return s.length > max ? `${s.slice(0, max)}… [+${s.length - max} caratteri]` : s;
}

/** Errore pronto per log/report: senza segreti, su una riga, troncato. */
export function sanitizeError(err, secrets = []) {
  return limitLine(redact(String(err?.message ?? err), secrets).replace(/\s+/g, ' '), 300);
}

export function createLogger({ secrets = [], maxLines = 200, maxLineChars = 300, sink = (l) => console.error(l) } = {}) {
  let lines = 0;
  let suppressed = 0;
  return {
    log(msg) {
      if (lines >= maxLines) {
        suppressed += 1;
        return;
      }
      lines += 1;
      sink(limitLine(redact(msg, secrets), maxLineChars));
    },
    summary() {
      return { lines, suppressed };
    },
  };
}
