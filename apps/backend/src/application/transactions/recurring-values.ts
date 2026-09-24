import type { RecurringScheduleValues } from "../../domain/transactions/recurring-schedule.ts";
import type { TransactionValues } from "../../domain/transactions/transaction.ts";

export function scheduleTemplate(
  values: TransactionValues,
): Pick<
  RecurringScheduleValues,
  | "accountId"
  | "kind"
  | "amount"
  | "currency"
  | "categoryId"
  | "counterparty"
  | "note"
> {
  return {
    accountId: values.accountId,
    kind: values.kind,
    amount: values.amount,
    currency: values.currency,
    categoryId: values.categoryId,
    counterparty: values.counterparty,


    note: values.note,
  };
}
