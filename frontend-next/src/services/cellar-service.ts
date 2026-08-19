/**
 * CellarService reale su Supabase — Fase 6c-2.
 *
 * UNA BOTTIGLIA È UNA RIGA. Nei dati mock una `CellarBottle` porta un campo
 * `quantita` (2, 4, 3…) e un solo `storageLocationId`: una pila di quattro
 * Sassicaia sta in un foro solo. Nello schema reale `bottle_units` è per unità
 * e `cellar_slots` tiene una posizione per bottiglia, e nessun percorso di
 * codice ha mai creato una pila — il wizard di Fase 6b conia un'unità per
 * volta. Qui `quantita` vale quindi 1 per una bottiglia ancora chiusa e 0 per
 * una aperta o consumata: è la traduzione fedele dei comportamenti che nel mock
 * dipendevano da quel numero (il totale in cantina, il valore stimato, il
 * decremento all'apertura, la penalità nella ricerca per abbinamento), senza
 * introdurre un raggruppamento che il database non ha.
 *
 * IL PREZZO VIENE DALL'ANNUNCIO, non dal catalogo. In `wines` un prezzo non
 * esiste: appartiene a `listings`. Dalla 6d-2a una bottiglia privata o pubblica
 * può non avere annunci; in quel caso il valore resta zero invece di inventare
 * una stima.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CellarBottle,
  StorageEnvironment,
  StorageModule,
  StorageSlot,
  WineVintageMeta,
} from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { rigaAMeta, type RigaMetaVino } from "@/services/wine-meta";
import { urlImmagine } from "@/services/listing-service";
import { STATI_BLOCCANTI_APERTURA } from "@/lib/cantina/apertura";
import type {
  CellarService,
  DatiCantina,
  DatiNuovaBottiglia,
  DatiNuovoAmbiente,
  OverrideFinestra,
  Result,
} from "@/services/types";

const IMMAGINE_ASSENTE = "/images/vinea-bottle-1.jpg";
export const BUCKET_CANTINA = "cantina";

const CANTINA_VUOTA: DatiCantina = {
  bottiglie: [],
  vini: [],
  metaPerVino: {},
  ambienti: [],
  moduli: [],
};

// -- Righe come arrivano da PostgREST ---------------------------------------

type RigaModulo = {
  id: string;
  environment_id: string;
  etichetta: string;
  posizione_x: number;
  posizione_y: number;
  posizione_z: number;
  rotazione_y: number;
  righe: number;
  colonne: number;
  profondita: number;
};

type RigaAmbiente = {
  id: string;
  nome: string;
  forma: StorageEnvironment["shape"];
  tema: StorageEnvironment["theme"];
  materiale: StorageEnvironment["material"];
  illuminazione: StorageEnvironment["lighting"];
  larghezza_cm: number;
  altezza_cm: number;
  profondita_cm: number;
  cellar_modules: RigaModulo[] | null;
};

type RigaAnnuncio = {
  id: string;
  slug: string;
  stato: string;
  prezzo_cents: number;
  prezzo_mercato_cents: number | null;
  condizione: string;
  conservazione: string;
  storia: string;
  degustazione: string;
  immagini: string[] | null;
  tag: string[] | null;
  created_at: string;
};

type RigaSlot = { module_id: string; riga: number; colonna: number };

type RigaVinoCantina = RigaMetaVino & {
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  denominazione: string;
  tipo: string;
  formato: string;
  provenienza: "staff" | "utente";
};

type RigaBottiglia = {
  id: string;
  stato: "chiusa" | "aperta" | "consumata";
  visibilita: "privata" | "cantina_pubblica";
  apertura_pianificata: string | null;
  note_personali: string;
  degustazione_nota: string;
  degustazione_at: string | null;
  prezzo_visibilita: CellarBottle["priceVisibility"];
  override_finestra_inizio: number | null;
  override_finestra_fine: number | null;
  override_apice_inizio: number | null;
  override_apice_fine: number | null;
  override_preferenza: "giovane" | "equilibrato" | "evoluto" | null;
  override_nota: string;
  ceduta_at: string | null;
  immagini: string[] | null;
  created_at: string;
  wines: RigaVinoCantina | RigaVinoCantina[] | null;
  cellar_slots: RigaSlot | RigaSlot[] | null;
  listings: RigaAnnuncio[] | null;
};

const COLONNE_AMBIENTI = `
  id, nome, forma, tema, materiale, illuminazione,
  larghezza_cm, altezza_cm, profondita_cm,
  cellar_modules (
    id, environment_id, etichetta,
    posizione_x, posizione_y, posizione_z, rotazione_y,
    righe, colonne, profondita
  )
`;

const COLONNE_BOTTIGLIE = `
  id, stato, visibilita, apertura_pianificata, note_personali, prezzo_visibilita,
  degustazione_nota, degustazione_at,
  override_finestra_inizio, override_finestra_fine,
  override_apice_inizio, override_apice_fine,
  override_preferenza, override_nota, ceduta_at, immagini, created_at,
  wines!inner (
    slug, produttore, nome, annata, regione, denominazione, tipo, formato,
    provenienza,
    finestra_inizio, finestra_fine, apice_inizio, apice_fine,
    finestra_fonte, finestra_affidabilita, finestra_aggiornata_at,
    temperatura_servizio, decantazione_minuti, calice, occasione, abbinamenti
  ),
  cellar_slots ( module_id, riga, colonna ),
  listings ( id, slug, stato, prezzo_cents, prezzo_mercato_cents, condizione,
             conservazione, storia, degustazione, immagini, tag, created_at )
`;

/**
 * PostgREST restituisce un oggetto quando la relazione è uno-a-uno e un elenco
 * quando è uno-a-molti, e la distinzione dipende da come riconosce i vincoli.
 * `cellar_slots` ha un unico su `bottle_unit_id` e dovrebbe arrivare come
 * oggetto: normalizzare qui evita che un cambio di versione trasformi la
 * posizione delle bottiglie in `undefined` senza che nulla protesti.
 */
