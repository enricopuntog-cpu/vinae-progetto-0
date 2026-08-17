"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { usePathname } from "next/navigation";
import {
  Home,
  PlusCircle,
  Users,
  User,
  Search,
  Shield,
} from "lucide-react";
import { type ReactNode } from "react";
import { Toaster } from "@/components/ui/sonner";
import { Badge } from "@/components/ui/badge";
import { HeaderInboxActions } from "@/components/vinea/notifications/HeaderInboxActions";
import { AI_UI, DEMO_UI_ABILITATA } from "@/config/features";
import { useVinea, type DemoRuolo } from "@/lib/vinea-store";

// Fase 10c. Il pannello Sommelier era rimasto fuori dalla Fase 3 perché
// dipendeva da `@/services/api-client`, cioè dal backend FastAPI; ora la sua
// controparte è `AiService` sopra le Edge Function, e rientra.
//
// Si carica con `next/dynamic` come la vista 3D della cantina
// (`frontend-next/src/app/cantina/page-client.tsx:5`), che è l'equivalente App
// Router del `lazy` + `Suspense` di `frontend/`
// (`frontend/src/components/vinea/Layout.tsx:19`, `:254-256`): il pannello è in
// fondo a ogni pagina ma lo apre una minoranza dei visitatori, e non ha motivo
// di stare nel bundle iniziale.
//
// `ssr: false` è lecito qui perché questo file è già un componente client, e
// dice la verità sul componente: la conversazione ha un identificativo che vive
// in `localStorage`, che sul server non esiste.
const SommelierChat = dynamic(() => import("@/components/vinea/SommelierChat"), {
  ssr: false,
});

// Fase 12a. La voce Club torna in entrambe le navigazioni, nella posizione che
// aveva prima della #44: quella PR l'aveva tolta perche /community era una
// community finta e diventava un notFound(), non perche la voce fosse di
// troppo. La griglia mobile e rimasta `grid-cols-5` da allora con quattro sole
// voci - questo la riporta a cinque, che e il numero per cui e scritta.
const nav = [
  { to: "/", label: "Home", icon: Home, exact: true },
  { to: "/esplora", label: "Ricerca", icon: Search, exact: false },
  { to: "/vendi", label: "Vendi", icon: PlusCircle, exact: false },
  { to: "/community", label: "Club", icon: Users, exact: false },
  // La voce Account porta al profilo e non piu a /accedi: da autenticati
  // quest'ultima mostrava soltanto "Sei autenticato" ed "Esci", cioe una
  // schermata di accesso a chi era gia dentro. /account rimanda a /accedi da
  // solo quando la sessione manca, quindi la voce resta valida in entrambi gli
  // stati e non serve una voce condizionale.
  { to: "/account", label: "Account", icon: User, exact: false },
] as const;

const desktopLinks = [
  { to: "/", label: "Home", exact: true },
  { to: "/esplora", label: "Ricerca", exact: false },
  { to: "/community", label: "Club", exact: false },
  { to: "/cantina", label: "La mia cantina", exact: false },
  { to: "/vendi", label: "Vendi", exact: false },
  { to: "/account", label: "Account", exact: false },
] as const;

