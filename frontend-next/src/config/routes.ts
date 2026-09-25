/**
 * Route path registry.
 * Ogni percorso interno usato nell'app passa da qui — semplifica il porting
 * a Next.js App Router (basta sostituire i valori con /app segment paths).
 */

export const routes = {
  home: "/",
  homeUtente: "/home",
  ricerca: "/esplora",
  annuncio: (id: string) => `/annuncio/${id}`,
  cantina: "/cantina",
  vendi: "/vendi",
  club: "/community",
  clubDettaglio: (slug: string) => `/community/${slug}`,
  messaggi: "/messaggi",
  notifiche: "/notifiche",
  profilo: "/profilo",
  /** Il profilo pubblico di un'altra persona: un uuid, non uno username. */
  profiloPubblico: (id: string) => `/profilo/${id}`,
  /** La Cantina pubblica di quella persona, che è una pagina del suo profilo. */
  cantinaPubblica: (id: string) => `/profilo/${id}/cantina`,
  venditore: (username: string) => `/venditore/${username}`,
  onboarding: "/onboarding",
  verificaVenditore: "/verifica-venditore",
  checkout: (id: string) => `/checkout/${id}`,
  acquisti: "/acquisti",
  vendite: "/vendite",
  ordine: (id: string) => `/ordine/${id}`,
  segnalazioni: "/segnalazioni",
  admin: "/admin",
  adminStati: "/admin/stati",
} as const;

export type RouteKey = keyof typeof routes;
