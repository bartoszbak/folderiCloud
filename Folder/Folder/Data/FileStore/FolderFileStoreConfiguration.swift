import Foundation

struct FolderFileStoreConfiguration: Sendable {
    enum RootLocation: Sendable {
        case ubiquityContainer(identifier: String?)
        case fixed(URL)
    }

    let rootLocation: RootLocation

    nonisolated init(
        rootLocation: RootLocation = .ubiquityContainer(identifier: "iCloud.com.bartbak.fastapp.Folder")
    ) {
        self.rootLocation = rootLocation
    }
}
