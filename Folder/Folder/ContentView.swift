import SwiftUI

struct ContentView: View {
    @State private var bootstrap = FolderLibraryBootstrapModel()

    var body: some View {
        FolderBootstrapView(model: bootstrap)
            .task {
                await bootstrap.start()
            }
    }
}

#Preview {
    ContentView()
}
