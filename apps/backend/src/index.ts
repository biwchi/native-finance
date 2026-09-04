import { app } from "./app.ts";
import { config } from "./config.ts";
import { closeDatabase } from "./infrastructure/db/client.ts";

app.listen({
  hostname: config.host,
  port: config.port,
  // A second dev server must not share traffic with a suspended or stale process.
  reusePort: false,
});

console.log(
  `Finance Tracker API is running at http://${config.host}:${config.port}`,
);

async function shutdown(): Promise<void> {
  await closeDatabase();
  process.exit(0);
}

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
