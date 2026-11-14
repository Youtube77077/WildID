import Foundation

enum HTTPError: LocalizedError {
    case badStatus(Int)
    case offline
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "The server responded with status \(code)."
        case .offline: "You're offline. Connect to the internet to load this."
        case .decoding(let message): "Unexpected data from the server (\(message))."
        }
    }
}

/// Spaces requests to a host so WildID stays within public API fair-use limits
/// (iNaturalist asks for roughly one request per second).
actor RateLimiter {
    private let minimumInterval: TimeInterval
    private var nextSlot = Date.distantPast

    init(requestsPerSecond: Double) {
        minimumInterval = 1.0 / requestsPerSecond
    }

    func waitTurn() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(minimumInterval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

/// Shared JSON client. Every successful response is stored in a disk cache so that
/// previously viewed species, maps and lists keep working without a connection.
final class HTTPClient: @unchecked Sendable {
    static let shared = HTTPClient()

    let session: URLSession
    let cache: URLCache
    private let limiters: [String: RateLimiter] = [
        "api.inaturalist.org": RateLimiter(requestsPerSecond: 1.2),
        "api.gbif.org": RateLimiter(requestsPerSecond: 4),
        "en.wikipedia.org": RateLimiter(requestsPerSecond: 4),
        "query.wikidata.org": RateLimiter(requestsPerSecond: 2),
        "xeno-canto.org": RateLimiter(requestsPerSecond: 1),
    ]

    static let userAgent = "WildID/1.0 (iOS; open-source wildlife identification app)"

    private init() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cache = URLCache(memoryCapacity: 24 * 1024 * 1024,
                         diskCapacity: 300 * 1024 * 1024,
                         directory: cachesURL.appendingPathComponent("WildIDHTTP"))
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": HTTPClient.userAgent, "Accept": "application/json"]
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    /// Fetch raw data. Falls back to the last cached copy when offline or when the server fails.
    func data(from url: URL, maxAge: TimeInterval = 60 * 60 * 6, rateLimited: Bool = true) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let cached = cache.cachedResponse(for: request),
           let stored = cached.userInfo?["storedAt"] as? Date,
           Date().timeIntervalSince(stored) < maxAge {
            return cached.data
        }

        do {
            if rateLimited, let host = url.host, let limiter = limiters[host] {
                await limiter.waitTurn()
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.badStatus(-1) }
            guard (200..<300).contains(http.statusCode) else {
                if let cached = cache.cachedResponse(for: request) { return cached.data }
                throw HTTPError.badStatus(http.statusCode)
            }
            let entry = CachedURLResponse(response: http, data: data, userInfo: ["storedAt": Date()], storagePolicy: .allowed)
            cache.storeCachedResponse(entry, for: request)
            return data
        } catch let error as URLError {
            if let cached = cache.cachedResponse(for: request) { return cached.data }
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw HTTPError.offline
            default:
                throw error
            }
        }
    }

    func get<T: Decodable>(_ type: T.Type, from url: URL, maxAge: TimeInterval = 60 * 60 * 6) async throws -> T {
        let data = try await data(from: url, maxAge: maxAge)
        do {
            return try JSONDecoder.wild.decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error).prefix(160).description)
        }
    }

    /// Removes all cached API responses (used by Settings > Storage).
    func clearCache() {
        cache.removeAllCachedResponses()
    }
}

extension JSONDecoder {
    static let wild: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}

extension URL {
    /// Builds a URL from a base and query items, skipping nil values.
    static func build(_ base: String, _ items: [String: String?]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = items.compactMap { key, value in
            value.map { URLQueryItem(name: key, value: $0) }
        }.sorted { $0.name < $1.name }
        return components.url!
    }
}
