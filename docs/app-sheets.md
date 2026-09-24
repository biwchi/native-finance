# App sheets

`DesignSystem/Components/AppSheet.swift` supplies the shared `appSheet(isPresented:layout:background:onDismiss:content:)` and `appSheet(item:layout:background:onDismiss:content:)` APIs. It uses SwiftUI presentation modifiers available before the app's iOS 17 minimum. The presentation boundary owns appearance; reusable screen and list content no longer modifies its containing sheet.

## Audit

The current audit covers all 28 production `appSheet` call sites. Existing detents, drag indicators, navigation, interactive dismissal rules, and callbacks remain in place.

| Presenter | Destinations | Count |
| --- | --- | --- |
| MainView | Manual entry, camera, draft review, scan drafts, nested draft review, account management | 6 |
| QuickEntryReviewView | Nested draft editor | 1 |
| AccountManagementView | Account editor | 1 |
| CurrencyPickerView | Rate help | 1 |
| DashboardView | Summary metric, transaction editor | 2 |
| BudgetTransactionsView | Transaction editor | 1 |
| DebtsView | Recipient management, new debt transaction, transaction editor | 3 |
| DebtRecipientPicker | Nested recipient management | 1 |
| DebtRecipientsView | Nested recipient editor, with selection dismissal callback | 1 |
| CategorySettingsView | Category editor | 1 |
| SettingsView | Delete-data confirmation | 1 |
| SyncReviewView | Discard-changes review | 1 |
| CSVImportView | Import help, transaction review | 2 |
| TransactionListView | Transaction editor | 1 |
| RecurringTransactionsView | New transaction, recorded transaction, recurring transaction editor | 3 |
| CategoryPickerView | Nested category creation, with selection dismissal callback | 1 |
| FinanceDatePickerButton | Date filter | 1 |

The retired sheet modifier used the 32-point composer radius only before iOS 26. Four sheet-content views and the list adapter invoked it directly: transaction entry, date filter, rate help, summary metric detail, and the legacy list adapter. The list adapter also changed sheets indirectly whenever a sheet contained a list. Sheet geometry now has a separate token and no version branch.

The date filter keeps its elevated background, measured-height detent, and accessibility large detent. The camera keeps its black background, dark appearance, large detent, hidden drag indicator, edge-to-edge preview, and safe-area-aware controls. Transaction entry retains its existing page and scroll backgrounds. All 26 navigation-sheet presentations receive the older-OS toolbar correction from `AppSheet` by default. It adds 10 points to the presented hosting controller's top safe area, increasing the gap above 44-point toolbar controls from 6 to 16 points. The navigation container continues to fill the sheet, so its own background extends behind the grabber. This replaces the outer padding that exposed a black strip above elevated dark backgrounds. This includes quick-entry, scan, document, and CSV reviews, nested editors, management sheets, help sheets, confirmations, and metric detail. There is no opt-in spacing modifier. The camera and measured date filter explicitly use `layout: .content` to retain their existing spacing. iOS 26 retains its native layout. The default presentation background now applies consistently to all other sheets.

## OS-owned presentations and effects

PhotosPicker and fileImporter in ReceiptScannerView, fileImporter in CSVImportView, and fileExporter in CSVExportView, CSVImportHelpView, and SyncReviewView remain system-owned. Confirmation dialogs, alerts, permission prompts, and picker or menu internals also keep their native appearance. The month picker and transaction date/time picker are popovers with explicit compact popover adaptation.

A fixed app corner radius and semantic background do not reproduce iOS 26 Liquid Glass, system shadows, dimming, animations, keyboard styling, or the geometry and adaptation chosen by the OS in every size class. The wrapper retains native presentation and accessibility behavior. Simulator camera checks cover the preview container without a live camera, safe areas, and attachment controls; live preview, capture, torch hardware, and physical-device camera permission transitions require a device.

## Verification

The AppSheetTests simulator suite covers light and dark appearances, native iOS 26 reference snapshots, medium and large detents, scrolling, keyboard avoidance with a 300-point test input view, navigation push/pop, nested sheets, inherited environment, interactive-dismissal configuration, both bindings, item replacement, dismissal callbacks, and the actual receipt camera view's safe areas. Tests use local fixtures and do not call AI services. Existing date-filter rendering tests cover measured-height and accessibility detents.

Verified on 2026-09-21 with Xcode 26.6, an iPhone 16 Pro simulator running iOS 18.6, and an iPhone 17 simulator running iOS 26.5. The app builds with its iOS 17 deployment target, and that simulator build runs on both OS versions. No browser verification or real AI calls were used.

The shared 38-point radius matches the native iOS 26 reference. On the iPhone 17 medium-detent screenshots, 176 sampled rows of the upper-left corner contour had zero pixel difference between the native radius and an explicit 38-point radius at 3x scale. This is a measured phone reference. Other devices and presentation sizes may differ.

