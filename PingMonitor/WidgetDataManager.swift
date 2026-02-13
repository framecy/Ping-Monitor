import Foundation

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
        
        // Extended statistics for high-density display
        var minLatency: Double?
        var maxLatency: Double?
        var avgLatency: Double?
        var packetLoss: Double?
    }
    
    let displayMode: DisplayMode
    let title: String
    let entries: [HostStatus]
    let lastUpdated: Date
    
    // Debug info to show on Widget if something goes wrong
    var debugMessage: String?
    
    // Legacy support / Single host compatibility (optional, but good for safety)
    var primaryHost: HostStatus? { entries.first }
}

struct WidgetDataManager {
    static let shared = WidgetDataManager()
    
    // Path to the Widget's container Documents directory.
    // Since the Main App is not sandboxed, it can write here.
    // The Widget is sandboxed, so it can read/write here (its own container).
    private var dataFileURL: URL? {
        let fileManager = FileManager.default
        
        // Check if we are running in the Main App or the Widget Extension
        if let bundleID = Bundle.main.bundleIdentifier, bundleID == "com.pingmonitor.app.widget" {
            // Widget Context (Sandboxed): Use local Documents directory
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("widget_data.json")
        } else {
            // Main App Context (Non-Sandboxed): Write to the Widget's Container
            let home = fileManager.homeDirectoryForCurrentUser
            return home.appendingPathComponent("Library/Containers/com.pingmonitor.app.widget/Data/Documents/widget_data.json")
        }
    }
    
    func save(_ data: WidgetData) {
        guard let url = dataFileURL else { return }
        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: url)
            
            // Only log if in Main App (LogManager might not be available/safe in Widget)
            if Bundle.main.bundleIdentifier != "com.pingmonitor.app.widget" {
                 print("WidgetDataManager: Saved to \(url.path)") // Will show in system logs
            }
        } catch {
             print("WidgetDataManager: Failed to save: \(error)")
        }
    }
    
    func load() -> WidgetData? {
        // If URL resolution fails, return a debug object immediately
        guard let url = dataFileURL else {
            return WidgetData(
                displayMode: .auto,
                title: "Path Error",
                entries: [],
                lastUpdated: Date(),
                debugMessage: "Err: dataFileURL is nil\nBundle: \(Bundle.main.bundleIdentifier ?? "nil")"
            )
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(WidgetData.self, from: data)
        } catch {
            // Return a dummy object with the error and path for debugging
            return WidgetData(
                displayMode: .auto,
                title: "Load Failed",
                entries: [],
                lastUpdated: Date(),
                debugMessage: "Err: \(error.localizedDescription)\nPath: \(url.path)"
            )
        }
    }
}
