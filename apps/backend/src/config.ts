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
  host: Bun.env.HOST ?? "0.0.0.0",
  port: readPort(Bun.env.PORT),
} as const;
