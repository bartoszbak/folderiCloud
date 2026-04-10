import Foundation

protocol LinkInfoRepository: Sendable {
    func fetchLinkInfo(itemIDs: [UUID]) async throws -> [UUID: LinkInfo]
    func save(_ linkInfo: LinkInfo?, for itemID: UUID) async throws
}
