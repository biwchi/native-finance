import type { Budget, BudgetDraft } from "../../domain/budgets/budget.ts";

export interface BudgetRepository {
  find(accountId: string | null): Promise<Budget | null>;
  save(snapshot: BudgetDraft): Promise<Budget>;
  delete(accountId: string | null): Promise<void>;
}
