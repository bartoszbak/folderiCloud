import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class FileImportViewModel {
    private let runtime: FolderRuntimeConfiguration

    var isImporting = false
    var errorMessage: String?

    init(runtime: FolderRuntimeConfiguration) {
        self.runtime = runtime
    }

    func importFile(from result: Result<URL, Error>) async -> Bool {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let sourceURL = try result.get()
            guard sourceURL.startAccessingSecurityScopedResource() else {
                throw FolderFileStoreError.cannotAccessSourceFile(sourceURL)
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            let filename = sourceURL.lastPathComponent
            let stagedURL = try FolderComposeStaging.stageCopy(
                of: sourceURL,
                preferredFilename: filename
            )

            let contentType = UTType(filenameExtension: sourceURL.pathExtension) ?? .data
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

            _ = try await useCase.execute(
                FolderItemDraft(
                    kind: .file,
                    title: Self.displayTitle(for: filename)
                ),
                importedFiles: [
                    ImportedFolderFileDraft(
                        role: .original,
                        preferredFilename: filename,
                        payload: .stagedFile(stagedURL, moveIntoPlace: true),
                        uti: contentType.identifier,
                        mimeType: contentType.preferredMIMEType ?? "application/octet-stream"
                    )
                ]
            )

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private static func displayTitle(for filename: String) -> String {
        let title = (filename as NSString).deletingPathExtension
        return title.isEmpty ? filename : title
    }
}
