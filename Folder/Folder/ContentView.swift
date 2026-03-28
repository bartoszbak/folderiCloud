import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @Environment(WordPressAuthManager.self) private var auth
    @State private var isLoggingIn = false
    @State private var loginError: String?
    @State private var showHelp = false

    var body: some View {
        Group {
            if !auth.isReady {
                Color(.systemBackground).ignoresSafeArea()
            } else if auth.isAuthenticated && auth.selectedSite != nil {
                MainGridView()
            } else {
                loginView
            }
        }
        .sheet(isPresented: Binding(
            get: { auth.isReady && auth.isAuthenticated && auth.selectedSite == nil },
            set: { _ in }
        )) {
            SitePickerView()
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Login

    private var loginView: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                if let uiImage = UIImage(named: "AppIconDisplay") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .padding(.bottom, 24)
                }

                Text("Folder")
                    .font(.system(size: 40, weight: .bold))
                    .padding(.bottom, 12)

                Text("Everything you want to keep,\nready when you need it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)

                if let error = loginError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.bottom, 12)
                }

                Button {
                    Task { await performLogin() }
                } label: {
                    Text(isLoggingIn ? "Connecting…" : "Connect WordPress.com account")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.blue).interactive(), in: Capsule())
                .disabled(isLoggingIn)
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Help button — rendered on top
            Button { showHelp = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .padding(.top, 8)
            .padding(.trailing, 20)
        }
        .sheet(isPresented: $showHelp) {
            HowItWorksView()
        }
    }
}

// MARK: - How It Works Sheet

private struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step {
        let icon: String
        let title: String
        let description: String
    }

    private let steps: [Step] = [
        Step(icon: "person.badge.key", title: "Connect your account", description: "Sign in with your WordPress.com account to link Folder to your blog."),
        Step(icon: "square.and.arrow.up", title: "Share from any app", description: "Use the iOS Share sheet to send photos, links, text, or files directly to your blog."),
        Step(icon: "photo.on.rectangle", title: "Save photos", description: "Share images from Photos or any other app — they're uploaded and posted instantly."),
        Step(icon: "link", title: "Save links", description: "Share a URL from Safari or any browser to save it as a link post."),
        Step(icon: "doc", title: "Save files", description: "Share PDFs or other files to store them on your blog for easy access later."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How Folder works")
                            .font(.largeTitle.bold())
                        Text("Save anything to your WordPress.com blog in seconds.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: step.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title)
                                        .font(.body.weight(.semibold))
                                    Text(step.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 16)
                            if index < steps.count - 1 {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - ContentView Actions extension

extension ContentView {
    func performLogin() async {
        isLoggingIn = true
        loginError = nil
        do {
            try await auth.login()
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                loginError = error.localizedDescription
            }
        }
        isLoggingIn = false
    }
}

#Preview {
    ContentView()
        .environment(WordPressAuthManager())
}
