import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useAuthDomain } from "./auth-domain";

describe("useAuthDomain", () => {
  it("parte con il ruolo demo 'user'", () => {
    const { result } = renderHook(() => useAuthDomain({ onGuestSwitch: vi.fn() }));
    expect(result.current.ruolo).toBe("user");
  });

  it("cambia ruolo senza azzerare l'onboarding se non è guest", () => {
    const onGuestSwitch = vi.fn();
    const { result } = renderHook(() => useAuthDomain({ onGuestSwitch }));

    act(() => result.current.setRuolo("admin"));

    expect(result.current.ruolo).toBe("admin");
    expect(onGuestSwitch).not.toHaveBeenCalled();
  });

  it("azzera l'onboarding quando si passa a guest", () => {
    const onGuestSwitch = vi.fn();
    const { result } = renderHook(() => useAuthDomain({ onGuestSwitch }));

    act(() => result.current.setRuolo("guest"));

    expect(result.current.ruolo).toBe("guest");
    expect(onGuestSwitch).toHaveBeenCalledTimes(1);
  });
});
