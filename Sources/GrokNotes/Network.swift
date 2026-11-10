import Foundation

/// The one URLSession for xAI and Google. Nothing it sends or receives is cached or kept on disk, it keeps
/// no cookies, and it refuses TLS older than 1.2.
enum Network {
    static let session = URLSession(configuration: configuration)

    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return config
    }

    /// The most of an error reply that is read, so a misbehaving server cannot fill memory.
    static let maxErrorBody = 64 * 1024
}
