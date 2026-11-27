"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { getSupabaseClient } from "@/lib/supabase/client";
import { messaggioEsitoProposta, proposteDisponibili } from "@/lib/cantina/proposta-catalogo";
import {
  FORMATI,
  FORMATO_STANDARD,
  MAX_BOTTIGLIE_PER_AGGIUNTA,
  formatoValido,
  nuovaChiaveIdempotenza,
  quantitaDaTesto,
} from "@/lib/cantina/gruppo";
import { creaScortePartnerService } from "@/services/partner-scorte-service";
import { creaWineRegionsService } from "@/services/wine-regions-service";

const TIPI = ["Rosso", "Bianco", "Bollicine", "Rosato", "Dolce"];

/**
 * Aggiunta di scorte commerciali: N unità identiche dello stesso prodotto in
 * un'operazione sola (`scorte_partner_aggiungi`). La chiave d'idempotenza vale
 * per il gesto: un nuovo tentativo dopo una risposta persa non duplica.
 * Nessun costo d'acquisto e nessuna fotografia privata: è un catalogo.
 */
export function AggiungiScortePartner() {
  const router = useRouter();
  const [campi, setCampi] = useState({
    produttore: "",
    nome: "",
    annata: "",
    regione: "",
    tipo: "Rosso",
    formato: FORMATO_STANDARD as string,
    quantita: "6",
  });
  const [regioni, setRegioni] = useState<string[]>([]);
  const [inCorso, setInCorso] = useState(false);
  // WI-016: con le proposte spente il comando non compare; il consenso non è mai preselezionato.
  const [proposteAttive, setProposteAttive] = useState(false);
  const [consensoCatalogo, setConsensoCatalogo] = useState(false);
  const chiave = useRef(nuovaChiaveIdempotenza("scorte"));
  const set = (k: keyof typeof campi) => (v: string) => setCampi((c) => ({ ...c, [k]: v }));

  useEffect(() => {
    let attivo = true;
    void creaWineRegionsService(getSupabaseClient())
      .elenco()
      .then((esito) => {
        if (attivo && esito.ok) setRegioni(esito.data);
      });
    void proposteDisponibili(getSupabaseClient()).then((disponibili) => {
      if (attivo) setProposteAttive(disponibili);
    });
    return () => {
      attivo = false;
    };
  }, []);

  const invia = async () => {
    const annata = Number(campi.annata);
    const quantita = quantitaDaTesto(campi.quantita, MAX_BOTTIGLIE_PER_AGGIUNTA);
    if (!campi.produttore.trim() || !campi.nome.trim()) {
      toast.error("Indica produttore e nome del vino.");
      return;
    }
    if (!Number.isInteger(annata) || annata < 1800 || annata > 2100) {
      toast.error("Indica un'annata fra 1800 e 2100.");
      return;
    }
    if (!regioni.includes(campi.regione)) {
      toast.error("Scegli una Regione dall'elenco.");
      return;
    }
    if (!formatoValido(campi.formato) || quantita === null) {
      toast.error(`Indica formato e quantità (da 1 a ${MAX_BOTTIGLIE_PER_AGGIUNTA}).`);
      return;
    }
    setInCorso(true);
    try {
      const consensoDato = proposteAttive && consensoCatalogo;
      const esito = await creaScortePartnerService(getSupabaseClient()).aggiungi({
        produttore: campi.produttore.trim(),
        nome: campi.nome.trim(),
        annata,
        regione: campi.regione,
        tipo: campi.tipo,
        formato: campi.formato,
        quantita,
        idempotencyKey: chiave.current,
        ...(consensoDato ? { proponiAlCatalogo: true } : {}),
      });
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }
      chiave.current = nuovaChiaveIdempotenza("scorte");
      const avvisoCatalogo = messaggioEsitoProposta(esito.data.catalogo, {
        richiesta: consensoDato,
        ripetuta: esito.data.replay,
      });
      if (avvisoCatalogo) toast.info(avvisoCatalogo);
      // il consenso vale per UNA richiesta
      setConsensoCatalogo(false);
      toast.success(`${esito.data.quantita} unità aggiunte alle scorte`);
      setCampi((c) => ({ ...c, produttore: "", nome: "", annata: "", quantita: "6" }));
      router.refresh();
    } finally {
      setInCorso(false);
    }
  };

  return (
    <form
      className="grid gap-3 rounded-3xl border border-border bg-card p-4 md:grid-cols-2 md:p-6"
      data-testid="aggiungi-scorte"
      onSubmit={(e) => {
        e.preventDefault();
        void invia();
      }}
    >
      <p className="font-serif text-xl md:col-span-2">Aggiungi scorte</p>
      <div className="space-y-1">
        <Label htmlFor="scorte-produttore">Produttore</Label>
        <Input id="scorte-produttore" value={campi.produttore} onChange={(e) => set("produttore")(e.target.value)} />
      </div>
      <div className="space-y-1">
        <Label htmlFor="scorte-nome">Nome del vino</Label>
        <Input id="scorte-nome" value={campi.nome} onChange={(e) => set("nome")(e.target.value)} />
      </div>
      <div className="space-y-1">
        <Label htmlFor="scorte-annata">Annata</Label>
        <Input
          id="scorte-annata"
          type="number"
          inputMode="numeric"
          value={campi.annata}
          onChange={(e) => set("annata")(e.target.value)}
        />
      </div>
      <div className="space-y-1">
        <Label>Regione</Label>
        <Select value={campi.regione || undefined} onValueChange={set("regione")} disabled={regioni.length === 0}>
          <SelectTrigger aria-label="Regione">
            <SelectValue placeholder="Scegli la regione" />
          </SelectTrigger>
          <SelectContent>
            {regioni.map((r) => (
              <SelectItem key={r} value={r}>
                {r}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label>Tipologia</Label>
        <Select value={campi.tipo} onValueChange={set("tipo")}>
          <SelectTrigger aria-label="Tipologia">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {TIPI.map((t) => (
              <SelectItem key={t} value={t}>
                {t}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label>Formato</Label>
        <Select value={campi.formato} onValueChange={set("formato")}>
          <SelectTrigger aria-label="Formato">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {FORMATI.map((f) => (
              <SelectItem key={f} value={f}>
                {f}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label htmlFor="scorte-quantita">Unità</Label>
        <Input
          id="scorte-quantita"
          type="number"
          inputMode="numeric"
          min={1}
          max={MAX_BOTTIGLIE_PER_AGGIUNTA}
          step={1}
          value={campi.quantita}
          onChange={(e) => set("quantita")(e.target.value)}
        />
      </div>
      {proposteAttive ? (
        <label className="flex items-start gap-2 rounded-xl border border-border p-3 text-xs md:col-span-2">
          <input
            type="checkbox"
            className="mt-0.5"
            checked={consensoCatalogo}
            onChange={(e) => setConsensoCatalogo(e.target.checked)}
            data-testid="scorte-proposta-consenso"
          />
          <span>
            Proponi anche questo vino al catalogo condiviso di Vinea: solo produttore, nome, annata, regione, tipo e
            formato. Quantità e dati commerciali non vengono inviati; un curatore rivede la proposta.
          </span>
        </label>
      ) : null}
      <div className="flex items-end md:col-span-2">
        <Button type="submit" disabled={inCorso} className="bg-bordeaux hover:bg-bordeaux/90">
          Aggiungi alle scorte
        </Button>
      </div>
    </form>
  );
}
