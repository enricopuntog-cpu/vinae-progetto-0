import { NotFoundState } from "@/components/vinea/States";

export default function NotFound() {
  return (
    <NotFoundState
      title="Profilo non disponibile"
      message="Il profilo richiesto non è disponibile."
      ritorno={{ href: "/esplora", etichetta: "Esplora gli annunci" }}
    />
  );
}
