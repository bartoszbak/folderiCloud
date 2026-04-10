import SwiftUI

struct ShareImportProgressView: View {
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                Text("Adding to Folder")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("Folder")
        }
    }
}

#Preview {
    ShareImportProgressView(message: "Preparing your shared items.")
}
