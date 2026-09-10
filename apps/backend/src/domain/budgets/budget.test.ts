import { describe, expect, it } from "bun:test";

import type { Account } from "../accounts/account.ts";
import type { Category } from "../categories/category.ts";
import { createBudget } from "./budget.ts";

describe("createBudget", () => {
  const foodId = "abcdef01-2345-4678-9abc-def012345678";
  const groupId = "bcdef012-3456-4789-abcd-ef0123456789";

  it("accepts iOS uppercase category UUIDs returned lowercase by the database", () => {
    const result = createBudget({
      currency: "USD",
      monthlyLimit: "1200",
      groups: [],
      categoryAssignments: [{ categoryId: foodId.toUpperCase(), limit: "300" }],
    }, { account: null, categories: [category(foodId, "expense")] });

    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.categoryAssignments).toEqual([
      { categoryId: foodId, groupId: null, limit: "300" },
    ]);
  });

  it("matches pool UUIDs regardless of casing", () => {
    const result = createBudget({
      currency: "USD",
      groups: [{ id: groupId.toUpperCase(), name: "Needs", limit: "500" }],
      categoryAssignments: [{ categoryId: foodId.toUpperCase(), groupId }],
    }, { account: null, categories: [category(foodId, "expense")] });

    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.groups[0]?.id).toBe(groupId);
    expect(result.value.categoryAssignments).toEqual([
      { categoryId: foodId, groupId, limit: null },
    ]);
  });

  it("rejects duplicate category UUIDs with different casing", () => {
    const result = createBudget({
      currency: "USD",
      groups: [],
      categoryAssignments: [
        { categoryId: foodId, limit: "100" },
        { categoryId: foodId.toUpperCase(), limit: "200" },
      ],
    }, { account: null, categories: [category(foodId, "expense")] });

    expect(result).toMatchObject({ ok: false, error: { code: "duplicate_category_assignment" } });
  });

  it("rejects duplicate pool UUIDs with different casing", () => {
    const result = createBudget({
      currency: "USD",
      groups: [
        { id: groupId, name: "Needs", limit: "500" },
        { id: groupId.toUpperCase(), name: "Wants", limit: "200" },
      ],
      categoryAssignments: [],
    }, { account: null, categories: [] });

    expect(result).toMatchObject({ ok: false, error: { code: "duplicate_group_id" } });
  });

  it("still rejects categories that do not exist", () => {
    const result = createBudget({
      currency: "USD",
      groups: [],
      categoryAssignments: [{ categoryId: foodId.toUpperCase(), limit: "100" }],
    }, { account: null, categories: [] });

    expect(result).toMatchObject({ ok: false, error: { code: "category_not_found" } });
  });

  it("still rejects income categories with uppercase UUIDs", () => {
    const result = createBudget({
      currency: "USD",
      groups: [],
      categoryAssignments: [{ categoryId: foodId.toUpperCase(), limit: "100" }],
    }, { account: null, categories: [category(foodId, "income")] });

    expect(result).toMatchObject({ ok: false, error: { code: "income_category" } });
  });

  it("builds normalized groups and category assignments", () => {
    const result = createBudget({
      accountId: "account",
      currency: "usd",
      monthlyLimit: "1000",
      groups: [{ id: "group", name: "  Needs  ", limit: "500" }],
      categoryAssignments: [{ categoryId: "food", groupId: "group" }],
    }, {
      account: account("account", "USD"),
      categories: [category("food", "expense")],
    });

    expect(result).toEqual({
      ok: true,
      value: {
        accountId: "account",
        currency: "USD",
        monthlyLimit: "1000",
        groups: [{ id: "group", name: "Needs", limit: "500", sortOrder: 0 }],
        categoryAssignments: [{ categoryId: "food", groupId: "group", limit: null }],
      },
    });
  });

  it("rejects an assignment to a group outside the budget", () => {
    const result = createBudget({
      currency: "USD",
      groups: [],
      categoryAssignments: [{ categoryId: "food", groupId: "missing" }],
    }, {
      account: null,
      categories: [category("food", "expense")],
    });

    expect(result).toEqual({
      ok: false,
      error: {
        code: "unknown_group",
        message: "Category assignment references an unknown group",
      },
    });
  });
});

function account(id: string, currency: string): Account {
  return {
    id,
    name: id,
    type: "checking",
    currency,
    icon: "creditcard.fill",
    iconColor: "blue",
    sortOrder: 0,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}

function category(id: string, kind: Category["kind"]): Category {
  return {
    id,
    systemKey: null,
    name: id,
    kind,
    parentId: null,
    icon: null,
    color: null,
    isSystem: false,
    examples: [],
    sortOrder: 0,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}
