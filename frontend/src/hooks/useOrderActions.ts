import { useCallback, useState } from "react";
import { toast } from "sonner";
import { wineImg } from "@/lib/wine-images";
import type { Order, OrderReview } from "@/data/orders";

type Packaging = "scatola_singola" | "scatola_polistirolo" | "cassa_legno";

type SellerPrepOptions = {
  orderId: string;
  updateSellerOrder: (orderId: string, patch: Partial<Order>) => void;
  markShipped: (orderId: string, trackingNumber: string, courier: string) => void;
};

export function useSellerPrepActions({
  orderId,
  updateSellerOrder,
  markShipped,
}: SellerPrepOptions) {
  const [imballaggio, setImballaggio] = useState<Packaging>("scatola_polistirolo");
  const [checks, setChecks] = useState<Record<string, boolean>>({
    foto_frontale: false,
    foto_capsula: false,
    foto_livello: false,
    foto_imballaggio: false,
  });
  const [tracking, setTracking] = useState("");
  const [courier, setCourier] = useState("Corriere Vinea");
  const [labelGenerated, setLabelGenerated] = useState(false);
  const [loading, setLoading] = useState(false);

  const allDone = Object.values(checks).every(Boolean);
  const canShip = allDone && tracking.trim().length >= 4 && labelGenerated;

  const generaLabel = useCallback(() => {
    setLoading(true);
    setTimeout(() => {
      const t = `VNA-${Math.floor(1000 + Math.random() * 8999)}-${Math.floor(100 + Math.random() * 899)}`;
      setTracking(t);
      setLabelGenerated(true);
      setLoading(false);
      updateSellerOrder(orderId, { sellerStatus: "da_spedire", buyerStatus: "in_preparazione" });
      toast.success("Etichetta di spedizione simulata generata");
    }, 900);
  }, [orderId, updateSellerOrder]);

  const conferma = useCallback(() => {
    setLoading(true);
    setTimeout(() => {
      markShipped(orderId, tracking, courier);
      setLoading(false);
    }, 700);
  }, [orderId, tracking, courier, markShipped]);

  return {
    imballaggio,
    setImballaggio,
    checks,
    setChecks,
    tracking,
    setTracking,
    courier,
    setCourier,
    labelGenerated,
    loading,
    allDone,
    canShip,
    generaLabel,
    conferma,
  };
}

type BuyerConfirmOptions = {
  orderId: string;
  confirmOk: (orderId: string) => void;
  openDispute: (
    orderId: string,
    d: { motivo: string; descrizione: string; foto: string[] },
  ) => void;
  onDisputeSubmitted?: () => void;
};

export function useBuyerConfirmActions({
  orderId,
  confirmOk,
  openDispute,
  onDisputeSubmitted,
}: BuyerConfirmOptions) {
  const [motivo, setMotivo] = useState("Bottiglia non conforme");
  const [descr, setDescr] = useState("");
  const [foto, setFoto] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadingConfirm, setLoadingConfirm] = useState(false);

  const simulaCarica = useCallback(() => {
    setFoto((prev) => [...prev, wineImg(`disp-${prev.length}-${Date.now()}`)]);
  }, []);

  const confirmDelivery = useCallback(() => {
    setLoadingConfirm(true);
    setTimeout(() => {
      confirmOk(orderId);
      setLoadingConfirm(false);
    }, 700);
  }, [orderId, confirmOk]);

  const submitDispute = useCallback(() => {
    setLoading(true);
    setTimeout(() => {
      openDispute(orderId, { motivo, descrizione: descr, foto });
      setLoading(false);
      onDisputeSubmitted?.();
    }, 800);
  }, [orderId, motivo, descr, foto, openDispute, onDisputeSubmitted]);

  return {
    motivo,
    setMotivo,
    descr,
    setDescr,
    foto,
    simulaCarica,
    loading,
    loadingConfirm,
    confirmDelivery,
    submitDispute,
  };
}

type DisputeResolutionOptions = {
  orderId: string;
  resolveDispute: (
    orderId: string,
    esito: "rimborsata" | "risolta" | "respinta",
    nota?: string,
  ) => void;
};

export function useDisputeResolutionActions({ orderId, resolveDispute }: DisputeResolutionOptions) {
  const [loading, setLoading] = useState(false);

  const resolve = useCallback(
    (esito: "rimborsata" | "risolta" | "respinta", nota: string) => {
      setLoading(true);
      setTimeout(() => {
        resolveDispute(orderId, esito, nota);
        setLoading(false);
      }, 700);
    },
    [orderId, resolveDispute],
  );

  return { loading, resolve };
}

type ReviewActionsOptions = {
  orderId: string;
  existing?: OrderReview;
  submitReview: (orderId: string, r: OrderReview) => void;
};

export function useReviewActions({ orderId, existing, submitReview }: ReviewActionsOptions) {
  const [voto, setVoto] = useState(existing?.voto ?? 5);
  const [conf, setConf] = useState(existing?.conformita ?? 5);
  const [imb, setImb] = useState(existing?.imballaggio ?? 5);
  const [com, setCom] = useState(existing?.comunicazione ?? 5);
  const [testo, setTesto] = useState(existing?.testo ?? "");
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(!!existing);

  const submit = useCallback(() => {
    setLoading(true);
    setTimeout(() => {
      submitReview(orderId, {
        voto,
        conformita: conf,
        imballaggio: imb,
        comunicazione: com,
        testo,
        ts: new Date().toISOString(),
      });
      setLoading(false);
      setSent(true);
    }, 700);
  }, [orderId, voto, conf, imb, com, testo, submitReview]);

  return {
    voto,
    setVoto,
    conf,
    setConf,
    imb,
    setImb,
    com,
    setCom,
    testo,
    setTesto,
    loading,
    sent,
    submit,
  };
}
