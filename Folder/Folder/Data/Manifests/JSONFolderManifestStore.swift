import Foundation

final class JSONFolderManifestStore: FolderManifestStore, @unchecked Sendable {
    private let fileStore: any FolderFileStore
    nonisolated(unsafe) private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init(
        fileStore: any FolderFileStore,
        fileManager: FileManager = .default
    ) {
        self.fileStore = fileStore
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func manifestURL(for item: FolderItem) throws -> URL {
        try fileStore.itemDirectoryURL(for: item)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    func writeManifest(for record: FolderItemRecord) throws -> FolderItemManifest {
        let manifest = FolderItemManifest(record: record)
        let manifestURL = try manifestURL(for: record.item)
        let data = try encoder.encode(manifest)

        try coordinateWrite(to: manifestURL) { url in
            try data.write(to: url, options: .atomic)
        }

        return manifest
    }

    func readManifest(for item: FolderItem) throws -> FolderItemManifest? {
        let manifestURL = try manifestURL(for: item)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        return try readManifest(at: manifestURL)
    }

    func scanManifests() throws -> [FolderItemManifest] {
        let rootURL = try fileStore.rootDirectoryURL()
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var manifests: [FolderItemManifest] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "manifest.json" {
                manifests.append(try readManifest(at: url))
            }
        }

        return manifests.sorted { $0.item.sortDate > $1.item.sortDate }
    }

    private func readManifest(at url: URL) throws -> FolderItemManifest {
        let data = try coordinateRead(at: url) { try Data(contentsOf: $0) }

        do {
            let manifest = try decoder.decode(FolderItemManifest.self, from: data)
            guard manifest.schemaVersion == FolderItemManifest.currentSchemaVersion else {
                throw FolderManifestStoreError.unsupportedSchemaVersion(manifest.schemaVersion)
            }
            return manifest
        } catch let error as FolderManifestStoreError {
            throw error
        } catch {
            throw FolderManifestStoreError.invalidManifestData(url)
        }
    }

    private func coordinateRead<T>(at url: URL, block: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: T?
        var thrownError: Error?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                result = try block(coordinatedURL)
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
        if let coordinationError {
            throw FolderFileStoreError.coordinatedWriteFailed(coordinationError.localizedDescription)
        }

        guard let result else {
            throw FolderManifestStoreError.invalidManifestData(url)
        }

        return result
    }

    private func coordinateWrite(to url: URL, block: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrownError: Error?

        let options: NSFileCoordinator.WritingOptions = fileManager.fileExists(atPath: url.path) ? .forReplacing : []
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do {
                try block(coordinatedURL)
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
        if let coordinationError {
            throw FolderFileStoreError.coordinatedWriteFailed(coordinationError.localizedDescription)
        }
    }
}
