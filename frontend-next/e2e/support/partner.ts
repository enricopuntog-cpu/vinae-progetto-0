import { randomUUID } from "node:crypto";
import { EMAIL, accedi, accendiPubblicazione, caricaFoto, idCategoriaCalici, passwordFixture, rpc, type Ruolo } from "./api";
import { eseguiSql, ripristinaFixture } from "./db";

/**
 * Preparazione dello stato Partner per i test browser (VPM-015QA-FINAL-B2-COMPLETION).
 * Usa le stesse porte pubbliche del programma Partner (invito, accettazione, dati, verifica, approvazione):
 * nessuna scrittura diretta sul ciclo di vita. I soli interruttori che non hanno porta di accensione
 * (`vendita_partner`) si accendono a mano sul solo stack isolato, come fa la griglia 12zr, e la pulizia 12zk
 * li spegne.
 */

const MOTIVO = "prova browser E2E";

/** Una partita IVA valida per la funzione del database (prefisso di 10 cifre + cifra di controllo). */
const partitaIva = (prefisso: string): string =>
  eseguiSql(`select ${"'" + prefisso + "'"} || d from generate_series(0, 9) d
    where private.partita_iva_valida(${"'" + prefisso + "'"} || d::text) limit 1;`);

const ok = (nome: string, r: { ok: boolean; status: number }): void => {
  if (!r.ok) throw new Error(`Partner: ${nome} fallita (HTTP ${r.status}).`);
};

/** Porta un utente della fixture a Partner ATTIVO e restituisce l'id del Partner. */
export const attivaPartner = async (ruolo: Ruolo, prefissoPiva: string): Promise<string> => {
  const admin = await accedi("rilascio");
  const utente = await accedi(ruolo);
  const email = EMAIL[ruolo];
  const invito = await rpc<{ token: string }>("partner_admin_invito_crea", { p_email: email }, admin);
  ok("invito", invito);
  const accettato = await rpc<string>("partner_invito_accetta", { p_token: invito.body.token }, utente);
  ok("accettazione", accettato);
  const partnerId = accettato.body;
  ok(
    "dati",
    await rpc(
      "partner_dati_aggiorna",
      {
        p_ragione_sociale: `Ragione ${ruolo} Srl`,
        p_nome_commerciale: `Enoteca ${ruolo}`,
        p_partita_iva: partitaIva(prefissoPiva),
        p_email_commerciale: `commerciale.${email}`,
        p_tipologia: "enoteca",
        p_sede_indirizzo: "Via Prova 1",
        p_sede_cap: "12051",
        p_sede_citta: "Alba",
        p_sede_provincia: "CN",
      },
      utente,
    ),
  );
  ok("verifica", await rpc("partner_invia_verifica", {}, utente));
  ok("approvazione", await rpc("partner_admin_decidi", { p_partner_id: partnerId, p_azione: "approva" }, admin));
  return partnerId;
};

export type AzionePartner = "sospendi" | "riattiva" | "revoca";

/** Decisione dell'amministratore sul Partner; restituisce lo stato letto dal database. */
export const decidiPartner = async (partnerId: string, azione: AzionePartner): Promise<string> => {
  const admin = await accedi("rilascio");
  ok(azione, await rpc("partner_admin_decidi", { p_partner_id: partnerId, p_azione: azione, p_motivo: MOTIVO }, admin));
  return eseguiSql(`select stato::text from private.partners where id = '${partnerId}';`);
};

/** `vendita_partner` non ha una porta di accensione: solo su stack isolato, e la pulizia 12zk lo riporta a falso. */
export const impostaVenditaPartner = (acceso: boolean): void => {
  eseguiSql(`update private.inventario_impostazioni set vendita_partner = ${acceso ? "true" : "false"};`);
};

/** Visibilità del catalogo Accessori (porta del ruolo di rilascio). */
export const accendiCatalogo = async (): Promise<void> => {
  const rilascio = await accedi("rilascio");
  ok("catalogo", await rpc("accessori_admin_visibilita_imposta", { p_attiva: true, p_motivo: MOTIVO }, rilascio));
};

/** Una scheda di catalogo PUBBLICATA (sintetica) collegabile da una scorta; l'autore è l'amministratore di rilascio. */
export const creaSchedaCatalogo = async (slug: string, nome: string): Promise<void> => {
  const rilascio = await accedi("rilascio");
  eseguiSql(`
    insert into private.accessori (categoria_id, slug, nome, descrizione, marchio, condizione, quantita, stato, creato_da)
    select id, '${slug}', '${nome}', 'Scheda sintetica di prova.', 'Marchio', 'nuovo', 1, 'bozza', '${rilascio.id}'
    from private.accessori_categorie where slug = 'calici-da-rosso';
    update private.accessori
       set immagini = array[id::text || '/' || gen_random_uuid()::text || '.webp'], stato = 'pubblicato'
     where slug = '${slug}';`);
};

