// WI-015 — contratto di acquisizione delle osservazioni di prezzo per la valutazione WI-014. SPENTO per difetto e non
// collegato a nessun dominio: nessuna lettura di ordini o transazioni reali finché il founder non decide finalità e
// trattamento dei dati. Una fonte si legge solo con l'acquisizione accesa (esattamente `true`), autorizzata e con una
// finalità dichiarata. L'elenco dei campi è CHIUSO: una riga con un campo in più (persone, ordini, contatti) viene
// scartata intera, così un produttore che manda dati personali si vede invece di passare ripulito.

import type { OsservazionePrezzo } from "./valutazione";

const CAMPI = ["id", "tipo", "centesimi", "valuta", "osservatoIl", "fonte", "vinoId", "annata", "formatoMl", "condizione"] as const;

export type FonteOsservazioni = {
  nome: string;
  /** Diritto di usare la fonte, verificato fuori da qui. */
  autorizzata: boolean;
  /** Finalità del trattamento approvata; vuota = non leggere. */
  finalita: string | null;
  leggi: () => Promise<unknown[]>;
};

export type Raccolta =
  | { esito: "disattivata" }
  | { esito: "raccolte"; osservazioni: OsservazionePrezzo[]; scartate: number; fontiEscluse: number };

const testo = (v: unknown, massimo = 120): v is string => typeof v === "string" && v.length > 0 && v.length <= massimo;
const interoONullo = (v: unknown): boolean => v === null || Number.isInteger(v);

export function accettaOsservazione(riga: unknown, nomeFonte: string): OsservazionePrezzo | null {
  if (!riga || typeof riga !== "object" || Array.isArray(riga)) return null;
  const r = riga as Record<string, unknown>;
  if (Object.keys(r).some((k) => !(CAMPI as readonly string[]).includes(k))) return null;
  if (
    !testo(r.id) ||
    (r.tipo !== "richiesto" && r.tipo !== "realizzato") ||
    !Number.isInteger(r.centesimi) ||
    (r.centesimi as number) <= 0 ||
    typeof r.valuta !== "string" ||
    !/^[a-z]{3}$/.test(r.valuta) ||
    !testo(r.osservatoIl, 40) ||
    Number.isNaN(Date.parse(r.osservatoIl)) ||
    r.fonte !== nomeFonte ||
    !testo(r.vinoId) ||
    !interoONullo(r.annata) ||
    !interoONullo(r.formatoMl) ||
    !(r.condizione === null || testo(r.condizione, 40))
  ) {
    return null;
  }
  return r as unknown as OsservazionePrezzo;
}

export async function raccogliOsservazioni(
  fonti: readonly FonteOsservazioni[],
  { attiva }: { attiva?: boolean } = {},
): Promise<Raccolta> {
  if (attiva !== true) return { esito: "disattivata" };
  const osservazioni: OsservazionePrezzo[] = [];
  let scartate = 0;
  let fontiEscluse = 0;
  for (const fonte of fonti) {
    if (!fonte.autorizzata || !fonte.finalita?.trim()) {
      fontiEscluse += 1;
      continue;
    }
    for (const riga of await fonte.leggi()) {
      const o = accettaOsservazione(riga, fonte.nome);
      if (o) osservazioni.push(o);
      else scartate += 1;
    }
  }
  return { esito: "raccolte", osservazioni, scartate, fontiEscluse };
}
