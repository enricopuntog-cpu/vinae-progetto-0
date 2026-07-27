# Route map

Legenda accesso: **G**=Guest, **U**=Utente autenticato, **A**=Admin.
Il ruolo si commuta dal profilo (demo).

| Percorso               | File                             | Accesso | Note                                                     |
| ---------------------- | -------------------------------- | ------- | -------------------------------------------------------- |
| `/`                    | `routes/index.tsx`               | G/U/A   | Home ospite (hero, sezioni editoriali)                   |
| `/home`                | `routes/home.tsx`                | U/A     | Home utente (saluto, consigliati, attività Club)         |
| `/esplora`             | `routes/esplora.tsx`             | G/U/A   | Ricerca con modalità _recenti / prezzo / abbinamento_    |
| `/annuncio/$id`        | `routes/annuncio.$id.tsx`        | G/U/A   | Dettaglio annuncio, gallery, CTA proposta/checkout       |
| `/cantina`             | `routes/cantina.tsx`             | U/A     | KPI, in vendita, grafico valore, drink window, sfondi 3D |
| `/vendi`               | `routes/vendi.tsx`               | U/A     | Wizard 8 step, richiede verifica venditore               |
| `/community`           | `routes/community.index.tsx`     | G/U/A   | Hub Club, filtri per territorio/denominazione            |
| `/community/$slug`     | `routes/community.$slug.tsx`     | G/U/A   | Dettaglio Club, discussioni, note degustazione           |
| `/messaggi`            | `routes/messaggi.tsx`            | U/A     | 2 pannelli desktop, messaggi di sistema proposte         |
| `/notifiche`           | `routes/notifiche.tsx`           | U/A     | Tab Marketplace / Community / Sistema                    |
| `/profilo`             | `routes/profilo.tsx`             | G/U/A   | Profilo + switch ruolo demo                              |
| `/venditore/$username` | `routes/venditore.$username.tsx` | G/U/A   | Profilo pubblico venditore verificato                    |
| `/onboarding`          | `routes/onboarding.tsx`          | G       | Wizard registrazione + preferenze + età                  |
| `/verifica-venditore`  | `routes/verifica-venditore.tsx`  | U       | KYC simulato prima della prima vendita                   |
| `/checkout/$id`        | `routes/checkout.$id.tsx`        | U/A     | Riepilogo, consegna, pagamento simulato                  |
| `/acquisti`            | `routes/acquisti.tsx`            | U/A     | Stati acquirente (10)                                    |
| `/vendite`             | `routes/vendite.tsx`             | U/A     | Stati venditore (6) + prep spedizione                    |
| `/ordine/$id`          | `routes/ordine.$id.tsx`          | U/A     | Timeline, conferma, dispute, recensione                  |
| `/segnalazioni`        | `routes/segnalazioni.tsx`        | U/A     | Cronologia segnalazioni utente                           |
| `/admin`               | `routes/admin.tsx`               | A       | KPI, moderazione, controversie, audit                    |
| `/admin/stati`         | `routes/admin.stati.tsx`         | A       | Catalogo demo stati (skeleton/empty/error/AI)            |

## Layout

`__root.tsx` monta `<Layout>` (header desktop + bottom nav mobile + skip-link).
Non esistono pathless routes (`_authenticated`): l'auth è simulata via ruolo
nello store. In Next.js questa diventerà una `route group` con middleware.
