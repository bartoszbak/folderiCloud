import Foundation
import SwiftData

enum FolderLocalStore {
    static let schema = Schema([
        FolderItemEntity.self,
        AttachmentEntity.self,
        LinkInfoEntity.self,
    ])

    static func makeConfiguration(
        mode: FolderLocalStoreMode = .liveCloudSync,
        isStoredInMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(
                "FolderLocal",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }

        if let storeURL {
            let parentURL = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
            return ModelConfiguration(
                "FolderLocal",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: mode.cloudKitDatabase
            )
        }

        return ModelConfiguration(
            "FolderLocal",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: mode.groupContainer,
            cloudKitDatabase: mode.cloudKitDatabase
        )
    }

    static func makeContainer(
        mode: FolderLocalStoreMode = .liveCloudSync,
        isStoredInMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        let configuration = try makeConfiguration(
            mode: mode,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            storeURL: storeURL
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func defaultStoreURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let folderDirectory = applicationSupport
            .appendingPathComponent("Folder", isDirectory: true)
            .appendingPathComponent("Database", isDirectory: true)

        try fileManager.createDirectory(at: folderDirectory, withIntermediateDirectories: true)
        return folderDirectory.appendingPathComponent("Folder.sqlite", isDirectory: false)
    }

    static func makeRepository(
        mode: FolderLocalStoreMode = .liveCloudSync,
        isStoredInMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws -> SwiftDataFolderRepository {
        let resolvedURL: URL?
        if isStoredInMemoryOnly {
            resolvedURL = nil
        } else if let storeURL {
            resolvedURL = storeURL
        } else if mode == .localOnly {
            resolvedURL = try defaultStoreURL()
        } else {
            resolvedURL = nil
        }

        let container = try makeContainer(
            mode: mode,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            storeURL: resolvedURL
        )
        return SwiftDataFolderRepository(container: container)
    }
}
