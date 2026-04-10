import SwiftUI

struct FolderBootstrapView: View {
    let model: FolderLibraryBootstrapModel

    var body: some View {
        switch model.state {
        case .loading:
            FolderBootstrapLoadingView(
                title: "Loading Folder",
                message: "Checking iCloud availability and preparing your library."
            )
        case .libraryInitializing:
            FolderBootstrapLoadingView(
                title: "Initializing Library",
                message: "Connecting the local database with your iCloud-backed metadata."
            )
        case let .iCloudUnavailable(message):
            FolderUnavailableView(message: message) {
                await model.start(force: true)
            }
        case let .ready(readyState):
            FolderFeedView(readyState: readyState)
        }
    }
}

private struct FolderBootstrapLoadingView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("Folder")
        }
    }
}

private struct FolderUnavailableView: View {
    let message: String
    let retry: @Sendable () async -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("iCloud Required", systemImage: "icloud.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task {
                        await retry()
                    }
                }
            }
            .navigationTitle("Folder")
        }
    }
}

#Preview("Unavailable") {
    FolderBootstrapView(
        model: FolderLibraryBootstrapModel(
            previewState: FolderLibraryBootstrapModel.State.iCloudUnavailable(
                message: "iCloud Drive is disabled."
            )
        )
    )
}
