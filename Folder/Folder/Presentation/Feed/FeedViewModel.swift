import Foundation
import SwiftUI

@MainActor
@Observable
final class FeedViewModel {
    struct ThoughtPreview: Identifiable, Hashable {
        let id: UUID
        let title: String
        let body: String
    }

    struct FeedStatus: Equatable {
        enum Kind: Equatable {
            case info
            case success
            case failure
        }

        let kind: Kind
        let message: String
    }

    private let runtime: FolderRuntimeConfiguration
    private let libraryLocationDescription: String
    private let fileStore: FolderUbiquityFileStore
    private var repository: SwiftDataFolderRepository?
    private var recordsByID: [UUID: FolderItemRecord] = [:]
    private var statusTask: Task<Void, Never>?

    var items: [FeedItemViewData] = []
    var isLoading = false
    var loadError: String?
    var activeFilter: FolderItemKind?
    var status: FeedStatus?
    var quickLookURL: URL?
    var safariURL: URL?
    var thoughtPreview: ThoughtPreview?

    init(runtime: FolderRuntimeConfiguration) {
        self.runtime = runtime
        self.libraryLocationDescription = runtime.libraryLocationDescription
        self.fileStore = runtime.makeFileStore()
        self.status = runtime.launchMessage.map { .init(kind: .info, message: $0) }
    }

    var filteredItems: [FeedItemViewData] {
        guard let activeFilter else { return items }
        return items.filter { $0.kind == activeFilter }
    }

    var navigationTitle: String {
        guard let activeFilter else { return "Folder" }
        switch activeFilter {
        case .photo:
            return "Folder / Photos"
        case .thought:
            return "Folder / Thoughts"
        case .link:
            return "Folder / Links"
        case .file:
            return "Folder / Files"
        }
    }

    var emptyDescription: String {
        "Saved items will appear from \(runtime.storageDescription) in \(libraryLocationDescription)."
    }

    func load(force: Bool = false) async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let repository = try repository ?? runtime.makeRepository()
            self.repository = repository

            let records = try await FetchFolderItemsUseCase(
                itemRepository: repository,
                attachmentRepository: repository,
                linkInfoRepository: repository
            ).execute()

            recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            items = try records.map(makeViewData(from:))
            loadError = nil
        } catch {
            if force || items.isEmpty {
                loadError = error.localizedDescription
            } else {
                showStatus(.init(kind: .failure, message: error.localizedDescription))
            }
        }
    }

    func processPendingShareImports() async {
        do {
            let repository = try repository ?? runtime.makeRepository()
            self.repository = repository

            let summary = try await FolderSharedInboxImporter(
                store: runtime.makeInboxStore(),
                itemRepository: repository,
                attachmentRepository: repository,
                linkInfoRepository: repository,
                manifestStore: JSONFolderManifestStore(fileStore: fileStore),
                fileStore: fileStore
            ).processPendingRequests()

            if summary.hasChanges {
                await load(force: true)
            }
        } catch {
            showStatus(.init(kind: .failure, message: error.localizedDescription))
        }
    }

    func handleTap(_ item: FeedItemViewData) async {
        do {
            switch item.previewAction {
            case .none:
                showStatus(.init(kind: .info, message: "No preview is available for this item yet."))
            case let .thought(title, body):
                thoughtPreview = .init(id: item.id, title: title, body: body)
            case let .link(url):
                safariURL = url
            case let .attachment(relativePath):
                let materialized = try fileStore.materializedFile(
                    for: relativePath,
                    downloadIfNeeded: true
                )
                switch materialized.availability {
                case .availableLocally:
                    quickLookURL = materialized.absoluteURL
                case .downloading:
                    showStatus(.init(kind: .info, message: "Downloading from iCloud. Open it again in a moment."))
                case .notDownloaded:
                    showStatus(.init(kind: .info, message: "Requested from iCloud. Open it again once the download starts."))
                case .missing:
                    showStatus(.init(kind: .failure, message: "The file is missing from the iCloud library."))
                }
            }
        } catch {
            showStatus(.init(kind: .failure, message: error.localizedDescription))
        }
    }

    func delete(itemID: UUID) async {
        guard let repository else {
            showStatus(.init(kind: .failure, message: "Library is not ready yet."))
            return
        }

        do {
            _ = try await DeleteFolderItemUseCase(itemRepository: repository).execute(itemID: itemID)
            showStatus(.init(kind: .success, message: "Item removed from the feed."))
            await load(force: true)
        } catch {
            showStatus(.init(kind: .failure, message: error.localizedDescription))
        }
    }

    func dismissPreviews() {
        safariURL = nil
        quickLookURL = nil
        thoughtPreview = nil
    }

    private func makeViewData(from record: FolderItemRecord) throws -> FeedItemViewData {
        let title = normalizedTitle(for: record)
        let subtitle = subtitle(for: record)
        let thumbnailState = try thumbnailState(for: record)
        let previewAction = FeedViewModel.previewAction(for: record)
        let syncBadge = try syncBadge(for: record, previewAction: previewAction)

        return FeedItemViewData(
            id: record.item.id,
            kind: record.item.kind,
            title: title,
            subtitle: subtitle,
            thumbnailState: thumbnailState,
            previewAction: previewAction,
            syncBadge: syncBadge
        )
    }

    private func normalizedTitle(for record: FolderItemRecord) -> String {
        if !record.item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return record.item.title
        }

        switch record.item.kind {
        case .thought:
            return "Untitled Thought"
        case .link:
            return record.linkInfo?.pageTitle ?? record.linkInfo?.displayHost ?? "Untitled Link"
        case .photo:
            return "Untitled Photo"
        case .file:
            return "Untitled File"
        }
    }

    private func subtitle(for record: FolderItemRecord) -> String {
        switch record.item.kind {
        case .thought:
            let note = (record.item.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? formattedDate(record.item.updatedAt) : note
        case .link:
            return record.linkInfo?.displayHost ?? formattedDate(record.item.updatedAt)
        case .photo, .file:
            if let filename = preferredPreviewAttachment(for: record)?.relativePath.split(separator: "/").last {
                return String(filename)
            }
            return formattedDate(record.item.updatedAt)
        }
    }

    private func thumbnailState(for record: FolderItemRecord) throws -> FeedThumbnailState {
        switch record.item.kind {
        case .thought:
            let initials = String(normalizedTitle(for: record).prefix(1)).uppercased()
            return .monogram(initials)
        case .link:
            if let path = record.linkInfo?.faviconPath,
               let materialized = try localMaterializedFile(for: path) {
                return .localImage(materialized.absoluteURL)
            }
            return .symbol("link")
        case .photo:
            if let path = preferredPreviewAttachment(for: record)?.relativePath,
               let materialized = try localMaterializedFile(for: path) {
                return .localImage(materialized.absoluteURL)
            }
            return .symbol("photo")
        case .file:
            if let attachment = record.attachments.first(where: { $0.role == .preview }),
               let materialized = try localMaterializedFile(for: attachment.relativePath) {
                return .localImage(materialized.absoluteURL)
            }
            return .symbol("doc")
        }
    }

    private func syncBadge(for record: FolderItemRecord, previewAction: FeedPreviewAction) throws -> FeedSyncBadge {
        switch record.item.syncState {
        case .localOnly, .synced:
            break
        case .syncing:
            return .syncing
        case .conflicted:
            return .conflicted
        case .pendingDelete:
            return .pendingDelete
        }

        if case let .attachment(relativePath) = previewAction {
            let materialized = try fileStore.materializedFile(for: relativePath, downloadIfNeeded: false)
            switch materialized.availability {
            case .availableLocally:
                return .synced
            case .downloading:
                return .downloading
            case .notDownloaded:
                return .cloudOnly
            case .missing:
                return .conflicted
            }
        }

        return .synced
    }

    private func localMaterializedFile(for relativePath: String) throws -> FolderMaterializedFile? {
        let materialized = try fileStore.materializedFile(for: relativePath, downloadIfNeeded: false)
        return materialized.availability == .availableLocally ? materialized : nil
    }

    private func preferredPreviewAttachment(for record: FolderItemRecord) -> Attachment? {
        if let preview = record.attachments.first(where: { $0.role == .preview }) {
            return preview
        }
        if let original = record.attachments.first(where: { $0.role == .original }) {
            return original
        }
        if let favicon = record.attachments.first(where: { $0.role == .favicon }) {
            return favicon
        }
        return record.attachments.first
    }

    private static func previewAction(for record: FolderItemRecord) -> FeedPreviewAction {
        switch record.item.kind {
        case .thought:
            let body = (record.item.note ?? record.item.title).trimmingCharacters(in: .whitespacesAndNewlines)
            return .thought(title: record.item.title, body: body)
        case .link:
            if let url = record.linkInfo?.sourceURL {
                return .link(url)
            }
            return .none
        case .photo, .file:
            if let preview = record.attachments.first(where: { $0.role == .original }) ??
                record.attachments.first(where: { $0.role == .preview }) {
                return .attachment(relativePath: preview.relativePath)
            }
            return .none
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func showStatus(_ status: FeedStatus) {
        self.status = status
        statusTask?.cancel()
        statusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                self.status = nil
            }
        }
    }
}
