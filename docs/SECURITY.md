# Sicurezza

## Stato e ambito

Questa guida descrive i controlli della pre-release. Non sostituisce una revisione
professionale prima di transazioni reali o trattamento di documenti d’identità.

## Segreti

- Non versionare `.env`, chiavi Stripe, segreti webhook, token AI o credenziali
  database.
- Usare chiavi Stripe di test in sviluppo.
- Separare completamente sviluppo, staging e produzione.
- Ruotare immediatamente una chiave accidentalmente esposta, anche dopo averla
  rimossa dalla cronologia Git.

## Autenticazione e autorizzazione

- L’identità viene verificata dal backend.
- Ruoli e ownership non sono accettati dal payload del browser.
- Le route private richiedono un principal autenticato.
- Le operazioni amministrative richiedono un ruolo server-side.
- Le conversazioni Sommelier, transazioni e ordini possono essere letti solo dal
  proprietario o da ruoli esplicitamente autorizzati.

L’adapter di autenticazione è sostituibile: collegare un nuovo provider non deve
modificare le regole di dominio.

## Stripe

- Verificare la firma del webhook sul corpo raw.
- In produzione `STRIPE_WEBHOOK_SECRET` deve essere presente e non vuoto.
- Deduplicare gli eventi webhook.
- Consentire il recupero degli eventi rimasti in elaborazione oltre la lease.
- Distinguere rimborsi parziali e totali senza retrocedere lo stato verificato.
- Usare idempotenza nella creazione delle sessioni.
- Non considerare `session.status=complete` equivalente a pagamento incassato.
- Accettare redirect solo se origin e percorso rispettano l’allowlist server-side.
- Non fidarsi di prezzo, valuta, proprietario o stato inviati dal client.
- Non registrare payload completi contenenti dati personali o di pagamento.

## CORS e redirect

- Le origini CORS sono definite tramite ambiente.
- `*` non è ammesso negli ambienti condivisi o di produzione.
- I redirect devono usare HTTPS in produzione.
- La corrispondenza considera origin completa, non sottostringhe del dominio.

## Rate limiting

Checkout, stato pagamenti e AI hanno limiti separati. La chiave di limitazione
combina identità autenticata e, dove opportuno, indirizzo client normalizzato.

Il limiter in memoria è adeguato a test e singola istanza. Un deployment
orizzontale deve usare uno storage condiviso e atomico, per esempio Redis.
Il bucket applicativo del webhook viene consumato soltanto dopo la verifica
della firma; traffico non firmato e volumetrico deve essere filtrato al bordo
tramite WAF o reverse proxy attendibile.

## AI

- Prompt e output hanno limiti di dimensione.
- Il provider ha timeout controllati.
- Gli errori interni sono registrati lato server e restituiti al client in forma
  generica.
- Il provider è astratto e sostituibile.
- Lo storico ha ownership, limite massimo e TTL.
- Le risposte non certificano autenticità o valore.

## Database asincrono

Gli handler asincroni non devono usare client database sincroni. I repository
vengono sostituiti con adapter in memoria nei test per evitare rete e dipendenze
esterne.

## Logging

Non registrare:

- secret o token;
- header `Authorization`;
- firme Stripe;
- prompt completi con dati personali;
- dati di pagamento;
- eccezioni del provider inviate al browser.

Usare identificatori di correlazione, livelli coerenti e messaggi minimizzati.

## Segnalazione di vulnerabilità

Non aprire issue pubbliche con dettagli sfruttabili o credenziali. Usare un canale
privato concordato con il proprietario del repository, includendo impatto,
riproduzione minima e versione interessata.

## Prima della produzione

- threat model e revisione indipendente;
- rate limiter condiviso;
- gestione centralizzata dei segreti;
- CSP, HSTS e header di sicurezza;
- monitoraggio, alert e audit log;
- backup, restore e disaster recovery;
- verifica legale su vendita di alcolici, età, privacy e marketplace;
- progettazione Stripe Connect, rimborsi e contestazioni.
