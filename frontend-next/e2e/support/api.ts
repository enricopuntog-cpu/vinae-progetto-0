import { randomUUID } from "node:crypto";
import { risolviBersaglio } from "./stack";

/**
 * Porte reali dello stack locale (GoTrue, PostgREST, Storage) per PREPARARE lo
 * stato dei test. Le verifiche sul comportamento passano dal browser; qui si
 * costruisce soltanto il contesto, con le stesse porte che usa l'interfaccia.
 */

export const EMAIL = {
  rilascio: "u01@e2e-12zk.test",
  venditore: "u02@e2e-12zk.test",
  altro: "u03@e2e-12zk.test",
  segnalante: "u04@e2e-12zk.test",
  adminSenzaRilascio: "u05@e2e-12zk.test",
} as const;

export type Ruolo = keyof typeof EMAIL;

export const passwordFixture = (): string => {
  const password = process.env.E2E_PASSWORD;
  if (!password) throw new Error("E2E_PASSWORD assente: la fixture non è stata creata da questa corsa.");
  return password;
};

export interface Sessione {
  token: string;
  id: string;
}

export const accedi = async (ruolo: Ruolo): Promise<Sessione> => {
  const { apiUrl, anonKey } = risolviBersaglio();
  const res = await fetch(`${apiUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL[ruolo], password: passwordFixture() }),
  });
  const json = (await res.json().catch(() => ({}))) as { access_token?: string; user?: { id: string } };
  if (!res.ok || !json.access_token || !json.user) throw new Error(`Accesso fallito per ${ruolo}: HTTP ${res.status}`);
  return { token: json.access_token, id: json.user.id };
};

export interface RispostaRpc<T = unknown> {
  status: number;
  body: T;
  ok: boolean;
}

export const rpc = async <T = unknown>(nome: string, args: object, sessione?: Sessione): Promise<RispostaRpc<T>> => {
  const { apiUrl, anonKey } = risolviBersaglio();
  const res = await fetch(`${apiUrl}/rest/v1/rpc/${nome}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${sessione?.token ?? anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const testo = await res.text();
  let body: unknown = null;
  try {
    body = testo ? JSON.parse(testo) : null;
  } catch {
    body = testo;
  }
  return { status: res.status, body: body as T, ok: res.status >= 200 && res.status < 300 };
};

export const BUCKET_FOTO = "cantina-accessori-foto";

/** WebP 1x1 valido: basta al bucket, che accetta WebP fino a 2 MB. */
export const WEBP_MINIMO = Buffer.from("UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA", "base64");

export const caricaFoto = async (sessione: Sessione, percorso: string): Promise<number> => {
  const { apiUrl, anonKey } = risolviBersaglio();
  const res = await fetch(`${apiUrl}/storage/v1/object/${BUCKET_FOTO}/${percorso}`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${sessione.token}`, "Content-Type": "image/webp" },
    body: new Uint8Array(WEBP_MINIMO),
  });
  return res.status;
};

/** Richiede una URL firmata per una foto; `status >= 400` = firma negata. */
export const firmaFoto = async (percorso: string, sessione?: Sessione): Promise<number> => {
  const { apiUrl, anonKey } = risolviBersaglio();
  const res = await fetch(`${apiUrl}/storage/v1/object/sign/${BUCKET_FOTO}/${percorso}`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${sessione?.token ?? anonKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: 60 }),
  });
  return res.status;
};

/** Accende la visibilità pubblica degli accessori esposti (porta del ruolo di rilascio). */
export const accendiVisibilitaCantina = async (): Promise<void> => {
  const rilascio = await accedi("rilascio");
  const esito = await rpc(
    "cantina_accessori_admin_imposta",
    { p_interruttore: "visibilita_pubblica", p_attiva: true, p_motivo: "prova browser E2E" },
    rilascio,
  );
  if (!esito.ok) throw new Error(`Visibilità Cantina non accesa: HTTP ${esito.status}`);
};

interface CategoriaPubblicazione {
  id: string;
  slug: string;
}

/**
 * Accende i tre interruttori e approva le categorie con le porte del ruolo di
 * rilascio, come farebbe il titolare: nulla è acceso dalla migrazione e nulla
 * resta acceso dopo la pulizia.
 */
export const accendiPubblicazione = async (): Promise<void> => {
  const rilascio = await accedi("rilascio");
  const motivo = "prova browser E2E";
  const accesi = [
    await rpc("cantina_accessori_admin_imposta", { p_interruttore: "funzione", p_attiva: true, p_motivo: motivo }, rilascio),
    await rpc("annunci_accessori_admin_imposta", { p_attiva: true, p_motivo: motivo }, rilascio),
    await rpc("annunci_accessori_admin_pubblicazione_imposta", { p_attiva: true, p_motivo: motivo }, rilascio),
  ];
  if (!accesi.every((r) => r.ok)) throw new Error(`Interruttori non accesi: ${accesi.map((r) => r.status).join(",")}`);

  const categorie = await rpc<CategoriaPubblicazione[]>("annunci_accessori_admin_categorie_pubblicazione", {}, rilascio);
  const idCategoria = (slug: string): string => {
    const id = categorie.body.find((c) => c.slug === slug)?.id;
    if (!id) throw new Error(`Categoria ${slug} assente.`);
    return id;
  };
  for (const slug of ["calici", "calici-da-rosso"]) {
    const esito = await rpc(
      "annunci_accessori_admin_categoria_pubblicabile_imposta",
      { p_categoria: idCategoria(slug), p_pubblicabile: true, p_motivo: motivo },
      rilascio,
    );
    if (!esito.ok) throw new Error(`Categoria ${slug} non approvata: HTTP ${esito.status}`);
  }
};

export const idCategoriaCalici = async (): Promise<string> => {
  const rilascio = await accedi("rilascio");
  const categorie = await rpc<CategoriaPubblicazione[]>("annunci_accessori_admin_categorie_pubblicazione", {}, rilascio);
  const id = categorie.body.find((c) => c.slug === "calici-da-rosso")?.id;
  if (!id) throw new Error("Categoria calici-da-rosso assente.");
  return id;
};

export interface AnnuncioPreparato {
  cantinaId: string;
  annuncioId: string;
  percorsoFoto: string;
}

/**
 * Il venditore ha 6 calici in Cantina e ne mette in vendita 2 a 20,00 €
 * (stesso contesto della prova 12zk: preventivo atteso 2273 centesimi).
 */
export const pubblicaAnnuncioPreparato = async (nome: string): Promise<AnnuncioPreparato> => {
  const venditore = await accedi("venditore");
  const categoriaId = await idCategoriaCalici();
  const cantinaId = randomUUID();
  const creato = await rpc(
    "cantina_accessori_salva",
    {
      p_id: cantinaId,
      p_dati: { categoria_id: categoriaId, nome, quantita: 6, note: "NOTA-PRIVATA-E2E", condizione: "usato" },
    },
    venditore,
  );
  if (!creato.ok) throw new Error(`Accessorio non creato: HTTP ${creato.status}`);

  const percorsoFoto = `${venditore.id}/${cantinaId}/${randomUUID()}.webp`;
  if ((await caricaFoto(venditore, percorsoFoto)) >= 300) throw new Error("Foto non caricata.");
  const collegata = await rpc("cantina_accessori_immagini_imposta", { p_id: cantinaId, p_percorsi: [percorsoFoto] }, venditore);
  if (!collegata.ok) throw new Error(`Foto non collegata: HTTP ${collegata.status}`);

  const annuncioId = randomUUID();
  const bozza = await rpc(
    "annunci_accessori_salva",
    {
      p_id: annuncioId,
      p_dati: { cantina_id: cantinaId, quantita: 2, prezzo_unitario_cents: 2000, condizione: "come_nuovo", descrizione: "Due calici.", conforme: true },
    },
    venditore,
  );
  if (!bozza.ok) throw new Error(`Bozza non creata: HTTP ${bozza.status}`);
  const pubblicato = await rpc("annunci_accessori_pubblica", { p_id: annuncioId }, venditore);
  if (!pubblicato.ok) throw new Error(`Annuncio non pubblicato: HTTP ${pubblicato.status}`);
  return { cantinaId, annuncioId, percorsoFoto };
};
