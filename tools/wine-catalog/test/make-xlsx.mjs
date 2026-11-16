// Helper di test: costruisce un .xlsx minimo (zip con entry deflate) interamente
// in memoria. Nessun file esterno, nessun dato reale.
import { deflateRawSync, crc32 } from 'node:zlib';

function zip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const [name, content] of entries) {
    const nameBuf = Buffer.from(name);
    const raw = Buffer.from(content);
    const data = deflateRawSync(raw);
    const crc = typeof crc32 === 'function' ? crc32(raw) : 0;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(8, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(8, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt32LE(offset, 42);
    locals.push(local, nameBuf, data);
    centrals.push(central, nameBuf);
    offset += 30 + nameBuf.length + data.length;
  }
  const cd = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, eocd]);
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const col = (i) => String.fromCharCode(65 + i);

/** Pacchetto xlsx il cui foglio contiene esattamente `sheetXml` (anche malformato). */
export function makeRawSheetXlsx(sheetXml) {
  return zip([['xl/worksheets/sheet1.xml', sheetXml]]);
}

/** rows: array di array. Una stringa diventa inlineStr (o shared se opts.shared);
 *  un numero diventa t="n"; null/'' diventa cella vuota. */
export function makeXlsx(rows, { shared = false } = {}) {
  const sst = [];
  const sheetRows = rows.map((r, ri) => {
    const cells = r.map((v, ci) => {
      const ref = `${col(ci)}${ri + 1}`;
      if (v === null || v === undefined) return `<c r="${ref}"/>`;
      if (typeof v === 'number') return `<c r="${ref}" t="n"><v>${v}</v></c>`;
      if (shared) {
        sst.push(v);
        return `<c r="${ref}" t="s"><v>${sst.length - 1}</v></c>`;
      }
      return `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;
    });
    return `<row r="${ri + 1}">${cells.join('')}</row>`;
  });
  const sheet =
    '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    `<sheetData>${sheetRows.join('\n')}</sheetData></worksheet>`;
  const sstXml =
    '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    sst.map((s) => `<si><t>${esc(s)}</t></si>`).join('') +
    '</sst>';
  return zip([
    ['xl/sharedStrings.xml', sstXml],
    ['xl/worksheets/sheet1.xml', sheet],
  ]);
}