function primo<T>(valore: T | T[] | null | undefined): T | null {
  if (valore === null || valore === undefined) return null;
  return Array.isArray(valore) ? (valore[0] ?? null) : valore;
}

/**
 * L'annuncio che rappresenta la bottiglia: quello vivo se c'è, altrimenti il
 * più recente. Serve solo per prezzo, foto e collegamento alla scheda — lo
 * stato di vendita si calcola sull'insieme, non su questo.
 */
function annuncioRappresentativo(annunci: RigaAnnuncio[]): RigaAnnuncio | null {
  if (annunci.length === 0) return null;
  const vivo = annunci.find((a) => a.stato === "attivo" || a.stato === "riservato");
  if (vivo) return vivo;
  return [...annunci].sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
}

/**
 * `SaleStatus` resta derivato, come deciso in 6a: `in_vendita` e `venduta` non
 * sono colonne di `bottle_units`, sono fatti che vivono in `listings`.
 *
 * L'eccezione arriva con la 6d-1: `ceduta_at` dice che l'unità è uscita dal
 * possesso del proprietario, ed è il fatto autoritativo — un annuncio riscritto
 * o ritirato non la riporta indietro. Viene prima di tutto il resto.
 *
 * Ciò che si vede non cambia: `ceduta_at` la valorizza un trigger all'ingresso
 * dell'annuncio in `venduto`, cioè esattamente il caso che già restituiva
 * "venduta". Togliere le bottiglie cedute dai totali di cantina è un'altra cosa,
 * e appartiene al trasferimento di proprietà al compratore — debito dichiarato,
 * non lavoro di questa fase.
 */
function statoDiVendita(
  annunci: RigaAnnuncio[],
  visibilita: RigaBottiglia["visibilita"],
  cedutaAt: string | null,
): CellarBottle["saleStatus"] {
  if (cedutaAt !== null) return "venduta";
  if (annunci.some((a) => a.stato === "attivo" || a.stato === "riservato")) return "in_vendita";
  if (annunci.some((a) => a.stato === "venduto")) return "venduta";
  return visibilita === "cantina_pubblica" ? "cantina_pubblica" : "privata";
}

/**
 * Id di posizione nella forma usata dai dati mock (`<modulo>-r<riga>c<colonna>`).
 * `Cellar3D` e la finestra "Sposta" confrontano `CellarBottle.storageLocationId`
 * con `StorageSlot.id`: mantenere la stessa forma è ciò che permette di
 * collegare il componente esistente senza toccarlo.
 */
export function idPosizione(moduleId: string, riga: number, colonna: number): string {
  return `${moduleId}-r${riga}c${colonna}`;
}

/** Scompone l'id di posizione. Ritorna null se non ha quella forma. */
export function leggiPosizione(
  slotId: string,
): { moduleId: string; riga: number; colonna: number } | null {
  const m = /^(.*)-r(\d+)c(\d+)$/.exec(slotId);
  if (!m) return null;
  return { moduleId: m[1], riga: Number(m[2]), colonna: Number(m[3]) };
}

