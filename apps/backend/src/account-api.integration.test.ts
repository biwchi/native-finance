import { describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";
import { app } from "./app.ts";
import { db } from "./infrastructure/db/client.ts";
import { accounts, transactions } from "./infrastructure/db/schema/index.ts";

const suite = Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;
const request = (path: string, method: string, body: unknown) => app.handle(new Request(`http://localhost/api/v1/accounts${path}`, {
  method, headers: { "content-type": "application/json" }, body: JSON.stringify(body),
}));

suite("account initial balance API", () => {
  it("creates and edits balances without an account type or income entries", async () => {
    const details = { name: "Initial balance test", currency: "usd", icon: "wallet", iconColor: "blue" };
    const response = await request("", "POST", { ...details, initialBalance: "1234.5678" });
    expect(response.status).toBe(201);
    const account = await response.json() as { id: string; initialBalance: string; currency: string };
    try {
      expect(account).toMatchObject({ initialBalance: "1234.5678", currency: "USD" });
      expect(account).not.toHaveProperty("type");
      const rename = await request(`/${account.id}`, "PATCH", { ...details, name: "Renamed" });
      expect(rename.status).toBe(200);
      expect(await rename.json()).toMatchObject({ initialBalance: "1234.5678" });
      const correction = await request(`/${account.id}`, "PATCH", { ...details, initialBalance: "-5.25" });
      expect(correction.status).toBe(200);
      expect(await correction.json()).toMatchObject({ initialBalance: "-5.2500" });
      expect(await db.select().from(transactions).where(eq(transactions.accountId, account.id))).toHaveLength(0);
      const invalid = await request(`/${account.id}`, "PATCH", { ...details, initialBalance: "1x2" });
      expect(invalid.status).toBe(422);
      expect((await db.select().from(accounts).where(eq(accounts.id, account.id)))[0]?.initialBalance).toBe("-5.2500");
    } finally {
      await db.delete(accounts).where(eq(accounts.id, account.id));
    }
  });
});
