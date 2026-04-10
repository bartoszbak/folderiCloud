import Foundation
import Testing
@testable import Folder

struct DomainCoreTests {

    @Test func createLinkBuildsPureFolderDomainRecord() async throws {
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let useCase = CreateFolderItemUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )

        let created = try await useCase.execute(
            FolderItemDraft(
                kind: .link,
                title: "Folder",
                note: "Primary reference",
                createdAt: Date(timeIntervalSince1970: 100),
                attachments: [
                    AttachmentDraft(
                        role: .favicon,
                        relativePath: "Links/2026/03/example/favicon.png",
                        uti: "public.png",
                        mimeType: "image/png",
                        byteSize: 128
                    )
                ],
                linkInfo: LinkInfoDraft(
                    sourceURL: URL(string: "https://folder.example/item")!,
                    pageTitle: "Folder"
                )
            )
        )

        #expect(created.item.kind == FolderItemKind.link)
        #expect(created.linkInfo?.displayHost == "folder.example")
        #expect(created.attachments.count == 1)
        #expect(created.attachments.first?.itemID == created.item.id)
        #expect(created.item.syncState == SyncState.localOnly)
    }

    @Test func fetchAppliesQueryFiltersAndHydratesAttachments() async throws {
        let itemRepository = InMemoryFolderItemRepository(items: [
            FolderItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                kind: .thought,
                title: "Newest thought",
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 20),
                sortDate: Date(timeIntervalSince1970: 20)
            ),
            FolderItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                kind: .photo,
                title: "Photo",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10),
                sortDate: Date(timeIntervalSince1970: 10)
            )
        ])
        let attachmentRepository = InMemoryAttachmentRepository(attachmentsByItemID: [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!: [],
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!: [
                Attachment(
                    itemID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    role: .original,
                    relativePath: "Photos/2026/03/example/original.heic",
                    uti: "public.heic",
                    mimeType: "image/heic",
                    byteSize: 4096
                )
            ]
        ])
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let useCase = FetchFolderItemsUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )

        let fetched = try await useCase.execute(query: FolderItemQuery(kind: .photo))

        #expect(fetched.count == 1)
        #expect(fetched.first?.item.kind == .photo)
        #expect(fetched.first?.attachments.count == 1)
    }

    @Test func updateRefreshesTimestampAndRejectsCrossOwnedAttachments() async throws {
        let itemID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let itemRepository = InMemoryFolderItemRepository(items: [
            FolderItem(
                id: itemID,
                kind: .thought,
                title: "Draft",
                note: "Before",
                createdAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 5),
                sortDate: Date(timeIntervalSince1970: 5)
            )
        ])
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let useCase = UpdateFolderItemUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )

        let invalidRecord = FolderItemRecord(
            item: FolderItem(
                id: itemID,
                kind: .thought,
                title: "Draft",
                note: "After",
                createdAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 5),
                sortDate: Date(timeIntervalSince1970: 5)
            ),
            attachments: [
                Attachment(
                    itemID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    role: .preview,
                    relativePath: "Thoughts/preview.txt",
                    uti: "public.plain-text",
                    mimeType: "text/plain",
                    byteSize: 12
                )
            ]
        )

        do {
            _ = try await useCase.execute(invalidRecord)
            Issue.record("Expected attachment ownership validation to fail.")
        } catch let error as FolderDomainError {
            #expect(error == FolderDomainError.attachmentOwnershipMismatch(itemID: itemID))
        }

        let validRecord = FolderItemRecord(
            item: FolderItem(
                id: itemID,
                kind: .thought,
                title: "Draft",
                note: "After",
                createdAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 5),
                sortDate: Date(timeIntervalSince1970: 5)
            )
        )

        let updated = try await useCase.execute(
            validRecord,
            updatedAt: Date(timeIntervalSince1970: 25)
        )

        #expect(updated.item.updatedAt == Date(timeIntervalSince1970: 25))
    }

    @Test func deleteMarksItemAsPendingDelete() async throws {
        let itemID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let itemRepository = InMemoryFolderItemRepository(items: [
            FolderItem(
                id: itemID,
                kind: .file,
                title: "Document",
                createdAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 5),
                sortDate: Date(timeIntervalSince1970: 5),
                syncState: .synced
            )
        ])
        let useCase = DeleteFolderItemUseCase(itemRepository: itemRepository)

        let deleted = try await useCase.execute(
            itemID: itemID,
            deletedAt: Date(timeIntervalSince1970: 30)
        )

        #expect(deleted.isDeleted)
        #expect(deleted.syncState == SyncState.pendingDelete)
        #expect(deleted.updatedAt == Date(timeIntervalSince1970: 30))
    }

    @Test func syncSnapshotAndFinalizeDeleteUseCasesTrackTombstones() async throws {
        let doomedID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let safeID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let itemRepository = InMemoryFolderItemRepository(items: [
            FolderItem(
                id: doomedID,
                kind: .file,
                title: "Old File",
                createdAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 5),
                sortDate: Date(timeIntervalSince1970: 5),
                syncState: .pendingDelete,
                isDeleted: true
            ),
            FolderItem(
                id: safeID,
                kind: .thought,
                title: "Draft",
                createdAt: Date(timeIntervalSince1970: 6),
                updatedAt: Date(timeIntervalSince1970: 6),
                sortDate: Date(timeIntervalSince1970: 6),
                syncState: .syncing
            )
        ])
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let snapshotUseCase = FetchFolderSyncSnapshotUseCase(itemRepository: itemRepository)
        let finalizeUseCase = FinalizeDeletedFolderItemsUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            fileStore: fileStore
        )

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let snapshot = try await snapshotUseCase.execute()
        let finalized = try await finalizeUseCase.execute()
        let remaining = try await itemRepository.fetchItems(query: FolderItemQuery(includeDeleted: true))

        #expect(snapshot.pendingDeleteCount == 1)
        #expect(snapshot.syncingCount == 1)
        #expect(finalized == [doomedID])
        #expect(remaining.map(\.id) == [safeID])
    }
}
