import { afterAll, beforeEach, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";

import { app } from "./app.ts";
import { db } from "./db/client.ts";
import { accounts, recurringSchedules, transactions } from "./db/schema.ts";
import { materializeRecurringSchedule } from "./services/recurring-transactions.ts";

const databaseDescribe = Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;
type Upcoming = { id: string; occurredAt: string; endAt: string | null; amount: string; accountId: string };
type Created = { id: string; recurrence: { id: string } };

databaseDescribe("recurring template editing and deletion", () => {
  const accountIds: string[] = [];
  let accountId: string;
  const firstDate = "2100-01-31T12:00:00.000Z";

  beforeEach(async () => {
    const [account] = await db.insert(accounts).values({
      name: `Recurring mutation test ${crypto.randomUUID()}`, type: "checking", currency: "USD",
    }).returning();
    accountId = account!.id;
    accountIds.push(accountId);
  });

  afterAll(async () => {
    for (const id of accountIds) await db.delete(accounts).where(eq(accounts.id, id));
  });

  it("edits a projected template without rewriting historical entries or inserting an early occurrence", async () => {
    const pastDate = new Date(Date.UTC(new Date().getUTCFullYear() - 1, 0, 31, 12)).toISOString();
    const created = await create({ occurredAt: pastDate, recurrence: { frequency: "yearly" } });
    const [item] = await upcoming();
    const before = await ledger();
    const response = await update(item!, { amount: "29.99", merchant: "New subscription", note: "New template" });
    expect(response.status).toBe(200);
    expect(await ledger()).toEqual(before);
    expect((await upcoming())[0]).toMatchObject({ id: created.recurrence.id, amount: "29.9900", merchant: "New subscription" });
  });

  it("updates a saved future occurrence and its next date, frequency, and end date", async () => {
    const created = await create();
    const [item] = await upcoming();
    const response = await update(item!, {
      occurredAt: "2100-02-03T12:00:00.000Z", amount: "40", merchant: "Internet",
      recurrence: { frequency: "weekly", endAt: "2100-02-17T12:00:00.000Z" },
    });
    expect(response.status).toBe(200);
    expect((await ledger())[0]).toMatchObject({ id: created.id, amount: "40.0000", occurredAt: new Date("2100-02-03T12:00:00.000Z") });
    expect((await upcoming())[0]).toMatchObject({ occurredAt: "2100-02-03T12:00:00.000Z", endAt: "2100-02-17T12:00:00.000Z", frequency: "weekly" });
    const [schedule] = await db.select().from(recurringSchedules).where(eq(recurringSchedules.id, item!.id));
    expect(schedule?.nextOccurrenceAt?.toISOString()).toBe("2100-02-10T12:00:00.000Z");
  });

  it("moves only future template entries to a different account and currency", async () => {
    const created = await create();
    const [item] = await upcoming();
    const [destination] = await db.insert(accounts).values({ name: "Destination", type: "checking", currency: "EUR" }).returning();
    accountIds.push(destination!.id);
    expect((await update(item!, { accountId: destination!.id })).status).toBe(200);
    expect(await upcoming()).toEqual([]);
    const [stored] = await db.select().from(transactions).where(eq(transactions.id, created.id));
    expect(stored).toMatchObject({ accountId: destination!.id, currency: "EUR" });
  });

  it("retains a month-end anchor when only the amount changes", async () => {
    const created = await create();
    await db.delete(transactions).where(eq(transactions.id, created.id));
    const [item] = await upcoming();
    expect(item!.occurredAt).toBe("2100-02-28T12:00:00.000Z");
    expect((await update(item!, { amount: "20" })).status).toBe(200);
    expect((await remove(item!, "occurrence")).status).toBe(200);
    expect((await upcoming())[0]!.occurredAt).toBe("2100-03-31T12:00:00.000Z");
  });

  it("converts an edited projected occurrence to one-time when repeat is turned off", async () => {
    const created = await create();
    await db.delete(transactions).where(eq(transactions.id, created.id));
    const [item] = await upcoming();
    expect((await update(item!, { recurrence: null, amount: "17" })).status).toBe(200);
    expect(await upcoming()).toEqual([]);
    expect(await ledger()).toMatchObject([{ amount: "17.0000", recurringScheduleId: null, occurredAt: new Date(item!.occurredAt) }]);
  });

  for (const recorded of [false, true]) {
    for (const action of ["occurrence", "stopRepeating", "occurrenceAndFuture"] as const) {
      it(`${action} handles a ${recorded ? "saved" : "projected"} upcoming occurrence`, async () => {
        const created = await create();
        if (!recorded) await db.delete(transactions).where(eq(transactions.id, created.id));
        const [item] = await upcoming();
        expect((await remove(item!, action)).status).toBe(200);

        if (action === "occurrence") {
          expect(await ledger()).toEqual([]);
          expect((await upcoming())[0]!.occurredAt).toBe(recorded ? "2100-02-28T12:00:00.000Z" : "2100-03-31T12:00:00.000Z");
          await materializeRecurringSchedule(item!.id, new Date("2100-03-31T12:00:00.000Z"));
          expect((await ledger()).some((row) => row.occurredAt.toISOString() === item!.occurredAt)).toBeFalse();
        } else {
          expect(await upcoming()).toEqual([]);
          const rows = await ledger();
          expect(rows).toHaveLength(action === "stopRepeating" ? 1 : 0);
          if (action === "stopRepeating") {
            expect(rows[0]).toMatchObject({ recurringScheduleId: null, occurredAt: new Date(item!.occurredAt) });
          }
          await materializeRecurringSchedule(item!.id, new Date("2100-12-31T12:00:00.000Z"));
          expect(await ledger()).toEqual(rows);
        }
      });
    }
  }

  for (const action of ["occurrence", "stopRepeating", "occurrenceAndFuture"] as const) {
    it(`${action} on a historical transaction preserves other past entries`, async () => {
      const created = await create();
      const history = await db.insert(transactions).values([1, 2].map((day) => ({
        accountId, kind: "expense" as const, currency: "USD", amount: "14.99",
        recurringScheduleId: created.recurrence.id, occurredAt: new Date(`2020-01-0${day}T12:00:00.000Z`),
      }))).returning();
      const response = await request(`/api/v1/transactions/${history[0]!.id}?action=${action}`, "DELETE");
      expect(response.status).toBe(200);
      const rows = await ledger();
      expect(rows.some((row) => row.id === history[1]!.id)).toBeTrue();
      expect(rows.some((row) => row.id === history[0]!.id)).toBe(action === "stopRepeating");
      expect(rows.some((row) => row.id === created.id)).toBe(action === "occurrence");
      expect((await upcoming()).length).toBe(action === "occurrence" ? 1 : 0);
    });
  }

  it("rejects stale skips and edits without deleting the following occurrence", async () => {
    await create();
    const [item] = await upcoming();
    expect((await remove(item!, "occurrence")).status).toBe(200);
    const next = await upcoming();
    expect((await remove(item!, "occurrence")).status).toBe(409);
    expect((await update(item!, { amount: "99" })).status).toBe(409);
    expect(await upcoming()).toEqual(next);
  });

  it("serializes skipping with materialization so a deleted date cannot return", async () => {
    const created = await create();
    await db.delete(transactions).where(eq(transactions.id, created.id));
    const [item] = await upcoming();
    const [response] = await Promise.all([
      remove(item!, "occurrence"),
      materializeRecurringSchedule(item!.id, new Date("2100-03-31T12:00:00.000Z")),
    ]);
    expect(response.status).toBe(200);
    expect((await ledger()).map((row) => row.occurredAt.toISOString())).toEqual(["2100-03-31T12:00:00.000Z"]);
  });

  function draft() {
    return { accountId, kind: "expense", amount: "14.99", merchant: "Netflix", occurredAt: firstDate, recurrence: { frequency: "monthly" } };
  }
  async function create(overrides: Record<string, unknown> = {}): Promise<Created> {
    const response = await request("/api/v1/transactions", "POST", { ...draft(), ...overrides });
    expect(response.status).toBe(201);
    return await response.json() as Created;
  }
  async function upcoming(): Promise<Upcoming[]> {
    const response = await request(`/api/v1/transactions/upcoming?accountId=${accountId}`);
    expect(response.status).toBe(200);
    return await response.json() as Upcoming[];
  }
  function update(item: Upcoming, overrides: Record<string, unknown> = {}) {
    return request(`/api/v1/transactions/recurring/${item.id}`, "PUT", {
      expectedOccurredAt: item.occurredAt,
      transaction: { ...draft(), occurredAt: item.occurredAt, ...overrides },
    });
  }
  function remove(item: Upcoming, action: string) {
    return request(`/api/v1/transactions/recurring/${item.id}?action=${action}&occurredAt=${encodeURIComponent(item.occurredAt)}`, "DELETE");
  }
  function ledger() {
    return db.select().from(transactions).where(eq(transactions.accountId, accountId)).orderBy(transactions.occurredAt);
  }
});

function request(path: string, method = "GET", body?: unknown) {
  return app.handle(new Request(`http://localhost${path}`, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}
