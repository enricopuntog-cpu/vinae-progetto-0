# Sviluppo e flusso GitHub

## Principi

- GitHub è la fonte ufficiale del codice.
- Bun 1.3.14 è l’unico package manager frontend.
- `bun.lock` deve essere versionato; non introdurre altri lockfile.
- Ogni segreto resta fuori da Git e viene fornito dall’ambiente.
- Le operazioni critiche si implementano e verificano lato server.
- Una modifica funzionale include test proporzionati al rischio.

## Branch e pull request

1. Partire da `main` aggiornato.
2. Creare una branch breve e descrittiva, per esempio
   `agent/pre-release-hardening`.
3. Fare commit piccoli, con messaggi che descrivano il risultato.
4. Aprire una pull request in bozza.
5. Attendere la pipeline CI.
6. Richiedere revisione prima del merge.
7. Non fare force-push su branch condivise.

Non si pubblicano direttamente modifiche incomplete su `main`.

## Installazione riproducibile

Frontend:

```bash
cd frontend
bun install --frozen-lockfile
```

Backend:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

## Comandi obbligatori

Prima di aprire una pull request:

```bash
cd frontend
bun run lint
bun run typecheck
bun run test
bun run build
```

```bash
cd backend
python -m compileall -q .
python -m ruff check .
python -m pytest -q
```

La pipeline `.github/workflows/ci.yml` esegue gli stessi controlli in un ambiente
pulito.

## Test con servizi esterni

I test automatici non devono dipendere da:

- preview temporanee;
- rete;
- MongoDB remoto;
- Stripe reale;
- provider AI reale;
- chiavi o token.

Le prove di integrazione reali sono manuali, usano ambienti sandbox dedicati e
vengono registrate in `docs/TEST_REPORT.md` senza salvare credenziali o dati
personali.

## Migrazioni e configurazioni

- Cambiare un contratto API richiede l’aggiornamento simultaneo di client, test e
  documentazione.
- Aggiungere una variabile ambiente richiede l’aggiornamento di
  `backend/.env.example` e `docs/ENVIRONMENT.md`.
- Aggiungere un provider richiede un adapter dietro l’interfaccia esistente.
- Modificare uno stato di pagamento richiede test per webhook duplicati, eventi
  fuori ordine e metodi asincroni.

## Definition of done

Una modifica è completa quando:

- il codice è tipizzato e leggibile;
- gli errori non espongono dettagli interni;
- i permessi sono verificati lato server;
- esistono test locali deterministici;
- lint, typecheck, test e build passano;
- documentazione ed esempi ambiente sono aggiornati;
- non sono presenti segreti o dipendenze da preview temporanee.
