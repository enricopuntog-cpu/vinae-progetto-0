"use client";

import { CreditCard, Handshake, PackageCheck, Truck } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  OPZIONI_IMBALLAGGIO_BETA,
  type DatiCheckoutBeta,
  type ErroriCheckout,
} from "@/lib/beta/checkout";

type StepProps = {
  dati: DatiCheckoutBeta;
  errori: ErroriCheckout;
  set: <K extends keyof DatiCheckoutBeta>(campo: K, valore: DatiCheckoutBeta[K]) => void;
};

const ErroreCampo = ({ testo }: { testo?: string }) =>
  testo ? <p className="mt-1 text-xs text-red-700">{testo}</p> : null;

export const ContattiStep = ({ dati, errori, set }: StepProps) => (
  <section className="space-y-4" data-testid="checkout-step-contatti">
    <div>
      <h2 className="font-serif text-2xl">Dati di contatto</h2>
      <p className="text-sm text-muted-foreground">Servono per gli aggiornamenti sull'acquisto.</p>
    </div>
    <div className="grid gap-4 sm:grid-cols-2">
      <div>
        <Label htmlFor="checkout-email">Email</Label>
        <Input id="checkout-email" value={dati.email} onChange={(e) => set("email", e.target.value)} />
        <ErroreCampo testo={errori.email} />
      </div>
      <div>
        <Label htmlFor="checkout-telefono">Telefono</Label>
        <Input
          id="checkout-telefono"
          inputMode="tel"
          value={dati.telefono}
          onChange={(e) => set("telefono", e.target.value)}
        />
        <ErroreCampo testo={errori.telefono} />
      </div>
    </div>
  </section>
);

export const ConsegnaStep = ({ dati, errori, set }: StepProps) => (
  <section className="space-y-4" data-testid="checkout-step-consegna">
    <div>
      <h2 className="font-serif text-2xl">Consegna o ritiro</h2>
      <p className="text-sm text-muted-foreground">Scegli il flusso che vuoi verificare.</p>
    </div>
    <RadioGroup
      value={dati.deliveryMode}
      onValueChange={(valore) => set("deliveryMode", valore as DatiCheckoutBeta["deliveryMode"])}
      className="grid gap-3 sm:grid-cols-2"
    >
      <Scelta id="spedizione" icona={Truck} titolo="Spedizione" nota="Indirizzo richiesto" />
      <Scelta id="consegna_mano" icona={Handshake} titolo="Ritiro concordato" nota="Nessun indirizzo" />
    </RadioGroup>
    {dati.deliveryMode === "spedizione" ? (
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo id="destinatario" label="Destinatario" valore={dati.destinatario} errore={errori.destinatario} set={set} />
        <Campo id="via" label="Indirizzo" valore={dati.via} errore={errori.via} set={set} />
        <Campo id="cap" label="CAP" valore={dati.cap} errore={errori.cap} set={set} />
        <Campo id="citta" label="Città" valore={dati.citta} errore={errori.citta} set={set} />
        <Campo id="provincia" label="Provincia" valore={dati.provincia} errore={errori.provincia} set={set} />
      </div>
    ) : null}
  </section>
);

export const ImballaggioStep = ({ dati, set }: StepProps) => (
  <section className="space-y-4" data-testid="checkout-step-imballaggio">
    <div>
      <h2 className="font-serif text-2xl">Preferenza di imballaggio</h2>
      <p className="text-sm text-muted-foreground">Dati beta locali, costo attuale pari a zero.</p>
    </div>
    <RadioGroup value={dati.imballaggioCodice} onValueChange={(v) => set("imballaggioCodice", v)}>
      <Scelta id="nessuno" icona={PackageCheck} titolo="Da concordare" nota="Nessun costo stimato" />
      {OPZIONI_IMBALLAGGIO_BETA.map((opzione) => (
        <Scelta
          key={opzione.codice}
          id={opzione.codice}
          icona={PackageCheck}
          titolo={opzione.etichetta}
          nota={opzione.descrizione ?? "Preferenza beta"}
        />
      ))}
    </RadioGroup>
  </section>
);

export const PagamentoStep = ({ dati, set, usaSaldo, setUsaSaldo }: StepProps & { usaSaldo?: boolean; setUsaSaldo?: (v: boolean) => void }) => (
  <section className="space-y-4" data-testid="checkout-step-pagamento">
    <div>
      <h2 className="font-serif text-2xl">Metodo di pagamento</h2>
      <p className="text-sm text-muted-foreground">La conferma finale si fermerà prima del provider.</p>
    </div>
    <RadioGroup value={dati.metodoPagamento} onValueChange={(v) => set("metodoPagamento", v as DatiCheckoutBeta["metodoPagamento"])}>
      <Scelta id="carta" icona={CreditCard} titolo="Carta di pagamento" nota="Disponibilità verificata dal provider all'attivazione" />
      <Scelta id="wallet" icona={CreditCard} titolo="Wallet digitale" nota="Disponibilità verificata dal provider all'attivazione" />
    </RadioGroup>
    {setUsaSaldo && (
      <label className="flex items-center gap-3 rounded-xl border border-border bg-muted/30 p-3 cursor-pointer">
        <input
          type="checkbox"
          checked={!!usaSaldo}
          onChange={(e) => setUsaSaldo(e.target.checked)}
          className="h-4 w-4 accent-bordeaux"
        />
        <div>
          <span className="block text-sm font-medium">Usa saldo Vinea</span>
          <span className="block text-xs text-muted-foreground">Se hai credito disponibile verrà applicato automaticamente.</span>
        </div>
      </label>
    )}
  </section>
);

const Campo = ({ id, label, valore, errore, set }: { id: "destinatario" | "via" | "cap" | "citta" | "provincia"; label: string; valore: string; errore?: string; set: StepProps["set"] }) => (
  <div>
    <Label htmlFor={`checkout-${id}`}>{label}</Label>
    <Input id={`checkout-${id}`} value={valore} onChange={(e) => set(id, e.target.value)} />
    <ErroreCampo testo={errore} />
  </div>
);

const Scelta = ({ id, icona: Icon, titolo, nota }: { id: string; icona: typeof Truck; titolo: string; nota: string }) => (
  <Label htmlFor={`checkout-${id}`} className="flex cursor-pointer items-start gap-3 rounded-xl border border-border p-3">
    <RadioGroupItem id={`checkout-${id}`} value={id} className="mt-0.5" />
    <Icon className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" />
    <span><span className="block font-semibold">{titolo}</span><span className="block text-xs font-normal text-muted-foreground">{nota}</span></span>
  </Label>
);
