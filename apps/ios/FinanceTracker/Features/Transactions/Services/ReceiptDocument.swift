import Foundation
import UniformTypeIdentifiers

struct ReceiptDocument: Encodable, Sendable {
    static let maximumBytes = 10 * 1024 * 1024
    static let supportedTypes: [UTType] = [
        .pdf, .commaSeparatedText, .tabSeparatedText,
        UTType(filenameExtension: "xls"), UTType(filenameExtension: "xlsx"),
    ].compactMap { $0 }

    let filename: String
    let mediaType: String
    let data: Data

    init(data: Data, filename: String) throws {
        let types = [
            "pdf": "application/pdf", "csv": "text/csv", "tsv": "text/tsv",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ]
        guard filename.count <= 255,
              filename.rangeOfCharacter(from: .controlCharacters) == nil,
              !filename.contains("/"), !filename.contains("\\"),
              let mediaType = types[(filename as NSString).pathExtension.lowercased()] else {
            throw LocalDataError(message: "Choose a PDF, CSV, TSV, XLS, or XLSX file.")
        }
        guard !data.isEmpty else { throw LocalDataError(message: "This document is empty. Choose another file.") }
        guard data.count <= Self.maximumBytes else {
            throw LocalDataError(message: "Choose a file smaller than 10 MB.")
        }
        self.filename = filename
        self.mediaType = mediaType
        self.data = data
    }

    /// Coordinate cloud-provider access and read a bounded copy while the security scope is open.
    static func load(from url: URL) throws -> ReceiptDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var result: Result<ReceiptDocument, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readableURL in
            result = Result {
                let values = try readableURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else {
                    throw LocalDataError(message: "Choose a document file.")
                }
                if let size = values.fileSize, size > maximumBytes {
                    throw LocalDataError(message: "Choose a file smaller than 10 MB.")
                }
                let handle = try FileHandle(forReadingFrom: readableURL)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
                return try ReceiptDocument(data: data, filename: url.lastPathComponent)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw LocalDataError(message: "This document couldn't be loaded. Choose another file.") }
        return try result.get()
    }
}
