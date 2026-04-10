import Foundation

protocol AttachmentRepository: Sendable {
    func fetchAttachments(itemIDs: [UUID]) async throws -> [UUID: [Attachment]]
    func replaceAttachments(_ attachments: [Attachment], for itemID: UUID) async throws
}
