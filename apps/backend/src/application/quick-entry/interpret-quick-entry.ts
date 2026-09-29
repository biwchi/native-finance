import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import type { Debt, DebtRepository } from "../../domain/debts/debt.ts";
import { QuickEntryInterpretationError } from "./quick-entry-extraction.ts";
import { validateQuickEntryDocument, type QuickEntryDocument } from "./quick-entry-document.ts";
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
  quickEntryDraftLimitFor,
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
  kind: "expense" | "income" | "transfer" | "debt";
  debtId?: string | null;
  destinationAmount?: string | null;
  destinationCurrency?: string | null;
  destinationAmountEstimated?: boolean;
  accountId: string;
  destinationAccountId: string | null;
  amount: string;
  currency: string;
  categoryId: string | null;
  counterparty: string | null;
  note: string | null;
  occurredAt: string;
  recurrence: {
    frequency: RecurrenceFrequency;
    endAt: string | null;
    timeZone?: string;
  } | null;
  conversion: QuickEntryConversion | null;
};

export type QuickEntryResponse = {
  referenceNow: string;
  transactions: QuickEntryDraft[];
};

export type QuickEntryError =
  | "account_not_found"
  | "empty_quick_entry"
  | "empty_extraction"
  | "invalid_document"
  | "exchange_rates_unavailable"
  | "invalid_ai_response"
  | "quick_entry_unavailable"
  | "too_many_drafts"
  | "unsupported_quick_entry";

