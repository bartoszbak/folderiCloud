import Foundation

struct FolderCanonicalPathBuilder: Sendable {
    nonisolated init() {}

    nonisolated func relativeItemDirectory(for item: FolderItem) -> String {
        let components = [
            rootDirectoryName(for: item.kind),
            item.createdAt.formatted(.dateTime.year(.defaultDigits)),
            item.createdAt.formatted(.dateTime.month(.twoDigits)),
            item.id.uuidString.lowercased(),
        ]

        return NSString.path(withComponents: components)
    }

    nonisolated func relativeAttachmentPath(
        for item: FolderItem,
        role: AttachmentRole,
        preferredFilename: String
    ) -> String {
        let directory = relativeItemDirectory(for: item)
        let bucket = subdirectoryName(for: role)
        let filename = sanitizedFilename(preferredFilename, fallback: fallbackFilename(for: role))

        return NSString.path(withComponents: [directory, bucket, filename])
    }

    nonisolated func rootDirectoryName(for kind: FolderItemKind) -> String {
        switch kind {
        case .photo:
            "Photos"
        case .thought:
            "Thoughts"
        case .link:
            "Links"
        case .file:
            "Files"
        }
    }

    private nonisolated func subdirectoryName(for role: AttachmentRole) -> String {
        switch role {
        case .original:
            "originals"
        case .preview, .favicon, .poster:
            "previews"
        case .sidecar:
            "sidecars"
        }
    }

    private nonisolated func fallbackFilename(for role: AttachmentRole) -> String {
        switch role {
        case .original:
            "original.bin"
        case .preview:
            "preview.bin"
        case .favicon:
            "favicon.bin"
        case .poster:
            "poster.bin"
        case .sidecar:
            "sidecar.bin"
        }
    }

    private nonisolated func sanitizedFilename(_ filename: String, fallback: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? fallback : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\\n\r\t")
        let parts = candidate.components(separatedBy: invalid).filter { !$0.isEmpty }
        return parts.isEmpty ? fallback : parts.joined(separator: "-")
    }
}
