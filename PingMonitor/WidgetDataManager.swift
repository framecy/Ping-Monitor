import Foundation
import WidgetKit

struct WidgetData: Codable {
    enum DisplayMode: String, Codable {
        case auto
        case specific
    }
    
    struct HostStatus: Codable, Identifiable {
        var id: String { name }
        let name: String
        let latency: Double
        let status: String // "green", "yellow", "red", "gray"
        let isRunning: Bool
    }
    
    let displayMode: DisplayMode
    let title: String
    let entries: [HostStatus]
    let lastUpdated: Date
    
    var debugMessage: String?
    var primaryHost: HostStatus? { entries.first }
}

struct WidgetDataManager {
    static let shared = WidgetDataManager()
    
    private let appGroupID = "group.com.pingmonitor.shared"
    private let userDefaultsKey = "widget_data_json"
    
    // MARK: - Primary: UserDefaults (suiteName) via App Group
    // This works when App Groups are properly configured with a valid Team ID.
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    // MARK: - Fallback: Direct file in widget container
    // Main app (non-sandboxed) writes to widget's sandbox container.
    // Widget (sandboxed) reads from its own Documents.
    
    private var fileURL: URL? {
        let fm = FileManager.default
        if let bundleID = Bundle.main.bundleIdentifier, bundleID == "com.pingmonitor.app.widget" {
            // Widget reads from its own Documents
            return fm.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("widget_data.json")
        } else {
            // Main app writes to widget's container
            let home = fm.homeDirectoryForCurrentUser
            return home.appendingPathComponent(
                "Library/Containers/com.pingmonitor.app.widget/Data/Documents/widget_data.json"
            )
        }
    }
    
    // MARK: - Secondary fallback: Shared temp location
    // If the widget container doesn't exist yet, use a shared temp folder
    
    private var sharedFileURL: URL {
        let fm = FileManager.default
        let sharedDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PingMonitor")
        try? fm.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        return sharedDir.appendingPathComponent("widget_data.json")
    }
    
    // MARK: - Save
    
    func save(_ data: WidgetData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        
        guard let jsonData = try? encoder.encode(data) else {
            print("WidgetDataManager: Failed to encode data")
            return
        }
        
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        // Strategy 1: App Group UserDefaults (most reliable when configured)
        if let defaults = sharedDefaults {
            defaults.set(jsonString, forKey: userDefaultsKey)
            defaults.synchronize()
        }
        
        // Strategy 2: Direct file to widget container
        if let url = fileURL {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try jsonData.write(to: url, options: .atomic)
            } catch {
                // Container doesn't exist yet — fall through to Strategy 3
                print("WidgetDataManager: Container write failed: \(error.localizedDescription)")
            }
        }
        
        // Strategy 3: Shared Application Support location (always writable)
        do {
            try jsonData.write(to: sharedFileURL, options: .atomic)
        } catch {
            print("WidgetDataManager: Shared file write failed: \(error.localizedDescription)")
        }
        
        // Trigger widget timeline refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Load
    
    func load() -> WidgetData? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        // Strategy 1: App Group UserDefaults
        if let defaults = sharedDefaults,
           let jsonString = defaults.string(forKey: userDefaultsKey),
           let jsonData = jsonString.data(using: .utf8),
           let data = try? decoder.decode(WidgetData.self, from: jsonData) {
            return data
        }
        
        // Strategy 2: Direct file (widget's own Documents)
        if let url = fileURL,
           let jsonData = try? Data(contentsOf: url),
           let data = try? decoder.decode(WidgetData.self, from: jsonData) {
            return data
        }
        
        // Strategy 3: Shared Application Support location
        if let jsonData = try? Data(contentsOf: sharedFileURL),
           let data = try? decoder.decode(WidgetData.self, from: jsonData) {
            return data
        }
        
        // Nothing found
        return WidgetData(
            displayMode: .auto,
            title: "No Data",
            entries: [],
            lastUpdated: Date(),
            debugMessage: "No data found. Bundle: \(Bundle.main.bundleIdentifier ?? "nil")"
        )
    }
}