The broader verification ran 66 tests per OS. The sheet, date-filter, accent contrast, toolbar blur, and legacy appearance checks passed. OS-specific checks skipped one test on iOS 26 and three on iOS 18. Both runs failed the existing `DesignSystemArchitectureTests.testProductionFilesKeepOnePrimaryTopLevelEntity` check on the same nine files. Comparing against the workspace snapshot taken before this migration confirmed all nine violations predated these changes. The new shared-sheet ownership check passed.

Screenshots were inspected for light/dark medium sheets, scrolling, focused input, nested sheets, and camera controls. The camera close, capture, and attachment controls remain clear of the sheet edges and bottom safe area. Keyboard assertions compare the list's visible bottom with UIKit's keyboard layout guide; window snapshots do not include the separate system keyboard window. Hardware camera behavior and a full native-keyboard typing session were not verified. No iOS 17 runtime or iPad/landscape verification was performed.

The test results and attached screenshots are in `/tmp/finance-appsheet-18.xcresult` and `/tmp/finance-appsheet-26.xcresult`. Native radius comparison is in `/tmp/finance-appsheet-final26.xcresult`. Final detent, navigation, keyboard, and nested-dismissal results are in `/tmp/finance-appsheet-navigation18.xcresult` and `/tmp/finance-appsheet-navigation26.xcresult`. The final checks passed on both OS versions. They compare detents as a set because SwiftUI does not guarantee their returned order.

## Shared spacing coverage

The spacing correction is the default `.navigation` layout of `AppSheet` for both Boolean and item presentations. A screen cannot miss it by omitting a separate modifier. `AppSheetLayout.content` is an explicit exception for the two views that own their top spacing without a navigation bar. The architecture suite checks that direct sheet styling has one owner, records both content exceptions, and rejects the retired per-screen spacing modifier. Scan drafts and the discard-changes review also use the shared older-iOS styling for their dismissal buttons.

`AppSheetTests.testProductionNavigationSheetLayouts` renders quick-entry, scan, document and CSV review, scan drafts, account management and editing, rate help, recipient management and editing, category editing and creation, deletion confirmation, CSV help, and metric detail in light and dark mode. It verifies that each navigation container fills the sheet and that the top safe-area adjustment is applied once. Rendered pixel comparisons on both sides of the inset boundary detect contrasting header strips. The quick-entry review also checks the 44-point Close control's top inset on older iOS. The transaction-toolbar test measures its actual close control; the existing lifecycle suite exercises both bindings, keyboard avoidance, navigation and nested dismissal. Camera and date-filter checks cover the content-layout exceptions.

The earlier spacing-only verification passed on iOS 18.6 and iOS 26.5: 29 tests per OS, zero failures, with the native-iOS-26 reference test skipped on iOS 18. The final results are `/tmp/finance-sheets-final18.xcresult` and `/tmp/finance-sheets-final26.xcresult`. Earlier iOS 18 test hosts received signal kill; rerunning in an isolated simulator passed, and that temporary simulator was removed afterward. That pass checked 15 production layout fixtures in both appearances, along with transaction entry, nested navigation, and camera captures, but missed the contrasting strip above dark navigation backgrounds. The new pixel assertions reproduced that defect in all 15 dark fixtures before the safe-area fix. The inline discard-changes route was source-audited and its Cancel button now uses the same legacy toolbar control as other sheets. Pressed and loading states were not retested in this spacing pass.

## Header background regression fix

The outer 10-point padding was exposing the base presentation background above elevated navigation content. `AppSheet` now adjusts the presented hosting controller's `additionalSafeAreaInsets.top` on iOS 17 through 25. The navigation container fills the sheet bounds, and its existing background extends into that safe area. The adapter records the original top inset and restores it when removed. It leaves other safe-area edges intact, scopes itself to the current presentation, and does not install on iOS 26 or on `.content` sheets. No feature-specific background overrides were added.

The regression assertions compare RGB pixels at 3 and 13 points below the sheet edge, away from the grabber and controls. Before the fix, they detected the black strip in every dark production layout fixture. After the fix, these checks pass alongside the existing 16-point toolbar-top measurements. Additional checks cover nested header continuity, parent spacing after nested dismissal, and removing and reinstalling the navigation inset without accumulating space.

Final verification on 2026-09-21 passed 30 targeted tests on each OS, with zero failures. The native iOS 26 reference test was skipped on iOS 18. Results and screenshots are in `/tmp/finance-seam-final18.xcresult` and `/tmp/finance-seam-final26.xcresult`. The 15 production sheet fixtures, transaction editor, scrolling, test keyboard avoidance, nested sheets, and camera safe areas were checked in both appearances. The date-filter rendering tests and shared sheet architecture checks also passed. Light/dark screenshots were visually inspected for header seams and rounded edges. A before/after scan-review header comparison is saved at `/tmp/finance-sheet-header-before-after.png`.

The camera tests use the simulator's unavailable-camera state. Live capture and a full native-keyboard typing session still need device verification. System-owned presentation effects and the other verification limits listed above remain unchanged.
