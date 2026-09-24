// Deterministic fixtures only. These tests do not call an AI service or use credentials.
import { describe, expect, it } from "bun:test";
import type { ExtractedDate, ExtractedTransaction } from "./quick-entry-extraction.ts";
import type { QuickEntryInterpreterInput } from "./quick-entry-interpreter.ts";
import { createQuickEntryCalendar } from "./quick-entry-calendar.ts";
import { dividePayment } from "./quick-entry-money.ts";
import { resolveQuickEntryExtraction } from "./resolve-quick-entry-extraction.ts";

const now = new Date("2026-09-11T19:15:23Z");
const account = { id: "account", name: "Daily", initialBalance: "0", currency: "USD", icon: "card", iconColor: "red" as const, sortOrder: 0, createdAt: now, updatedAt: now };
const category = { id: "shopping", name: "Shopping", kind: "expense" as const, parentId: null as string | null, icon: null, color: null, isSystem: false, systemKey: null, examples: [] as string[], sortOrder: 0, createdAt: now, updatedAt: now };
const input: QuickEntryInterpreterInput = { text: "", photo: "fixture", referenceNow: now.toISOString(), timeZone: "Asia/Almaty", locale: "en", defaultAccountId: account.id, accounts: [account], categories: [category, { ...category, id: "merchant", name: "Example Market", parentId: category.id }, { ...category, id: "food", name: "Groceries" }] };
function event(overrides: Partial<ExtractedTransaction> = {}): ExtractedTransaction {
  return {
    location: "row 1", documentType: "product_offer", status: "offer", kind: "expense",
    account: { id: null, basis: "selected", source: null }, destinationAccountId: null, destinationAccountSource: null,
    amounts: [{ value: "120", currency: "USD", role: "price" }, { value: "10", currency: "USD", role: "installment" }], selectedAmountIndex: 1, amountChoiceSource: null,
    category: { id: "food", basis: "merchant", source: "EXAMPLE MARKET" }, counterparty: "EXAMPLE MARKET", note: null,
    date: null, schedule: null, unresolved: [], ...overrides,
  };
}
function resolve(item: ExtractedTransaction, context = input) {
  return resolveQuickEntryExtraction({ transactions: [item] }, context).transactions[0]!;
}

