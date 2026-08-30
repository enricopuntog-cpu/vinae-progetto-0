import Link from "next/link";
import { ArrowLeft, MoreHorizontal } from "lucide-react";
import { formatEUR } from "@/lib/format";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { SafeImage } from "@/components/vinea/States";
import type { ConversationSummary } from "@/services/types";

/**
 * L'intestazione della conversazione è il punto in cui i Messaggi presentano
 * una persona, quindi è qui che sta l'ingresso al suo profilo pubblico.
 *
 * `counterpart.userId` c'era già: la vista delle conversazioni lo porta perché
 * serve a sapere con chi si sta parlando, e finora la UI lo scartava. Non
 * serviva nessuna lettura in più.
 *
 * L'avatar passa ora da `AvatarPersona`. `counterpart.avatarUrl` arriva da
 * `profiles.avatar_url`, che è una colonna scrivibile dal client: disegnarla
 * dritta in un `<img>` significava lasciare che una stringa altrui decidesse
 * una richiesta di rete. La foundation la accetta solo se è un preset del
 * catalogo o una foto nella cartella di questa stessa persona — ed è per
 * questo che `proprietarioId` è `counterpart.userId` e non altro.
 */
export const ConversationHeader = ({
  conversation,
  onBack,
}: {
  conversation: ConversationSummary;
  onBack: () => void;
}) => {
  const profiloControparte = `/profilo/${conversation.counterpart.userId}`;

  return (
    <>
      <header className="flex items-center gap-3 border-b border-border p-3">
        <button
          onClick={onBack}
          className="rounded-full p-1 hover:bg-secondary md:hidden"
          aria-label="Indietro"
        >
          <ArrowLeft className="h-4 w-4" />
        </button>
        <Link
          href={profiloControparte}
          aria-label={`Profilo di ${conversation.counterpart.username}`}
          className="shrink-0 rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          data-testid="conversazione-controparte-avatar"
        >
          <AvatarPersona
            avatarUrl={conversation.counterpart.avatarUrl}
            proprietarioId={conversation.counterpart.userId}
            className="h-10 w-10"
          />
        </Link>
        <span className="min-w-0 flex-1">
          {/* Due link affiancati e non annidati: la persona e l'annuncio sono due
              destinazioni diverse, e l'annuncio collegato deve continuare a
              portare all'annuncio. */}
          <Link
            href={profiloControparte}
            className="block font-semibold hover:underline"
            data-testid="conversazione-controparte-username"
          >
            {conversation.counterpart.username}
          </Link>
          <Link
            href={`/annuncio/${conversation.listingSlug}`}
            className="block truncate text-xs text-muted-foreground hover:underline"
          >
            {conversation.wineName} · {formatEUR(conversation.listingPriceCents / 100)}
          </Link>
        </span>
        <button
          disabled
          title="Segnalazione e blocco arrivano con la Fase 9"
          className="rounded-full p-2 opacity-40"
          aria-label="Altre azioni non disponibili"
        >
          <MoreHorizontal className="h-4 w-4" />
        </button>
      </header>
      <Link
        href={`/annuncio/${conversation.listingSlug}`}
        className="flex items-center gap-3 border-b border-border bg-crema/60 p-3 hover:bg-crema"
      >
        {/* `conversations_page` proietta `coalesce(l.immagini[1], '')`: un annuncio
            senza foto arriva qui come stringa vuota, e `src=""` fa risolvere al
            browser l'URL della pagina stessa — il riquadro rotto. `SafeImage`
            copre in un colpo solo quel caso e l'URL che c'è ma non carica,
            usando lo stesso segnaposto già in uso sulle schede annuncio. Nessuna
            lettura in più: il valore è quello che la conversazione porta già. */}
        <SafeImage
          src={conversation.wineImage}
          alt=""
          fallbackLabel="Foto non disponibile"
          compact
          className="h-12 w-9 shrink-0 rounded object-cover"
          data-testid="conversazione-annuncio-immagine"
        />
        <span className="min-w-0 flex-1">
          <span className="block text-[11px] uppercase tracking-wide text-salvia">
            Annuncio collegato
          </span>
          <span className="block truncate font-serif font-semibold">{conversation.wineName}</span>
        </span>
      </Link>
    </>
  );
};
