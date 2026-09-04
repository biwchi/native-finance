import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import type { ExchangeRateProvider } from "../exchange-rates/exchange-rate-provider.ts";
import type { ExchangeRateRepository } from "../exchange-rates/exchange-rate.repository.ts";
import { getLatestExchangeRates } from "../exchange-rates/get-latest-exchange-rates.ts";
import {
  convertExchangeAmount,
  normalizeCurrency,
} from "../../domain/exchange-rates/exchange-rate.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { RecurrenceFrequency } from "../../domain/transactions/transaction.ts";
import {
  quickEntryDraftLimit,
  type QuickEntryInterpreter,
} from "./quick-entry-interpreter.ts";

export type QuickEntryConversion = {
  originalAmount: string;
  originalCurrency: string;
  convertedAmount: string;
  convertedCurrency: string;
  rate: string;
  effectiveDate: string;
  stale: boolean;
};

export type QuickEntryDraft = {
  id: string;
  kind: "expense" | "income" | "transfer";
  accountId: string;
  destinationAccountId: string | null;
  amount: string;
  currency: string;
  categoryId: string | null;
  merchant: string | null;
  payee: string | null;
  note: string | null;
  occurredAt: string;
  recurrence: {
    frequency: RecurrenceFrequency;
    endAt: string | null;
  } | null;
  sourceText: string;
  conversion: QuickEntryConversion | null;
  warnings: string[];
};

export type QuickEntryResponse = {
  referenceNow: string;
  transactions: QuickEntryDraft[];
  unparsedText: string[];
};

export type QuickEntryError =
  | "account_not_found"
  | "empty_quick_entry"
  | "exchange_rates_unavailable"
  | "invalid_ai_response"
  | "quick_entry_unavailable"
  | "too_many_drafts";

