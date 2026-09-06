import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";
import { app } from "./app.ts";
import { db } from "./infrastructure/db/client.ts";
import { accounts, debts, transactions } from "./infrastructure/db/schema/index.ts";

const databaseDescribe = Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;

databaseDescribe("debt recipients and lending", () => {
  let accountId: string;
  const debtIds: string[] = [];

  beforeAll(async () => {
    const [account] = await db.insert(accounts).values({
      name: "Debt integration test", type: "checking", currency: "USD",
    }).returning();
    accountId = account!.id;
  });

  afterAll(async () => {
    await db.delete(accounts).where(eq(accounts.id, accountId));
    for (const id of debtIds) await db.delete(debts).where(eq(debts.id, id));
  });

  async function recipient() {
    const response = await request("/debts", "POST", { name: "  Alexey  " });
    expect(response.status).toBe(201);
    const debt = await response.json() as { id: string; name: string; icon: string; color: string };
    debtIds.push(debt.id);
    expect(debt.name).toBe("Alexey");
    return debt;
  }

  function draft(debtId?: string) {
    return { accountId, kind: "debt", amount: "100.1250", debtId, occurredAt: "2026-09-05T10:00:00.000Z" };
  }

  it("persists a recipient and multiple loans, then removes only the returned loan", async () => {
    const debt = await recipient();
    const recipients = await (await request("/debts")).json() as { id: string }[];
    expect(recipients.some((item) => item.id === debt.id)).toBeTrue();
    const created: string[] = [];
    for (let i = 0; i < 2; i++) {
      const response = await request("/transactions", "POST", draft(debt.id));
      expect(response.status).toBe(201);
      const row = await response.json() as { id: string };
      expect(row).toMatchObject({ kind: "debt", amount: "100.1250", debtId: debt.id, debt, currency: "USD", category: null, recurrence: null });
      created.push(row.id);
    }
    const returned = await request(`/transactions/${created[0]}`, "DELETE");
    expect(returned.status).toBe(200);
    expect((await request(`/transactions/${created[0]}`, "DELETE")).status).toBe(404);
    const rows = await (await request(`/transactions?accountId=${accountId}`)).json() as { id: string; debtId: string }[];
    expect(rows.some((row) => row.id === created[0])).toBeFalse();
    expect(rows.filter((row) => row.debtId === debt.id)).toHaveLength(1);
    const [saved] = await db.select().from(debts).where(eq(debts.id, debt.id));
    expect(saved).toEqual(debt);
  });

  it("changes the recipient and clears the association when changed to expense", async () => {
    const first = await recipient();
    const second = await recipient();
    const created = await (await request("/transactions", "POST", draft(first.id))).json() as { id: string };
    const changed = await request(`/transactions/${created.id}`, "PUT", draft(second.id));
    expect(changed.status).toBe(200);
    expect(await changed.json()).toMatchObject({ debtId: second.id, debt: second });
    const expense = await request(`/transactions/${created.id}`, "PUT", { ...draft(), kind: "expense" });
    expect(expense.status).toBe(200);
    expect(await expense.json()).toMatchObject({ kind: "expense", debtId: null, debt: null });
  });

  it("rejects missing or unknown recipients and incompatible transaction fields", async () => {
    expect((await request("/transactions", "POST", draft())).status).toBe(400);
    expect((await request("/transactions", "POST", draft(crypto.randomUUID()))).status).toBe(404);
    const debt = await recipient();
    for (const fields of [
      { kind: "income" }, { kind: "expense" },
      { recurrence: { frequency: "monthly" } }, { categoryId: crypto.randomUUID() },
    ]) {
      expect((await request("/transactions", "POST", { ...draft(debt.id), ...fields })).status).toBe(400);
    }
    const rows = await db.select().from(transactions).where(eq(transactions.debtId, debt.id));
    expect(rows).toHaveLength(0);
  });

  it("validates debt transactions in batches before any writes", async () => {
    const debt = await recipient();
    const response = await request("/transactions/batch", "POST", { transactions: [
      { type: "transaction", transaction: draft(debt.id) },
      { type: "transaction", transaction: draft(crypto.randomUUID()) },
    ] });
    expect(response.status).toBe(404);
    expect(await db.select().from(transactions).where(eq(transactions.debtId, debt.id))).toHaveLength(0);
    expect((await request("/transactions/batch", "POST", { transactions: [
      { type: "transaction", transaction: draft(debt.id) },
    ] })).status).toBe(201);
  });

  it("persists recipient appearance and updates existing loan responses", async () => {
    const response = await request("/debts", "POST", { name: "Alexey", icon: "star", color: "purple" });
    expect(response.status).toBe(201);
    const debt = await response.json() as { id: string };
    debtIds.push(debt.id);
    expect(debt).toMatchObject({ icon: "star", color: "purple" });
    await request("/transactions", "POST", draft(debt.id));
    const updated = await request(`/debts/${debt.id}`, "PATCH", { icon: "heart", color: "coral" });
    expect(updated.status).toBe(200);
    expect(await updated.json()).toMatchObject({ id: debt.id, name: "Alexey", icon: "heart", color: "coral" });
    const rows = await (await request(`/transactions?accountId=${accountId}`)).json() as { debtId: string; debt: unknown }[];
    expect(rows.find((row) => row.debtId === debt.id)?.debt).toMatchObject({ icon: "heart", color: "coral" });
    const recipients = await (await request("/debts")).json() as { id: string; color: string }[];
    expect(recipients.find((row) => row.id === debt.id)?.color).toBe("coral");
  });

  it("defaults old clients to a blue person icon and rejects invalid appearance", async () => {
    const debt = await recipient();
    expect(debt).toMatchObject({ icon: "user", color: "blue" });
    for (const invalid of [{ icon: "" }, { icon: "  " }, { color: "unknown" }]) {
      expect((await request(`/debts/${debt.id}`, "PATCH", invalid)).status).toBe(422);
      expect((await request("/debts", "POST", { name: "Invalid", ...invalid })).status).toBe(422);
    }
    expect((await request(`/debts/${crypto.randomUUID()}`, "PATCH", { color: "blue" })).status).toBe(404);
  });

  it("rejects empty recipient names and non-positive amounts", async () => {
    expect((await request("/debts", "POST", { name: "  " })).status).toBe(400);
    const debt = await recipient();
    for (const amount of ["0", "-10", "no money"]) {
      expect((await request("/transactions", "POST", { ...draft(debt.id), amount })).status).toBe(422);
    }
  });
});

function request(path: string, method = "GET", body?: unknown) {
  return app.handle(new Request(`http://localhost/api/v1${path}`, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}
