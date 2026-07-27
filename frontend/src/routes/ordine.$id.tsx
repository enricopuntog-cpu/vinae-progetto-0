import { createFileRoute, Link, notFound, useRouter } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import {
  ArrowLeft,
  Truck,
  Package,
  ShieldCheck,
  CheckCircle2,
  Star,
  AlertTriangle,
  Camera,
  ClipboardCheck,
  Printer,
  MapPin,
  MessageCircle,
  Clock,
  XCircle,
  Info,
} from "lucide-react";
import { wines } from "@/data/wines";
import {
  colorBuyerStatus,
  labelBuyerStatus,
  labelSellerStatus,
  type OrderReview,
  type TrackingEvent,
} from "@/data/orders";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { wineImg } from "@/lib/wine-images";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";

export const Route = createFileRoute("/ordine/$id")({
  head: ({ params }) => ({
    meta: [
      { title: `Ordine ${params.id} — Vinea` },
      { name: "description", content: "Dettaglio ordine dimostrativo Vinea Wine Club." },
      { property: "og:title", content: `Ordine ${params.id} — Vinea` },
      {
        property: "og:description",
        content: "Timeline, spedizione, protezione e stato dell'ordine.",
      },
      { name: "robots", content: "noindex" },
    ],
  }),
  notFoundComponent: () => (
    <div className="grid place-items-center py-24 text-center">
      <p className="font-serif text-3xl">Ordine non trovato</p>
      <Link to="/acquisti" className="mt-4 text-bordeaux underline">
        Vai ai tuoi acquisti
      </Link>
    </div>
  ),
  component: Dettaglio,
});

