import { Elysia, t } from "elysia";

import type { RecurringDeletionAction } from "../../../application/transactions/delete-recurring-transaction.ts";
import type { Result } from "../../../domain/shared/result.ts";
import type {
  TransactionInput,
  TransactionResponse,
  UpcomingTransaction,
} from "../../../domain/transactions/transaction.ts";
import {
  recurringDeletionActionSchema,
  transactionBodySchema,
  transactionBatchBodySchema,
  transactionIdParamsSchema,
  transferBodySchema,
} from "../schemas/transaction.http-schema.ts";

export type TransactionController = {
  list(input: { accountId?: string }): Promise<TransactionResponse[]>;
  upcoming(input: { accountId?: string }): Promise<UpcomingTransaction[]>;
  create(input: TransactionInput): Promise<Result<TransactionResponse, string>>;
  transfer(
    input: typeof transferBodySchema.static,
  ): Promise<Result<{ source: TransactionResponse; destination: TransactionResponse }, string>>;
  batch(
    input: typeof transactionBatchBodySchema.static.transactions,
  ): Promise<Result<{ created: number }, string>>;
  update(input: {
    id: string;
    transaction: TransactionInput;
  }): Promise<Result<TransactionResponse, string>>;
  delete(input: {
    id: string;
    action?: RecurringDeletionAction;
  }): Promise<Result<{ deleted: boolean; stopped?: boolean }, string>>;
  updateRecurring(input: {
    scheduleId: string;
    expectedOccurredAt: string;
    transaction: TransactionInput;
  }): Promise<Result<{ updated: true }, string>>;
  deleteRecurring(input: {
    scheduleId: string;
    occurredAt: Date;
    action: RecurringDeletionAction;
  }): Promise<Result<{ deleted: boolean; stopped: boolean }, string>>;
};

export function createTransactionsRouter(controller: TransactionController) {
  return new Elysia({ prefix: "/transactions" })
    .get("/", ({ query }) => controller.list(query), {
      query: t.Object({ accountId: t.Optional(t.String({ format: "uuid" })) }),
    })
    .get("/upcoming", ({ query }) => controller.upcoming(query), {
      query: t.Object({ accountId: t.Optional(t.String({ format: "uuid" })) }),
    })
    .put("/recurring/:id", async ({ params, body, set }) => {
      const result = await controller.updateRecurring({
        scheduleId: params.id,
        expectedOccurredAt: body.expectedOccurredAt,
        transaction: body.transaction,
      });
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, {
      params: transactionIdParamsSchema,
      body: t.Object({
        transaction: transactionBodySchema,
        expectedOccurredAt: t.String({ format: "date-time" }),
      }),
    })
    .delete("/recurring/:id", async ({ params, query, set }) => {
      const result = await controller.deleteRecurring({
        scheduleId: params.id,
        occurredAt: new Date(query.occurredAt),
        action: query.action,
      });
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, {
      params: transactionIdParamsSchema,
      query: t.Object({
        occurredAt: t.String({ format: "date-time" }),
        action: recurringDeletionActionSchema,
      }),
    })
    .post("/", async ({ body, set }) => {
      const result = await controller.create(body);
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      set.status = 201;
      return result.value;
    }, { body: transactionBodySchema })
    .post("/transfer", async ({ body, set }) => {
      const result = await controller.transfer(body);
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      set.status = 201;
      return result.value;
    }, { body: transferBodySchema })
    .post("/batch", async ({ body, set }) => {
      const result = await controller.batch(body.transactions);
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      set.status = 201;
      return result.value;
    }, { body: transactionBatchBodySchema })
    .put("/:id", async ({ params, body, set }) => {
      const result = await controller.update({ id: params.id, transaction: body });
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, { params: transactionIdParamsSchema, body: transactionBodySchema })
    .delete("/:id", async ({ params, query, set }) => {
      const result = await controller.delete({ id: params.id, action: query.action });
      if (!result.ok) {
        set.status = transactionErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, {
      params: transactionIdParamsSchema,
      query: t.Object({ action: t.Optional(recurringDeletionActionSchema) }),
    });
}

function transactionErrorStatus(code: string): 400 | 404 | 409 {
  if (
    code === "transaction_not_found" ||
    code === "account_not_found" ||
    code === "category_not_found" ||
    code === "recurring_transaction_not_found"
  ) {
    return 404;
  }
  if (code === "stale_occurrence" || code === "not_recurring") return 409;
  return 400;
}
