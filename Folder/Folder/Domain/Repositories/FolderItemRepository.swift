import Foundation

protocol FolderItemRepository: Sendable {
    func fetchItem(id: UUID) async throws -> FolderItem?
    func fetchItems(query: FolderItemQuery) async throws -> [FolderItem]
    func save(_ item: FolderItem) async throws
    func deleteItem(id: UUID) async throws
}
