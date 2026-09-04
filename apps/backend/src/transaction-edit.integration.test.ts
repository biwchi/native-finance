import { afterAll, beforeAll, beforeEach, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";

import { app } from "./app.ts";
import { db } from "./infrastructure/db/client.ts";
import {
  accounts,
  categories,
  recurringSchedules,
  transactions,
} from "./infrastructure/db/schema/index.ts";

const databaseDescribe = Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;
type TransactionResponse = { id: string; createdAt: string; updatedAt: string };

databaseDescribe("transaction editing", () => {
  const accountIds: string[] = [];
  let accountId: string;
  let destinationId: string;
  let foodId: string;
  let salaryId: string;
  let original: TransactionResponse;

  beforeAll(async () => {
    const seeded = await db.select().from(categories);
    foodId = seeded.find((category) => category.systemKey === "expense.food-drink")!.id;
    salaryId = seeded.find((category) => category.systemKey === "income.salary")!.id;

    for (const currency of ["KZT", "USD"]) {
      const [account] = await db.insert(accounts).values({
        name: `Transaction edit test ${crypto.randomUUID()}`,
        type: "checking",
        currency,
      }).returning();
      accountIds.push(account!.id);
    }
    accountId = accountIds[0]!;
    destinationId = accountIds[1]!;
  });

  beforeEach(async () => {
    const response = await request("/api/v1/transactions", "POST", draft());
    expect(response.status).toBe(201);
    original = await response.json() as TransactionResponse;
  });

  afterAll(async () => {
    for (const id of accountIds) {
      await db.delete(accounts).where(eq(accounts.id, id));
    }
  });

  it("updates the same record and persists its category, amount, note, and date", async () => {
    const response = await update({
      ...draft(), kind: "income", categoryId: salaryId, amount: "1000.1250",
      note: "  New note  ",
      occurredAt: "2026-09-01T07:08:09.123Z",
    });
    expect(response.status).toBe(200);
    const edited = await response.json() as TransactionResponse;
    expect(edited).toMatchObject({
      id: original.id, kind: "income", amount: "1000.1250", currency: "KZT",
      note: "New note", category: { id: salaryId }, recurrence: null,
      occurredAt: "2026-09-01T07:08:09.123Z", createdAt: original.createdAt,
    });
    expect(new Date(edited.updatedAt).getTime()).toBeGreaterThanOrEqual(new Date(original.updatedAt).getTime());

    const list = await (await request(`/api/v1/transactions?accountId=${accountId}`)).json() as TransactionResponse[];
    expect(list.filter((item: { id: string }) => item.id === original.id)).toEqual([edited]);
  });

  for (const mode of ["omitted", "null", "blank"] as const) {
    it(`clears optional fields when ${mode}`, async () => {
      const { categoryId: _, note: __, ...required } = draft();
      const body = mode === "omitted" ? required : {
        ...required, categoryId: null,
        note: mode === "blank" ? "  " : null,
      };
      const response = await update(body);
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ category: null, note: null, recurrence: null });
      const [stored] = await db.select().from(transactions).where(eq(transactions.id, original.id));
      expect(stored).toMatchObject({ categoryId: null, note: null });
    });
  }

  it("moves an edited transaction to its new account and currency", async () => {
    const response = await update({ ...draft(), accountId: destinationId });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ id: original.id, accountId: destinationId, currency: "USD" });

    const previous = await (await request(`/api/v1/transactions?accountId=${accountId}`)).json() as TransactionResponse[];
    const destination = await (await request(`/api/v1/transactions?accountId=${destinationId}`)).json() as TransactionResponse[];
    expect(previous.some((item: { id: string }) => item.id === original.id)).toBeFalse();
    expect(destination.some((item: { id: string }) => item.id === original.id)).toBeTrue();
  });

  it("preserves the historical currency for edits within the same account", async () => {
    await db.update(accounts).set({ currency: "EUR" }).where(eq(accounts.id, accountId));
    try {
      const response = await update({ ...draft(), note: "Only a note changed" });
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ currency: "KZT", note: "Only a note changed" });
    } finally {
      await db.update(accounts).set({ currency: "KZT" }).where(eq(accounts.id, accountId));
    }
  });

  it("deletes a transaction and returns 404 when deleting it again", async () => {
    const deleted = await request(`/api/v1/transactions/${original.id}`, "DELETE");
    expect(deleted.status).toBe(200);
    expect(await deleted.json()).toEqual({ deleted: true });

    const [stored] = await db.select().from(transactions).where(eq(transactions.id, original.id));
    expect(stored).toBeUndefined();

    const missing = await request(`/api/v1/transactions/${original.id}`, "DELETE");
    expect(missing.status).toBe(404);
    expect(await missing.json()).toEqual({ message: "Transaction not found" });
  });

  it("creates every due past occurrence and does not recreate a deleted one", async () => {
    const response = await request("/api/v1/transactions", "POST", {
      ...draft(),
      occurredAt: "2026-08-28T12:30:00.000Z",
      recurrence: {
        frequency: "daily",
        endAt: "2026-08-31T12:30:00.000Z",
      },
    });
    expect(response.status).toBe(201);
    const recurring = await response.json() as TransactionResponse & {
      recurrence: { id: string; frequency: string; endAt: string };
    };
    expect(recurring.recurrence).toMatchObject({ frequency: "daily" });

    const beforeDelete = await listScheduleTransactions(recurring.recurrence.id);
    expect(beforeDelete.map((transaction) => transaction.occurredAt)).toEqual([
      "2026-08-28T12:30:00.000Z",
      "2026-08-29T12:30:00.000Z",
      "2026-08-30T12:30:00.000Z",
      "2026-08-31T12:30:00.000Z",
    ]);

    const deletedID = beforeDelete[1]!.id;
    expect((await request(`/api/v1/transactions/${deletedID}`, "DELETE")).status).toBe(200);
    expect((await request(`/api/v1/transactions?accountId=${accountId}`)).status).toBe(200);

    const afterDelete = await listScheduleTransactions(recurring.recurrence.id);
    expect(afterDelete.map((transaction) => transaction.id)).not.toContain(deletedID);
    expect(afterDelete).toHaveLength(3);
  });

  it("turns recurrence off when an occurrence is saved without a rule", async () => {
    const response = await request("/api/v1/transactions", "POST", {
      ...draft(),
      recurrence: { frequency: "monthly" },
    });
    const recurring = await response.json() as TransactionResponse & {
      recurrence: { id: string };
    };

    const edited = await request(
      `/api/v1/transactions/${recurring.id}`,
      "PUT",
      { ...draft(), note: "No longer recurring" },
    );
    expect(edited.status).toBe(200);
    expect(await edited.json()).toMatchObject({ recurrence: null });

    const [schedule] = await db
      .select()
      .from(recurringSchedules)
      .where(eq(recurringSchedules.id, recurring.recurrence.id));
    expect(schedule).toBeUndefined();
  });

  it("rejects invalid edits without changing the original transaction", async () => {
    const [before] = await db.select().from(transactions).where(eq(transactions.id, original.id));
    const invalid = [
      { body: { ...draft(), categoryId: salaryId }, status: 400 },
      { body: { ...draft(), accountId: crypto.randomUUID() }, status: 404 },
      { body: { ...draft(), categoryId: crypto.randomUUID() }, status: 404 },
      { body: { ...draft(), amount: "0" }, status: 422 },
      { body: { ...draft(), occurredAt: "invalid" }, status: 422 },
    ];
    for (const { body, status } of invalid) {
      expect((await update(body)).status).toBe(status);
    }
    const [after] = await db.select().from(transactions).where(eq(transactions.id, original.id));
    expect(after).toEqual(before);
    const missing = await request(`/api/v1/transactions/${crypto.randomUUID()}`, "PUT", draft());
    expect(missing.status).toBe(404);
    expect(await missing.json()).toEqual({ message: "Transaction not found" });
  });

  function draft() {
    return {
      accountId, kind: "expense", amount: "12.5000", categoryId: foodId,
      note: "Original coffee", occurredAt: "2026-08-31T12:30:00.123Z",
    };
  }

  function update(body: unknown) {
    return request(`/api/v1/transactions/${original.id}`, "PUT", body);
  }

  async function listScheduleTransactions(scheduleId: string) {
    return await db
      .select({ id: transactions.id, occurredAt: transactions.occurredAt })
      .from(transactions)
      .where(eq(transactions.recurringScheduleId, scheduleId))
      .orderBy(transactions.occurredAt)
      .then((rows) => rows.map((row) => ({
        id: row.id,
        occurredAt: row.occurredAt.toISOString(),
      })));
  }
});

function request(path: string, method = "GET", body?: unknown): Promise<Response> {
  return app.handle(new Request(`http://localhost${path}`, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}
