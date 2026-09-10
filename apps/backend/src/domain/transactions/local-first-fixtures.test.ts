import { describe, expect, it } from "bun:test";
import fixtures from "../../../../../fixtures/local-first-recurrence.json";
import { occurrenceId } from "./occurrence-id.ts";
import { recurrencePlan } from "./recurrence.ts";
import type { RecurrenceFrequency } from "./transaction.ts";

describe("shared Swift/backend recurrence fixtures", () => {
  it("uses the same UUID v5 namespace and canonical UTC timestamp", () => {
    expect(occurrenceId(fixtures.occurrence.scheduleId, new Date(fixtures.occurrence.scheduledFor))).toBe(fixtures.occurrence.id);
  });
  for (const fixture of fixtures.schedules) it(`preserves ${fixture.frequency} anchors including leap days`, () => {
    const start = new Date(fixture.dates[0]!); const end = new Date(fixture.dates.at(-1)!);
    const result = recurrencePlan(start, start, fixture.frequency as RecurrenceFrequency, end, end);
    expect(result.dates.map(d => d.toISOString())).toEqual(fixture.dates.map(d => new Date(d).toISOString()));
    expect(result.nextOccurrenceAt).toBeNull();
  });
});
