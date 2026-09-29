// Local fixtures only: the model response and exchange rates are injected.
import { describe, expect, it } from "bun:test";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import type { ExtractedTransaction } from "./quick-entry-extraction.ts";
import { QuickEntryInterpretationError } from "./quick-entry-extraction.ts";
import type { QuickEntryInterpreterInput } from "./quick-entry-interpreter.ts";
import { resolveQuickEntryExtraction } from "./resolve-quick-entry-extraction.ts";
import { interpretQuickEntry } from "./interpret-quick-entry.ts";
import { createQuickEntryCalendar } from "./quick-entry-calendar.ts";
import { nextRecurrenceDate } from "../../domain/transactions/recurrence.ts";
import { createTransfer } from "../../domain/transactions/transaction.ts";
import { createOpenAIQuickEntryInterpreter } from "../../infrastructure/providers/openai-quick-entry-interpreter.ts";

const now = new Date("2026-01-02T12:00:00Z");
const source = { id: "10000000-0000-4000-8000-000000000001", name: "Daily", initialBalance: "0", currency: "USD", icon: "card", iconColor: "blue" as const, sortOrder: 0, createdAt: now, updatedAt: now };
const destination = { ...source, id: "10000000-0000-4000-8000-000000000002", name: "Savings", currency: "KZT" };
const debt = { id: "10000000-0000-4000-8000-000000000003", name: "Alex" };
const input: QuickEntryInterpreterInput = { text: "monthly to Savings", referenceNow: now.toISOString(), timeZone: "Asia/Almaty", locale: "en", defaultAccountId: source.id, accounts: [source, destination], categories: [], debts: [debt] };
const event = (extra: Partial<ExtractedTransaction> = {}): ExtractedTransaction => ({
  location: "entry 1", documentType: "text", status: "completed", kind: "expense", debtId: null,
  account: { id: null, basis: "selected", source: null }, destinationAccountId: null, destinationAccountSource: null, destinationAmountIndex: null,
  amounts: [{ value: "120", currency: "USD", role: "price" }], selectedAmountIndex: 0, amountChoiceSource: null,
  category: { id: null, basis: "unresolved", source: null }, counterparty: null, note: null, date: null, schedule: null, unresolved: [], ...extra,
});
const schedule = { source: "monthly", frequency: "monthly" as const, occurrenceCount: 12, duration: null, endDate: null, totalAmountIndex: null };
const resolve = (item: ExtractedTransaction, context = input) => resolveQuickEntryExtraction({ transactions: [item] }, context).transactions[0]!;
const provider = (transactions: ExtractedTransaction[], extra: Record<string, unknown> = {}) => createOpenAIQuickEntryInterpreter({
  apiKey: "local-fixture", fetcher: (async (_url, _init) => Response.json({ output_text: JSON.stringify({ transactions, hasMoreTransactions: false, unsupportedRequests: [], ...extra }) })) as typeof fetch,
});
async function draft(item: ExtractedTransaction, allowRates = true) {
  return interpretQuickEntry({ text: input.text, defaultAccountId: source.id, locale: input.locale, timeZone: input.timeZone,
    context: { accounts: input.accounts, categories: [], debts: [debt] } }, {
    accounts: {} as AccountRepository, categories: {} as CategoryRepository,
    exchangeRateRepository: { async findLatest() { return []; }, async save() {} },
    exchangeRateProvider: async () => { if (!allowRates) throw new Error("Unexpected rate request"); return [{ quoteCurrency: "KZT", rate: "500", effectiveDate: "2026-01-02" }]; },
    interpreter: provider([item]), now: () => now,
  });
}

