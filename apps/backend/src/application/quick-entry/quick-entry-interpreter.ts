import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import type { Debt } from "../../domain/debts/debt.ts";
import type { RecurrenceFrequency } from "../../domain/transactions/transaction.ts";
import type { QuickEntryDocument } from "./quick-entry-document.ts";

export const quickEntryDraftLimit = 100;
export const quickEntryDocumentDraftLimit = 750;

export function quickEntryDraftLimitFor(input: Pick<QuickEntryInterpreterInput, "document">): number {
  return input.document ? quickEntryDocumentDraftLimit : quickEntryDraftLimit;
}

export type InterpretedQuickEntryTransaction = {
  kind: "expense" | "income" | "transfer" | "debt";
  debtId?: string | null;
  destinationAmount?: string | null;
  destinationCurrency?: string | null;
  accountId: string | null;
  destinationAccountId: string | null;
  amount: string;
  currency: string | null;
  categoryId: string | null;
  counterparty: string | null;
  note: string | null;
  occurredAt: string | null;
  recurrence: {
    frequency: RecurrenceFrequency;
    endAt: string | null;
    timeZone?: string;
  } | null;
};

export type QuickEntryInterpretation = {
  transactions: InterpretedQuickEntryTransaction[];
};

export type QuickEntryInterpreterInput = {
  text: string;
  photo?: string;
  document?: QuickEntryDocument;
  referenceNow: string;
  timeZone: string;
  locale: string;
  defaultAccountId: string;
  accounts: Account[];
  categories: Category[];
  debts?: Debt[];
};

export interface QuickEntryInterpreter {
  interpret(input: QuickEntryInterpreterInput): Promise<QuickEntryInterpretation>;
}
