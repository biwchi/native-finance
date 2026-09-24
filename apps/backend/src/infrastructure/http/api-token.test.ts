import { describe, expect, it } from "bun:test";

import { hasValidApiToken } from "./create-http-app.ts";

describe("API token authentication", () => {
  it("allows local development when no token is configured", () => {
    expect(hasValidApiToken(new Request("http://localhost/api/v1/accounts"))).toBeTrue();
  });

  it("accepts only the configured token", () => {
    const valid = new Request("http://localhost/api/v1/accounts", {
      headers: { "X-API-Key": "test-secret" },
    });
    const invalid = new Request("http://localhost/api/v1/accounts", {
      headers: { "X-API-Key": "wrong-secret" },
    });

    expect(hasValidApiToken(valid, "test-secret")).toBeTrue();
    expect(hasValidApiToken(invalid, "test-secret")).toBeFalse();
    expect(hasValidApiToken(
      new Request("http://localhost/api/v1/accounts"),
      "test-secret",
    )).toBeFalse();
  });
});
