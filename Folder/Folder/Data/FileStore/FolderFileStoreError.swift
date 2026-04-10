import Foundation

enum FolderFileStoreError: Error, Equatable, Sendable {
    case ubiquityContainerUnavailable
    case invalidRelativePath(String)
    case cannotAccessSourceFile(URL)
    case coordinatedWriteFailed(String)
    case itemDirectoryMissing(UUID)
}
