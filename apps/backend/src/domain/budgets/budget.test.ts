import { describe, expect, it } from "bun:test";

import type { Account } from "../accounts/account.ts";
import type { Category } from "../categories/category.ts";
import { createBudget } from "./budget.ts";

describe("createBudget", () => {
  it("builds normalized groups and category assignments", () => {
    const result = createBudget({
      month: "2026-09",
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
        month: "2026-09-01",
        currency: "USD",
        monthlyLimit: "1000",
        groups: [{ id: "group", name: "Needs", limit: "500", sortOrder: 0 }],
        categoryAssignments: [{ categoryId: "food", groupId: "group", limit: null }],
      },
    });
  });

  it("rejects an assignment to a group outside the budget", () => {
    const result = createBudget({
      month: "2026-09",
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
