import Foundation
import SwiftUI

@MainActor
@Observable
final class FolderLibraryBootstrapModel {
    enum State {
        case loading
        case iCloudUnavailable(message: String)
        case libraryInitializing
        case ready(FolderReadyState)
    }

    struct FolderReadyState {
        let syncSnapshot: FolderSyncSnapshot
        let libraryLocationDescription: String
        let runtime: FolderRuntimeConfiguration
        let launchMessage: String?
    }

    private(set) var state: State = .loading
    private var hasStarted = false

    init() {}

    init(previewState: State) {
        self.state = previewState
        self.hasStarted = true
    }

    func start(force: Bool = false) async {
        if hasStarted && !force {
            return
        }

        hasStarted = true
        state = .loading

        let runtime: FolderRuntimeConfiguration
        do {
            runtime = try Self.resolveRuntime()
        } catch {
            state = .iCloudUnavailable(
                message: """
                Folder could not initialize a usable library.
                \(error.localizedDescription)
                """
            )
            return
        }

        state = .libraryInitializing

        do {
            let fileStore = runtime.makeFileStore()
            let repository = try runtime.makeRepository()
            let importer = FolderSharedInboxImporter(
                store: runtime.makeInboxStore(),
                itemRepository: repository,
                attachmentRepository: repository,
                linkInfoRepository: repository,
                manifestStore: JSONFolderManifestStore(fileStore: fileStore),
                fileStore: fileStore
            )
            _ = try await importer.processPendingRequests()
            let syncSnapshot = try await FetchFolderSyncSnapshotUseCase(itemRepository: repository).execute()
            _ = try fileStore.rootDirectoryURL()

            state = .ready(
                .init(
                    syncSnapshot: syncSnapshot,
                    libraryLocationDescription: runtime.libraryLocationDescription,
                    runtime: runtime,
                    launchMessage: runtime.launchMessage
                )
            )
        } catch {
            state = .iCloudUnavailable(
                message: """
                Folder could not initialize the iCloud-backed library.
                \(error.localizedDescription)
                """
            )
        }
    }

    private static func resolveRuntime() throws -> FolderRuntimeConfiguration {
        do {
            return try .liveCloud()
        } catch {
#if DEBUG
            return try .localDevelopmentFallback()
#else
            throw error
#endif
        }
    }
}
