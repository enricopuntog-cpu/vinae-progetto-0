// WI-016 — Wine Research, acquisizione da una fonte GIA autorizzata. Si legge soltanto un file locale consegnato dalla
// fonte (esportazione o fixture): nessuna richiesta di rete verso le fonti, nessuno scraping. La fonte NON sta nel file:
// e quella dell'adattatore registrato, che il database riconosce dalla sessione. Autorizzazione, diritti, provenienza,
// doppioni, tetto giornaliero e revisione umana sono decisi dal database (`brain.research_ingest`).

const CAMPI = ["soggetto", "soggetto_id", "attributo", "valore", "riferimento", "acquisita", "attendibilita"];
const MAX_RIGHE = 1000;
const MAX_BYTE_RIGA = 8 * 1024;
const LOTTO = 20;

/** Solo un percorso locale `.jsonl`: nessun protocollo e nessuna condivisione di rete. */
export const percorsoAmmesso = (percorso) =>
  typeof percorso === "string" && percorso.endsWith(".jsonl") && !/^[a-z][a-z0-9+.-]+:\/\//i.test(percorso) && !/^(\\\\|\/\/)/.test(percorso);

// Margine per separatori CRLF e righe vuote, con lo stesso limite per la lettura di prova.
const MAX_BYTE_FILE = 9 * 1024 * 1024;

export async function leggiFileLimitato(chunks) {
  const contenuto = [];
  let byte = 0;
  for await (const chunk of chunks) {
    byte += chunk.byteLength;
    if (byte > MAX_BYTE_FILE) throw new Error("file_troppo_grande");
    contenuto.push(chunk);
  }
  return Buffer.concat(contenuto, byte).toString("utf8");
}

/** Una riga = un elemento. Lo scarto porta il solo numero di riga e un codice, mai il contenuto. */
export function leggiElementi(testo) {
  const righe = String(testo).split(/\r?\n/);
  if (righe.filter((r) => r.trim() !== "").length > MAX_RIGHE) throw new Error("troppe_righe");
  const elementi = [];
  const scartati = [];
  righe.forEach((riga, i) => {
    if (riga.trim() === "") return;
    const scarta = (motivo) => scartati.push({ riga: i + 1, motivo });
    if (Buffer.byteLength(riga) > MAX_BYTE_RIGA) return scarta("riga_troppo_lunga");
    let e;
    try {
      e = JSON.parse(riga);
    } catch {
      return scarta("json_non_valido");
    }
    if (!e || typeof e !== "object" || Array.isArray(e)) return scarta("non_un_oggetto");
    if (Object.keys(e).some((k) => !CAMPI.includes(k))) return scarta("campi_non_ammessi");
    if (CAMPI.some((k) => !(k in e))) return scarta("campi_mancanti");
    elementi.push(e);
  });
  return { elementi, scartati };
}

const codiceSql = (errore) => {
  const grezzo = String(errore?.errno ?? errore?.code ?? "");
  return /^[0-9A-Z]{5}$/.test(grezzo) ? grezzo : "invio";
};

/** `invia(lotto)` e la porta del database. Al primo errore si ferma: nessun ciclo di ritentativi. */
export async function acquisisci(invia, elementi) {
  const totale = { inviati: 0, nuovi: 0, gia_visti: 0, rifiutati: [] };
  for (let i = 0; i < elementi.length; i += LOTTO) {
    const lotto = elementi.slice(i, i + LOTTO);
    let esito;
    try {
      esito = await invia(lotto);
    } catch (errore) {
      return { esito: "interrotto", codice: codiceSql(errore), ...totale };
    }
    totale.inviati += lotto.length;
    totale.nuovi += esito.nuovi;
    totale.gia_visti += esito.gia_visti;
    totale.rifiutati.push(...esito.rifiutati.map((r) => ({ elemento: i + r.indice, codice: r.codice })));
  }
  return { esito: "completato", ...totale };
}
