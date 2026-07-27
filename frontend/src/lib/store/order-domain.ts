import { useCallback, useState } from "react";
import { toast } from "sonner";
import type { Notifica } from "@/data/extra";
import {
  calcolaProtezione,
  calcolaSpedizione,
  indirizzoDemo,
  ordersSeed,
  proposalsSeed,
  salesSeed,
  type BuyerOrderStatus,
  type DeliveryMode,
  type Order,
  type OrderReview,
  type Proposal,
  type TrackingEvent,
} from "@/data/orders";
import { wines } from "@/data/wines";

type DemoPaymentMethod = "carta_demo" | "paypal_demo" | "bonifico_demo";
type NotificationInput = Omit<Notifica, "id" | "letta">;

export type CreateOrderInput = {
  wineId: string;
  quantita: number;
  deliveryMode: DeliveryMode;
  metodoPagamento: DemoPaymentMethod;
  proposalId?: string;
  prezzoUnitario?: number;
};

type OrderDomainOptions = {
  pushNotifica: (notification: NotificationInput) => void;
  recordProposalPrice: (wineId: string, price: number) => void;
};

export function useOrderDomain({ pushNotifica, recordProposalPrice }: OrderDomainOptions) {
  const [orders, setOrders] = useState<Order[]>(ordersSeed);
  const [sales, setSales] = useState<Order[]>(salesSeed);
  const [proposals, setProposals] = useState<Proposal[]>(proposalsSeed);

  const getOrder = useCallback(
    (id: string) =>
      orders.find((order) => order.id === id) ?? sales.find((order) => order.id === id),
    [orders, sales],
  );

  const createOrder = useCallback(
    async (input: CreateOrderInput): Promise<Order> => {
      const wine = wines.find((candidate) => candidate.id === input.wineId);
      if (!wine) throw new Error("Vino non trovato");

      await new Promise((resolve) => setTimeout(resolve, 1200));
      const prezzoUnitario = input.prezzoUnitario ?? wine.prezzo;
      const subtotale = prezzoUnitario * input.quantita;
      const spedizione = calcolaSpedizione(input.deliveryMode, subtotale);
      const protezione = calcolaProtezione(subtotale);
      const now = new Date();
      const id = `ORD-2026-${String(1000 + Math.floor(Math.random() * 8999)).slice(-4)}`;
      const cartaMascherata =
        input.metodoPagamento === "carta_demo"
          ? "Visa •••• 4242"
          : input.metodoPagamento === "paypal_demo"
            ? "PayPal — elena@demo.it"
            : "Bonifico bancario (demo)";
      const order: Order = {
        id,
        wineId: wine.id,
        quantita: input.quantita,
        prezzoUnitario,
        spedizione,
        protezione,
        totale: subtotale + spedizione + protezione,
        deliveryMode: input.deliveryMode,
        indirizzo: indirizzoDemo,
        metodoPagamento: input.metodoPagamento,
        cartaMascherata,
        buyer: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68" },
        seller: {
          nome: wine.venditore.nome,
          avatar: wine.venditore.avatar,
          verificato: wine.venditore.verificato,
        },
        buyerStatus: "pagato",
        sellerStatus: "nuovo",
        createdAt: now.toISOString(),
        paidAt: now.toISOString(),
        tracking: [
          { id: "t1", ts: now.toISOString(), titolo: "Ordine ricevuto", tipo: "sistema" },
          {
            id: "t2",
            ts: now.toISOString(),
            titolo: "Pagamento confermato",
            descrizione: "Simulazione demo — nessun addebito reale",
            tipo: "sistema",
          },
        ],
        fromProposalId: input.proposalId,
      };

      setOrders((current) => [order, ...current]);
      pushNotifica({
        categoria: "marketplace",
        testo: `Ordine ${id} confermato: ${wine.nome} ${wine.annata}`,
        tempo: "ora",
      });
      if (input.proposalId) {
        setProposals((current) =>
          current.map((proposal) =>
            proposal.id === input.proposalId
              ? { ...proposal, stato: "convertita", orderId: id }
              : proposal,
          ),
        );
      }
      return order;
    },
    [pushNotifica],
  );

  const patchOrder = useCallback((orderId: string, patch: (order: Order) => Order) => {
    setOrders((current) => current.map((order) => (order.id === orderId ? patch(order) : order)));
    setSales((current) => current.map((order) => (order.id === orderId ? patch(order) : order)));
  }, []);

  const advanceOrder = useCallback(
    (orderId: string, target: BuyerOrderStatus) => {
      patchOrder(orderId, (order) => ({ ...order, buyerStatus: target }));
    },
    [patchOrder],
  );

  const updateSellerOrder = useCallback(
    (orderId: string, patch: Partial<Order>) => {
      patchOrder(orderId, (order) => ({ ...order, ...patch }));
    },
    [patchOrder],
  );

  const addTracking = useCallback(
    (orderId: string, event: Omit<TrackingEvent, "id" | "ts"> & { ts?: string }) => {
      patchOrder(orderId, (order) => ({
        ...order,
        tracking: [
          ...order.tracking,
          { id: `t-${Date.now()}`, ts: event.ts ?? new Date().toISOString(), ...event },
        ],
      }));
    },
    [patchOrder],
  );

  const markShipped = useCallback(
    (orderId: string, trackingNumber: string, courier: string) => {
      const now = new Date().toISOString();
      patchOrder(orderId, (order) => ({
        ...order,
        buyerStatus: "spedito",
        sellerStatus: "spedito",
        shippedAt: now,
        trackingNumber,
        courier,
        tracking: [
          ...order.tracking,
          {
            id: `t-${Date.now()}`,
            ts: now,
            titolo: "Spedito",
            descrizione: `${courier} — ${trackingNumber}`,
            tipo: "spedizione",
          },
        ],
      }));
      pushNotifica({
        categoria: "sistema",
        testo: `Ordine ${orderId} spedito (${trackingNumber})`,
        tempo: "ora",
      });
    },
    [patchOrder, pushNotifica],
  );

  const markDelivered = useCallback(
    (orderId: string) => {
      const now = new Date().toISOString();
      patchOrder(orderId, (order) => ({
        ...order,
        buyerStatus: "consegnato",
        sellerStatus: "consegnato",
        deliveredAt: now,
        tracking: [
          ...order.tracking,
          { id: `t-${Date.now()}`, ts: now, titolo: "Consegnato", tipo: "consegna" },
        ],
      }));
      pushNotifica({
        categoria: "sistema",
        testo: `Ordine ${orderId} consegnato`,
        tempo: "ora",
      });
    },
    [patchOrder, pushNotifica],
  );

  const confirmOk = useCallback(
    (orderId: string) => {
      const now = new Date().toISOString();
      patchOrder(orderId, (order) => ({
        ...order,
        buyerStatus: "completato",
        sellerStatus: "completato",
        completedAt: now,
        tracking: [
          ...order.tracking,
          {
            id: `t-${Date.now()}`,
            ts: now,
            titolo: "Ordine completato dall'acquirente",
            tipo: "sistema",
          },
        ],
      }));
      toast.success("Grazie! Ordine confermato.");
      pushNotifica({
        categoria: "sistema",
        testo: `Ordine ${orderId} completato`,
        tempo: "ora",
      });
    },
    [patchOrder, pushNotifica],
  );

  const openDispute = useCallback(
    (orderId: string, dispute: { motivo: string; descrizione: string; foto: string[] }) => {
      const now = new Date().toISOString();
      patchOrder(orderId, (order) => ({
        ...order,
        buyerStatus: "contestato",
        sellerStatus: "contestato",
        dispute: { ...dispute, stato: "aperta", aperturaTs: now },
        tracking: [
          ...order.tracking,
          {
            id: `t-${Date.now()}`,
            ts: now,
            titolo: "Contestazione aperta",
            descrizione: dispute.motivo,
            tipo: "problema",
          },
        ],
      }));
      pushNotifica({
        categoria: "sistema",
        testo: `Contestazione aperta per ${orderId}`,
        tempo: "ora",
      });
    },
    [patchOrder, pushNotifica],
  );

  const resolveDispute = useCallback(
    (orderId: string, esito: "rimborsata" | "risolta" | "respinta", nota?: string) => {
      const now = new Date().toISOString();
      patchOrder(orderId, (order) => ({
        ...order,
        buyerStatus:
          esito === "rimborsata"
            ? "rimborsato"
            : esito === "respinta"
              ? "consegnato"
              : "completato",
        sellerStatus: esito === "rimborsata" ? "rimborsato" : "completato",
        dispute: order.dispute
          ? { ...order.dispute, stato: esito, chiusuraTs: now, esito: nota }
          : order.dispute,
        tracking: [
          ...order.tracking,
          {
            id: `t-${Date.now()}`,
            ts: now,
            titolo: `Contestazione ${esito}`,
            descrizione: nota,
            tipo: "sistema",
          },
        ],
      }));
      pushNotifica({
        categoria: "sistema",
        testo: `Contestazione ${esito} per ${orderId}`,
        tempo: "ora",
      });
    },
    [patchOrder, pushNotifica],
  );

  const submitReview = useCallback(
    (orderId: string, review: OrderReview) => {
      patchOrder(orderId, (order) => ({ ...order, review }));
      toast.success("Recensione pubblicata");
    },
    [patchOrder],
  );

  const createProposal = useCallback(
    (wineId: string, prezzoProposto: number): Proposal | null => {
      const wine = wines.find((candidate) => candidate.id === wineId);
      if (!wine) return null;
      const activeProposal = proposals.find(
        (proposal) =>
          proposal.wineId === wineId &&
          (proposal.stato === "inviata" || proposal.stato === "controproposta"),
      );
      if (activeProposal) {
        toast("Hai già una proposta attiva per questa bottiglia");
        return activeProposal;
      }

      const now = new Date();
      const proposal: Proposal = {
        id: `PRP-2026-${String(1000 + Math.floor(Math.random() * 8999)).slice(-4)}`,
        wineId,
        prezzoRichiesto: wine.prezzo,
        prezzoProposto,
        stato: "inviata",
        createdAt: now.toISOString(),
        scadenza: new Date(now.getTime() + 7 * 24 * 3600 * 1000).toISOString(),
        buyer: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68" },
        seller: { nome: wine.venditore.nome, avatar: wine.venditore.avatar },
      };
      setProposals((current) => [proposal, ...current]);
      recordProposalPrice(wineId, prezzoProposto);
      pushNotifica({
        categoria: "marketplace",
        testo: `Proposta inviata per ${wine.nome} ${wine.annata}: € ${prezzoProposto.toLocaleString("it-IT")}`,
        tempo: "ora",
      });
      toast.success(`Proposta inviata: € ${prezzoProposto.toLocaleString("it-IT")}`);
      return proposal;
    },
    [proposals, pushNotifica, recordProposalPrice],
  );

  const sellerCounter = useCallback(
    (proposalId: string, controProposta: number) => {
      setProposals((current) =>
        current.map((proposal) =>
          proposal.id === proposalId
            ? { ...proposal, stato: "controproposta", controProposta }
            : proposal,
        ),
      );
      pushNotifica({
        categoria: "marketplace",
        testo: `Il venditore ha inviato una controproposta di € ${controProposta.toLocaleString("it-IT")}`,
        tempo: "ora",
      });
    },
    [pushNotifica],
  );

  const acceptProposal = useCallback(
    (proposalId: string) => {
      setProposals((current) =>
        current.map((proposal) =>
          proposal.id === proposalId ? { ...proposal, stato: "accettata" } : proposal,
        ),
      );
      pushNotifica({
        categoria: "marketplace",
        testo: "Proposta accettata: procedi con l'acquisto",
        tempo: "ora",
      });
      toast.success("Proposta accettata. Procedi con il checkout.");
    },
    [pushNotifica],
  );

  const rejectProposal = useCallback(
    (proposalId: string) => {
      setProposals((current) =>
        current.map((proposal) =>
          proposal.id === proposalId ? { ...proposal, stato: "rifiutata" } : proposal,
        ),
      );
      pushNotifica({
        categoria: "marketplace",
        testo: "Proposta rifiutata",
        tempo: "ora",
      });
    },
    [pushNotifica],
  );

  return {
    orders,
    sales,
    proposals,
    getOrder,
    createOrder,
    advanceOrder,
    updateSellerOrder,
    addTracking,
    markShipped,
    markDelivered,
    confirmOk,
    openDispute,
    resolveDispute,
    submitReview,
    createProposal,
    sellerCounter,
    acceptProposal,
    rejectProposal,
  };
}
