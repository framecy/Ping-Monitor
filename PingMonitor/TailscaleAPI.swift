import Foundation

// MARK: - Tailnet device (control-plane inventory)

/// 来自 `GET /api/v2/tailnet/{tailnet}/devices` 的设备记录。
/// 这是「全局监管」的数据源：覆盖整个 tailnet，不依赖本机能不能连上对端，
/// 也完全不经过 tailnet 数据面 —— 只是一次到 api.tailscale.com 的 HTTPS 调用。
struct TailnetDevice: Identifiable, Sendable {
    let id: String
    let hostname: String
    let name: String            // MagicDNS 全名，如 nas.tail1234.ts.net
    let addresses: [String]     // 100.x.y.z / fd7a:...
    let os: String
    let user: String
    let clientVersion: String
    let updateAvailable: Bool
    let authorized: Bool
    let lastSeen: Date?
    let expires: Date?
    let keyExpiryDisabled: Bool
    let tags: [String]
    let advertisedRoutes: [String]
    let enabledRoutes: [String]
    let isExternal: Bool

    var tailscaleIP: String {
        addresses.first(where: { $0.contains(".") }) ?? addresses.first ?? ""
    }

    /// 控制面不返回 online 布尔值，只有 lastSeen；按心跳窗口推导在线状态。
    /// Tailscale 客户端约每 1 分钟上报一次，5 分钟是留足抖动的保守阈值。
    static let onlineWindow: TimeInterval = 300

    var isOnline: Bool {
        guard let lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < Self.onlineWindow
    }

    /// 密钥过期预警：7 天内到期且未关闭过期。
    var keyExpiringSoon: Bool {
        guard !keyExpiryDisabled, let expires else { return false }
        let remaining = expires.timeIntervalSinceNow
        return remaining > 0 && remaining < 7 * 24 * 3600
    }

    var keyExpired: Bool {
        guard !keyExpiryDisabled, let expires else { return false }
        return expires.timeIntervalSinceNow <= 0
    }
}

// MARK: - Wire format

private struct DevicesResponse: Decodable {
    let devices: [Device]

    struct Device: Decodable {
        let id: String?
        let nodeId: String?
        let hostname: String?
        let name: String?
        let addresses: [String]?
        let os: String?
        let user: String?
        let clientVersion: String?
        let updateAvailable: Bool?
        let authorized: Bool?
        let lastSeen: String?
        let expires: String?
        let keyExpiryDisabled: Bool?
        let tags: [String]?
        let advertisedRoutes: [String]?
        let enabledRoutes: [String]?
        let isExternal: Bool?
    }
}

private struct OAuthTokenResponse: Decodable {
    let access_token: String
    let expires_in: Double?
}

// MARK: - Errors

enum TailscaleAPIError: Error, Sendable {
    case notConfigured
    case unauthorized
    case forbidden
    case rateLimited
    case http(Int)
    case transport(String)
    case decoding(String)

    /// 本地化 key，展示时由调用方（UI，主 actor）翻译；非 key 的分支返回原始信息。
    var localizationKey: String? {
        switch self {
        case .notConfigured: return "tailscale.api.error.not_configured"
        case .unauthorized: return "tailscale.api.error.unauthorized"
        case .forbidden: return "tailscale.api.error.forbidden"
        case .rateLimited: return "tailscale.api.error.rate_limited"
        case .http, .transport, .decoding: return nil
        }
    }

    var rawDescription: String {
        switch self {
        case .notConfigured: return "OAuth client not configured"
        case .unauthorized: return "Unauthorized (401)"
        case .forbidden: return "Forbidden (403) — missing devices:core:read scope"
        case .rateLimited: return "Rate limited (429)"
        case .http(let code): return "HTTP \(code)"
        case .transport(let message): return message
        case .decoding(let message): return "Decode: \(message)"
        }
    }
}

// MARK: - API client

