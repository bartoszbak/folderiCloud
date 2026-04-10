import SwiftUI

struct FolderThoughtComposerSheet: View {
    let viewModel: ThoughtComposerViewModel
    let onCreated: @Sendable () async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $viewModel.text, axis: .vertical)
                        .lineLimit(8...)
                        .focused($focused)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Thoughts")
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
                    .disabled(viewModel.isSubmitting || viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            focused = true
        }
    }
}
