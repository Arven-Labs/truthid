import { describe, it, expect } from "vitest";
import { PublishStepError, describeUploadError } from "../publishErrors";

describe("describeUploadError", () => {
  it("explica a falta de carteira Arweave", () => {
    expect(
      describeUploadError("nenhuma wallet Arweave configurada — gere ou importe uma antes de publicar o vault"),
    ).toContain("Generate or import one in the Arweave tab");
  });

  it("converte winston em AR no saldo insuficiente", () => {
    const msg = describeUploadError("saldo insuficiente: precisa de 3579614675 winston, tem 0 winston");
    expect(msg).toContain("0.003579 AR");
    expect(msg).toContain("has 0.000000 AR");
  });

  it("explica vault vazio", () => {
    expect(describeUploadError("vault ainda não existe — adicione ao menos uma entrada antes de publicar")).toContain(
      "nothing to publish",
    );
  });

  it("explica falha de rede e mantém o texto cru entre parênteses", () => {
    const msg = describeUploadError("error sending request for url (https://arweave.net/tx_anchor)");
    expect(msg).toContain("Check your internet connection");
    expect(msg).toContain("error sending request");
  });

  it("devolve o texto cru quando não reconhece o erro", () => {
    expect(describeUploadError("algo inesperado")).toBe("algo inesperado");
  });
});

describe("PublishStepError", () => {
  it("põe número e nome da etapa na frente e não vira 'PublishStepError: ...'", () => {
    const e = new PublishStepError("sign", "boom");
    expect(String(e)).toBe("Step 2 of 3 — Signing and sending the transaction: boom");
    expect(e.step).toBe("sign");
  });
});
