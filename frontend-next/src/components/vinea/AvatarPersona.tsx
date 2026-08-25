"use client";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { risolviAvatarPersona } from "@/lib/profilo/avatar";
import { cn } from "@/lib/utils";

/**
 * La persona generica di Vinea: testa e spalle dentro il cerchio dell'avatar.
 *
 * È un SVG inline e non un file in `public/`, perché è il fondo della catena:
 * se anche il fallback fosse una richiesta di rete, il caso "immagine che non
 * arriva" non avrebbe fine. Sta qui come export a sé, e non dentro
 * `AvatarPersona`, perché serve anche dove l'avatar non è un avatar — un posto
 * vuoto in una lista, il segnaposto di un mittente sconosciuto.
 */
export const SilhouettePersona = ({ className }: { className?: string }) => (
  <svg
    viewBox="0 0 40 40"
    aria-hidden
    focusable="false"
    className={cn("h-full w-full text-bordeaux/55", className)}
    data-testid="avatar-silhouette"
  >
    <circle cx="20" cy="15.5" r="6.5" fill="currentColor" />
    <path d="M6.5 36.5a13.5 13.5 0 0 1 27 0z" fill="currentColor" />
  </svg>
);

type AvatarPersonaProps = {
  avatarUrl: string | null | undefined;
  proprietarioId?: string | null;
  /**
   * Vuoto per default: nell'header l'immagine sta dentro un link che porta già
   * la sua etichetta, e ripetere il nome darebbe due volte la stessa cosa a chi
   * legge con uno screen reader. Va valorizzato solo quando l'avatar è l'unico
   * contenuto che identifica qualcuno.
   */
  alt?: string;
  className?: string;
};

/**
 * Avatar di una persona con la priorità foto → preset → silhouette.
 *
 * La decisione sta tutta in `risolviAvatarPersona()`: qui si disegna soltanto.
 * `AvatarFallback` di Radix copre anche il caso che il resolver non può
 * prevedere — un URL legittimo che però non carica — e in quel caso ricade
 * sulla stessa silhouette invece di lasciare il buco.
 */
export const AvatarPersona = ({
  avatarUrl,
  proprietarioId,
  alt = "",
  className,
}: AvatarPersonaProps) => {
  const avatar = risolviAvatarPersona(avatarUrl, proprietarioId);
  return (
    <Avatar
      className={cn("h-8 w-8 border border-border bg-secondary", className)}
      data-testid="avatar-persona"
      data-fonte-avatar={avatar.fonte}
    >
      {avatar.url ? <AvatarImage src={avatar.url} alt={alt} /> : null}
      <AvatarFallback className="bg-secondary">
        <SilhouettePersona />
      </AvatarFallback>
    </Avatar>
  );
};
