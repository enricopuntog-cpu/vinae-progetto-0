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
 * I badge della finestra di bevuta usavano sfondi **traslucidi**: `phaseColor`
 * dava a «Pronto ora» le classi `bg-salvia/25 text-salvia`
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
 * ## E poi «Pronto ora» è stato corretto con lo stesso rimedio
 *
 * Quando il badge «Aperta» è nato, `phaseColor` non fu toccato: la sessione
 * aveva chiesto il badge nuovo, non il rifacimento di quelli esistenti. La
 * sessione del **19 agosto 2026** ha chiesto anche quello, per «Pronto ora» e
 * **solo** per quello — «Momento ideale» misura 9,99:1 ed è già leggibile.
 * `COLORE_BADGE_PRONTO` è il risultato, e `COLORE_BADGE_PRONTO_PRIMA` tiene in
 * vita la misura del difetto perché nessuno possa tornarci sopra per
 * distrazione.
 *
 * ## E il 24 agosto 2026 anche «Quasi pronto»
 *
 * Quella sessione lasciò `quasi` fuori perimetro, ma ne scrisse il numero
 * proprio perché non restasse un'omissione silenziosa: **1,10:1** su foto scura,
 * peggiore dei 3,96:1 che avevano motivato la correzione di «Pronto ora». Quel
 * numero è stato la ragione per riaprirlo, ed è ciò che `COLORE_BADGE_QUASI` e
 * `COLORE_BADGE_QUASI_PRIMA` tengono ora misurabile.
 *
 * `oltre` (`bg-destructive/20 text-destructive`) resta traslucido: è fuori dal
 * perimetro chiesto qui. Non è approvazione — è un debito con un nome.
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

/**
 * I colori di «Pronto ora», nella stessa forma e per la stessa ragione.
 *
 * Questa pastiglia è il difetto che il badge «Aperta» era stato costruito per
 * non ripetere, e ora è corretta con lo stesso rimedio: fondo **opaco**, quindi
 * un contrasto che non dipende dalla foto sottostante.
 *
 * `--salvia-scuro` è un token **nuovo**, e la ragione è una misura: nessuna
 * coppia fra i token già esistenti reggeva la soglia. `--salvia` (`#74806c`) è
 * un mezzotono a L46%, e contro `crema` dà 3,76:1, contro `antracite` 3,92:1 —
 * sotto 4,5:1 in tutte e due le direzioni. «Rendilo opaco» non era quindi un
 * cambio di una classe: senza un colore nuovo il badge restava illeggibile con
 * l'aria di essere stato corretto, che è peggio di lasciarlo com'era.
 *
 * `#4a5344` conserva la tinta di salvia (H96, identica) e la porta a L30%, cioè
 * al peso di `--bordeaux` (L27%), che è il fondo della pastiglia accanto. Su
 * `--crema` misura 7,27:1: passa AA e anche AAA.
 */
export const COLORE_BADGE_PRONTO = {
  classi: "bg-salvia-scuro text-crema",
  sfondo: "#4a5344",
  testo: "#f7f3ec",
} as const;

/**
 * Il valore che `phaseColor.pronto` aveva prima della correzione, tenuto qui
 * perché i casi che ne misurano il difetto restino eseguibili.
 *
 * Non è nostalgia: quei numeri — 3,09:1 e 3,96:1 — sono la ragione per cui
 * `--salvia-scuro` esiste, e un test che li ricalcola ogni volta è ciò che
 * impedisce di tornare a un fondo traslucido «tanto si legge».
 */
export const COLORE_BADGE_PRONTO_PRIMA = {
  classi: "bg-salvia/25 text-salvia",
  base: "#74806c",
  alpha: 0.25,
} as const;

/**
 * I colori di «Quasi pronto», nella stessa forma e per la stessa ragione.
 *
 * È l'ultima pastiglia della finestra di bevuta che stesse **peggio** di quella
 * corretta il 19 agosto: `bg-oro/25 text-antracite` è oro traslucido con testo
 * scuro, e su una foto scura il fondo diventa quasi nero mentre il testo lo è
 * già — 1,10:1, cioè praticamente invisibile. Su una foto chiara misurava
 * 13,12:1, il che è il punto: il contrasto non era una proprietà del badge, era
 * una proprietà della fotografia.
 *
 * `--oro-scuro` è un token **nuovo**, per una ragione misurata e non estetica.
 * `--oro` pieno (`#b59a63`) con `antracite` dà 6,03:1 e passerebbe — ma è
 * *identico* a `phaseColor.presto`, e `quasi` («troppo giovane, aspetta») e
 * `presto` («bevila entro pochi anni») sono le due estremità opposte della
 * stessa scala. Oggi si distinguono solo per la trasparenza, che è l'unica cosa
 * che questa correzione deve togliere: renderlo opaco riusando `--oro` avrebbe
 * chiuso il difetto di contrasto cancellando l'informazione.
 *
 * `#5e4d2c` conserva tinta e saturazione di `--oro` (H40, S36%, identiche) e le
 * porta a L27%, cioè al peso di `--bordeaux`. Su `--crema` misura 7,38:1: passa
 * AA e anche AAA, come `--salvia-scuro` accanto.
 */
export const COLORE_BADGE_QUASI = {
  classi: "bg-oro-scuro text-crema",
  sfondo: "#5e4d2c",
  testo: "#f7f3ec",
} as const;

/**
 * Il valore che `phaseColor.quasi` aveva prima della correzione, tenuto qui per
 * la stessa ragione del gemello di «Pronto ora»: 1,10:1 è la misura che ha
 * riaperto il caso, e un test che la ricalcola è ciò che impedisce di rimettere
 * un fondo traslucido «tanto sulle mie foto si legge».
 *
 * `testo` è esplicito e non implicito: questa pastiglia falliva con testo
 * **scuro** su fondo che si scurisce, che è una forma diversa dal difetto di
 * `pronto`, dove testo e fondo erano lo stesso colore.
 */
export const COLORE_BADGE_QUASI_PRIMA = {
  classi: "bg-oro/25 text-antracite",
  base: "#b59a63",
  alpha: 0.25,
  testo: "#202020",
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
