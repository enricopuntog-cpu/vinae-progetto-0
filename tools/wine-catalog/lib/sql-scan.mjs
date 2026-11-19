// Scansione lessicale MINIMA del testo SQL per i filtri lato client (difesa in profondità, WI-001C-FIX-02).
// Sostituisce i letterali stringa con `''` e i commenti con uno spazio, riconoscendo: stringhe '…' con '' di escape, stringhe E'…' con
// escape a backslash, identificativi "…", stringhe a dollaro $tag$…$tag$ e commenti annidati /* /* */ */. Se un letterale o un commento
// non è chiuso il testo è RIFIUTATO (fail-closed): un filtro non deve decidere su un testo che non sa leggere.
// Non è un parser SQL e non sostituisce i privilegi del database: la barriera vera resta il ruolo.

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
      const nl = s.indexOf('\n', i);
      out += ' ';
      i = nl === -1 ? n : nl + 1;
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
      const escapeString = (prev === 'E' || prev === 'e') && !/[A-Za-z0-9_$]/.test(out.slice(-2, -1) || ' ');
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
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(s.slice(i, i + 80));
      if (m) {
        const tag = m[0];
        const end = s.indexOf(tag, i + tag.length);
        if (end === -1) bad('letterale a dollaro');
        i = end + tag.length;
        out += "''";
      } else { out += c; i += 1; }
    } else { out += c; i += 1; }
  }
  return out;
}