export async function interpretQuickEntry(
  input: {
    text: string;
    photo?: string;
    document?: QuickEntryDocument;
    defaultAccountId: string;
    locale: string;
    timeZone: string;
    context?: {
      debts?: Pick<Debt, "id" | "name">[];
      accounts: Pick<Account, "id" | "name" | "currency" | "icon" | "iconColor">[];
      categories: (Pick<Category, "id" | "name" | "kind"> & Partial<Pick<Category, "parentId" | "icon" | "color" | "examples">>)[];
    };
  },
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
    debts?: DebtRepository;
    exchangeRateRepository: ExchangeRateRepository;
    exchangeRateProvider: ExchangeRateProvider;
    interpreter: QuickEntryInterpreter;
    now?: () => Date;
  },
): Promise<Result<QuickEntryResponse, QuickEntryError>> {
  const text = input.text.trim();
  if (!text && !input.photo && !input.document) return error("empty_quick_entry", "Quick entry cannot be empty");
  if (input.document) {
    if (input.photo) return error("invalid_document", "Choose one photo or document at a time.");
    const message = validateQuickEntryDocument(input.document);
    if (message) return error("invalid_document", message);
  }

  const referenceNow = (dependencies.now ?? (() => new Date()))();
  const [accounts, categories]: [Account[], Category[]] = input.context ? [
    input.context.accounts.map((a, sortOrder) => ({ ...a, initialBalance: "0", id: canonicalId(a.id), currency: normalizeCurrency(a.currency), sortOrder, createdAt: referenceNow, updatedAt: referenceNow })),
    input.context.categories.map((c, sortOrder) => ({ icon: null, color: null, examples: [], ...c, parentId: c.parentId ? canonicalId(c.parentId) : null, id: canonicalId(c.id), systemKey: null, isSystem: false, sortOrder, createdAt: referenceNow, updatedAt: referenceNow })),
  ] : await Promise.all([dependencies.accounts.list(), dependencies.categories.list()]);
  const defaultAccount = accounts.find(
    (account) => canonicalId(account.id) === canonicalId(input.defaultAccountId),
  );
  if (!defaultAccount) return error("account_not_found", "Default account not found");
  const debts = input.context ? input.context.debts ?? [] : await dependencies.debts?.list() ?? [];

  let interpreted;
  try {
    interpreted = await dependencies.interpreter.interpret({
      text,
      photo: input.photo,
      document: input.document,
      referenceNow: referenceNow.toISOString(),
      timeZone: input.timeZone,
      locale: input.locale,
      defaultAccountId: defaultAccount.id,
      accounts,
      categories,
      debts,
    });
  } catch (cause) {
    if (cause instanceof QuickEntryInterpretationError) return error(cause.code, cause.message);
    const message = cause instanceof Error ? cause.message : "Quick Entry is unavailable";
    return error("quick_entry_unavailable", message);
  }

  const draftLimit = quickEntryDraftLimitFor(input);
  if (interpreted.transactions.length > draftLimit) {
    return error(
      "too_many_drafts",
      `${input.document ? "Document import" : "Quick Entry"} supports up to ${draftLimit} transactions at a time`,
    );
  }
  if (interpreted.transactions.length === 0) {
    return error("empty_extraction", input.document
      ? "No transactions could be read. Choose a document with readable transaction amounts."
      : input.photo
      ? "No purchases could be read. Try a clearer photo with a visible total."
      : "No transactions could be understood");
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
  const currencies = [...new Set(resolved.flatMap(({ transaction, account, sourceCurrency }) => [
    normalizeCurrency(account.currency),
    sourceCurrency,
    ...(transaction.kind === "transfer" ? [
      accountById.get(canonicalId(transaction.destinationAccountId ?? ""))?.currency,
      transaction.destinationCurrency,
    ].filter((currency): currency is string => !!currency) : []),
  ]))];

  const needsConversion = resolved.some(({ transaction, account, sourceCurrency }) => {
    if (transaction.amount === "") return false;
    const destination = accountById.get(canonicalId(transaction.destinationAccountId ?? ""));
    return sourceCurrency !== normalizeCurrency(account.currency) || transaction.kind === "transfer" && !!destination &&
      (transaction.destinationAmount ? normalizeCurrency(transaction.destinationCurrency ?? destination.currency) !== destination.currency : sourceCurrency !== destination.currency);
  });
  const exchangeRates = needsConversion ? await getLatestExchangeRates({
    reportingCurrency: defaultAccount.currency,
    currencies,
  }, {
    repository: dependencies.exchangeRateRepository,
    provider: dependencies.exchangeRateProvider,
    now: dependencies.now,
  }) : null;
  if (exchangeRates && !exchangeRates.ok) return exchangeRates;

  const drafts: QuickEntryDraft[] = [];
  for (const { transaction, account, sourceCurrency } of resolved) {
    const unresolvedAmount = transaction.amount === "";
    if (!unresolvedAmount && !isNonZeroAmount(transaction.amount)) {
      return error("invalid_ai_response", "AI returned an invalid transaction amount");
    }
    const requestedDestination = transaction.kind === "transfer"
      ? accountById.get(canonicalId(transaction.destinationAccountId ?? "")) ?? null
      : null;
    const destination = requestedDestination && requestedDestination.id !== account.id ? requestedDestination : null;

    const targetCurrency = normalizeCurrency(account.currency);
    const converted = unresolvedAmount || sourceCurrency === targetCurrency
      ? { amount: transaction.amount, rate: "1", effectiveDate: referenceNow.toISOString().slice(0, 10) }
      : exchangeRates?.ok ? convertExchangeAmount(
      transaction.amount,
      sourceCurrency,
      targetCurrency,
      exchangeRates.value,
    ) : null;
    if (!converted) {
      return error("exchange_rates_unavailable", "Exchange rates are temporarily unavailable");
    }
    let destinationAmount: string | null = null;
    let destinationAmountEstimated = false;
    if (destination && !unresolvedAmount) {
      const received = transaction.destinationAmount ?? transaction.amount;
      const receivedCurrency = normalizeCurrency(transaction.destinationAmount ? transaction.destinationCurrency ?? destination.currency : sourceCurrency);
      if (!isNonZeroAmount(received)) return error("invalid_ai_response", "AI returned an invalid received amount");
      const conversion = receivedCurrency === destination.currency ? { amount: received }
        : exchangeRates?.ok ? convertExchangeAmount(received, receivedCurrency, destination.currency, exchangeRates.value) : null;
      if (!conversion) return error("exchange_rates_unavailable", "Exchange rates are temporarily unavailable");
      destinationAmount = conversion.amount;
      destinationAmountEstimated = receivedCurrency !== destination.currency;
    }

    const category = transaction.kind === "transfer" || transaction.kind === "debt" || !transaction.categoryId
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
    const recurrence = transaction.kind === "transfer" || transaction.kind === "debt"
      ? null
      : validRecurrence(transaction.recurrence, resolvedOccurredAt);

    drafts.push({
      id: crypto.randomUUID(),
      kind: transaction.kind,
      accountId: account.id,
      destinationAccountId: destination?.id ?? null,
      destinationAmount, destinationCurrency: destination?.currency ?? null,
      destinationAmountEstimated,
      debtId: transaction.kind === "debt" ? debts.find((debt) => canonicalId(debt.id) === canonicalId(transaction.debtId ?? ""))?.id ?? null : null,
      amount: converted.amount,
      currency: targetCurrency,
      categoryId,
      counterparty: cleanText(transaction.counterparty),
      note: cleanText(transaction.note),
      occurredAt: resolvedOccurredAt.toISOString(),
      recurrence,
      conversion: unresolvedAmount || sourceCurrency === targetCurrency ? null : {
        originalAmount: normalizeAmount(transaction.amount),
        originalCurrency: sourceCurrency,
        convertedAmount: converted.amount,
        convertedCurrency: targetCurrency,
        rate: converted.rate,
        effectiveDate: converted.effectiveDate,
        stale: exchangeRates?.ok ? exchangeRates.value.stale : false,
      },
    });
  }

  return ok({
    referenceNow: referenceNow.toISOString(),
    transactions: drafts,
  });
}

function validDate(value: string | null): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function validRecurrence(
  recurrence: { frequency: RecurrenceFrequency; endAt: string | null; timeZone?: string } | null,
  occurredAt: Date,
): QuickEntryDraft["recurrence"] {
  if (!recurrence) return null;
  const endAt = validDate(recurrence.endAt);
  return {
    frequency: recurrence.frequency,
    endAt: endAt && endAt >= occurredAt ? endAt.toISOString() : null,
    ...(recurrence.timeZone ? { timeZone: recurrence.timeZone } : {}),
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

function isNonZeroAmount(value: string): boolean {
  const amount = normalizeAmount(value);
  return /^-?(?:0|[1-9]\d{0,14})(?:\.\d{1,4})?$/.test(amount) && Number(amount) !== 0;
}
