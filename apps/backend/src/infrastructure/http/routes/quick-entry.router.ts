import { Elysia } from "elysia";

import type {
  QuickEntryError,
  QuickEntryResponse,
} from "../../../application/quick-entry/interpret-quick-entry.ts";
import type { Result } from "../../../domain/shared/result.ts";
import { quickEntryBodySchema } from "../schemas/quick-entry.http-schema.ts";

export type QuickEntryController = {
  interpret(
    input: typeof quickEntryBodySchema.static,
  ): Promise<Result<QuickEntryResponse, QuickEntryError>>;
};

export function createQuickEntryRouter(controller: QuickEntryController) {
  return new Elysia({ prefix: "/quick-entry" })
    .post("/interpret", async ({ body, set }) => {
      const result = await controller.interpret(body);
      if (!result.ok) {
        set.status = quickEntryErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, { body: quickEntryBodySchema });
}

function quickEntryErrorStatus(code: QuickEntryError): 400 | 404 | 422 | 503 {
  if (code === "account_not_found") return 404;
  if (code === "quick_entry_unavailable" || code === "exchange_rates_unavailable") return 503;
  if (code === "invalid_ai_response") return 422;
  return 400;
}
