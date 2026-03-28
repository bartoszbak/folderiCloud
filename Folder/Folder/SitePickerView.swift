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
                            HStack(spacing: 12) {
                                SiteFavicon(urlString: site.iconURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(site.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color(.label))
                                    Text(site.url)
                                        .font(.footnote)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .foregroundStyle(Color(.label))
                    }
                }
            }
            .navigationTitle("Choose a Site")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
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

// MARK: - Favicon

private struct SiteFavicon: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderIcon: some View {
        Image(systemName: "globe")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
    }
}
