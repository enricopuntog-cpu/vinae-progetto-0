// Scansione lessicale MINIMA del testo SQL per i filtri lato client (difesa in profondità, WI-001C-FIX-02).
// Sostituisce i letterali stringa con `''` e i commenti con uno spazio, riconoscendo: stringhe '…' con '' di escape, stringhe E'…' con
// escape a backslash, identificativi "…", stringhe a dollaro $tag$…$tag$ e commenti annidati /* /* */ */. Se un letterale o un commento
// non è chiuso il testo è RIFIUTATO (fail-closed): un filtro non deve decidere su un testo che non sa leggere.
// Non è un parser SQL e non sostituisce i privilegi del database: la barriera vera resta il ruolo.

// carattere che può far parte di un identificativo non quotato (lettere, cifre, `_`, `$`, caratteri non ASCII)
const IDENT_PART = /[A-Za-z0-9_$\u0080-￿]/;

const DOLLAR_TAG = /\$([A-Za-z_\u0080-￿][A-Za-z0-9_\u0080-￿]*)?\$/y;

export function sanitizeSqlForFilter(text) {
  const s = String(text);
  let out = '';
  let i = 0;
  const n = s.length;
  const bad = (what) => { throw new Error(`Testo SQL non leggibile dal filtro (${what} non chiuso): non ammesso.`); };
  while (i < n) {
    const c = s[i];
    const d = s[i + 1];
    if (c === '-' && d === '-') {
      // il lexer di PostgreSQL chiude il commento `--` sia a `\n` sia a `\r`
      let j = i + 2;
      while (j < n && s[j] !== '\n' && s[j] !== '\r') j += 1;
      out += ' ';
      i = j >= n ? n : j + 1;
    } else if (c === '/' && d === '*') {
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (s[i] === '/' && s[i + 1] === '*') { depth += 1; i += 2; } else if (s[i] === '*' && s[i + 1] === '/') { depth -= 1; i += 2; } else i += 1;
      }
      if (depth > 0) bad('commento');
      out += ' ';
    } else if (c === "'") {
      const prev = out.slice(-1);
      const escapeString = (prev === 'E' || prev === 'e') && !IDENT_PART.test(out.slice(-2, -1) || ' ');
      i += 1;
      let closed = false;
      while (i < n) {
        if (escapeString && s[i] === '\\') { i += 2; continue; }
        if (s[i] === "'") {
          if (s[i + 1] === "'") { i += 2; continue; }
          closed = true;
          i += 1;
          break;
        }
        i += 1;
      }
      if (!closed) bad('letterale');
      out += "''";
    } else if (c === '"') {
      const startQ = i;
      i += 1;
      let closed = false;
      while (i < n) {
        if (s[i] === '"') {
          if (s[i + 1] === '"') { i += 2; continue; }
          closed = true;
          i += 1;
          break;
        }
        i += 1;
      }
      if (!closed) bad('identificativo');
      out += s.slice(startQ, i); // l'identificativo resta leggibile al filtro ("set_config" è comunque set_config)
    } else if (c === '$') {
      // `$` è carattere valido DENTRO un identificativo (`x$q$`): dopo un carattere d'identificativo non apre mai una stringa a dollaro.
      // Si guarda l'ultimo carattere già emesso: dopo un letterale/commento sostituiti (`''`, spazio) o dopo `"…"` il `$` è un nuovo token.
      // tag come nel lexer di PostgreSQL: lettere, `_` e byte non ASCII; senza limite di lunghezza
      DOLLAR_TAG.lastIndex = i;
      const m = IDENT_PART.test(out.slice(-1)) ? null : DOLLAR_TAG.exec(s);
      if (m) {
        const tag = m[0];
        const end = s.indexOf(tag, i + tag.length);
        if (end === -1) bad('letterale a dollaro');
        i = end + tag.length;
        out += "''";
      } else if (!IDENT_PART.test(out.slice(-1)) && !/\d/.test(s[i + 1] ?? '')) {
        // `$` fuori da un identificativo che non è un parametro `$1` né un tag riconosciuto: il filtro non sa leggerlo → rifiuto (fail-closed)
        bad('simbolo $ (tag non riconosciuto)');
      } else { out += c; i += 1; }
    } else { out += c; i += 1; }
  }
  return out;
}
