import Foundation

protocol FolderManifestStore: Sendable {
    func manifestURL(for item: FolderItem) throws -> URL
    func writeManifest(for record: FolderItemRecord) throws -> FolderItemManifest
    func readManifest(for item: FolderItem) throws -> FolderItemManifest?
    func scanManifests() throws -> [FolderItemManifest]
}
