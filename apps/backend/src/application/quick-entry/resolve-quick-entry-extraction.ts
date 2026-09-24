import type { Category } from "../../domain/categories/category.ts";
import { createQuickEntryCalendar } from "./quick-entry-calendar.ts";
import type { AmountCandidate, CalendarUnit, ExtractedTransaction, QuickEntryExtraction } from "./quick-entry-extraction.ts";
import type { InterpretedQuickEntryTransaction, QuickEntryInterpretation, QuickEntryInterpreterInput } from "./quick-entry-interpreter.ts";
import { dividePayment, formatMoneyUnits, moneyUnits } from "./quick-entry-money.ts";

const frequencyUnit = { daily: "day", weekly: "week", monthly: "month", yearly: "year" } as const;

export function resolveQuickEntryExtraction(extraction: QuickEntryExtraction, input: QuickEntryInterpreterInput): QuickEntryInterpretation {
  const calendar = createQuickEntryCalendar(input.referenceNow, input.timeZone);
  const accounts = new Map(input.accounts.map((account) => [account.id.toLowerCase(), account]));
  const selectedAccount = accounts.get(input.defaultAccountId.toLowerCase());
  if (!selectedAccount) throw new Error("Selected account not found");
  const transactions: InterpretedQuickEntryTransaction[] = [];
  const seen = new Set<string>();

  for (const item of extraction.transactions) {
    if (item.status === "canceled") continue;
    // Identical amounts alone do not establish a duplicate.
    const sourceKey = JSON.stringify([item.documentType, item.location, item.kind, item.amounts, item.counterparty]);
    if (item.location.trim() && seen.has(sourceKey)) continue;
    seen.add(sourceKey);

    const kind = item.kind ?? "expense";

    let account = selectedAccount;
    if (item.account.basis === "user") {
      const requested = accounts.get(item.account.id?.toLowerCase() ?? "");
      if (requested && userEvidence(item.account.source, input.text)) account = requested;
    }
    let destination = kind === "transfer" ? accounts.get(item.destinationAccountId?.toLowerCase() ?? "") : undefined;
    if (kind === "transfer" && !userEvidence(item.destinationAccountSource, input.text)
      && !(destination?.id === selectedAccount.id && account.id !== selectedAccount.id && item.account.basis === "user")) {
      destination = undefined;
    }
    if (destination && (destination.id === account.id || destination.currency !== account.currency)) destination = undefined;

    const categoryId = resolveCategory(item, input.categories, input.text);
    let occurredAt = calendar.reference;
    try { occurredAt = calendar.resolve(item.date); }
    catch { occurredAt = calendar.reference; }

    const schedule = item.schedule && kind !== "transfer" && userEvidence(item.schedule.source, input.text) ? item.schedule : null;
    const candidate = selectAmount(item, input, schedule !== null);
    let amount = candidate?.value ?? "";
    let currency = candidate?.currency ?? null;
    let recurrence: InterpretedQuickEntryTransaction["recurrence"] = null;
    // A null currency defaults to the account later. An explicit uncertainty flag
    // means conflicting source evidence and must still block saving.
    if (item.unresolved.length > 0) amount = "";
    // An ambiguous statement direction must require an edit before it can be saved.
    if ((input.photo || input.document) && item.kind === null) amount = "";
    if (amount) {
      try { amount = formatMoneyUnits(moneyUnits(amount)); }
      catch { amount = ""; }
    }

    if (schedule) {
      try {
        const unit: CalendarUnit = frequencyUnit[schedule.frequency];
        const counts = [schedule.occurrenceCount];
        if (schedule.duration) {
          const boundary = calendar.add(occurredAt, schedule.duration.unit, schedule.duration.value);
          counts.push(calendar.countOccurrences(occurredAt, boundary, unit, false));
        }
        const explicitEnd = schedule.endDate ? calendar.resolve(schedule.endDate, occurredAt) : null;
        if (explicitEnd) counts.push(calendar.countOccurrences(occurredAt, explicitEnd, unit, true));
        const resolvedCounts = counts.filter((count): count is number => count !== null);
        if (new Set(resolvedCounts).size > 1) throw new Error("The payment count and schedule duration disagree.");
        const count = resolvedCounts[0] ?? null;
        const endAt = count ? calendar.add(occurredAt, unit, count - 1) : null;
        recurrence = { frequency: schedule.frequency, endAt: endAt?.toISOString() ?? null };
        const total = schedule.totalAmountIndex === null ? null : item.amounts[schedule.totalAmountIndex];
        if (schedule.totalAmountIndex !== null && !total) throw new Error("The plan total could not be identified.");
        if (candidate && amount && (candidate.role === "plan_total" || candidate.role === "price" || candidate === total)) {
          if (!count) throw new Error("Enter the number of payments or the amount of one payment.");
          amount = dividePayment(amount, count, currency ?? account.currency);
        } else if (candidate && total && count && amount) {
          if ((total.currency ?? account.currency) !== (currency ?? account.currency)) throw new Error("The payment and plan total use different currencies.");
          if (moneyUnits(amount) * BigInt(count) !== moneyUnits(total.value)) amount = "";
        }
      } catch {
        recurrence = null;
        if (candidate?.role !== "installment") amount = "";
      }
    }
    if (currency && !/^[A-Z]{3}$/.test(currency)) {
      currency = null; amount = "";
    }
    transactions.push({
      kind, accountId: account.id, destinationAccountId: destination?.id ?? null,
      amount, currency, categoryId,
      counterparty: item.counterparty, note: item.note,
      occurredAt: occurredAt.toISOString(), recurrence,
    });
  }
  return { transactions };
}

