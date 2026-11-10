import AppKit
import CryptoKit
import Foundation
import Network

/// Google sign-in for the calendar, entirely on this Mac: the system browser shows Google's consent page and
/// redirects to a one-time listener on 127.0.0.1, with PKCE so an intercepted code is useless. There is no
/// backend and no web view. The refresh token is kept in the Keychain; access tokens stay in memory.
@MainActor
final class GoogleOAuth: ObservableObject {
    /// The OAuth "Desktop app" client that `build-app.sh` writes into the built Info.plist.
    struct Client {
        let id: String
        let secret: String

        static var bundled: Client? {
            let info = Bundle.main.infoDictionary
            guard let id = info?["GNGoogleClientID"] as? String, !id.isEmpty,
                  let secret = info?["GNGoogleClientSecret"] as? String, !secret.isEmpty else { return nil }
            return Client(id: id, secret: secret)
        }
    }

    enum OAuthError: LocalizedError {
        case notConfigured
        case cancelled
        case timedOut
        case callback(String)
        case server(String)
        case reconnect

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google sign-in is not configured in this build."
            case .cancelled: "Google sign-in was cancelled."
            case .timedOut: "Google sign-in timed out. Try again."
            case .callback(let message): message
            case .server(let message): "Google said: \(message)"
            case .reconnect: "Google access ended. Reconnect Google Calendar."
            }
        }
    }

    static let scopes = "https://www.googleapis.com/auth/calendar.events.readonly openid email"
    private static let refreshAccount = "google_refresh_token"
    private static let authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!
    private static let signInTimeout: Duration = .seconds(300)

    let client: Client?
    @Published private(set) var isConnected: Bool
    /// The signed-in account, when known: from sign-in, or from the calendar the source last read.
    @Published var email: String?
    @Published private(set) var signingIn = false
    @Published private(set) var lastError: String?

    private var token: (value: String, expires: Date)?
    private var refreshing: Task<String, Error>?
    private var loopback: LoopbackServer?

    init(client: Client? = .bundled) {
        self.client = client
        isConnected = client != nil && ((try? Keychain.data(for: Self.refreshAccount)) ?? nil) != nil
    }

    var isConfigured: Bool { client != nil }

    // MARK: Sign in

    func signIn() async {
        guard let client else {
            lastError = OAuthError.notConfigured.localizedDescription
            return
        }
        loopback?.cancel()
        signingIn = true
        lastError = nil
        defer {
            signingIn = false
            loopback = nil
        }
        do {
            let verifier = OAuthPKCE.randomString()
            let state = OAuthPKCE.randomString()
            let server = LoopbackServer()
            loopback = server
            let port = try await server.start()
            let redirect = "http://127.0.0.1:\(port)"
            var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: client.id),
                URLQueryItem(name: "redirect_uri", value: redirect),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: Self.scopes),
                URLQueryItem(name: "code_challenge", value: OAuthPKCE.challenge(for: verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]
            NSWorkspace.shared.open(components.url!)
            let query = try await server.waitForCallback(timeout: Self.signInTimeout)
            let code = try OAuthPKCE.code(fromCallbackQuery: query, expectedState: state)
            let reply = try await post(Self.tokenURL, [
                "code": code,
                "client_id": client.id,
                "client_secret": client.secret,
                "redirect_uri": redirect,
                "grant_type": "authorization_code",
                "code_verifier": verifier,
            ])
            guard let refresh = reply.refreshToken else { throw OAuthError.server("no refresh token was returned") }
            Keychain.delete(Self.refreshAccount)
            try Keychain.add(Data(refresh.utf8), for: Self.refreshAccount)
            token = (reply.accessToken, Date().addingTimeInterval(reply.expiresIn ?? 3600))
            email = reply.idToken.flatMap(OAuthPKCE.email(fromIDToken:))
            isConnected = true
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelSignIn() {
        loopback?.cancel()
    }

    /// Revokes the grant at Google, then forgets the tokens.
    func disconnect() async {
        let refresh = (try? Keychain.data(for: Self.refreshAccount))?.flatMap { String(data: $0, encoding: .utf8) }
        forget()
        if let refresh {
            _ = try? await post(Self.revokeURL, ["token": refresh])
        }
    }

    private func forget() {
        Keychain.delete(Self.refreshAccount)
        token = nil
        refreshing?.cancel()
        refreshing = nil
        email = nil
        isConnected = false
    }

    // MARK: Access tokens

    /// A valid access token, refreshed when it is about to expire. Concurrent callers share one refresh.
    func accessToken() async throws -> String {
        if let token, token.expires.timeIntervalSinceNow > 60 { return token.value }
        if let refreshing { return try await refreshing.value }
        let task = Task { try await self.refresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func refresh() async throws -> String {
        guard let client else { throw OAuthError.notConfigured }
        guard let data = try Keychain.data(for: Self.refreshAccount), let refresh = String(data: data, encoding: .utf8) else {
            isConnected = false
            throw OAuthError.reconnect
        }
        do {
            let reply = try await post(Self.tokenURL, [
                "refresh_token": refresh,
                "client_id": client.id,
                "client_secret": client.secret,
                "grant_type": "refresh_token",
            ])
            token = (reply.accessToken, Date().addingTimeInterval(reply.expiresIn ?? 3600))
            lastError = nil
            return reply.accessToken
        } catch OAuthError.server(let message) where message.hasPrefix("invalid_grant") {
            forget()
            lastError = OAuthError.reconnect.localizedDescription
            throw OAuthError.reconnect
        }
    }

    /// Forgets the access token so the next request refreshes it, after Google rejected it.
    func invalidateAccessToken() {
        token = nil
    }

    // MARK: HTTP

    private struct TokenReply: Decodable {
        let accessToken: String
        let expiresIn: Double?
        let refreshToken: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    private struct ErrorReply: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func post(_ url: URL, _ form: [String: String]) async throws -> TokenReply {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(OAuthPKCE.formEncode(form).utf8)
        let (data, response) = try await Network.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reply = try? JSONDecoder().decode(ErrorReply.self, from: data)
            let message = [reply?.error, reply?.errorDescription].compactMap { $0 }.joined(separator: ": ")
            throw OAuthError.server(message.isEmpty ? "HTTP \(status)" : message)
        }
        if url == Self.revokeURL { return TokenReply(accessToken: "", expiresIn: nil, refreshToken: nil, idToken: nil) }
        return try JSONDecoder().decode(TokenReply.self, from: data)
    }
}

/// The pieces of the sign-in that need no network, kept apart so they can be tested.
enum OAuthPKCE {
    /// 43 characters from the RFC 7636 unreserved set, from 32 random bytes.
    static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    /// The S256 code challenge for `verifier`.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The authorization code from the redirect's query, after checking `state`.
    static func code(fromCallbackQuery query: String, expectedState: String) throws -> String {
        var components = URLComponents()
        components.percentEncodedQuery = query
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw GoogleOAuth.OAuthError.callback(error == "access_denied" ? "Google access was not allowed." : "Google sign-in failed: \(error)")
        }
        guard value("state") == expectedState else {
            throw GoogleOAuth.OAuthError.callback("The sign-in reply did not match this request. Try again.")
        }
        guard let code = value("code"), !code.isEmpty else {
            throw GoogleOAuth.OAuthError.callback("Google did not return a sign-in code.")
        }
        return code
    }

    /// The `email` claim of an ID token, for display only. The token came straight from Google over TLS.
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["email"] as? String
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }
}

