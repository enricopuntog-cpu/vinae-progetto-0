import { createContext, useContext, useState, useCallback, useMemo, type ReactNode } from "react";
import { toast } from "sonner";
import { notificheComplete, type Notifica } from "@/data/extra";
import { communitySeguiteIniziali } from "@/data/communities";
import { type CellarBottle, type StorageEnvironment, type StorageModule } from "@/data/cellar";
import {
  type Order,
  type Proposal,
  type BuyerOrderStatus,
  type SellerOrderStatus,
  type DeliveryMode,
  type TrackingEvent,
  type Dispute,
  type OrderReview,
} from "@/data/orders";
import { wines } from "@/data/wines";
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
import {
  reportsSeed,
  listingStatusSeed,
  auditSeed,
  priorityFromReason,
  MY_REPORTER,
  type Report,
  type ReportStatus,
  type ReportTargetType,
  type ListingStatus,
  type ModAction,
  type AuditEntry,
} from "@/data/moderation";
import { useOrderDomain } from "@/lib/store/order-domain";
import { useCellarDomain, type DrinkOverride, type SfondoCantina } from "@/lib/store/cellar-domain";

export type { DrinkOverride, SfondoCantina } from "@/lib/store/cellar-domain";

export type DemoRuolo = "guest" | "user" | "admin";

