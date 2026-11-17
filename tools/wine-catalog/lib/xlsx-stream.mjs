// Lettore .xlsx in streaming, senza dipendenze esterne (solo node:fs/zlib).
//
// Perché esiste: il file LWIN pesa ~25 MB compresso ma ~265 MB di XML nel foglio.
// Caricarlo con un parser che materializza il DOM costerebbe gigabyte; qui il
// foglio viene decompresso a chunk e le righe sono emesse una alla volta.
//
// Limiti dichiarati: primo foglio del pacchetto (xl/worksheets/sheet1.xml o il
// più basso per numero), niente zip64, niente cifratura. Un file fuori da
// questi limiti viene rifiutato con errore, non letto a metà.
import { open } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createInflateRaw } from 'node:zlib';
import { StringDecoder } from 'node:string_decoder';

const SIG_EOCD = 0x06054b50;
const SIG_CEN = 0x02014b50;
const MAX_ROW_BUFFER = 16 * 1024 * 1024; // una riga reale pesa poche centinaia di byte

async function readCentralDirectory(path) {
  const fh = await open(path, 'r');
  try {
    const { size } = await fh.stat();
    const tailLen = Math.min(size, 22 + 65535);
    const tail = Buffer.alloc(tailLen);
    await fh.read(tail, 0, tailLen, size - tailLen);
    let eocd = -1;
    for (let i = tailLen - 22; i >= 0; i--) {
      if (tail.readUInt32LE(i) === SIG_EOCD) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw new Error('File non valido: non è uno zip (EOCD assente)');
    const total = tail.readUInt16LE(eocd + 10);
    const cdSize = tail.readUInt32LE(eocd + 12);
    const cdOffset = tail.readUInt32LE(eocd + 16);
    if (cdSize === 0xffffffff || cdOffset === 0xffffffff || total === 0xffff) {
      throw new Error('zip64 non supportato');
    }
    if (cdOffset + cdSize > size) throw new Error('Zip corrotto: directory centrale fuori dal file');
    const cd = Buffer.alloc(cdSize);
    await fh.read(cd, 0, cdSize, cdOffset);
    const entries = new Map();
    let p = 0;
    for (let n = 0; n < total; n++) {
      if (cd.readUInt32LE(p) !== SIG_CEN) throw new Error('Zip corrotto: directory centrale illeggibile');
      if (cd.readUInt16LE(p + 8) & 1) throw new Error('Zip cifrato non supportato');
      const method = cd.readUInt16LE(p + 10);
      const compSize = cd.readUInt32LE(p + 20);
      const nameLen = cd.readUInt16LE(p + 28);
      const extraLen = cd.readUInt16LE(p + 30);
      const commentLen = cd.readUInt16LE(p + 32);
      const localOffset = cd.readUInt32LE(p + 42);
      const name = cd.toString('utf8', p + 46, p + 46 + nameLen);
      entries.set(name, { method, compSize, localOffset });
      p += 46 + nameLen + extraLen + commentLen;
    }
    return { entries, size };
  } finally {
    await fh.close();
  }
}

async function dataStart(path, entry) {
  const fh = await open(path, 'r');
  try {
    const hdr = Buffer.alloc(30);
    await fh.read(hdr, 0, 30, entry.localOffset);
    if (hdr.readUInt32LE(0) !== 0x04034b50) throw new Error('Zip corrotto: header locale illeggibile');
    return entry.localOffset + 30 + hdr.readUInt16LE(26) + hdr.readUInt16LE(28);
  } finally {
    await fh.close();
  }
}

/** Stream di stringhe utf-8 del contenuto (decompresso) di una entry. */
async function* entryText(path, entry) {
  if (entry.method !== 0 && entry.method !== 8) throw new Error(`Metodo zip ${entry.method} non supportato`);
  const start = await dataStart(path, entry);
  const raw = createReadStream(path, { start, end: start + entry.compSize - 1, highWaterMark: 1 << 20 });
  const src = entry.method === 8 ? raw.pipe(createInflateRaw()) : raw;
  raw.on('error', (e) => src.destroy(e));
  const dec = new StringDecoder('utf8');
  for await (const chunk of src) yield dec.write(chunk);
  const rest = dec.end();
  if (rest) yield rest;
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
export function decodeXml(s) {
  if (!s.includes('&')) return s;
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-z]+);/g, (m, e) => {
    if (e[0] === '#') {
      const cp = e[1] === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(cp) && cp <= 0x10ffff ? String.fromCodePoint(cp) : m;
    }
    return ENTITIES[e] ?? m;
  });
}

