import { describe, it, expect } from "vitest";
import { describeSystemError } from "../systemErrors";

describe("describeSystemError", () => {
  it("explica permissão negada e dá o chown", () => {
    const msg = describeSystemError("Permission denied (os error 13)");
    expect(msg).toContain("sudo chown -R $USER ~/.truthid");
    expect(msg).toContain("os error 13");
  });

  it("explica keyring indisponível", () => {
    expect(describeSystemError("Platform secure storage failure: DBus error")).toContain("system keyring");
  });

  it("deixa passar o que não reconhece", () => {
    expect(describeSystemError("outra coisa")).toBe("outra coisa");
  });
});
