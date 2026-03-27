import SwiftUI

struct SitePickerView: View {
    @Environment(WordPressAuthManager.self) private var auth
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if auth.isFetchingSites {
                    ProgressView("Loading your sites…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ContentUnavailableView {
                        Label("Couldn't Load Sites", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadSites() } }
                    }
                } else if auth.sites.isEmpty {
                    ContentUnavailableView(
                        "No Sites Found",
                        systemImage: "globe.slash",
                        description: Text("No WordPress.com sites were found for your account.")
                    )
                } else {
                    List(auth.sites) { site in
                        Button {
                            auth.selectSite(site)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(site.url)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Choose a Site")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Disconnect", role: .destructive) {
                        auth.logout()
                    }
                }
            }
        }
        .task { await loadSites() }
    }

    private func loadSites() async {
        loadError = nil
        do {
            try await auth.fetchSites()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
