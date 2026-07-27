import { useCallback, useState } from "react";
import { toast } from "sonner";
import { communitySeguiteIniziali } from "@/data/communities";

export function useClubsDomain() {
  const [communityFollows, setCommunityFollows] = useState<Set<string>>(
    new Set(communitySeguiteIniziali),
  );

  const toggleCommunityFollow = useCallback((slug: string) => {
    setCommunityFollows((prev) => {
      const next = new Set(prev);
      if (next.has(slug)) {
        next.delete(slug);
        toast("Non segui più il club");
      } else {
        next.add(slug);
        toast.success("Segui il club");
      }
      return next;
    });
  }, []);

  return {
    communityFollows,
    toggleCommunityFollow,
  };
}
