import { describe, expect, it } from "bun:test";
import { TypeCompiler } from "@sinclair/typebox/compiler";
import { accountBodySchema } from "./account.http-schema.ts";
import { normalizeChange } from "../../sync/sync-validation.ts";

const validate = TypeCompiler.Compile(accountBodySchema);
const details = { name: "Everyday", currency: "USD", icon: "wallet", iconColor: "blue" };
const id = "10000000-0000-4000-8000-000000000001";
const times = { createdAt: "2026-09-12T00:00:00Z", updatedAt: "2026-09-12T00:00:00Z" };

describe("account balance contract", () => {
  it("accepts accounts without type and validates signed decimal balances", () => {
    expect(validate.Check(details)).toBeTrue();
    for (const initialBalance of ["0", "-0.0000", "12.3456", "-500", "999999999999999.9999"]) {
      expect(validate.Check({ ...details, initialBalance })).toBeTrue();
      const change = normalizeChange({ entity: "account", key: id, baseVersion: null,
        data: { ...details, ...times, id, sortOrder: 0, initialBalance } });
      expect(change.data?.initialBalance).toBe(initialBalance);
    }
  });
  it("rejects malformed, overflowing and overprecise balances in HTTP and sync", () => {
    for (const initialBalance of ["", "1e3", "1x2", "12,50", "1000000000000000", "0.00001", "NaN", 100, null]) {
      expect(validate.Check({ ...details, initialBalance })).toBeFalse();
      expect(() => normalizeChange({ entity: "account", key: id, baseVersion: null,
        data: { ...details, ...times, id, sortOrder: 0, initialBalance } })).toThrow();
    }
  });
  it("discards legacy account type and leaves omitted balances unchanged", () => {
    const change = normalizeChange({ entity: "account", key: id, baseVersion: null,
      data: { ...details, ...times, id, sortOrder: 0, type: "checking" } });
    expect(change.data).not.toHaveProperty("type");
    expect(change.data).not.toHaveProperty("initialBalance");
  });
});
