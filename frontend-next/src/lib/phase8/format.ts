import { routes } from "@/config/routes";
import type { NotificationDestination } from "@/services/types";

export const formatPhase8Time = (value: string): string =>
  new Intl.DateTimeFormat("it-IT", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));

export const destinationHref = (destination: NotificationDestination): string | null => {
  if (destination.kind === "conversation") {
    return `/messaggi?conversation=${encodeURIComponent(destination.conversationId)}`;
  }
  if (destination.kind === "listing") {
    return `/annuncio/${encodeURIComponent(destination.listingId)}`;
  }
  if (destination.kind === "order") return `/ordine/${destination.orderId}`;
  if (destination.kind === "club") return `/community/${destination.clubSlug}`;
  // Il percorso non si scrive a mano: lo compone il registro delle rotte, cosi
  // la Cantina pubblica ha un solo indirizzo in tutta l'applicazione.
  if (destination.kind === "cellar") {
    return routes.cantinaPubblica(encodeURIComponent(destination.profileId));
  }
  return null;
};
