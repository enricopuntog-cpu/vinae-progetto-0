import { createFileRoute, Link, notFound, useNavigate, useRouter } from "@tanstack/react-router";
import { useMemo, useRef, useState } from "react";
import {
  ArrowLeft,
  ShieldCheck,
  Truck,
  Handshake,
  CreditCard,
  Lock,
  AlertTriangle,
  Loader2,
  type LucideIcon,
} from "lucide-react";
import { wines } from "@/data/wines";
import {
  calcolaProtezione,
  calcolaSpedizione,
  carteDemo,
  indirizzoDemo,
  tempiConsegna,
  type DeliveryMode,
  type PaymentMethod,
} from "@/data/orders";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { Button } from "@/components/ui/button";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { apiJson, jsonRequest } from "@/services/api-client";
import { checkoutSessionSchema } from "@/services/api-contracts";

export const Route = createFileRoute("/checkout/$id")({
  validateSearch: (s: Record<string, unknown>) => ({
    prop: typeof s.prop === "string" ? s.prop : undefined,
    q: typeof s.q === "string" ? Number(s.q) : undefined,
  }),
  loader: ({ params }) => {
    const wine = wines.find((w) => w.id === params.id);
    if (!wine) throw notFound();
    return { wine };
  },
  head: ({ loaderData }) => ({
    meta: [
      { title: loaderData ? `Checkout — ${loaderData.wine.nome} | Vinea` : "Checkout — Vinea" },
      {
        name: "description",
        content: "Checkout dimostrativo Vinea Wine Club. Nessun pagamento reale.",
      },
      { property: "og:title", content: "Checkout — Vinea Wine Club" },
      {
        property: "og:description",
        content: "Simulazione di checkout con protezione acquisti, spedizione e riepilogo.",
      },
      { name: "robots", content: "noindex" },
    ],
  }),
  notFoundComponent: () => (
    <div className="grid place-items-center py-24 text-center">
      <p className="font-serif text-3xl">Annuncio non trovato</p>
      <Link to="/esplora" className="mt-4 text-bordeaux underline">
        Torna alla ricerca
      </Link>
    </div>
  ),
  component: Checkout,
});

