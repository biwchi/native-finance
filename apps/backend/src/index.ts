import { app } from "./app.ts";
import { config } from "./config.ts";
import { closeDatabase } from "./db/client.ts";

app.listen({
  hostname: config.host,
  port: config.port,
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

