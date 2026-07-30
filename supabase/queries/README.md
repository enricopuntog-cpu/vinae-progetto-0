# Query manuali Supabase

Questa cartella contiene esclusivamente query di controllo o diagnostica che
possono essere salvate nel SQL Editor con lo stesso nome del file.

## Regole

- I file in `supabase/migrations/` sono migrazioni versionate: non vanno
  rilanciati manualmente dopo che risultano applicati.
- I file TypeScript di `frontend/` e `frontend-next/` non sono SQL e non vanno
  incollati nel SQL Editor.
- Prima di eseguire una query controllare il titolo nel commento iniziale.
- Le modifiche future allo schema devono nascere come nuove migrazioni, mai
  sovrascrivendo una migrazione storica.

## Query disponibili

| File | Titolo da usare nel SQL Editor | Effetto |
| --- | --- | --- |
| `00_INFO_NON_ESEGUIRE_TYPESCRIPT_CANTINA.sql` | `00 — INFO — NON ESEGUIRE IL TYPESCRIPT DELLA CANTINA` | Nessuna modifica |
| `01_VERIFICA_SCHEMA_CANTINA_FASE_6C1.sql` | `01 — VERIFICA — SCHEMA CANTINA FASE 6C-1` | Sola lettura |
