import type { Account } from "../accounts/account.ts";
import type {
  Category,
  CategorySummary,
  TransactionKind,
} from "../categories/category.ts";
import { error, ok, type Result } from "../shared/result.ts";

export type TransactionRecord = {
  id: string;
  accountId: string;
  kind: TransactionKind;
  amount: string;
  currency: string;
  categoryId: string | null;
  recurringScheduleId: string | null;
  merchant: string | null;
  payee: string | null;
  note: string | null;
  occurredAt: Date;
  createdAt: Date;
  updatedAt: Date;
};

export type TransactionValues = Omit<
  TransactionRecord,
  "id" | "recurringScheduleId" | "createdAt" | "updatedAt"
> & {
  recurringScheduleId?: string | null;
};

export type TransactionResponse = Omit<
  TransactionRecord,
  "categoryId" | "recurringScheduleId"
> & {
  category: CategorySummary | null;
  recurrence: {
    id: string;
    frequency: RecurrenceFrequency;
    endAt: Date | null;
  } | null;
};

export type RecurrenceFrequency = "daily" | "weekly" | "monthly" | "yearly";

export type TransactionInput = {
  accountId: string;
  kind: TransactionKind;
  amount: string;
  categoryId?: string | null;
  merchant?: string | null;
  payee?: string | null;
  note?: string | null;
  recurrence?: {
    frequency: RecurrenceFrequency;
    endAt?: string | null;
  } | null;
  occurredAt: string;
};

export type TransactionDraft = {
  values: TransactionValues;
  recurrence: {
    frequency: RecurrenceFrequency;
    endAt: Date | null;
  } | null;
};

export type TransactionValidationError =
  | "account_not_found"
  | "category_not_found"
  | "category_kind_mismatch"
  | "invalid_occurred_at"
  | "invalid_recurrence_end";

export function createTransaction(
  input: TransactionInput,
  context: { account: Account | null; category: Category | null },
): Result<TransactionDraft, TransactionValidationError> {
  if (!context.account) return error("account_not_found", "Account not found");
  if (input.categoryId && !context.category) {
    return error("category_not_found", "Category not found");
  }
  if (context.category && context.category.kind !== input.kind) {
    return error(
      "category_kind_mismatch",
      "Category kind must match transaction kind",
    );
  }

  const occurredAt = new Date(input.occurredAt);
  if (Number.isNaN(occurredAt.getTime())) {
    return error(
      "invalid_occurred_at",
      "occurredAt must be a valid date and time",
    );
  }

  const recurrence = createRecurrence(input.recurrence, occurredAt);
  if (!recurrence.ok) return recurrence;

  return ok({
    values: {
      accountId: context.account.id,
      kind: input.kind,
      amount: input.amount,
      currency: context.account.currency,
      categoryId: context.category?.id ?? null,
      merchant: cleanOptionalText(input.merchant),
      payee: cleanOptionalText(input.payee),
      note: cleanOptionalText(input.note),
      occurredAt,
    },
    recurrence: recurrence.value,
  });
}

export type TransferInput = {
  fromAccountId: string;
  toAccountId: string;
  amount: string;
  merchant?: string | null;
  payee?: string | null;
  note?: string | null;
  occurredAt: string;
};

export type TransferValidationError =
  | "same_account"
  | "account_not_found"
  | "currency_mismatch"
  | "invalid_occurred_at";

export function createTransfer(
  input: TransferInput,
  context: {
    sourceAccount: Account | null;
    destinationAccount: Account | null;
  },
): Result<
  { source: TransactionValues; destination: TransactionValues },
  TransferValidationError
> {
  if (input.fromAccountId === input.toAccountId) {
    return error("same_account", "Transfer accounts must be different");
  }
  if (!context.sourceAccount || !context.destinationAccount) {
    return error("account_not_found", "Transfer account not found");
  }
  if (context.sourceAccount.currency !== context.destinationAccount.currency) {
    return error(
      "currency_mismatch",
      "Transfer accounts must use the same currency",
    );
  }

  const occurredAt = new Date(input.occurredAt);
  if (Number.isNaN(occurredAt.getTime())) {
    return error(
      "invalid_occurred_at",
      "occurredAt must be a valid date and time",
    );
  }
  const shared = {
    amount: input.amount,
    currency: context.sourceAccount.currency,
    categoryId: null,
    merchant: cleanOptionalText(input.merchant),
    payee: cleanOptionalText(input.payee),
    note: cleanOptionalText(input.note),
    occurredAt,
  };
  return ok({
    source: {
      ...shared,
      accountId: context.sourceAccount.id,
      kind: "expense",
    },
    destination: {
      ...shared,
      accountId: context.destinationAccount.id,
      kind: "income",
    },
  });
}

function createRecurrence(
  recurrence: TransactionInput["recurrence"],
  occurredAt: Date,
): Result<TransactionDraft["recurrence"], "invalid_recurrence_end"> {
  if (!recurrence) return ok(null);
  const endAt = recurrence.endAt ? new Date(recurrence.endAt) : null;
  if (endAt && (Number.isNaN(endAt.getTime()) || endAt < occurredAt)) {
    return error(
      "invalid_recurrence_end",
      "Recurrence end date must be on or after the transaction date",
    );
  }
  return ok({ frequency: recurrence.frequency, endAt });
}

function cleanOptionalText(value: string | null | undefined): string | null {
  return value?.trim() || null;
}

export type UpcomingTransaction = {
  id: string;
  accountId: string;
  kind: TransactionKind;
  amount: string;
  currency: string;
  category: CategorySummary | null;
  merchant: string | null;
  payee: string | null;
  note: string | null;
  frequency: RecurrenceFrequency;
  startAt: Date;
  endAt: Date | null;
  occurredAt: Date;
};
