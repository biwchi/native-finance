import { cors } from "@elysiajs/cors";
import { Elysia } from "elysia";

import { config } from "./config.ts";
import { accountsRoutes } from "./routes/accounts.ts";
import { categoriesRoutes } from "./routes/categories.ts";
import { transactionsRoutes } from "./routes/transactions.ts";

export const app = new Elysia({ name: "finance-tracker-api" })
  .use(
    cors({
      origin: config.corsOrigin,
    }),
  )
  .get("/health", () => ({
    service: "finance-tracker-api",
    status: "ok" as const,
  }))
  .group("/api/v1", (api) =>
    api.use(accountsRoutes).use(categoriesRoutes).use(transactionsRoutes),
  );

export type App = typeof app;
