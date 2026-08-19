/**
 * Il badge che dice, sulla foto di una scheda in Cantina, che la bottiglia è
 * già stata aperta.
 *
 * ## Perché è un modulo e non tre righe dentro `WineCard`
 *
 * Perché la promessa che fa — «questo badge si legge» — è una misura, e in
 * questo repository non c'è modo di montare un componente React in un test
 * (niente jsdom, niente testing-library: è la stessa lacuna registrata dal
 * Gruppo 2 per i dialoghi di apertura). Un colore scelto a occhio dentro il JSX
 * non è verificabile da nessuno; qui la coppia di colori è un dato, il calcolo
 * del contrasto è una funzione, e la soglia è un caso di test.
 *
 * ## Il difetto che questo badge non ripete
 *
 * I badge della finestra di bevuta usano sfondi **traslucidi**: `phaseColor`
 * dà a «Pronto ora» le classi `bg-salvia/25 text-salvia`
 * (`src/data/cellar.ts`). Un badge traslucido sovrapposto a una foto non ha un
 * contrasto proprio — ce l'ha *insieme alla foto che ha sotto*, che è un dato
 * caricato dall'utente e quindi ignoto. Su una foto chiara «Pronto ora» misura
 * **3,09:1** e su una scura **3,96:1**, mentre WCAG 2.1 AA chiede **4,5:1** per
 * un testo che — a 10px in grassetto — non è «testo grande» sotto nessuna
 * definizione. È il problema di leggibilità già osservato su quel badge.
 *
 * Il badge «Aperta» è quindi **opaco**: il suo contrasto non dipende dalla foto,
 * ed è lo stesso identico numero su sfondo chiaro e su sfondo scuro. Non è una
 * preferenza estetica — è la sola forma in cui la promessa si può mantenere
 * senza sapere che foto ci sarà sotto.
 *
 * `phaseColor` **non** viene toccato: la sessione di coordinamento ha chiesto di
 * costruire il badge nuovo, non di rifare i badge esistenti.
 */

// Gli stati vivono accanto a `CellarBottle`, che è il tipo di cui sono un
// campo: sono un fatto del dominio Cantina, non di questo badge. Una seconda
// copia qui potrebbe divergere da quella senza che nulla protesti.
import type { StatoBottiglia } from "@/data/cellar";

/** Il testo del badge. Una parola, perché lo spazio sopra una foto è quello. */
export const TESTO_BADGE_APERTA = "Aperta";

/**
 * I colori del badge, nelle due forme in cui servono.
 *
 * `classi` è ciò che il componente scrive; `sfondo` e `testo` sono gli stessi
 * due colori in esadecimale, che è la forma su cui si calcola un contrasto.
 * Le due copie devono coincidere, e un test le confronta con i token di
 * `globals.css`: se qualcuno ridefinisce `--antracite` o `--crema`, il numero
 * qui sotto smette di essere vero e il test protesta invece di lasciare passare
 * un badge illeggibile.
 *
 * Antracite su crema e non bordeaux: `bg-bordeaux` è già il badge «In vendita»,
 * e due pastiglie dello stesso colore sulla stessa foto direbbero due cose
 * diverse con la stessa voce.
 */
export const COLORE_BADGE_APERTA = {
  classi: "bg-antracite text-crema",
  sfondo: "#202020",
  testo: "#f7f3ec",
} as const;

export type BadgeStatoBottiglia = {
  testo: string;
  classi: string;
};

/**
 * Il badge da disegnare per una bottiglia, o `null` se non ce n'è uno.
 *
 * Solo `aperta` ha un badge. `consumata` **di proposito no**: la sessione di
 * coordinamento del 19 agosto 2026 ha posto la condizione esplicita di non
 * costruire un indicatore per quello stato, che nel repository non ne ha mai
 * avuto uno. `chiusa` è lo stato normale e un badge su ogni scheda non
 * distinguerebbe niente.
 *
 * `undefined` vale come «non lo so», e non come «chiusa»: è ciò che arriva dai
 * dati dimostrativi di `bottiglieSeed`, dove `quantita` è un conteggio e lo
 * stato non esiste affatto. Disegnare un badge su un'ignoranza sarebbe
 * inventare.
 */
export function badgeStatoBottiglia(
  stato: StatoBottiglia | undefined | null,
): BadgeStatoBottiglia | null {
  if (stato !== "aperta") return null;
  return { testo: TESTO_BADGE_APERTA, classi: COLORE_BADGE_APERTA.classi };
}

// ============================================================
// Contrasto — WCAG 2.1, §1.4.3
// ============================================================

/** La soglia AA per il testo normale. 10px in grassetto non è «testo grande». */
export const SOGLIA_CONTRASTO_AA = 4.5;

function canali(hex: string): [number, number, number] {
  const pulito = hex.replace("#", "").trim();
  if (!/^[0-9a-fA-F]{6}$/.test(pulito)) {
    throw new Error(`Colore non riconosciuto: ${hex}`);
  }
  return [
    parseInt(pulito.slice(0, 2), 16),
    parseInt(pulito.slice(2, 4), 16),
    parseInt(pulito.slice(4, 6), 16),
  ];
}

function versoLineare(valore: number): number {
  const c = valore / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

/** Luminanza relativa di un colore opaco, formula WCAG 2.1. */
export function luminanzaRelativa(hex: string): number {
  const [r, g, b] = canali(hex).map(versoLineare) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** Rapporto di contrasto fra due colori opachi: da 1:1 a 21:1. */
export function contrastoWcag(primo: string, secondo: string): number {
  const a = luminanzaRelativa(primo);
  const b = luminanzaRelativa(secondo);
  const chiaro = Math.max(a, b);
  const scuro = Math.min(a, b);
  return (chiaro + 0.05) / (scuro + 0.05);
}

/**
 * Il colore che si vede davvero quando `colore` è disegnato con `alpha` sopra
 * `sfondo`.
 *
 * Serve a misurare i badge traslucidi: `bg-salvia/25` non è salvia, è salvia al
 * 25% mescolata con ciò che ha sotto. Senza questa composizione un badge
 * traslucido sembrerebbe avere il contrasto del suo colore pieno, che è
 * esattamente l'errore che rende «Pronto ora» illeggibile su una foto chiara.
 */
export function componiAlpha(colore: string, alpha: number, sfondo: string): string {
  const sopra = canali(colore);
  const sotto = canali(sfondo);
  const mescola = (i: number) => Math.round(alpha * sopra[i] + (1 - alpha) * sotto[i]);
  return `#${[0, 1, 2].map((i) => mescola(i).toString(16).padStart(2, "0")).join("")}`;
}

/**
 * Le due foto estreme che possono finire sotto un badge: bianco pieno e nero
 * pieno. Nessuna foto reale è più chiara della prima né più scura del secondo,
 * quindi un badge che regge su entrambe regge su qualunque foto.
 */
export const SFONDO_CHIARO = "#ffffff";
export const SFONDO_SCURO = "#000000";
