import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";

import { app } from "./app.ts";
import { db } from "./infrastructure/db/client.ts";
import { accounts, categories } from "./infrastructure/db/schema/index.ts";

const databaseDescribe =
  Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;

databaseDescribe("monthly budget API", () => {
  let accountId = "";
  let foodId = "";
  let transportId = "";
  let salaryId = "";

  beforeAll(async () => {
    const seeded = await db.select().from(categories);
    foodId = seeded.find((category) => category.systemKey === "expense.food-drink")!.id;
    transportId = seeded.find((category) => category.systemKey === "expense.transport")!.id;
    salaryId = seeded.find((category) => category.systemKey === "income.salary")!.id;

    const [account] = await db
      .insert(accounts)
      .values({
        name: `Budget test ${crypto.randomUUID()}`,
        type: "checking",
        currency: "USD",
      })
      .returning();
    accountId = account!.id;
  });

  afterAll(async () => {
    if (accountId) {
      await db.delete(accounts).where(eq(accounts.id, accountId));
    }
  });

  it("saves and replaces a layered monthly budget", async () => {
    const groupId = crypto.randomUUID();
    const saveResponse = await request("/api/v1/budgets/monthly", "PUT", {
      accountId,
      month: "2026-09",
      currency: "usd",
      monthlyLimit: "3800",
      groups: [{ id: groupId, name: "Needs", limit: "500" }],
      categoryAssignments: [
        { categoryId: foodId, groupId },
        { categoryId: transportId, limit: "150" },
      ],
    });
    const saved = (await saveResponse.json()) as {
      id: string;
      currency: string;
      monthlyLimit: string;
      groups: Array<{ id: string; name: string; limit: string; sortOrder: number }>;
      categoryAssignments: Array<{
        categoryId: string;
        groupId: string | null;
        limit: string | null;
      }>;
    };

    expect(saveResponse.status).toBe(200);
    expect(saved).toMatchObject({
      accountId,
      month: "2026-09",
      currency: "USD",
      monthlyLimit: "3800.0000",
    });
    expect(saved.groups).toEqual([
      { id: groupId, name: "Needs", limit: "500.0000", sortOrder: 0 },
    ]);
    expect(saved.categoryAssignments).toEqual(
      expect.arrayContaining([
        { categoryId: foodId, groupId, limit: null },
        { categoryId: transportId, groupId: null, limit: "150.0000" },
      ]),
    );

    const getResponse = await request(
      `/api/v1/budgets/monthly?month=2026-09&accountId=${accountId}`,
    );
    expect(getResponse.status).toBe(200);
    expect(await getResponse.json()).toEqual(saved);

    const clearResponse = await request("/api/v1/budgets/monthly", "PUT", {
      accountId,
      month: "2026-09",
      currency: "USD",
      monthlyLimit: null,
      groups: [],
      categoryAssignments: [],
    });
    expect(clearResponse.status).toBe(200);
    expect(await clearResponse.json()).toBeNull();

    const emptyResponse = await request(
      `/api/v1/budgets/monthly?month=2026-09&accountId=${accountId}`,
    );
    expect(await emptyResponse.json()).toBeNull();
  });

  it("rejects duplicate and income-category assignments", async () => {
    const duplicateResponse = await request("/api/v1/budgets/monthly", "PUT", {
      accountId,
      month: "2026-10",
      currency: "USD",
      groups: [],
      categoryAssignments: [
        { categoryId: foodId, limit: "100" },
        { categoryId: foodId, limit: "200" },
      ],
    });
    expect(duplicateResponse.status).toBe(400);
    expect(await duplicateResponse.json()).toEqual({
      message: "Each category can only appear once in a monthly budget",
    });

    const incomeResponse = await request("/api/v1/budgets/monthly", "PUT", {
      accountId,
      month: "2026-10",
      currency: "USD",
      groups: [],
      categoryAssignments: [{ categoryId: salaryId, limit: "100" }],
    });
    expect(incomeResponse.status).toBe(400);
    expect(await incomeResponse.json()).toEqual({
      message: "Only expense categories can have spending budgets",
    });
  });
});

function request(path: string, method = "GET", body?: unknown): Promise<Response> {
  return app.handle(
    new Request(`http://localhost${path}`, {
      method,
      headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
}
