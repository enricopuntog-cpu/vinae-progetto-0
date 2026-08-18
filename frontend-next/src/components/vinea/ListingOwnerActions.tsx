"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Pencil, PackageX, Info } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  createListingService,
  ETICHETTA_STATO,
  type AnnuncioProprietario,
} from "@/services/listing-service";
import { AVVISO_RIMOZIONE_IRREVERSIBILE, EFFETTO_RIMOZIONE } from "@/lib/annunci/rimozione";
import type { Wine } from "@/data/wines";

const CONDIZIONI: Wine["condizione"][] = ["Perfetto", "Ottimo", "Buono"];

/**
 * Il pannello che il venditore vede sul proprio annuncio, e nessun altro.
 *
 * Esiste perché fino a oggi non c'era **nessun** comando per togliere un
 * annuncio dalla vendita: la RPC `listing_sospendi` è in produzione dalla Fase
 * 6b e non aveva un chiamante. La pagina dell'annuncio è il posto giusto — è
 * dove il venditore arriva per guardare cosa vede chi compra.
 *
 * Non decide da sé chi è il proprietario: riceve `annuncio` solo quando la
 * lettura lato server, filtrata dalla RLS, ha restituito una riga. Chi non è il
 * venditore non ottiene quella riga e questo componente non viene montato. La
 * garanzia sta nella policy, non in questo componente.
 */
export function ListingOwnerActions({ annuncio }: { annuncio: AnnuncioProprietario }) {
  const router = useRouter();
  const service = useMemo(() => createListingService(getSupabaseClient()), []);
  const listingId = annuncio.wine.listingId ?? annuncio.wine.id;

  const [sospensioneAperta, setSospensioneAperta] = useState(false);
  const [modificaAperta, setModificaAperta] = useState(false);
  const [inCorso, setInCorso] = useState(false);

  const [prezzo, setPrezzo] = useState(String(annuncio.wine.prezzo));
  const [condizione, setCondizione] = useState<Wine["condizione"]>(annuncio.wine.condizione);
  const [conservazione, setConservazione] = useState(annuncio.wine.conservazione);
  const [storia, setStoria] = useState(annuncio.wine.storia);

  const rimuoviDallaVendita = async () => {
    setInCorso(true);
    try {
      const esito = await service.sospendi(listingId);
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }
      toast.success("Annuncio rimosso dalla vendita");
      setSospensioneAperta(false);
      // I dati restano: la pagina si ricarica sulla lettura del proprietario,
      // che non filtra sullo stato.
      router.refresh();
    } finally {
      setInCorso(false);
    }
  };

  const salvaModifiche = async () => {
    const centesimi = Math.round(Number(prezzo) * 100);
    if (!Number.isSafeInteger(centesimi) || centesimi <= 0) {
      toast.error("Inserisci un prezzo valido.");
      return;
    }

    setInCorso(true);
    try {
      const esito = await service.aggiorna(listingId, {
        prezzoCents: centesimi,
        condizione,
        conservazione: conservazione.trim(),
        storia: storia.trim(),
      });
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }
      toast.success("Annuncio aggiornato");
      setModificaAperta(false);
      router.refresh();
    } finally {
      setInCorso(false);
    }
  };

  return (
    <section className="rounded-2xl border border-oro/40 bg-oro/5 p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-medium">Il tuo annuncio</p>
          <p className="text-sm text-muted-foreground">
            Stato: <span className="font-medium">{ETICHETTA_STATO[annuncio.stato]}</span>
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          {annuncio.modificabile ? (
            <Button variant="outline" size="sm" onClick={() => setModificaAperta(true)}>
              <Pencil className="mr-1 h-4 w-4" /> Modifica
            </Button>
          ) : null}

          {annuncio.sospendibile ? (
            <Button variant="outline" size="sm" onClick={() => setSospensioneAperta(true)}>
              <PackageX className="mr-1 h-4 w-4" /> Rimuovi dalla vendita
            </Button>
          ) : null}
        </div>
      </div>

      {annuncio.stato === "sospeso" ? (
        <p className="mt-3 flex gap-2 text-sm text-muted-foreground">
          <Info className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            Questo annuncio non è più visibile a chi compra. Prezzo, fotografie e descrizione
            restano qui, e la bottiglia è di nuovo libera in Cantina: per rimetterla in vendita si
            crea un annuncio nuovo, perché un annuncio rimosso non torna in vendita.
          </span>
        </p>
      ) : null}

      {/* --- Rimozione dalla vendita -------------------------------------- */}
      <Dialog open={sospensioneAperta} onOpenChange={setSospensioneAperta}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rimuovere questo annuncio dalla vendita?</DialogTitle>
            {/*
              La domanda che si fa chi preme è «tornerà visibile?». La risposta
              onesta oggi è no: `sospeso` sta fuori dall'indice degli stati non
              terminali, `listing_pubblica` riparte solo da bozza o modifiche
              richieste, e nessuna funzione riporta un annuncio ad attivo. Dirlo
              qui costa una riga; scoprirlo dopo costa la fiducia.
            */}
            <DialogDescription>
              {EFFETTO_RIMOZIONE}
              <strong className="mt-2 block font-medium text-foreground">
                {AVVISO_RIMOZIONE_IRREVERSIBILE}
              </strong>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setSospensioneAperta(false)} disabled={inCorso}>
              Annulla
            </Button>
            <Button onClick={rimuoviDallaVendita} disabled={inCorso}>
              {inCorso ? "Rimozione…" : "Rimuovi dalla vendita"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Modifica ------------------------------------------------------ */}
      <Dialog open={modificaAperta} onOpenChange={setModificaAperta}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Modifica annuncio</DialogTitle>
            <DialogDescription>
              Produttore, nome, annata e regione appartengono alla bottiglia e non si cambiano da
              qui.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="prezzo-modifica">Prezzo (€)</Label>
              <Input
                id="prezzo-modifica"
                inputMode="decimal"
                value={prezzo}
                onChange={(e) => setPrezzo(e.target.value)}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="condizione-modifica">Condizione</Label>
              <Select
                value={condizione}
                onValueChange={(v) => setCondizione(v as Wine["condizione"])}
              >
                <SelectTrigger id="condizione-modifica">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CONDIZIONI.map((c) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="conservazione-modifica">Conservazione</Label>
              <Input
                id="conservazione-modifica"
                value={conservazione}
                onChange={(e) => setConservazione(e.target.value)}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="storia-modifica">Storia</Label>
              <Textarea
                id="storia-modifica"
                rows={4}
                value={storia}
                onChange={(e) => setStoria(e.target.value)}
              />
            </div>
          </div>

          <DialogFooter>
            <Button variant="ghost" onClick={() => setModificaAperta(false)} disabled={inCorso}>
              Annulla
            </Button>
            <Button onClick={salvaModifiche} disabled={inCorso}>
              {inCorso ? "Salvataggio…" : "Salva modifiche"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  );
}
