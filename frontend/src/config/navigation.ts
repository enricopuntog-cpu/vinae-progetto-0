/**
 * Voci di navigazione (desktop + mobile).
 * Non importare direttamente icone qui: le route sono agnostiche dal renderer.
 * Layout.tsx mappa `iconKey` alla libreria Lucide effettiva.
 */

import { routes } from "./routes";

export type IconKey =
  "home" | "search" | "sell" | "club" | "profile" | "cellar" | "messages" | "bell" | "shield";

export type NavItem = {
  key: string;
  label: string;
  to: string;
  iconKey: IconKey;
  requiresAuth?: boolean;
  adminOnly?: boolean;
};

export const navDesktop: NavItem[] = [
  { key: "home", label: "Home", to: routes.home, iconKey: "home" },
  { key: "ricerca", label: "Ricerca", to: routes.ricerca, iconKey: "search" },
  { key: "club", label: "Club", to: routes.club, iconKey: "club" },
  {
    key: "cantina",
    label: "La mia cantina",
    to: routes.cantina,
    iconKey: "cellar",
    requiresAuth: true,
  },
  { key: "vendi", label: "Vendi", to: routes.vendi, iconKey: "sell", requiresAuth: true },
  { key: "profilo", label: "Profilo", to: routes.profilo, iconKey: "profile" },
];

export const navMobile: NavItem[] = [
  { key: "home", label: "Home", to: routes.home, iconKey: "home" },
  { key: "ricerca", label: "Ricerca", to: routes.ricerca, iconKey: "search" },
  { key: "vendi", label: "Vendi", to: routes.vendi, iconKey: "sell" },
  { key: "club", label: "Club", to: routes.club, iconKey: "club" },
  { key: "profilo", label: "Profilo", to: routes.profilo, iconKey: "profile" },
];
