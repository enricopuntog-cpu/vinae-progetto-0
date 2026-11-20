"use client";

import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import { Loader2, MessageSquareText } from "lucide-react";
import { ascoltaRichiesteSommelier, type ContestoUi } from "@/lib/phase10/sommelier-contesto-ui";

function Pulsante({ onClick, caricamento = false }: { onClick?: () => void; caricamento?: boolean }) {
  return (
    <button
      type="button"
      aria-label={caricamento ? "Apertura Sommelier AI" : "Apri chat Sommelier AI"}
      aria-busy={caricamento}
      aria-haspopup="dialog"
      aria-expanded={false}
      disabled={caricamento}
      data-testid="sommelier-trigger"
      onClick={onClick}
      className="fixed right-4 z-40 grid h-14 w-14 place-items-center rounded-full bg-bordeaux text-crema shadow-xl ring-4 ring-bordeaux/25 transition-transform duration-200 hover:scale-105 active:scale-95 md:h-16 md:w-16"
      style={{ bottom: "calc(env(safe-area-inset-bottom, 0px) + 5rem)" }}
    >
      <span className="absolute -top-1 -right-1 inline-flex h-3 w-3 rounded-full bg-oro ring-2 ring-crema" />
      {caricamento ? <Loader2 className="h-6 w-6 animate-spin" /> : <MessageSquareText className="h-6 w-6" />}
    </button>
  );
}

const Pannello = dynamic(() => import("@/components/vinea/SommelierChat"), {
  ssr: false,
  loading: () => <Pulsante caricamento />,
});

export default function SommelierLauncher() {
  const [richiesto, setRichiesto] = useState(false);
  // WI-004: una pagina (scheda del vino, Cantina) può aprire il pannello su un
  // contesto. Il launcher lo carica al primo evento e glielo passa; da lì in poi
  // il pannello ascolta da solo. Il contesto non porta nessun consenso.
  const [contestoIniziale, setContestoIniziale] = useState<ContestoUi | null>(null);

  useEffect(
    () =>
      ascoltaRichiesteSommelier((contesto) => {
        setContestoIniziale(contesto);
        setRichiesto(true);
      }),
    [],
  );

  // Dopo il primo click conserviamo lo stato della conversazione anche chiudendo.
  return richiesto ? (
    <Pannello inizialmenteAperto contestoIniziale={contestoIniziale} />
  ) : (
    <Pulsante onClick={() => setRichiesto(true)} />
  );
}
