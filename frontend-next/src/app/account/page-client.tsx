"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import { Check, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
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
import { useVinea } from "@/lib/vinea-store";
import { esperienzaLabels, type Esperienza } from "@/data/onboarding";
import { CATALOGO_AVATAR, avatarSicuro, inizialiDa } from "@/lib/profilo/avatar";
import type { ProfiloCorrente } from "@/services/types";

const ESPERIENZE = Object.keys(esperienzaLabels) as Esperienza[];

const MAX_BIO = 500;

/**
 * Modifica del proprio profilo su dati reali.
 *
 * Prima di questa schermata la voce «Account» dell'header portava a /accedi,
 * che da autenticati mostrava soltanto «Sei autenticato» ed «Esci»: nessun
 * percorso permetteva di cambiare presentazione, città o avatar, benché le
 * colonne e la policy `profiles_update_own` esistessero dalla Fase 5a.
 *
 * NON riusa `useProfileDomain()` della versione storica: quello tiene un
 * profilo dimostrativo in memoria (`profiloDemoIniziale`, «demo: user già
 * registrato») e non scrive da nessuna parte. Qui ogni campo arriva da
 * `public.profiles` e ci torna, con `auth.uid()` come unico filtro.
 *
 * L'avatar è scelto da un insieme curato servito da noi, mai da un servizio
 * esterno: il perché — e perché il caricamento di una foto propria è rimandato
 * a una decisione sua — sta in `lib/profilo/avatar.ts`.
 */
