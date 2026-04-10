import Foundation

enum FolderManifestStoreError: Error, Equatable, Sendable {
    case invalidManifestData(URL)
    case unsupportedSchemaVersion(Int)
}
