"use client";

import { LinkSuIntento as Link } from "@/components/vinea/LinkSuIntento";
import SommelierChat from "@/components/vinea/SommelierLauncher";
import { VineaLogo } from "@/components/vinea/VineaLogo";
import { usePathname } from "next/navigation";
import {
  Home,
  PlusCircle,
  Users,
  User,
  Search,
  Shield,
  Wine,
  TriangleAlert,
  type LucideIcon,
} from "lucide-react";
import { type ReactNode } from "react";
import { Toaster } from "@/components/ui/sonner";
import { Badge } from "@/components/ui/badge";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { HeaderInboxActions } from "@/components/vinea/notifications/HeaderInboxActions";
import { AI_UI, CLUB_UI_ABILITATA, DEMO_UI_ABILITATA } from "@/config/features";
import type { IncidentNotice } from "@/lib/incidents/notice";
import {
  classiRicercaHeader,
  navMobile,
  percorsoAttivo,
  voceNavAttiva,
  type IconaNavMobile,
} from "@/lib/shell/navigazione-mobile";
import { useVinea, type DemoRuolo } from "@/lib/vinea-store";

// Il launcher carica il pannello Sommelier soltanto al primo click.

// D6. Le voci della barra mobile stanno in `@/lib/shell/navigazione-mobile`,
// che tiene anche lo stato attivo: sono le due cose della shell che si possono
// verificare senza montare React. Qui resta solo la traduzione da nome
// dell'icona a componente, che React deve comunque avere sotto mano.
//
// Fase 12a. La voce Club sta in entrambe le navigazioni, nella posizione che
// aveva prima della #44: quella PR l'aveva tolta perche /community era una
// community finta e diventava un notFound(), non perche la voce fosse di
// troppo.
const ICONE_NAV: Record<IconaNavMobile, LucideIcon> = {
  home: Home,
  ricerca: Search,
  vendi: PlusCircle,
  club: Users,
  cantina: Wine,
  // Da ospiti la quinta voce resta Account e porta al profilo, non a /accedi:
  // /account rimanda da solo alla schermata di accesso quando la sessione
  // manca. Da autenticati quel posto e della Cantina, perche l'avatar
  // dell'header porta gia al profilo.
  account: User,
};

const desktopLinks = [
  { to: "/", label: "Home", exact: true },
  { to: "/esplora", label: "Ricerca", exact: false },
  { to: "/community", label: "Club", exact: false },
  { to: "/cantina", label: "La mia cantina", exact: false },
  { to: "/vendi", label: "Vendi", exact: false },
  { to: "/account", label: "Account", exact: false },
] as const;

