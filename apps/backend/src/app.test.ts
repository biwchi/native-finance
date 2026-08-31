import { describe, expect, it } from "bun:test";

import { app } from "./app.ts";

describe("Finance Tracker API", () => {
  it("reports its health", async () => {
    const response = await app.handle(
      new Request("http://localhost/health"),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      service: "finance-tracker-api",
      status: "ok",
    });
  });

  it("returns 404 for an unknown route", async () => {
    const response = await app.handle(
      new Request("http://localhost/does-not-exist"),
    );

    expect(response.status).toBe(404);
  });
});

