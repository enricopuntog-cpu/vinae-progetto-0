import { useCallback, useMemo, useState } from "react";
import { toast } from "sonner";
import { notificheComplete, type Notifica } from "@/data/extra";

export function useMessagingDomain() {
  const [notifiche, setNotifiche] = useState<Notifica[]>(notificheComplete);

  const segnaLetta = useCallback((id: string) => {
    setNotifiche((prev) => prev.map((n) => (n.id === id ? { ...n, letta: true } : n)));
  }, []);

  const segnaTutteLette = useCallback(() => {
    setNotifiche((prev) => prev.map((n) => ({ ...n, letta: true })));
    toast.success("Tutte le notifiche sono state lette");
  }, []);

  const pushNotifica = useCallback((n: Omit<Notifica, "id" | "letta">) => {
    setNotifiche((prev) => [
      { id: `n-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, letta: false, ...n },
      ...prev,
    ]);
  }, []);

  const nonLette = useMemo(() => notifiche.filter((n) => !n.letta).length, [notifiche]);

  return {
    notifiche,
    nonLette,
    segnaLetta,
    segnaTutteLette,
    pushNotifica,
  };
}
