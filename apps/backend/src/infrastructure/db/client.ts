import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

import { config } from "../../config.ts";
import * as schema from "./schema/index.ts";

const queryClient = postgres(config.databaseUrl, {
  max: 10,
  prepare: false,
});

export const db = drizzle(queryClient, { schema, casing: "snake_case" });

export type Database = typeof db;

export function closeDatabase(): Promise<void> {
  return queryClient.end();
}
