import { useCallback, useState } from "react";
import { toast } from "sonner";
import { apiJson, jsonRequest } from "@/services/api-client";
import { listingSuggestionSchema, type ListingSuggestion } from "@/services/api-contracts";
import type { SellerStatus } from "@/data/onboarding";

export type Modalita = "privata" | "pubblica" | "vendita";

type SellWizardOptions = {
  initialMode: Modalita;
  sellerStatus: SellerStatus;
  onNavigate: (path: "/cantina" | "/verifica-venditore") => void;
};

const VENDITA_STEPS = [
  "Modalità",
  "Foto",
  "Identificazione",
  "Condizioni",
  "Provenienza",
  "Prezzo",
  "Consegna",
  "Anteprima",
];

const CATALOGAZIONE_STEPS = [
  "Modalità",
  "Foto",
  "Identificazione",
  "Condizioni",
  "Provenienza",
  "Anteprima",
];

export function useSellWizard({ initialMode, sellerStatus, onNavigate }: SellWizardOptions) {
  const [modalita, setModalita] = useState<Modalita>(initialMode);
  const [step, setStep] = useState(0);
  const [d, setD] = useState({
    produttore: "",
    nome: "",
    annata: "",
    regione: "",
    tipo: "Rosso",
    condizione: "Perfetto",
    conservazione: "",
    storia: "",
    prezzo: "",
    disponibili: "1",
  });
  const set = (k: keyof typeof d) => (v: string) => setD((s) => ({ ...s, [k]: v }));

  const [aiHint, setAiHint] = useState("");
  const [aiSug, setAiSug] = useState<ListingSuggestion | null>(null);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState<string | null>(null);

  const askListingAI = useCallback(async () => {
    if (!aiHint.trim()) return;
    setAiLoading(true);
    setAiError(null);
    try {
      setAiSug(
        await apiJson(
          "/api/ai/listing-suggestion",
          listingSuggestionSchema,
          jsonRequest({ hint: aiHint.trim() }, { method: "POST" }),
        ),
      );
    } catch (e: unknown) {
      setAiError(e instanceof Error ? e.message : "Errore AI");
      setAiSug(null);
    } finally {
      setAiLoading(false);
    }
  }, [aiHint]);

  const applyAiSuggestion = useCallback(() => {
    if (!aiSug) return;
    setD((s) => ({
      ...s,
      produttore: aiSug.produttore || s.produttore,
      nome: aiSug.nome || s.nome,
      annata: aiSug.annata ? String(aiSug.annata) : s.annata,
      regione: aiSug.regione || s.regione,
      tipo: aiSug.tipologia || s.tipo,
      storia: aiSug.note_degustazione || s.storia,
      conservazione: aiSug.condizioni_suggerite || s.conservazione,
    }));
    toast.success("Suggerimenti AI applicati");
  }, [aiSug]);

  const isVendita = modalita === "vendita";
  const bloccatoVendita = isVendita && sellerStatus !== "abilitato";
  const steps = isVendita ? VENDITA_STEPS : CATALOGAZIONE_STEPS;
  const progress = ((step + 1) / steps.length) * 100;
  const next = useCallback(() => setStep((s) => Math.min(steps.length - 1, s + 1)), [steps.length]);
  const prev = useCallback(() => setStep((s) => Math.max(0, s - 1)), []);

  const pubblica = useCallback(() => {
    if (isVendita) {
      if (bloccatoVendita) {
        toast.error("Devi completare la verifica venditore prima di pubblicare");
        onNavigate("/verifica-venditore");
        return;
      }
      toast.success("Annuncio pubblicato! (demo)");
      onNavigate("/cantina");
    } else if (modalita === "pubblica") {
      toast.success("Bottiglia aggiunta alla cantina pubblica (demo)");
      onNavigate("/cantina");
    } else {
      toast.success("Bottiglia aggiunta alla tua cantina privata (demo)");
      onNavigate("/cantina");
    }
  }, [isVendita, bloccatoVendita, modalita, onNavigate]);

  const salvaBozza = useCallback(() => {
    toast.success("Bozza salvata nella cantina (demo)");
    onNavigate("/cantina");
  }, [onNavigate]);

  const suggerito = d.produttore.toLowerCase().includes("sassicaia")
    ? 260
    : d.produttore.toLowerCase().includes("barolo")
      ? 300
      : 120;

  return {
    modalita,
    setModalita,
    step,
    steps,
    progress,
    next,
    prev,
    isVendita,
    bloccatoVendita,
    d,
    set,
    suggerito,
    aiHint,
    setAiHint,
    aiSug,
    aiLoading,
    aiError,
    askListingAI,
    applyAiSuggestion,
    pubblica,
    salvaBozza,
  };
}
