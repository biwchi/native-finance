import { describe, expect, it } from "bun:test";

import {
  nextRecurrenceDate,
  recurrencePlan,
} from "./recurring-transactions.ts";

describe("recurring transaction dates", () => {
  it("keeps the original day when monthly dates cross a shorter month", () => {
    const start = new Date("2024-01-31T09:15:00.000Z");
    const february = nextRecurrenceDate(start, start, "monthly");
    const march = nextRecurrenceDate(february, start, "monthly");

    expect(february.toISOString()).toBe("2024-02-29T09:15:00.000Z");
    expect(march.toISOString()).toBe("2024-03-31T09:15:00.000Z");
  });

  it("keeps leap-day yearly schedules on the last valid February day", () => {
    const start = new Date("2024-02-29T18:30:00.000Z");

    expect(nextRecurrenceDate(start, start, "yearly").toISOString()).toBe(
      "2025-02-28T18:30:00.000Z",
    );
  });

  it("materializes past occurrences through now and respects the end date", () => {
    const plan = recurrencePlan(
      new Date("2026-08-29T12:00:00.000Z"),
      new Date("2026-08-28T12:00:00.000Z"),
      "daily",
      new Date("2026-08-31T12:00:00.000Z"),
      new Date("2026-09-02T12:00:00.000Z"),
    );

    expect(plan.dates.map((date) => date.toISOString())).toEqual([
      "2026-08-29T12:00:00.000Z",
      "2026-08-30T12:00:00.000Z",
      "2026-08-31T12:00:00.000Z",
    ]);
    expect(plan.nextOccurrenceAt).toBeNull();
  });
});
