import Foundation
import SwiftData
import Testing
@testable import Folder

struct SwiftDataFolderRepositoryTests {

    @Test func cloudSyncConfigurationUsesAppGroupAndPrivateCloudKit() throws {
        let configuration = try FolderLocalStore.makeConfiguration(mode: .liveCloudSync)

        #expect(configuration.groupAppContainerIdentifier == FolderLocalStoreMode.defaultAppGroupIdentifier)
        #expect(configuration.cloudKitContainerIdentifier == FolderLocalStoreMode.defaultCloudKitContainerIdentifier)
        #expect(configuration.isStoredInMemoryOnly == false)
    }

    @Test func savesAndFetchesItemsWithLocalFiltering() async throws {
        let repository = try FolderLocalStore.makeRepository(isStoredInMemoryOnly: true)

        try await repository.save(
            FolderItem(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                kind: .thought,
                title: "Thought",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10),
                sortDate: Date(timeIntervalSince1970: 10)
            )
        )
        try await repository.save(
            FolderItem(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                kind: .photo,
                title: "Photo",
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 20),
                sortDate: Date(timeIntervalSince1970: 20)
            )
        )

        let photos = try await repository.fetchItems(query: FolderItemQuery(kind: .photo))
        let allItems = try await repository.fetchItems(query: FolderItemQuery())

        #expect(photos.count == 1)
        #expect(photos.first?.title == "Photo")
        #expect(allItems.map(\.title) == ["Photo", "Thought"])
    }

    @Test func replacesAttachmentsAndLinkInfoForOneItem() async throws {
        let repository = try FolderLocalStore.makeRepository(isStoredInMemoryOnly: true)
        let itemID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

        try await repository.save(
            FolderItem(
                id: itemID,
                kind: .link,
                title: "Reference",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10),
                sortDate: Date(timeIntervalSince1970: 10)
            )
        )

        try await repository.replaceAttachments([
            Attachment(
                id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                itemID: itemID,
                role: .favicon,
                relativePath: "Links/favicon.png",
                uti: "public.png",
                mimeType: "image/png",
                byteSize: 100
            )
        ], for: itemID)

        try await repository.save(
            LinkInfo(
                itemID: itemID,
                sourceURL: URL(string: "https://folder.example/link")!,
                pageTitle: "Folder"
            ),
            for: itemID
        )

        let attachments = try await repository.fetchAttachments(itemIDs: [itemID])
        let linkInfos = try await repository.fetchLinkInfo(itemIDs: [itemID])

        #expect(attachments[itemID]?.count == 1)
        #expect(linkInfos[itemID]?.displayHost == "folder.example")

        try await repository.replaceAttachments([], for: itemID)
        try await repository.save(nil, for: itemID)

        let emptyAttachments = try await repository.fetchAttachments(itemIDs: [itemID])
        let emptyLinkInfos = try await repository.fetchLinkInfo(itemIDs: [itemID])

        #expect(emptyAttachments[itemID]?.isEmpty == true)
        #expect(emptyLinkInfos[itemID] == nil)
    }
}
