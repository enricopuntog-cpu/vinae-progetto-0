import type { SupabaseClient } from "@supabase/supabase-js";
import { createFakePackagingProvider } from "@/lib/packaging/fake-packaging-provider";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  OrderRecord,
  PackagingOption,
  PackagingProvider,
  PackagingService,
  Result,
} from "@/services/types";

type RigaListino = {
  codice: string;
  provider: string;
  modalita: PackagingOption["modalita"];
  etichetta: string;
  descrizione: string | null;
  prezzo_cents: number;
  richiede_punto: boolean;
  ordinamento: number;
};

/**
 * Il listino viene dalla **vista** `public_packaging_options`, mai dalla
 * tabella: la tabella non ha alcun `GRANT` verso i ruoli client, e la vista
 * espone otto colonne della sola versione corrente. Una colonna aggiunta domani
 * al listino resta privata finché qualcuno non la elenca nella vista di
 * proposito.
 *
 * Il prezzo che arriva di qui è **indicativo**: serve a mostrare un numero
 * prima che un ordine esista. L'importo che finisce sull'ordine lo rilegge
 * `order_checkout_reserve` dalla versione allora corrente, e quello è l'unico
 * autoritativo. Un client non manda mai un prezzo.
 */
const leggiListino = async (client: SupabaseClient): Promise<Result<PackagingOption[]>> => {
  const { data, error } = await client
    .from("public_packaging_options")
    .select(
      "codice,provider,modalita,etichetta,descrizione,prezzo_cents,richiede_punto,ordinamento",
    )
    .order("ordinamento", { ascending: true });

  if (error) return serviceError("public_packaging_options.select", error);

  const righe = (data ?? []) as RigaListino[];
  return {
    ok: true,
    data: righe.map((r) => ({
      codice: r.codice,
      provider: r.provider,
      modalita: r.modalita,
      etichetta: r.etichetta,
      descrizione: r.descrizione,
      prezzoCents: r.prezzo_cents,
      richiedePunto: r.richiede_punto,
    })),
  };
};

export type PackagingServiceOptions = {
  /**
   * Come si costruisce il provider a partire dal listino letto dal database.
   * Iniettabile per i test e, soprattutto, perché è **questa** la cucitura che
   * un fornitore vero sostituirà: al suo arrivo cambia questa funzione e non il
   * servizio, che continua a chiamare la stessa interfaccia.
   */
  provider?: (catalogo: PackagingOption[]) => PackagingProvider;
};

export const createPackagingService = (
  client: SupabaseClient | null,
  { provider = (catalogo) => createFakePackagingProvider({ catalogo }) }: PackagingServiceOptions = {},
): PackagingService => ({
  opzioni: async () => {
    if (!client) return noClient();
    return leggiListino(client);
  },

  punti: async ({ codice, cap }) => {
    if (!client) return noClient();
    const listino = await leggiListino(client);
    if (!listino.ok) return listino;
    return provider(listino.data).puntiVicini({ codice, cap });
  },

  /**
   * Il venditore dichiara il metodo sull'annuncio. Nessun prezzo fra i
   * parametri, e la scrittura non è un `update` diretto: `imballaggio_codice`
   * ha una regola di dominio dietro — dev'essere un codice della versione
   * corrente — quindi resta fuori dal `GRANT UPDATE` del client e ha una
   * `SECURITY DEFINER` come unica porta.
   */
  dichiaraSuAnnuncio: async (listingId, codice) => {
    if (!client) return noClient();
    const { error } = await client.rpc("listing_imballaggio_dichiara", {
      p_listing_id: listingId,
      p_codice: codice,
    });
    return error
      ? serviceError("listing_imballaggio_dichiara", error)
      : { ok: true, data: undefined };
  },

  /**
   * Il punto fisico si sceglie dopo il pagamento e **non ha prezzo**: è ciò che
   * permette al venditore di decidere dove consegnare senza che nessun importo
   * si muova. La RPC non scrive `imballaggio_cents`, per costruzione.
   */
  scegliPunto: async ({ orderId, puntoId, puntoNome }) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordine_imballaggio_punto_scegli", {
      p_order_id: orderId,
      p_punto_id: puntoId,
      p_punto_nome: puntoNome,
    });
    return error
      ? serviceError("ordine_imballaggio_punto_scegli", error)
      : { ok: true, data: data as OrderRecord };
  },
});
