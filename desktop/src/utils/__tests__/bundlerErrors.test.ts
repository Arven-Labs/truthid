import { describe, it, expect } from "vitest";
import { describeBundlerError, describeBundlerHttpError } from "../bundlerErrors";

describe("describeBundlerError", () => {
  it("explains AA24 in plain words and keeps the code", () => {
    const msg = describeBundlerError({
      message: "UserOperation reverted with reason: AA24 signature error",
      code: -32507,
    });
    expect(msg).toContain("not authorized on your account");
    expect(msg).toContain("Manage devices");
    expect(msg.endsWith("(AA24)")).toBe(true);
  });

  it("explains AA21 as missing ETH", () => {
    expect(describeBundlerError({ message: "AA21 didn't pay prefund" })).toContain("enough ETH");
  });

  it("explains AA25 as a pending operation", () => {
    expect(describeBundlerError({ message: "AA25 invalid account nonce" })).toContain("still pending");
  });

  it("flags a rejected API key", () => {
    expect(describeBundlerError({ message: "Invalid API key" })).toContain("Settings");
  });

  it("falls back to the raw message for unknown errors", () => {
    expect(describeBundlerError({ message: "something odd" })).toBe("something odd");
    expect(describeBundlerError("plain string")).toBe("plain string");
  });
});

describe("describeBundlerHttpError", () => {
  it("points to the Pimlico settings on 401/403", () => {
    expect(describeBundlerHttpError(401)).toContain("API key");
    expect(describeBundlerHttpError(403)).toContain("Settings");
  });

  it("explains rate limiting on 429", () => {
    expect(describeBundlerHttpError(429)).toContain("rate limit");
  });

  it("covers other statuses", () => {
    expect(describeBundlerHttpError(500)).toContain("HTTP 500");
  });
});
