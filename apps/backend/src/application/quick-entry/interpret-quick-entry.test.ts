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
  it("passes documents with empty typed text and returns editable drafts without finance writes", async () => {
    const document = { filename: "statement.pdf", mediaType: "application/pdf", data: Buffer.from("%PDF-1.7").toString("base64") };
    let calls = 0;
    const result = await interpretQuickEntry({ text: "", document, defaultAccountId: account.id, locale: "en_US", timeZone: "UTC" }, {
      accounts: accountRepository([account]), categories: categoryRepository([expenseCategory]),
      exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => [], now: () => now,
      interpreter: { async interpret(input) {
        calls++;
        expect(input.document).toEqual(document);
        expect(input.photo).toBeUndefined();
        expect(input.text).toBe("");
        return { transactions: [{ kind: "expense", accountId: null, destinationAccountId: null, amount: "12",
          currency: "KZT", categoryId: expenseCategory.id, counterparty: "Cafe", note: null, occurredAt: null, recurrence: null }] };
      } },
    });
    expect(calls).toBe(1);
    expect(result.ok).toBeTrue();
    if (result.ok) expect(result.value.transactions[0]).toMatchObject({ amount: "12", accountId: account.id, counterparty: "Cafe" });
  });

  it("rejects invalid documents and mixed attachments before calling the provider", async () => {
    const document = { filename: "statement.pdf", mediaType: "application/pdf", data: Buffer.from("%PDF-1.7").toString("base64") };
    for (const attachment of [{ document, photo: "photo" }, { document: { ...document, data: "YWJj" } }]) {
      let called = false;
      const result = await interpretQuickEntry({ text: "", ...attachment, defaultAccountId: account.id, locale: "en_US", timeZone: "UTC" }, {
        accounts: accountRepository([account]), categories: categoryRepository([]),
        exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => [],
        interpreter: { async interpret() { called = true; return { transactions: [] }; } },
      });
      expect(result.ok).toBeFalse();
      expect(called).toBeFalse();
    }
  });

  it("allows documents up to 750 drafts while keeping other quick entry modes at 100", async () => {
    const transaction = { kind: "expense" as const, accountId: null, destinationAccountId: null,
      amount: "1", currency: "KZT", categoryId: null, counterparty: null, note: null,
      occurredAt: null, recurrence: null };
    const dependencies = {
      accounts: accountRepository([account]), categories: categoryRepository([]),
      exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => [], now: () => now,
    };
    const document = { filename: "statement.pdf", mediaType: "application/pdf",
      data: Buffer.from("%PDF-1.7").toString("base64") };

    const documentResult = await interpretQuickEntry({ text: "", document, defaultAccountId: account.id,
      locale: "en_US", timeZone: "UTC" }, { ...dependencies,
      interpreter: { async interpret() { return { transactions: Array(751).fill(transaction) }; } } });
    expect(documentResult).toMatchObject({ ok: false,
      error: { code: "too_many_drafts", message: "Document import supports up to 750 transactions at a time" } });

    const textResult = await interpretQuickEntry({ text: "many entries", defaultAccountId: account.id,
      locale: "en_US", timeZone: "UTC" }, { ...dependencies,
      interpreter: { async interpret() { return { transactions: Array(101).fill(transaction) }; } } });
    expect(textResult).toMatchObject({ ok: false,
      error: { code: "too_many_drafts", message: "Quick Entry supports up to 100 transactions at a time" } });
  });

  it("converts a scanned KZT price into the local RUB account currency even when the server account is still KZT", async () => {
    const localAccount = { ...account, currency: "RUB" };
    const result = await interpretQuickEntry({ text: "Recognize purchases", photo: "data:image/jpeg;base64,/9j/2Q==",
      defaultAccountId: account.id, locale: "ru_RU", timeZone: "Asia/Almaty",
      context: { accounts: [localAccount], categories: [expenseCategory] } }, {
      accounts: accountRepository([account]), categories: categoryRepository([expenseCategory]),
      exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => [
        { quoteCurrency: "KZT", rate: "500", effectiveDate: "2026-09-04" },
        { quoteCurrency: "RUB", rate: "80", effectiveDate: "2026-09-04" },
      ], now: () => now,
      interpreter: { async interpret(input) {
        expect(input.accounts[0]?.currency).toBe("RUB");
        return { transactions: [{ kind: "expense", accountId: null, destinationAccountId: null, amount: "27756",
          currency: "KZT", categoryId: expenseCategory.id, counterparty: null, note: "Zelda",
          occurredAt: null, recurrence: null }] };
      } },
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.transactions[0]).toMatchObject({ amount: "4440.96", currency: "RUB", recurrence: null,
      conversion: { originalAmount: "27756", originalCurrency: "KZT", convertedAmount: "4440.96", convertedCurrency: "RUB", rate: "0.16" } });
  });

  it("passes photos to the interpreter and returns reviewable drafts without writing transactions", async () => {
    const photo = "data:image/jpeg;base64,/9j/2Q==";
    const result = await interpretQuickEntry({ text: "Recognize purchases", photo, defaultAccountId: account.id,
      locale: "en_KZ", timeZone: "Asia/Almaty" }, {
      accounts: accountRepository([account]), categories: categoryRepository([expenseCategory]),
      exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => [
        { quoteCurrency: "KZT", rate: "540.12", effectiveDate: "2026-09-04" },
      ], now: () => now,
      interpreter: { async interpret(input) {
        expect(input.photo).toBe(photo);
        return { transactions: [{ kind: "expense", accountId: null, destinationAccountId: null, amount: "1250",
          currency: "KZT", categoryId: expenseCategory.id, counterparty: "Cafe", note: "Coffee",
          occurredAt: null, recurrence: null, }] };
      } },
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.transactions[0]).toMatchObject({ accountId: account.id,
      amount: "1250", counterparty: "Cafe", categoryId: expenseCategory.id });
  });

  it("returns an explicit empty extraction error for scans with no readable transactions", async () => {
    const result = await interpretQuickEntry({
      text: "",
      photo: "data:image/jpeg;base64,/9j/2Q==",
      defaultAccountId: account.id,
      locale: "en_US",
      timeZone: "UTC",
    }, {
      accounts: accountRepository([account]), categories: categoryRepository([]),
      exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => [],
      interpreter: { async interpret() { return { transactions: [] }; } },
    });

    expect(result).toMatchObject({
      ok: false,
      error: {
        code: "empty_extraction",
        message: "No purchases could be read. Try a clearer photo with a visible total.",
      },
    });
  });

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
              counterparty: "Coffee",

              note: null,
              occurredAt: null,
              recurrence: null,
            }],
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

  it("uses complete local context for unsynced accounts and categories", async () => {
    const localAccount = makeAccount("Offline cash", "USD"); const localCategory = makeCategory("Offline food", "expense");
    const result = await interpretQuickEntry({ text: "Coffee 4", defaultAccountId: localAccount.id, locale: "en_US", timeZone: "UTC", context: { accounts: [localAccount], categories: [localCategory] } }, {
      accounts: accountRepository([]), categories: categoryRepository([]), exchangeRateRepository: memoryExchangeRepository(), exchangeRateProvider: async () => { throw new Error("No conversion needed"); }, now: () => now,
      interpreter: { async interpret(input) {
        expect(input.accounts.map(a => a.id)).toEqual([localAccount.id]); expect(input.categories.map(c => c.id)).toEqual([localCategory.id]);
        return { transactions: [{ kind: "expense", accountId: localAccount.id, destinationAccountId: null, amount: "4", currency: "USD", categoryId: localCategory.id, counterparty: "Coffee", note: null, occurredAt: null, recurrence: null }] };
      } },
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.transactions[0]).toMatchObject({ accountId: localAccount.id, categoryId: localCategory.id, amount: "4" });
  });

});

function makeAccount(name: string, currency: string): Account {
  return {
    id: crypto.randomUUID(),
    name,
    currency,
    initialBalance: "0",
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
