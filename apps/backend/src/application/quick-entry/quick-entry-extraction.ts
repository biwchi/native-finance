export type CalendarUnit = "day" | "week" | "month" | "year";

export type ExtractedDate = {
  calendarDate: { year: number | null; month: number; day: number } | null;
  relative: { unit: CalendarUnit; value: number } | null;
  weekday: { day: number; relation: "last" | "this" | "next" } | null;
  time: string | null;
};

export type AmountCandidate = {
  value: string;
  currency: string | null;
  role: "transaction" | "paid_total" | "price" | "conditional_price" | "installment"
    | "plan_total" | "subtotal" | "tendered" | "change" | "old_price" | "reward" | "other";
};

export type ExtractedTransaction = {
  location: string;
  documentType: "text" | "receipt" | "transaction_record" | "transaction_history" | "product_offer" | "invoice" | "other";
  status: "completed" | "pending" | "canceled" | "reversed" | "offer" | "unknown";
  kind: "expense" | "income" | "transfer" | null;
  account: { id: string | null; basis: "selected" | "user" | "unresolved"; source: string | null };
  destinationAccountId: string | null;
  destinationAccountSource: string | null;
  amounts: AmountCandidate[];
  selectedAmountIndex: number | null;
  amountChoiceSource: string | null;
  category: {
    id: string | null;
    basis: "user" | "merchant" | "purpose" | "source_label" | "parent" | "unresolved";
    source: string | null;
  };
  counterparty: string | null;
  note: string | null;
  date: ExtractedDate | null;
  schedule: {
    source: string;
    frequency: "daily" | "weekly" | "monthly" | "yearly";
    occurrenceCount: number | null;
    duration: { value: number; unit: CalendarUnit } | null;
    endDate: ExtractedDate | null;
    totalAmountIndex: number | null;
  } | null;
  unresolved: Array<"amount" | "currency">;
};

export type QuickEntryExtraction = {
  transactions: ExtractedTransaction[];
};
