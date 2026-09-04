import { describe, expect, it } from "bun:test";

import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import type { ExchangeRateRepository } from "../exchange-rates/exchange-rate.repository.ts";
import { interpretQuickEntry } from "./interpret-quick-entry.ts";

const now = new Date("2026-09-04T11:30:00.000Z");
const account = makeAccount("KZT account", "KZT");
const expenseCategory = makeCategory("Food", "expense");
const incomeCategory = makeCategory("Salary", "income");

describe("interpretQuickEntry", () => {
  it("supplies all accounts and category kinds, defaults time, and converts currency", async () => {
    const seen: { accounts?: Account[]; categories?: Category[] } = {};
    const result = await interpretQuickEntry({
      text: "Coffee $4",
      defaultAccountId: account.id.toUpperCase(),
      locale: "en_KZ",
      timeZone: "Asia/Almaty",
    }, {
      accounts: accountRepository([account]),
      categories: categoryRepository([expenseCategory, incomeCategory]),
      exchangeRateRepository: memoryExchangeRepository(),
      exchangeRateProvider: async () => [{
        quoteCurrency: "KZT",
        rate: "540.12",
        effectiveDate: "2026-09-04",
      }],
      interpreter: {
        async interpret(input) {
          seen.accounts = input.accounts;
          seen.categories = input.categories;
          expect(input.defaultAccountId).toBe(account.id);
          return {
            transactions: [{
              kind: "expense",
              accountId: null,
              destinationAccountId: null,
              amount: "4",
              currency: "USD",
              categoryId: expenseCategory.id,
              merchant: "Coffee",
              payee: null,
              note: null,
              occurredAt: null,
              recurrence: null,
              sourceText: "Coffee $4",
            }],
            unparsedText: [],
          };
        },
      },
      now: () => now,
    });

    expect(seen.accounts).toHaveLength(1);
    expect(seen.categories?.map((category) => category.kind)).toEqual(["expense", "income"]);
    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.transactions[0]).toMatchObject({
      accountId: account.id,
      amount: "2160.48",
      currency: "KZT",
      categoryId: expenseCategory.id,
      occurredAt: now.toISOString(),
      conversion: {
        originalAmount: "4",
        originalCurrency: "USD",
        convertedAmount: "2160.48",
        convertedCurrency: "KZT",
        rate: "540.12",
        effectiveDate: "2026-09-04",
        stale: false,
      },
    });
  });

});

function makeAccount(name: string, currency: string): Account {
  return {
    id: crypto.randomUUID(),
    name,
    currency,
    type: "checking",
    icon: "card",
    iconColor: "blue",
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  };
}

function makeCategory(name: string, kind: Category["kind"]): Category {
  return {
    id: crypto.randomUUID(),
    systemKey: null,
    name,
    kind,
    parentId: null,
    icon: null,
    color: null,
    isSystem: false,
    examples: [],
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  };
}

function accountRepository(accounts: Account[]): AccountRepository {
  return {
    async list() { return accounts; },
    async findById(id) { return accounts.find((item) => item.id === id) ?? null; },
  } as AccountRepository;
}

function categoryRepository(categories: Category[]): CategoryRepository {
  return {
    async list() { return categories; },
    async findById(id) { return categories.find((item) => item.id === id) ?? null; },
  } as CategoryRepository;
}

function memoryExchangeRepository(): ExchangeRateRepository {
  return {
    async findLatest() { return []; },
    async save() {},
  };
}
