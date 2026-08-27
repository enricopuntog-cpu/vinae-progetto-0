"use client";

import { useEffect, useState } from "react";
import { RefreshCcw, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createBalanceService } from "@/services/phase7/balance-service";
import { getSupabaseClient } from "@/lib/supabase/client";
import { formatEUR } from "@/lib/format";
import { etichettaMovimento, etichettaStatoPrelievo, deltaLeggibili } from "@/lib/balance/etichette";
import type { SaldoVinea } from "@/services/types";

const Card = ({ children, className = "" }: { children: React.ReactNode; className?: string }) => (
  <div className={`rounded-2xl border border-border bg-card p-5 md:p-6 ${className}`}>{children}</div>
);

export default function SaldoVineaPanel() {
  const [saldo, setSaldo] = useState<SaldoVinea | null>(null);
  const [caricamento, setCaricamento] = useState(true);
  const [errore, setErrore] = useState<string | null>(null);
  const [prelievoInCorso, setPrelievoInCorso] = useState(false);

  const carica = () => {
    setCaricamento(true);
    setErrore(null);
    createBalanceService(getSupabaseClient())
      .riepilogo(20)
      .then((r) => {
        if (r.ok) setSaldo(r.data);
        else setErrore(r.error);
        setCaricamento(false);
      })
      .catch(() => {
        setErrore("Non è stato possibile leggere il saldo.");
        setCaricamento(false);
      });
  };

  useEffect(() => {
    let attivo = true;

    createBalanceService(getSupabaseClient())
      .riepilogo(20)
      .then((r) => {
        if (!attivo) return;
        if (r.ok) setSaldo(r.data);
        else setErrore(r.error);
        setCaricamento(false);
      })
      .catch(() => {
        if (!attivo) return;
        setErrore("Non è stato possibile leggere il saldo.");
        setCaricamento(false);
      });

    return () => {
      attivo = false;
    };
  }, []);

  const richiediPrelievo = async () => {
    const importo = 5000; // valore demo — in una schermata reale l'importo
    // proviene da un input verificato, mai dal browser come decisione autonoma.
    setPrelievoInCorso(true);
    const r = await createBalanceService(getSupabaseClient()).richiediPrelievo(importo);
    setPrelievoInCorso(false);
    if (r.ok) carica();
    else setErrore(r.error);
  };

  const annullaPrelievo = async (id: string) => {
    const r = await createBalanceService(getSupabaseClient()).annullaPrelievo(id);
    if (r.ok) carica();
    else setErrore(r.error);
  };

  return (
    <section className="space-y-6" data-testid="saldo-vinea">
      <header>
        <h2 className="font-serif text-2xl md:text-3xl">Il tuo saldo Vinea</h2>
        <p className="text-sm text-muted-foreground mt-1">
          Il saldo è contabilità autorizzata dal database, non un numero ricavato dal browser.
        </p>
      </header>

      {caricamento && !saldo && (
        <Card><p className="text-sm text-muted-foreground">Carico il saldo…</p></Card>
      )}

      {errore && (
        <Card className="border-red-200 bg-red-50/40">
          <p className="text-sm text-red-700">{errore}</p>
          <Button size="sm" variant="outline" className="mt-3" onClick={carica}>
            <RefreshCcw className="h-3.5 w-3.5 mr-1.5" /> Riprova
          </Button>
        </Card>
      )}

      {saldo && (
        <>
          <div className="grid gap-4 sm:grid-cols-3">
            <Card>
              <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">In attesa</p>
              <p className="mt-1 font-serif text-3xl text-amber-700">{formatEUR(saldo.pendingCents / 100)}</p>
              <p className="text-xs text-muted-foreground mt-1">Proventi da vendite non ancora rilasciati</p>
            </Card>
            <Card>
              <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">Disponibili</p>
              <p className="mt-1 font-serif text-3xl text-emerald-700">{formatEUR(saldo.availableCents / 100)}</p>
              <p className="text-xs text-muted-foreground mt-1">Che puoi usare per un acquisto o prelevare</p>
            </Card>
            <Card>
              <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">Spendibile</p>
              <p className="mt-1 font-serif text-3xl">{formatEUR(saldo.spendableCents / 100)}</p>
              <p className="text-xs text-muted-foreground mt-1">Disponibili meno impegnati dai prelievi</p>
            </Card>
          </div>

          <Card>
            <h3 className="font-serif text-xl mb-4">Prelievi aperti</h3>
            {saldo.prelievi.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nessun prelievo aperto.</p>
            ) : (
              <ul className="divide-y divide-border">
                {saldo.prelievi.map((p) => (
                  <li key={p.id} className="py-3 flex items-center justify-between gap-4">
                    <div>
                      <p className="text-sm font-medium">{etichettaStatoPrelievo(p.stato)}</p>
                      <p className="text-xs text-muted-foreground">{formatEUR(p.amountCents / 100)} · {new Date(p.createdAt).toLocaleDateString("it-IT")}</p>
                    </div>
                    {(p.stato === "richiesto" || p.stato === "in_corso") && (
                      <Button size="sm" variant="outline" onClick={() => annullaPrelievo(p.id)} disabled={prelievoInCorso}>Annulla</Button>
                    )}
                  </li>
                ))}
              </ul>
            )}
            <div className="mt-4 pt-4 border-t border-border flex gap-3">
              <Button size="sm" variant="outline" onClick={richiediPrelievo} disabled={prelievoInCorso}>
                <Wallet className="h-3.5 w-3.5 mr-1.5" /> Richiedi prelievo (demo)
              </Button>
            </div>
          </Card>

          <Card>
            <h3 className="font-serif text-xl mb-4">Movimenti recenti</h3>
            {saldo.movimenti.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nessun movimento registrato.</p>
            ) : (
              <ul className="divide-y divide-border">
                {saldo.movimenti.map((m) => (
                  <li key={m.id} className="py-3">
                    <div className="flex items-start justify-between gap-4">
                      <div>
                        <p className="text-sm font-medium">{etichettaMovimento(m.tipo)}</p>
                        <p className="text-xs text-muted-foreground">{new Date(m.createdAt).toLocaleDateString("it-IT")}</p>
                      </div>
                      <div className="text-right shrink-0">
                        <div className="text-xs text-muted-foreground">{deltaLeggibili(m).join(" · ")}</div>
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </>
      )}
    </section>
  );
}
