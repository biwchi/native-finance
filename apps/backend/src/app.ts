import { createAccount } from "./application/accounts/create-account.ts";
import { deleteAccount } from "./application/accounts/delete-account.ts";
import { listAccounts } from "./application/accounts/list-accounts.ts";
import { reorderAccounts } from "./application/accounts/reorder-accounts.ts";
import { updateAccount } from "./application/accounts/update-account.ts";
import { getMonthlyBudget } from "./application/budgets/get-monthly-budget.ts";
import { saveMonthlyBudget } from "./application/budgets/save-monthly-budget.ts";
import { createCategory } from "./application/categories/create-category.ts";
import { deleteCategory } from "./application/categories/delete-category.ts";
import { listCategories } from "./application/categories/list-categories.ts";
import { suggestCategory } from "./application/categories/suggest-category.ts";
import { updateCategory } from "./application/categories/update-category.ts";
import { getLatestExchangeRates } from "./application/exchange-rates/get-latest-exchange-rates.ts";
import { interpretQuickEntry } from "./application/quick-entry/interpret-quick-entry.ts";
import { createTransactionBatch } from "./application/transactions/create-transaction-batch.ts";
import { createTransaction } from "./application/transactions/create-transaction.ts";
import { createTransfer } from "./application/transactions/create-transfer.ts";
import { deleteRecurringTransaction } from "./application/transactions/delete-recurring-transaction.ts";
import { deleteTransaction } from "./application/transactions/delete-transaction.ts";
import { listTransactions } from "./application/transactions/list-transactions.ts";
import { listUpcomingTransactions } from "./application/transactions/list-upcoming-transactions.ts";
import { updateRecurringTransaction } from "./application/transactions/update-recurring-transaction.ts";
import { updateTransaction } from "./application/transactions/update-transaction.ts";
import { config } from "./config.ts";
import { db } from "./infrastructure/db/client.ts";
import { createDrizzleAccountRepository } from "./infrastructure/db/repositories/drizzle-account.repository.ts";
import { createDrizzleBudgetRepository } from "./infrastructure/db/repositories/drizzle-budget.repository.ts";
import { createDrizzleCategoryHistoryRepository } from "./infrastructure/db/repositories/drizzle-category-history.repository.ts";
import { createDrizzleCategoryRepository } from "./infrastructure/db/repositories/drizzle-category.repository.ts";
import { createDrizzleExchangeRateRepository } from "./infrastructure/db/repositories/drizzle-exchange-rate.repository.ts";
import { createDrizzleTransactionRepository } from "./infrastructure/db/repositories/drizzle-transaction.repository.ts";
import { createHttpApp } from "./infrastructure/http/create-http-app.ts";
import { createFrankfurterExchangeRateProvider } from "./infrastructure/providers/frankfurter-exchange-rate.provider.ts";
import { createOpenAIQuickEntryInterpreter } from "./infrastructure/providers/openai-quick-entry-interpreter.ts";

const accounts = createDrizzleAccountRepository(db);
const budgets = createDrizzleBudgetRepository(db);
const categories = createDrizzleCategoryRepository(db);
const categoryHistory = createDrizzleCategoryHistoryRepository(db);
const exchangeRates = createDrizzleExchangeRateRepository(db);
const transactions = createDrizzleTransactionRepository(db);
const exchangeRateProvider = createFrankfurterExchangeRateProvider(
  config.frankfurterBaseUrl,
);
const quickEntryInterpreter = createOpenAIQuickEntryInterpreter({
  apiKey: config.openAIApiKey,
  model: config.openAIModel,
  baseUrl: config.openAIBaseUrl,
});

export const app = createHttpApp({
  accounts: {
    list: () => listAccounts(undefined, { accounts }),
    create: (input) => createAccount(input, { accounts }),
    reorder: (accountIds) => reorderAccounts(accountIds, { accounts }),
    update: (input) => updateAccount(input, { accounts }),
    delete: (id) => deleteAccount(id, { accounts }),
  },
  budgets: {
    get: (input) => getMonthlyBudget(input, { budgets }),
    save: (input) => saveMonthlyBudget(input, { accounts, budgets, categories }),
  },
  categories: {
    list: (input) => listCategories(input, { categories }),
    create: (input) => createCategory(input, { categories }),
    update: ({ id, values }) => updateCategory({ id, ...values }, { categories }),
    delete: (id) => deleteCategory(id, { categories }),
    suggest: (input) => suggestCategory(input, { history: categoryHistory }),
  },
  exchangeRates: {
    latest: (input) => getLatestExchangeRates(input, {
      repository: exchangeRates,
      provider: exchangeRateProvider,
    }),
  },
  quickEntry: {
    interpret: (input) => interpretQuickEntry(input, {
      accounts,
      categories,
      exchangeRateRepository: exchangeRates,
      exchangeRateProvider,
      interpreter: quickEntryInterpreter,
    }),
  },
  transactions: {
    list: (input) => listTransactions(input, { transactions }),
    upcoming: (input) => listUpcomingTransactions(input, { transactions }),
    create: (input) => createTransaction(input, { accounts, categories, transactions }),
    transfer: (input) => createTransfer(input, { accounts, transactions }),
    batch: (input) => createTransactionBatch(input, { accounts, categories, transactions }),
    update: (input) => updateTransaction(input, { accounts, categories, transactions }),
    delete: (input) => deleteTransaction(input, { transactions }),
    updateRecurring: (input) => updateRecurringTransaction(input, {
      accounts,
      categories,
      transactions,
    }),
    deleteRecurring: (input) => deleteRecurringTransaction(input, { transactions }),
  },
}, config.corsOrigin);

export type App = typeof app;
