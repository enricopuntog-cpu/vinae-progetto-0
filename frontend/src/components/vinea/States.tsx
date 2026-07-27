import { Link } from "@tanstack/react-router";
import {
  AlertTriangle,
  WifiOff,
  Inbox,
  Lock,
  Search,
  ImageOff,
  CheckCircle2,
  Sparkles,
  RefreshCw,
  Loader2,
  Compass,
  PencilLine,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useEffect, useState, type ReactNode, type ImgHTMLAttributes } from "react";

/* ------------------------------------------------------------------ */
/*  Card scaffolding                                                   */
/* ------------------------------------------------------------------ */
function StateCard({
  icon: Icon,
  title,
  message,
  actions,
  tone = "neutral",
  role = "status",
  live = "polite",
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  message?: ReactNode;
  actions?: ReactNode;
  tone?: "neutral" | "warn" | "danger" | "success" | "info";
  role?: "status" | "alert";
  live?: "polite" | "assertive" | "off";
}) {
  const tones = {
    neutral: "bg-secondary/60 text-antracite border-border",
    warn: "bg-oro/10 text-antracite border-oro/40",
    danger: "bg-bordeaux/5 text-bordeaux border-bordeaux/30",
    success: "bg-salvia/10 text-salvia border-salvia/40",
    info: "bg-crema text-antracite border-border",
  } as const;
  return (
    <div
      role={role}
      aria-live={live}
      className={`mx-auto flex w-full max-w-md flex-col items-center rounded-2xl border p-6 text-center ${tones[tone]}`}
    >
      <div className="mb-3 grid h-12 w-12 place-items-center rounded-full bg-background/70">
        <Icon className="h-5 w-5" />
      </div>
      <p className="font-serif text-lg font-semibold">{title}</p>
      {message && <div className="mt-1 text-sm text-muted-foreground">{message}</div>}
      {actions && <div className="mt-4 flex flex-wrap justify-center gap-2">{actions}</div>}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Empty                                                              */
/* ------------------------------------------------------------------ */
export function EmptyState({
  title = "Ancora nulla qui",
  message = "Non c'è ancora contenuto da mostrare.",
  action,
  icon = Inbox,
}: {
  title?: string;
  message?: ReactNode;
  action?: ReactNode;
  icon?: React.ComponentType<{ className?: string }>;
}) {
  return <StateCard icon={icon} title={title} message={message} actions={action} tone="neutral" />;
}

/* ------------------------------------------------------------------ */
/*  Error (recoverable, human copy)                                     */
/* ------------------------------------------------------------------ */
export function ErrorState({
  title = "Non riusciamo a mostrare questa sezione",
  message = "Puoi riprovare tra un istante. Se il problema persiste, torna alla home.",
  onRetry,
  home = true,
}: {
  title?: string;
  message?: ReactNode;
  onRetry?: () => void;
  home?: boolean;
}) {
  return (
    <StateCard
      icon={AlertTriangle}
      title={title}
      message={message}
      tone="danger"
      role="alert"
      actions={
        <>
          {onRetry && (
            <Button size="sm" className="bg-bordeaux hover:bg-bordeaux/90" onClick={onRetry}>
              <RefreshCw className="h-4 w-4" /> Riprova
            </Button>
          )}
          {home && (
            <Button asChild size="sm" variant="outline">
              <Link to="/">Torna alla home</Link>
            </Button>
          )}
        </>
      }
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Offline                                                            */
/* ------------------------------------------------------------------ */
export function OfflineState({ onRetry }: { onRetry?: () => void }) {
  return (
    <StateCard
      icon={WifiOff}
      title="Sembra che tu sia offline"
      message="Controlla la connessione e riprova. Alcune sezioni potrebbero non essere disponibili."
      tone="warn"
      role="status"
      actions={
        onRetry && (
          <Button size="sm" variant="outline" onClick={onRetry}>
            <RefreshCw className="h-4 w-4" /> Riprova
          </Button>
        )
      }
    />
  );
}

/** Hook: reagisce a online/offline. */
export function useOnline() {
  const [online, setOnline] = useState(true);
  useEffect(() => {
    if (typeof window === "undefined") return;
    setOnline(navigator.onLine);
    const on = () => setOnline(true);
    const off = () => setOnline(false);
    window.addEventListener("online", on);
    window.addEventListener("offline", off);
    return () => {
      window.removeEventListener("online", on);
      window.removeEventListener("offline", off);
    };
  }, []);
  return online;
}

/* ------------------------------------------------------------------ */
/*  Nessun risultato                                                   */
/* ------------------------------------------------------------------ */
export function NoResultsState({
  query,
  onReset,
  suggestions,
}: {
  query?: string;
  onReset?: () => void;
  suggestions?: ReactNode;
}) {
  return (
    <StateCard
      icon={Search}
      title="Nessun risultato"
      message={
        <>
          {query ? (
            <>
              Non abbiamo trovato nulla per <b>“{query}”</b>.
            </>
          ) : (
            <>Prova a modificare i filtri o allargare la ricerca.</>
          )}
          {suggestions && <div className="mt-2">{suggestions}</div>}
        </>
      }
      actions={
        onReset && (
          <Button size="sm" variant="outline" onClick={onReset}>
            Reimposta filtri
          </Button>
        )
      }
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Permesso negato                                                    */
/* ------------------------------------------------------------------ */
export function PermissionDeniedState({
  title = "Accesso non consentito",
  message = "Non hai i permessi necessari per vedere questa sezione.",
  action,
}: {
  title?: string;
  message?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <StateCard
      icon={Lock}
      title={title}
      message={message}
      tone="warn"
      actions={
        action ?? (
          <Button asChild size="sm" variant="outline">
            <Link to="/">Torna alla home</Link>
          </Button>
        )
      }
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Not found (route-level)                                            */
/* ------------------------------------------------------------------ */
export function NotFoundState({
  title = "Pagina non trovata",
  message = "La pagina che cercavi non esiste o è stata spostata.",
}: {
  title?: string;
  message?: ReactNode;
}) {
  return (
    <div className="mx-auto flex min-h-[50vh] max-w-lg flex-col items-center justify-center px-4 text-center">
      <p className="font-serif text-6xl text-bordeaux">404</p>
      <h1 className="mt-2 font-serif text-2xl font-semibold">{title}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{message}</p>
      <div className="mt-4 flex flex-wrap justify-center gap-2">
        <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
          <Link to="/">Torna alla home</Link>
        </Button>
        <Button asChild variant="outline">
          <Link to="/esplora">
            <Compass className="h-4 w-4" /> Esplora la ricerca
          </Link>
        </Button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Conferma completata                                                */
/* ------------------------------------------------------------------ */
export function SuccessConfirmation({
  title = "Fatto",
  message,
  action,
}: {
  title?: string;
  message?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <StateCard
      icon={CheckCircle2}
      title={title}
      message={message}
      tone="success"
      role="status"
      actions={action}
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Skeletons                                                          */
/* ------------------------------------------------------------------ */
export function CardSkeleton() {
  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <Skeleton className="aspect-[4/5] w-full rounded-none" />
      <div className="space-y-2 p-4">
        <Skeleton className="h-3 w-1/3" />
        <Skeleton className="h-5 w-3/4" />
        <Skeleton className="h-3 w-1/2" />
        <Skeleton className="h-6 w-1/3" />
      </div>
    </div>
  );
}
export function CardGridSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div
      aria-busy="true"
      aria-live="polite"
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
    >
      {Array.from({ length: count }).map((_, i) => (
        <CardSkeleton key={i} />
      ))}
    </div>
  );
}
export function LineSkeleton({ lines = 3 }: { lines?: number }) {
  return (
    <div aria-busy="true" aria-live="polite" className="space-y-2">
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton key={i} className={`h-3 ${i === lines - 1 ? "w-1/2" : "w-full"}`} />
      ))}
    </div>
  );
}
export function LoadingBlock({ label = "Caricamento in corso" }: { label?: string }) {
  return (
    <div
      role="status"
      aria-live="polite"
      className="flex items-center justify-center gap-2 rounded-2xl border border-border bg-secondary/40 p-8 text-sm text-muted-foreground"
    >
      <Loader2 className="h-4 w-4 animate-spin" /> {label}…
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Immagine con fallback                                              */
/* ------------------------------------------------------------------ */
type SafeImgProps = ImgHTMLAttributes<HTMLImageElement> & {
  fallbackLabel?: string;
  ratio?: string; // tailwind aspect utility, e.g. "aspect-square"
};
export function SafeImage({
  src,
  alt,
  fallbackLabel = "Immagine non disponibile",
  ratio,
  className,
  ...rest
}: SafeImgProps) {
  const [errored, setErrored] = useState(false);
  const missing = !src || errored;
  if (missing) {
    return (
      <div
        role="img"
        aria-label={fallbackLabel}
        className={`grid place-items-center bg-secondary text-muted-foreground ${ratio ?? ""} ${className ?? ""}`}
      >
        <div className="flex flex-col items-center gap-1 p-4 text-center text-xs">
          <ImageOff className="h-5 w-5" />
          <span>{fallbackLabel}</span>
        </div>
      </div>
    );
  }
  return (
    <img
      src={src}
      alt={alt ?? ""}
      loading="lazy"
      decoding="async"
      onError={() => setErrored(true)}
      className={`${ratio ?? ""} ${className ?? ""}`}
      {...rest}
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Stati IA (elaborazioni assistite)                                  */
/* ------------------------------------------------------------------ */
export type AiState = "attesa" | "elaborazione" | "completata" | "conferma" | "fallita";

export function AiStatusPanel({
  state,
  titolo = "Analisi assistita",
  descrizione,
  onConferma,
  onRitenta,
  onManuale,
}: {
  state: AiState;
  titolo?: string;
  descrizione?: ReactNode;
  onConferma?: () => void;
  onRitenta?: () => void;
  onManuale?: () => void;
}) {
  const map = {
    attesa: {
      tone: "neutral" as const,
      icon: Sparkles,
      title: `${titolo}: in attesa`,
      msg: descrizione ?? "Avvia l'analisi quando sei pronto. Puoi anche compilare i campi a mano.",
    },
    elaborazione: {
      tone: "info" as const,
      icon: Loader2,
      title: `${titolo}: in elaborazione`,
      msg: descrizione ?? "Stiamo analizzando i dati. Ci vogliono pochi secondi.",
    },
    completata: {
      tone: "success" as const,
      icon: CheckCircle2,
      title: `${titolo}: completata`,
      msg: descrizione ?? "I suggerimenti sono pronti. Puoi accettarli o modificarli.",
    },
    conferma: {
      tone: "warn" as const,
      icon: Sparkles,
      title: `${titolo}: richiede conferma`,
      msg: descrizione ?? "Verifica i suggerimenti prima di procedere.",
    },
    fallita: {
      tone: "danger" as const,
      icon: AlertTriangle,
      title: `${titolo}: non completata`,
      msg:
        descrizione ??
        "Non siamo riusciti a completare l'analisi. Puoi riprovare oppure inserire i dati manualmente.",
    },
  };
  const s = map[state];
  const Icon = s.icon;
  return (
    <StateCard
      icon={Icon}
      title={s.title}
      message={s.msg}
      tone={s.tone}
      role={state === "fallita" ? "alert" : "status"}
      actions={
        <>
          {state === "conferma" && onConferma && (
            <Button size="sm" className="bg-bordeaux hover:bg-bordeaux/90" onClick={onConferma}>
              <CheckCircle2 className="h-4 w-4" /> Conferma suggerimenti
            </Button>
          )}
          {(state === "fallita" || state === "completata") && onRitenta && (
            <Button size="sm" variant="outline" onClick={onRitenta}>
              <RefreshCw className="h-4 w-4" /> Riprova analisi
            </Button>
          )}
          {(state === "fallita" || state === "attesa" || state === "conferma") && onManuale && (
            <Button size="sm" variant="ghost" onClick={onManuale}>
              <PencilLine className="h-4 w-4" /> Inserimento manuale
            </Button>
          )}
        </>
      }
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Copy centralizzata per stati annuncio / ordine (usata dal pannello) */
/* ------------------------------------------------------------------ */
export const listingActionCopy: Record<string, { titolo: string; azioni: string[] }> = {
  bozza: { titolo: "Bozza", azioni: ["Continua a compilare", "Elimina bozza"] },
  in_revisione: { titolo: "In revisione", azioni: ["Attendi esito", "Ritira dalla revisione"] },
  modifiche_richieste: {
    titolo: "Modifiche richieste",
    azioni: ["Applica modifiche", "Contatta il team"],
  },
  attivo: { titolo: "Attivo", azioni: ["Modifica", "Metti in pausa", "Rimuovi"] },
  riservato: { titolo: "Riservato", azioni: ["Vedi trattativa", "Annulla riserva"] },
  venduto: { titolo: "Venduto", azioni: ["Vedi ordine", "Duplica annuncio"] },
  sospeso: { titolo: "Sospeso", azioni: ["Leggi motivazione", "Richiedi ricorso"] },
  rifiutato: { titolo: "Rifiutato", azioni: ["Leggi motivazione", "Crea nuova bozza"] },
  scaduto: { titolo: "Scaduto", azioni: ["Ripubblica", "Archivia"] },
};

export const proposalEdgeCases = [
  {
    id: "scaduta",
    label: "Proposta scaduta",
    desc: "La proposta ha superato i 7 giorni: non è più modificabile.",
  },
  {
    id: "gia_accettata",
    label: "Proposta già accettata",
    desc: "Il venditore ha già accettato: procedi al checkout.",
  },
  {
    id: "doppio_invio",
    label: "Doppio invio impedito",
    desc: "Esiste già una proposta attiva per questa bottiglia.",
  },
  {
    id: "non_disp",
    label: "Bottiglia non più disponibile",
    desc: "L'annuncio è stato ritirato o venduto.",
  },
  {
    id: "pagamento_ko",
    label: "Pagamento simulato fallito",
    desc: "Riprova con un altro metodo demo.",
  },
  {
    id: "etichetta_ko",
    label: "Etichetta non generata",
    desc: "Riprova a generarla o contatta l'assistenza.",
  },
  {
    id: "tracking_ko",
    label: "Tracking non disponibile",
    desc: "Il corriere non ha ancora aggiornato i dati.",
  },
  {
    id: "contest_aperta",
    label: "Contestazione già aperta",
    desc: "Esiste già una pratica in corso per questo ordine.",
  },
  {
    id: "recensione_inviata",
    label: "Recensione già inviata",
    desc: "Puoi consultarla ma non modificarla.",
  },
] as const;
