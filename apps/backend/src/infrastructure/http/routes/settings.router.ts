import { Elysia, t } from "elysia";
import type { AppDataRepository } from "../../../application/settings/app-data.repository.ts";

export function createSettingsRouter(data: AppDataRepository) {
  return new Elysia({ prefix: "/settings" })
    .delete("/data", async () => {
      await data.deleteAll();
      return { deleted: true };
    }, { body: t.Object({ confirmation: t.Literal("confirm") }) });
}
