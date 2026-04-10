import Foundation

enum FolderSharedInboxStoreError: LocalizedError {
    case appGroupUnavailable(String)
    case unsupportedSchemaVersion(Int)
    case missingPayloadURL(String)

    var errorDescription: String? {
        switch self {
        case let .appGroupUnavailable(identifier):
            "The shared app group container is unavailable: \(identifier)"
        case let .unsupportedSchemaVersion(version):
            "Unsupported shared inbox schema version: \(version)"
        case let .missingPayloadURL(path):
            "The shared inbox payload is missing: \(path)"
        }
    }
}

final class FolderSharedInboxStore: @unchecked Sendable {
    private let appGroupIdentifier: String?
    private let fixedBaseURL: URL?
    nonisolated(unsafe) private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init(
        appGroupIdentifier: String = FolderAppGroup.identifier,
        fileManager: FileManager = .default
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fixedBaseURL = nil
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    nonisolated init(
        fixedBaseURL: URL,
        fileManager: FileManager = .default
    ) {
        self.appGroupIdentifier = nil
        self.fixedBaseURL = fixedBaseURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func inboxDirectoryURL() throws -> URL {
        let baseURL: URL
        if let fixedBaseURL {
            baseURL = fixedBaseURL
        } else if let appGroupIdentifier,
                  let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            baseURL = containerURL
        } else {
            throw FolderSharedInboxStoreError.appGroupUnavailable(appGroupIdentifier ?? "unknown")
        }

        let inboxURL = baseURL.appendingPathComponent("Inbox", isDirectory: true)
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        return inboxURL
    }

    func scanRequests() throws -> [FolderSharedInboxQueuedRequest] {
        let inboxURL = try inboxDirectoryURL()
        guard fileManager.fileExists(atPath: inboxURL.path) else {
            return []
        }

        let directoryContents = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var requests: [FolderSharedInboxQueuedRequest] = []
        for directoryURL in directoryContents {
            let manifestURL = directoryURL.appendingPathComponent("request.json", isDirectory: false)
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            let manifest = try readManifest(at: manifestURL)
            requests.append(
                FolderSharedInboxQueuedRequest(
                    directoryURL: directoryURL,
                    manifestURL: manifestURL,
                    manifest: manifest
                )
            )
        }

        return requests.sorted { $0.manifest.createdAt < $1.manifest.createdAt }
    }

    func payloadURL(for relativePath: String, in request: FolderSharedInboxQueuedRequest) throws -> URL {
        let payloadURL = request.directoryURL.appendingPathComponent(relativePath, isDirectory: false)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw FolderSharedInboxStoreError.missingPayloadURL(relativePath)
        }
        return payloadURL
    }

    func writeManifest(_ manifest: FolderSharedInboxRequestManifest, to manifestURL: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    func removeRequestDirectory(_ request: FolderSharedInboxQueuedRequest) throws {
        guard fileManager.fileExists(atPath: request.directoryURL.path) else { return }
        try fileManager.removeItem(at: request.directoryURL)
    }

    private func readManifest(at manifestURL: URL) throws -> FolderSharedInboxRequestManifest {
        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(FolderSharedInboxRequestManifest.self, from: data)
        guard manifest.schemaVersion == FolderSharedInboxRequestManifest.currentSchemaVersion else {
            throw FolderSharedInboxStoreError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        return manifest
    }
}