function rigaABottiglia(riga: RigaBottiglia, slugVino: string): CellarBottle {
  const slot = primo(riga.cellar_slots);
  const annunci = riga.listings ?? [];

  const override: CellarBottle["override"] = {
    drinkWindowStart: riga.override_finestra_inizio ?? undefined,
    drinkWindowEnd: riga.override_finestra_fine ?? undefined,
    peakStart: riga.override_apice_inizio ?? undefined,
    peakEnd: riga.override_apice_fine ?? undefined,
    preferenza: riga.override_preferenza ?? undefined,
    nota: riga.override_nota || undefined,
  };
  const haOverride = Object.values(override).some((v) => v !== undefined);

  return {
    bottleId: riga.id,
    wineVintageId: slugVino,
    // Chiusa = 1, aperta o consumata = 0. Vedi l'intestazione del file.
    quantita: riga.stato === "chiusa" ? 1 : 0,
    // Lo stato per esteso, accanto alla sua compressione e non al posto suo:
    // `quantita` è letto da mezza Cantina e restringerlo ora sarebbe un lavoro
    // che nessuno ha chiesto. Chi deve distinguere `aperta` da `consumata` —
    // il badge della scheda — legge questo.
    stato: riga.stato,
    plannedOpenDate: riga.apertura_pianificata ?? undefined,
    override: haOverride ? override : undefined,
    saleStatus: statoDiVendita(annunci, riga.visibilita, riga.ceduta_at),
    priceVisibility: riga.prezzo_visibilita,
    storageLocationId: slot ? idPosizione(slot.module_id, slot.riga, slot.colonna) : undefined,
    personalNotes: riga.note_personali || undefined,
    // Distinta da `personalNotes`, e la distinzione è il punto della migrazione
    // 20260819120000: fino a quel file `bottiglia_apri` scriveva la nota di
    // degustazione *dentro* `note_personali`, cancellando quello che c'era. Chi
    // legge il commento da `personalNotes` sta leggendo la conseguenza di quel
    // difetto, non il commento.
    degustazioneNota: riga.degustazione_nota || undefined,
    degustazioneAt: riga.degustazione_at ?? undefined,
    annuncioBloccante: annuncioCheBlocca(annunci) ?? undefined,
  };
}

/**
 * L'annuncio che `bottiglia_apri` conterebbe come ostacolo, se ce n'è uno.
 *
 * Distinto da `annuncioRappresentativo`, che sceglie il più vivo o il più
 * recente per mostrarne prezzo e foto: qui interessa solo se esiste una riga in
 * uno dei cinque stati che fanno fallire l'apertura. L'indice
 * `listings_un_solo_annuncio_non_terminale` garantisce che non ce ne sia più di
 * uno, quindi il primo trovato è *il* bloccante e non uno a caso.
 */
function annuncioCheBlocca(annunci: RigaAnnuncio[]): { id: string; stato: string } | null {
  const bloccante = annunci.find((a) =>
    (STATI_BLOCCANTI_APERTURA as readonly string[]).includes(a.stato),
  );
  return bloccante ? { id: bloccante.id, stato: bloccante.stato } : null;
}

type Venditore = Wine["venditore"];

function rigaAVino(
  vino: RigaVinoCantina,
  annuncio: RigaAnnuncio | null,
  venditore: Venditore,
  disponibili: number,
  immaginiCantina: string[],
): Wine {
  const immagini =
    annuncio?.immagini && annuncio.immagini.length > 0
      ? annuncio.immagini.map(urlImmagine)
      : immaginiCantina.length > 0
        ? immaginiCantina
        : [IMMAGINE_ASSENTE];

  return {
    // Senza annuncio l'id resta quello del vino, ma detailHref è null: una
    // bottiglia privata non deve produrre un collegamento /annuncio inesistente.
    id: annuncio?.slug ?? vino.slug,
    detailHref: annuncio ? `/annuncio/${annuncio.slug}` : null,
    wineSlug: vino.slug,
    catalogSource: vino.provenienza,
    produttore: vino.produttore,
    nome: vino.nome,
    annata: vino.annata,
    regione: vino.regione,
    denominazione: vino.denominazione,
    tipo: vino.tipo as Wine["tipo"],
    formato: vino.formato,
    prezzo: annuncio ? annuncio.prezzo_cents / 100 : 0,
    prezzoMercato:
      annuncio?.prezzo_mercato_cents == null ? undefined : annuncio.prezzo_mercato_cents / 100,
    condizione: (annuncio?.condizione ?? "Ottimo") as Wine["condizione"],
    conservazione: annuncio?.conservazione ?? "",
    venditore,
    immagini,
    storia: annuncio?.storia ?? "",
    degustazione: annuncio?.degustazione ?? "",
    disponibili,
    tag: annuncio?.tag ?? [],
    createdAt: annuncio?.created_at ?? "",
  };
}

