import { NotFoundState } from "@/components/vinea/States";

export default function NotFound() {
  return (
    <NotFoundState
      title="Club non trovato"
      message="Il Club che cercavi non esiste o non è più visibile."
      ritorno={{ href: "/community", etichetta: "Torna ai Club" }}
    />
  );
}