/// Tailscale 控制面客户端。
///
/// 只做两件事：用 OAuth client credentials 换 access token，再拉设备清单。
/// 刻意不实现任何写接口 —— 本机已经装了 Tailscale app，PingMonitor 不注册节点、
/// 不改路由、不承载 tailnet 流量，纯只读监管。
actor TailscaleAPIClient {
    static let shared = TailscaleAPIClient()

    private let tokenURL = URL(string: "https://api.tailscale.com/api/v2/oauth/token")!
    /// `-` 是控制面对「凭据所属默认 tailnet」的别名，省得让用户手填 tailnet 名。
    private let devicesURL = URL(string: "https://api.tailscale.com/api/v2/tailnet/-/devices")!

    private var cachedToken: String?
    private var tokenExpiry: Date?
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // 凭据不进磁盘缓存。
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    /// 凭据变更后必须调用，丢弃旧 token。
    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = nil
    }

    func fetchDevices() async throws -> [TailnetDevice] {
        let token = try await accessToken()
        var request = URLRequest(url: devicesURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // token 可能已被撤销：清掉重试一次。
            invalidateToken()
            let retryToken = try await accessToken()
            request.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await send(request)
            try validate(retryResponse)
            return try decodeDevices(retryData)
        }
        try validate(response)
        return try decodeDevices(data)
    }

    /// 供设置页「验证并保存」使用：只校验凭据能否换到 token 并读到设备数。
    func validateCredentials() async throws -> Int {
        invalidateToken()
        return try await fetchDevices().count
    }

    // MARK: - 写操作（控制面配置，仍不经过 tailnet 数据面）
    //
    // 全部是对 tailnet 配置的修改，不会让本机承载任何 tailnet 流量。
    // 需要 OAuth client 具备对应的写 scope：
    //   authorized / key / tags / delete → devices:core
    //   routes                          → devices:routes

    func setAuthorized(deviceID: String, authorized: Bool) async throws {
        try await write(deviceID: deviceID, path: "authorized", body: ["authorized": authorized])
    }

    func setKeyExpiryDisabled(deviceID: String, disabled: Bool) async throws {
        try await write(deviceID: deviceID, path: "key", body: ["keyExpiryDisabled": disabled])
    }

    func setTags(deviceID: String, tags: [String]) async throws {
        try await write(deviceID: deviceID, path: "tags", body: ["tags": tags])
    }

    /// routes 接口是「全量覆盖」语义：传入的数组即最终启用的路由集合。
    func setEnabledRoutes(deviceID: String, routes: [String]) async throws {
        try await write(deviceID: deviceID, path: "routes", body: ["routes": routes])
    }

    func deleteDevice(deviceID: String) async throws {
        let token = try await accessToken()
        var request = URLRequest(url: deviceURL(deviceID))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await send(request)
        try validate(response)
    }

    private func deviceURL(_ deviceID: String, path: String? = nil) -> URL {
        let encoded = deviceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceID
        var raw = "https://api.tailscale.com/api/v2/device/\(encoded)"
        if let path { raw += "/\(path)" }
        return URL(string: raw)!
    }

    private func write(deviceID: String, path: String, body: [String: Any]) async throws {
        let token = try await accessToken()
        var request = URLRequest(url: deviceURL(deviceID, path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw TailscaleAPIError.decoding(error.localizedDescription)
        }
        let (_, response) = try await send(request)
        try validate(response)
    }

    // MARK: - Internals

    private func accessToken() async throws -> String {
        if let cachedToken, let tokenExpiry, tokenExpiry.timeIntervalSinceNow > 60 {
            return cachedToken
        }

        guard let clientID = KeychainStore.load(.tailscaleOAuthClientID),
              let clientSecret = KeychainStore.load(.tailscaleOAuthClientSecret),
              !clientID.isEmpty, !clientSecret.isEmpty else {
            throw TailscaleAPIError.notConfigured
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]
        // 凭据放 body，绝不进 URL/query（会被日志和代理记录）。
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await send(request)
        try validate(response)

        do {
            let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            cachedToken = token.access_token
            tokenExpiry = Date().addingTimeInterval(token.expires_in ?? 3600)
            return token.access_token
        } catch {
            throw TailscaleAPIError.decoding(error.localizedDescription)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw TailscaleAPIError.transport(error.localizedDescription)
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw TailscaleAPIError.unauthorized
        case 403: throw TailscaleAPIError.forbidden
        case 429: throw TailscaleAPIError.rateLimited
        default: throw TailscaleAPIError.http(http.statusCode)
        }
    }

    private func decodeDevices(_ data: Data) throws -> [TailnetDevice] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]

        func date(_ raw: String?) -> Date? {
            guard let raw, !raw.isEmpty else { return nil }
            return formatter.date(from: raw) ?? plainFormatter.date(from: raw)
        }

        do {
            let payload = try JSONDecoder().decode(DevicesResponse.self, from: data)
            return payload.devices.map { device in
                TailnetDevice(
                    id: device.id ?? device.nodeId ?? UUID().uuidString,
                    hostname: device.hostname ?? device.name ?? "unknown",
                    name: device.name ?? "",
                    addresses: device.addresses ?? [],
                    os: device.os ?? "unknown",
                    user: device.user ?? "",
                    clientVersion: device.clientVersion ?? "",
                    updateAvailable: device.updateAvailable ?? false,
                    authorized: device.authorized ?? true,
                    lastSeen: date(device.lastSeen),
                    expires: date(device.expires),
                    keyExpiryDisabled: device.keyExpiryDisabled ?? false,
                    tags: device.tags ?? [],
                    advertisedRoutes: device.advertisedRoutes ?? [],
                    enabledRoutes: device.enabledRoutes ?? [],
                    isExternal: device.isExternal ?? false
                )
            }
            .sorted { $0.hostname.localizedCaseInsensitiveCompare($1.hostname) == .orderedAscending }
        } catch {
            throw TailscaleAPIError.decoding(error.localizedDescription)
        }
    }
}
