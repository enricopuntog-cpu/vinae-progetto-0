import { afterAll, afterEach, describe, expect, it, spyOn } from "bun:test";
import { apriDom, chiudiDom } from "@/test/dom";

apriDom();

const { cleanup, render, screen } = await import("@testing-library/react");
const { ConfineOpzionale } = await import("./ConfineOpzionale");

const Guasto = (): never => {
  throw new Error("chunk non caricato");
};

afterEach(() => cleanup());
afterAll(async () => {
  await chiudiDom();
});

describe("ConfineOpzionale", () => {
  it("senza errori mostra il contenuto e non il ripiego", () => {
    render(
      <ConfineOpzionale fallback={<p>ripiego</p>}>
        <p>contenuto</p>
      </ConfineOpzionale>,
    );
    expect(screen.queryByText("contenuto")).not.toBeNull();
    expect(screen.queryByText("ripiego")).toBeNull();
  });

  it("un errore del contenuto resta nel confine: il resto della pagina non cade", () => {
    // React riporta in console l'errore intercettato: qui è atteso.
    const consoleError = spyOn(console, "error").mockImplementation(() => undefined);
    try {
      render(
        <main>
          <h1>Pagina</h1>
          <ConfineOpzionale fallback={<p>ripiego</p>}>
            <Guasto />
          </ConfineOpzionale>
        </main>,
      );
      expect(screen.queryByText("ripiego")).not.toBeNull();
      expect(screen.queryByText("Pagina")).not.toBeNull();
    } finally {
      consoleError.mockRestore();
    }
  });
});
