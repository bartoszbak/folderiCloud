import Foundation
import UIKit

@MainActor
@Observable
final class LinkComposerViewModel {
    private let runtime: FolderRuntimeConfiguration

    var urlString = ""
    var title = ""
    var descriptionText = ""
    var isSubmitting = false
    var errorMessage: String?

    let metadataFetcher: LinkMetadataFetcher

    init(runtime: FolderRuntimeConfiguration, metadataFetcher: LinkMetadataFetcher? = nil) {
        self.runtime = runtime
        self.metadataFetcher = metadataFetcher ?? LinkMetadataFetcher()
    }

    func handleURLChange() {
        title = ""
        descriptionText = ""
        errorMessage = nil
        metadataFetcher.schedule(urlString: normalizedURLString)
    }

    func applyFetchedTitle(_ fetchedTitle: String?) {
        title = fetchedTitle ?? ""
    }

    func applyFetchedDescription(_ fetchedDescription: String?) {
        descriptionText = fetchedDescription ?? ""
    }

    func submit() async -> Bool {
        let normalizedURLString = self.normalizedURLString
        guard let sourceURL = URL(string: normalizedURLString),
              let scheme = sourceURL.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            errorMessage = "Enter a valid link."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let repository = try runtime.makeRepository()
            let fileStore = runtime.makeFileStore()
            let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
            let resolvedTitle = resolvedTitle(for: sourceURL)
            let resolvedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            let linkInfo = LinkInfoDraft(
                sourceURL: sourceURL,
                pageTitle: resolvedTitle,
                summary: resolvedDescription.isEmpty ? nil : resolvedDescription
            )

            if let faviconImport = makeFaviconImport() {
                let useCase = CreateImportedFolderItemWithManifestUseCase(
                    itemRepository: repository,
                    attachmentRepository: repository,
                    linkInfoRepository: repository,
                    manifestStore: manifestStore,
                    fileStore: fileStore
                )
                _ = try await useCase.execute(
                    FolderItemDraft(
                        kind: .link,
                        title: resolvedTitle,
                        note: resolvedDescription.isEmpty ? nil : resolvedDescription,
                        linkInfo: linkInfo
                    ),
                    importedFiles: [faviconImport]
                )
            } else {
                let useCase = CreateFolderItemWithManifestUseCase(
                    itemRepository: repository,
                    attachmentRepository: repository,
                    linkInfoRepository: repository,
                    manifestStore: manifestStore
                )
                _ = try await useCase.execute(
                    FolderItemDraft(
                        kind: .link,
                        title: resolvedTitle,
                        note: resolvedDescription.isEmpty ? nil : resolvedDescription,
                        linkInfo: linkInfo
                    )
                )
            }

            reset()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        urlString = ""
        title = ""
        descriptionText = ""
        errorMessage = nil
        isSubmitting = false
        metadataFetcher.clear()
    }

    private var normalizedURLString: String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private func resolvedTitle(for url: URL) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if let fetchedTitle = metadataFetcher.fetchedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fetchedTitle.isEmpty {
            return fetchedTitle
        }

        return url.host() ?? url.absoluteString
    }

    private func makeFaviconImport() -> ImportedFolderFileDraft? {
        guard let favicon = metadataFetcher.favicon else { return nil }

        if let pngData = favicon.pngData() {
            return ImportedFolderFileDraft(
                role: .favicon,
                preferredFilename: "favicon.png",
                payload: .data(pngData),
                uti: "public.png",
                mimeType: "image/png"
            )
        }

        guard let jpegData = favicon.jpegData(compressionQuality: 0.92) else {
            return nil
        }

        return ImportedFolderFileDraft(
            role: .favicon,
            preferredFilename: "favicon.jpg",
            payload: .data(jpegData),
            uti: "public.jpeg",
            mimeType: "image/jpeg"
        )
    }
}