type StoreState = {
  favorites: Set<string>;
  follows: Set<string>;
  proposte: Record<string, number>;
  toggleFavorite: (id: string) => void;
  toggleFollow: (nome: string) => void;
  proponi: (wineId: string, prezzo: number) => void;

  ruolo: DemoRuolo;
  setRuolo: (r: DemoRuolo) => void;

  notifiche: Notifica[];
  nonLette: number;
  segnaLetta: (id: string) => void;
  segnaTutteLette: () => void;

  communityFollows: Set<string>;
  toggleCommunityFollow: (slug: string) => void;

  regionePref: string;
  tipologiaPref: string;
  setPreferenze: (r: string, t: string) => void;
  sfondoCantina: SfondoCantina;
  setSfondoCantina: (s: SfondoCantina) => void;
  inVendita: Set<string>;
  toggleInVendita: (id: string) => void;
  prezzoNascosto: Set<string>;
  togglePrezzoNascosto: (id: string) => void;

  // Cellar 3D
  bottiglieCantina: CellarBottle[];
  ambienti: StorageEnvironment[];
  moduli: StorageModule[];
  drinkWindowOverrides: Record<string, DrinkOverride>;
  setDrinkWindowOverride: (wineId: string, o: DrinkOverride) => void;
  openBottle: (bottleId: string, nota?: string) => void;
  scheduleOpen: (bottleId: string, date: string) => void;
  moveBottle: (bottleId: string, newSlotId: string) => void;
  addEnvironment: (env: StorageEnvironment, mods: StorageModule[]) => void;
  reduceMotion: boolean;
  setReduceMotion: (b: boolean) => void;

  // Orders & proposals
  orders: Order[];
  sales: Order[];
  proposals: Proposal[];
  getOrder: (id: string) => Order | undefined;
  createOrder: (input: {
    wineId: string;
    quantita: number;
    deliveryMode: DeliveryMode;
    metodoPagamento: "carta_demo" | "paypal_demo" | "bonifico_demo";
    proposalId?: string;
    prezzoUnitario?: number;
  }) => Promise<Order>;
  advanceOrder: (orderId: string, target: BuyerOrderStatus, side?: "buyer" | "sales") => void;
  updateSellerOrder: (orderId: string, patch: Partial<Order>) => void;
  addTracking: (
    orderId: string,
    ev: Omit<TrackingEvent, "id" | "ts"> & { ts?: string },
    side?: "buyer" | "sales",
  ) => void;
  markShipped: (orderId: string, trackingNumber: string, courier: string) => void;
  markDelivered: (orderId: string, side?: "buyer" | "sales") => void;
  confirmOk: (orderId: string) => void;
  openDispute: (
    orderId: string,
    d: { motivo: string; descrizione: string; foto: string[] },
  ) => void;
  resolveDispute: (
    orderId: string,
    esito: "rimborsata" | "risolta" | "respinta",
    nota?: string,
  ) => void;
  submitReview: (orderId: string, r: OrderReview) => void;

  // Proposte v2 (state machine)
  createProposal: (wineId: string, prezzoProposto: number) => Proposal | null;
  sellerCounter: (proposalId: string, controProposta: number) => void;
  acceptProposal: (proposalId: string) => void;
  rejectProposal: (proposalId: string) => void;

  pushNotifica: (n: Omit<Notifica, "id" | "letta">) => void;

  // Onboarding & verifica
  registrato: boolean;
  emailStatus: EmailStatus;
  ageStatus: AgeStatus;
  identityStatus: IdentityStatus;
  sellerStatus: SellerStatus;
  obiettivi: Set<Obiettivo>;
  regioniPreferite: Set<string>;
  tipologiePreferite: Set<string>;
  fasciaPrezzo: string | null;
  clubSuggeritiSalvati: boolean;
  preferenzeSalvate: boolean;
  profiloBase: boolean;
  profilo: ProfiloUtente;
  registerAccount: (p: {
    username: string;
    email: string;
    dob: string;
    maggiorenne: boolean;
  }) => void;
  verifyEmail: () => void;
  toggleObiettivo: (o: Obiettivo) => void;
  saveObiettivi: () => void;
  toggleRegionePref: (r: string) => void;
  toggleTipologiaPref: (t: string) => void;
  setFasciaPrezzo: (id: string) => void;
  savePreferenze: () => void;
  saveProfilo: (p: Partial<ProfiloUtente>) => void;
  startIdentityVerification: () => void;
  completeIdentityVerification: (esito: "verificata" | "rifiutata") => void;
  resetOnboarding: () => void;
  profileCompletion: { perc: number; items: { label: string; done: boolean; to?: string }[] };

  // Moderation
  reports: Report[];
  listingStatus: Record<string, ListingStatus>;
  auditLog: AuditEntry[];
  modScope: "piattaforma" | { club: string };
  setModScope: (s: "piattaforma" | { club: string }) => void;
  submitReport: (input: {
    targetType: ReportTargetType;
    targetId: string;
    targetLabel: string;
    reason: string;
    descrizione: string;
    foto: string[];
    clubSlug?: string;
  }) => void;
  updateReportStatus: (id: string, stato: ReportStatus, nota?: string) => void;
  assignReport: (id: string, assignee: string) => void;
  addReportNote: (id: string, testo: string) => void;
  setListingStatus: (wineId: string, s: ListingStatus) => void;
  applyModAction: (input: {
    action: ModAction;
    target: string;
    motivazione: string;
    durata?: string;
    scope?: "piattaforma" | "club";
    clubSlug?: string;
    reportId?: string;
  }) => void;
  richiediAltreFoto: (wineId: string, sellerName: string) => void;
};

const Ctx = createContext<StoreState | null>(null);

