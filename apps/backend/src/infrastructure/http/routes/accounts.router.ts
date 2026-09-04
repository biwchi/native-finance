import { Elysia, t } from "elysia";

import type { Account } from "../../../domain/accounts/account.ts";
import type { Result } from "../../../domain/shared/result.ts";
import {
  accountBodySchema,
  accountIdParamsSchema,
} from "../schemas/account.http-schema.ts";

export type AccountController = {
  list(): Promise<Account[]>;
  create(input: typeof accountBodySchema.static): Promise<Account>;
  reorder(accountIds: string[]): Promise<Result<Account[], string>>;
  update(input: {
    id: string;
    details: typeof accountBodySchema.static;
  }): Promise<Result<Account, string>>;
  delete(id: string): Promise<Result<{ deleted: true }, string>>;
};

export function createAccountsRouter(controller: AccountController) {
  return new Elysia({ prefix: "/accounts" })
    .get("/", () => controller.list())
    .post("/", async ({ body, set }) => {
      const account = await controller.create(body);
      set.status = 201;
      return account;
    }, { body: accountBodySchema })
    .patch("/order", async ({ body, set }) => {
      const result = await controller.reorder(body.accountIds);
      if (!result.ok) {
        set.status = 400;
        return { message: result.error.message };
      }
      return result.value;
    }, {
      body: t.Object({
        accountIds: t.Array(t.String({ format: "uuid" }), { uniqueItems: true }),
      }),
    })
    .patch("/:id", async ({ params, body, set }) => {
      const result = await controller.update({ id: params.id, details: body });
      if (!result.ok) {
        set.status = 404;
        return { message: result.error.message };
      }
      return result.value;
    }, { params: accountIdParamsSchema, body: accountBodySchema })
    .delete("/:id", async ({ params, set }) => {
      const result = await controller.delete(params.id);
      if (!result.ok) {
        set.status = 404;
        return { message: result.error.message };
      }
      return result.value;
    }, { params: accountIdParamsSchema });
}
