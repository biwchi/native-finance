import { describe, expect, it } from "bun:test";
import { createSettingsRouter } from "./settings.router.ts";

function request(body?: unknown) {
  return new Request("http://localhost/settings/data", {
    method: "DELETE",
    headers: { "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

describe("settings data deletion", () => {
  it("rejects absent and inexact confirmation without deleting anything", async () => {
    let calls = 0;
    const router = createSettingsRouter({ deleteAll: async () => { calls++; } });
    for (const body of [undefined, {}, { confirmation: "" }, { confirmation: "Confirm" },
      { confirmation: " confirm " }, { confirmation: true }]) {
      const response = await router.handle(request(body));
      expect(response.status).toBe(422);
    }
    expect(calls).toBe(0);
  });

  it("only reports success after deletion finishes", async () => {
    let calls = 0;
    const router = createSettingsRouter({ deleteAll: async () => { calls++; } });
    const response = await router.handle(request({ confirmation: "confirm" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ deleted: true });
    expect(calls).toBe(1);
  });

  it("does not report success if the database rejects deletion", async () => {
    const router = createSettingsRouter({ deleteAll: async () => { throw new Error("Deletion failed"); } });
    const response = await router.handle(request({ confirmation: "confirm" }));
    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain('"deleted":true');
  });
});