function Checkout() {
  const { wine } = Route.useLoaderData();
  const search = Route.useSearch();
  const router = useRouter();
  const navigate = useNavigate();
  const { proposals, createOrder } = useVinea();

  const proposta = search.prop ? proposals.find((p) => p.id === search.prop) : undefined;
  const prezzoUnit =
    proposta?.stato === "accettata"
      ? proposta.prezzoProposto
      : (proposta?.controProposta ?? wine.prezzo);

  const [quantita, setQuantita] = useState<number>(
    Math.min(Math.max(1, search.q ?? 1), wine.disponibili),
  );
  const [delivery, setDelivery] = useState<DeliveryMode>("spedizione");
  const [metodo, setMetodo] = useState<PaymentMethod>("stripe_real");
  const [processing, setProcessing] = useState(false);
  const [erroreVisibile, setErroreVisibile] = useState(false);
  const checkoutIdempotencyKey = useRef<string | null>(null);

  const subtot = prezzoUnit * quantita;
  const spedizione = useMemo(() => calcolaSpedizione(delivery, subtot), [delivery, subtot]);
  const protezione = calcolaProtezione(subtot);
  const totale = subtot + spedizione + protezione;

  async function conferma() {
    if (quantita < 1) return;
    if (metodo === "stripe_real") {
      await pagaConStripe();
      return;
    }
    setErroreVisibile(false);
    setProcessing(true);
    try {
      const order = await createOrder({
        wineId: wine.id,
        quantita,
        deliveryMode: delivery,
        metodoPagamento: metodo,
        proposalId: proposta?.id,
        prezzoUnitario: prezzoUnit,
      });
      toast.success("Ordine confermato");
      navigate({ to: "/ordine/$id", params: { id: order.id } });
    } catch (e) {
      setErroreVisibile(true);
      setProcessing(false);
    }
  }

  async function pagaConStripe() {
    setErroreVisibile(false);
    setProcessing(true);
    try {
      checkoutIdempotencyKey.current ??=
        typeof crypto !== "undefined" && "randomUUID" in crypto
          ? crypto.randomUUID()
          : `checkout-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const data = await apiJson(
        "/api/payments/checkout",
        checkoutSessionSchema,
        jsonRequest(
          {
            lookup_key: `wine_${wine.id}`,
            quantity: quantita,
          },
          {
            method: "POST",
            headers: { "Idempotency-Key": checkoutIdempotencyKey.current },
          },
        ),
      );
      window.location.href = data.checkout_url;
    } catch (e) {
      checkoutIdempotencyKey.current = null;
      setErroreVisibile(true);
      setProcessing(false);
      toast.error("Errore Stripe. Riprova.");
    }
  }

  return (
    <div className="space-y-6 pb-32 md:pb-6">
      <button
        onClick={() => router.history.back()}
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
      >
        <ArrowLeft className="h-4 w-4" /> Indietro
      </button>

      <div className="flex flex-wrap items-center gap-3">
        <h1 className="font-serif text-3xl md:text-4xl">Checkout</h1>
        <span className="rounded-full bg-salvia/15 px-3 py-1 text-xs font-semibold text-salvia">
          Stripe test mode — carta 4242 4242 4242 4242
        </span>
      </div>

      {proposta && (
        <div className="rounded-2xl border border-oro/40 bg-oro/10 p-3 text-sm">
          Stai acquistando con proposta <b>{proposta.id}</b> a <b>{formatEUR(prezzoUnit)}</b>
          /bottiglia.
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="space-y-6">
          {/* Riepilogo bottiglia */}
          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Bottiglia</p>
            <div className="flex gap-4">
              <img
                src={wine.immagini[0]}
                alt=""
                className="h-24 w-20 shrink-0 rounded object-cover"
              />
              <div className="min-w-0 flex-1">
                <p className="truncate font-serif text-lg font-semibold">
                  {wine.nome} {wine.annata}
                </p>
                <p className="truncate text-sm text-muted-foreground">
                  {wine.produttore} • {wine.formato}
                </p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Venditore: {wine.venditore.nome}
                </p>
              </div>
              <div className="text-right">
                <p className="font-serif text-xl font-semibold text-bordeaux">
                  {formatEUR(prezzoUnit)}
                </p>
                <div className="mt-2 inline-flex items-center gap-1 rounded-full border border-border">
                  <button
                    onClick={() => setQuantita((q) => Math.max(1, q - 1))}
                    className="px-2 py-1 text-sm"
                    aria-label="Diminuisci"
                  >
                    −
                  </button>
                  <span className="w-6 text-center text-sm font-semibold">{quantita}</span>
                  <button
                    onClick={() => setQuantita((q) => Math.min(wine.disponibili, q + 1))}
                    className="px-2 py-1 text-sm"
                    aria-label="Aumenta"
                  >
                    +
                  </button>
                </div>
                <p className="mt-1 text-[10px] text-muted-foreground">Max {wine.disponibili}</p>
              </div>
            </div>
          </section>

          {/* Consegna */}
          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Consegna</p>
            <RadioGroup
              value={delivery}
              onValueChange={(value) => {
                if (value === "spedizione" || value === "consegna_mano") setDelivery(value);
              }}
              className="grid gap-2 sm:grid-cols-2"
            >
              <DeliveryOption
                id="spedizione"
                checked={delivery === "spedizione"}
                icon={Truck}
                title="Spedizione"
                tempo="2–4 giorni lavorativi"
                costo={calcolaSpedizione("spedizione", subtot) === 0 ? "Gratis" : "12 €"}
              />
              <DeliveryOption
                id="consegna_mano"
                checked={delivery === "consegna_mano"}
                icon={Handshake}
                title="Consegna a mano"
                tempo="Da concordare col venditore"
                costo="Gratis"
              />
            </RadioGroup>
            <p className="mt-3 text-xs text-muted-foreground">
              Tempi: {tempiConsegna(delivery)}. Spedizione gratuita per ordini ≥ 500 €.
            </p>
          </section>

          {/* Indirizzo */}
          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
              Indirizzo di consegna (demo)
            </p>
            <div className="grid gap-2 text-sm sm:grid-cols-2">
              <div>
                <Label className="text-xs">Destinatario</Label>
                <Input readOnly value={indirizzoDemo.nome} />
              </div>
              <div>
                <Label className="text-xs">Via</Label>
                <Input readOnly value={indirizzoDemo.via} />
              </div>
              <div>
                <Label className="text-xs">CAP</Label>
                <Input readOnly value={indirizzoDemo.cap} />
              </div>
              <div>
                <Label className="text-xs">Città</Label>
                <Input readOnly value={`${indirizzoDemo.citta} (${indirizzoDemo.provincia})`} />
              </div>
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              Indirizzo dimostrativo. In demo non richiediamo dati reali.
            </p>
          </section>

          {/* Pagamento */}
          <section
            className="rounded-2xl border border-border bg-card p-4"
            data-testid="checkout-payment-section"
          >
            <div className="mb-3 flex items-center justify-between">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">
                Metodo di pagamento
              </p>
              <span className="inline-flex items-center gap-1 rounded-full bg-salvia/15 px-2 py-0.5 text-[10px] font-medium text-salvia">
                <Lock className="h-3 w-3" /> Stripe test mode
              </span>
            </div>
            <RadioGroup
              value={metodo}
              onValueChange={(value) => {
                if (
                  value === "stripe_real" ||
                  value === "carta_demo" ||
                  value === "paypal_demo" ||
                  value === "bonifico_demo"
                ) {
                  setMetodo(value);
                }
              }}
              className="grid gap-2"
            >
              <label
                htmlFor="stripe_real"
                className={`flex items-center gap-3 rounded-xl border p-3 text-sm cursor-pointer ${metodo === "stripe_real" ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
                data-testid="checkout-method-stripe"
              >
                <RadioGroupItem id="stripe_real" value="stripe_real" />
                <CreditCard className="h-4 w-4 text-bordeaux" />
                <span className="min-w-0 flex-1">
                  <span className="font-semibold">Carta di credito (Stripe)</span>
                  <span className="ml-2 text-xs text-muted-foreground">
                    Checkout sicuro — test 4242 4242 4242 4242
                  </span>
                </span>
                <span className="rounded-full bg-bordeaux/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-bordeaux">
                  Live demo
                </span>
              </label>
              {carteDemo.map((c) => (
                <label
                  key={c.id}
                  htmlFor={c.id}
                  className={`flex items-center gap-3 rounded-xl border p-3 text-sm cursor-pointer ${metodo === c.id ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
                  data-testid={`checkout-method-${c.id}`}
                >
                  <RadioGroupItem id={c.id} value={c.id} />
                  <CreditCard className="h-4 w-4 text-muted-foreground" />
                  <span className="min-w-0 flex-1 truncate">{c.label}</span>
                  <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] uppercase tracking-wide">
                    Mock
                  </span>
                </label>
              ))}
            </RadioGroup>
            <p className="mt-3 text-xs text-muted-foreground">
              Il metodo <b>Stripe</b> apre una vera sessione di checkout in modalità test. Usa la
              carta <code className="rounded bg-secondary px-1">4242 4242 4242 4242</code>,
              qualsiasi data futura e CVC. L’importo configurato dal server è mostrato da Stripe
              prima della conferma; spedizione e protezione visualizzate nella demo non vengono
              addebitate da questo flusso.
            </p>
          </section>

          {erroreVisibile && (
            <div className="flex items-start gap-2 rounded-2xl border border-red-500/30 bg-red-500/5 p-3 text-sm text-red-700">
              <AlertTriangle className="mt-0.5 h-4 w-4" />
              <div>
                <p className="font-semibold">Impossibile confermare l'ordine</p>
                <p className="text-xs">Riprova tra qualche secondo.</p>
              </div>
            </div>
          )}
        </div>

        {/* Riepilogo prezzo */}
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <div className="hidden rounded-2xl border border-border bg-card p-4 lg:block">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Riepilogo</p>
            <SummaryRows
              subtot={subtot}
              spedizione={spedizione}
              protezione={protezione}
              totale={totale}
              quantita={quantita}
              stripeMode={metodo === "stripe_real"}
            />
            <Button
              disabled={processing}
              data-testid="checkout-confirm-btn"
              onClick={metodo === "stripe_real" ? pagaConStripe : conferma}
              className="mt-4 w-full bg-bordeaux hover:bg-bordeaux/90"
            >
              {processing ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" /> Elaborazione…
                </>
              ) : metodo === "stripe_real" ? (
                <>
                  <CreditCard className="h-4 w-4" /> Continua su Stripe
                </>
              ) : (
                <>Conferma ordine · {formatEUR(totale)}</>
              )}
            </Button>
            <p className="mt-2 inline-flex items-center gap-1 text-[11px] text-muted-foreground">
              <ShieldCheck className="h-3 w-3 text-salvia" />
              {metodo === "stripe_real"
                ? "Importo finale verificabile nella pagina Stripe"
                : "Protezione acquisti Vinea inclusa"}
            </p>
          </div>
        </aside>
      </div>

      {/* CTA fissa mobile */}
      <div className="fixed inset-x-0 bottom-14 z-40 border-t border-border bg-crema/95 p-3 backdrop-blur md:bottom-0 lg:hidden">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3">
          <div>
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {metodo === "stripe_real" ? "Importo effettivo" : "Totale"}
            </p>
            <p className="font-serif text-xl font-semibold text-bordeaux">
              {metodo === "stripe_real" ? "Mostrato da Stripe" : formatEUR(totale)}
            </p>
          </div>
          <Button
            disabled={processing}
            data-testid="checkout-confirm-btn-mobile"
            onClick={metodo === "stripe_real" ? pagaConStripe : conferma}
            className="flex-1 bg-bordeaux hover:bg-bordeaux/90"
          >
            {processing ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" /> Elaborazione…
              </>
            ) : metodo === "stripe_real" ? (
              <>
                <CreditCard className="h-4 w-4" /> Paga con Stripe
              </>
            ) : (
              "Conferma ordine"
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}

type DeliveryOptionProps = {
  id: DeliveryMode;
  checked: boolean;
  icon: LucideIcon;
  title: string;
  tempo: string;
  costo: string;
};

function DeliveryOption({ id, checked, icon: Icon, title, tempo, costo }: DeliveryOptionProps) {
  return (
    <label
      htmlFor={id}
      className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 text-sm ${checked ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
    >
      <RadioGroupItem id={id} value={id} className="mt-0.5" />
      <Icon className="mt-0.5 h-5 w-5 text-bordeaux" />
      <div className="min-w-0 flex-1">
        <p className="font-semibold">{title}</p>
        <p className="text-xs text-muted-foreground">{tempo}</p>
      </div>
      <span className="shrink-0 text-sm font-semibold">{costo}</span>
    </label>
  );
}

type SummaryRowsProps = {
  subtot: number;
  spedizione: number;
  protezione: number;
  totale: number;
  quantita: number;
  stripeMode: boolean;
};

function SummaryRows({
  subtot,
  spedizione,
  protezione,
  totale,
  quantita,
  stripeMode,
}: SummaryRowsProps) {
  if (stripeMode) {
    return (
      <div className="space-y-2 text-sm">
        <Row label={`Prezzo annuncio × ${quantita}`} value={formatEUR(subtot)} />
        <Row label="Spedizione demo" value="Non addebitata" />
        <Row label="Protezione demo" value="Non addebitata" />
        <div className="my-2 h-px bg-border" />
        <p className="text-xs leading-relaxed text-muted-foreground">
          Questo riepilogo è indicativo. Il prezzo configurato nel catalogo server e l’importo
          effettivamente addebitato vengono mostrati nella pagina Stripe prima della conferma.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-1.5 text-sm">
      <Row label={`Bottiglie × ${quantita}`} value={formatEUR(subtot)} />
      <Row label="Spedizione" value={spedizione === 0 ? "Gratis" : formatEUR(spedizione)} />
      <Row
        label="Protezione acquisti"
        value={formatEUR(protezione)}
        hint="Copre autenticità, integrità e trasporto"
      />
      <div className="my-2 h-px bg-border" />
      <div className="flex items-baseline justify-between">
        <span className="font-serif text-lg">Totale</span>
        <span className="font-serif text-xl font-semibold text-bordeaux">{formatEUR(totale)}</span>
      </div>
    </div>
  );
}
function Row({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="flex items-start justify-between gap-2">
      <span className="min-w-0">
        <span className="text-antracite">{label}</span>
        {hint && <span className="block text-[11px] text-muted-foreground">{hint}</span>}
      </span>
      <span className="shrink-0 font-medium">{value}</span>
    </div>
  );
}
