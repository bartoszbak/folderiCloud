import AuthenticationServices
import Foundation

@Observable
final class WordPressAuthManager: NSObject {
    private(set) var token: String?
    private(set) var sites: [WordPressSite] = []
    private(set) var selectedSite: WordPressSite?
    private(set) var user: WordPressUser?
    private(set) var isFetchingSites = false

    var isAuthenticated: Bool { token != nil }

    private static let selectedSiteKey = "selected_wordpress_site"
    private static let userKey = "wordpress_user"
    private var session: ASWebAuthenticationSession?

    override init() {
        super.init()
        Task.detached(priority: .userInitiated) { [weak self] in
            let stored = KeychainHelper.loadToken()
            let site = Self.loadSelectedSite()
            let user = Self.loadUser()
            // Keep App Group in sync so the Share Extension always has fresh credentials
            // even if selectSite() was called on a previous install or the group data was cleared.
            let appGroup = UserDefaults(suiteName: KeychainHelper.appGroup)
            if let stored {
                appGroup?.set(stored, forKey: "shared_token")
            } else {
                appGroup?.removeObject(forKey: "shared_token")
            }
            if let site, let data = try? JSONEncoder().encode(site) {
                appGroup?.set(data, forKey: "shared_site")
            } else {
                appGroup?.removeObject(forKey: "shared_site")
            }
            await MainActor.run { [weak self] in
                self?.token = stored
                self?.selectedSite = site
                self?.user = user
            }
        }
    }

    // MARK: - Auth

    func login() async throws {
        var components = URLComponents(string: "https://public-api.wordpress.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: WordPressSecrets.clientID),
            URLQueryItem(name: "redirect_uri", value: WordPressSecrets.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "global"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let s = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "com.bartbak.fastapp.folder"
            ) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: AuthError.noCallbackURL); return }
                continuation.resume(returning: url)
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            s.start()
        }
        session = nil

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.missingCode }

        let fetchedToken = try await exchangeCode(code)
        KeychainHelper.saveToken(fetchedToken)
        token = fetchedToken

        try await fetchSites()
        try? await fetchUser()
    }

    func logout() {
        KeychainHelper.deleteToken()
        UserDefaults.standard.removeObject(forKey: Self.selectedSiteKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        let appGroup = UserDefaults(suiteName: KeychainHelper.appGroup)
        appGroup?.removeObject(forKey: "shared_site")
        token = nil
        selectedSite = nil
        sites = []
        user = nil
    }

    // MARK: - Sites

    func fetchSites() async throws {
        guard let token else { return }
        isFetchingSites = true
        defer { isFetchingSites = false }

        var request = URLRequest(url: URL(string: "https://public-api.wordpress.com/rest/v1.1/me/sites")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.sitesFetchFailed
        }

        let result = try JSONDecoder().decode(SitesResponse.self, from: data)
        sites = result.sites
    }

    func selectSite(_ site: WordPressSite) {
        selectedSite = site
        if let data = try? JSONEncoder().encode(site) {
            UserDefaults.standard.set(data, forKey: Self.selectedSiteKey)
            // Mirror to App Group so the Share Extension can read it
            UserDefaults(suiteName: KeychainHelper.appGroup)?.set(data, forKey: "shared_site")
        }
    }

    func fetchUser() async throws {
        guard let token else { return }
        var request = URLRequest(url: URL(string: "https://public-api.wordpress.com/rest/v1.1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let fetched = try JSONDecoder().decode(WordPressUser.self, from: data)
        user = fetched
        if let encoded = try? JSONEncoder().encode(fetched) {
            UserDefaults.standard.set(encoded, forKey: Self.userKey)
        }
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://public-api.wordpress.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id": WordPressSecrets.clientID,
            "client_secret": WordPressSecrets.clientSecret,
            "redirect_uri": WordPressSecrets.redirectURI,
            "code": code,
            "grant_type": "authorization_code",
        ]
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).accessToken
    }

    // MARK: - Persistence

    private static func loadSelectedSite() -> WordPressSite? {
        guard let data = UserDefaults.standard.data(forKey: selectedSiteKey) else { return nil }
        return try? JSONDecoder().decode(WordPressSite.self, from: data)
    }

    private static func loadUser() -> WordPressUser? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        return try? JSONDecoder().decode(WordPressUser.self, from: data)
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case noCallbackURL
        case missingCode
        case tokenExchangeFailed(String)
        case sitesFetchFailed

        var errorDescription: String? {
            switch self {
            case .noCallbackURL: "No callback URL received."
            case .missingCode: "Authorization code missing from callback."
            case .tokenExchangeFailed(let detail): "Token exchange failed: \(detail)"
            case .sitesFetchFailed: "Could not load your WordPress.com sites."
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension WordPressAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let scene else { fatalError("No window scene available") }
        return scene.windows.first { $0.isKeyWindow }
            ?? scene.windows.first
            ?? UIWindow(windowScene: scene)
    }
}

// MARK: - Private

private struct TokenResponse: Decodable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}
