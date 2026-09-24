import Foundation
import XCTest

final class DesignSystemArchitectureTests: XCTestCase {
    func testScreensUseSharedListAndSectionContainers() throws {
        let containers = try NSRegularExpression(pattern: #"\b(?:List|Form|Section)\s*(?:\(|\{)"#)
        let owners: Set<String> = [
            "DesignSystem/Components/AppList.swift",
            "DesignSystem/Components/AppSection.swift",
        ]
        let violations = try swiftFiles(in: sourceRoot).compactMap { file -> String? in
            let path = relativePath(for: file)
            guard !owners.contains(path) else { return nil }
            let source = try String(contentsOf: file, encoding: .utf8)
            return containers.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) == nil
                ? nil : path
        }
        XCTAssertEqual(violations, [], "Use AppList, AppForm, and AppSection so grouped layout stays consistent across iOS versions.")
    }

    func testSheetPresentationAndAppearanceHaveOneOwner() throws {
        let directPresentation = try NSRegularExpression(pattern: #"\b(?:sheet|presentationCornerRadius|presentationBackground)\s*\("#)
        let violations = try swiftFiles(in: sourceRoot).compactMap { file -> String? in
            let path = relativePath(for: file)
            guard path != "DesignSystem/Components/AppSheet.swift" else { return nil }
            let source = try String(contentsOf: file, encoding: .utf8)
            return directPresentation.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) == nil
                ? nil : path
        }
        XCTAssertEqual(violations, [], "Present app-owned sheets through appSheet; keep their appearance in AppSheet.")
    }

    func testOnlyContentSheetsOptOutOfNavigationSpacing() throws {
        let expected: Set<String> = [
            "App/Screens/MainView.swift",
            "Shared/Finance/Components/FinanceDatePickerButton.swift",
        ]
        let exceptions = try swiftFiles(in: sourceRoot).filter { file in
            try String(contentsOf: file, encoding: .utf8).contains("layout: .content")
        }.map { relativePath(for: $0) }
        XCTAssertEqual(Set(exceptions), expected,
                       "Navigation sheets use default spacing. Audit and document any new content-only exception.")
        for file in try swiftFiles(in: sourceRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            if expected.contains(relativePath(for: file)) {
                XCTAssertEqual(source.components(separatedBy: "layout: .content").count - 1, 1,
                               "Keep each content exception explicit and audited.")
            }
            XCTAssertFalse(source.contains("appSheetToolbarSpacing"), "Sheet spacing must not require a per-screen modifier.")
        }
    }

    func testNamedColorsAreOwnedByTheColorTokenFile() throws {
        let tokenFile = sourceRoot
            .appendingPathComponent("DesignSystem/Tokens/AppColor.swift")
            .standardizedFileURL
        let violations = try swiftFiles(in: sourceRoot).compactMap { file -> String? in
            guard file.standardizedFileURL != tokenFile else { return nil }
            let source = try String(contentsOf: file, encoding: .utf8)
            return source.contains("Color(\"") ? relativePath(for: file) : nil
        }

        XCTAssertEqual(
            violations,
            [],
            "Add named colors to AppColor and reference the semantic token from feature code."
        )
    }

    func testProductionFilesKeepOnePrimaryTopLevelEntity() throws {
        let declaration = try NSRegularExpression(
            pattern: #"^(?:private\s+)?(?:final\s+)?(?:struct|enum|class|actor|protocol)\s+"#,
            options: .anchorsMatchLines
        )
        let violations = try swiftFiles(in: sourceRoot).compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            let count = declaration.numberOfMatches(in: source, range: range)
            return count > 1 ? "\(relativePath(for: file)) (\(count))" : nil
        }

        XCTAssertEqual(
            violations,
            [],
            "Split unrelated top-level entities into dedicated Swift files."
        )
    }

    func testAccentPrimitivesRemainIndependentlyOwned() {
        let primitiveDirectory = sourceRoot.appendingPathComponent("DesignSystem/Primitives")
        for name in ["AccentSelectionButton", "PrimaryActionButton", "PrimaryIconButton"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: primitiveDirectory.appendingPathComponent("\(name).swift").path
                ),
                "Keep \(name) in its own primitive file."
            )
        }
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FinanceTracker")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys
        ) else {
            XCTFail("Could not enumerate \(directory.path)")
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: Set(resourceKeys))
            return values.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func relativePath(for file: URL) -> String {
        file.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
    }
}
