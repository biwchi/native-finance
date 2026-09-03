import Foundation
import XCTest

final class DesignSystemArchitectureTests: XCTestCase {
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
