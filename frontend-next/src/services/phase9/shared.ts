// Fase 9 - utilita condivise dell'adapter di moderazione.
//
// A differenza di Fase 7 e Fase 8, ModerationService (services/types.ts:970-981)
// non restituisce Result<T> ma promesse nude: e un'interfaccia piu vecchia della
// convenzione Result, ed e stata scritta prima. Il prompt di fase dice di
// implementarla, non di riscriverla, quindi l'errore qui e un'eccezione e non un
// ramo `ok: false`. Phase9Error esiste per non far arrivare alla UI il messaggio
// grezzo di Postgres.

type ServiceError = { code?: string; message?: string };

// Gli stessi codici che la Fase 8 considera leggibili: sono quelli che le RPC
// sollevano di proposito con un messaggio destinato all'utente.
const readableCodes = new Set(["P0001", "42501", "22023", "PGRST"]);

export class Phase9Error extends Error {
  readonly code?: string;

  constructor(operation: string, error: ServiceError) {
    const leggibile = error.code && readableCodes.has(error.code) && error.message;
    super(leggibile ? (error.message as string) : "Non e stato possibile completare l'operazione. Riprova.");
    this.name = "Phase9Error";
    this.code = error.code;
    // Il dettaglio non raggiunge la UI: resta nella console con il solo codice,
    // come fa phase8Error. Un messaggio di Postgres puo contenere nomi di
    // colonne e vincoli.
    console.error(`[Phase9] ${operation} fallita`, { code: error.code });
  }
}

export const phase9Throw = (operation: string, error: ServiceError): never => {
  throw new Phase9Error(operation, error);
};

// L'assenza di client non e un errore di rete: e configurazione mancante.
export const noPhase9Client = (operation: string): never => {
  throw new Phase9Error(operation, {
    code: "P0001",
    message: "Connessione a Supabase non configurata.",
  });
};

// Le azioni di moderazione sono il checkpoint 9b. Finche non esistono, i due
// metodi di scrittura dell'interfaccia devono esserci — l'interfaccia li
// dichiara — ma non devono fingere di funzionare.
export const nonAncoraDisponibile = (operazione: string): never => {
  throw new Phase9Error(operazione, {
    code: "P0001",
    message: "Questa azione arriva con il checkpoint 9b.",
  });
};
