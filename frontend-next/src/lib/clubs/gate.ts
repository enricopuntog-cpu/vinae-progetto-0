import { valoreFlagEsattamenteTrue } from "@/config/features";

/**
 * Gate autoritativo delle route Club.
 *
 * La flag pubblica controlla anche la navigazione, ma da sola non puo aprire
 * una superficie server. Entrambe devono essere la stringa esatta `true`.
 */
export const clubAbilitatiServer = (): boolean =>
  valoreFlagEsattamenteTrue(process.env.CLUBS_ENABLED) &&
  valoreFlagEsattamenteTrue(process.env.NEXT_PUBLIC_CLUBS_ENABLED);
