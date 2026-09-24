import { describe, expect, it } from "bun:test";

import type { Account } from "../accounts/account.ts";
import { createTransaction } from "./transaction.ts";

describe("createTransaction", () => {
  it("normalizes the counterparty and leaves blank names null", () => {
    for (const counterparty of [" Urbo Coffee ", "", null]) {
      const result = createTransaction({ accountId: "account", kind: "expense", amount: "300", counterparty,
        occurredAt: "2026-09-21T10:00:00Z" }, { account: account(), category: null });
      expect(result).toMatchObject({ ok: true, value: { values: { counterparty: counterparty?.trim() || null } } });
    }
  });

  it("accepts an explicit currency without converting the numeric amount", () => {
    const result = createTransaction({ accountId: "account", kind: "expense", amount: "200", currency: "rub",
      occurredAt: "2026-09-04T10:00:00.000Z" }, { account: account(), category: null });
    expect(result).toMatchObject({ ok: true, value: { values: { amount: "200", currency: "RUB" } } });
    const invalid = createTransaction({ accountId: "account", kind: "expense", amount: "200", currency: "invalid",
      occurredAt: "2026-09-04T10:00:00.000Z" }, { account: account(), category: null });
    expect(invalid).toMatchObject({ ok: false, error: { code: "invalid_currency" } });
  });

  it("uses the transaction kind for direction and stores a positive magnitude", () => {
    for (const kind of ["expense", "income"] as const) {
      const result = createTransaction({ accountId: "account", kind, amount: "-12.50",
        occurredAt: "2026-09-04T10:00:00.000Z" }, { account: account(), category: null });
      expect(result).toMatchObject({ ok: true, value: { values: { kind, amount: "12.50" } } });
    }
  });

  it("normalizes optional text and parses recurrence dates", () => {
    const result = createTransaction({
      accountId: "account",
      kind: "expense",
      amount: "12.50",
      counterparty: "  Corner shop  ",
      note: "   ",
      occurredAt: "2026-09-04T10:00:00.000Z",
      recurrence: {
        frequency: "monthly",
        endAt: "2026-12-04T10:00:00.000Z",
      },
    }, { account: account(), category: null });

    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.values).toMatchObject({
      accountId: "account",
      currency: "USD",
      counterparty: "Corner shop",
      note: null,
    });
    expect(result.value.recurrence).toEqual({
      frequency: "monthly",
      endAt: new Date("2026-12-04T10:00:00.000Z"),
    });
  });

  it("rejects an invalid occurrence date", () => {
    const result = createTransaction({
      accountId: "account",
      kind: "expense",
      amount: "12.50",
      occurredAt: "not-a-date",
    }, { account: account(), category: null });

    expect(result).toEqual({
      ok: false,
      error: {
        code: "invalid_occurred_at",
        message: "occurredAt must be a valid date and time",
      },
    });
  });
});

function account(): Account {
  return {
    id: "account",
    name: "Checking",
    initialBalance: "0",
    currency: "USD",
    icon: "creditcard.fill",
    iconColor: "blue",
    sortOrder: 0,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}

describe("debt transaction validation", () => {
  const debt = { id: "alexey", name: "Alexey" };
  const input = {
    accountId: "account", kind: "debt" as const, amount: "125.50", debtId: debt.id,
    occurredAt: "2026-09-05T10:00:00.000Z",
  };
  const context = { account: account(), category: null, debt };

  it("associates the recipient and inherits the lending account currency", () => {
    const result = createTransaction(input, context);
    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.values).toMatchObject({ debtId: debt.id, kind: "debt", currency: "USD", categoryId: null });
    expect(result.value.recurrence).toBeNull();
  });

  it("requires an existing recipient", () => {
    expect(createTransaction({ ...input, debtId: undefined }, context)).toMatchObject({ ok: false, error: { code: "debt_required" } });
    expect(createTransaction(input, { ...context, debt: null })).toMatchObject({ ok: false, error: { code: "debt_not_found" } });
  });

  it("rejects categories, recurrence, and recipients on ordinary transactions", () => {
    for (const fields of [
      { categoryId: "food" }, { recurrence: { frequency: "monthly" as const } },
      { kind: "income" as const }, { kind: "expense" as const },
    ]) {
      expect(createTransaction({ ...input, ...fields }, context)).toMatchObject({ ok: false, error: { code: "invalid_debt_transaction" } });
    }
  });
});
