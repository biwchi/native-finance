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

If the entire screen stays black after running from Xcode, press **Stop** in Xcode, close Finance Tracker on the phone, then run the **FinanceTracker Device** scheme to rebuild, reinstall, and launch independently of the debugger. Keep the phone unlocked during installation. Startup requests run asynchronously; while the server is unavailable, the dashboard should still show loading or error content. This recovery preserves app data and does not require uninstalling the app.

## Override the API address

For a different port, a network that does not resolve `.local` names, or a hosted API, set the FinanceTracker target's **Build Settings → User-Defined → API_BASE_URL** for the relevant configuration, then rebuild. Leave it empty for automatic selection. For example, `http://192.168.1.20:3000` uses your Mac's current Wi-Fi IP; it must be updated if that IP changes. A command-line build can pass the same setting:

```sh
xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'generic/platform=iOS' \
  API_BASE_URL=http://192.168.1.20:3000 build
```

Release builds use `API_BASE_URL` when supplied, otherwise the value in `FinanceTracker/Resources/Info.plist`; they never detect a development Mac or add the Debug local-network permissions. Set an HTTPS endpoint for distribution.

The centered account picker loads accounts from the backend. Total is the default and leaves transaction requests unfiltered; selecting an account adds its ID to the request. Its Manage Accounts action opens a sheet for adding, editing, deleting, and reordering accounts.

## Debts

Choose **Debt** when adding a transaction, select the account you lend from, and choose or create a recipient (for example, Alexey). Recipients have their own icons and colors. Set them when creating a recipient, or change them from **Debts → Add → Manage recipients** or **Edit recipient** in the transaction recipient picker. Changes appear on existing loans immediately. Debt transactions reduce the account balance but do not count as income or budget spending. They cannot repeat or have expense categories.

Open **Home → Finances → Debts** using the labeled Finances button in the dashboard toolbar. This screen includes outstanding debt transactions across all accounts and months, a total in the default display currency, recipient counts, and a balance for each recipient. Tap a transaction to edit it. If exchange rates are unavailable, separate currency totals are shown. Swipe a loan and choose **Delete · returned** once the money has been returned to its original account. Deleting removes the outstanding loan and restores the account balance; recipients remain available for future loans.

Apply the backend migration with `bun run db:migrate` before using this client with an existing database.

## Navigation

Home is the main screen. Its trailing toolbar groups the labeled **Finances** button and **Settings**, with Settings on the far right. Finances opens a permanent directory for **Recurring**, **Debts**, and **Budget**, including when these features have no data. The centered Add Transaction button belongs to the dashboard, so pushed pages cover it along with the dashboard. There is no bottom navigation menu.

**Recurring** shows a centered amount with **Expenses / Income / All** and **Day / Week / Month / Year** selectors, defaulting to Expenses and Month. Day and Week cover the next 1 and 7 days, Month the next 30 days, and Year the next 12 months. All shows net cash flow (income minus expenses). Projections expand actual scheduled dates in UTC, preserve month-end and leap-day anchors, respect end dates, and convert complete totals into the display currency. The type filter also applies to active schedules and recorded transactions. Add opens transaction entry with recurrence enabled and the selected transaction type.

**Budget** opens an overview for the selected account and Home’s selected month (or the current month when Home uses a different period). It shows spent/remaining amounts, progress for each pool and category limit, and category spending when only a shared pool limit exists. Tap a pool or category to see its transactions. The month picker changes the reporting month; the **Settings** icon opens the existing budget editor for that exact month and account. Debt transactions do not count as budget spending.

## Settings

**Recurring reminders → Show on Home** controls how many days before a recurring transaction its reminder appears (default: 3; configurable from the due day to 30 days before). Home shows the nearest upcoming transaction for the selected account, independently of the summary period. Multiple qualifying schedules appear as a stack; a single schedule appears as one card. Reminders display the original currency and full amount precision and have no tap action.

**First day of week** defaults to the device calendar and can be set to any weekday. The preference updates calendar pickers and the Week / Bi-weekly filters on Home. **Round totals** displays whole amounts on summary cards, Budget limits and forecasts, account balances, and debt totals. Stored amounts and transaction editing keep their original precision.

Support destinations are read from the app Info.plist: `APP_STORE_REVIEW_URL`, `SUPPORT_URL`, `PRIVACY_POLICY_URL`, and `TERMS_OF_USE_URL`. Use HTTPS URLs (the support URL also accepts `mailto:`); the App Store review URL should be the app's actual listing with `action=write-review`. Until real destinations are supplied, the rows explain that the destination is unavailable.

**Delete all data** requires a warning confirmation followed by typing the exact lowercase word `confirm`. The client calls `DELETE /api/v1/settings/data` with `{"confirmation":"confirm"}`. The backend removes all accounts, transactions, recurring schedules, budgets (including global plans), debts, and categories in one transaction. On success the app discards its stores and response cache; display preferences remain. This backend currently has one personal workspace and no user authentication: the operation applies to the entire connected workspace. The user-account deletion row is enabled and uses the same warning and typed-confirmation flow. Until a user identity service exists, the final step reports that account deletion is not available and leaves data intact.
