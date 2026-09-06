const DEFAULT_DATABASE_URL =
  "postgresql://finance_tracker:finance_tracker@localhost:5432/finance_tracker";

function readPort(value: string | undefined): number {
  const port = Number(value ?? "3000");

  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("PORT must be an integer between 1 and 65535");
  }

  return port;
}

export const config = {
  corsOrigin: Bun.env.CORS_ORIGIN ?? "http://localhost:3001",
  databaseUrl: Bun.env.DATABASE_URL ?? DEFAULT_DATABASE_URL,
  frankfurterBaseUrl: Bun.env.FRANKFURTER_BASE_URL ?? "https://api.frankfurter.dev",
  // Accept both IPv6 and IPv4 connections from physical devices.
  host: Bun.env.HOST ?? "::",
  openAIBaseUrl: Bun.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1",
  openAIApiKey: Bun.env.OPENAI_API_KEY,
  openAIModel: Bun.env.OPENAI_MODEL ?? "gpt-5.6-luna",
  port: readPort(Bun.env.PORT),
} as const;
