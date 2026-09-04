import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import type { RecurrenceFrequency } from "../../domain/transactions/transaction.ts";

export const quickEntryDraftLimit = 100;

export type InterpretedQuickEntryTransaction = {
  kind: "expense" | "income" | "transfer";
  accountId: string | null;
  destinationAccountId: string | null;
  amount: string;
  currency: string | null;
  categoryId: string | null;
  merchant: string | null;
  payee: string | null;
  note: string | null;
  occurredAt: string | null;
  recurrence: {
    frequency: RecurrenceFrequency;
    endAt: string | null;
  } | null;
  sourceText: string;
};

export type QuickEntryInterpretation = {
  transactions: InterpretedQuickEntryTransaction[];
  unparsedText: string[];
};

export type QuickEntryInterpreterInput = {
  text: string;
  referenceNow: string;
  timeZone: string;
  locale: string;
  defaultAccountId: string;
  accounts: Account[];
  categories: Category[];
};

export interface QuickEntryInterpreter {
  interpret(input: QuickEntryInterpreterInput): Promise<QuickEntryInterpretation>;
}
