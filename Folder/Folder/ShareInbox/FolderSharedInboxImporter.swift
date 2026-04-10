import Foundation

struct FolderSharedInboxImportSummary: Sendable {
    var processedRequestCount = 0
    var importedItemCount = 0
    var failedRequestCount = 0

    var hasChanges: Bool { importedItemCount > 0 || processedRequestCount > 0 }
}

struct FolderSharedInboxImporter: Sendable {
    private let store: FolderSharedInboxStore
    private let itemRepository: any FolderItemRepository
    private let attachmentRepository: any AttachmentRepository
    private let linkInfoRepository: any LinkInfoRepository
    private let manifestStore: any FolderManifestStore
    private let fileStore: any FolderFileStore

    init(
        store: FolderSharedInboxStore,
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository,
        manifestStore: any FolderManifestStore,
        fileStore: any FolderFileStore
    ) {
        self.store = store
        self.itemRepository = itemRepository
        self.attachmentRepository = attachmentRepository
        self.linkInfoRepository = linkInfoRepository
        self.manifestStore = manifestStore
        self.fileStore = fileStore
    }

    func processPendingRequests() async throws -> FolderSharedInboxImportSummary {
        let requests = try store.scanRequests()
        guard !requests.isEmpty else { return FolderSharedInboxImportSummary() }

        let importedFileUseCase = CreateImportedFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore,
            fileStore: fileStore
        )
        let createUseCase = CreateFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore
        )

        var summary = FolderSharedInboxImportSummary()

        for request in requests {
            var manifest = request.manifest
            let completedPayloadIDs = Set(manifest.completedPayloadIDs)
            var requestFailed = false

            for payload in manifest.payloads where !completedPayloadIDs.contains(payload.id) {
                do {
                    try await importPayload(
                        payload,
                        from: request,
                        importedFileUseCase: importedFileUseCase,
                        createUseCase: createUseCase
                    )
                    manifest.completedPayloadIDs.append(payload.id)
                    manifest.lastErrorDescription = nil
                    try store.writeManifest(manifest, to: request.manifestURL)
                    summary.importedItemCount += 1
                } catch {
                    manifest.lastErrorDescription = error.localizedDescription
                    try? store.writeManifest(manifest, to: request.manifestURL)
                    summary.failedRequestCount += 1
                    requestFailed = true
                    break
                }
            }

            if !requestFailed && Set(manifest.completedPayloadIDs) == Set(manifest.payloads.map(\.id)) {
                try store.removeRequestDirectory(request)
                summary.processedRequestCount += 1
            }
        }

        return summary
    }

    private func importPayload(
        _ payload: FolderSharedInboxPayloadManifest,
        from request: FolderSharedInboxQueuedRequest,
        importedFileUseCase: CreateImportedFolderItemWithManifestUseCase,
        createUseCase: CreateFolderItemWithManifestUseCase
    ) async throws {
        switch payload.kind {
        case .text:
            guard let text = payload.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }

            let title = Self.derivedThoughtTitle(from: text)
            let note = title == text ? nil : text
            _ = try await createUseCase.execute(
                FolderItemDraft(
                    kind: .thought,
                    title: title,
                    note: note
                )
            )

        case .url:
            guard let stringValue = payload.stringValue,
                  let sourceURL = URL(string: stringValue),
                  let scheme = sourceURL.scheme,
                  ["http", "https"].contains(scheme.lowercased()) else {
                throw URLError(.badURL)
            }

            _ = try await createUseCase.execute(
                FolderItemDraft(
                    kind: .link,
                    title: sourceURL.host() ?? stringValue,
                    linkInfo: LinkInfoDraft(sourceURL: sourceURL)
                )
            )

        case .image, .file:
            guard let relativePath = payload.relativePath else {
                throw FolderSharedInboxStoreError.missingPayloadURL("nil")
            }
            let payloadURL = try store.payloadURL(for: relativePath, in: request)
            let filename = payload.suggestedFilename ?? payloadURL.lastPathComponent
            let kind: FolderItemKind = payload.kind == .image ? .photo : .file

            _ = try await importedFileUseCase.execute(
                FolderItemDraft(
                    kind: kind,
                    title: Self.displayTitle(for: filename, fallback: kind == .photo ? "Photo" : "File")
                ),
                importedFiles: [
                    ImportedFolderFileDraft(
                        role: .original,
                        preferredFilename: filename,
                        payload: .stagedFile(payloadURL, moveIntoPlace: true),
                        uti: payload.uti ?? (payload.kind == .image ? "public.image" : "public.data"),
                        mimeType: payload.mimeType ?? (payload.kind == .image ? "image/jpeg" : "application/octet-stream")
                    )
                ]
            )
        }
    }

    private static func derivedThoughtTitle(from body: String) -> String {
        let title = body
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? body

        if title.count <= 80 {
            return title
        }

        let endIndex = title.index(title.startIndex, offsetBy: 80)
        return String(title[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayTitle(for filename: String, fallback: String) -> String {
        let title = (filename as NSString).deletingPathExtension
        return title.isEmpty ? fallback : title
    }
}
