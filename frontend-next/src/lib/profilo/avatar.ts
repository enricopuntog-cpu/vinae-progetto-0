/**
 * Catalogo degli avatar disponibili sul profilo.
 *
 * PERCHÉ UN INSIEME CURATO E NON UN CARICAMENTO. La demo storica
 * (`frontend/src/routes/onboarding.tsx`) pescava da `pravatar.cc`, cioè da un
 * servizio esterno: inaccettabile per un dato di produzione, perché ogni
 * visualizzazione di un profilo diventerebbe una richiesta a terzi con l'IP di
 * chi guarda. Qui i file sono **nostri**, serviti da `public/avatar/`.
 *
 * Il caricamento di una foto propria non è escluso per sempre: è escluso da
 * questo giro, e non per pigrizia. Un bucket nuovo porta con sé le stesse
 * domande che la Fase 11 dovette chiudere in sessione per `foto-ai` — pubblico
 * o privato, limite di dimensione, elenco MIME, pulizia degli orfani, e lo
 * spoglio EXIF, visto che una foto scattata in casa porta le coordinate GPS del
 * luogo dello scatto. Deciderle qui, fuori da una sessione, sarebbe inventare
 * una decisione; e la migrazione che crea il bucket si applicherebbe da sé al
 * progetto reale al momento del merge (7.10).
 *
 * SICUREZZA. `profiles.avatar_url` è scrivibile dal client — è fra le otto
 * colonne del `GRANT UPDATE` della 9b — quindi il valore che torna dal database
 * non è fidato: un utente può scriverci qualunque stringa, compreso un URL
 * esterno che trasformerebbe la propria scheda in un tracciatore per chi la
 * apre. Per questo la lettura passa sempre da `avatarSicuro()`, che accetta
 * **solo** un percorso del catalogo e altrimenti ricade sulle iniziali. La
 * convalida sta in lettura e non solo in scrittura perché è in lettura che il
 * valore viene reso a un terzo.
 */

export type AvatarId = "calice" | "bottiglia" | "grappolo" | "botte" | "tappo" | "decanter";

export type VoceAvatar = { id: AvatarId; percorso: string; etichetta: string };

export const CATALOGO_AVATAR: readonly VoceAvatar[] = [
  { id: "calice", percorso: "/avatar/calice.svg", etichetta: "Calice" },
  { id: "bottiglia", percorso: "/avatar/bottiglia.svg", etichetta: "Bottiglia" },
  { id: "grappolo", percorso: "/avatar/grappolo.svg", etichetta: "Grappolo" },
  { id: "botte", percorso: "/avatar/botte.svg", etichetta: "Botte" },
  { id: "tappo", percorso: "/avatar/tappo.svg", etichetta: "Tappo" },
  { id: "decanter", percorso: "/avatar/decanter.svg", etichetta: "Decanter" },
] as const;

const PERCORSI_AMMESSI = new Set(CATALOGO_AVATAR.map((voce) => voce.percorso));

/**
 * Il percorso da disegnare, oppure `null` se il valore memorizzato non
 * appartiene al catalogo — compreso il caso normale della stringa vuota, che è
 * il default della colonna per chi non ha mai scelto.
 */
export function avatarSicuro(valore: string | null | undefined): string | null {
  if (!valore) return null;
  return PERCORSI_AMMESSI.has(valore) ? valore : null;
}

/**
 * Iniziali da mostrare quando non c'è un avatar valido. Una lettera sola se il
 * nome non ne offre due: meglio di un riquadro vuoto, e non inventa caratteri.
 */
export function inizialiDa(nome: string | null | undefined): string {
  const parole = (nome ?? "")
    .split(/[\s._-]+/)
    .map((parte) => parte.trim())
    .filter(Boolean);
  if (parole.length === 0) return "?";
  if (parole.length === 1) return parole[0]!.slice(0, 2).toUpperCase();
  return `${parole[0]![0]}${parole[1]![0]}`.toUpperCase();
}