export default function AccountPageClient() {
  const {
    authUser,
    authLoading,
    authError,
    authProfilo,
    authProfileLoading,
    authAggiornaProfilo,
    authLogout,
  } = useVinea();

  // Le modifiche vivono accanto al profilo letto, non al posto suo: finché un
  // campo non viene toccato mostra il valore del database. Derivazione e non
  // effect, per la stessa ragione spiegata in /completa-profilo.
  const [modifiche, setModifiche] = useState<Partial<ProfiloCorrente>>({});
  const [inCorso, setInCorso] = useState(false);
  const [salvato, setSalvato] = useState(false);

  const campo = <K extends keyof ProfiloCorrente>(chiave: K): ProfiloCorrente[K] | undefined =>
    (modifiche[chiave] ?? authProfilo?.[chiave]) as ProfiloCorrente[K] | undefined;

  const aggiorna = <K extends keyof ProfiloCorrente>(chiave: K, valore: ProfiloCorrente[K]) => {
    setModifiche((precedenti) => ({ ...precedenti, [chiave]: valore }));
    setSalvato(false);
  };

  const username = (campo("username") ?? "") as string;
  const bio = (campo("bio") ?? "") as string;
  const citta = (campo("citta") ?? "") as string;
  const provincia = (campo("provincia") ?? "") as string;
  const esperienza = (campo("esperienza") ?? "curioso") as Esperienza;
  const avatarUrl = (campo("avatarUrl") ?? "") as string;

  const avatarDaMostrare = avatarSicuro(avatarUrl);
  const usernameValido = username.trim().length >= 3;
  const bioValida = bio.length <= MAX_BIO;
  const modificato = Object.keys(modifiche).length > 0;
  const puoSalvare = usernameValido && bioValida && modificato && !inCorso;

  const salva = async () => {
    if (!puoSalvare) return;
    setInCorso(true);
    const esito = await authAggiornaProfilo({
      username: username.trim(),
      bio,
      citta,
      provincia,
      esperienza,
      avatarUrl,
    });
    setInCorso(false);
    if (esito.ok) {
      // Le modifiche locali si svuotano solo dopo che il server ha risposto con
      // la riga vera: da lì in poi `authProfilo` è la fonte, e tenere anche una
      // copia locale significherebbe due verità sullo stesso campo.
      setModifiche({});
      setSalvato(true);
    }
  };

  if (authLoading) {
    return (
      <div className="mx-auto max-w-2xl">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <p className="text-sm text-muted-foreground">Verifica della sessione…</p>
        </div>
      </div>
    );
  }

  if (!authUser) {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Serve prima l&apos;accesso</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Il profilo è personale: accedi per vederlo e modificarlo.
          </p>
          <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90">
            <Link href="/accedi">Vai all&apos;accesso</Link>
          </Button>
        </div>
      </div>
    );
  }

  if (authProfileLoading) {
    return (
      <div className="mx-auto max-w-2xl">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <p className="text-sm text-muted-foreground">Caricamento del profilo…</p>
        </div>
      </div>
    );
  }

  if (!authProfilo) {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Profilo non disponibile</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Non siamo riusciti a leggere il tuo profilo. Riprova fra poco.
          </p>
          {authError && (
            <p className="mt-4 rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
              {authError}
            </p>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            <h1 className="font-serif text-2xl md:text-3xl">Il tuo profilo</h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Account: <b className="break-all">{authProfilo.email ?? authUser.userId}</b>
            </p>
          </div>
          <Button variant="outline" data-testid="logout" onClick={() => authLogout()}>
            <LogOut className="h-4 w-4" /> Esci
          </Button>
        </div>

        <div className="mt-6 space-y-6">
          <div>
            <Label>Avatar</Label>
            <div className="mt-2 flex flex-wrap items-center gap-3">
              <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-crema">
                {avatarDaMostrare ? (
                  <Image
                    src={avatarDaMostrare}
                    alt="Avatar scelto"
                    width={64}
                    height={64}
                    className="h-16 w-16"
                  />
                ) : (
                  <span className="font-serif text-lg text-bordeaux">
                    {inizialiDa(username || authProfilo.username)}
                  </span>
                )}
              </div>
              <div className="flex flex-wrap gap-2">
                {CATALOGO_AVATAR.map((voce) => {
                  const scelto = avatarUrl === voce.percorso;
                  return (
                    <button
                      key={voce.id}
                      type="button"
                      onClick={() => aggiorna("avatarUrl", scelto ? "" : voce.percorso)}
                      aria-pressed={scelto}
                      aria-label={voce.etichetta}
                      title={voce.etichetta}
                      className={`h-11 w-11 overflow-hidden rounded-full border-2 transition ${
                        scelto ? "border-bordeaux" : "border-transparent hover:border-oro"
                      }`}
                    >
                      <Image
                        src={voce.percorso}
                        alt={voce.etichetta}
                        width={44}
                        height={44}
                        className="h-11 w-11"
                      />
                    </button>
                  );
                })}
              </div>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              Ripremi l&apos;avatar scelto per tornare alle iniziali.
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label htmlFor="username">Nome utente</Label>
              <Input
                id="username"
                value={username}
                onChange={(e) => aggiorna("username", e.target.value)}
                autoComplete="username"
              />
              {!usernameValido && (
                <p className="mt-1 text-xs text-bordeaux">Almeno 3 caratteri.</p>
              )}
            </div>
            <div>
              <Label htmlFor="esperienza">Livello di esperienza</Label>
              <Select
                value={esperienza}
                onValueChange={(valore) => aggiorna("esperienza", valore as Esperienza)}
              >
                <SelectTrigger id="esperienza">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ESPERIENZE.map((valore) => (
                    <SelectItem key={valore} value={valore}>
                      {esperienzaLabels[valore]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="citta">Città</Label>
              <Input
                id="citta"
                value={citta}
                onChange={(e) => aggiorna("citta", e.target.value)}
                placeholder="es. Milano"
                autoComplete="address-level2"
              />
            </div>
            <div>
              <Label htmlFor="provincia">Provincia</Label>
              <Input
                id="provincia"
                value={provincia}
                onChange={(e) => aggiorna("provincia", e.target.value)}
                placeholder="es. MI"
                autoComplete="address-level1"
              />
            </div>
          </div>

          <div>
            <Label htmlFor="bio">Presentazione</Label>
            <Textarea
              id="bio"
              value={bio}
              onChange={(e) => aggiorna("bio", e.target.value)}
              placeholder="Due righe su di te e sui vini che ti piacciono."
              rows={4}
            />
            <p className={`mt-1 text-xs ${bioValida ? "text-muted-foreground" : "text-bordeaux"}`}>
              {bio.length} / {MAX_BIO} caratteri
            </p>
          </div>

          {authError && (
            <p className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
              {authError}
            </p>
          )}

          {salvato && !modificato && (
            <p className="rounded-xl border border-oro/30 bg-oro/5 p-3 text-sm text-antracite/80">
              Profilo aggiornato.
            </p>
          )}

          <Button
            onClick={salva}
            disabled={!puoSalvare}
            className="bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso ? (
              "Salvataggio…"
            ) : (
              <>
                <Check className="h-4 w-4" /> Salva modifiche
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}
