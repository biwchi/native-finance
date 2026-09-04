import { describe, expect, it } from "bun:test";

import { error, ok, tryCatch } from "./result.ts";

describe("Result", () => {
  it("creates deterministic success and error values", () => {
    expect(ok(42)).toEqual({ ok: true, value: 42 });
    expect(error("invalid", "Invalid value")).toEqual({
      ok: false,
      error: { code: "invalid", message: "Invalid value" },
    });
  });

  it("maps expected exceptions and rethrows unexpected ones", async () => {
    const mapped = await tryCatch(
      async () => { throw { code: "23505" }; },
      (cause) => typeof cause === "object" && cause !== null &&
          "code" in cause && cause.code === "23505"
        ? { code: "duplicate" as const, message: "Already exists" }
        : null,
    );
    expect(mapped).toEqual({
      ok: false,
      error: { code: "duplicate", message: "Already exists" },
    });

    expect(tryCatch(
      async () => { throw new Error("unexpected"); },
      () => null,
    )).rejects.toThrow("unexpected");
  });
});