describe("transaction evidence resolution without AI", () => {
  it("only uses a counterparty as a merchant category match when supported as a seller", () => {
    const personal = event({ counterparty: "EXAMPLE MARKET", category: { id: "food", basis: "purpose", source: null } });
    expect(resolve(personal).categoryId).toBe("food");
    expect(resolve({ ...personal, category: { ...personal.category, basis: "merchant" } }).categoryId).toBe("merchant");
    expect(resolve({ ...personal, counterparty: null }).categoryId).toBe("food");
  });

  it("preserves a bare typed price with omitted currency and recovers a missing selection", () => {
    const context = { ...input, photo: undefined, text: "Эклер на работе 300",
      accounts: [{ ...account, currency: "KZT" }] };
    for (const selectedAmountIndex of [0, null]) {
      expect(resolve(event({ documentType: "text", status: "completed",
        amounts: [{ value: "300", currency: null, role: "transaction" }], selectedAmountIndex }), context))
        .toMatchObject({ accountId: account.id, amount: "300", currency: null, recurrence: null });
    }
  });

  it("does not recover competing, uncertain, alternative or scheduled amounts", () => {
    const context = { ...input, photo: undefined, text: "record the purchase" };
    const ordinary = event({ documentType: "text", selectedAmountIndex: null,
      amounts: [{ value: "300", currency: null, role: "transaction" }] });
    for (const field of ["amount", "currency"] as const) {
      expect(resolve({ ...ordinary, unresolved: [field] }, context).amount).toBe("");
    }
    expect(resolve({ ...ordinary, amounts: [...ordinary.amounts, { value: "400", currency: null, role: "transaction" }] }, context).amount).toBe("");
    for (const role of ["conditional_price", "installment", "plan_total", "subtotal", "tendered", "change", "old_price", "reward", "other"] as const) {
      expect(resolve({ ...ordinary, amounts: [{ value: "300", currency: null, role }] }, context).amount).toBe("");
    }
    expect(resolve({ ...ordinary, schedule: { source: "monthly", frequency: "monthly", occurrenceCount: null,
      duration: null, endDate: null, totalAmountIndex: null } }, context).amount).toBe("");
  });

  it("rejects an index outside the actual candidates instead of silently losing the amount", () => {
    const item = event({ amounts: [{ value: "300", currency: null, role: "transaction" }] });
    for (const selectedAmountIndex of [-1, 0.5, 1, 19]) {
      expect(() => resolve({ ...item, selectedAmountIndex }, { ...input, photo: undefined }))
        .toThrow("amount selection was invalid");
    }
  });

  it("preserves omitted and explicit currency but blocks conflicting evidence in text and scans", () => {
    for (const attachment of [{}, { photo: "fixture" },
      { document: { filename: "statement.pdf", mediaType: "application/pdf", data: "fixture" } }]) {
      const context = { ...input, photo: undefined, ...attachment };
      for (const currency of [null, "KZT"]) {
        const item = event({ documentType: "transaction_record", status: "completed",
          amounts: [{ value: "300", currency, role: "transaction" }], selectedAmountIndex: 0 });
        expect(resolve(item, context)).toMatchObject({ amount: "300", currency });
        expect(resolve({ ...item, unresolved: ["currency"] }, context).amount).toBe("");
      }
    }
  });

  it("applies scan amount rules to documents while preserving explicit choices and uncertainty", () => {
    const context = { ...input, photo: undefined, document: { filename: "statement.pdf", mediaType: "application/pdf", data: "fixture" } };
    expect(resolve(event(), context).amount).toBe("120");
    const receipt = event({ documentType: "receipt", status: "completed", amounts: [
      { value: "100", currency: "USD", role: "subtotal" }, { value: "108", currency: "USD", role: "paid_total" },
    ], selectedAmountIndex: 0 });
    expect(resolve(receipt, context).amount).toBe("108");
    expect(resolve({ ...receipt, kind: null }, context).amount).toBe("");
    expect(resolve({ ...receipt, amounts: [...receipt.amounts, { value: "110", currency: "USD", role: "paid_total" }] }, context).amount).toBe("");
    expect(resolve({ ...receipt, amountChoiceSource: "record 100" }, { ...context, text: "record 100; do not repeat" }).amount).toBe("100");
    expect(resolve({ ...receipt, account: { id: "other", basis: "user", source: "file says other" },
      schedule: { source: "repeat monthly", frequency: "monthly", occurrenceCount: 12, duration: null, endDate: null, totalAmountIndex: 0 } },
    { ...context, text: "do not repeat", accounts: [...input.accounts, { ...account, id: "other" }] }))
      .toMatchObject({ accountId: account.id, recurrence: null });
  });

  it("keeps distinct statement rows across sheets and pages and omits canceled events", () => {
    const context = { ...input, photo: undefined, document: { filename: "statement.xlsx", mediaType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", data: "fixture" } };
    const item = event({ documentType: "transaction_history", status: "completed", location: "sheet 1 row 1",
      amounts: [{ value: "12", currency: "USD", role: "transaction" }], selectedAmountIndex: 0 });
    const result = resolveQuickEntryExtraction({ transactions: [item, item,
      { ...item, location: "sheet 2 row 1" }, { ...item, location: "sheet 2 row 2", status: "canceled" },
      { ...item, location: "sheet 2 row 3", kind: "income" }] }, context);
    expect(result.transactions.map(({ amount, kind }) => ({ amount, kind }))).toEqual([
      { amount: "12", kind: "expense" }, { amount: "12", kind: "expense" }, { amount: "12", kind: "income" },
    ]);
  });
  it("applies the ordinary price and a matching child category to extracted evidence", () => {
    const draft = resolve(event());
    expect(draft.amount).toBe("120");
    expect(draft.categoryId).toBe("merchant");
    expect(draft.recurrence).toBeNull();

  });

  it("honors explicit user category and price choices over defaults", () => {
    const draft = resolve(event({ category: { id: "food", basis: "user", source: "under Groceries" }, amountChoiceSource: "paid the discounted price", amounts: [{ value: "90", currency: "USD", role: "conditional_price" }], selectedAmountIndex: 0 }), { ...input, text: "I paid the discounted price; put this under Groceries" });
    expect(draft.amount).toBe("90");
    expect(draft.categoryId).toBe("food");
  });

  it("leaves competing amounts blank without guessing and leaves unrelated merchant matches unresolved", () => {
    const item = event();
    item.amounts.push({ value: "130", currency: "USD", role: "price" });
    const draft = resolve(item, { ...input, categories: [...input.categories, { ...category, id: "other", name: "Example Market" }] });
    expect(draft.amount).toBe("");
    expect(draft.categoryId).toBeNull();

  });

  it("divides an extracted total and resolves a duration to an inclusive last payment", () => {
    const draft = resolve(event({ documentType: "text", amounts: [{ value: "2400", currency: "USD", role: "plan_total" }], selectedAmountIndex: 0,
      schedule: { source: "over two years", frequency: "monthly", duration: { value: 2, unit: "year" }, occurrenceCount: null, endDate: null, totalAmountIndex: 0 } }), { ...input, photo: undefined, text: "Bought a computer for 2400 over two years" });
    expect(draft.amount).toBe("100");
    expect(draft.recurrence).toEqual({ frequency: "monthly", endAt: "2028-08-11T19:15:23.000Z" });
  });

  it("rejects unsupported schedule evidence and keeps the selected account", () => {
    const draft = resolve(event({ account: { id: "different", basis: "selected", source: "bank logo" }, schedule: { source: "monthly installments", frequency: "monthly", duration: null, occurrenceCount: 12, endDate: null, totalAmountIndex: 0 } }));
    expect(draft.recurrence).toBeNull();
    expect(draft.amount).toBe("120");
    expect(draft.accountId).toBe(account.id);

  });

  it("omits canceled records while retaining separate identical purchases and posted refunds", () => {
    const item = event({ documentType: "transaction_history", status: "completed", amounts: [{ value: "120", currency: "USD", role: "transaction" }], selectedAmountIndex: 0 });
    const result = resolveQuickEntryExtraction({ transactions: [item, item, { ...item, location: "row 2" }, { ...item, location: "row 3", status: "canceled" }, { ...item, location: "row 4", kind: "income", counterparty: null }] }, input);
    expect(result.transactions).toHaveLength(3);
    expect(result.transactions[2]?.kind).toBe("income");

  });

  it("keeps ordinary account defaults quiet in both input modes", () => {
    for (const photo of [undefined, input.photo]) {
      const draft = resolve(event({ documentType: "transaction_record", status: "completed",
        amounts: [{ value: "120", currency: "USD", role: "transaction" }], selectedAmountIndex: 0,
        account: { id: null, basis: "selected", source: null } }), { ...input, photo });
      expect(draft.accountId).toBe(account.id);


    }
  });

  it("keeps unreadable amounts blank without generating review messages", () => {
    const result = resolveQuickEntryExtraction({ transactions: [event({ status: "pending", note: "Birthday lunch",
      unresolved: ["amount"] })] }, input);
    expect(result.transactions[0]?.amount).toBe("");
    expect(result.transactions[0]?.note).toBe("Birthday lunch");
    const serialized = JSON.parse(JSON.stringify(result));
    expect(serialized.unparsedText).toBeUndefined();
    expect(serialized.transactions[0].warnings).toBeUndefined();
    expect(serialized.transactions[0].requiresReview).toBeUndefined();
  });

  it("does not silently accept an image-selected destination account", () => {
    const other = { ...account, id: "other" };
    const draft = resolve(event({ kind: "transfer", destinationAccountId: other.id }), { ...input, accounts: [account, other] });

    expect(draft.destinationAccountId).toBeNull();
  });
});

describe("calendar and money arithmetic", () => {
  const calendar = createQuickEntryCalendar(now.toISOString(), "Asia/Almaty");
  const date = (overrides: Partial<ExtractedDate>): ExtractedDate => ({ calendarDate: null, relative: null, weekday: null, time: null, ...overrides });
  it("resolves relative dates using the user's calendar day and retains the local time", () => {
    expect(calendar.resolve(date({ relative: { unit: "day", value: -1 } })).toISOString()).toBe("2026-09-10T19:15:23.000Z");
    expect(calendar.resolve(date({ calendarDate: { year: null, month: 9, day: 4 } })).toISOString()).toBe("2026-09-03T19:15:23.000Z");
  });
  it("keeps the original month-day anchor across shorter months", () => {
    const start = new Date("2026-01-31T12:00:00Z");
    expect(calendar.add(start, "month", 1).toISOString()).toBe("2026-02-28T12:00:00.000Z");
    expect(calendar.add(start, "month", 2).toISOString()).toBe("2026-03-31T12:00:00.000Z");
  });
  it("rejects invalid dates and daylight-saving gaps or overlaps", () => {
    expect(() => calendar.resolve(date({ calendarDate: { year: 2026, month: 2, day: 30 } }))).toThrow();
    const eastern = createQuickEntryCalendar(now.toISOString(), "America/New_York");
    expect(() => eastern.resolve(date({ calendarDate: { year: 2026, month: 3, day: 8 }, time: "02:30:00" }))).toThrow();
    expect(() => eastern.resolve(date({ calendarDate: { year: 2026, month: 11, day: 1 }, time: "01:30:00" }))).toThrow();
  });
  it("uses exact decimal arithmetic and rounds to currency precision", () => {
    expect(dividePayment("1500000", 24, "KZT")).toEqual("62500");
    expect(dividePayment("100", 3, "USD")).toEqual("33.33");
    expect(dividePayment("100", 3, "JPY")).toEqual("33");
    expect(dividePayment("-100", 3, "USD")).toEqual("33.33");
  });

  it("normalizes signed extracted amounts while preserving the selected kind", () => {
    const expense = resolve(event({ amounts: [{ value: "-120", currency: "USD", role: "price" }], selectedAmountIndex: 0 }));
    const income = resolve(event({ kind: "income", amounts: [{ value: "-120", currency: "USD", role: "price" }], selectedAmountIndex: 0 }));
    expect(expense).toMatchObject({ kind: "expense", amount: "120" });
    expect(income).toMatchObject({ kind: "income", amount: "120" });
  });
});
