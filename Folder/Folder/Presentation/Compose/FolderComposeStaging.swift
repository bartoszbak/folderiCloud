import Foundation

enum FolderComposeStaging {
    static func stageData(
        _ data: Data,
        preferredFilename: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagedURL = try makeStagedFileURL(
            preferredFilename: preferredFilename,
            fileManager: fileManager
        )
        try data.write(to: stagedURL, options: .atomic)
        return stagedURL
    }

    static func stageCopy(
        of sourceURL: URL,
        preferredFilename: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagedURL = try makeStagedFileURL(
            preferredFilename: preferredFilename,
            fileManager: fileManager
        )
        try fileManager.copyItem(at: sourceURL, to: stagedURL)
        return stagedURL
    }

    static func sanitizedFilename(_ preferredFilename: String) -> String {
        let trimmed = preferredFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID().uuidString }

        let scalars = trimmed.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "/", ":", "\u{0000}":
                return "_"
            default:
                return Character(scalar)
            }
        }

        let filename = String(scalars)
        return filename.isEmpty ? UUID().uuidString : filename
    }

    private static func stagingDirectory(fileManager: FileManager) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("FolderComposeStaging", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func makeStagedFileURL(
        preferredFilename: String,
        fileManager: FileManager
    ) throws -> URL {
        let directory = try stagingDirectory(fileManager: fileManager)
        let sanitized = sanitizedFilename(preferredFilename)
        return directory.appendingPathComponent("\(UUID().uuidString)-\(sanitized)", isDirectory: false)
    }
}
