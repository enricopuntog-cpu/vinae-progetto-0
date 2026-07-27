# Vinea — Wine Club

Vinea è una web app italiana per catalogare una cantina personale, scoprire vini,
partecipare ai club tematici e simulare flussi marketplace tra privati.

Questa repository è la base autonoma del progetto: lo sviluppo avviene direttamente
nel codice e su GitHub. Non richiede runtime, preview o servizi proprietari di
Lovable o Emergent.

> **Stato:** pre-release tecnica. I flussi Stripe e AI sono protetti e testabili con
> provider simulati, ma pagamenti reali e vendita di alcolici non devono essere
> attivati senza credenziali, monitoraggio e validazione legale/operativa.

## Struttura

```text
frontend/   React 19, TanStack Start, TypeScript, Tailwind, React Three Fiber
backend/    FastAPI, servizi Stripe e AI, repository asincroni
docs/       architettura, sicurezza, ambienti, audit e risultati dei test
.github/    pipeline CI
```

## Requisiti locali

- [Bun 1.3.14](https://bun.sh/) per il frontend (unico package manager supportato);
- Python 3.12 per il backend;
- un database MongoDB compatibile, se si eseguono flussi persistenti;
- account e chiavi di test Stripe solo per i test di integrazione manuali;
- credenziali di un provider AI compatibile solo per prove reali dell’AI.

## Avvio rapido

### Frontend

```bash
cd frontend
bun install --frozen-lockfile
bun run dev
```

### Backend

```bash
cd backend
python -m venv .venv
```

Attivare l’ambiente virtuale:

```bash
# macOS/Linux
source .venv/bin/activate

# Windows PowerShell
.\.venv\Scripts\Activate.ps1
```

Quindi:

```bash
python -m pip install -r requirements.txt
cp .env.example .env
python -m uvicorn server:app --host 127.0.0.1 --port 8001 --reload
```

Su Windows sostituire `cp` con:

```powershell
Copy-Item .env.example .env
```

Usare solo valori locali o chiavi di test. I file `.env` non vanno versionati.

## Controlli locali

Frontend:

```bash
cd frontend
bun run lint
bun run typecheck
bun run test       # test runner nativo di Bun
bun run build
```

Backend:

```bash
cd backend
python -m compileall -q .
python -m ruff check .
python -m pytest -q
```

I test automatici devono funzionare senza rete, database reale o credenziali
esterne. Le verifiche con Stripe e provider AI reali sono manuali e separate.

## Configurazione e documentazione

- [Architettura](docs/ARCHITECTURE.md)
- [Configurazione degli ambienti](docs/ENVIRONMENT.md)
- [Sicurezza](docs/SECURITY.md)
- [Sviluppo e flusso GitHub](docs/DEVELOPMENT.md)
- [Audit originale](docs/PRE_RELEASE_AUDIT.md)
- [Risoluzione dell’audit](docs/PRE_RELEASE_AUDIT_RESOLVED.md)
- [Rapporto dei test](docs/TEST_REPORT.md)

## Regola di pubblicazione

Le modifiche passano da branch dedicata e pull request. La pipeline deve completare
lint, typecheck, test e build prima del merge su `main`. Nessun segreto deve essere
inserito nel repository o nei workflow.