function Dettaglio() {
  const { id } = Route.useParams();
  const router = useRouter();
  const { getOrder, sales } = useVinea();
  const order = getOrder(id);
  if (!order) throw notFound();

  const wine = wines.find((w) => w.id === order.wineId);
  const isSeller = sales.some((s) => s.id === order.id);

  return (
    <div className="space-y-6">
      <button
        onClick={() => router.history.back()}
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
      >
        <ArrowLeft className="h-4 w-4" /> Indietro
      </button>

      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-4 sm:flex sm:flex-wrap sm:items-center sm:justify-between">
        <div className="min-w-0">
          <p className="text-xs uppercase tracking-wide text-muted-foreground">
            Ordine · {isSeller ? "Vendita" : "Acquisto"}
          </p>
          <h1 className="truncate font-serif text-2xl sm:text-3xl">{order.id}</h1>
          <p className="mt-1 text-xs text-muted-foreground">
            Creato il {new Date(order.createdAt).toLocaleDateString("it-IT")}
          </p>
        </div>
        <div className="flex flex-col items-end gap-2">
          <span
            className={`rounded-full px-3 py-1 text-xs font-semibold ${colorBuyerStatus(order.buyerStatus)}`}
          >
            {isSeller ? labelSellerStatus(order.sellerStatus) : labelBuyerStatus(order.buyerStatus)}
          </span>
          <span className="inline-flex items-center gap-1 rounded-full bg-oro/15 px-2 py-0.5 text-[10px] font-medium text-oro">
            Demo — nessun processo reale
          </span>
        </div>
      </header>

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="space-y-6">
          {/* Bottiglia */}
          {wine && (
            <section className="flex gap-4 rounded-2xl border border-border bg-card p-4">
              <img
                src={wine.immagini[0]}
                alt=""
                className="h-24 w-20 shrink-0 rounded object-cover"
              />
              <div className="min-w-0 flex-1">
                <Link
                  to="/annuncio/$id"
                  params={{ id: wine.id }}
                  className="truncate font-serif text-lg font-semibold hover:text-bordeaux"
                >
                  {wine.nome} {wine.annata}
                </Link>
                <p className="truncate text-sm text-muted-foreground">
                  {wine.produttore} • {wine.formato}
                </p>
                <p className="mt-1 text-xs">
                  Quantità: <b>{order.quantita}</b> · {formatEUR(order.prezzoUnitario)} cad.
                </p>
              </div>
            </section>
          )}

          {/* Timeline tracking */}
          <section className="rounded-2xl border border-border bg-card p-4">
            <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Tracking</p>
              {order.trackingNumber && (
                <p className="text-xs text-muted-foreground">
                  {order.courier} · <b className="text-antracite">{order.trackingNumber}</b>
                </p>
              )}
            </div>
            <Timeline events={order.tracking} />
          </section>

          {/* Sezione seller: prepara spedizione */}
          {isSeller && ["nuovo", "da_preparare", "da_spedire"].includes(order.sellerStatus) && (
            <SellerPrepPanel orderId={order.id} />
          )}

          {/* Buyer: dopo consegna → conferma/segnala problema */}
          {!isSeller && order.buyerStatus === "consegnato" && !order.dispute && (
            <BuyerConfirmPanel orderId={order.id} />
          )}

          {/* Dispute panel */}
          {order.dispute && <DisputePanel orderId={order.id} isSeller={isSeller} />}

          {/* Review — solo buyer, ordine completato */}
          {!isSeller && order.buyerStatus === "completato" && (
            <ReviewPanel orderId={order.id} existing={order.review} />
          )}
        </div>

        {/* Sidebar riepilogo */}
        <aside className="space-y-4 lg:sticky lg:top-24 lg:self-start">
          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
              Riepilogo pagamento
            </p>
            <div className="space-y-1.5 text-sm">
              <Row
                label={`Bottiglie × ${order.quantita}`}
                value={formatEUR(order.prezzoUnitario * order.quantita)}
              />
              <Row
                label="Spedizione"
                value={order.spedizione === 0 ? "Gratis" : formatEUR(order.spedizione)}
              />
              <Row label="Protezione" value={formatEUR(order.protezione)} />
              <div className="my-2 h-px bg-border" />
              <Row label="Totale" value={formatEUR(order.totale)} bold />
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              Pagato con {order.cartaMascherata} · Demo
            </p>
          </section>

          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Consegna</p>
            <p className="text-sm font-semibold">
              {order.deliveryMode === "spedizione" ? "Spedizione con corriere" : "Consegna a mano"}
            </p>
            <p className="mt-2 flex items-start gap-2 text-xs text-muted-foreground">
              <MapPin className="mt-0.5 h-3 w-3" /> {order.indirizzo.nome}, {order.indirizzo.via},{" "}
              {order.indirizzo.cap} {order.indirizzo.citta} ({order.indirizzo.provincia})
            </p>
          </section>

          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
              {isSeller ? "Acquirente" : "Venditore"}
            </p>
            <div className="flex items-center gap-3">
              <img
                src={isSeller ? order.buyer.avatar : order.seller.avatar}
                alt=""
                className="h-10 w-10 rounded-full object-cover"
              />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1 truncate text-sm font-semibold">
                  {isSeller ? order.buyer.nome : order.seller.nome}
                  {!isSeller && order.seller.verificato && (
                    <ShieldCheck className="h-3.5 w-3.5 text-salvia" />
                  )}
                </p>
              </div>
              <Button asChild size="sm" variant="outline">
                <Link to="/messaggi">
                  <MessageCircle className="h-3.5 w-3.5" /> Messaggio
                </Link>
              </Button>
            </div>
          </section>

          <div className="rounded-2xl border border-oro/40 bg-oro/10 p-3 text-xs">
            <p className="flex items-center gap-1 font-semibold text-oro">
              <ShieldCheck className="h-3.5 w-3.5" /> Protezione acquisti Vinea
            </p>
            <p className="mt-1 text-antracite/80">
              Copre autenticità, integrità e trasporto. In caso di problema puoi aprire una
              contestazione entro il periodo di verifica.
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}

function Row({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div
      className={`flex items-baseline justify-between gap-2 ${bold ? "font-serif text-lg" : ""}`}
    >
      <span className="text-antracite">{label}</span>
      <span className={`font-medium ${bold ? "text-bordeaux" : ""}`}>{value}</span>
    </div>
  );
}

function Timeline({ events }: { events: TrackingEvent[] }) {
  if (events.length === 0) {
    return <p className="text-sm text-muted-foreground">Nessun evento ancora registrato.</p>;
  }
  return (
    <ol className="relative ml-2 space-y-4 border-l border-border pl-5">
      {events.map((e) => (
        <li key={e.id} className="relative">
          <span
            className={`absolute -left-[26px] top-1 grid h-4 w-4 place-items-center rounded-full ${iconBg(e.tipo)}`}
          >
            {iconFor(e.tipo)}
          </span>
          <p className="text-sm font-semibold">{e.titolo}</p>
          {e.descrizione && <p className="text-xs text-muted-foreground">{e.descrizione}</p>}
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {new Date(e.ts).toLocaleString("it-IT", {
              day: "2-digit",
              month: "short",
              hour: "2-digit",
              minute: "2-digit",
            })}
            {e.luogo ? ` · ${e.luogo}` : ""}
          </p>
        </li>
      ))}
    </ol>
  );
}

function iconBg(t: TrackingEvent["tipo"]): string {
  switch (t) {
    case "spedizione":
      return "bg-blue-500/15 text-blue-700";
    case "consegna":
      return "bg-salvia/20 text-salvia";
    case "problema":
      return "bg-red-500/15 text-red-700";
    case "sistema":
      return "bg-bordeaux/10 text-bordeaux";
    default:
      return "bg-secondary text-antracite";
  }
}
function iconFor(t: TrackingEvent["tipo"]) {
  switch (t) {
    case "spedizione":
      return <Truck className="h-2.5 w-2.5" />;
    case "consegna":
      return <CheckCircle2 className="h-2.5 w-2.5" />;
    case "problema":
      return <AlertTriangle className="h-2.5 w-2.5" />;
    case "sistema":
      return <Info className="h-2.5 w-2.5" />;
    default:
      return <Clock className="h-2.5 w-2.5" />;
  }
}

/* ============ Seller: prepara spedizione ============ */

function SellerPrepPanel({ orderId }: { orderId: string }) {
  const { getOrder, updateSellerOrder, markShipped } = useVinea();
  const order = getOrder(orderId)!;
  type Packaging = "scatola_singola" | "scatola_polistirolo" | "cassa_legno";
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

  function generaLabel() {
    setLoading(true);
    setTimeout(() => {
      const t = `VNA-${Math.floor(1000 + Math.random() * 8999)}-${Math.floor(100 + Math.random() * 899)}`;
      setTracking(t);
      setLabelGenerated(true);
      setLoading(false);
      updateSellerOrder(orderId, { sellerStatus: "da_spedire", buyerStatus: "in_preparazione" });
      toast.success("Etichetta di spedizione simulata generata");
    }, 900);
  }

  function conferma() {
    setLoading(true);
    setTimeout(() => {
      markShipped(orderId, tracking, courier);
      setLoading(false);
    }, 700);
  }

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <div className="mb-3 flex items-center justify-between gap-2">
        <p className="text-sm font-semibold">Prepara spedizione</p>
        <span className="rounded-full bg-oro/15 px-2 py-0.5 text-[10px] font-medium text-oro">
          Demo
        </span>
      </div>

      <div className="space-y-4">
        <div>
          <Label className="text-xs uppercase">Imballaggio</Label>
          <RadioGroup
            value={imballaggio}
            onValueChange={(value) => {
              if (
                value === "scatola_singola" ||
                value === "scatola_polistirolo" ||
                value === "cassa_legno"
              ) {
                setImballaggio(value);
              }
            }}
            className="mt-2 grid gap-2 sm:grid-cols-3"
          >
            {[
              { v: "scatola_singola", l: "Scatola singola" },
              { v: "scatola_polistirolo", l: "Scatola + polistirolo" },
              { v: "cassa_legno", l: "Cassa di legno" },
            ].map((o) => (
              <label
                key={o.v}
                className={`flex cursor-pointer items-center gap-2 rounded-xl border p-2 text-sm ${imballaggio === o.v ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
              >
                <RadioGroupItem value={o.v} />
                <Package className="h-4 w-4 text-bordeaux" />
                <span className="truncate">{o.l}</span>
              </label>
            ))}
          </RadioGroup>
        </div>

        <div>
          <Label className="text-xs uppercase">Checklist fotografica</Label>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {[
              { k: "foto_frontale", l: "Foto etichetta frontale" },
              { k: "foto_capsula", l: "Foto capsula e collo" },
              { k: "foto_livello", l: "Foto livello del vino" },
              { k: "foto_imballaggio", l: "Foto imballaggio finale" },
            ].map((c) => (
              <label
                key={c.k}
                className="flex items-center gap-2 rounded-xl border border-border bg-secondary/40 p-2 text-sm"
              >
                <Checkbox
                  checked={checks[c.k]}
                  onCheckedChange={(v) => setChecks((s) => ({ ...s, [c.k]: !!v }))}
                />
                <Camera className="h-4 w-4 text-muted-foreground" />
                <span className="min-w-0 flex-1 truncate">{c.l}</span>
                {checks[c.k] && (
                  <span className="rounded-full bg-salvia/15 px-2 py-0.5 text-[10px] text-salvia">
                    ok
                  </span>
                )}
              </label>
            ))}
          </div>
        </div>

        <div className="grid gap-2 sm:grid-cols-[1fr_1fr_auto]">
          <div>
            <Label className="text-xs uppercase">Corriere</Label>
            <Select value={courier} onValueChange={setCourier}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="Corriere Vinea">Corriere Vinea</SelectItem>
                <SelectItem value="BRT">BRT</SelectItem>
                <SelectItem value="DHL">DHL</SelectItem>
                <SelectItem value="GLS">GLS</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label className="text-xs uppercase">Numero tracking</Label>
            <Input
              value={tracking}
              onChange={(e) => setTracking(e.target.value)}
              placeholder="Genera etichetta o inserisci"
            />
          </div>
          <div className="sm:self-end">
            <Button
              variant="outline"
              onClick={generaLabel}
              disabled={!allDone || loading}
              className="w-full"
            >
              <Printer className="h-4 w-4" />{" "}
              {labelGenerated ? "Rigenera etichetta" : "Genera etichetta"}
            </Button>
          </div>
        </div>

        {!allDone && (
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <ClipboardCheck className="h-3.5 w-3.5" /> Completa la checklist per generare
            l'etichetta.
          </p>
        )}

        <Button
          onClick={conferma}
          disabled={!canShip || loading}
          className="w-full bg-bordeaux hover:bg-bordeaux/90"
        >
          {loading ? "Elaborazione…" : "Segna come spedito"}
        </Button>
      </div>
    </section>
  );
}

/* ============ Buyer: dopo consegna ============ */

function BuyerConfirmPanel({ orderId }: { orderId: string }) {
  const { confirmOk, openDispute } = useVinea();
  const [openDispDlg, setOpenDispDlg] = useState(false);
  const [motivo, setMotivo] = useState("Bottiglia non conforme");
  const [descr, setDescr] = useState("");
  const [foto, setFoto] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadingConfirm, setLoadingConfirm] = useState(false);

  function simulaCarica() {
    setFoto((prev) => [...prev, wineImg(`disp-${prev.length}-${Date.now()}`)]);
  }

  return (
    <section className="rounded-2xl border border-salvia/40 bg-salvia/5 p-4">
      <p className="text-sm font-semibold">Hai ricevuto l'ordine?</p>
      <p className="mt-1 text-xs text-muted-foreground">
        Durante il periodo di verifica puoi confermare o segnalare un problema.
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <Button
          className="bg-bordeaux hover:bg-bordeaux/90"
          disabled={loadingConfirm}
          onClick={() => {
            setLoadingConfirm(true);
            setTimeout(() => {
              confirmOk(orderId);
              setLoadingConfirm(false);
            }, 700);
          }}
        >
          <CheckCircle2 className="h-4 w-4" />{" "}
          {loadingConfirm ? "Conferma in corso…" : "Conferma che è tutto corretto"}
        </Button>
        <Dialog open={openDispDlg} onOpenChange={setOpenDispDlg}>
          <DialogTrigger asChild>
            <Button variant="outline">
              <AlertTriangle className="h-4 w-4" /> Segnala un problema
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-lg">
            <DialogHeader>
              <DialogTitle className="font-serif text-2xl">Apri contestazione</DialogTitle>
            </DialogHeader>
            <div className="space-y-3">
              <div>
                <Label className="text-xs">Motivo</Label>
                <Select value={motivo} onValueChange={setMotivo}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Bottiglia non conforme">
                      Bottiglia non conforme alla descrizione
                    </SelectItem>
                    <SelectItem value="Bottiglia danneggiata">
                      Bottiglia danneggiata nel trasporto
                    </SelectItem>
                    <SelectItem value="Livello alterato">Livello del vino non corretto</SelectItem>
                    <SelectItem value="Sospetta contraffazione">Sospetta contraffazione</SelectItem>
                    <SelectItem value="Mancata consegna">Mancata consegna</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label className="text-xs">Descrizione</Label>
                <Textarea
                  rows={4}
                  value={descr}
                  onChange={(e) => setDescr(e.target.value)}
                  placeholder="Racconta cosa è successo…"
                />
              </div>
              <div>
                <Label className="text-xs">Foto</Label>
                <div className="mt-2 flex flex-wrap gap-2">
                  {foto.map((f, i) => (
                    <img key={i} src={f} alt="" className="h-16 w-16 rounded-md object-cover" />
                  ))}
                  <button
                    onClick={simulaCarica}
                    type="button"
                    className="grid h-16 w-16 place-items-center rounded-md border border-dashed border-border text-xs text-muted-foreground hover:bg-secondary"
                  >
                    <Camera className="h-4 w-4" />
                  </button>
                </div>
                <p className="mt-1 text-[10px] text-muted-foreground">
                  Caricamento simulato (demo)
                </p>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setOpenDispDlg(false)}>
                Annulla
              </Button>
              <Button
                className="bg-bordeaux hover:bg-bordeaux/90"
                disabled={!descr.trim() || loading}
                onClick={() => {
                  setLoading(true);
                  setTimeout(() => {
                    openDispute(orderId, { motivo, descrizione: descr, foto });
                    setLoading(false);
                    setOpenDispDlg(false);
                  }, 800);
                }}
              >
                {loading ? "Invio…" : "Apri contestazione"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </section>
  );
}

/* ============ Dispute display ============ */

function DisputePanel({ orderId, isSeller }: { orderId: string; isSeller: boolean }) {
  const { getOrder, resolveDispute } = useVinea();
  const order = getOrder(orderId)!;
  const d = order.dispute!;
  const [loading, setLoading] = useState(false);
  const statoLabel = {
    aperta: "Aperta",
    in_valutazione: "In valutazione",
    rimborsata: "Rimborsata",
    risolta: "Risolta",
    respinta: "Respinta",
  }[d.stato];

  return (
    <section className="rounded-2xl border border-red-500/30 bg-red-500/5 p-4">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-semibold text-red-700">Contestazione · {statoLabel}</p>
        <span className="rounded-full bg-red-500/10 px-2 py-0.5 text-[10px] font-medium text-red-700">
          {new Date(d.aperturaTs).toLocaleDateString("it-IT")}
        </span>
      </div>
      <p className="mt-2 text-sm">
        <b>Motivo:</b> {d.motivo}
      </p>
      <p className="mt-1 text-sm text-antracite/80">{d.descrizione}</p>
      {d.foto.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-2">
          {d.foto.map((f, i) => (
            <img key={i} src={f} alt="" className="h-16 w-16 rounded-md object-cover" />
          ))}
        </div>
      )}
      {d.esito && <p className="mt-3 text-xs text-muted-foreground">Esito: {d.esito}</p>}

      {d.stato === "aperta" && (
        <div className="mt-4 space-y-2 border-t border-red-500/20 pt-3">
          <p className="text-xs text-muted-foreground">
            Azioni demo — simula l'esito della pratica:
          </p>
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={loading}
              onClick={() => {
                setLoading(true);
                setTimeout(() => {
                  resolveDispute(orderId, "rimborsata", "Rimborso completo emesso");
                  setLoading(false);
                }, 700);
              }}
            >
              Rimborsa acquirente
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={loading}
              onClick={() => {
                setLoading(true);
                setTimeout(() => {
                  resolveDispute(orderId, "risolta", "Accordo tra le parti");
                  setLoading(false);
                }, 700);
              }}
            >
              Risolta con accordo
            </Button>
            {isSeller && (
              <Button
                size="sm"
                variant="ghost"
                disabled={loading}
                onClick={() => {
                  setLoading(true);
                  setTimeout(() => {
                    resolveDispute(orderId, "respinta", "Nessuna irregolarità riscontrata");
                    setLoading(false);
                  }, 700);
                }}
              >
                <XCircle className="h-3.5 w-3.5" /> Respingi
              </Button>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

/* ============ Review ============ */

function ReviewPanel({ orderId, existing }: { orderId: string; existing?: OrderReview }) {
  const { submitReview } = useVinea();
  const [voto, setVoto] = useState(existing?.voto ?? 5);
  const [conf, setConf] = useState(existing?.conformita ?? 5);
  const [imb, setImb] = useState(existing?.imballaggio ?? 5);
  const [com, setCom] = useState(existing?.comunicazione ?? 5);
  const [testo, setTesto] = useState(existing?.testo ?? "");
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(!!existing);

  if (sent) {
    return (
      <section className="rounded-2xl border border-oro/40 bg-oro/10 p-4">
        <p className="text-sm font-semibold">Recensione inviata</p>
        <div className="mt-2 flex flex-wrap gap-3 text-sm">
          <Rating label="Generale" value={voto} />
          <Rating label="Conformità" value={conf} />
          <Rating label="Imballaggio" value={imb} />
          <Rating label="Comunicazione" value={com} />
        </div>
        {testo && <p className="mt-3 text-sm italic">"{testo}"</p>}
      </section>
    );
  }

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="text-sm font-semibold">Lascia una recensione</p>
      <p className="mt-1 text-xs text-muted-foreground">
        Aiuta la community valutando l'esperienza.
      </p>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <StarInput label="Voto generale" value={voto} onChange={setVoto} />
        <StarInput label="Conformità descrizione" value={conf} onChange={setConf} />
        <StarInput label="Imballaggio" value={imb} onChange={setImb} />
        <StarInput label="Comunicazione" value={com} onChange={setCom} />
      </div>
      <Textarea
        className="mt-3"
        rows={3}
        value={testo}
        onChange={(e) => setTesto(e.target.value)}
        placeholder="Un commento (facoltativo)…"
      />
      <Button
        className="mt-3 bg-bordeaux hover:bg-bordeaux/90"
        disabled={loading}
        onClick={() => {
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
        }}
      >
        {loading ? "Invio…" : "Pubblica recensione"}
      </Button>
    </section>
  );
}

function StarInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (n: number) => void;
}) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="mt-1 flex gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button key={n} type="button" onClick={() => onChange(n)} aria-label={`${n} stelle`}>
            <Star
              className={`h-5 w-5 ${n <= value ? "fill-oro text-oro" : "text-muted-foreground"}`}
            />
          </button>
        ))}
      </div>
    </div>
  );
}

function Rating({ label, value }: { label: string; value: number }) {
  return (
    <div className="text-xs">
      <p className="text-muted-foreground">{label}</p>
      <div className="flex">
        {Array.from({ length: value }).map((_, k) => (
          <Star key={k} className="h-3.5 w-3.5 fill-oro text-oro" />
        ))}
      </div>
    </div>
  );
}
