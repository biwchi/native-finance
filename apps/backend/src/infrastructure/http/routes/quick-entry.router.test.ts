import { describe, expect, it } from "bun:test";
import { createQuickEntryRouter } from "./quick-entry.router.ts";
import { quickEntryDocumentBase64Limit, quickEntryDocumentTypes } from "../../../application/quick-entry/quick-entry-document.ts";

describe("photo quick entry requests", () => {
  const base = { text: "Recognize purchases", defaultAccountId: crypto.randomUUID(), locale: "en_US", timeZone: "UTC" };

  async function request(photo?: string) {
    let received: unknown;
    const app = createQuickEntryRouter({
      async interpret(input) {
        received = input;
        return { ok: true, value: { referenceNow: new Date().toISOString(), transactions: [] } };
      },
    });
    const response = await app.handle(new Request("http://localhost/quick-entry/interpret", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...base, photo }),
    }));
    return { response, received };
  }

  it("accepts a bounded JPEG data URL and still accepts text-only requests", async () => {
    const photo = "data:image/jpeg;base64,/9j/2Q==";
    expect((await request(photo)).received).toEqual({ ...base, photo });
    expect((await request()).response.status).toBe(200);
  });

  it("rejects remote URLs, other MIME types, invalid base64, and oversized photos before interpretation", async () => {
    for (const photo of ["https://example.com/photo.jpg", "data:image/svg+xml;base64,AAAA",
      "data:image/jpeg;base64,?bad", "data:image/jpeg;base64,", "data:image/jpeg;base64," + "A".repeat(5_592_412)]) {
      const result = await request(photo);
      expect(result.response.status).toBe(422);
      expect(result.received).toBeUndefined();
    }
  });
});

describe("document quick entry HTTP validation", () => {
  async function request(document: unknown) {
    let called = false;
    const app = createQuickEntryRouter({ async interpret() {
      called = true;
      return { ok: true, value: { referenceNow: new Date().toISOString(), transactions: [] } };
    } });
    const response = await app.handle(new Request("http://localhost/quick-entry/interpret", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "", document, defaultAccountId: crypto.randomUUID(), locale: "en_US", timeZone: "UTC" }),
    }));
    return { status: response.status, called };
  }

  it("accepts each allowed format without requiring typed text", async () => {
    for (const [extension, mediaType] of Object.entries(quickEntryDocumentTypes)) {
      expect(await request({ filename: `Statement.${extension.toUpperCase()}`, mediaType, data: "YWJj" }))
        .toEqual({ status: 200, called: true });
    }
  });

  it("rejects unsupported, empty, remote, malformed and oversized payloads before the controller", async () => {
    const document = { filename: "statement.pdf", mediaType: "application/pdf", data: "YWJj" };
    for (const invalid of [
      { ...document, filename: "script.exe" }, { ...document, filename: "../statement.pdf" },
      { ...document, filename: "" }, { ...document, mediaType: "text/html" },
      { ...document, data: "" }, { ...document, data: "?bad" },
      { ...document, data: "https://example.com/statement.pdf" },
      { ...document, data: "A".repeat(quickEntryDocumentBase64Limit + 4) },
    ]) {
      expect(await request(invalid)).toEqual({ status: 422, called: false });
    }
  });
});

describe("quick entry error contract", () => {
  it("returns the machine-readable empty extraction code with the compatible message", async () => {
    const app = createQuickEntryRouter({ async interpret() {
      return { ok: false, error: { code: "empty_extraction" as const, message: "No transactions could be read." } };
    } });
    const response = await app.handle(new Request("http://localhost/quick-entry/interpret", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: "coffee",
        defaultAccountId: crypto.randomUUID(),
        locale: "en_US",
        timeZone: "UTC",
      }),
    }));

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({
      message: "No transactions could be read.",
      code: "empty_extraction",
    });
  });
});