describe("quick entry supported capabilities", () => {
  it("preserves recurring prices and divides only whole-plan totals in text and scans", () => {
    for (const photo of [undefined, "fixture"]) {
      for (const occurrenceCount of [12, null]) {
        const result = resolve(event({ schedule: { ...schedule, occurrenceCount } }), { ...input, photo });
        expect(result.amount).toBe("120");
        expect(result.recurrence?.frequency).toBe("monthly");
      }
      expect(resolve(event({ amounts: [{ value: "1200", currency: "USD", role: "plan_total" }],
        schedule: { ...schedule, totalAmountIndex: 0 } }), { ...input, photo }).amount).toBe("100");
      expect(resolve(event({ schedule: { ...schedule, totalAmountIndex: 0 } }), { ...input, photo }).amount).toBe("");
    }
  });

  it("carries lending recipients through strict extraction and draft creation", async () => {
    for (const debtId of [debt.id, null]) {
      const result = await draft(event({ kind: "debt", debtId, counterparty: "Alex" }), false);
      expect(result).toMatchObject({ ok: true, value: { transactions: [{ kind: "debt", debtId, counterparty: "Alex", categoryId: null, recurrence: null }] } });
    }
  });

  it("preserves both stated sides of a cross-currency transfer without exchange rates", async () => {
    const result = await draft(event({ kind: "transfer", destinationAccountId: destination.id, destinationAccountSource: "to Savings",
      amounts: [{ value: "100", currency: "USD", role: "transaction" }, { value: "49500", currency: "KZT", role: "transfer_destination" }], destinationAmountIndex: 1 }), false);
    expect(result).toMatchObject({ ok: true, value: { transactions: [{ amount: "100", currency: "USD", destinationAmount: "49500", destinationCurrency: "KZT", destinationAccountId: destination.id }] } });
  });

  it("calculates the missing side of a cross-currency transfer", async () => {
    const transfer = event({ kind: "transfer", destinationAccountId: destination.id, destinationAccountSource: "to Savings",
      amounts: [{ value: "100", currency: null, role: "transaction" }] });
    expect(await draft(transfer)).toMatchObject({ ok: true, value: { transactions: [{ amount: "100", destinationAmount: "50000", destinationAmountEstimated: true }] } });
    expect(await draft({ ...transfer, amounts: [{ value: "50000", currency: null, role: "transfer_destination" }], destinationAmountIndex: 0 }))
      .toMatchObject({ ok: true, value: { transactions: [{ amount: "100", destinationAmount: "50000" }] } });
    expect(await draft(transfer, false)).toMatchObject({ ok: false, error: { code: "exchange_rates_unavailable" } });
  });

  it("persists separate transfer amounts and rejects missing or invalid received amounts", () => {
    const request = { fromAccountId: source.id, toAccountId: destination.id, amount: "100", occurredAt: now.toISOString() };
    const context = { sourceAccount: source, destinationAccount: destination };
    expect(createTransfer({ ...request, destinationAmount: "49500" }, context)).toMatchObject({ ok: true, value: {
      source: { amount: "100", currency: "USD", kind: "expense" }, destination: { amount: "49500", currency: "KZT", kind: "income" },
    } });
    expect(createTransfer(request, context).ok).toBeFalse();
    for (const destinationAmount of ["0", "-10", "oops"]) expect(createTransfer({ ...request, destinationAmount }, context).ok).toBeFalse();
  });

  it("rejects recurring transfers and loans even if the extraction omitted its unsupported flag", () => {
    for (const kind of ["transfer", "debt"] as const) expect(() => resolve(event({ kind, schedule }))).toThrow(QuickEntryInterpretationError);
  });

  it("rejects unsupported requests and overflow for every input mode instead of returning a partial batch", async () => {
    for (const attachment of [{}, { photo: "fixture" }, { document: { filename: "statement.pdf", mediaType: "application/pdf", data: "JVBERi0=" } }]) {
      await expect(provider([event()], { hasMoreTransactions: true }).interpret({ ...input, ...attachment })).rejects.toMatchObject({ code: "too_many_drafts" });
      for (const reason of ["custom_schedule", "recurring_transfer", "borrowing", "debt_repayment", "modify_existing", "variable_payment_plan"]) {
        await expect(provider([event()], { unsupportedRequests: [{ source: "monthly", reason }] }).interpret({ ...input, ...attachment })).rejects.toMatchObject({ code: "unsupported_quick_entry" });
      }
    }
  });
});

describe("quick entry calendar contract", () => {
  const expression = (month: number, day: number, yearRelation: "past" | "future" | "nearest", year: number | null = null) => ({
    calendarDate: { year, month, day, yearRelation }, relative: null, weekday: null, time: null,
  });
  it("resolves omitted years across New Year using past, future and nearest intent", () => {
    const january = createQuickEntryCalendar("2026-01-02T12:00:00Z", "Asia/Almaty");
    expect(january.resolve(expression(12, 31, "past")).toISOString()).toBe("2025-12-31T12:00:00.000Z");
    expect(january.resolve(expression(12, 31, "nearest")).toISOString()).toBe("2025-12-31T12:00:00.000Z");
    expect(january.resolve(expression(12, 31, "future")).toISOString()).toBe("2026-12-31T12:00:00.000Z");
    expect(january.resolve(expression(12, 31, "past", 2027)).getUTCFullYear()).toBe(2027);
    expect(january.resolve(expression(2, 29, "past")).getUTCFullYear()).toBe(2024);
    expect(january.resolve(expression(2, 29, "future")).getUTCFullYear()).toBe(2028);
  });

  it("uses the same local calendar for draft end dates and saved monthly occurrences", () => {
    const context = { ...input, referenceNow: "2026-02-28T19:30:00Z" };
    const result = resolve(event({ schedule: { ...schedule, occurrenceCount: 3 } }), context);
    const first = new Date(result.occurredAt!);
    const second = nextRecurrenceDate(first, first, "monthly", result.recurrence?.timeZone);
    const third = nextRecurrenceDate(second, first, "monthly", result.recurrence?.timeZone);
    expect(second.toISOString()).toBe("2026-03-31T19:30:00.000Z");
    expect(third.toISOString()).toBe("2026-04-30T19:30:00.000Z");
    expect(result.recurrence?.endAt).toBe(third.toISOString());
  });

  it("preserves local time through DST and restores the anchor after a missing wall time", () => {
    const start = new Date("2026-03-07T07:30:00Z");
    const second = nextRecurrenceDate(start, start, "daily", "America/New_York");
    const third = nextRecurrenceDate(second, start, "daily", "America/New_York");
    expect(second.toISOString()).toBe("2026-03-08T07:30:00.000Z");
    expect(third.toISOString()).toBe("2026-03-09T06:30:00.000Z");
    const fall = new Date("2026-10-31T05:30:00Z");
    expect(nextRecurrenceDate(fall, fall, "daily", "America/New_York").toISOString()).toBe("2026-11-01T05:30:00.000Z");
    const overlap = createQuickEntryCalendar("2026-11-01T06:30:00Z", "America/New_York", true);
    expect(overlap.add(overlap.reference, "day", 0).toISOString()).toBe("2026-11-01T06:30:00.000Z");
  });
});
