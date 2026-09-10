# iOS client

Open `FinanceTracker.xcodeproj` in Xcode 26 or newer to build the iOS 26 Liquid Glass controls. Simulator Debug builds connect to `http://127.0.0.1:3000` to match the backend's IPv4 listener. Using `localhost` can reach another development server listening on IPv6 port 3000 and return a 404 even while this backend is running.

## Icons

App icons use the free Hugeicons Stroke Rounded set through the [Hugeicons Swift package](https://github.com/iSapozhnik/hugeicons-swift), pinned to revision `81caddf04ce5352652ffaa619562f02477dbf35d`. This is a community-maintained Swift wrapper around `@hugeicons/core-free-icons`. Xcode resolves it through Swift Package Manager. License notices are included in the app's `ThirdPartyNotices.txt` resource.

Use `AppIcon` for explicitly sized, Dynamic Type-aware icons, `Label(..., icon: ...)` for native labels and menus, and `AppIcons.uiImage(named:)` for UIKit tab items. `AppIcons.artwork` maps stable app identifiers to Hugeicons artwork. Existing Iconoir identifiers and older SF Symbols names remain compatible with saved accounts and categories. Keep using the app identifiers in picker choices; add new artwork mappings in `AppIcons` when needed. Icons without an exact equivalent use the closest available artwork, and unknown saved names show a tag.

Run `AppIconTests` and `AccentControlContrastTests` when changing icon rendering or the icon catalog. The rendering tests attach light/dark samples to the Xcode test results.

## Test on your iPhone over Wi-Fi

1. Connect your Mac and iPhone to the same Wi-Fi network.
2. Start the backend with `bun run dev` from the repository root. Keep `HOST=::` in `apps/backend/.env` so it accepts both IPv6 and IPv4 connections from your phone. An existing `HOST=0.0.0.0` setting accepts only IPv4 and can cause timeouts on networks where the iPhone reaches the Mac over IPv6. After changing this setting, restart the backend.
3. Select your iPhone as the run destination in Xcode and run the `FinanceTracker Device` scheme. It builds with the Debug configuration and launches without attaching LLDB, so a stalled debugger connection cannot hold the app at its launch screen. Use the original `FinanceTracker` scheme when you need breakpoints.
4. Allow **Local Network** access when the app asks.

Each device Debug build automatically uses `http://<your-Mac-hostname>.local:3000`. Xcode's **Configure API** build step detects the Mac's Bonjour hostname and writes a generated Info.plist into DerivedData. The hostname continues to work when the Mac's Wi-Fi IP changes; no address needs to be committed or switched when returning to the simulator. Local HTTP permission is added only to Debug builds, and requests wait up to 30 seconds for connectivity while you respond to the first permission prompt.

To check connectivity from the iPhone, open `http://<your-Mac-hostname>.local:3000/health` in Safari. Find your Mac's hostname with:

```sh
scutil --get LocalHostName
```

If it does not load, check that the backend is running, allow incoming connections for Bun if the macOS firewall asks, and avoid guest Wi-Fi or VPN configurations that prevent devices from communicating. If local-network access was denied, enable Finance Tracker under **Settings → Privacy & Security → Local Network** on the iPhone, then reopen the app.

If the entire screen stays black after running from Xcode, press **Stop** in Xcode, close Finance Tracker on the phone, then run the **FinanceTracker Device** scheme to rebuild, reinstall, and launch independently of the debugger. Keep the phone unlocked during installation. The initial import has its own setup screen. After it succeeds, subsequent launches show saved local content even when the server is unavailable. This recovery preserves app data and does not require uninstalling the app.

## Override the API address

For a different port, a network that does not resolve `.local` names, or a hosted API, set the FinanceTracker target's **Build Settings → User-Defined → API_BASE_URL** for the relevant configuration, then rebuild. Leave it empty for automatic selection. For example, `http://192.168.1.20:3000` uses your Mac's current Wi-Fi IP; it must be updated if that IP changes. A command-line build can pass the same setting:

```sh
xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'generic/platform=iOS' \
  API_BASE_URL=http://192.168.1.20:3000 build
```

Release builds use `API_BASE_URL` when supplied, otherwise the value in `FinanceTracker/Resources/Info.plist`; they never detect a development Mac or add the Debug local-network permissions. Set an HTTPS endpoint for distribution.

The account picker and finance screens read the shared local SQLite database. **All Accounts** is the default; selecting an account or month queries the local data immediately. The menu shows the first four accounts in the saved order. **View Accounts** opens the complete accounts sheet, where each account shows its balance in its currency and **All Accounts** shows the combined balance in the display currency. Tapping an account or **All Accounts** selects it and closes the sheet. Swipe left on an account for **Edit** and **Delete**; deletion requires confirmation. Use the toolbar's **Edit** mode to tap into account details, reorder, or delete accounts. Reordering also changes which four accounts appear in the menu. **Add Account** and account editing open at full sheet height.

## Debts

Choose **Debt** when adding a transaction, select the account you lend from, and choose or create a recipient (for example, Alexey). Recipients have their own icons and colors. Set them when creating a recipient, or change them from **Debts → Add → Manage recipients** or **Edit recipient** in the transaction recipient picker. Changes appear on existing loans immediately. Debt transactions reduce the account balance but do not count as income or budget spending. They cannot repeat or have expense categories.

Open **Home → Finances → Debts** using the labeled Finances button in the dashboard toolbar. This screen includes outstanding debt transactions across all accounts and months, a total in the default display currency, recipient counts, and a balance for each recipient. Tap a transaction to edit it. If exchange rates are unavailable, separate currency totals are shown. Swipe a loan and choose **Delete · returned** once the money has been returned to its original account. Deleting removes the outstanding loan and restores the account balance; recipients remain available for future loans.

Apply the backend migration with `bun run db:migrate` before using this client with an existing database.

## Navigation

Home is the main screen. Its trailing toolbar groups the icon-only **Finances** button with a 2×2 grid icon and **Settings**, with Settings on the far right. Finances opens a permanent directory for **Recurring**, **Debts**, and **Budget**, including when these features have no data. The centered Add Transaction button belongs to the dashboard, so pushed pages cover it along with the dashboard. There is no bottom navigation menu.

**Recurring** shows a centered amount with **Expenses / Income / All** and **Day / Week / Month / Year** selectors, defaulting to Expenses and Month. Day and Week cover the next 1 and 7 days, Month the next 30 days, and Year the next 12 months. All shows net cash flow (income minus expenses). Projections expand actual scheduled dates in UTC, preserve month-end and leap-day anchors, respect end dates, and convert complete totals into the display currency. The type filter also applies to active schedules and recorded transactions. Add opens transaction entry with recurrence enabled and the selected transaction type.

**Budget** opens an overview for the selected account and Home’s selected month (or the current month when Home uses a different period). It keeps the summary at the top, then surfaces over-budget pool and category limits with links to their transactions. Each pool has a separate card with a stable color, its remaining amount, and a current-month elapsed-time marker. Tap a pool to expand its categories and the **View pool transactions** link; standalone categories appear below the pools. Category limits retain all subcategory spending, with a note when part of that spending belongs outside the displayed pool. The marker is informational and is hidden for past and future months. The month picker changes the spending report. Each account, including **All Accounts**, has one saved budget that applies to every month. **Settings** edits that shared setup; changing or clearing limits also updates reports for previous months. Debt transactions do not count as budget spending.

## Settings

**Budget summary → Use pool and category limits** is on by default. When no monthly limit is set, Home and Budget use the sum of pool limits and category limits outside pools. Category limits within a pool do not add to the total. An explicit monthly limit always takes precedence. Turn this setting off to use only an explicit monthly limit for the budget summary. With no configured limits, the existing spending and net summaries remain.

**Recurring reminders → Show on Home** controls how many days before a recurring transaction its reminder appears (default: 3; configurable from the due day to 30 days before). Home shows the nearest upcoming transaction for the selected account, independently of the summary period. Multiple qualifying schedules appear as a stack; a single schedule appears as one card. Reminders display the original currency and full amount precision and have no tap action.

**First day of week** defaults to the device calendar and can be set to any weekday. The preference updates calendar pickers and the Week / Bi-weekly filters on Home. **Round totals** displays whole amounts on summary cards, Budget limits and forecasts, account balances, and debt totals. Stored amounts and transaction editing keep their original precision.

Support destinations are read from the app Info.plist: `APP_STORE_REVIEW_URL`, `SUPPORT_URL`, `PRIVACY_POLICY_URL`, and `TERMS_OF_USE_URL`. Use HTTPS URLs (the support URL also accepts `mailto:`); the App Store review URL should be the app's actual listing with `action=write-review`. Until real destinations are supplied, the rows explain that the destination is unavailable.

**Delete all data** requires a warning confirmation followed by typing the exact lowercase word `confirm`. The client clears local finance data and persists a reset operation in the same SQLite transaction. It sends that reset automatically when connected. A workspace generation barrier keeps delayed uploads and responses from restoring deleted content; new local entries wait behind the reset. Display preferences remain. This backend currently has one personal workspace and no user authentication: the operation applies to the entire connected workspace. The user-account deletion row is enabled and uses the same warning and typed-confirmation flow. Until a user identity service exists, the final step reports that account deletion is not available and leaves data intact.

## Local storage and sync

The shared GRDB 7.11.1 database lives at `Application Support/FinanceTracker/finance.sqlite`. Apply backend migrations through 0014 before running this client. Migration 0014 keeps the most recently edited budget per account with its pools and category limits, then removes the saved month. The local SQLite upgrade makes the same change and preserves pending offline edits. First launch imports a consistent snapshot before enabling editing. Later launches use the saved database immediately.

Finance saves, ordering, transfers, reviewed Quick Entry batches, budgets, and recurrence work locally. A single worker attempts uploads after a commit, then reads server changes. Connectivity changes, foreground entry, and an iOS background refresh request also trigger it. iOS chooses when suspended apps receive execution time; the app does not depend on a fixed background schedule.

Routine synchronization has no visible indicators. Conflicts and permanent rejections appear under **Settings → Review changes**. This view preserves both versions and lets you keep local changes or accept the server version. Quick Entry interpretation needs a connection, uses local account/category context, and preserves the prompt and reviewed drafts. Committing reviewed drafts works offline.

All screens share a persistent USD-based exchange-rate table. Successful refreshes are reused for 24 hours. Failed refreshes leave cached conversions usable; missing rates leave original amounts visible. **Settings → Exchange rates** shows effective dates and the last successful fetch.

See [the sync protocol and validation guide](../../docs/local-first.md) for database, API, reset, and test details.