function textRuns(xml) {
  let out = '';
  const re = /<t\b[^>]*?(?:\/>|>([\s\S]*?)<\/t>)/g;
  let m;
  while ((m = re.exec(xml))) out += m[1] ? decodeXml(m[1]) : '';
  return out;
}

async function loadSharedStrings(path, entry) {
  if (!entry) return [];
  let xml = '';
  for await (const part of entryText(path, entry)) xml += part;
  const out = [];
  const re = /<si\b[^>]*?(?:\/>|>([\s\S]*?)<\/si>)/g;
  let m;
  while ((m = re.exec(xml))) out.push(m[1] ? textRuns(m[1].replace(/<rPh\b[\s\S]*?<\/rPh>/g, '')) : '');
  return out;
}

function colIndex(ref) {
  let n = 0;
  for (const ch of ref) {
    const c = ch.charCodeAt(0);
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

function parseRow(body, shared) {
  const cells = [];
  let next = 0;
  const re = /<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
  let m;
  while ((m = re.exec(body))) {
    const attrs = m[1];
    const ref = /\br="([A-Z]+)\d*"/.exec(attrs);
    const idx = ref ? colIndex(ref[1]) : next;
    const type = /\bt="([^"]*)"/.exec(attrs)?.[1];
    let value = '';
    const inner = m[2];
    if (inner) {
      if (type === 'inlineStr') value = textRuns(inner);
      else {
        const v = /<v\b[^>]*>([\s\S]*?)<\/v>/.exec(inner);
        if (v) value = type === 's' ? (shared[Number(v[1])] ?? '') : decodeXml(v[1]);
      }
    }
    while (cells.length < idx) cells.push('');
    cells[idx] = value;
    next = idx + 1;
  }
  return cells;
}

/** Emette { rowNumber, cells: string[] } per ogni riga del primo foglio. */
export async function* readXlsxRows(path) {
  const { entries } = await readCentralDirectory(path);
  const sheetNames = [...entries.keys()]
    .filter((n) => /^xl\/worksheets\/sheet\d+\.xml$/.test(n))
    .sort((a, b) => parseInt(a.match(/\d+/)[0], 10) - parseInt(b.match(/\d+/)[0], 10));
  if (sheetNames.length === 0) throw new Error('Nessun foglio di lavoro trovato nel pacchetto xlsx');
  const shared = await loadSharedStrings(path, entries.get('xl/sharedStrings.xml'));
  const rowRe = /<row\b([^>]*?)(?:\/>|>([\s\S]*?)<\/row>)/g;
  let buf = '';
  let seq = 0;
  for await (const part of entryText(path, entries.get(sheetNames[0]))) {
    buf += part;
    rowRe.lastIndex = 0;
    let consumed = 0;
    let m;
    while ((m = rowRe.exec(buf))) {
      consumed = rowRe.lastIndex;
      seq += 1;
      const r = /\br="(\d+)"/.exec(m[1]);
      yield { rowNumber: r ? Number(r[1]) : seq, cells: m[2] ? parseRow(m[2], shared) : [] };
    }
    buf = buf.slice(consumed);
    if (buf.length > MAX_ROW_BUFFER) {
      throw new Error(`Foglio malformato: riga oltre il tetto di ${MAX_ROW_BUFFER >> 20} MB senza chiusura`);
    }
  }
}
