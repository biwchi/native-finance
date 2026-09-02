# iOS client

Open `FinanceTracker.xcodeproj` in Xcode 26 or newer to build the iOS 26 Liquid Glass tab bar. Simulator builds connect to `http://localhost:3000`.

## Icons

App icons use the official [Iconoir Swift package](https://github.com/iconoir-icons/iconoir-swift), pinned to revision `66391f61281c4c203ae2003ebf66627dc849f233`. Xcode resolves it through Swift Package Manager. Its MIT notice is included in the app's `ThirdPartyNotices.txt` resource.

Use `AppIcon` for explicitly sized, Dynamic Type-aware icons, `Label(..., icon: ...)` for native labels and menus, and `AppIcons.uiImage(named:)` for UIKit tab items. Use Iconoir's kebab-case names. `AppIcons` translates previously saved SF Symbols names for account/category compatibility; new picker choices use Iconoir names. Icons without an exact equivalent use the closest available artwork, and unknown saved names show a tag.

Run `AppIconTests` and `AccentControlContrastTests` when changing icon rendering or the icon catalog. The rendering tests attach light/dark samples to the Xcode test results.

## Test on your iPhone over Wi-Fi

1. Connect your Mac and iPhone to the same Wi-Fi network.
2. Start the backend with `bun run dev` from the repository root. Keep `HOST=0.0.0.0` in `apps/backend/.env` so it accepts connections from your phone.
3. Select your iPhone as the run destination in Xcode and run the `FinanceTracker` scheme with the Debug configuration.
4. Allow **Local Network** access when the app asks.

Each device Debug build automatically uses `http://<your-Mac-hostname>.local:3000`. Xcode's **Configure API** build step detects the Mac's Bonjour hostname and writes a generated Info.plist into DerivedData. The hostname continues to work when the Mac's Wi-Fi IP changes; no address needs to be committed or switched when returning to the simulator. Local HTTP permission is added only to Debug builds, and requests wait up to 30 seconds for connectivity while you respond to the first permission prompt.

To check connectivity from the iPhone, open `http://<your-Mac-hostname>.local:3000/health` in Safari. Find your Mac's hostname with:

```sh
scutil --get LocalHostName
```

If it does not load, check that the backend is running, allow incoming connections for Bun if the macOS firewall asks, and avoid guest Wi-Fi or VPN configurations that prevent devices from communicating. If local-network access was denied, enable Finance Tracker under **Settings → Privacy & Security → Local Network** on the iPhone, then reopen the app.

## Override the API address

For a different port, a network that does not resolve `.local` names, or a hosted API, set the FinanceTracker target's **Build Settings → User-Defined → API_BASE_URL** for the relevant configuration, then rebuild. Leave it empty for automatic selection. For example, `http://192.168.1.20:3000` uses your Mac's current Wi-Fi IP; it must be updated if that IP changes. A command-line build can pass the same setting:

```sh
xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'generic/platform=iOS' \
  API_BASE_URL=http://192.168.1.20:3000 build
```

Release builds use `API_BASE_URL` when supplied, otherwise the value in `FinanceTracker/Resources/Info.plist`; they never detect a development Mac or add the Debug local-network permissions. Set an HTTPS endpoint for distribution.

The centered account picker loads accounts from the backend. Total is the default and leaves transaction requests unfiltered; selecting an account adds its ID to the request. Its Manage Accounts action opens a sheet for adding, editing, deleting, and reordering accounts.