export function VineaLayout({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { ruolo, setRuolo } = useVinea();

  return (
    <div className="min-h-dvh bg-background text-foreground pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-0">
      <a href="#contenuto-principale" className="skip-link" data-testid="skip-link">
        Vai al contenuto principale
      </a>
      <header
        className="sticky top-0 z-40 border-b border-border bg-crema/80 header-blur"
        data-testid="app-header"
      >
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3 md:py-4">
          <Link href="/" className="flex items-center gap-2.5" data-testid="brand-logo-link">
            <span className="grid h-9 w-9 place-items-center rounded-full bg-bordeaux text-crema font-serif text-lg">
              V
            </span>
            <span className="flex flex-col leading-none">
              <span className="font-serif text-2xl font-semibold tracking-tight text-bordeaux">
                Vinea
              </span>
              <span className="mt-0.5 text-[9px] font-medium uppercase tracking-[0.35em] text-oro">
                Wine Club
              </span>
            </span>
            <span
              className="rounded-full border border-oro/50 bg-oro/10 px-2 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-bordeaux"
              data-testid="beta-badge"
            >
              Beta
            </span>
          </Link>

          <nav
            className="ml-6 hidden items-center gap-0.5 md:flex"
            aria-label="Navigazione principale"
            data-testid="desktop-nav"
          >
            {desktopLinks.map((n) => {
              const active = n.exact
                ? pathname === n.to || (n.to === "/" && pathname === "/home")
                : pathname === n.to || pathname.startsWith(n.to + "/");
              return (
                <Link
                  key={n.to}
                  href={n.to}
                  aria-current={active ? "page" : undefined}
                  data-testid={`nav-link-${n.label.toLowerCase().replace(/\s+/g, "-")}`}
                  className={`relative rounded-full px-3 py-1.5 text-sm font-medium transition ${
                    active
                      ? "bg-bordeaux text-crema font-semibold shadow-sm ring-1 ring-bordeaux/30"
                      : "text-antracite hover:bg-secondary"
                  }`}
                >
                  {n.label}
                </Link>
              );
            })}
            {ruolo === "admin" && (
              <Link
                href="/admin"
                data-testid="nav-link-admin"
                aria-current={pathname.startsWith("/admin") ? "page" : undefined}
                className={`rounded-full px-3 py-1.5 text-sm font-medium transition ${pathname.startsWith("/admin") ? "bg-antracite text-crema font-semibold" : "text-antracite hover:bg-secondary"}`}
              >
                <span className="inline-flex items-center gap-1">
                  <Shield className="h-3.5 w-3.5" /> Admin
                </span>
              </Link>
            )}
          </nav>

          <div className="ml-auto flex items-center gap-2">
            {ruolo === "guest" && (
              // Punta a /registrati e non a /onboarding: il wizard di
              // onboarding non è portato (i suoi passi obiettivi/preferenze/
              // profilo appartengono a ProfileService, fase successiva),
              // mentre /registrati è la registrazione reale introdotta in
              // Fase 5a. Conseguenza diretta della scelta di scope minimale
              // già approvata, non una deviazione a sé.
              <Link
                href="/registrati"
                data-testid="cta-register"
                className="hidden rounded-full bg-bordeaux px-3 py-1.5 text-xs font-semibold text-crema hover:bg-bordeaux/90 sm:inline-flex"
              >
                Registrati
              </Link>
            )}
            {DEMO_UI_ABILITATA ? <DemoSwitch ruolo={ruolo} setRuolo={setRuolo} /> : null}
            <Link
              href="/esplora"
              aria-label="Ricerca"
              data-testid="header-search-link"
              className="rounded-full p-2 hover:bg-secondary"
            >
              <Search className="h-5 w-5" />
            </Link>
            <HeaderInboxActions />
          </div>
        </div>
      </header>

      <main
        id="contenuto-principale"
        tabIndex={-1}
        className="mx-auto max-w-6xl px-4 py-6 focus:outline-none page-enter"
        key={pathname}
        data-testid="page-content"
      >
        {children}
      </main>

      <nav
        className="fixed bottom-0 left-0 right-0 z-40 border-t border-border bg-crema/90 pb-safe header-blur md:hidden"
        aria-label="Navigazione principale"
        data-testid="mobile-nav"
      >
        <ul className="grid grid-cols-5">
          {nav.map((n) => {
            const to = n.to === "/" && ruolo !== "guest" ? "/home" : n.to;
            const active = n.exact
              ? pathname === to || (n.to === "/" && pathname === "/home")
              : pathname.startsWith(n.to);
            const Icon = n.icon;
            const isSell = n.to === "/vendi";
            return (
              <li key={n.to} className="flex">
                <Link
                  href={to}
                  aria-current={active ? "page" : undefined}
                  aria-label={n.label}
                  data-testid={`mobile-nav-${n.label.toLowerCase()}`}
                  className={`relative flex flex-1 flex-col items-center justify-center gap-1 py-2.5 text-[11px] ${
                    active ? "text-bordeaux font-semibold" : "text-antracite/70 font-medium"
                  }`}
                >
                  {active && !isSell && (
                    <span
                      aria-hidden
                      className="absolute top-0 h-0.5 w-8 rounded-full bg-bordeaux"
                    />
                  )}
                  {isSell ? (
                    <span
                      className={`grid h-10 w-10 -mt-3 place-items-center rounded-full bg-bordeaux text-crema shadow-lg ${active ? "ring-2 ring-oro" : ""}`}
                    >
                      <Icon className="h-5 w-5" />
                    </span>
                  ) : (
                    <Icon
                      className={`h-5 w-5 ${active ? "text-bordeaux" : ""}`}
                      strokeWidth={active ? 2.5 : 2}
                    />
                  )}
                  <span>{n.label}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      <Toaster position="top-center" richColors />

      {AI_UI.sommelier && <SommelierChat />}
    </div>
  );
}

function DemoSwitch({ ruolo, setRuolo }: { ruolo: DemoRuolo; setRuolo: (r: DemoRuolo) => void }) {
  const opts: { v: DemoRuolo; l: string }[] = [
    { v: "guest", l: "Ospite" },
    { v: "user", l: "Utente" },
    { v: "admin", l: "Admin" },
  ];
  return (
    <div
      className="hidden rounded-full border border-border bg-card p-0.5 text-[11px] sm:flex"
      title="Modalità demo"
      data-testid="demo-switch"
    >
      {opts.map((o) => (
        <button
          key={o.v}
          onClick={() => setRuolo(o.v)}
          data-testid={`demo-switch-${o.v}`}
          className={`rounded-full px-2.5 py-1 font-medium transition ${
            ruolo === o.v ? "bg-bordeaux text-crema" : "text-antracite/70 hover:text-antracite"
          }`}
        >
          {o.l}
        </button>
      ))}
    </div>
  );
}

export function Kpi({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="rounded-2xl border border-border bg-card p-4">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 font-serif text-2xl font-semibold text-bordeaux">{value}</p>
      {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-4 flex items-end justify-between gap-4">
      <h2 className="font-serif text-2xl font-semibold text-antracite md:text-3xl">{children}</h2>
      {action}
    </div>
  );
}

export { Badge };
