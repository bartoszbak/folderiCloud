import Foundation

struct FolderRuntimeConfiguration: Sendable {
    let localStoreMode: FolderLocalStoreMode
    let fileStoreConfiguration: FolderFileStoreConfiguration
    let libraryLocationDescription: String
    let storageDescription: String
    let launchMessage: String?

    func makeRepository() throws -> SwiftDataFolderRepository {
        try FolderLocalStore.makeRepository(mode: localStoreMode)
    }

    func makeFileStore() -> FolderUbiquityFileStore {
        FolderUbiquityFileStore(configuration: fileStoreConfiguration)
    }

    func makeManifestStore() -> JSONFolderManifestStore {
        JSONFolderManifestStore(fileStore: makeFileStore())
    }

    func makeInboxStore() -> FolderSharedInboxStore {
        FolderSharedInboxStore()
    }

    static func liveCloud() throws -> FolderRuntimeConfiguration {
        let fileStore = FolderUbiquityFileStore()
        let rootURL = try fileStore.rootDirectoryURL()

        return FolderRuntimeConfiguration(
            localStoreMode: .liveCloudSync,
            fileStoreConfiguration: FolderFileStoreConfiguration(),
            libraryLocationDescription: rootURL.lastPathComponent,
            storageDescription: "your iCloud-backed library",
            launchMessage: nil
        )
    }

    static func localDevelopmentFallback(fileManager: FileManager = .default) throws -> FolderRuntimeConfiguration {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let libraryURL = applicationSupport
            .appendingPathComponent("Folder", isDirectory: true)
            .appendingPathComponent("LocalLibrary", isDirectory: true)

        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        return FolderRuntimeConfiguration(
            localStoreMode: .localOnly,
            fileStoreConfiguration: FolderFileStoreConfiguration(rootLocation: .fixed(libraryURL)),
            libraryLocationDescription: "On-Device Library",
            storageDescription: "your on-device development library",
            launchMessage: "Running in local development mode because iCloud is unavailable for this build."
        )
    }
}
