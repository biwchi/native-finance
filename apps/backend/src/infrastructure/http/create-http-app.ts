import type { AppDataRepository } from "../../application/settings/app-data.repository.ts";
import { createSettingsRouter } from "./routes/settings.router.ts";
import type { DebtRepository } from "../../domain/debts/debt.ts";
import { createDebtsRouter } from "./routes/debts.router.ts";
import { cors } from "@elysiajs/cors";
import { Elysia } from "elysia";

import {
  createAccountsRouter,
  type AccountController,
} from "./routes/accounts.router.ts";
import {
  createBudgetsRouter,
  type BudgetController,
} from "./routes/budgets.router.ts";
import {
  createCategoriesRouter,
  type CategoryController,
} from "./routes/categories.router.ts";
import {
  createExchangeRatesRouter,
  type ExchangeRateController,
} from "./routes/exchange-rates.router.ts";
import {
  createQuickEntryRouter,
  type QuickEntryController,
} from "./routes/quick-entry.router.ts";
import {
  createTransactionsRouter,
  type TransactionController,
} from "./routes/transactions.router.ts";

export type HttpControllers = {
  appData?: AppDataRepository;
  debts?: DebtRepository;
  accounts: AccountController;
  budgets: BudgetController;
  categories: CategoryController;
  exchangeRates: ExchangeRateController;
  quickEntry: QuickEntryController;
  transactions: TransactionController;
};

export function createHttpApp(
  controllers: HttpControllers,
  corsOrigin: string,
) {
  return new Elysia({ name: "finance-tracker-api" })
    .use(cors({ origin: corsOrigin }))
    .get("/health", () => ({
      service: "finance-tracker-api",
      status: "ok" as const,
    }))
    .group("/api/v1", (api) => api
      .use(controllers.appData ? createSettingsRouter(controllers.appData) : new Elysia())
      .use(controllers.debts ? createDebtsRouter(controllers.debts) : new Elysia())
      .use(createAccountsRouter(controllers.accounts))
      .use(createBudgetsRouter(controllers.budgets))
      .use(createCategoriesRouter(controllers.categories))
      .use(createExchangeRatesRouter(controllers.exchangeRates))
      .use(createQuickEntryRouter(controllers.quickEntry))
      .use(createTransactionsRouter(controllers.transactions))
    );
}