/** Servizio e tariffa di PROVA (valori inventati, non tariffe) per il solo stack isolato. */
export const creaLogisticaDiProva = (provider: string): void => {
  eseguiSql(`
do $f$
declare
  v_t timestamptz := now() - interval '1 hour';
  v_srv uuid;
  v_rete uuid;
begin
  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level, max_weight_g, max_length_mm, max_width_mm,
    max_height_mm, max_volume_cm3, eligible_packaging_formats, operational_eligibility, active, effective_from
  ) values ('${provider}', 'standard', 'standard', 20000, 600, 400, 400, 90000, '{}', true, true, v_t)
  returning id into v_srv;
  insert into private.logistics_service_capabilities (service_definition_id, capability) values (v_srv, 'PUDO_TO_PUDO');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('${provider}', '${provider}_rete', 'Rete di prova E2E', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('${provider}', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790,
          'Prova E2E (non una tariffa)', 'active', v_t);
end
$f$;`);
};

/** Accende logistica e checkout con le porte del ruolo di rilascio. */
export const accendiCheckout = async (): Promise<void> => {
  const rilascio = await accedi("rilascio");
  const logistica = await rpc("accessori_logistica_admin_imposta", { p_attiva: true, p_motivo: MOTIVO }, rilascio);
  const checkout = await rpc("accessori_checkout_admin_imposta", { p_attivo: true, p_motivo: MOTIVO }, rilascio);
  if (!logistica.ok || !checkout.ok) throw new Error(`Interruttori non accesi: ${logistica.status}/${checkout.status}`);
};

/** Prenota `quantita` pezzi con le stesse porte della UI (preventivo congelato + ordine); restituisce l'id dell'ordine. */
export const prenotaConLeStessePorte = async (ruolo: Ruolo, annuncioId: string, quantita: number): Promise<string> => {
  const sessione = await accedi(ruolo);
  const congelato = await rpc<{ preventivoId: string }>(
    "accessori_logistica_preventivo_congela",
    { p_annuncio: annuncioId, p_quantita: quantita },
    sessione,
  );
  if (!congelato.ok) throw new Error(`Preventivo non congelato: HTTP ${congelato.status}`);
  const creato = await rpc<{ id: string }>(
    "accessori_checkout_crea",
    { p_preventivo_id: congelato.body.preventivoId, p_chiave: `e2e-${randomUUID()}` },
    sessione,
  );
  if (!creato.ok) throw new Error(`Ordine non creato: HTTP ${creato.status} ${JSON.stringify(creato.body).slice(0, 200)}`);
  return creato.body.id;
};

export interface ScenarioPartner {
  partnerId: string;
  cantinaId: string;
  annuncioId: string;
  url: string;
}

/**
 * Fixture nuova, Partner attivo (`venditore`), scorta commerciale da `scorta` pezzi con foto e annuncio
 * pubblicato da `inVendita` pezzi a 20,00 €, `vendita_partner` e checkout accesi. Solo stack isolato.
 */
export const preparaScenarioPartner = async (provider: string, scorta = 8, inVendita = 6): Promise<ScenarioPartner> => {
  ripristinaFixture(passwordFixture());
  await accendiPubblicazione();
  creaLogisticaDiProva(provider);
  await accendiCheckout();
  const partnerId = await attivaPartner("venditore", "1234567890");
  impostaVenditaPartner(true);
  const venditore = await accedi("venditore");
  const cantinaId = randomUUID();
  const creato = await rpc(
    "accessori_partner_scorta_salva",
    { p_id: cantinaId, p_dati: { categoria_id: await idCategoriaCalici(), nome: "Calice Partner E2E", quantita: scorta } },
    venditore,
  );
  if (!creato.ok) throw new Error(`Scorta non creata: HTTP ${creato.status}`);
  const foto = `${venditore.id}/${cantinaId}/${randomUUID()}.webp`;
  if ((await caricaFoto(venditore, foto)) >= 300) throw new Error("Foto non caricata.");
  const collegata = await rpc("cantina_accessori_immagini_imposta", { p_id: cantinaId, p_percorsi: [foto] }, venditore);
  if (!collegata.ok) throw new Error(`Foto non collegata: HTTP ${collegata.status}`);
  const annuncioId = randomUUID();
  const bozza = await rpc(
    "annunci_accessori_salva",
    {
      p_id: annuncioId,
      p_dati: {
        cantina_id: cantinaId, quantita: inVendita, prezzo_unitario_cents: 2000, condizione: "nuovo", descrizione: "Calici nuovi.",
        conforme: true, peso_g: 400, lunghezza_mm: 250, larghezza_mm: 100, altezza_mm: 100, fragile: false,
      },
    },
    venditore,
  );
  if (!bozza.ok) throw new Error(`Bozza non creata: HTTP ${bozza.status}`);
  const pubblicato = await rpc("annunci_accessori_pubblica", { p_id: annuncioId }, venditore);
  if (!pubblicato.ok) throw new Error(`Annuncio non pubblicato: HTTP ${pubblicato.status}`);
  return { partnerId, cantinaId, annuncioId, url: `/accessori/annunci/${annuncioId}` };
};

/** Spegne il checkout (qualunque admin può spegnere): le vendite si chiudono ma ordini e post-vendita restano consultabili. */
export const spegniCheckout = async (): Promise<void> => {
  const rilascio = await accedi("rilascio");
  ok("checkout spento", await rpc("accessori_checkout_admin_imposta", { p_attivo: false, p_motivo: MOTIVO }, rilascio));
};
