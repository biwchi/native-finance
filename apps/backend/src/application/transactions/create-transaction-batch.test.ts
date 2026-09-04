import { describe, expect, it } from "bun:test";

import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import type {
  TransactionRecord,
  TransactionValues,
} from "../../domain/transactions/transaction.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import {
  createTransactionBatch,
  type TransactionBatchItem,
} from "./create-transaction-batch.ts";
import type {
  TransactionRepository,
  TransactionStore,
} from "./transaction.repository.ts";

describe("createTransactionBatch", () => {
  it("validates the batch before inserting every item in one atomic operation", async () => {
    const source = account("Source");
    const destination = account("Destination");
    const food = category();
    const memory = transactionRepository();
    const occurredAt = "2026-09-04T12:00:00.000Z";
    const items: TransactionBatchItem[] = [
      {
        type: "transaction",
        transaction: {
          accountId: source.id,
          kind: "expense",
          amount: "12.5",
          categoryId: food.id,
          occurredAt,
        },
      },
      {
        type: "transfer",
        transfer: {
          fromAccountId: source.id,
          toAccountId: destination.id,
          amount: "100",
          occurredAt,
        },
      },
    ];

    const result = await createTransactionBatch(items, {
      accounts: accountRepository([source, destination]),
      categories: categoryRepository([food]),
      transactions: memory.repository,
    });

    expect(result).toEqual({ ok: true, value: { created: 2 } });
    expect(memory.atomicCalls()).toBe(1);
    expect(memory.records).toHaveLength(3);
    expect(memory.records.map((record) => record.kind)).toEqual([
      "expense",
      "expense",
      "income",
    ]);
  });
});

const date = new Date("2026-09-04T12:00:00.000Z");

function account(name: string): Account {
  return {
    id: crypto.randomUUID(),
    name,
    type: "checking",
    currency: "KZT",
    icon: "card",
    iconColor: "red",
    sortOrder: 0,
    createdAt: date,
    updatedAt: date,
  };
}

function category(): Category {
  return {
    id: crypto.randomUUID(),
    systemKey: null,
    name: "Food",
    kind: "expense",
    parentId: null,
    icon: null,
    color: null,
    isSystem: false,
    examples: [],
    sortOrder: 0,
    createdAt: date,
    updatedAt: date,
  };
}

function accountRepository(accounts: Account[]): AccountRepository {
  return {
    async findById(id) { return accounts.find((item) => item.id === id) ?? null; },
  } as AccountRepository;
}

function categoryRepository(categories: Category[]): CategoryRepository {
  return {
    async findById(id) { return categories.find((item) => item.id === id) ?? null; },
  } as CategoryRepository;
}

function transactionRepository(): {
  repository: TransactionRepository;
  records: TransactionRecord[];
  atomicCalls(): number;
} {
  const records: TransactionRecord[] = [];
  let calls = 0;
  const insertTransaction = async (values: TransactionValues): Promise<TransactionRecord> => {
    const record = {
      ...values,
      id: crypto.randomUUID(),
      recurringScheduleId: values.recurringScheduleId ?? null,
      createdAt: date,
      updatedAt: date,
    };
    records.push(record);
    return record;
  };
  const store = {
    insertTransaction,
    async insertTransactions(values: TransactionValues[]) {
      return Promise.all(values.map(insertTransaction));
    },
  } as TransactionStore;
  const repository = {
    ...store,
    async atomically<Value>(operation: (store: TransactionStore) => Promise<Value>) {
      calls += 1;
      return operation(store);
    },
  } as TransactionRepository;
  return { repository, records, atomicCalls: () => calls };
}
