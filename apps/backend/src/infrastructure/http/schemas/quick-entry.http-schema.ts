import { t } from "elysia";

export const quickEntryBodySchema = t.Object({
  text: t.String({ minLength: 1, maxLength: 20_000 }),
  defaultAccountId: t.String({ format: "uuid" }),
  locale: t.String({ minLength: 2, maxLength: 100 }),
  timeZone: t.String({ minLength: 1, maxLength: 100 }),
});
