import Foundation

@MainActor
class ConfigManager {
    static let shared = ConfigManager()
    
    private let fm = FileManager.default
    private let defaultBaseURL: URL
    
    var baseURL: URL {
        return defaultBaseURL
    }
    
    private init() {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        defaultBaseURL = appSupport.appendingPathComponent("PingMonitor", isDirectory: true)
        
        try? fm.createDirectory(at: defaultBaseURL, withIntermediateDirectories: true)
    }
    
    var hostsURL: URL { baseURL.appendingPathComponent("hosts.json") }
    var presetsURL: URL { baseURL.appendingPathComponent("presets.json") }
    var statsURL: URL { baseURL.appendingPathComponent("stats.json") }
    var settingsURL: URL { baseURL.appendingPathComponent("settings.json") }

    func listConfigFiles() -> [URL] {
        return [hostsURL, presetsURL, statsURL, settingsURL]
    }
    
    func save<T: Encodable>(_ data: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: url, options: .atomic)
        } catch {
            print("ConfigManager: Failed to save to \(url.lastPathComponent): \(error)")
        }
    }
    
    func load<T: Decodable>(from url: URL) -> T? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("ConfigManager: Failed to load from \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    // Migration helpers
    func migrateFromUserDefaults(hostsKey: String, presetsKey: String, statsKey: String) {
        let defaults = UserDefaults.standard
        
        if let data = defaults.data(forKey: hostsKey), !fm.fileExists(atPath: hostsURL.path) {
            try? data.write(to: hostsURL)
            print("ConfigManager: Migrated hosts from UserDefaults")
        }
        
        if let data = defaults.data(forKey: presetsKey), !fm.fileExists(atPath: presetsURL.path) {
            try? data.write(to: presetsURL)
            print("ConfigManager: Migrated presets from UserDefaults")
        }
        
        if let data = defaults.data(forKey: statsKey), !fm.fileExists(atPath: statsURL.path) {
            try? data.write(to: statsURL)
            print("ConfigManager: Migrated stats from UserDefaults")
        }
    }
}

// MARK: - AnyCodable
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) {
            value = x
        } else if let x = try? container.decode(Int.self) {
            value = x
        } else if let x = try? container.decode(Double.self) {
            value = x
        } else if let x = try? container.decode(String.self) {
            value = x
        } else if let x = try? container.decode([String: AnyCodable].self) {
            value = x.mapValues { $0.value }
        } else if let x = try? container.decode([AnyCodable].self) {
            value = x.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable: Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let x as Bool:
            try container.encode(x)
        case let x as Int:
            try container.encode(x)
        case let x as Double:
            try container.encode(x)
        case let x as String:
            try container.encode(x)
        case let x as [String: Any]:
            try container.encode(x.mapValues { AnyCodable($0) })
        case let x as [Any]:
            try container.encode(x.map { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable: Unsupported type")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
