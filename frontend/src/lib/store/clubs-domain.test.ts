import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useClubsDomain } from "./clubs-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

describe("useClubsDomain", () => {
  it("segue un club non ancora seguito", () => {
    const { result } = renderHook(() => useClubsDomain());
    expect(result.current.communityFollows.has("barolo-barbaresco")).toBe(true);
    expect(result.current.communityFollows.has("valpolicella")).toBe(false);

    act(() => result.current.toggleCommunityFollow("valpolicella"));

    expect(result.current.communityFollows.has("valpolicella")).toBe(true);
  });

  it("smette di seguire un club già seguito", () => {
    const { result } = renderHook(() => useClubsDomain());

    act(() => result.current.toggleCommunityFollow("barolo-barbaresco"));

    expect(result.current.communityFollows.has("barolo-barbaresco")).toBe(false);
  });
});
