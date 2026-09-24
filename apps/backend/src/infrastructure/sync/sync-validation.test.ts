import { describe, expect, it } from "bun:test";
import { normalizeChange } from "./sync-validation.ts";

const id = "60000000-0000-0000-0000-000000000001";
const recipient = { id, name: "Alexey", icon: "user", color: "blue" };

describe("recipient sync validation", () => {
  it("accepts saved positions and keeps omission distinct for legacy edits", () => {
    expect(normalizeChange({ entity: "debt", key: id, baseVersion: null, data: { ...recipient, sortOrder: 3 } }).data?.sortOrder).toBe(3);
    expect(normalizeChange({ entity: "debt", key: id, baseVersion: null, data: recipient }).data).not.toHaveProperty("sortOrder");
  });

  it("rejects invalid positions before persisting any recipient changes", () => {
    for (const sortOrder of [-1, 0.5, null, "1", 2147483648, Number.NaN]) {
      expect(() => normalizeChange({ entity: "debt", key: id, baseVersion: null, data: { ...recipient, sortOrder } })).toThrow("Invalid sort order");
    }
  });

  it("accepts recipient tombstones", () => {
    expect(normalizeChange({ entity: "debt", key: id, baseVersion: "2", data: null }).data).toBeNull();
  });
});

describe("transaction sync validation", () => {
  it("normalizes the counterparty and supports clearing it", () => {
    const record = { id, accountId: "60000000-0000-0000-0000-000000000002", kind: "expense", amount: "300",
      currency: "KZT", note: "Lunch", occurredAt: "2026-09-21T10:00:00.000Z",
      createdAt: "2026-09-21T10:00:00.000Z", updatedAt: "2026-09-21T10:00:00.000Z" };
    const normalize = (extra: Record<string, unknown>) => normalizeChange({ entity: "transaction", key: id, baseVersion: null, data: { ...record, ...extra } }).data;
    expect(normalize({ counterparty: " Urbo Coffee " })?.counterparty).toBe("Urbo Coffee");
    for (const counterparty of [undefined, null, "", "   "]) expect(normalize({ counterparty })?.counterparty).toBeNull();
    expect(() => normalize({ counterparty: "x".repeat(2001) })).toThrow();
  });

  it("accepts a signed input and stores its positive magnitude", () => {
    const data = normalizeChange({ entity: "transaction", key: id, baseVersion: null, data: {
      id, accountId: "60000000-0000-0000-0000-000000000002", kind: "expense", amount: "-12.50",
      currency: "USD", categoryId: null, debtId: null, recurringScheduleId: null,
      counterparty: null, note: null, occurredAt: "2026-09-04T10:00:00.000Z",
      scheduledFor: null, createdAt: "2026-09-04T10:00:00.000Z", updatedAt: "2026-09-04T10:00:00.000Z",
    } }).data;
    expect(data?.amount).toBe("12.50");
  });
});
