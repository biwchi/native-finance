import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";

import { app } from "./app.ts";
import { db } from "./db/client.ts";
import { accounts, recurringSchedules, transactions } from "./db/schema.ts";

const databaseDescribe = Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;
type Upcoming = { id: string; accountId: string; merchant: string; amount: string; occurredAt: string };

databaseDescribe("upcoming recurring transactions", () => {
  const accountIds: string[] = [];
  let accountId: string;
  let otherAccountId: string;
  const startAt = new Date("2100-01-31T12:00:00.000Z");

  beforeAll(async () => {
    for (let index = 0; index < 2; index++) {
      const [account] = await db.insert(accounts).values({
        name: `Upcoming test ${crypto.randomUUID()}`, type: "checking", currency: "USD",
      }).returning();
      accountIds.push(account!.id);
    }
    [accountId, otherAccountId] = accountIds as [string, string];
  });

  afterAll(async () => {
    for (const id of accountIds) await db.delete(accounts).where(eq(accounts.id, id));
  });

  it("returns the future first occurrence once per schedule, sorted, without a four-item API limit", async () => {
    const schedules = [];
    for (const day of [9, 4, 10, 6, 7]) {
      schedules.push(await create({ occurredAt: `2100-09-${String(day).padStart(2, "0")}T12:00:00.000Z` }));
    }
    const other = await create({ accountId: otherAccountId });
    await create({ recurrence: null, merchant: "One-time purchase" });

    const scoped = await upcoming(accountId);
    expect(scoped.map((row) => row.occurredAt)).toEqual([
      "2100-09-04T12:00:00.000Z", "2100-09-06T12:00:00.000Z", "2100-09-07T12:00:00.000Z",
      "2100-09-09T12:00:00.000Z", "2100-09-10T12:00:00.000Z",
    ]);
    expect(new Set(scoped.map((row) => row.id)).size).toBe(5);
    expect(scoped.every((row) => row.accountId === accountId)).toBeTrue();
    expect((await upcoming()).some((row) => row.id === other.recurrence.id)).toBeTrue();
    expect(scoped.map((row) => row.id).sort()).toEqual(schedules.map((row) => row.recurrence.id).sort());
  });

  it("keeps schedules after their recorded occurrence is deleted, using the anchored next date", async () => {
    const created = await create();
    await db.delete(transactions).where(eq(transactions.id, created.id));
    const row = (await upcoming(accountId)).find((item) => item.id === created.recurrence.id);
    expect(row).toMatchObject({ occurredAt: "2100-02-28T12:00:00.000Z", merchant: "Netflix", amount: "14.9900" });
  });

  it("includes a final future occurrence and excludes a schedule once it has ended", async () => {
    const future = await create({ recurrence: { frequency: "monthly", endAt: startAt.toISOString() } });
    expect((await upcoming(accountId)).find((row) => row.id === future.recurrence.id)?.occurredAt)
      .toBe(startAt.toISOString());

    const ended = await create({
      occurredAt: "2020-01-01T12:00:00.000Z",
      recurrence: { frequency: "daily", endAt: "2020-01-02T12:00:00.000Z" },
    });
    expect((await upcoming(accountId)).some((row) => row.id === ended.recurrence.id)).toBeFalse();
  });

  it("uses the current schedule details and removes schedules when recurrence is disabled", async () => {
    const created = await create();
    await db.update(recurringSchedules).set({ merchant: "Updated subscription", amount: "19.99" })
      .where(eq(recurringSchedules.id, created.recurrence.id));
    expect((await upcoming(accountId)).find((row) => row.id === created.recurrence.id))
      .toMatchObject({ merchant: "Updated subscription", amount: "19.9900" });
    await db.delete(recurringSchedules).where(eq(recurringSchedules.id, created.recurrence.id));
    expect((await upcoming(accountId)).some((row) => row.id === created.recurrence.id)).toBeFalse();
  });

  it("rejects an invalid account filter", async () => {
    expect((await request("/api/v1/transactions/upcoming?accountId=invalid")).status).toBe(422);
  });

  async function create(overrides: Record<string, unknown> = {}) {
    const response = await request("/api/v1/transactions", "POST", {
      accountId, kind: "expense", amount: "14.99", merchant: "Netflix",
      occurredAt: startAt.toISOString(), recurrence: { frequency: "monthly" }, ...overrides,
    });
    expect(response.status).toBe(201);
    return await response.json() as { id: string; recurrence: { id: string } };
  }

  async function upcoming(scope?: string): Promise<Upcoming[]> {
    const response = await request(`/api/v1/transactions/upcoming${scope ? `?accountId=${scope}` : ""}`);
    expect(response.status).toBe(200);
    return await response.json() as Upcoming[];
  }
});

function request(path: string, method = "GET", body?: unknown) {
  return app.handle(new Request(`http://localhost${path}`, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}