function rigaAAmbiente(riga: RigaAmbiente): StorageEnvironment {
  return {
    id: riga.id,
    name: riga.nome,
    shape: riga.forma,
    theme: riga.tema,
    material: riga.materiale,
    lighting: riga.illuminazione,
    // Lo schema misura in centimetri interi, la scena 3D in metri.
    dimensions: {
      width: riga.larghezza_cm / 100,
      height: riga.altezza_cm / 100,
      depth: riga.profondita_cm / 100,
    },
  };
}

function rigaAModulo(riga: RigaModulo): StorageModule {
  return {
    id: riga.id,
    environmentId: riga.environment_id,
    label: riga.etichetta,
    position: [Number(riga.posizione_x), Number(riga.posizione_y), Number(riga.posizione_z)],
    rotationY: Number(riga.rotazione_y),
    rows: riga.righe,
    columns: riga.colonne,
    depth: riga.profondita,
  };
}

/**
 * Le posizioni libere non hanno riga in `cellar_slots` (scelta di 6c-1): si
 * ricavano dalla geometria del modulo. Questa è la gemella di `makeSlots()` +
 * `slotsWithBottles()` di src/data/cellar.ts, che lavorano invece sui moduli
 * mock costanti.
 */
export function slotsDaModuli(
  moduli: StorageModule[],
  bottiglie: CellarBottle[],
): StorageSlot[] {
  const occupanti = new Map<string, string>();
  for (const b of bottiglie) {
    if (b.storageLocationId) occupanti.set(b.storageLocationId, b.bottleId);
  }

  const out: StorageSlot[] = [];
  for (const m of moduli) {
    for (let r = 0; r < m.rows; r++) {
      for (let c = 0; c < m.columns; c++) {
        const id = idPosizione(m.id, r, c);
        const bottleId = occupanti.get(id);
        out.push({
          id,
          moduleId: m.id,
          row: r,
          column: c,
          bottleId,
          status: bottleId ? "occupato" : "libero",
        });
      }
    }
  }
  return out;
}

// -- Errori ------------------------------------------------------------------

function segnalaErrore(operazione: string, errore: unknown): void {
  console.error(`[CellarService] ${operazione} fallita:`, errore);
}

/** Stessa regola di ListingService: all'utente solo i messaggi scritti da noi. */
const CODICI_LEGGIBILI = new Set(["P0001", "42501"]);
const ERRORE_GENERICO = "Non è stato possibile completare l'operazione. Riprova.";

type ErrorePostgrest = { code?: string; message?: string };

function messaggioPerUtente(operazione: string, errore: ErrorePostgrest): string {
  segnalaErrore(operazione, errore);
  if (errore.code && CODICI_LEGGIBILI.has(errore.code) && errore.message) return errore.message;
  return ERRORE_GENERICO;
}

const NESSUN_CLIENT: Result<never> = {
  ok: false,
  error: "Connessione a Supabase non configurata.",
};

async function scrittura(
  operazione: string,
  esegui: () => Promise<{ error: ErrorePostgrest | null }>,
): Promise<Result<void>> {
  const { error } = await esegui();
  if (error) return { ok: false, error: messaggioPerUtente(operazione, error) };
  return { ok: true, data: undefined };
}

// -- Servizio ----------------------------------------------------------------

