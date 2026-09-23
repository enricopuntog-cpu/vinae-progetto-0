"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import Link from "next/link";
import { PERCORSO_SICUREZZA, erroreRichiedeMfa } from "@/lib/auth/mfa";
import { getSupabaseClient } from "@/lib/supabase/client";
import type { IncidentNoticeKind } from "@/lib/incidents/notice";

const KINDS: Array<{ value: IncidentNoticeKind; label: string }> = [
  { value: "manutenzione", label: "Manutenzione" },
  { value: "degrado", label: "Servizio degradato" },
  { value: "incidente", label: "Incidente" },
  { value: "sicurezza", label: "Sicurezza" },
];

export function IncidentNoticeAdmin() {
  const [kind, setKind] = useState<IncidentNoticeKind>("manutenzione");
  const [message, setMessage] = useState("");
  const [statusUrl, setStatusUrl] = useState("");
  const [active, setActive] = useState(true);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; message: string; mfa?: boolean } | null>(null);

  const save = async () => {
    const client = getSupabaseClient();
    if (!client) {
      setResult({ ok: false, message: "Connessione a Supabase non configurata." });
      return;
    }
    setBusy(true);
    setResult(null);
    try {
      const { error } = await client.rpc("incident_notice_set", {
        p_kind: kind,
        p_message: message.trim(),
        p_status_url: statusUrl.trim() || null,
        p_active: active,
      });
      // Sessione scaduta o nuova in aal1: il database rifiuta il delegato con
      // hint aal2_required. Si rimanda alla verifica, non a un errore generico.
      setResult(
        erroreRichiedeMfa(error)
          ? { ok: false, message: "Serve la verifica in due passaggi per questa sessione.", mfa: true }
          : error
          ? { ok: false, message: "Non e stato possibile aggiornare il banner." }
          : {
              ok: true,
              message: active ? "Banner operativo pubblicato." : "Banner operativo disattivato.",
            },
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="space-y-3 rounded-xl border bg-card p-4" data-testid="incident-admin">
      <div>
        <h2 className="font-serif text-xl">Comunicazione incidente</h2>
        <p className="text-xs text-muted-foreground">
          Il messaggio compare globalmente. Usa la pagina di stato solo quando e ospitata fuori
          dall&apos;infrastruttura principale.
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-[220px_1fr]">
        <label className="text-sm">
          <span className="mb-1 block font-medium">Tipo</span>
          <select
            value={kind}
            onChange={(event) => setKind(event.target.value as IncidentNoticeKind)}
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          >
            {KINDS.map((item) => (
              <option key={item.value} value={item.value}>{item.label}</option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          <span className="mb-1 block font-medium">URL pagina di stato HTTPS</span>
          <input
            type="url"
            value={statusUrl}
            onChange={(event) => setStatusUrl(event.target.value)}
            placeholder="https://status.vineawineclub.com"
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
      </div>
      <div>
        <Label htmlFor="incident-message">Messaggio</Label>
        <Textarea
          id="incident-message"
          value={message}
          onChange={(event) => setMessage(event.target.value)}
          maxLength={500}
          rows={3}
          placeholder="Descrivi l'impatto e dove trovare gli aggiornamenti."
        />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={active} onChange={(event) => setActive(event.target.checked)} />
        Banner attivo
      </label>
      {result ? (
        <p role={result.ok ? "status" : "alert"} className={result.ok ? "text-sm" : "text-sm text-bordeaux"}>
          {result.message}
          {result.mfa ? (
            <>
              {" "}
              <Link href={PERCORSO_SICUREZZA} className="underline">
                Completa la verifica
              </Link>
            </>
          ) : null}
        </p>
      ) : null}
      <Button
        onClick={() => void save()}
        disabled={busy || message.trim().length < 10}
        className="bg-bordeaux hover:bg-bordeaux/90"
      >
        {busy ? "Salvataggio…" : active ? "Pubblica banner" : "Disattiva banner"}
      </Button>
    </section>
  );
}