export function VineaProvider({ children }: { children: ReactNode }) {
  const [favorites, setFavorites] = useState<Set<string>>(new Set(["sassicaia-2018"]));
  const [follows, setFollows] = useState<Set<string>>(new Set(["Marco B."]));
  const [proposte, setProposte] = useState<Record<string, number>>({});
  const [ruolo, setRuolo] = useState<DemoRuolo>("user");
  const [notifiche, setNotifiche] = useState<Notifica[]>(notificheComplete);
  const [communityFollows, setCommunityFollows] = useState<Set<string>>(
    new Set(communitySeguiteIniziali),
  );
  const cellarDomain = useCellarDomain();

  const toggleFavorite = useCallback((id: string) => {
    setFavorites((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
        toast("Rimosso dai preferiti");
      } else {
        next.add(id);
        toast.success("Aggiunto ai preferiti");
      }
      return next;
    });
  }, []);

  const toggleFollow = useCallback((nome: string) => {
    setFollows((prev) => {
      const next = new Set(prev);
      if (next.has(nome)) {
        next.delete(nome);
        toast(`Non segui più ${nome}`);
      } else {
        next.add(nome);
        toast.success(`Ora segui ${nome}`);
      }
      return next;
    });
  }, []);

  const proponi = useCallback((wineId: string, prezzo: number) => {
    setProposte((p) => ({ ...p, [wineId]: prezzo }));
    toast.success(`Proposta inviata: € ${prezzo.toLocaleString("it-IT")}`);
  }, []);

  const segnaLetta = useCallback((id: string) => {
    setNotifiche((prev) => prev.map((n) => (n.id === id ? { ...n, letta: true } : n)));
  }, []);
  const segnaTutteLette = useCallback(() => {
    setNotifiche((prev) => prev.map((n) => ({ ...n, letta: true })));
    toast.success("Tutte le notifiche sono state lette");
  }, []);

  const toggleCommunityFollow = useCallback((slug: string) => {
    setCommunityFollows((prev) => {
      const n = new Set(prev);
      if (n.has(slug)) {
        n.delete(slug);
        toast("Non segui più il club");
      } else {
        n.add(slug);
        toast.success("Segui il club");
      }
      return n;
    });
  }, []);

  const pushNotifica = useCallback((n: Omit<Notifica, "id" | "letta">) => {
    setNotifiche((prev) => [
      { id: `n-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, letta: false, ...n },
      ...prev,
    ]);
  }, []);

  const recordProposalPrice = useCallback((wineId: string, price: number) => {
    setProposte((current) => ({ ...current, [wineId]: price }));
  }, []);

  const orderDomain = useOrderDomain({ pushNotifica, recordProposalPrice });

  const nonLette = useMemo(() => notifiche.filter((n) => !n.letta).length, [notifiche]);

  // ============== Onboarding & verifica ==============
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

  // Se l'utente entra come "guest", azzeriamo l'onboarding
  const setRuoloWithReset = useCallback((r: DemoRuolo) => {
    setRuolo(r);
    if (r === "guest") {
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
    }
  }, []);

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

  // ============== Moderation ==============
  const [reports, setReports] = useState<Report[]>(reportsSeed);
  const [listingStatus, setListingStatusState] =
    useState<Record<string, ListingStatus>>(listingStatusSeed);
  const [auditLog, setAuditLog] = useState<AuditEntry[]>(auditSeed);
  const [modScope, setModScope] = useState<"piattaforma" | { club: string }>("piattaforma");

  const submitReport = useCallback(
    (input: {
      targetType: ReportTargetType;
      targetId: string;
      targetLabel: string;
      reason: string;
      descrizione: string;
      foto: string[];
      clubSlug?: string;
    }) => {
      const now = new Date().toISOString();
      const r: Report = {
        id: `SEG-2026-${String(300 + Math.floor(Math.random() * 699)).slice(-4)}`,
        targetType: input.targetType,
        targetId: input.targetId,
        targetLabel: input.targetLabel,
        reason: input.reason,
        descrizione: input.descrizione,
        foto: input.foto,
        stato: "inviata",
        priorita: priorityFromReason(input.reason),
        reporter: MY_REPORTER,
        clubSlug: input.clubSlug,
        createdAt: now,
        updatedAt: now,
        storia: [{ ts: now, testo: "Segnalazione ricevuta", autore: "Sistema" }],
        noteInterne: [],
      };
      setReports((prev) => [r, ...prev]);
      pushNotifica({
        categoria: "sistema",
        testo: `Segnalazione ${r.id} inviata. La stiamo esaminando.`,
        tempo: "ora",
      });
      toast.success("Segnalazione inviata (demo)");
    },
    [pushNotifica],
  );

  const updateReportStatus = useCallback(
    (id: string, stato: ReportStatus, nota?: string) => {
      const now = new Date().toISOString();
      setReports((prev) =>
        prev.map((r) =>
          r.id === id
            ? {
                ...r,
                stato,
                updatedAt: now,
                storia: [
                  ...r.storia,
                  { ts: now, testo: nota ?? `Stato aggiornato: ${stato}`, autore: "Moderazione" },
                ],
              }
            : r,
        ),
      );
      pushNotifica({
        categoria: "sistema",
        testo: `Segnalazione ${id}: ${stato.replace("_", " ")}`,
        tempo: "ora",
      });
    },
    [pushNotifica],
  );

  const assignReport = useCallback((id: string, assignee: string) => {
    const now = new Date().toISOString();
    setReports((prev) =>
      prev.map((r) =>
        r.id === id
          ? {
              ...r,
              assignee,
              updatedAt: now,
              storia: [
                ...r.storia,
                { ts: now, testo: `Assegnata a ${assignee}`, autore: "Sistema" },
              ],
            }
          : r,
      ),
    );
  }, []);

  const addReportNote = useCallback((id: string, testo: string) => {
    const now = new Date().toISOString();
    setReports((prev) =>
      prev.map((r) =>
        r.id === id
          ? {
              ...r,
              updatedAt: now,
              noteInterne: [...r.noteInterne, { ts: now, testo, autore: "Moderazione" }],
            }
          : r,
      ),
    );
  }, []);

  const setListingStatus = useCallback((wineId: string, s: ListingStatus) => {
    setListingStatusState((prev) => ({ ...prev, [wineId]: s }));
    toast.success(`Stato annuncio: ${s.replace("_", " ")}`);
  }, []);

  const applyModAction = useCallback(
    (input: {
      action: ModAction;
      target: string;
      motivazione: string;
      durata?: string;
      scope?: "piattaforma" | "club";
      clubSlug?: string;
      reportId?: string;
    }) => {
      const now = new Date().toISOString();
      const entry: AuditEntry = {
        id: `au-${Date.now()}`,
        ts: now,
        attore: input.scope === "club" ? "Mod. Club" : "Mod. Vinea",
        scope: input.scope ?? "piattaforma",
        clubSlug: input.clubSlug,
        azione: input.action,
        target: input.target,
        motivazione: input.motivazione,
        durata: input.durata,
        ricorso: "nessuno",
      };
      setAuditLog((prev) => [entry, ...prev]);
      if (input.reportId) {
        const nextStato: ReportStatus =
          input.action === "info_richieste"
            ? "info_richieste"
            : input.action === "chiusura"
              ? "risolta"
              : input.action === "ripristino"
                ? "respinta"
                : "risolta";
        setReports((prev) =>
          prev.map((r) =>
            r.id === input.reportId
              ? {
                  ...r,
                  stato: nextStato,
                  updatedAt: now,
                  storia: [
                    ...r.storia,
                    {
                      ts: now,
                      autore: entry.attore,
                      testo: `${input.action.replace("_", " ")}${input.durata ? ` (${input.durata})` : ""} — ${input.motivazione}`,
                    },
                  ],
                }
              : r,
          ),
        );
      }
      toast.success("Azione registrata (demo)");
    },
    [],
  );

  const richiediAltreFoto = useCallback(
    (wineId: string, sellerName: string) => {
      const wine = wines.find((w) => w.id === wineId);
      const label = wine ? `${wine.nome} ${wine.annata}` : wineId;
      pushNotifica({
        categoria: "marketplace",
        testo: `Hai chiesto altre foto a ${sellerName} per ${label}`,
        tempo: "ora",
      });
      toast.success(`Richiesta inviata a ${sellerName} in chat`);
    },
    [pushNotifica],
  );

  return (
    <Ctx.Provider
      value={{
        favorites,
        follows,
        proposte,
        toggleFavorite,
        toggleFollow,
        proponi,
        ruolo,
        setRuolo: setRuoloWithReset,
        notifiche,
        nonLette,
        segnaLetta,
        segnaTutteLette,
        communityFollows,
        toggleCommunityFollow,
        ...cellarDomain,
        ...orderDomain,
        pushNotifica,
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
        profileCompletion,
        reports,
        listingStatus,
        auditLog,
        modScope,
        setModScope,
        submitReport,
        updateReportStatus,
        assignReport,
        addReportNote,
        setListingStatus,
        applyModAction,
        richiediAltreFoto,
      }}
    >
      {children}
    </Ctx.Provider>
  );
}

export function useVinea() {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useVinea deve stare dentro VineaProvider");
  return ctx;
}

export { formatEUR } from "@/lib/format";
