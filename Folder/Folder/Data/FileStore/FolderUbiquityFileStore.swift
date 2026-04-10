import Foundation

final class FolderUbiquityFileStore: FolderFileStore, @unchecked Sendable {
    private let configuration: FolderFileStoreConfiguration
    private let pathBuilder: FolderCanonicalPathBuilder
    nonisolated(unsafe) private let fileManager: FileManager

    nonisolated init(
        configuration: FolderFileStoreConfiguration = FolderFileStoreConfiguration(),
        pathBuilder: FolderCanonicalPathBuilder = FolderCanonicalPathBuilder(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.pathBuilder = pathBuilder
        self.fileManager = fileManager
    }

    func isAvailable() -> Bool {
        (try? resolveRootURL()) != nil
    }

    func rootDirectoryURL() throws -> URL {
        try resolveRootURL()
    }

    func itemDirectoryURL(for item: FolderItem) throws -> URL {
        let rootURL = try resolveRootURL()
        let directoryURL = rootURL.appendingPathComponent(pathBuilder.relativeItemDirectory(for: item), isDirectory: true)

        try ensureDirectoryExists(at: directoryURL)
        return directoryURL
    }

    func commitFile(_ request: FolderFileCommitRequest) throws -> FolderStoredFile {
        let rootURL = try resolveRootURL()
        let relativePath = pathBuilder.relativeAttachmentPath(
            for: request.item,
            role: request.role,
            preferredFilename: request.preferredFilename
        )
        let destinationURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        let destinationDirectory = destinationURL.deletingLastPathComponent()

        try ensureDirectoryExists(at: destinationDirectory)

        switch request.payload {
        case let .data(data):
            try coordinateWrite(to: destinationURL, replaceExisting: true) { coordinatedDestination in
                try data.write(to: coordinatedDestination, options: .atomic)
            }

        case let .stagedFile(sourceURL, moveIntoPlace):
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw FolderFileStoreError.cannotAccessSourceFile(sourceURL)
            }

            try coordinateReadWrite(from: sourceURL, to: destinationURL, replaceExisting: true) { coordinatedSource, coordinatedDestination in
                if moveIntoPlace {
                    if fileManager.fileExists(atPath: coordinatedDestination.path) {
                        try fileManager.removeItem(at: coordinatedDestination)
                    }
                    try fileManager.moveItem(at: coordinatedSource, to: coordinatedDestination)
                } else {
                    if fileManager.fileExists(atPath: coordinatedDestination.path) {
                        try fileManager.removeItem(at: coordinatedDestination)
                    }
                    try fileManager.copyItem(at: coordinatedSource, to: coordinatedDestination)
                }
            }
        }

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return FolderStoredFile(
            role: request.role,
            relativePath: relativePath,
            absoluteURL: destinationURL,
            originalFilename: request.preferredFilename,
            byteSize: byteSize
        )
    }

    func materializedFile(for relativePath: String, downloadIfNeeded: Bool = false) throws -> FolderMaterializedFile {
        let rootURL = try resolveRootURL()
        let absoluteURL = try absoluteURL(forRelativePath: relativePath, rootURL: rootURL)
        let availability = try fileAvailability(at: absoluteURL, downloadIfNeeded: downloadIfNeeded)

        return FolderMaterializedFile(
            relativePath: relativePath,
            absoluteURL: absoluteURL,
            availability: availability
        )
    }

    func removeItemDirectory(for item: FolderItem) throws {
        let rootURL = try resolveRootURL()
        let directoryURL = rootURL.appendingPathComponent(pathBuilder.relativeItemDirectory(for: item), isDirectory: true)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw FolderFileStoreError.itemDirectoryMissing(item.id)
        }

        try coordinateWrite(to: directoryURL, replaceExisting: false) { coordinatedDirectory in
            try fileManager.removeItem(at: coordinatedDirectory)
        }
    }

    private func resolveRootURL() throws -> URL {
        switch configuration.rootLocation {
        case let .fixed(rootURL):
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL

        case let .ubiquityContainer(identifier):
            guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: identifier) else {
                throw FolderFileStoreError.ubiquityContainerUnavailable
            }

            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            return documentsURL
        }
    }

    private func absoluteURL(forRelativePath relativePath: String, rootURL: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw FolderFileStoreError.invalidRelativePath(relativePath)
        }

        return rootURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        try coordinateWrite(to: directoryURL, replaceExisting: false) { coordinatedDirectory in
            try fileManager.createDirectory(at: coordinatedDirectory, withIntermediateDirectories: true)
        }
    }

    private func fileAvailability(at url: URL, downloadIfNeeded: Bool) throws -> FolderFileAvailability {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingStatusKey,
        ])

        guard values.isUbiquitousItem == true else {
            return .availableLocally
        }

        if values.ubiquitousItemIsDownloading == true {
            return .downloading
        }

        if downloadIfNeeded {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            return .downloading
        }

        if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current ||
            values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.downloaded {
            return .availableLocally
        }

        if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.notDownloaded {
            return .notDownloaded
        }

        return .availableLocally
    }

    private func coordinateWrite(
        to destinationURL: URL,
        replaceExisting: Bool,
        block: (URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrownError: Error?

        let options: NSFileCoordinator.WritingOptions = replaceExisting ? .forReplacing : []
        coordinator.coordinate(writingItemAt: destinationURL, options: options, error: &coordinationError) { coordinatedDestination in
            do {
                try block(coordinatedDestination)
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

    private func coordinateReadWrite(
        from sourceURL: URL,
        to destinationURL: URL,
        replaceExisting: Bool,
        block: (URL, URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrownError: Error?

        let options: NSFileCoordinator.WritingOptions = replaceExisting ? .forReplacing : []
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            writingItemAt: destinationURL,
            options: options,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            do {
                try block(coordinatedSource, coordinatedDestination)
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
