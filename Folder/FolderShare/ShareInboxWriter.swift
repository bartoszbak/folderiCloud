import Foundation

enum ShareInboxPayloadKind: String, Codable, CaseIterable, Sendable {
    case image
    case file
    case url
    case text
}

struct ShareInboxPayloadManifest: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let kind: ShareInboxPayloadKind
    let relativePath: String?
    let stringValue: String?
    let suggestedFilename: String?
    let uti: String?
    let mimeType: String?

    init(
        id: UUID = UUID(),
        kind: ShareInboxPayloadKind,
        relativePath: String? = nil,
        stringValue: String? = nil,
        suggestedFilename: String? = nil,
        uti: String? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.stringValue = stringValue
        self.suggestedFilename = suggestedFilename
        self.uti = uti
        self.mimeType = mimeType
    }
}

struct ShareInboxRequestManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let requestID: UUID
    let createdAt: Date
    var payloads: [ShareInboxPayloadManifest]
    var completedPayloadIDs: [UUID]
    var lastErrorDescription: String?

    init(
        schemaVersion: Int = ShareInboxRequestManifest.currentSchemaVersion,
        requestID: UUID = UUID(),
        createdAt: Date = .now,
        payloads: [ShareInboxPayloadManifest],
        completedPayloadIDs: [UUID] = [],
        lastErrorDescription: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.payloads = payloads
        self.completedPayloadIDs = completedPayloadIDs
        self.lastErrorDescription = lastErrorDescription
    }
}

enum SharedImportPayload: Sendable {
    case image(data: Data, filename: String, uti: String, mimeType: String)
    case url(String)
    case text(String)
    case file(sourceURL: URL, filename: String, uti: String, mimeType: String)
}

enum ShareInboxWriterError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The shared Folder app group is unavailable."
        }
    }
}

final class ShareInboxWriter: @unchecked Sendable {
    private let appGroupIdentifier = "group.com.bartbak.fastapp.folder"
    nonisolated(unsafe) private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func writeRequest(_ payloads: [SharedImportPayload]) throws {
        guard let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ShareInboxWriterError.appGroupUnavailable
        }

        let inboxURL = appGroupURL.appendingPathComponent("Inbox", isDirectory: true)
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let requestID = UUID()
        let requestURL = inboxURL.appendingPathComponent(requestID.uuidString, isDirectory: true)
        let payloadsDirectory = requestURL.appendingPathComponent("payloads", isDirectory: true)
        try fileManager.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)

        var manifests: [ShareInboxPayloadManifest] = []
        for payload in payloads {
            switch payload {
            case let .image(data, filename, uti, mimeType):
                let relativePath = try writeDataPayload(
                    data,
                    suggestedFilename: filename,
                    into: payloadsDirectory
                )
                manifests.append(
                    ShareInboxPayloadManifest(
                        kind: .image,
                        relativePath: relativePath,
                        suggestedFilename: filename,
                        uti: uti,
                        mimeType: mimeType
                    )
                )

            case let .file(sourceURL, filename, uti, mimeType):
                let relativePath = try copyFilePayload(
                    sourceURL,
                    suggestedFilename: filename,
                    into: payloadsDirectory
                )
                manifests.append(
                    ShareInboxPayloadManifest(
                        kind: .file,
                        relativePath: relativePath,
                        suggestedFilename: filename,
                        uti: uti,
                        mimeType: mimeType
                    )
                )

            case let .url(stringValue):
                manifests.append(
                    ShareInboxPayloadManifest(
                        kind: .url,
                        stringValue: stringValue
                    )
                )

            case let .text(stringValue):
                manifests.append(
                    ShareInboxPayloadManifest(
                        kind: .text,
                        stringValue: stringValue
                    )
                )
            }
        }

        let manifest = ShareInboxRequestManifest(requestID: requestID, payloads: manifests)
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: requestURL.appendingPathComponent("request.json"), options: .atomic)
    }

    private func writeDataPayload(
        _ data: Data,
        suggestedFilename: String,
        into payloadsDirectory: URL
    ) throws -> String {
        let filename = sanitizedFilename(suggestedFilename)
        let destinationURL = payloadsDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)", isDirectory: false)
        try data.write(to: destinationURL, options: .atomic)
        return "payloads/\(destinationURL.lastPathComponent)"
    }

    private func copyFilePayload(
        _ sourceURL: URL,
        suggestedFilename: String,
        into payloadsDirectory: URL
    ) throws -> String {
        let filename = sanitizedFilename(suggestedFilename)
        let destinationURL = payloadsDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)", isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return "payloads/\(destinationURL.lastPathComponent)"
    }

    private func sanitizedFilename(_ suggestedFilename: String) -> String {
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID().uuidString }
        return trimmed.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
