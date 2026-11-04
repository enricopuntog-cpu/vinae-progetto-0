import { describe, expect, it } from "bun:test";
import { destinazioneEsternaAmmessa } from "./checkout";

describe("destinazioneEsternaAmmessa", () => {
  it("segue solo la pagina di pagamento di Stripe", () => {
    expect(destinazioneEsternaAmmessa("https://checkout.stripe.com/c/pay/cs_test_1")).toBe(true);
  });

  it("rifiuta ogni altra destinazione", () => {
    for (const indirizzo of [
      "https://pagamento.invalid/sessione",
      "http://checkout.stripe.com/c/pay",
      "https://checkout.stripe.com.evil.example/c/pay",
      "https://evil.example/#checkout.stripe.com",
      "https://checkout.stripe.com@evil.example/",
      "javascript:alert(1)",
      "/acquisti",
      "",
    ]) {
      expect(destinazioneEsternaAmmessa(indirizzo)).toBe(false);
    }
  });
});
