import { deflateSync } from "node:zlib";

const TABELLA_CRC = (() => {
  const tabella = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    tabella[n] = c >>> 0;
  }
  return tabella;
})();

const crc32 = (dati: Buffer): number => {
  let c = 0xffffffff;
  for (const byte of dati) c = TABELLA_CRC[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

const blocco = (tipo: string, dati: Buffer): Buffer => {
  const lunghezza = Buffer.alloc(4);
  lunghezza.writeUInt32BE(dati.length);
  const corpo = Buffer.concat([Buffer.from(tipo, "ascii"), dati]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(corpo));
  return Buffer.concat([lunghezza, corpo, crc]);
};

/**
 * PNG sintetico e deterministico (tinta unita calda), generato in memoria: nessun
 * file binario nel repository e nessun dato personale. Abbastanza grande da
 * passare per la preparazione WebP del browser.
 */
export const pngSintetico = (larghezza = 640, altezza = 480): Buffer => {
  const riga = Buffer.alloc(1 + larghezza * 3);
  for (let x = 0; x < larghezza; x++) {
    riga[1 + x * 3] = 0x8b;
    riga[2 + x * 3] = 0x2e;
    riga[3 + x * 3] = 0x3c;
  }
  const grezzo = Buffer.concat(Array.from({ length: altezza }, () => riga));
  const intestazione = Buffer.alloc(13);
  intestazione.writeUInt32BE(larghezza, 0);
  intestazione.writeUInt32BE(altezza, 4);
  intestazione[8] = 8; // profondità
  intestazione[9] = 2; // RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    blocco("IHDR", intestazione),
    blocco("IDAT", deflateSync(grezzo)),
    blocco("IEND", Buffer.alloc(0)),
  ]);
};