export function VineaLayout({
  children,
  incidentNotice,
}: {
  children: ReactNode;
  incidentNotice: IncidentNotice | null;
}) {
  const pathname = usePathname();
  const { ruolo, setRuolo, authRuolo, authProfilo } = useVinea();
  // Lo stesso segnale che la barra mobile usava gia per mandare Home su /home:
  // non ne serve un secondo. Con lo switcher demo acceso `ruolo` e quello
  // scelto a mano, e l'avatar ricade sulla silhouette perche `authProfilo` resta
  // nullo senza una sessione vera - che e esattamente cio che deve succedere.
  const autenticato = ruolo !== "guest";
  const vociMobile = navMobile(autenticato).filter(
    (voce) => CLUB_UI_ABILITATA || voce.icona !== "club",
  );
  const vociDesktop = desktopLinks.filter(
    (voce) => CLUB_UI_ABILITATA || voce.to !== "/community",
  );

  return (
    <div className="min-h-dvh bg-background text-foreground pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-0">
      <a href="#contenuto-principale" className="skip-link" data-testid="skip-link">
        Vai al contenuto principale
      </a>
      {incidentNotice ? <IncidentBanner notice={incidentNotice} /> : null}
      <header
        className="sticky top-0 z-40 border-b border-border bg-crema/80 header-blur"
        data-testid="app-header"
      >
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3 md:py-4">
          <Link href="/" className="flex items-center gap-2.5" data-testid="brand-logo-link">
            <VineaLogo />
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
            {vociDesktop.map((n) => {
              const active = n.exact
                ? pathname === n.to || (n.to === "/" && pathname === "/home")
                : pathname === n.to || pathname.startsWith(n.to + "/");
              return (
                <Link
                  key={n.to}
                  href={n.to}
                  prefetch={n.to === "/esplora" || n.to === "/community" ? null : undefined}
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
            {/*
              D10. Il ruolo **reale**, non quello del selettore. Prima bastava
              scegliere «Admin» nello switcher demo per far comparire questa
              voce, che portava a una pagina che ora risponde `notFound()`: un
              collegamento che non porta da nessuna parte e peggio di un
              collegamento assente. Il confine resta `user_roles`; questa riga
              decide solo che cosa si vede.
            */}
            {authRuolo === "admin" && (
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
              className={`rounded-full p-2 hover:bg-secondary ${classiRicercaHeader(autenticato)}`}
            >
              <Search className="h-5 w-5" />
            </Link>
            {/* Messaggi e Notifiche, in quest'ordine, dall'infrastruttura della
                Fase 8 gia in uso: nessuna messaggistica nuova passa di qui. */}
            <HeaderInboxActions />
            {autenticato && (
              // Ultimo elemento di una riga che scorre da sinistra a destra:
              // e cosi che l'avatar sta all'estrema destra, senza posizionamento
              // assoluto che poi litiga con il resto.
              //
              // Solo mobile: su desktop la barra principale ha gia la voce
              // Account, e questo task non tocca quella shell.
              <Link
                href="/account"
                aria-label="Account"
                data-testid="header-avatar-link"
                // Stesso confronto della barra: `startsWith` nudo direbbe
                // "pagina corrente" anche su una futura rotta che comincia per
                // /account senza esserlo, ed e' la bugia che gli screen reader
                // leggono per prima.
                aria-current={percorsoAttivo("/account", pathname) ? "page" : undefined}
                className="rounded-full p-0.5 hover:bg-secondary md:hidden"
              >
                <AvatarPersona
                  avatarUrl={authProfilo?.avatarUrl}
                  proprietarioId={authProfilo?.userId}
                />
              </Link>
            )}
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

      <footer className="mx-auto max-w-6xl px-4 pb-6 text-center text-xs text-muted-foreground">
          <Link href="/legale" className="underline-offset-2 hover:text-bordeaux hover:underline">
            Centro legale
          </Link>
          <span aria-hidden="true" className="mx-2">·</span>
          <Link href="/legale#privacy" className="underline-offset-2 hover:text-bordeaux hover:underline">Privacy</Link>
          <span aria-hidden="true" className="mx-2">·</span>
          <Link href="/legale#termini" className="underline-offset-2 hover:text-bordeaux hover:underline">Termini</Link>
          <span aria-hidden="true" className="mx-2">·</span>
          <Link href="/legale#cookie" className="underline-offset-2 hover:text-bordeaux hover:underline">Cookie</Link>
      </footer>

      <nav
        className="fixed bottom-0 left-0 right-0 z-40 border-t border-border bg-crema/90 pb-safe header-blur md:hidden"
        aria-label="Navigazione principale"
        data-testid="mobile-nav"
      >
        <ul className="grid grid-cols-5">
          {vociMobile.map((n) => {
            const active = voceNavAttiva(n, pathname);
            const Icon = ICONE_NAV[n.icona];
            const isSell = n.to === "/vendi";
            return (
              <li key={n.to} className="flex">
                <Link
                  href={n.to}
                  prefetch={n.to === "/esplora" || n.to === "/community" ? null : undefined}
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

const INCIDENT_STYLE: Record<IncidentNotice["kind"], string> = {
  manutenzione: "border-oro/40 bg-oro/15 text-antracite",
  degrado: "border-amber-500/40 bg-amber-50 text-amber-950",
  incidente: "border-red-500/40 bg-red-50 text-red-950",
  sicurezza: "border-bordeaux/40 bg-bordeaux/10 text-bordeaux",
};

function IncidentBanner({ notice }: { notice: IncidentNotice }) {
  return (
    <aside
      role={notice.kind === "incidente" || notice.kind === "sicurezza" ? "alert" : "status"}
      className={`border-b px-4 py-2 text-sm ${INCIDENT_STYLE[notice.kind]}`}
      data-testid="incident-banner"
    >
      <div className="mx-auto flex max-w-6xl items-start gap-2">
        <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
        <p className="flex-1">
          {notice.message}
          {notice.statusUrl ? (
            <>
              {" "}
              <a
                href={notice.statusUrl}
                rel="noreferrer"
                className="font-semibold underline underline-offset-2"
              >
                Aggiornamenti sullo stato
              </a>
            </>
          ) : null}
        </p>
      </div>
    </aside>
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
