import { NotFoundState } from "@/components/vinea/States";

export default function NotFound() {
  return (
    <NotFoundState
      title="Annuncio non trovato"
      message="L'annuncio potrebbe essere stato venduto o rimosso dal venditore."
      ritorno={{ href: "/esplora", etichetta: "Torna alla ricerca" }}
    />
  );
}
