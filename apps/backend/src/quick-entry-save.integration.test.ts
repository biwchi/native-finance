import { afterEach, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";
import { app } from "./app.ts";
import { db } from "./infrastructure/db/client.ts";
import { accounts, recurringSchedules } from "./infrastructure/db/schema/index.ts";

const suite = Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;
const ids: string[] = [];
const request = (path: string, method: string, body?: unknown) => app.handle(new Request(`http://localhost/api/v1${path}`, {
  method, headers: { "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body),
}));
async function account(currency: string) {
  const [result] = await db.insert(accounts).values({ name: `Quick entry test ${crypto.randomUUID()}`, initialBalance: "0", currency }).returning();
  ids.push(result!.id);
  return result!;
}

suite("saving quick entry capabilities through the API", () => {
  afterEach(async () => { for (const id of ids.splice(0)) await db.delete(accounts).where(eq(accounts.id, id)); });

  it("saves an exact cross-currency debit and credit in one transfer", async () => {
    const source = await account("USD");
    const destination = await account("KZT");
    const response = await request("/transactions/transfer", "POST", { fromAccountId: source.id, toAccountId: destination.id,
      amount: "100", destinationAmount: "49500", occurredAt: "2100-03-01T12:00:00Z" });
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ source: { amount: "100.0000", currency: "USD", kind: "expense" },
      destination: { amount: "49500.0000", currency: "KZT", kind: "income" } });
    expect((await request("/transactions/transfer", "POST", { fromAccountId: source.id, toAccountId: destination.id,
      amount: "100", occurredAt: "2100-03-01T12:00:00Z" })).status).toBe(400);
  });

  it("keeps a schedule timezone through creation, legacy edits and skipping an occurrence", async () => {
    const source = await account("USD");
    const transaction = { accountId: source.id, kind: "expense", amount: "120", occurredAt: "2100-02-28T19:30:00Z",
      recurrence: { frequency: "monthly", endAt: "2100-04-30T19:30:00Z", timeZone: "Asia/Almaty" } };
    const response = await request("/transactions", "POST", transaction);
    expect(response.status).toBe(201);
    const saved = await response.json();
    expect(saved.recurrence.timeZone).toBe("Asia/Almaty");
    const scheduleId = saved.recurrence.id;
    const load = async () => (await db.select().from(recurringSchedules).where(eq(recurringSchedules.id, scheduleId)))[0]!;
    expect((await load()).nextOccurrenceAt?.toISOString()).toBe("2100-03-31T19:30:00.000Z");
    expect((await request(`/transactions/${saved.id}`, "PUT", { ...transaction, amount: "130",
      recurrence: { frequency: "monthly", endAt: transaction.recurrence.endAt } })).status).toBe(200);
    expect((await load()).timeZone).toBe("Asia/Almaty");
    expect((await request(`/transactions/recurring/${scheduleId}?occurredAt=2100-03-31T19%3A30%3A00Z&action=occurrence`, "DELETE")).status).toBe(200);
    expect((await load()).nextOccurrenceAt?.toISOString()).toBe("2100-04-30T19:30:00.000Z");
  });
});
