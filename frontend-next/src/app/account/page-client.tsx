"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { Camera, Check, LogOut, Trash2 } from "lucide-react";
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
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { esperienzaLabels, type Esperienza } from "@/data/onboarding";
import {
  CATALOGO_AVATAR,
  avatarSicuro,
  inizialiDa,
  percorsoAvatarPersonale,
} from "@/lib/profilo/avatar";
import { preparaFotoAvatar } from "@/lib/profilo/prepara-foto-avatar";
import { salvaProfiloConAvatar } from "@/lib/profilo/salva-avatar";
import { supabaseProfileService } from "@/services/profile-service";
import type { ProfiloCorrente } from "@/services/types";
import AttivitaVendita from "./attivita-vendita";
import SaldoVineaPanel from "./saldo-vinea";
import QualificheProfessionali from "./qualifiche-professionali";

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
 * L'avatar resta sempre Vinea: uno dei sei preset locali oppure una foto
 * preparata nel browser e salvata nel bucket dedicato. URL esterni e percorsi di
 * un altro profilo non arrivano né alla persistenza né al rendering.
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
  const [fotoPreparata, setFotoPreparata] = useState<File | null>(null);
  const [anteprimaFoto, setAnteprimaFoto] = useState<string | null>(null);
  const [preparazioneInCorso, setPreparazioneInCorso] = useState(false);
  const [inCorso, setInCorso] = useState(false);
  const [erroreFoto, setErroreFoto] = useState<string | null>(null);
  const [avvisoPulizia, setAvvisoPulizia] = useState<string | null>(null);
  const [salvato, setSalvato] = useState(false);
  const selettoreFoto = useRef<HTMLInputElement>(null);

  useEffect(
    () => () => {
      if (anteprimaFoto) URL.revokeObjectURL(anteprimaFoto);
    },
    [anteprimaFoto],
  );

  const campo = <K extends keyof ProfiloCorrente>(chiave: K): ProfiloCorrente[K] | undefined =>
    (modifiche[chiave] ?? authProfilo?.[chiave]) as ProfiloCorrente[K] | undefined;

  const aggiorna = <K extends keyof ProfiloCorrente>(chiave: K, valore: ProfiloCorrente[K]) => {
    setModifiche((precedenti) => ({ ...precedenti, [chiave]: valore }));
    setSalvato(false);
    setAvvisoPulizia(null);
  };

  const scartaFotoPreparata = () => {
    setFotoPreparata(null);
    setAnteprimaFoto(null);
    if (selettoreFoto.current) selettoreFoto.current.value = "";
  };

  const scegliAvatar = (valore: string) => {
    scartaFotoPreparata();
    setErroreFoto(null);
    aggiorna("avatarUrl", valore);
  };

  const preparaFoto = async (file: File | undefined) => {
    if (!file) return;
    setPreparazioneInCorso(true);
    setErroreFoto(null);
    setSalvato(false);
    setAvvisoPulizia(null);
    try {
      const preparata = await preparaFotoAvatar(file);
      const anteprima = URL.createObjectURL(preparata);
      setFotoPreparata(preparata);
      setAnteprimaFoto(anteprima);
    } catch (errore) {
      scartaFotoPreparata();
      setErroreFoto(errore instanceof Error ? errore.message : "Foto non valida.");
    } finally {
      setPreparazioneInCorso(false);
    }
  };

  const username = (campo("username") ?? "") as string;
  const bio = (campo("bio") ?? "") as string;
  const citta = (campo("citta") ?? "") as string;
  const provincia = (campo("provincia") ?? "") as string;
  const esperienza = (campo("esperienza") ?? "curioso") as Esperienza;
  const avatarUrl = (campo("avatarUrl") ?? "") as string;
  const avatarPersonale = percorsoAvatarPersonale(avatarUrl, authProfilo?.userId);
  const avatarDaMostrare = anteprimaFoto ?? avatarSicuro(avatarUrl, authProfilo?.userId);
  const usernameValido = username.trim().length >= 3;
  const bioValida = bio.length <= MAX_BIO;
  const modificato = Object.keys(modifiche).length > 0 || fotoPreparata !== null;
  const occupato = inCorso || preparazioneInCorso;
  const puoSalvare = usernameValido && bioValida && modificato && !occupato;

  const salva = async () => {
    if (!puoSalvare || !authProfilo) return;
    setInCorso(true);
    setErroreFoto(null);
    setAvvisoPulizia(null);
    const esito = await salvaProfiloConAvatar(
      {
        profiloId: authProfilo.userId,
        avatarPrecedente: authProfilo.avatarUrl,
        nuovaFoto: fotoPreparata,
        patch: {
          username: username.trim(),
          bio,
          citta,
          provincia,
          esperienza,
          avatarUrl,
        },
      },
      {
        caricaFoto: (file) => supabaseProfileService.caricaFotoAvatar(file),
        aggiornaProfilo: authAggiornaProfilo,
        eliminaFoto: (percorso) => supabaseProfileService.eliminaFotoAvatar(percorso),
      },
    );
    setInCorso(false);
    if (!esito.ok) {
      setErroreFoto(esito.error);
      return;
    }

    // Le modifiche locali si svuotano solo dopo che il server ha risposto con
    // la riga vera: da lì in poi `authProfilo` è la fonte. La pulizia Storage può
    // invece fallire dopo un UPDATE valido e resta quindi un avviso separato.
    scartaFotoPreparata();
    setModifiche({});
    setAvvisoPulizia(esito.data.avvisoPulizia);
    setSalvato(true);
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
            {/*
              Con `?next=`: chi è stato fermato qui torna qui dopo l'accesso,
              con la password, con il magic link o con Google. Il percorso è
              scritto per esteso perché è noto staticamente — stessa forma e
              stessa ragione di /vendite.
            */}
            <Link href={`/accedi?${PARAMETRO_NEXT}=%2Faccount`}>Vai all&apos;accesso</Link>
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
              <div
                className={`flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full border bg-crema ${
                  anteprimaFoto || avatarPersonale ? "border-bordeaux" : "border-border"
                }`}
              >
                {avatarDaMostrare ? (
                  anteprimaFoto || avatarPersonale ? (
                    <img
                      src={avatarDaMostrare}
                      alt="Foto profilo scelta"
                      className="h-16 w-16 object-cover"
                    />
                  ) : (
                    <Image
                      src={avatarDaMostrare}
                      alt="Avatar scelto"
                      width={64}
                      height={64}
                      className="h-16 w-16"
                    />
                  )
                ) : (
                  <span className="font-serif text-lg text-bordeaux">
                    {inizialiDa(username || authProfilo.username)}
                  </span>
                )}
              </div>
              <div className="min-w-0 flex-1 space-y-3">
                <div className="flex flex-wrap gap-2">
                  {CATALOGO_AVATAR.map((voce) => {
                    const scelto = !fotoPreparata && avatarUrl === voce.percorso;
                    return (
                      <button
                        key={voce.id}
                        type="button"
                        onClick={() => scegliAvatar(scelto ? "" : voce.percorso)}
                        disabled={occupato}
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
                <div className="flex flex-wrap gap-2">
                  <input
                    ref={selettoreFoto}
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    className="sr-only"
                    onChange={(evento) => preparaFoto(evento.target.files?.[0])}
                  />
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={occupato}
                    onClick={() => selettoreFoto.current?.click()}
                  >
                    <Camera className="h-4 w-4" />
                    {preparazioneInCorso
                      ? "Preparazione…"
                      : anteprimaFoto || avatarPersonale
                        ? "Sostituisci foto"
                        : "Carica una foto"}
                  </Button>
                  {(anteprimaFoto || avatarPersonale) && (
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      disabled={occupato}
                      onClick={() => scegliAvatar("")}
                    >
                      <Trash2 className="h-4 w-4" /> Rimuovi foto
                    </Button>
                  )}
                </div>
              </div>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              JPEG, PNG o WebP fino a 5 MB. La foto viene ritagliata al centro,
              ridimensionata e ripulita dai metadati prima del caricamento. Ripremi
              il preset scelto per tornare alle iniziali.
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
              {!usernameValido ? (
                <p className="mt-1 text-xs text-bordeaux">Almeno 3 caratteri.</p>
              ) : (
                <p className="mt-1 text-xs text-muted-foreground">
                  Un nome già usato non torna disponibile cambiando maiuscole o minuscole.
                </p>
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

          {(erroreFoto || authError) && (
            <p className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
              {erroreFoto ?? authError}
            </p>
          )}

          {avvisoPulizia && (
            <p className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm text-antracite">
              {avvisoPulizia}
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
              fotoPreparata ? "Caricamento e salvataggio…" : "Salvataggio…"
            ) : (
              <>
                <Check className="h-4 w-4" /> Salva modifiche
              </>
            )}
          </Button>
        </div>
      </div>

      {/*
        Una scheda separata, non un blocco dentro il modulo di modifica: tutto
        quello che sta sopra si cambia, questo si legge e basta. Metterlo fra i
        campi avrebbe suggerito che si possa toccare.

        Ha anche una ragione di robustezza: la sezione fa due letture di rete
        proprie, e il loro esito non tocca nessuno stato di questo modulo. Se
        falliscono, qui sopra non cambia nulla.
      */}
      <AttivitaVendita />
      <SaldoVineaPanel />
      <QualificheProfessionali />
    </div>
  );
}
