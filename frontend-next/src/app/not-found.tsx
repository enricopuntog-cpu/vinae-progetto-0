import { NotFoundState } from "@/components/vinea/States";

/** Qualunque URL senza pagina. Lo stato HTTP resta 404 e Next aggiunge `noindex`. */
export default function NonTrovato() {
  return <NotFoundState />;
}