function selectAmount(item: ExtractedTransaction, input: QuickEntryInterpreterInput, recurring: boolean): AmountCandidate | null {
  if (item.selectedAmountIndex !== null && (!Number.isInteger(item.selectedAmountIndex)
    || item.selectedAmountIndex < 0 || item.selectedAmountIndex >= item.amounts.length)) {
    throw new Error("The transaction amount selection was invalid. Please try again.");
  }
  const selected = item.selectedAmountIndex === null ? null : item.amounts[item.selectedAmountIndex] ?? null;
  if (item.unresolved.includes("amount")) return null;
  // Recover an omitted selection only for one ordinary typed amount. Never infer
  // a choice between prices, payment plans, or explicitly uncertain evidence.
  if (!selected && !input.photo && !input.document && !item.schedule && item.unresolved.length === 0
    && item.amounts.length === 1) {
    const sole = item.amounts[0]!;
    if (sole.role === "transaction" || sole.role === "paid_total" || sole.role === "price") return sole;
  }
  if ((!input.photo && !input.document) || recurring || userEvidence(item.amountChoiceSource, input.text)) return selected;
  const role = item.documentType === "product_offer" ? "price"
    : item.documentType === "receipt" ? "paid_total"
    : item.documentType === "transaction_record" || item.documentType === "transaction_history" ? "transaction" : null;
  if (!role) return selected;
  const candidates = item.amounts.filter((candidate) => candidate.role === role);
  const unique = new Map(candidates.map((candidate) => [`${candidate.value}:${candidate.currency}`, candidate]));
  return unique.size === 1 ? [...unique.values()][0]! : null;
}

function resolveCategory(item: ExtractedTransaction, categories: Category[], request: string): string | null {
  if (item.kind === "transfer") return null;
  const available = categories.filter((category) => category.kind === item.kind);
  const proposed = available.find((category) => category.id.toLowerCase() === item.category.id?.toLowerCase());
  if (item.category.basis === "user") {
    return proposed && userEvidence(item.category.source, request) ? proposed.id : null;
  }
  // Only seller evidence may trigger business-based category matching.
  const merchant = item.category.basis === "merchant" ? normalize(item.counterparty ?? "") : "";
  const exactMatches = merchant ? available.filter((category) => [category.name, ...category.examples].some((name) => normalize(name) === merchant)) : [];
  // A matching child can beat its matching parent; unrelated matches remain ambiguous.
  const leaves = exactMatches.filter((category) => !exactMatches.some((other) => other.parentId === category.id));
  if (leaves.length === 1) return leaves[0]!.id;
  if (leaves.length > 1) return null;
  return proposed?.id ?? null;
}

function normalize(value: string) { return value.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim(); }
function userEvidence(source: string | null, request: string): boolean {
  const excerpt = normalize(source ?? "");
  return excerpt.length > 0 && (` ${normalize(request)} `).includes(` ${excerpt} `);
}
