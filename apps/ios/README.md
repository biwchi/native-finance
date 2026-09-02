# iOS client

Open `FinanceTracker.xcodeproj` in Xcode 26 or newer to build the iOS 26 Liquid Glass tab bar. The debug app expects the backend at `http://localhost:3000`, which works from the iOS simulator.

Before installing on a physical device, replace `API_BASE_URL` in `FinanceTracker/Resources/Info.plist` with an address that the device can reach. Use HTTPS outside local development.

The centered account picker loads accounts from the backend. Total is the default and leaves transaction requests unfiltered; selecting an account adds its ID to the request. Its Manage Accounts action opens a sheet for adding, editing, deleting, and reordering accounts.
