-- WI-009 (audit indipendente WI-008, finding F-11): le tre porte Cantina<->catalogo sono per l'utente autenticato.
-- I privilegi di default davano EXECUTE anche a service_role (la 20261126100000 revocava solo public e anon). Nessun
-- percorso di servizio le usa e, senza `sub`, fallivano già con 42501: la revoca applica il minimo privilegio.
revoke execute on function
  public.cellar_catalogo_scegli(text, text),
  public.cellar_catalogo_rimuovi(text),
  public.catalogo_canonico_disponibile()
from service_role;
