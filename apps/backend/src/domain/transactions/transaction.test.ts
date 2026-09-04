import { describe, expect, it } from "bun:test";

import type { Account } from "../accounts/account.ts";
import { createTransaction } from "./transaction.ts";

describe("createTransaction", () => {
  it("normalizes optional text and parses recurrence dates", () => {
    const result = createTransaction({
      accountId: "account",
      kind: "expense",
      amount: "12.50",
      merchant: "  Corner shop  ",
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
      merchant: "Corner shop",
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
    type: "checking",
    currency: "USD",
    icon: "creditcard.fill",
    iconColor: "blue",
    sortOrder: 0,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}
