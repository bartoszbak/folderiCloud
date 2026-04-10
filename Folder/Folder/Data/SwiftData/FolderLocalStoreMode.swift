import Foundation
import SwiftData

enum FolderLocalStoreMode: Hashable, Sendable {
    case localOnly
    case privateCloud(cloudKitContainerIdentifier: String, appGroupIdentifier: String)

    static let defaultAppGroupIdentifier = "group.com.bartbak.fastapp.folder"
    static let defaultCloudKitContainerIdentifier = "iCloud.com.bartbak.fastapp.Folder"
    static let liveCloudSync = Self.privateCloud(
        cloudKitContainerIdentifier: defaultCloudKitContainerIdentifier,
        appGroupIdentifier: defaultAppGroupIdentifier
    )

    var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
        switch self {
        case .localOnly:
            .none
        case let .privateCloud(cloudKitContainerIdentifier, _):
            .private(cloudKitContainerIdentifier)
        }
    }

    var groupContainer: ModelConfiguration.GroupContainer {
        switch self {
        case .localOnly:
            .none
        case let .privateCloud(_, appGroupIdentifier):
            .identifier(appGroupIdentifier)
        }
    }

    var groupAppContainerIdentifier: String? {
        switch self {
        case .localOnly:
            nil
        case let .privateCloud(_, appGroupIdentifier):
            appGroupIdentifier
        }
    }

    var cloudKitContainerIdentifier: String? {
        switch self {
        case .localOnly:
            nil
        case let .privateCloud(cloudKitContainerIdentifier, _):
            cloudKitContainerIdentifier
        }
    }
}
