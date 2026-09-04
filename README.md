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

The API is reachable over IPv4 at `http://127.0.0.1:3000`. Check it with:

```sh
curl http://127.0.0.1:3000/health
```

Quick Entry runs through the backend so the OpenAI key never ships in the iOS
app. Set `OPENAI_API_KEY` in `apps/backend/.env`; `OPENAI_MODEL` defaults to
`gpt-5-nano`. Restart the backend after changing either value.

Keep one backend running at a time. Stop it with **Ctrl+C** before restarting;
**Ctrl+Z** suspends it and leaves the API port occupied. A second server now fails
with a port-in-use error. If a suspended server is holding the port, use `jobs`
and `fg` in the terminal where you started it, then **Ctrl+C** to stop it.

## Run the iOS app

Open `apps/ios/FinanceTracker.xcodeproj`, select an iPhone simulator or your connected iPhone, and run the `FinanceTracker` scheme. Simulator Debug builds connect to `http://127.0.0.1:3000`. Device Debug builds automatically connect to your Mac at `http://<your-Mac-hostname>.local:3000`.

For a physical iPhone, keep both devices on the same Wi-Fi, leave the backend running with `HOST=0.0.0.0`, and allow Local Network access when the app asks. See [the iOS setup guide](apps/ios/README.md) for troubleshooting and API address overrides.

The app loads accounts from `/api/v1/accounts`, creates and edits them from the account picker, and filters `/api/v1/transactions` by the selected account. Account icons, colors, and ISO currency codes are stored by the backend. The default Total selection loads transactions across every account.

## Common commands

```sh
bun run typecheck
bun test
bun run db:generate
bun run db:migrate
bun run db:studio
```

Drizzle schema changes belong in `apps/backend/src/infrastructure/db/schema/`.
Keep tables grouped by domain, then run `bun run db:generate` and commit any
generated migration.
