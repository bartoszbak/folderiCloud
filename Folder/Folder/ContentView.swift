import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @Environment(WordPressAuthManager.self) private var auth
    @State private var isLoggingIn = false
    @State private var loginError: String?

    var body: some View {
        if auth.isAuthenticated {
            if auth.selectedSite != nil {
                MainGridView()
            } else {
                SitePickerView()
            }
        } else {
            loginView
        }
    }

    // MARK: - Login

    private var loginView: some View {
        VStack(spacing: 24) {
            Spacer()
            if let uiImage = UIImage(named: "AppIconDisplay") {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            Text("Folder")
                .font(.largeTitle.bold())
            Text("Connect your WordPress.com account to share content directly from any app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            if let error = loginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                Task { await performLogin() }
            } label: {
                Label(
                    isLoggingIn ? "Connecting…" : "Connect with WordPress.com",
                    systemImage: "link"
                )
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoggingIn)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Actions

    private func performLogin() async {
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
