/**
 * Requisiti formali della password Vinea: un solo validatore per registrazione,
 * reimpostazione e password facoltativa del primo accesso Google.
 *
 * LA POLICY È QUELLA DI SUPABASE PRODUCTION, NON UNA SCELTA DI QUESTA PAGINA.
 * Dashboard del progetto `pijnmcllmfgjmgsvtcej`, Authentication → Sign In /
 * Providers → Email, verificato dal titolare il 19 ottobre 2026: lunghezza
 * minima 6, almeno una minuscola, una maiuscola, un numero e un simbolo,
 * protezione contro le password compromesse attiva. Cambiare la lunghezza
 * minima (per esempio a 8) è una decisione del titolare da fare prima nel
 * dashboard e poi qui, mai il contrario.
 *
 * GLI INSIEMI DI CARATTERI SONO QUELLI DI GOTRUE, CARATTERE PER CARATTERE.
 * L'opzione «lowercase, uppercase letters, digits and symbols» corrisponde in
 * Supabase Auth a quattro classi ASCII (supabase/cli,
 * `password-requirements.ts`; supabase/auth, `checkPasswordStrength` con
 * `strings.ContainsAny`): `a-z`, `A-Z`, `0-9` e i 32 segni di punteggiatura
 * ASCII. Una «à», una «É» o un «€» non soddisfano nessuna delle quattro, e lo
 * spazio non è un simbolo. Se questo modulo fosse più generoso del server,
 * l'utente vedrebbe cinque spunte verdi e poi un rifiuto: per questo qui non
 * si usa `\p{Ll}` né «qualunque carattere non alfanumerico».
 *
 * IL FRONTEND NON È L'AUTORITÀ. Questi controlli servono a dire in anticipo
 * all'utente che cosa manca; il rifiuto vero lo decide Supabase Auth, che resta
 * l'unico a sapere se una password compare negli archivi di violazioni (HIBP).
 * Quel caso non ha una spunta, perché nessuna pagina può saperlo prima di
 * chiedere: arriva come errore dal server (`password-compromessa`).
 */

/** Lunghezza minima configurata in Supabase Production. */
export const LUNGHEZZA_MINIMA_PASSWORD = 6;

/**
 * Limite di GoTrue (`MaxPasswordLength`, imposto da bcrypt), misurato in byte
 * UTF-8 come fa `len()` in Go: oltre, la richiesta viene respinta prima di ogni
 * altro controllo.
 */
export const LUNGHEZZA_MASSIMA_PASSWORD_BYTE = 72;

const MINUSCOLE = "abcdefghijklmnopqrstuvwxyz";
const MAIUSCOLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const CIFRE = "0123456789";
/** I 32 segni di punteggiatura ASCII, nell'ordine di GoTrue. */
export const SIMBOLI_PASSWORD = "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~";

const contieneUnoDi = (password: string, insieme: string): boolean => {
  for (const carattere of password) if (insieme.includes(carattere)) return true;
  return false;
};

/**
 * Lunghezza in caratteri visibili (code point), non in unità UTF-16: un'emoji
 * conta uno. Ogni code point vale almeno un byte, quindi una password che qui
 * raggiunge 6 caratteri li raggiunge anche per GoTrue, che conta in byte.
 */
const caratteri = (password: string): number => [...password].length;

const byteUtf8 = (password: string): number => new TextEncoder().encode(password).length;

export type IdRequisitoPassword = "lunghezza" | "minuscola" | "maiuscola" | "numero" | "simbolo";

export type RequisitoPassword = {
  readonly id: IdRequisitoPassword;
  readonly etichetta: string;
  readonly soddisfatto: (password: string) => boolean;
};

/** I cinque requisiti, nell'ordine in cui la pagina li mostra. */
export const REQUISITI_PASSWORD: readonly RequisitoPassword[] = [
  {
    id: "lunghezza",
    etichetta: `Almeno ${LUNGHEZZA_MINIMA_PASSWORD} caratteri`,
    soddisfatto: (password) => caratteri(password) >= LUNGHEZZA_MINIMA_PASSWORD,
  },
  {
    id: "minuscola",
    etichetta: "Una lettera minuscola (a-z)",
    soddisfatto: (password) => contieneUnoDi(password, MINUSCOLE),
  },
  {
    id: "maiuscola",
    etichetta: "Una lettera maiuscola (A-Z)",
    soddisfatto: (password) => contieneUnoDi(password, MAIUSCOLE),
  },
  {
    id: "numero",
    etichetta: "Un numero (0-9)",
    soddisfatto: (password) => contieneUnoDi(password, CIFRE),
  },
  {
    id: "simbolo",
    etichetta: "Un simbolo, per esempio ! ? @ # . - _",
    soddisfatto: (password) => contieneUnoDi(password, SIMBOLI_PASSWORD),
  },
];

export type ValutazionePassword = {
  readonly requisiti: readonly { readonly id: IdRequisitoPassword; readonly etichetta: string; readonly soddisfatto: boolean }[];
  /** Quanti dei cinque requisiti sono soddisfatti. */
  readonly soddisfatti: number;
  /** Oltre il limite di GoTrue: nessun requisito la rende accettabile. */
  readonly troppoLunga: boolean;
  /** Tutti i requisiti formali soddisfatti e lunghezza entro il limite. */
  readonly valida: boolean;
};

/**
 * Valuta una password così com'è stata digitata o incollata. Nessun `trim`: uno
 * spazio è un carattere della password, e toglierlo vorrebbe dire salvare una
 * password diversa da quella che il password manager ha memorizzato.
 */
export const valutaPassword = (password: string): ValutazionePassword => {
  const requisiti = REQUISITI_PASSWORD.map((r) => ({
    id: r.id,
    etichetta: r.etichetta,
    soddisfatto: r.soddisfatto(password),
  }));
  const soddisfatti = requisiti.filter((r) => r.soddisfatto).length;
  const troppoLunga = byteUtf8(password) > LUNGHEZZA_MASSIMA_PASSWORD_BYTE;
  return {
    requisiti,
    soddisfatti,
    troppoLunga,
    valida: soddisfatti === REQUISITI_PASSWORD.length && !troppoLunga,
  };
};

export const passwordValida = (password: string): boolean => valutaPassword(password).valida;

export const MESSAGGIO_PASSWORD_TROPPO_LUNGA = `La password è troppo lunga: usa al massimo ${LUNGHEZZA_MASSIMA_PASSWORD_BYTE} caratteri, meno se contiene lettere accentate o emoji.`;

export const MESSAGGIO_REQUISITI_MANCANTI = "La password non soddisfa ancora tutti i requisiti indicati.";

/**
 * Regole per i generatori di password dei browser (Safari / Portachiavi
 * iCloud). È un suggerimento: chi lo ignora resta comunque guidato dalla lista
 * dei requisiti. I simboli elencati sono un sottoinsieme di `SIMBOLI_PASSWORD`,
 * così una password generata non può contenere un simbolo che GoTrue non conta.
 */
export const REGOLE_GENERATORE_PASSWORD = `minlength: ${LUNGHEZZA_MINIMA_PASSWORD}; required: lower; required: upper; required: digit; required: [-!#$%&*+.=?@_];`;
