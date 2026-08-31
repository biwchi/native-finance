# Finance Tracker

One repository for the native iOS client and the shared backend. A web client can be added under `apps/web` later.

## Requirements

- Bun 1.3 or newer
- Docker Desktop or another Docker Compose runtime
- Xcode 26 or newer for the iOS 26 Liquid Glass tab bar

## Start the backend

```sh
bun install
docker compose up -d postgres
cp apps/backend/.env.example apps/backend/.env
bun run db:migrate
bun run dev
```

If another PostgreSQL instance already uses port `5432`, set `POSTGRES_PORT=5433`
in a `.env` file at the repository root and change the port in
`apps/backend/.env`'s `DATABASE_URL` to `5433`. Then run
`docker compose up -d postgres` again before applying migrations. The root `.env`
configures Docker Compose; `apps/backend/.env` configures the backend and migrations.

The API listens on `http://localhost:3000`. Check it with:

```sh
curl http://localhost:3000/health
```

## Run the iOS app

Open `apps/ios/FinanceTracker.xcodeproj`, select an iPhone simulator, and run the `FinanceTracker` scheme. The debug build connects to `http://127.0.0.1:3000`.

The app loads accounts from `/api/v1/accounts`, creates and edits them from the account picker, and filters `/api/v1/transactions` by the selected account. Account icons, colors, and ISO currency codes are stored by the backend. The default Total selection loads transactions across every account.

## Common commands

```sh
bun run typecheck
bun test
bun run db:generate
bun run db:migrate
bun run db:studio
```

Drizzle schema changes belong in `apps/backend/src/db/schema.ts`. Run `bun run db:generate` after changing it and commit the generated migration.
