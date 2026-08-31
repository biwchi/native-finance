import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";

import { app } from "./app.ts";
import { db } from "./db/client.ts";
import { accounts, categories, transactions } from "./db/schema.ts";
import { normalizeTransactionDescription } from "./services/category-resolution.ts";

const databaseDescribe =
  Bun.env.RUN_DATABASE_TESTS === "1" ? describe : describe.skip;

databaseDescribe("category and transaction API integration", () => {
  const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 12);
  let accountId = "";
  let foodCategoryId = "";
  let fuelCategoryId = "";
  let salaryCategoryId = "";
  const customCategoryIds: string[] = [];

  beforeAll(async () => {
    const categoriesResponse = await request("/api/v1/categories");
    const seeded = (await categoriesResponse.json()) as Array<{
      id: string;
      systemKey: string | null;
    }>;
    foodCategoryId = seeded.find(
      (category) => category.systemKey === "expense.food-drink",
    )!.id;
    fuelCategoryId = seeded.find(
      (category) => category.systemKey === "expense.fuel",
    )!.id;
    salaryCategoryId = seeded.find(
      (category) => category.systemKey === "income.salary",
    )!.id;

    const accountResponse = await request("/api/v1/accounts", {
      method: "POST",
      body: {
        name: `Integration ${suffix}`,
        type: "checking",
        currency: "kzt",
        icon: "creditcard.fill",
        iconColor: "blue",
      },
    });
    const account = (await accountResponse.json()) as { id: string };
    accountId = account.id;
  });

  afterAll(async () => {
    if (accountId) {
      await db.delete(accounts).where(eq(accounts.id, accountId));
    }
    for (const categoryId of customCategoryIds) {
      await db.delete(categories).where(eq(categories.id, categoryId));
    }
  });

  it("seeds every system category and filters by kind", async () => {
    const allResponse = await request("/api/v1/categories");
    const all = (await allResponse.json()) as Array<{
      systemKey: string | null;
      kind: string;
    }>;
    const expenseResponse = await request(
      "/api/v1/categories?kind=expense",
    );
    const expense = (await expenseResponse.json()) as Array<{ kind: string }>;

    expect(allResponse.status).toBe(200);
    expect(all.filter((category) => category.systemKey !== null)).toHaveLength(
      22,
    );
    expect(expense).toHaveLength(16);
    expect(expense.every((category) => category.kind === "expense")).toBeTrue();
  });

  it("enforces case-insensitive category uniqueness within a kind", async () => {
    const name = `Work Snacks ${suffix}`;
    const firstResponse = await request("/api/v1/categories", {
      method: "POST",
      body: { name, kind: "expense" },
    });
    const first = (await firstResponse.json()) as { id: string };
    customCategoryIds.push(first.id);

    const duplicateResponse = await request("/api/v1/categories", {
      method: "POST",
      body: { name: name.toUpperCase(), kind: "expense" },
    });

    expect(firstResponse.status).toBe(201);
    expect(duplicateResponse.status).toBe(409);
  });

  it("validates category kind and derives currency from the account", async () => {
    const mismatchResponse = await createTransaction({
      description: `mismatched ${suffix}`,
      categoryId: salaryCategoryId,
      kind: "expense",
    });
    expect(mismatchResponse.status).toBe(400);

    const response = await createTransaction({
      description: `fuel purchase ${suffix}`,
      categoryId: fuelCategoryId,
      kind: "expense",
    });
    const transaction = (await response.json()) as {
      currency: string;
      description: string;
      category: { id: string; name: string; kind: string };
      occurredAt: string;
    };

    expect(response.status).toBe(201);
    expect(transaction.currency).toBe("KZT");
    expect(transaction.description).toBe(`fuel purchase ${suffix}`);
    expect(transaction.category).toMatchObject({
      id: fuelCategoryId,
      name: "Fuel",
      kind: "expense",
    });
    expect(new Date(transaction.occurredAt).toISOString()).toBe(
      "2026-08-31T12:30:00.000Z",
    );
  });

  it("uses the most recent exact normalized history match", async () => {
    const description = `Exact Merchant ${suffix}`;
    const normalizedDescription = normalizeTransactionDescription(description);
    await db.insert(transactions).values([
      {
        accountId,
        kind: "expense",
        amount: "10",
        currency: "KZT",
        categoryId: foodCategoryId,
        description,
        normalizedDescription,
        occurredAt: new Date("2026-08-01T12:00:00.000Z"),
        createdAt: new Date("2026-08-01T12:00:00.000Z"),
      },
      {
        accountId,
        kind: "expense",
        amount: "11",
        currency: "KZT",
        categoryId: fuelCategoryId,
        description,
        normalizedDescription,
        occurredAt: new Date("2026-08-02T12:00:00.000Z"),
        createdAt: new Date("2026-08-02T12:00:00.000Z"),
      },
    ]);

    const response = await suggest(`  EXACT merchant--${suffix} `, "expense");
    const body = (await response.json()) as SuggestionBody;

    expect(body.suggestions).toEqual([
      {
        categoryId: fuelCategoryId,
        score: 1,
        source: "exact_history",
      },
    ]);
  });

  it("learns from a misspelled historical description", async () => {
    const token = `nfs${suffix}`;
    await createTransaction({
      description: `north fuel station ${token}`,
      categoryId: fuelCategoryId,
      kind: "expense",
    });

    const response = await suggest(
      `north fuel staton ${token}`,
      "expense",
    );
    const body = (await response.json()) as SuggestionBody;

    expect(body.suggestions[0]?.categoryId).toBe(fuelCategoryId);
    expect(body.suggestions[0]?.source).toBe("fuzzy_history");
  });

  it("does not guess when equally similar history conflicts", async () => {
    const token = `conflict${suffix}`;
    const descriptions = [
      {
        description: `quasar alpha portal ${token}`,
        categoryId: foodCategoryId,
      },
      {
        description: `quasar alpha portal ${token}`,
        categoryId: fuelCategoryId,
      },
    ];

    for (const item of descriptions) {
      await createTransaction({
        ...item,
        kind: "expense",
      });
    }

    const response = await suggest(
      `quasar alfa portal ${token}`,
      "expense",
    );
    const body = (await response.json()) as SuggestionBody;

    expect(body.suggestions).toEqual([]);
  });

  it("returns no result for unrelated text", async () => {
    const response = await suggest(
      `zzqv unresolved marker ${crypto.randomUUID()}`,
      "expense",
    );
    const body = (await response.json()) as SuggestionBody;

    expect(body.suggestions).toEqual([]);
  });

  function createTransaction(input: {
    description: string;
    categoryId: string;
    kind: "expense" | "income";
  }): Promise<Response> {
    return request("/api/v1/transactions", {
      method: "POST",
      body: {
        accountId,
        kind: input.kind,
        amount: "12.5000",
        categoryId: input.categoryId,
        description: input.description,
        occurredAt: "2026-08-31T12:30:00.000Z",
      },
    });
  }
});

type SuggestionBody = {
  suggestions: Array<{
    categoryId: string;
    score: number;
    source: string;
  }>;
};

function suggest(
  description: string,
  kind: "expense" | "income",
): Promise<Response> {
  return request("/api/v1/categories/suggest", {
    method: "POST",
    body: { description, kind },
  });
}

function request(
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<Response> {
  return app.handle(
    new Request(`http://localhost${path}`, {
      method: options.method ?? "GET",
      headers:
        options.body === undefined
          ? undefined
          : { "Content-Type": "application/json" },
      body:
        options.body === undefined
          ? undefined
          : JSON.stringify(options.body),
    }),
  );
}
