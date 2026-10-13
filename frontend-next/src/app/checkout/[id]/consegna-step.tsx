"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Handshake, Home, MapPin, Plus, Truck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { FormIndirizzo } from "@/components/vinea/indirizzi/FormIndirizzo";
import { useRubrica } from "@/components/vinea/indirizzi/useRubrica";
import {
  indirizzoConsegnaProposto,
  indirizzoVuoto,
  rigaIndirizzo,
  titoloIndirizzo,
} from "@/lib/indirizzi/rubrica";
import { opzioneDestinazione, type DatiCheckoutBeta, type ErroriCheckout } from "@/lib/beta/checkout";
import { euro } from "@/lib/prezzi/classe";
import type { PreventivoLogistica } from "@/services/logistica-service";

type Props = {
  dati: DatiCheckoutBeta;
  errori: ErroriCheckout;
  set: <K extends keyof DatiCheckoutBeta>(campo: K, valore: DatiCheckoutBeta[K]) => void;
  logistica: PreventivoLogistica | null;
  bottiglie: number;
};

/**
 * Consegna: spedizione (punto di ritiro predefinito, o domicilio da rubrica) o
 * ritiro concordato. Nessun corriere né servizio si sceglie qui: li decide il
 * routing del database. Il costo mostrato per ogni destinazione è quello del
 * preventivo del database; se manca, si dice e non si stima.
 */