export function createCellarService(client: SupabaseClient | null): CellarService {
  async function venditoreCorrente(): Promise<Venditore> {
    const vuoto: Venditore = {
      nome: "",
      citta: "",
      rating: 0,
      valutazioni: 0,
      verificato: false,
      avatar: "",
    };
    if (!client) return vuoto;

    const { data: sessione } = await client.auth.getUser();
    const uid = sessione.user?.id;
    if (!uid) return vuoto;

    const { data, error } = await client
      .from("profiles")
      .select("username, citta, avatar_url")
      .eq("id", uid)
      .maybeSingle();

    if (error || !data) {
      if (error) segnalaErrore("profilo", error);
      return vuoto;
    }

    // rating, valutazioni e verificato restano a zero/false per la stessa
    // ragione dichiarata in 6a: nascono da ordini e verifica identità, domini
    // non ancora migrati. Meglio non attestare nulla che attestare il falso.
    return {
      ...vuoto,
      nome: data.username as string,
      citta: data.citta as string,
      avatar: data.avatar_url as string,
    };
  }

  return {
    async carica(): Promise<DatiCantina> {
      if (!client) return CANTINA_VUOTA;

      const [ambientiRes, bottiglieRes, venditore] = await Promise.all([
        client.from("cellar_environments").select(COLONNE_AMBIENTI).order("created_at"),
        client
          .from("bottle_units")
          .select(COLONNE_BOTTIGLIE)
          .is("deleted_at", null)
          .order("created_at"),
        venditoreCorrente(),
      ]);

      if (ambientiRes.error) segnalaErrore("ambienti", ambientiRes.error);
      if (bottiglieRes.error) segnalaErrore("bottiglie", bottiglieRes.error);

      const righeAmbienti = (ambientiRes.data ?? []) as unknown as RigaAmbiente[];
      const ambienti = righeAmbienti.map(rigaAAmbiente);
      const moduli = righeAmbienti.flatMap((a) => (a.cellar_modules ?? []).map(rigaAModulo));

      const righeBottiglie = (bottiglieRes.data ?? []) as unknown as RigaBottiglia[];
      const percorsiCantina = Array.from(
        new Set(righeBottiglie.flatMap((riga) => riga.immagini ?? [])),
      );
      const urlCantina = new Map<string, string>();
      if (percorsiCantina.length > 0) {
        const { data: firme, error: erroreFirme } = await client.storage
          .from(BUCKET_CANTINA)
          .createSignedUrls(percorsiCantina, 3600);
        if (erroreFirme) {
          segnalaErrore("foto cantina", erroreFirme);
        } else {
          for (const firma of firme ?? []) {
            if (firma.path && firma.signedUrl) urlCantina.set(firma.path, firma.signedUrl);
          }
        }
      }

      const bottiglie: CellarBottle[] = [];
      const metaPerVino: Record<string, WineVintageMeta> = {};
      // Un vino per scheda, come in frontend/: le viste a griglia ed elenco
      // mostrano vini, non unità. La prima bottiglia incontrata (ordine di
      // creazione) è quella che presta annuncio, prezzo e foto alla scheda.
      const primoAnnuncioPerVino = new Map<string, RigaAnnuncio | null>();
      const primeImmaginiPerVino = new Map<string, string[]>();
      const vinoPerSlug = new Map<string, RigaVinoCantina>();
      const chiusePerVino = new Map<string, number>();

      for (const riga of righeBottiglie) {
        const vino = primo(riga.wines);
        if (!vino) continue;

        bottiglie.push(rigaABottiglia(riga, vino.slug));

        if (!vinoPerSlug.has(vino.slug)) {
          vinoPerSlug.set(vino.slug, vino);
          metaPerVino[vino.slug] = rigaAMeta(vino);
          primoAnnuncioPerVino.set(vino.slug, annuncioRappresentativo(riga.listings ?? []));
        }
        if ((primeImmaginiPerVino.get(vino.slug)?.length ?? 0) === 0) {
          primeImmaginiPerVino.set(
            vino.slug,
            (riga.immagini ?? [])
              .map((percorso) => urlCantina.get(percorso))
              .filter((url): url is string => Boolean(url)),
          );
        }
        chiusePerVino.set(
          vino.slug,
          (chiusePerVino.get(vino.slug) ?? 0) + (riga.stato === "chiusa" ? 1 : 0),
        );
      }

      const vini = Array.from(vinoPerSlug.values()).map((vino) =>
        rigaAVino(
          vino,
          primoAnnuncioPerVino.get(vino.slug) ?? null,
          venditore,
          chiusePerVino.get(vino.slug) ?? 0,
          primeImmaginiPerVino.get(vino.slug) ?? [],
        ),
      );

      return { bottiglie, vini, metaPerVino, ambienti, moduli };
    },

    async aggiungiBottiglia(
      dati: DatiNuovaBottiglia,
    ): Promise<Result<{ bottleUnitId: string; wineId: string }>> {
      if (!client) return NESSUN_CLIENT;

      const { data, error } = await client.rpc("cellar_bottiglia_aggiungi", {
        p_produttore: dati.produttore,
        p_nome: dati.nome,
        p_annata: dati.annata,
        p_regione: dati.regione,
        p_tipo: dati.tipo,
        p_visibilita: dati.visibilita,
        p_immagini: dati.immagini,
      });

      if (error) return { ok: false, error: messaggioPerUtente("aggiungiBottiglia", error) };

      const riga = (
        data as { bottle_unit_id: string; wine_id: string }[] | null
      )?.[0];
      if (!riga) {
        segnalaErrore("aggiungiBottiglia", "RPC senza risultato");
        return { ok: false, error: ERRORE_GENERICO };
      }
      return {
        ok: true,
        data: { bottleUnitId: riga.bottle_unit_id, wineId: riga.wine_id },
      };
    },

    /**
     * Dalla 6d-1 aprire una bottiglia è una RPC e non più un UPDATE diretto.
     * La 6c-2 poteva permetterselo perché `stato` non aveva regole dietro; ora
     * ne ha una che un CHECK non sa esprimere — «non si apre una bottiglia con
     * un annuncio non terminale» guarda un'altra tabella — e la verifica
     * deve avvenire sotto lock di riga, o due sessioni concorrenti la
     * aggirerebbero. `stato` è quindi uscito dai GRANT di colonna: questo
     * `UPDATE` oggi verrebbe rifiutato da PostgreSQL prima ancora della RLS.
     *
     * Il messaggio di rifiuto arriva all'utente già scritto in italiano dalla
     * funzione SQL: `P0001` è fra i `CODICI_LEGGIBILI`, quindi «questa bottiglia
     * è in vendita: sospendi il suo annuncio prima di aprirla» passa da
     * `messaggioPerUtente` senza altro lavoro qui.
     */
    async apri(bottleUnitId: string, nota?: string): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;

      return scrittura("apri", async () =>
        client.rpc("bottiglia_apri", {
          p_bottle_unit_id: bottleUnitId,
          p_nota: nota ?? null,
        }),
      );
    },

    async pianificaApertura(bottleUnitId: string, data: string): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("pianificaApertura", async () =>
        client.from("bottle_units").update({ apertura_pianificata: data }).eq("id", bottleUnitId),
      );
    },

    /** Qui invece serve la funzione: la posizione va verificata contro la
     * geometria del modulo e la bottiglia contro il suo proprietario, e
     * `cellar_slots` non è scrivibile dal client (scelta di 6c-1). */
    async colloca(
      bottleUnitId: string,
      moduleId: string,
      riga: number,
      colonna: number,
    ): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("colloca", async () =>
        client.rpc("cellar_posiziona", {
          p_bottle_unit_id: bottleUnitId,
          p_module_id: moduleId,
          p_riga: riga,
          p_colonna: colonna,
        }),
      );
    },

    async togliDallaPosizione(bottleUnitId: string): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("togliDallaPosizione", async () =>
        client.rpc("cellar_togli_posizione", { p_bottle_unit_id: bottleUnitId }),
      );
    },

    async impostaVisibilitaPrezzo(
      bottleUnitIds: string[],
      visibilita: CellarBottle["priceVisibility"],
    ): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      if (bottleUnitIds.length === 0) return { ok: true, data: undefined };

      return scrittura("impostaVisibilitaPrezzo", async () =>
        client
          .from("bottle_units")
          .update({ prezzo_visibilita: visibilita })
          .in("id", bottleUnitIds),
      );
    },

    async impostaOverrideFinestra(
      bottleUnitIds: string[],
      override: OverrideFinestra,
    ): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      if (bottleUnitIds.length === 0) return { ok: true, data: undefined };

      return scrittura("impostaOverrideFinestra", async () =>
        client
          .from("bottle_units")
          .update({
            override_finestra_inizio: override.drinkWindowStart ?? null,
            override_finestra_fine: override.drinkWindowEnd ?? null,
            override_apice_inizio: override.peakStart ?? null,
            override_apice_fine: override.peakEnd ?? null,
            override_preferenza: override.preferenza ?? null,
            override_nota: override.nota ?? "",
          })
          .in("id", bottleUnitIds),
      );
    },

    /** Ambiente e primo modulo nascono nella stessa transazione SQL. */
    async creaAmbiente(dati: DatiNuovoAmbiente): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("creaAmbiente", async () =>
        client.rpc("cellar_ambiente_crea", {
          p_nome: dati.nome,
          p_forma: dati.forma,
          p_tema: dati.tema,
          p_righe: dati.righe,
          p_colonne: dati.colonne,
        }),
      );
    },
  };
}
