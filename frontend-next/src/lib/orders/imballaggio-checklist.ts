/**
 * La checklist canonica di imballaggio e i due tipi di prova fotografica.
 *
 * **Questa non è l'autorità.** Lo sono `private.imballaggio_checklist_voci()` e
 * `private.imballaggio_checklist_completa(jsonb)`, che vedono la riga e che
 * `ordine_prepara_spedizione` interroga prima di valorizzare
 * `preparazione_confermata_at`. Questa copia esiste per accendere e spegnere un
 * bottone senza una andata al database per ogni spunta — e perché il test possa
 * rileggere la migrazione vera e accorgersi quando le due divergono.
 *
 * Gli ID non si inventano: una voce con un ID diverso si salva e non conta, e
 * la preparazione resterebbe non confermata senza che si capisca perché. Le
 * etichette invece sono solo lingua e stanno qui.
 */

import type { ShippingEvidenceKind, VoceChecklist } from "@/services/types";

/**
 * Le sei dichiarazioni di sicurezza. Sostituiscono le quattro voci fotografiche
 * della 7c («Foto etichetta frontale» e le altre): erano spunte che affermavano
 * una fotografia senza che ne esistesse una, e la fotografia ora si carica
 * davvero.
 */
export const VOCI_IMBALLAGGIO: ReadonlyArray<{ id: string; label: string }> = [
  { id: "bottiglia_immobilizzata", label: "Bottiglia immobilizzata" },
  { id: "nessun_movimento", label: "Nessun movimento all'interno del collo" },
  { id: "protezione_tutti_lati", label: "Protezione su tutti i lati" },
  { id: "cartone_esterno_integro", label: "Cartone esterno integro" },
  { id: "chiusura_adeguata", label: "Chiusura adeguata" },
  {
    id: "confezione_originale_protetta",
    label:
      "Se presente, cofanetto/cassa originale protetto e senza nastro o etichette applicati direttamente",
  },
];

export const ID_IMBALLAGGIO: readonly string[] = VOCI_IMBALLAGGIO.map((v) => v.id);

/**
 * Le due prove fotografiche. Una sola CORRENTE per tipo: ricaricare sostituisce
 * e la precedente resta archiviata, finché l'ordine non è spedito.
 */
export const PROVE_SPEDIZIONE: ReadonlyArray<{
  kind: ShippingEvidenceKind;
  titolo: string;
  obbligatoria: boolean;
  obbligo: string;
  aiuto: string;
}> = [
  {
    kind: "collo_finale",
    titolo: "Foto del pacco chiuso",
    obbligatoria: true,
    obbligo: "Obbligatoria",
    aiuto: "Fotografa il collo finale già chiuso e pronto alla spedizione.",
  },
  {
    kind: "interno_pre_chiusura",
    titolo: "Foto dell'interno prima della chiusura",
    obbligatoria: false,
    obbligo: "Facoltativa",
    aiuto: "Facoltativa, ma utile in caso di contestazione.",
  },
];

/**
 * Esattamente le sei voci canoniche, ciascuna una volta, tutte spuntate. È la
 * stessa regola di `private.imballaggio_checklist_completa`: «più qualcosa» non
 * è completa, e una voce inventata non sostituisce quella che manca.
 */
export const checklistCompleta = (voci: readonly VoceChecklist[]): boolean => {
  if (voci.length !== ID_IMBALLAGGIO.length) return false;
  const distinti = new Set(voci.map((v) => v.id));
  if (distinti.size !== ID_IMBALLAGGIO.length) return false;
  return ID_IMBALLAGGIO.every((id) => voci.some((v) => v.id === id && v.done === true));
};

/**
 * Quando la chiamata a `ordine_prepara_spedizione` chiuderà davvero il
 * cancello. Serve ad accendere «Conferma preparazione»: il rifiuto vero, se
 * questa copia sbaglia, resta quello del database.
 */
export const preparazioneConfermabile = (
  voci: readonly VoceChecklist[],
  proveCorrenti: readonly ShippingEvidenceKind[],
): boolean => checklistCompleta(voci) && proveCorrenti.includes("collo_finale");
