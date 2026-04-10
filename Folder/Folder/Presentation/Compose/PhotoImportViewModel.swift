import Foundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class PhotoImportViewModel {
    private let runtime: FolderRuntimeConfiguration

    var isImporting = false
    var errorMessage: String?

    init(runtime: FolderRuntimeConfiguration) {
        self.runtime = runtime
    }

    func importItems(_ items: [PhotosPickerItem]) async -> Int {
        guard !items.isEmpty else { return 0 }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let repository = try runtime.makeRepository()
            let fileStore = runtime.makeFileStore()
            let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
            let useCase = CreateImportedFolderItemWithManifestUseCase(
                itemRepository: repository,
                attachmentRepository: repository,
                linkInfoRepository: repository,
                manifestStore: manifestStore,
                fileStore: fileStore
            )

            var importedCount = 0
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let filename = Self.preferredFilename(for: item)
                let contentType = item.supportedContentTypes.first ?? UTType.image
                let stagedURL = try FolderComposeStaging.stageData(
                    data,
                    preferredFilename: filename
                )

                _ = try await useCase.execute(
                    FolderItemDraft(
                        kind: .photo,
                        title: Self.displayTitle(for: filename)
                    ),
                    importedFiles: [
                        ImportedFolderFileDraft(
                            role: .original,
                            preferredFilename: filename,
                            payload: .stagedFile(stagedURL, moveIntoPlace: true),
                            uti: contentType.identifier,
                            mimeType: contentType.preferredMIMEType ?? "image/jpeg"
                        )
                    ]
                )
                importedCount += 1
            }
            return importedCount
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private static func preferredFilename(for item: PhotosPickerItem) -> String {
        if let identifier = item.itemIdentifier {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = result.firstObject {
                let resources = PHAssetResource.assetResources(for: asset)
                if let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) {
                    return resource.originalFilename
                }
            }
        }
        return "photo.jpg"
    }

    private static func displayTitle(for filename: String) -> String {
        let title = (filename as NSString).deletingPathExtension
        return title.isEmpty ? "Photo" : title
    }
}
