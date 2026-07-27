import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { z, ZodError } from "zod";
import { CheckCircle2, Loader2, AlertTriangle, ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import { apiJson } from "@/services/api-client";
import { paymentStatusSchema } from "@/services/api-contracts";

const search = z.object({ session_id: z.string().optional() });

export const Route = createFileRoute("/payment/success")({
  validateSearch: search,
  head: () => ({
    meta: [{ title: "Pagamento completato — Vinea" }, { name: "robots", content: "noindex" }],
  }),
  component: PaymentSuccess,
});

type PollState = "polling" | "paid" | "expired" | "error";

function PaymentSuccess() {
  const { session_id } = Route.useSearch();
  const nav = useNavigate();
  const [state, setState] = useState<PollState>("polling");
  const [attempts, setAttempts] = useState(0);
  const [orderId, setOrderId] = useState<string | null>(null);

  useEffect(() => {
    if (!session_id) {
      setState("error");
      return;
    }
    const paymentSessionId = session_id;

    let cancelled = false;
    let n = 0;

    async function tick() {
      if (cancelled) return;
      n += 1;
      setAttempts(n);

      if (n > 8) {
        setState("expired");
        return;
      }

      try {
        const data = await apiJson(
          `/api/payments/status/${encodeURIComponent(paymentSessionId)}`,
          paymentStatusSchema,
        );

        if (data.payment_status === "paid") {
          setOrderId(data.order_id);
          setState("paid");
          return;
        }
        if (data.status === "expired" || data.payment_status === "expired") {
          setState("expired");
          return;
        }
      } catch (error) {
        if (error instanceof ZodError) {
          setState("error");
          return;
        }
        // Gli errori di rete transitori vengono ritentati.
      }
      setTimeout(tick, 2000);
    }

    tick();
    return () => {
      cancelled = true;
    };
  }, [session_id]);

  useEffect(() => {
    if (state === "paid") toast.success("Pagamento riuscito — ordine confermato");
  }, [state]);

  return (
    <div
      className="mx-auto grid max-w-lg place-items-center gap-4 rounded-3xl border border-border bg-card p-8 text-center"
      data-testid="payment-success-page"
    >
      {state === "polling" && (
        <>
          <div className="grid h-16 w-16 place-items-center rounded-full bg-oro/15 text-oro">
            <Loader2 className="h-8 w-8 animate-spin" />
          </div>
          <h1 className="font-serif text-3xl">Verifica del pagamento in corso…</h1>
          <p className="text-sm text-muted-foreground">
            Stiamo confermando con Stripe (tentativo {attempts}/8).
          </p>
        </>
      )}
      {state === "paid" && (
        <>
          <div className="grid h-16 w-16 place-items-center rounded-full bg-salvia/20 text-salvia">
            <CheckCircle2 className="h-8 w-8" />
          </div>
          <h1 className="font-serif text-3xl" data-testid="payment-success-title">
            Pagamento riuscito!
          </h1>
          <p className="text-sm text-muted-foreground">
            Grazie. Il tuo ordine è stato registrato e sarà spedito a breve.
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            {orderId && (
              <Button
                data-testid="payment-success-view-order"
                className="bg-bordeaux hover:bg-bordeaux/90"
                onClick={() => nav({ to: "/ordine/$id", params: { id: orderId } })}
              >
                Vedi ordine <ArrowRight className="ml-1 h-4 w-4" />
              </Button>
            )}
            <Button asChild variant="outline">
              <Link to="/acquisti">I miei acquisti</Link>
            </Button>
            <Button asChild variant="ghost">
              <Link to="/esplora">Continua a esplorare</Link>
            </Button>
          </div>
        </>
      )}
      {state === "expired" && (
        <>
          <div className="grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
            <AlertTriangle className="h-8 w-8" />
          </div>
          <h1 className="font-serif text-3xl">Verifica non completata</h1>
          <p className="text-sm text-muted-foreground">
            Il pagamento potrebbe essere ancora in corso. Controlla tra qualche istante dalla pagina
            "I miei acquisti".
          </p>
          <Button asChild variant="outline">
            <Link to="/acquisti">I miei acquisti</Link>
          </Button>
        </>
      )}
      {state === "error" && (
        <>
          <div className="grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
            <AlertTriangle className="h-8 w-8" />
          </div>
          <h1 className="font-serif text-3xl">Sessione non trovata</h1>
          <p className="text-sm text-muted-foreground">
            La sessione di pagamento non è più disponibile. Se hai già pagato, controlla la sezione
            ordini.
          </p>
          <Button asChild variant="outline">
            <Link to="/esplora">Torna alla ricerca</Link>
          </Button>
        </>
      )}
      <p className="mt-4 text-[10px] uppercase tracking-[0.3em] text-muted-foreground">
        Stripe test mode — nessun addebito reale
      </p>
    </div>
  );
}
