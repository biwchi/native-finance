import { Elysia, t } from "elysia";
import type { DebtRepository } from "../../../domain/debts/debt.ts";
import { categoryColorSchema } from "../schemas/category.http-schema.ts";

const appearance = {
  icon: t.Optional(t.String({ minLength: 1, maxLength: 80, pattern: "\\S" })),
  color: t.Optional(categoryColorSchema),
};
const nameSchema = t.String({ minLength: 1, maxLength: 200 });

export function createDebtsRouter(debts: DebtRepository) {
  return new Elysia({ prefix: "/debts" })
    .get("/", () => debts.list())
    .post("/", async ({ body, set }) => {
      if (!body.name.trim()) {
        set.status = 400;
        return { message: "Recipient name cannot be empty" };
      }
      const debt = await debts.create({ ...body, name: body.name.trim(), icon: body.icon?.trim() });
      set.status = 201;
      return debt;
    }, { body: t.Object({ name: nameSchema, ...appearance }) })
    .patch("/:id", async ({ params, body, set }) => {
      if (body.name !== undefined && !body.name.trim()) {
        set.status = 400;
        return { message: "Recipient name cannot be empty" };
      }
      const details = {
        ...body,
        ...(body.name !== undefined ? { name: body.name.trim() } : {}),
        ...(body.icon !== undefined ? { icon: body.icon.trim() } : {}),
      };
      const debt = Object.keys(details).length === 0
        ? await debts.findById(params.id)
        : await debts.update(params.id, details);
      if (!debt) {
        set.status = 404;
        return { message: "Debt recipient not found" };
      }
      return debt;
    }, {
      params: t.Object({ id: t.String({ format: "uuid" }) }),
      body: t.Object({ name: t.Optional(nameSchema), ...appearance }),
    });
}