/// Listens on 127.0.0.1 for the one browser redirect that ends a sign-in, then stops.
@MainActor
private final class LoopbackServer {
    private var listener: NWListener?
    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<String, Error>?
    private var pendingQuery: Result<String, Error>?
    private var timeout: Task<Void, Never>?

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            portContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.stateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func waitForCallback(timeout: Duration) async throws -> String {
        if let pendingQuery { return try pendingQuery.get() }
        self.timeout = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(GoogleOAuth.OAuthError.timedOut))
        }
        return try await withCheckedThrowingContinuation { callbackContinuation = $0 }
    }

    func cancel() {
        finish(.failure(GoogleOAuth.OAuthError.cancelled))
    }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                portContinuation?.resume(returning: port)
                portContinuation = nil
            }
        case .failed(let error):
            portContinuation?.resume(throwing: error)
            portContinuation = nil
            finish(.failure(error))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                self?.handle(data.map { String(decoding: $0, as: UTF8.self) } ?? "", on: connection)
            }
        }
    }

    /// Answers `GET /?…` with a short page and ends the sign-in. Other paths, like the favicon, get a 404.
    private func handle(_ request: String, on connection: NWConnection) {
        let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        guard target.hasPrefix("/?") else {
            respond(connection, status: "404 Not Found", body: "")
            return
        }
        let query = String(target.dropFirst(2))
        let ok = query.contains("code=")
        respond(connection, status: "200 OK", body: ok
            ? "<p>GrokNola is connected to Google Calendar. You can close this tab.</p>"
            : "<p>Google sign-in did not finish. You can close this tab and try again in GrokNola.</p>")
        finish(.success(query))
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=utf-8><title>GrokNola</title><body style=\"font: 15px -apple-system; margin: 3em\">\(body)</body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<String, Error>) {
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else if pendingQuery == nil {
            pendingQuery = result
        }
    }
}