export function ConsegnaStep({ dati, errori, set, logistica, bottiglie }: Props) {
  const home = opzioneDestinazione(logistica, "home");
  const notaDomicilio = home?.ordinabile && home.totaleCents !== null
    ? `Spedizione ${euro(home.totaleCents)}, sempre addebitata`
    : "Non ancora disponibile";
  const notaPudo = bottiglie > 1
    ? (() => {
        const pudo = opzioneDestinazione(logistica, "pudo");
        return pudo?.ordinabile && pudo.totaleCents !== null
          ? `Consigliato · spedizione ${euro(pudo.totaleCents)}`
          : "Consigliato · spedizione non ancora disponibile";
      })()
    : "Consigliato · ritiri il pacco in un punto vicino a te";

  return (
    <section className="space-y-4" data-testid="checkout-step-consegna">
      <div>
        <h2 className="font-serif text-2xl">Consegna o ritiro</h2>
        <p className="text-sm text-muted-foreground">Il corriere e il servizio li sceglie Vinea in base alla destinazione.</p>
      </div>
      <RadioGroup
        value={dati.deliveryMode}
        onValueChange={(valore) => set("deliveryMode", valore as DatiCheckoutBeta["deliveryMode"])}
        className="grid gap-3 sm:grid-cols-2"
      >
        <Scelta id="spedizione" icona={Truck} titolo="Spedizione" nota="Punto di ritiro o domicilio" />
        <Scelta id="consegna_mano" icona={Handshake} titolo="Ritiro concordato" nota="Nessun indirizzo" />
      </RadioGroup>
      {dati.deliveryMode === "spedizione" ? (
        <div className="space-y-3" data-testid="checkout-destinazione">
          <h3 className="text-sm font-semibold">Dove ricevi il pacco?</h3>
          <RadioGroup
            value={dati.destinazione}
            onValueChange={(valore) => set("destinazione", valore as DatiCheckoutBeta["destinazione"])}
            className="grid gap-3 sm:grid-cols-2"
          >
            <Scelta id="pudo" icona={MapPin} titolo="Punto di ritiro" nota={notaPudo} />
            <Scelta id="home" icona={Home} titolo="A domicilio" nota={notaDomicilio} />
          </RadioGroup>
          {dati.destinazione === "home" ? (
            <SceltaIndirizzo dati={dati} set={set} errore={errori.indirizzoId} />
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

function SceltaIndirizzo({
  dati,
  set,
  errore,
}: {
  dati: DatiCheckoutBeta;
  set: Props["set"];
  errore?: string;
}) {
  const { indirizzi, errore: erroreRubrica, caricamento, salva } = useRubrica();
  const [nuovo, setNuovo] = useState(false);
  const proposto = indirizzi ? indirizzoConsegnaProposto(indirizzi, dati.indirizzoId) : null;

  // Proposta: il predefinito di consegna (o il primo) quando non c'è ancora
  // una scelta valida; un indirizzo archiviato altrove non resta selezionato.
  useEffect(() => {
    if (!indirizzi) return;
    const valido = dati.indirizzoId !== null && indirizzi.some((i) => i.id === dati.indirizzoId);
    if (!valido && (proposto?.id ?? null) !== dati.indirizzoId) set("indirizzoId", proposto?.id ?? null);
  }, [indirizzi, proposto, dati.indirizzoId, set]);

  if (caricamento && !indirizzi) return <p className="text-sm text-muted-foreground">Caricamento della rubrica…</p>;
  if (!indirizzi) {
    return (
      <p role="alert" className="text-sm text-red-700">
        {erroreRubrica ?? "La rubrica non è leggibile in questo momento."}
      </p>
    );
  }

  return (
    <div className="space-y-3 rounded-xl border border-border p-3" data-testid="checkout-rubrica">
      {indirizzi.length > 0 ? (
        <RadioGroup
          value={dati.indirizzoId ?? ""}
          onValueChange={(id) => set("indirizzoId", id)}
          className="grid gap-2"
        >
          {indirizzi.map((i) => (
            <Label
              key={i.id}
              htmlFor={`checkout-indirizzo-${i.id}`}
              className="flex cursor-pointer items-start gap-3 rounded-lg border border-border p-3"
            >
              <RadioGroupItem id={`checkout-indirizzo-${i.id}`} value={i.id} className="mt-0.5" />
              <span className="text-sm">
                <span className="block font-semibold">{titoloIndirizzo(i)}</span>
                <span className="block font-normal text-muted-foreground">{rigaIndirizzo(i)}</span>
              </span>
            </Label>
          ))}
        </RadioGroup>
      ) : (
        <p className="text-sm text-muted-foreground">Non hai ancora indirizzi salvati.</p>
      )}
      {errore ? <p className="text-xs text-red-700">{errore}</p> : null}
      {nuovo ? (
        <FormIndirizzo
          id={null}
          iniziale={indirizzoVuoto({ predefinitoConsegna: indirizzi.length === 0 })}
          mostraPredefiniti={false}
          etichettaSalva="Salva e usa questo indirizzo"
          onSalva={async (id, input) => {
            const esito = await salva(id, input);
            if (esito.ok) {
              set("indirizzoId", esito.data.id);
              setNuovo(false);
            }
            return esito;
          }}
          onAnnulla={() => setNuovo(false)}
        />
      ) : (
        <div className="flex flex-wrap items-center gap-3">
          <Button type="button" variant="outline" size="sm" onClick={() => setNuovo(true)} data-testid="checkout-nuovo-indirizzo">
            <Plus className="h-4 w-4" /> Nuovo indirizzo
          </Button>
          <Link href="/account#indirizzi" className="text-xs text-bordeaux underline underline-offset-2">
            Gestisci la rubrica
          </Link>
        </div>
      )}
      <p className="text-xs text-muted-foreground">
        Il venditore vede solo città e provincia; l&apos;indirizzo completo serve al corriere.
      </p>
    </div>
  );
}

const Scelta = ({ id, icona: Icon, titolo, nota }: { id: string; icona: typeof Truck; titolo: string; nota: string }) => (
  <Label htmlFor={`checkout-${id}`} className="flex cursor-pointer items-start gap-3 rounded-xl border border-border p-3">
    <RadioGroupItem id={`checkout-${id}`} value={id} className="mt-0.5" />
    <Icon className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" />
    <span><span className="block font-semibold">{titolo}</span><span className="block text-xs font-normal text-muted-foreground">{nota}</span></span>
  </Label>
);
