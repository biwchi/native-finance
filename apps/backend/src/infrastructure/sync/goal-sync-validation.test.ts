import { describe, expect, it } from "bun:test";
import { calendarDay, normalizeChange } from "./sync-validation.ts";
import type { SyncChange } from "../../application/sync/sync.repository.ts";

const goal = () => {
  const id = crypto.randomUUID();
  return { entity: "goal", key: id, baseVersion: null, data: {
    id, accountId: crypto.randomUUID(), name: " Dream car ", targetAmount: "25000.1234",
    icon: "car", color: "blue", deadline: "2028-02-29", sortOrder: 0,
    createdAt: "2026-09-22T12:00:00.000Z", updatedAt: "2026-09-22T12:00:00.000Z",
  } } satisfies SyncChange;
};

describe("goal sync validation", () => {
  it("keeps decimal precision and a date-only deadline", () => {
    expect(normalizeChange(goal()).data).toMatchObject({ name: "Dream car", targetAmount: "25000.1234", deadline: "2028-02-29" });
    expect(calendarDay(null)).toBeNull();
  });
  it("rejects invalid days rather than normalizing them into another month", () => {
    for (const date of ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-00", "2026-01-01T00:00:00Z", "", "2026-1-1"]) {
      expect(() => calendarDay(date)).toThrow();
    }
  });
  it("rejects missing accounts, invalid amounts, colors, and positions", () => {
    for (const bad of [{ accountId: null }, { name: " " }, { targetAmount: "0" }, { targetAmount: "-1" },
      { targetAmount: 20 }, { targetAmount: "1.00001" }, { targetAmount: "1000000000000000" },
      { color: "not-a-color" }, { sortOrder: -1 }, { sortOrder: 1.5 }, { icon: "" }]) {
      const change = goal();
      expect(() => normalizeChange({ ...change, data: { ...change.data, ...bad } })).toThrow();
    }
  });
  it("clears omitted deadlines and supports tombstones", () => {
    const change = goal();
    expect(normalizeChange({ ...change, data: { ...change.data, deadline: undefined } }).data?.deadline).toBeNull();
    expect(normalizeChange({ ...change, data: null }).data).toBeNull();
  });
});
