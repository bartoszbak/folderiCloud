import SwiftUI

struct FolderMaintenanceView: View {
    let viewModel: FolderMaintenanceViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                if let status = viewModel.status {
                    Section {
                        Text(status.message)
                            .foregroundStyle(status.kind == .failure ? .red : .primary)
                    }
                }

                Section("Repair Report") {
                    summaryRow("Missing DB Records", value: viewModel.repairReport?.missingDatabaseRecords.count ?? 0)
                    summaryRow("Missing Manifests", value: viewModel.repairReport?.missingManifests.count ?? 0)
                    summaryRow("Missing Files", value: viewModel.repairReport?.missingFiles.count ?? 0)
                    summaryRow("Orphan Files", value: viewModel.repairReport?.orphanFiles.count ?? 0)
                }

                Section("Maintenance") {
                    Button("Refresh Report") {
                        Task { await viewModel.refreshReport() }
                    }
                    .disabled(viewModel.isWorking)

                    Button("Rebuild DB From Manifests") {
                        Task { await viewModel.rebuildDatabaseFromManifests() }
                    }
                    .disabled(viewModel.isWorking)

                    Button("Regenerate Previews") {
                        Task { await viewModel.regeneratePreviews() }
                    }
                    .disabled(viewModel.isWorking)

                    Button("Clean Inbox Older Than 7 Days") {
                        Task { await viewModel.cleanSharedInbox() }
                    }
                    .disabled(viewModel.isWorking)
                }

                if let report = viewModel.repairReport,
                   !report.missingFiles.isEmpty || !report.orphanFiles.isEmpty {
                    Section("File Details") {
                        ForEach(report.missingFiles, id: \.self) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Missing")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.relativePath)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                            }
                        }
                        ForEach(report.orphanFiles, id: \.self) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Orphan")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.relativePath)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if viewModel.repairReport == nil {
                await viewModel.refreshReport()
            }
        }
    }

    private func summaryRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
        }
    }
}
