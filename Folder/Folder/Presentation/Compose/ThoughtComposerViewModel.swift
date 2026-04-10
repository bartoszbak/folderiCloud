import Foundation

@MainActor
@Observable
final class ThoughtComposerViewModel {
    private let runtime: FolderRuntimeConfiguration

    var text = ""
    var isSubmitting = false
    var errorMessage: String?

    init(runtime: FolderRuntimeConfiguration) {
        self.runtime = runtime
    }

    func submit() async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            errorMessage = "Enter a thought before saving."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let repository = try runtime.makeRepository()
            let fileStore = runtime.makeFileStore()
            let useCase = CreateFolderItemWithManifestUseCase(
                itemRepository: repository,
                attachmentRepository: repository,
                linkInfoRepository: repository,
                manifestStore: JSONFolderManifestStore(fileStore: fileStore)
            )

            let title = Self.derivedTitle(from: body)
            let note = title == body ? nil : body
            _ = try await useCase.execute(
                FolderItemDraft(
                    kind: .thought,
                    title: title,
                    note: note
                )
            )
            reset()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        text = ""
        errorMessage = nil
        isSubmitting = false
    }

    private static func derivedTitle(from body: String) -> String {
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
}
