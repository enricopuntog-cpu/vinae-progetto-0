"use client";

import { useState } from "react";
import { AlertTriangle, CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";

/** Gli stessi cinque motivi di frontend/. */
const MOTIVI = [
  "Bottiglia non conforme",
  "Bottiglia danneggiata",
  "Livello alterato",
  "Sospetta contraffazione",
  "Mancata consegna",
] as const;

type Props = {
  inCorso: boolean;
  onConferma: () => Promise<string | null>;
  onContesta: (motivo: string, descrizione: string, foto: string[]) => Promise<string | null>;
};

/**
 * Conferma di ricezione o apertura di una contestazione, lato compratore.
 *
 * La conferma è ammessa anche prima che il venditore dichiari la consegna: è
 * una scelta della 7b, e toglie al venditore la possibilità di tenere i fondi
 * bloccati non dichiarando mai nulla. Chi ha la bottiglia in mano può liberarli.
 */
export function BuyerConfirmPanel({ inCorso, onConferma, onContesta }: Props) {
  const [aperto, setAperto] = useState(false);
  const [motivo, setMotivo] = useState<string>(MOTIVI[0]);
  const [descrizione, setDescrizione] = useState("");
  const [errore, setErrore] = useState<string | null>(null);

  return (
    <section className="rounded-2xl border border-salvia/40 bg-salvia/5 p-4">
      <p className="text-sm font-semibold">Hai ricevuto l&apos;ordine?</p>
      <p className="mt-1 text-xs text-muted-foreground">
        Confermando liberi il pagamento al venditore. Se qualcosa non va, apri una contestazione:
        blocca i fondi finché la pratica non è chiusa.
      </p>
      {errore && <p className="mt-2 text-xs text-red-700">{errore}</p>}

      <div className="mt-3 flex flex-wrap gap-2">
        <Button
          className="bg-bordeaux hover:bg-bordeaux/90"
          disabled={inCorso}
          onClick={async () => setErrore(await onConferma())}
        >
          <CheckCircle2 className="h-4 w-4" />
          {inCorso ? "Conferma in corso…" : "Conferma che è tutto corretto"}
        </Button>

        <Dialog open={aperto} onOpenChange={setAperto}>
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
                    {MOTIVI.map((m) => (
                      <SelectItem key={m} value={m}>
                        {m}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label className="text-xs">Descrizione</Label>
                <Textarea
                  rows={4}
                  value={descrizione}
                  onChange={(e) => setDescrizione(e.target.value)}
                  placeholder="Racconta cosa è successo…"
                />
              </div>
              <p className="text-[11px] text-muted-foreground">
                Il caricamento delle foto arriverà con lo Storage della Cantina, ancora da
                verificare: per ora la contestazione si apre senza allegati.
              </p>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setAperto(false)}>
                Annulla
              </Button>
              <Button
                className="bg-bordeaux hover:bg-bordeaux/90"
                disabled={descrizione.trim().length < 3 || inCorso}
                onClick={async () => {
                  const err = await onContesta(motivo, descrizione, []);
                  setErrore(err);
                  if (!err) setAperto(false);
                }}
              >
                {inCorso ? "Invio…" : "Apri contestazione"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </section>
  );
}
