"use client";

import { useCallback, useMemo, useState } from "react";
import { toast } from "sonner";
import type { Notifica } from "@/data/extra";
import {
  profiloDemoIniziale,
  calcolaCompletamento,
  type Obiettivo,
  type EmailStatus,
  type AgeStatus,
  type IdentityStatus,
  type SellerStatus,
  type ProfiloUtente,
} from "@/data/onboarding";

type NotificationInput = Omit<Notifica, "id" | "letta">;

type ProfileDomainOptions = {
  pushNotifica: (notification: NotificationInput) => void;
};

export function useProfileDomain({ pushNotifica }: ProfileDomainOptions) {
  const [registrato, setRegistrato] = useState(true); // demo: user già registrato
  const [emailStatus, setEmailStatus] = useState<EmailStatus>("verificata");
  const [ageStatus, setAgeStatus] = useState<AgeStatus>("dichiarata");
  const [identityStatus, setIdentityStatus] = useState<IdentityStatus>("non_avviata");
  const [sellerStatus, setSellerStatus] = useState<SellerStatus>("non_abilitato");
  const [obiettivi, setObiettiviSet] = useState<Set<Obiettivo>>(new Set(["comprare", "cantina"]));
  const [regioniPreferite, setRegioniPreferite] = useState<Set<string>>(
    new Set(["Piemonte", "Toscana"]),
  );
  const [tipologiePreferite, setTipologiePreferite] = useState<Set<string>>(
    new Set(["Rossi strutturati"]),
  );
  const [fasciaPrezzo, setFasciaPrezzoState] = useState<string | null>("50-150");
  const [clubSuggeritiSalvati] = useState(true);
  const [preferenzeSalvate, setPreferenzeSalvate] = useState(true);
  const [profiloBase, setProfiloBase] = useState(true);
  const [profilo, setProfilo] = useState<ProfiloUtente>(profiloDemoIniziale);

  const registerAccount = useCallback(
    (p: { username: string; email: string; dob: string; maggiorenne: boolean }) => {
      setRegistrato(true);
      setEmailStatus("non_verificata");
      setAgeStatus(p.maggiorenne ? "dichiarata" : "da_verificare");
      setProfilo((prev) => ({
        ...prev,
        username: p.username || prev.username,
        email: p.email || prev.email,
        dob: p.dob || prev.dob,
      }));
      toast.success("Account demo creato");
    },
    [],
  );

  const verifyEmail = useCallback(() => {
    setEmailStatus("verificata");
    setAgeStatus((prev) => (prev === "da_verificare" ? "dichiarata" : prev));
    toast.success("Email verificata (demo)");
  }, []);

  const toggleObiettivo = useCallback((o: Obiettivo) => {
    setObiettiviSet((prev) => {
      const n = new Set(prev);
      if (n.has(o)) n.delete(o);
      else n.add(o);
      return n;
    });
  }, []);
  const saveObiettivi = useCallback(() => {
    toast.success("Obiettivi salvati");
  }, []);

  const toggleRegionePref = useCallback((r: string) => {
    setRegioniPreferite((prev) => {
      const n = new Set(prev);
      if (n.has(r)) n.delete(r);
      else n.add(r);
      return n;
    });
  }, []);
  const toggleTipologiaPref = useCallback((t: string) => {
    setTipologiePreferite((prev) => {
      const n = new Set(prev);
      if (n.has(t)) n.delete(t);
      else n.add(t);
      return n;
    });
  }, []);
  const setFasciaPrezzo = useCallback((id: string) => setFasciaPrezzoState(id), []);
  const savePreferenze = useCallback(() => {
    setPreferenzeSalvate(true);
    toast.success("Preferenze salvate");
  }, []);

  const saveProfilo = useCallback((p: Partial<ProfiloUtente>) => {
    setProfilo((prev) => ({ ...prev, ...p }));
    setProfiloBase(true);
    toast.success("Profilo aggiornato");
  }, []);

  const startIdentityVerification = useCallback(() => {
    setIdentityStatus("in_verifica");
    pushNotifica({
      categoria: "sistema",
      testo: "Verifica identità inviata: risposta entro 24–48h (demo)",
      tempo: "ora",
    });
    toast.success("Verifica inviata (demo)");
  }, [pushNotifica]);

  const completeIdentityVerification = useCallback(
    (esito: "verificata" | "rifiutata") => {
      setIdentityStatus(esito);
      setAgeStatus(esito === "verificata" ? "verificata" : "dichiarata");
      if (esito === "verificata") {
        setSellerStatus("abilitato");
        pushNotifica({
          categoria: "sistema",
          testo: "Identità verificata: ora puoi vendere su Vinea",
          tempo: "ora",
        });
        toast.success("Identità verificata — venditore abilitato");
      } else {
        pushNotifica({
          categoria: "sistema",
          testo: "Verifica identità non riuscita. Riprova (demo)",
          tempo: "ora",
        });
        toast.error("Verifica rifiutata (demo)");
      }
    },
    [pushNotifica],
  );

  const resetOnboarding = useCallback(() => {
    setRegistrato(false);
    setEmailStatus("non_verificata");
    setAgeStatus("da_verificare");
    setIdentityStatus("non_avviata");
    setSellerStatus("non_abilitato");
    setObiettiviSet(new Set());
    setPreferenzeSalvate(false);
    setProfiloBase(false);
    toast("Onboarding reimpostato");
  }, []);

  const resetForGuest = useCallback(() => {
    setRegistrato(false);
    setEmailStatus("non_verificata");
    setAgeStatus("da_verificare");
    setIdentityStatus("non_avviata");
    setSellerStatus("non_abilitato");
    setObiettiviSet(new Set());
    setRegioniPreferite(new Set());
    setTipologiePreferite(new Set());
    setFasciaPrezzoState(null);
    setPreferenzeSalvate(false);
    setProfiloBase(false);
  }, []);

  const profileCompletion = useMemo(
    () =>
      calcolaCompletamento({
        registrato,
        emailVerificata: emailStatus === "verificata",
        obiettivi: obiettivi.size,
        preferenzeSalvate,
        profiloBase,
        identita: identityStatus,
        venditore: sellerStatus,
      }),
    [
      registrato,
      emailStatus,
      obiettivi,
      preferenzeSalvate,
      profiloBase,
      identityStatus,
      sellerStatus,
    ],
  );

  return {
    registrato,
    emailStatus,
    ageStatus,
    identityStatus,
    sellerStatus,
    obiettivi,
    regioniPreferite,
    tipologiePreferite,
    fasciaPrezzo,
    clubSuggeritiSalvati,
    preferenzeSalvate,
    profiloBase,
    profilo,
    registerAccount,
    verifyEmail,
    toggleObiettivo,
    saveObiettivi,
    toggleRegionePref,
    toggleTipologiaPref,
    setFasciaPrezzo,
    savePreferenze,
    saveProfilo,
    startIdentityVerification,
    completeIdentityVerification,
    resetOnboarding,
    resetForGuest,
    profileCompletion,
  };
}