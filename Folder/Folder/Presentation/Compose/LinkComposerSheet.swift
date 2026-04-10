import SwiftUI

struct FolderLinkComposerSheet: View {
    let viewModel: LinkComposerViewModel
    let onCreated: @Sendable () async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $viewModel.urlString)
                        .keyboardType(.default)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)

                    if viewModel.metadataFetcher.isFetching {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text("Fetching page info…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.metadataFetcher.fetchedTitle != nil || viewModel.metadataFetcher.fetchedDescription != nil {
                        HStack(alignment: .top, spacing: 10) {
                            Group {
                                if let favicon = viewModel.metadataFetcher.favicon {
                                    Image(uiImage: favicon)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                            VStack(alignment: .leading, spacing: 2) {
                                if let title = viewModel.metadataFetcher.fetchedTitle {
                                    Text(title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                if let description = viewModel.metadataFetcher.fetchedDescription {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Title (optional)") {
                    TextField("Add a title", text: $viewModel.title)
                }

                Section("Description (optional)") {
                    TextField("Add a description", text: $viewModel.descriptionText, axis: .vertical)
                        .lineLimit(3...)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.reset()
                        dismiss()
                    }
                    .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSubmitting ? "Saving..." : "Save") {
                        Task {
                            if await viewModel.submit() {
                                dismiss()
                                await onCreated()
                            }
                        }
                    }
                    .disabled(viewModel.isSubmitting || viewModel.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            focused = true
        }
        .onChange(of: viewModel.urlString) { _, _ in
            viewModel.handleURLChange()
        }
        .onChange(of: viewModel.metadataFetcher.fetchedTitle) { _, newTitle in
            viewModel.applyFetchedTitle(newTitle)
        }
        .onChange(of: viewModel.metadataFetcher.fetchedDescription) { _, newDescription in
            viewModel.applyFetchedDescription(newDescription)
        }
    }
}
