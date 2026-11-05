-- VPM-022B-R-DB-01: five trigger functions and two internal Sommelier helpers.
-- Existing trigger bindings keep working. The service_role API uses the public
-- SECURITY DEFINER wrappers (owner postgres), not direct private helper calls.
-- These seven functions have only the implicit PUBLIC EXECUTE default; preserve
-- owner privileges and every existing explicit grant. No body or API changes.
revoke execute on function
  private.seller_enabled_sync(),
  private.orders_tracking_sync(),
  private.disputes_invariante(),
  private.club_post_owner_only_guard(),
  private.club_risposta_owner_only_guard(),
  private.sommelier_contesto_leggi(uuid, text, integer),
  private.sommelier_scambio_registra(uuid, text, text, text)
from public;
