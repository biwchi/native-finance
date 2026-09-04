import { describe, expect, it } from "bun:test";

import type { Account } from "../../domain/accounts/account.ts";
import type { AccountRepository } from "./account.repository.ts";
import { reorderAccounts } from "./reorder-accounts.ts";

describe("reorderAccounts", () => {
  it("rejects an order that omits an account", async () => {
    const repository = createAccountRepository([account("first"), account("second")]);

    const result = await reorderAccounts(["first"], { accounts: repository });

    expect(result).toEqual({
      ok: false,
      error: {
        code: "invalid_account_order",
        message: "Account order must include every account exactly once",
      },
    });
  });

  it("persists and returns a complete order", async () => {
    const repository = createAccountRepository([account("first"), account("second")]);

    const result = await reorderAccounts(["second", "first"], {
      accounts: repository,
    });

    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.map((value) => value.id)).toEqual(["second", "first"]);
  });
});

function createAccountRepository(initial: Account[]): AccountRepository {
  let accounts = [...initial];
  return {
    async list() {
      return accounts;
    },
    async findById(id) {
      return accounts.find((value) => value.id === id) ?? null;
    },
    async create() {
      throw new Error("Not used by this test");
    },
    async update() {
      throw new Error("Not used by this test");
    },
    async delete() {
      throw new Error("Not used by this test");
    },
    async replaceOrder(ids) {
      accounts = ids.map((id, sortOrder) => ({
        ...accounts.find((value) => value.id === id)!,
        sortOrder,
      }));
      return accounts;
    },
  };
}

function account(id: string): Account {
  return {
    id,
    name: id,
    type: "checking",
    currency: "USD",
    icon: "creditcard.fill",
    iconColor: "blue",
    sortOrder: 0,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}
