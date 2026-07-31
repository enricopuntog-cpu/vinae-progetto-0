import { describe, expect, it } from "bun:test";

const reserveOnce = () => {
  let owner: string | null = null;
  let queue = Promise.resolve();
  return (buyer: string): Promise<boolean> => {
    const result = queue.then(() => {
      if (owner) return owner === buyer;
      owner = buyer;
      return true;
    });
    queue = result.then(() => undefined);
    return result;
  };
};

describe("prenotazione concorrente", () => {
  it("ammette un solo compratore e rende idempotente il suo retry", async () => {
    const reserve = reserveOnce();
    const [first, second] = await Promise.all([reserve("buyer-a"), reserve("buyer-b")]);
    expect([first, second].filter(Boolean)).toHaveLength(1);
    const winner = first ? "buyer-a" : "buyer-b";
    expect(await reserve(winner)).toBeTrue();
  });
});
