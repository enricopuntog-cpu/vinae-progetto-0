import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  Outlet,
  Link,
  createRootRouteWithContext,
  useRouter,
  HeadContent,
  Scripts,
} from "@tanstack/react-router";
import type { ReactNode } from "react";

import appCss from "../styles.css?url";
import { VineaProvider } from "@/lib/vinea-store";
import { VineaLayout } from "@/components/vinea/Layout";
import { NotFoundState, ErrorState } from "@/components/vinea/States";

function NotFoundComponent() {
  return (
    <div className="min-h-screen bg-background py-16">
      <NotFoundState />
    </div>
  );
}

function ErrorComponent({ error, reset }: { error: Error; reset: () => void }) {
  console.error(error);
  const router = useRouter();
  return (
    <div className="min-h-screen bg-background py-16">
      <ErrorState
        title="Questa pagina non si è caricata"
        message="Puoi riprovare o tornare alla home. I tuoi dati demo restano al sicuro."
        onRetry={() => {
          router.invalidate();
          reset();
        }}
      />
    </div>
  );
}

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Vinea — Ogni bottiglia ha una storia" },
      {
        name: "description",
        content:
          "Il marketplace sociale italiano per il vino tra privati. Compra, vendi e scopri bottiglie con una storia.",
      },
      { property: "og:title", content: "Vinea — Marketplace sociale del vino" },
      {
        property: "og:description",
        content: "Compra, vendi e scopri vini pregiati tra privati appassionati.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "icon", href: "/favicon.ico", type: "image/x-icon" },
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      { rel: "preconnect", href: "https://fonts.gstatic.com", crossOrigin: "anonymous" },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Inter:wght@400;500;600;700&display=swap",
      },
    ],
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent,
});

function RootShell({ children }: { children: ReactNode }) {
  return (
    <html lang="it">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function RootComponent() {
  const { queryClient } = Route.useRouteContext();

  return (
    <QueryClientProvider client={queryClient}>
      <VineaProvider>
        <VineaLayout />
      </VineaProvider>
    </QueryClientProvider>
  );
}
