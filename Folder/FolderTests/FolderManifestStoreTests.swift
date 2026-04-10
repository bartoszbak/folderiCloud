import Foundation
import Testing
@testable import Folder

struct FolderManifestStoreTests {

    @Test func writesAndScansManifestJSON() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let item = FolderItem(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            kind: .link,
            title: "Folder",
            createdAt: Date(timeIntervalSince1970: 1_711_849_600),
            updatedAt: Date(timeIntervalSince1970: 1_711_849_600),
            sortDate: Date(timeIntervalSince1970: 1_711_849_600)
        )
        let record = FolderItemRecord(
            item: item,
            attachments: [
                Folder.Attachment(
                    itemID: item.id,
                    role: .favicon,
                    relativePath: "Links/2024/03/12345678-1234-1234-1234-1234567890ab/previews/favicon.png",
                    uti: "public.png",
                    mimeType: "image/png",
                    byteSize: 42
                )
            ],
            linkInfo: LinkInfo(
                itemID: item.id,
                sourceURL: URL(string: "https://folder.example")!,
                pageTitle: "Folder"
            )
        )

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifest = try manifestStore.writeManifest(for: record)
        let scanned = try manifestStore.scanManifests()

        #expect(manifest.schemaVersion == FolderItemManifest.currentSchemaVersion)
        #expect(scanned.count == 1)
        #expect(scanned.first?.item.id == item.id)
        #expect(scanned.first?.linkInfo?.displayHost == "folder.example")
    }

    @Test func repairInspectionFindsMissingDbRecordAndMissingFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let useCase = InspectFolderRepairStateUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore,
            fileStore: fileStore
        )
        let item = FolderItem(
            id: UUID(uuidString: "ABCDEFAB-CDEF-CDEF-CDEF-ABCDEFABCDEF")!,
            kind: .file,
            title: "Specs",
            createdAt: Date(timeIntervalSince1970: 1_711_849_600),
            updatedAt: Date(timeIntervalSince1970: 1_711_849_600),
            sortDate: Date(timeIntervalSince1970: 1_711_849_600)
        )

        defer { try? FileManager.default.removeItem(at: rootURL) }

        _ = try fileStore.commitFile(
            FolderFileCommitRequest(
                item: item,
                role: .preview,
                preferredFilename: "preview.jpg",
                payload: .data(Data("preview".utf8))
            )
        )

        let missingAttachment = Folder.Attachment(
            itemID: item.id,
            role: .original,
            relativePath: "Files/2024/03/abcdefab-cdef-cdef-cdef-abcdefabcdef/originals/original.pdf",
            uti: "com.adobe.pdf",
            mimeType: "application/pdf",
            byteSize: 100
        )
        let manifest = FolderItemRecord(
            item: item,
            attachments: [missingAttachment]
        )
        _ = try manifestStore.writeManifest(for: manifest)

        let report = try await useCase.execute()

        #expect(report.missingDatabaseRecords.count == 1)
        #expect(report.missingDatabaseRecords.first?.manifest.item.id == item.id)
        #expect(report.missingFiles.contains { $0.relativePath == missingAttachment.relativePath })
    }

    @Test func manifestBackedCreatePersistsManifestAndDatabaseRecord() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let useCase = CreateFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore
        )

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let record = try await useCase.execute(
            FolderItemDraft(
                kind: .link,
                title: "Folder",
                createdAt: Date(timeIntervalSince1970: 1_711_849_600),
                attachments: [
                    AttachmentDraft(
                        role: .favicon,
                        relativePath: "Links/2024/03/will-be-rewritten/previews/favicon.png",
                        uti: "public.png",
                        mimeType: "image/png",
                        byteSize: 42
                    )
                ],
                linkInfo: LinkInfoDraft(
                    sourceURL: URL(string: "https://folder.example/item")!,
                    pageTitle: "Folder"
                )
            )
        )

        let manifest = try manifestStore.readManifest(for: record.item)
        let storedItem = try await itemRepository.fetchItem(id: record.item.id)
        let storedAttachments = try await attachmentRepository.fetchAttachments(itemIDs: [record.item.id])
        let storedLinkInfo = try await linkInfoRepository.fetchLinkInfo(itemIDs: [record.item.id])

        #expect(manifest?.item.id == record.item.id)
        #expect(storedItem?.id == record.item.id)
        #expect(storedAttachments[record.item.id] == record.attachments)
        #expect(storedLinkInfo[record.item.id] == record.linkInfo)
    }

    @Test func manifestBackedUpdateRewritesManifestAndDatabaseRecord() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let createUseCase = CreateFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore
        )
        let updateUseCase = UpdateFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore
        )

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let created = try await createUseCase.execute(
            FolderItemDraft(
                kind: .thought,
                title: "Draft",
                note: "Before",
                createdAt: Date(timeIntervalSince1970: 1_711_849_600)
            )
        )

        var updatedRecord = created
        updatedRecord.item.title = "Published"
        updatedRecord.item.note = "After"

        let updated = try await updateUseCase.execute(
            updatedRecord,
            updatedAt: Date(timeIntervalSince1970: 1_711_850_000)
        )

        let manifest = try manifestStore.readManifest(for: updated.item)
        let storedItem = try await itemRepository.fetchItem(id: updated.item.id)

        #expect(updated.item.updatedAt == Date(timeIntervalSince1970: 1_711_850_000))
        #expect(manifest?.item.title == "Published")
        #expect(manifest?.item.note == "After")
        #expect(storedItem?.title == "Published")
        #expect(storedItem?.note == "After")
    }
}
