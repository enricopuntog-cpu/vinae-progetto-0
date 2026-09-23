import type {
  ClubExternalLinkAdmin,
  ClubJoinRequestAdmin,
  ClubMemberAdmin,
  ClubRuleVersionAdmin,
  ManagedClub,
} from "@/services/phase12/club-governance-service";

export type ClubManagementReader = {
  managedClubs: () => Promise<ManagedClub[]>;
  members: (slug: string) => Promise<ClubMemberAdmin[]>;
  joinRequests: (slug: string) => Promise<ClubJoinRequestAdmin[]>;
  rules: (slug: string) => Promise<ClubRuleVersionAdmin[]>;
  links: (slug: string) => Promise<ClubExternalLinkAdmin[]>;
};

export type ClubManagementSnapshot = {
  club: ManagedClub;
  currentUserId: string;
  members: ClubMemberAdmin[];
  requests: ClubJoinRequestAdmin[];
  rules: ClubRuleVersionAdmin[];
  links: ClubExternalLinkAdmin[];
};

// Il pannello di gestione e montato su ogni pagina Club. Un visitatore senza
// sessione non ha grant sulle viste di gestione: interrogarle produceva cinque
// 401 per pagina. Le viste restano il confine di autorizzazione; qui si evita
// soltanto di chiederle a chi non puo gestire il Club.
export const loadClubManagement = async (
  slug: string,
  currentUserId: () => Promise<string | null>,
  reader: ClubManagementReader,
): Promise<ClubManagementSnapshot | null> => {
  const userId = await currentUserId();
  if (!userId) return null;
  const club = (await reader.managedClubs()).find((item) => item.slug === slug);
  if (!club) return null;
  const [members, requests, rules, links] = await Promise.all([
    reader.members(slug), reader.joinRequests(slug), reader.rules(slug), reader.links(slug),
  ]);
  return { club, currentUserId: userId, members, requests, rules, links };
};
