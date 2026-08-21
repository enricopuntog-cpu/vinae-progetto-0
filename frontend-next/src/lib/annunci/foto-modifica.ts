export const MAX_FOTO = 6;

export type FotoModifica = {
  chiave: string;
  percorso: string;
  anteprima: string;
  origine: "persistita" | "sessione";
};

export function creaBozzaFoto(
  percorsi: string[],
  creaAnteprima: (percorso: string) => string,
): FotoModifica[] {
  return percorsi.map((percorso, indice) => ({
    chiave: `persistita:${indice}:${percorso}`,
    percorso,
    anteprima: creaAnteprima(percorso),
    origine: "persistita",
  }));
}

export function aggiungiFoto(foto: FotoModifica[], nuova: FotoModifica): FotoModifica[] {
  return foto.length >= MAX_FOTO ? foto : [...foto, nuova];
}

export function rimuoviFoto(foto: FotoModifica[], indice: number): FotoModifica[] {
  return foto.filter((_, posizione) => posizione !== indice);
}

export function sostituisciFoto(
  foto: FotoModifica[],
  indice: number,
  nuova: FotoModifica,
): FotoModifica[] {
  if (indice < 0 || indice >= foto.length) return foto;
  return foto.map((elemento, posizione) => (posizione === indice ? nuova : elemento));
}

export function spostaFoto(
  foto: FotoModifica[],
  indice: number,
  direzione: -1 | 1,
): FotoModifica[] {
  const destinazione = indice + direzione;
  if (indice < 0 || indice >= foto.length || destinazione < 0 || destinazione >= foto.length) {
    return foto;
  }

  const riordinate = [...foto];
  [riordinate[indice], riordinate[destinazione]] = [
    riordinate[destinazione],
    riordinate[indice],
  ];
  return riordinate;
}

export const percorsiFoto = (foto: FotoModifica[]): string[] =>
  foto.map((elemento) => elemento.percorso);

export function percorsiSessioneNonUsati(
  percorsiCaricati: Iterable<string>,
  foto: FotoModifica[],
): string[] {
  const usati = new Set(
    foto
      .filter((elemento) => elemento.origine === "sessione")
      .map((elemento) => elemento.percorso),
  );
  return [...new Set(percorsiCaricati)].filter((percorso) => !usati.has(percorso));
}

export function revocaAnteprimeBlob(foto: FotoModifica[]): void {
  for (const elemento of foto) {
    if (elemento.anteprima.startsWith("blob:")) URL.revokeObjectURL(elemento.anteprima);
  }
}
