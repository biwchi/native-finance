import { t } from "elysia";

export const accountBodySchema = t.Object({
  name: t.String({ minLength: 1, maxLength: 120 }),
  initialBalance: t.Optional(t.String({ pattern: "^-?(?:0|[1-9][0-9]{0,14})(?:\\.[0-9]{1,4})?$" })),
  currency: t.String({ pattern: "^[A-Za-z]{3}$" }),
  icon: t.String({ minLength: 1, maxLength: 80 }),
  iconColor: t.Union([
    t.Literal("blue"),
    t.Literal("indigo"),
    t.Literal("purple"),
    t.Literal("pink"),
    t.Literal("red"),
    t.Literal("orange"),
    t.Literal("green"),
    t.Literal("teal"),
    t.Literal("gray"),
  ]),
});

export const accountIdParamsSchema = t.Object({
  id: t.String({ format: "uuid" }),
});