export async function interpretQuickEntry(
  input: {
    text: string;
    defaultAccountId: string;
    locale: string;
    timeZone: string;
  },
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
    exchangeRateRepository: ExchangeRateRepository;
    exchangeRateProvider: ExchangeRateProvider;
    interpreter: QuickEntryInterpreter;
    now?: () => Date;
  },
): Promise<Result<QuickEntryResponse, QuickEntryError>> {
  const text = input.text.trim();
  if (!text) return error("empty_quick_entry", "Quick entry cannot be empty");

  const [accounts, categories] = await Promise.all([
    dependencies.accounts.list(),
    dependencies.categories.list(),
  ]);
  const defaultAccount = accounts.find(
    (account) => canonicalId(account.id) === canonicalId(input.defaultAccountId),
  );
  if (!defaultAccount) return error("account_not_found", "Default account not found");

  const referenceNow = (dependencies.now ?? (() => new Date()))();
  let interpreted;
  try {
    interpreted = await dependencies.interpreter.interpret({
      text,
      referenceNow: referenceNow.toISOString(),
      timeZone: input.timeZone,
      locale: input.locale,
      defaultAccountId: defaultAccount.id,
      accounts,
      categories,
    });
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : "Quick Entry is unavailable";
    return error("quick_entry_unavailable", message);
  }

  if (interpreted.transactions.length > quickEntryDraftLimit) {
    return error(
      "too_many_drafts",
      `Quick Entry supports up to ${quickEntryDraftLimit} transactions at a time`,
    );
  }
  if (interpreted.transactions.length === 0) {
    return error("invalid_ai_response", "No transactions could be understood");
  }

  const accountById = new Map(accounts.map((account) => [canonicalId(account.id), account]));
  const categoryById = new Map(categories.map((category) => [canonicalId(category.id), category]));
  const resolved: Array<{
    transaction: typeof interpreted.transactions[number];
    account: typeof defaultAccount;
    sourceCurrency: string;
  }> = [];
  for (const transaction of interpreted.transactions) {
    const account = accountById.get(canonicalId(transaction.accountId ?? defaultAccount.id));
    if (!account) {
      return error("invalid_ai_response", "AI returned an unknown account");
    }
    const sourceCurrency = normalizeCurrency(transaction.currency ?? account.currency);
    if (!/^[A-Z]{3}$/.test(sourceCurrency)) {
      return error("invalid_ai_response", "AI returned an invalid currency");
    }
    resolved.push({ transaction, account, sourceCurrency });
  }
  const currencies = [...new Set(resolved.flatMap(({ account, sourceCurrency }) => [
    normalizeCurrency(account.currency),
    sourceCurrency,
  ]))];

  const exchangeRates = await getLatestExchangeRates({
    reportingCurrency: defaultAccount.currency,
    currencies,
  }, {
    repository: dependencies.exchangeRateRepository,
    provider: dependencies.exchangeRateProvider,
    now: dependencies.now,
  });
  if (!exchangeRates.ok) return exchangeRates;

  const drafts: QuickEntryDraft[] = [];
  for (const { transaction, account, sourceCurrency } of resolved) {
    if (!isPositiveAmount(transaction.amount)) {
      return error("invalid_ai_response", "AI returned an invalid transaction amount");
    }
    const destination = transaction.kind === "transfer"
      ? accountById.get(canonicalId(transaction.destinationAccountId ?? "")) ?? null
      : null;
    if (transaction.kind === "transfer" && (!destination || destination.id === account.id)) {
      return error("invalid_ai_response", "AI returned an invalid transfer account");
    }
    if (destination && destination.currency !== account.currency) {
      return error(
        "invalid_ai_response",
        "Transfers between accounts with different currencies are not supported yet",
      );
    }

    const targetCurrency = normalizeCurrency(account.currency);
    const converted = convertExchangeAmount(
      transaction.amount,
      sourceCurrency,
      targetCurrency,
      exchangeRates.value,
    );
    if (!converted) {
      return error("exchange_rates_unavailable", "Exchange rates are temporarily unavailable");
    }

    const category = transaction.kind === "transfer" || !transaction.categoryId
      ? null
      : categoryById.get(canonicalId(transaction.categoryId)) ?? null;
    const categoryId = category?.kind === transaction.kind ? category.id : null;
    const occurredAt = validDate(transaction.occurredAt);
    if (transaction.occurredAt && !occurredAt) {
      return error("invalid_ai_response", "AI returned an invalid transaction date");
    }
    const resolvedOccurredAt = occurredAt ?? referenceNow;
    if (transaction.recurrence?.endAt && !validDate(transaction.recurrence.endAt)) {
      return error("invalid_ai_response", "AI returned an invalid recurrence end date");
    }
    const recurrence = transaction.kind === "transfer"
      ? null
      : validRecurrence(transaction.recurrence, resolvedOccurredAt);

    drafts.push({
      id: crypto.randomUUID(),
      kind: transaction.kind,
      accountId: account.id,
      destinationAccountId: destination?.id ?? null,
      amount: converted.amount,
      currency: targetCurrency,
      categoryId,
      merchant: cleanText(transaction.merchant),
      payee: cleanText(transaction.payee),
      note: cleanText(transaction.note),
      occurredAt: resolvedOccurredAt.toISOString(),
      recurrence,
      sourceText: transaction.sourceText.trim() || text,
      conversion: sourceCurrency === targetCurrency ? null : {
        originalAmount: normalizeAmount(transaction.amount),
        originalCurrency: sourceCurrency,
        convertedAmount: converted.amount,
        convertedCurrency: targetCurrency,
        rate: converted.rate,
        effectiveDate: converted.effectiveDate,
        stale: exchangeRates.value.stale,
      },
      warnings: categoryId || transaction.kind === "transfer"
        ? []
        : ["No matching category was found"],
    });
  }

  return ok({
    referenceNow: referenceNow.toISOString(),
    transactions: drafts,
    unparsedText: interpreted.unparsedText.map((value) => value.trim()).filter(Boolean),
  });
}

function validDate(value: string | null): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function validRecurrence(
  recurrence: { frequency: RecurrenceFrequency; endAt: string | null } | null,
  occurredAt: Date,
): QuickEntryDraft["recurrence"] {
  if (!recurrence) return null;
  const endAt = validDate(recurrence.endAt);
  return {
    frequency: recurrence.frequency,
    endAt: endAt && endAt >= occurredAt ? endAt.toISOString() : null,
  };
}

function cleanText(value: string | null): string | null {
  return value?.trim() || null;
}

function canonicalId(value: string): string {
  return value.toLowerCase();
}

function normalizeAmount(value: string): string {
  return value.trim().replace(/,/g, "");
}

function isPositiveAmount(value: string): boolean {
  const amount = normalizeAmount(value);
  return /^(?:0|[1-9]\d{0,14})(?:\.\d{1,4})?$/.test(amount) && Number(amount) > 0;
}
