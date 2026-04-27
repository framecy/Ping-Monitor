import SwiftUI
import UserNotifications
import ServiceManagement
import WidgetKit
import Combine
import Network

@main
struct PingMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.viewModel.stopAll()
    }
}

// MARK: - Statistics Model
struct HostStats: Codable, Identifiable {
    var id: UUID
    var hostId: UUID
    var totalPings: Int
    var successfulPings: Int
    var failedPings: Int
    var totalBytesSent: Int64
    var totalBytesReceived: Int64
    var minLatency: Double?
    var maxLatency: Double?
    var avgLatency: Double
    var latencyHistory: [LatencyPoint]
    var startTime: Date
    
    init(hostId: UUID) {
        self.id = UUID()
        self.hostId = hostId
        self.totalPings = 0
        self.successfulPings = 0
        self.failedPings = 0
        self.totalBytesSent = 0
        self.totalBytesReceived = 0
        self.minLatency = nil
        self.maxLatency = nil
        self.avgLatency = 0
        self.latencyHistory = []
        self.startTime = Date()
    }
    
    var packetLossRate: Double {
        guard totalPings > 0 else { return 0 }
        return Double(failedPings) / Double(totalPings) * 100
    }
    
    var successRate: Double {
        guard totalPings > 0 else { return 0 }
        return Double(successfulPings) / Double(totalPings) * 100
    }
    
    var totalTraffic: String {
        let total = totalBytesSent + totalBytesReceived
        return formatBytes(total)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct LatencyPoint: Codable, Identifiable {
    var id: UUID
    let timestamp: Date
    let latency: Double
    
    init(timestamp: Date, latency: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.latency = latency
    }
}

private final class ProbeResolutionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    func tryResolve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return false }
        resolved = true
        return true
    }
}

private final class ProbeFailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var failureReason: ProbeFailureReason?

    func set(_ reason: ProbeFailureReason?) {
        lock.lock()
        failureReason = reason
        lock.unlock()
    }

    func get() -> ProbeFailureReason? {
        lock.lock()
        defer { lock.unlock() }
        return failureReason
    }
}

enum ProbeFailureCategory: String, Sendable {
    case timeout
    case dnsFailure
    case noRoute
    case networkUnreachable
    case hostDown
    case connectionRefused
    case permissionDenied
    case processError
    case unknown
}

struct ProbeFailureReason: Sendable {
    let category: ProbeFailureCategory
    let detail: String?
}

enum ProbePathKind: String, Sendable {
    case direct
    case relay
    case unknown
}

struct ProbePathSnapshot: Sendable {
    let kind: ProbePathKind
    let endpoint: String?
}

enum ProbeOutcomeStatus: Sendable {
    case success
    case failure
}

struct HostProbeDiagnostic: Sendable {
    var lastCheckedAt: Date?
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var lastFailureReason: ProbeFailureReason?
    var lastPathSnapshot: ProbePathSnapshot?
    var lastRawMessage: String?
    var lastOutcome: ProbeOutcomeStatus?
}

enum NetworkQualityWindow: String, CaseIterable, Identifiable, Sendable {
    case oneMinute
    case fiveMinutes
    case oneHour

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 5 * 60
        case .oneHour:
            return 60 * 60
        }
    }
}

struct ProbeSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let latency: Double?
    let success: Bool
    let failureCategory: ProbeFailureCategory?
    let pathKind: ProbePathKind
}

struct QualityDimensionScores: Sendable {
    var latency: Int
    var stability: Int
    var path: Int
    var bandwidth: Int
    var resolution: Int
    var overlay: Int

    var average: Int {
        Int(round(Double(latency + stability + path + bandwidth + resolution + overlay) / 6.0))
    }
}

struct HostQualitySnapshot: Identifiable, Sendable {
    let id: UUID
    let hostId: UUID
    let hostName: String
    let window: NetworkQualityWindow
    let score: Int
    let dimensions: QualityDimensionScores
    let sampleCount: Int
    let currentLatency: Double?
    let averageLatency: Double?
    let p95Latency: Double?
    let p99Latency: Double?
    let jitter: Double
    let packetLoss: Double
    let availability: Double
    let spikeRate: Double
    let pathKind: ProbePathKind
    let pathFlapCount: Int
    let consecutiveFailures: Int
    let lastFailureText: String?
}

enum QualityEventSeverity: String, Sendable {
    case info
    case warning
    case critical
}

struct NetworkQualityEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let hostId: UUID?
    let hostName: String?
    let severity: QualityEventSeverity
    let title: String
    let detail: String
}

struct GlobalQualitySnapshot: Sendable {
    let window: NetworkQualityWindow
    let score: Int
    let dimensions: QualityDimensionScores
    let hostCount: Int
    let healthyHostCount: Int
    let degradedHostCount: Int
    let criticalHostCount: Int
    let averageP95Latency: Double?
    let averagePacketLoss: Double
    let averageJitter: Double
    let tunnelShare: Double
    let worstHosts: [HostQualitySnapshot]
    let recentEvents: [NetworkQualityEvent]
}

struct QualityTrendPoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let score: Double
    let averageLatency: Double
    let packetLoss: Double
}

@MainActor
extension ProbeFailureReason {
    func localizedDescription(using languageManager: LanguageManager = .shared) -> String {
        let base: String
        switch category {
        case .timeout:
            base = languageManager.t("diagnostics.failure.timeout")
        case .dnsFailure:
            base = languageManager.t("diagnostics.failure.dns")
        case .noRoute:
            base = languageManager.t("diagnostics.failure.no_route")
        case .networkUnreachable:
            base = languageManager.t("diagnostics.failure.network_unreachable")
        case .hostDown:
            base = languageManager.t("diagnostics.failure.host_down")
        case .connectionRefused:
            base = languageManager.t("diagnostics.failure.connection_refused")
        case .permissionDenied:
            base = languageManager.t("diagnostics.failure.permission_denied")
        case .processError:
            base = languageManager.t("diagnostics.failure.process_error")
        case .unknown:
            base = languageManager.t("diagnostics.failure.unknown")
        }

        guard let detail, !detail.isEmpty, category == .processError || category == .unknown else {
            return base
        }
        return "\(base): \(detail)"
    }
}

@MainActor
extension ProbePathSnapshot {
    func localizedDescription(using languageManager: LanguageManager = .shared) -> String {
        switch kind {
        case .direct:
            if let endpoint, !endpoint.isEmpty {
                return String(format: languageManager.t("diagnostics.path.direct_via"), endpoint)
            }
            return languageManager.t("diagnostics.path.direct")
        case .relay:
            if let endpoint, !endpoint.isEmpty {
                return String(format: languageManager.t("diagnostics.path.relay_via"), endpoint)
            }
            return languageManager.t("diagnostics.path.relay")
        case .unknown:
            return languageManager.t("diagnostics.path.unknown")
        }
    }
}

@MainActor
class LogManager: ObservableObject {
    static let shared = LogManager()
    @Published var logs: [LogEntry] = []
    private let maxLogs = 1000
    
    struct LogEntry: Identifiable, Codable {
        var id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String
        let host: String?
        
        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }
    
    enum LogLevel: String, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        
        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
    }
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info, host: String? = nil) {
        DispatchQueue.main.async {
            let entry = LogEntry(timestamp: Date(), level: level, message: message, host: host)
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
            
            print("[\(level.rawValue)] \(host != nil ? "[\(host!)] " : "")\(message)")
        }
    }
    
    func debug(_ message: String, host: String? = nil) {
        log(message, level: .debug, host: host)
    }
    
    func info(_ message: String, host: String? = nil) {
        log(message, level: .info, host: host)
    }
    
    func warning(_ message: String, host: String? = nil) {
        log(message, level: .warning, host: host)
    }
    
    func error(_ message: String, host: String? = nil) {
        log(message, level: .error, host: host)
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
    
    func exportToFile() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "PingMonitor_Logs_\(formatter.string(from: Date())).txt"
        
        let content = logs.map { entry in
            "[\(entry.formattedTimestamp)] [\(entry.level.rawValue)] \(entry.host != nil ? "[\(entry.host!)] " : "")\(entry.message)"
        }.joined(separator: "\n")
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            self.error("Failed to export logs: \(error)")
            return nil
        }
    }

    func exportHostLogs(for hostName: String) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(hostName.replacingOccurrences(of: " ", with: "_"))_Logs_\(formatter.string(from: Date())).txt"
        
        let hostLogs = logs.filter { $0.host == hostName }
        let content = hostLogs.map { entry in
            "[\(entry.formattedTimestamp)] [\(entry.level.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            self.error("Failed to export host logs: \(error)")
            return nil
        }
    }
}

@MainActor
class PingMonitorViewModel: ObservableObject {
    @Published var hosts: [HostConfig] = []
    @Published var presets: [HostPreset] = []
    @Published var isRunning = false
    @Published var selectedHostId: UUID?
    @Published var autoStart = false
    @Published var showLatencyInMenu = true
    @Published var showLabelsInMenu = true
    @Published var notificationEnabled = true
    @Published var notificationType = "system"
    @Published var barkURL = ""
    @Published var pingInterval: Double = 5.0
    @Published var logLevel: LogManager.LogLevel = .info
    @Published var statusBarDisplayMode: StatusBarDisplayMode = .first
    @Published var hostStats: [UUID: HostStats] = [:]
    @Published var hostDiagnostics: [UUID: HostProbeDiagnostic] = [:]
    @Published var probeSamples: [UUID: [ProbeSample]] = [:]
    @Published var qualityEvents: [NetworkQualityEvent] = []
    @Published var selectedStatHost: HostConfig?
    @Published var widgetDisplayMode: String = "auto"
    @Published var widgetSelectedHostId: String = ""
    @Published var showSpeedInMenu: Bool = false
    @Published var speedUnit: String = "auto"  // "auto", "KB", "MB"
    @Published var statusBarWidth: Int = 160    // total status bar item width in pt
    @Published var statusBarFontSize: Int = 9
    @Published var statusBarFontWeight: String = "medium" // "regular", "medium", "bold"
    @Published var showIconInMenu: Bool = true
    @Published var appAppearance: String = "system" // "system", "light", "dark"
    
    var statusBarController: StatusBarController?
    private var pingProcesses: [UUID: Process] = [:]
    private var tcpProbeTimers: [UUID: DispatchSourceTimer] = [:]
    private let defaults = UserDefaults.standard
    private var consecutiveFailures: [UUID: Int] = [:]
    private let maxFailuresBeforeOffline = 3
    private let maxProbeSamplesPerHost = 4096
    private let maxQualityEventCount = 120
    
    // Batch update properties
    private var batchUpdateTimer: AnyCancellable?
    private struct PendingUpdate: Sendable {
        let hostId: UUID
        let index: Int
        let latency: Double?
        let success: Bool
        let failureReason: ProbeFailureReason?
        let pathSnapshot: ProbePathSnapshot?
        let rawMessage: String?
        let checkedAt: Date
    }
    private struct TCPProbeResult: Sendable {
        let latency: Double?
        let failureReason: ProbeFailureReason?
    }
    private let pendingUpdatesBuffer = LockedArray<PendingUpdate>()
    private var lastWidgetSync = Date.distantPast
    private let widgetSyncInterval: TimeInterval = 5.0

    init() {
        loadSettings()
        setupAutoStart()
        setupKeepAliveListener()
        startBatchUpdateTimer()
        LogManager.shared.info("PingMonitor initialized")
    }

    private func startBatchUpdateTimer() {
        batchUpdateTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performBatchUpdate()
            }
    }

    private var keepAliveCancellables = Set<AnyCancellable>()
    
    private func setupKeepAliveListener() {
        NotificationCenter.default.publisher(for: .keepAliveStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let interface = notification.userInfo?["interface"] as? String,
                   let active = notification.userInfo?["active"] as? Bool {
                    self.handleKeepAliveChange(interface: interface, active: active)
                }
            }
            .store(in: &keepAliveCancellables)
    }
    
    private func handleKeepAliveChange(interface: String, active: Bool) {
        guard isRunning else { return }
        
        // Find all Tailscale nodes and restart their ping processes with the new interval
        for i in hosts.indices {
            if hosts[i].isTailscaleNode {
                // Restart ping process to apply new interval
                stopPingProcess(for: hosts[i].id)
                startPingProcess(for: hosts[i], at: i)
            }
        }
    }

    func loadSettings() {
        if let savedHosts: [HostConfig] = ConfigManager.shared.load(from: ConfigManager.shared.hostsURL) {
            hosts = savedHosts
        } else if let data = defaults.data(forKey: "hosts"),
                  let savedHosts = try? JSONDecoder().decode([HostConfig].self, from: data) {
            hosts = savedHosts
        } else {
            hosts = [HostConfig(name: "Google DNS", address: "8.8.8.8")]
        }
        
        if let savedPresets: [HostPreset] = ConfigManager.shared.load(from: ConfigManager.shared.presetsURL) {
            presets = savedPresets
        } else if let presetsData = defaults.data(forKey: "presets"),
                  let savedPresets = try? JSONDecoder().decode([HostPreset].self, from: presetsData) {
            presets = savedPresets
        } else {
            presets = [
                HostPreset(name: "Google DNS", address: "8.8.8.8"),
                HostPreset(name: "Cloudflare", address: "1.1.1.1"),
                HostPreset(name: "百度", address: "www.baidu.com"),
                HostPreset(name: "淘宝", address: "www.taobao.com")
            ]
        }
        
        if let savedStats: [String: HostStats] = ConfigManager.shared.load(from: ConfigManager.shared.statsURL) {
            var stats: [UUID: HostStats] = [:]
            for (key, value) in savedStats {
                if let uuid = UUID(uuidString: key) {
                    stats[uuid] = value
                }
            }
            hostStats = stats
        } else if let statsData = defaults.data(forKey: "hostStats"),
                  let savedStats = try? JSONDecoder().decode([String: HostStats].self, from: statsData) {
            var stats: [UUID: HostStats] = [:]
            for (key, value) in savedStats {
                if let uuid = UUID(uuidString: key) {
                    stats[uuid] = value
                }
            }
            hostStats = stats
        }
        
        // Also load general settings from settings.json if exists
        let settingsEnc: [String: AnyCodable]? = ConfigManager.shared.load(from: ConfigManager.shared.settingsURL)
        let settings = settingsEnc?.mapValues { $0.value }
        
        autoStart = (settings?["autoStart"] as? Bool) ?? defaults.bool(forKey: "autoStart")
        showLatencyInMenu = (settings?["showLatencyInMenu"] as? Bool) ?? defaults.bool(forKey: "showLatencyInMenu", defaultValue: true)
        showLabelsInMenu = (settings?["showLabelsInMenu"] as? Bool) ?? defaults.bool(forKey: "showLabelsInMenu", defaultValue: true)
        notificationEnabled = (settings?["notificationEnabled"] as? Bool) ?? defaults.bool(forKey: "notificationEnabled", defaultValue: true)
        notificationType = (settings?["notificationType"] as? String) ?? (defaults.string(forKey: "notificationType") ?? "system")
        barkURL = (settings?["barkURL"] as? String) ?? (defaults.string(forKey: "barkURL") ?? "")
        if let val = settings?["pingInterval"] {
            if let d = val as? Double {
                pingInterval = d
            } else if let i = val as? Int {
                pingInterval = Double(i)
            }
        } else {
            pingInterval = defaults.double(forKey: "pingInterval")
        }
        if pingInterval == 0 { pingInterval = 5.0 }
        
        if let levelRaw = (settings?["logLevel"] as? String) ?? defaults.string(forKey: "logLevel"),
           let level = LogManager.LogLevel(rawValue: levelRaw) {
            logLevel = level
        }
        
        if let modeRaw = (settings?["statusBarDisplayMode"] as? String) ?? defaults.string(forKey: "statusBarDisplayMode"),
           let mode = StatusBarDisplayMode(rawValue: modeRaw) {
            statusBarDisplayMode = mode
        }
        
        widgetDisplayMode = (settings?["widgetDisplayMode"] as? String) ?? (defaults.string(forKey: "widgetDisplayMode") ?? "auto")
        widgetSelectedHostId = (settings?["widgetSelectedHostId"] as? String) ?? (defaults.string(forKey: "widgetSelectedHostId") ?? "")
        showSpeedInMenu = (settings?["showSpeedInMenu"] as? Bool) ?? defaults.bool(forKey: "showSpeedInMenu")
        speedUnit = (settings?["speedUnit"] as? String) ?? (defaults.string(forKey: "speedUnit") ?? "auto")
        
        let savedWidth = (settings?["statusBarWidth"] as? Int) ?? defaults.integer(forKey: "statusBarWidth")
        statusBarWidth = savedWidth == 0 ? 160 : savedWidth
        
        let savedSize = (settings?["statusBarFontSize"] as? Int) ?? defaults.integer(forKey: "statusBarFontSize")
        statusBarFontSize = savedSize == 0 ? 9 : savedSize
        
        statusBarFontWeight = (settings?["statusBarFontWeight"] as? String) ?? (defaults.string(forKey: "statusBarFontWeight") ?? "medium")
        
        if let iconSaved = (settings?["showIconInMenu"] as? Bool) ?? (defaults.object(forKey: "showIconInMenu") as? Bool) {
            showIconInMenu = iconSaved
        } else {
            showIconInMenu = true
        }
        
        appAppearance = (settings?["appAppearance"] as? String) ?? (defaults.string(forKey: "appAppearance") ?? "system")
        
        LogManager.shared.info("Settings loaded: \(hosts.count) hosts, \(presets.count) presets")
    }

    func saveSettings() {
        ConfigManager.shared.save(hosts, to: ConfigManager.shared.hostsURL)
        ConfigManager.shared.save(presets, to: ConfigManager.shared.presetsURL)
        
        var statsDict: [String: HostStats] = [:]
        for (key, value) in hostStats {
            statsDict[key.uuidString] = value
        }
        ConfigManager.shared.save(statsDict, to: ConfigManager.shared.statsURL)
        
        let settings: [String: AnyCodable] = [
            "autoStart": AnyCodable(autoStart),
            "showLatencyInMenu": AnyCodable(showLatencyInMenu),
            "showLabelsInMenu": AnyCodable(showLabelsInMenu),
            "notificationEnabled": AnyCodable(notificationEnabled),
            "notificationType": AnyCodable(notificationType),
            "barkURL": AnyCodable(barkURL),
            "pingInterval": AnyCodable(pingInterval),
            "logLevel": AnyCodable(logLevel.rawValue),
            "statusBarDisplayMode": AnyCodable(statusBarDisplayMode.rawValue),
            "widgetDisplayMode": AnyCodable(widgetDisplayMode),
            "widgetSelectedHostId": AnyCodable(widgetSelectedHostId),
            "showSpeedInMenu": AnyCodable(showSpeedInMenu),
            "speedUnit": AnyCodable(speedUnit),
            "statusBarWidth": AnyCodable(statusBarWidth),
            "statusBarFontSize": AnyCodable(statusBarFontSize),
            "statusBarFontWeight": AnyCodable(statusBarFontWeight),
            "showIconInMenu": AnyCodable(showIconInMenu),
            "appAppearance": AnyCodable(appAppearance)
        ]
        ConfigManager.shared.save(settings, to: ConfigManager.shared.settingsURL)
        
        // Also keep UserDefaults in sync for now (secondary backup)
        if let data = try? JSONEncoder().encode(hosts) {
            defaults.set(data, forKey: "hosts")
        }
        if let presetData = try? JSONEncoder().encode(presets) {
            defaults.set(presetData, forKey: "presets")
        }
        if let statsData = try? JSONEncoder().encode(statsDict) {
            defaults.set(statsData, forKey: "hostStats")
        }
        
        defaults.set(autoStart, forKey: "autoStart")
        defaults.set(showLatencyInMenu, forKey: "showLatencyInMenu")
        defaults.set(showLabelsInMenu, forKey: "showLabelsInMenu")
        defaults.set(notificationEnabled, forKey: "notificationEnabled")
        defaults.set(notificationType, forKey: "notificationType")
        defaults.set(barkURL, forKey: "barkURL")
        defaults.set(pingInterval, forKey: "pingInterval")
        defaults.set(logLevel.rawValue, forKey: "logLevel")
        defaults.set(statusBarDisplayMode.rawValue, forKey: "statusBarDisplayMode")
        defaults.set(widgetDisplayMode, forKey: "widgetDisplayMode")
        defaults.set(widgetSelectedHostId, forKey: "widgetSelectedHostId")
        defaults.set(showSpeedInMenu, forKey: "showSpeedInMenu")
        defaults.set(speedUnit, forKey: "speedUnit")
        defaults.set(statusBarWidth, forKey: "statusBarWidth")
        defaults.set(statusBarFontSize, forKey: "statusBarFontSize")
        defaults.set(statusBarFontWeight, forKey: "statusBarFontWeight")
        defaults.set(showIconInMenu, forKey: "showIconInMenu")
        defaults.set(appAppearance, forKey: "appAppearance")
    }

    func setupAutoStart() {
        if autoStart {
            startAll()
        }
    }

    func toggleAutoStart(_ enabled: Bool) {
        autoStart = enabled
        saveSettings()

        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                LogManager.shared.info("Auto-start enabled")
            } else {
                try service.unregister()
                LogManager.shared.info("Auto-start disabled")
            }
        } catch {
            LogManager.shared.error("Failed to toggle auto-start: \(error)")
        }
    }

    func startAll() {
        LogManager.shared.info("Starting all monitors")
        isRunning = true
        
        for i in hosts.indices {
            if !hosts[i].isPaused {
                startPingProcess(for: hosts[i], at: i)
            }
        }
        
        syncToWidget()
    }

    func stopAll() {
        LogManager.shared.info("Stopping all monitors")
        
        for (hostId, _) in pingProcesses {
            stopPingProcess(for: hostId)
        }
        for (hostId, _) in tcpProbeTimers {
            stopPingProcess(for: hostId)
        }
        pingProcesses.removeAll()
        tcpProbeTimers.removeAll()
        
        isRunning = false
        for i in hosts.indices {
            hosts[i].isChecking = false
        }
        syncToWidget()
    }

    func toggle() {
        isRunning ? stopAll() : startAll()
    }
    
    func stopPingProcess(for hostId: UUID) {
        if let process = pingProcesses[hostId] {
            let pid = process.processIdentifier
            if process.isRunning {
                process.terminate()
                kill(pid, SIGTERM)
                kill(pid, SIGKILL)
                LogManager.shared.debug("Terminated ping process (PID \(pid)) for host: \(hostId)")
            }
            pingProcesses.removeValue(forKey: hostId)
        }
        if let timer = tcpProbeTimers[hostId] {
            timer.setEventHandler {}
            timer.cancel()
            tcpProbeTimers.removeValue(forKey: hostId)
            LogManager.shared.debug("Stopped TCP probe timer for host: \(hostId)")
        }
        if let idx = hosts.firstIndex(where: { $0.id == hostId }) {
            hosts[idx].isChecking = false
        }
    }
    
    func togglePing(for hostId: UUID) {
        if let index = hosts.firstIndex(where: { $0.id == hostId }) {
            hosts[index].isPaused.toggle()
            let isPaused = hosts[index].isPaused
            saveSettings()
            
            if isPaused {
                stopPingProcess(for: hostId)
            } else if isRunning {
                startPingProcess(for: hosts[index], at: index)
            }
        }
    }
    
    func exportStats(for hostId: UUID) {
        let statsList = [hostId].compactMap { id -> (HostConfig, HostStats)? in
             guard let h = hosts.first(where: { $0.id == id }), let s = hostStats[id] else { return nil }
             return (h, s)
        }
        exportStatsData(data: statsList, fileName: "ping_stats_\(statsList.first?.0.name ?? "host").csv")
    }

    func exportAllStats() {
        let statsList = hosts.compactMap { h -> (HostConfig, HostStats)? in
            guard let s = hostStats[h.id] else { return nil }
            return (h, s)
        }
        exportStatsData(data: statsList, fileName: "ping_stats_all.csv")
    }

    private func exportStatsData(data: [(HostConfig, HostStats)], fileName: String) {
        var csv = "HostName,Address,TotalPings,Success,Failed,MinLatency,MaxLatency,AvgLatency,BytesSent,BytesReceived\n"
        for (h, s) in data {
            csv += "\"\(h.name)\",\"\(h.address)\",\(s.totalPings),\(s.successfulPings),\(s.failedPings),\(s.minLatency ?? 0),\(s.maxLatency ?? 0),\(s.avgLatency),\(s.totalBytesSent),\(s.totalBytesReceived)\n"
        }
        
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = fileName
            panel.begin { result in
                if result == .OK, let url = panel.url {
                    do {
                        try csv.write(to: url, atomically: true, encoding: .utf8)
                        LogManager.shared.info("Exported stats to \(url.path)")
                    } catch {
                        LogManager.shared.error("Failed to export stats: \(error)")
                    }
                }
            }
        }
    }
    
    func resetStats(for hostId: UUID) {
        hostStats[hostId] = HostStats(hostId: hostId)
        probeSamples[hostId] = []
        saveSettings()
        LogManager.shared.info("Reset stats for host: \(hostId)")
    }
    
    func resetAllStats() {
        hostStats.removeAll()
        probeSamples.removeAll()
        for host in hosts {
            hostStats[host.id] = HostStats(hostId: host.id)
        }
        saveSettings()
        LogManager.shared.info("Reset all stats")
    }
    
    // MARK: - Batch Updates
    
    private func performBatchUpdate() {
        let updates = pendingUpdatesBuffer.values
        guard !updates.isEmpty else { return }
        pendingUpdatesBuffer.clear()
        
        // Use a set to track which hosts were updated to update status bar only once
        var updatedHostIds = Set<UUID>()
        
        for update in updates {
            guard update.index < hosts.count && hosts[update.index].id == update.hostId else { continue }
            
            let hostId = update.hostId
            let index = update.index
            let latency = update.latency
            let success = update.success
            let effectivePath = update.pathSnapshot ?? hostDiagnostics[hostId]?.lastPathSnapshot

            recordProbeSample(
                for: hostId,
                checkedAt: update.checkedAt,
                latency: latency,
                success: success,
                failureReason: update.failureReason,
                pathSnapshot: effectivePath
            )

            updateProbeDiagnostic(
                for: hostId,
                checkedAt: update.checkedAt,
                success: success,
                failureReason: update.failureReason,
                pathSnapshot: effectivePath,
                rawMessage: update.rawMessage
            )
            
            if success, let lat = latency {
                self.consecutiveFailures[hostId] = 0
                self.hosts[index].lastLatency = lat
                self.hosts[index].isReachable = true
                self.hosts[index].isChecking = false
                
                self.updateStatsInternal(for: hostId, latency: lat, success: true)
                
                if self.notificationEnabled {
                    self.checkNotification(host: self.hosts[index])
                }
            } else {
                let fails = (self.consecutiveFailures[hostId] ?? 0) + 1
                self.consecutiveFailures[hostId] = fails
                self.hosts[index].isChecking = false
                
                self.updateStatsInternal(for: hostId, latency: nil, success: false)
                
                if fails >= self.maxFailuresBeforeOffline {
                    self.hosts[index].isReachable = false
                    if self.notificationEnabled {
                        self.checkNotification(host: self.hosts[index])
                    }
                }
            }
            updatedHostIds.insert(hostId)
        }
        
        // Throttled widget sync
        if Date().timeIntervalSince(lastWidgetSync) >= widgetSyncInterval {
            lastWidgetSync = Date()
            syncToWidget()
        }
        
        updateStatusBarDisplay()
    }
    
    private func updateStatsInternal(for hostId: UUID, latency: Double?, success: Bool) {
        if hostStats[hostId] == nil {
            hostStats[hostId] = HostStats(hostId: hostId)
        }
        
        var stats = hostStats[hostId]!
        stats.totalPings += 1
        
        // Estimate bytes: ICMP packet ~64 bytes sent, ~64 bytes received
        stats.totalBytesSent += 64
        stats.totalBytesReceived += 64
        
        if success, let lat = latency {
            stats.successfulPings += 1
            
            if stats.minLatency == nil || lat < stats.minLatency! {
                stats.minLatency = lat
            }
            if stats.maxLatency == nil || lat > stats.maxLatency! {
                stats.maxLatency = lat
            }
            
            // Update rolling average
            let oldAvg = stats.avgLatency
            let count = Double(stats.successfulPings)
            stats.avgLatency = oldAvg + (lat - oldAvg) / count
            
            // Add to history (keep last 60 points instead of 100 for memory and CPU optimization)
            stats.latencyHistory.append(LatencyPoint(timestamp: Date(), latency: lat))
            if stats.latencyHistory.count > 60 {
                stats.latencyHistory.removeFirst()
            }
        } else {
            stats.failedPings += 1
        }
        
        hostStats[hostId] = stats
    }

    private func recordProbeSample(for hostId: UUID,
                                   checkedAt: Date,
                                   latency: Double?,
                                   success: Bool,
                                   failureReason: ProbeFailureReason?,
                                   pathSnapshot: ProbePathSnapshot?) {
        var samples = probeSamples[hostId] ?? []
        samples.append(
            ProbeSample(
                timestamp: checkedAt,
                latency: latency,
                success: success,
                failureCategory: failureReason?.category,
                pathKind: pathSnapshot?.kind ?? .unknown
            )
        )

        let cutoff = checkedAt.addingTimeInterval(-2 * 60 * 60)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > maxProbeSamplesPerHost {
            samples.removeFirst(samples.count - maxProbeSamplesPerHost)
        }
        probeSamples[hostId] = samples
    }

    private func appendQualityEvent(_ event: NetworkQualityEvent) {
        qualityEvents.insert(event, at: 0)
        if qualityEvents.count > maxQualityEventCount {
            qualityEvents.removeLast(qualityEvents.count - maxQualityEventCount)
        }
    }

    private func qualityEvent(for hostId: UUID?,
                              severity: QualityEventSeverity,
                              title: String,
                              detail: String) -> NetworkQualityEvent {
        let hostName = hostId.flatMap { id in
            hosts.first(where: { $0.id == id })?.name
        }
        return NetworkQualityEvent(
            timestamp: Date(),
            hostId: hostId,
            hostName: hostName,
            severity: severity,
            title: title,
            detail: detail
        )
    }

    private func updateProbeDiagnostic(for hostId: UUID,
                                       checkedAt: Date,
                                       success: Bool,
                                       failureReason: ProbeFailureReason?,
                                       pathSnapshot: ProbePathSnapshot?,
                                       rawMessage: String?) {
        let previousDiagnostic = hostDiagnostics[hostId]
        var diagnostic = previousDiagnostic ?? HostProbeDiagnostic()
        diagnostic.lastCheckedAt = checkedAt
        diagnostic.lastRawMessage = rawMessage

        if let pathSnapshot {
            diagnostic.lastPathSnapshot = pathSnapshot
        }

        if success {
            diagnostic.lastOutcome = .success
            diagnostic.lastSuccessAt = checkedAt
            diagnostic.lastFailureReason = nil
        } else {
            diagnostic.lastOutcome = .failure
            diagnostic.lastFailureAt = checkedAt
            diagnostic.lastFailureReason = failureReason ?? ProbeFailureReason(category: .unknown, detail: rawMessage)
        }

        hostDiagnostics[hostId] = diagnostic

        if let previousPath = previousDiagnostic?.lastPathSnapshot,
           let nextPath = pathSnapshot,
           (previousPath.kind != nextPath.kind || previousPath.endpoint != nextPath.endpoint) {
            appendQualityEvent(
                qualityEvent(
                    for: hostId,
                    severity: nextPath.kind == .relay ? .warning : .info,
                    title: nextPath.kind == .relay ? LanguageManager.shared.t("quality_event.path_relay") : LanguageManager.shared.t("quality_event.path_updated"),
                    detail: nextPath.localizedDescription(using: .shared)
                )
            )
        }

        if success, previousDiagnostic?.lastOutcome == .failure {
            appendQualityEvent(
                qualityEvent(
                    for: hostId,
                    severity: .info,
                    title: LanguageManager.shared.t("quality_event.host_recovered"),
                    detail: LanguageManager.shared.t("quality_event.host_recovered_detail")
                )
            )
        } else if !success, previousDiagnostic?.lastOutcome != .failure {
            appendQualityEvent(
                qualityEvent(
                    for: hostId,
                    severity: failureReason?.category == .dnsFailure ? .warning : .critical,
                    title: LanguageManager.shared.t("quality_event.probe_failed"),
                    detail: (failureReason ?? ProbeFailureReason(category: .unknown, detail: rawMessage)).localizedDescription(using: .shared)
                )
            )
        }
    }

    private func samples(for hostId: UUID, within window: NetworkQualityWindow) -> [ProbeSample] {
        let cutoff = Date().addingTimeInterval(-window.duration)
        return (probeSamples[hostId] ?? []).filter { $0.timestamp >= cutoff }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(max(Int(ceil(Double(sorted.count) * fraction)) - 1, 0), sorted.count - 1)
        return sorted[index]
    }

    private func jitter(for latencies: [Double]) -> Double {
        guard latencies.count > 1 else { return 0 }
        let diffs = zip(latencies.dropFirst(), latencies).map { abs($0 - $1) }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    func qualitySnapshot(for host: HostConfig, window: NetworkQualityWindow = .fiveMinutes) -> HostQualitySnapshot {
        let samples = samples(for: host.id, within: window)
        let latencyValues = samples.compactMap(\.latency)
        let successCount = samples.filter(\.success).count
        let sampleCount = samples.count
        let failureCount = sampleCount - successCount
        let availability = sampleCount > 0 ? (Double(successCount) / Double(sampleCount) * 100.0) : 100.0
        let packetLoss = sampleCount > 0 ? (Double(failureCount) / Double(sampleCount) * 100.0) : 0.0
        let avgLatency = average(latencyValues)
        let p95Latency = percentile(latencyValues, fraction: 0.95)
        let p99Latency = percentile(latencyValues, fraction: 0.99)
        let jitterValue = jitter(for: latencyValues)

        let spikeThreshold = (avgLatency ?? 0) + max(25.0, jitterValue * 2.0)
        let spikeCount = latencyValues.filter { $0 > spikeThreshold && spikeThreshold > 0 }.count
        let spikeRate = latencyValues.isEmpty ? 0 : (Double(spikeCount) / Double(latencyValues.count) * 100.0)

        let pathKinds = samples
            .map(\.pathKind)
            .filter { $0 != .unknown }
        let currentPath = pathKinds.last ?? hostDiagnostics[host.id]?.lastPathSnapshot?.kind ?? .unknown
        let pathFlapCount = zip(pathKinds.dropFirst(), pathKinds).reduce(into: 0) { result, pair in
            if pair.0 != pair.1 {
                result += 1
            }
        }

        let latencyScore: Int = {
            let p95 = p95Latency ?? host.lastLatency ?? 0
            let base: Int
            switch p95 {
            case ..<50:
                base = 100
            case ..<100:
                base = 85
            case ..<200:
                base = 65
            case ..<350:
                base = 40
            default:
                base = 15
            }

            var score = base
            if jitterValue > 25 { score -= 20 }
            else if jitterValue > 10 { score -= 10 }
            if spikeRate > 15 { score -= 20 }
            else if spikeRate > 5 { score -= 10 }
            return max(0, min(100, score))
        }()

        let stabilityScore: Int = {
            let base: Int
            switch availability {
            case 99.5...:
                base = 100
            case 99.0..<99.5:
                base = 90
            case 97.0..<99.0:
                base = 75
            case 90.0..<97.0:
                base = 50
            default:
                base = 20
            }

            var score = base
            if packetLoss > 5 {
                score -= 35
            } else if packetLoss > 3 {
                score -= 20
            } else if packetLoss > 1 {
                score -= 10
            }

            if (consecutiveFailures[host.id] ?? 0) >= 3 {
                score = min(score, 45)
            }
            return max(0, min(100, score))
        }()

        let pathScore: Int = {
            var score: Int
            switch currentPath {
            case .direct:
                score = 100
            case .relay:
                score = 60
            case .unknown:
                score = 75
            }

            if pathFlapCount >= 2 {
                score -= 15
            }
            let routeFailures = samples.filter {
                $0.failureCategory == .noRoute || $0.failureCategory == .networkUnreachable
            }.count
            if routeFailures > 0 {
                score -= 20
            }
            return max(0, min(100, score))
        }()

        let bandwidthScore: Int = {
            let speedManager = NetworkSpeedManager.shared
            let physicalSpeed = speedManager.totalSpeedIn + speedManager.totalSpeedOut
            let tunnelSpeed = speedManager.tunnelSpeedIn + speedManager.tunnelSpeedOut
            let combined = physicalSpeed + tunnelSpeed
            guard combined > 0 else { return 80 }
            let tunnelShare = tunnelSpeed / combined
            if currentPath == .relay && tunnelShare > 0.7 {
                return 55
            }
            if tunnelShare > 0.7 {
                return 65
            }
            if combined > 50 * 1024 * 1024 {
                return 70
            }
            return 82
        }()

        let resolutionScore: Int = {
            let dnsFailures = samples.filter { $0.failureCategory == .dnsFailure }.count
            if dnsFailures == 0 {
                return 85
            }
            let ratio = sampleCount > 0 ? Double(dnsFailures) / Double(sampleCount) : 0
            if ratio > 0.2 {
                return 35
            }
            return 65
        }()

        let overlayScore: Int = {
            if host.isTailscaleNode {
                switch currentPath {
                case .direct:
                    return 92
                case .relay:
                    return 60
                case .unknown:
                    return 75
                }
            }
            if currentPath == .relay {
                return 65
            }
            return 85
        }()

        let dimensions = QualityDimensionScores(
            latency: latencyScore,
            stability: stabilityScore,
            path: pathScore,
            bandwidth: bandwidthScore,
            resolution: resolutionScore,
            overlay: overlayScore
        )

        var totalScore = Int(round(
            Double(latencyScore) * 0.30 +
            Double(stabilityScore) * 0.30 +
            Double(pathScore) * 0.15 +
            Double(bandwidthScore) * 0.10 +
            Double(resolutionScore) * 0.05 +
            Double(overlayScore) * 0.10
        ))

        if (consecutiveFailures[host.id] ?? 0) >= 3 {
            totalScore = min(totalScore, 49)
        }
        if availability < 90 {
            totalScore = min(totalScore, 59)
        }
        if samples.contains(where: { $0.failureCategory == .dnsFailure }) && host.address.range(of: #"^[0-9\.:]+$"#, options: .regularExpression) == nil {
            totalScore = min(totalScore, 45)
        }

        return HostQualitySnapshot(
            id: host.id,
            hostId: host.id,
            hostName: host.name,
            window: window,
            score: max(0, min(100, totalScore)),
            dimensions: dimensions,
            sampleCount: sampleCount,
            currentLatency: host.lastLatency,
            averageLatency: avgLatency,
            p95Latency: p95Latency,
            p99Latency: p99Latency,
            jitter: jitterValue,
            packetLoss: packetLoss,
            availability: availability,
            spikeRate: spikeRate,
            pathKind: currentPath,
            pathFlapCount: pathFlapCount,
            consecutiveFailures: consecutiveFailures[host.id] ?? 0,
            lastFailureText: hostDiagnostics[host.id]?.lastFailureReason?.localizedDescription(using: .shared)
        )
    }

    func qualitySnapshots(window: NetworkQualityWindow = .fiveMinutes) -> [HostQualitySnapshot] {
        hosts.map { qualitySnapshot(for: $0, window: window) }
    }

    func globalQualitySnapshot(window: NetworkQualityWindow = .fiveMinutes) -> GlobalQualitySnapshot {
        let snapshots = qualitySnapshots(window: window)
        let speedManager = NetworkSpeedManager.shared
        let tunnelSpeed = speedManager.tunnelSpeedIn + speedManager.tunnelSpeedOut
        let physicalSpeed = speedManager.totalSpeedIn + speedManager.totalSpeedOut
        let totalObservedSpeed = tunnelSpeed + physicalSpeed
        let tunnelShare = totalObservedSpeed > 0 ? tunnelSpeed / totalObservedSpeed : 0

        guard !snapshots.isEmpty else {
            return GlobalQualitySnapshot(
                window: window,
                score: 0,
                dimensions: QualityDimensionScores(latency: 0, stability: 0, path: 0, bandwidth: 0, resolution: 0, overlay: 0),
                hostCount: 0,
                healthyHostCount: 0,
                degradedHostCount: 0,
                criticalHostCount: 0,
                averageP95Latency: nil,
                averagePacketLoss: 0,
                averageJitter: 0,
                tunnelShare: tunnelShare,
                worstHosts: [],
                recentEvents: recentQualityEvents()
            )
        }

        let weightedSnapshots = snapshots.map { snapshot in
            (snapshot, max(snapshot.sampleCount, 1))
        }
        let totalWeight = weightedSnapshots.reduce(0) { $0 + $1.1 }
        let weightedScore = Double(weightedSnapshots.reduce(0) { $0 + ($1.0.score * $1.1) }) / Double(max(totalWeight, 1))
        let worstPenalty = Double(snapshots.sorted { $0.score < $1.score }.prefix(max(1, snapshots.count / 5)).reduce(0) { $0 + $1.score }) / Double(max(1, snapshots.count / 5))
        let overallScore = Int(round(weightedScore * 0.8 + worstPenalty * 0.2))

        let averageDimension = { (keyPath: KeyPath<QualityDimensionScores, Int>) -> Int in
            Int(round(Double(snapshots.reduce(0) { $0 + $1.dimensions[keyPath: keyPath] }) / Double(snapshots.count)))
        }

        let dimensions = QualityDimensionScores(
            latency: averageDimension(\.latency),
            stability: averageDimension(\.stability),
            path: averageDimension(\.path),
            bandwidth: averageDimension(\.bandwidth),
            resolution: averageDimension(\.resolution),
            overlay: averageDimension(\.overlay)
        )

        return GlobalQualitySnapshot(
            window: window,
            score: overallScore,
            dimensions: dimensions,
            hostCount: snapshots.count,
            healthyHostCount: snapshots.filter { $0.score >= 75 }.count,
            degradedHostCount: snapshots.filter { $0.score >= 40 && $0.score < 75 }.count,
            criticalHostCount: snapshots.filter { $0.score < 40 }.count,
            averageP95Latency: average(snapshots.compactMap(\.p95Latency)),
            averagePacketLoss: snapshots.reduce(0) { $0 + $1.packetLoss } / Double(snapshots.count),
            averageJitter: snapshots.reduce(0) { $0 + $1.jitter } / Double(snapshots.count),
            tunnelShare: tunnelShare,
            worstHosts: Array(snapshots.sorted { $0.score < $1.score }.prefix(5)),
            recentEvents: recentQualityEvents()
        )
    }

    func qualityTrend(window: NetworkQualityWindow = .fiveMinutes) -> [QualityTrendPoint] {
        let bucketInterval: TimeInterval
        switch window {
        case .oneMinute:
            bucketInterval = 5
        case .fiveMinutes:
            bucketInterval = 15
        case .oneHour:
            bucketInterval = 60
        }

        let cutoff = Date().addingTimeInterval(-window.duration)
        let allSamples = probeSamples.values
            .flatMap { $0 }
            .filter { $0.timestamp >= cutoff }

        guard !allSamples.isEmpty else { return [] }

        let grouped = Dictionary(grouping: allSamples) { sample -> Date in
            let seconds = floor(sample.timestamp.timeIntervalSince1970 / bucketInterval) * bucketInterval
            return Date(timeIntervalSince1970: seconds)
        }

        return grouped.keys.sorted().compactMap { bucket in
            guard let bucketSamples = grouped[bucket], !bucketSamples.isEmpty else { return nil }
            let latencies = bucketSamples.compactMap(\.latency)
            let avgLatency = average(latencies) ?? 0
            let failureCount = bucketSamples.filter { !$0.success }.count
            let loss = Double(failureCount) / Double(bucketSamples.count) * 100.0

            var score = 100.0
            if avgLatency > 200 {
                score -= 35
            } else if avgLatency > 100 {
                score -= 20
            } else if avgLatency > 50 {
                score -= 10
            }
            score -= min(loss * 4.0, 45.0)

            return QualityTrendPoint(
                timestamp: bucket,
                score: max(0, min(100, score)),
                averageLatency: avgLatency,
                packetLoss: loss
            )
        }
    }

    func recentQualityEvents(limit: Int = 8) -> [NetworkQualityEvent] {
        Array(qualityEvents.prefix(limit))
    }
    
    /// Legacy method kept for backward compatibility if needed synchronously
    private func updateStats(for hostId: UUID, latency: Double?, success: Bool) {
        updateStatsInternal(for: hostId, latency: latency, success: success)
    }
    
    func startPingProcess(for host: HostConfig, at index: Int) {
        guard index < hosts.count else { return }
        if host.isPaused { return }
        if host.probeMode == .tcp {
            startTCPProbe(for: host, at: index)
            return
        }
        
        let hostName = host.name
        let address = host.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let customCommand = host.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostId = host.id
        let tailscaleCLIPath = tailscaleProbeCLIPath(for: host, address: address, customCommand: customCommand)
        let isTailscaleProbe = tailscaleCLIPath != nil
        
        // CRITICAL: Prevent spawning a new ping if one is already running and tracked
        if let existing = pingProcesses[hostId], existing.isRunning {
             LogManager.shared.debug("Ping process already running for \(hostName), skipping spawn.")
             return
        }
        
        let interval = (pingInterval.truncatingRemainder(dividingBy: 1.0) == 0 ? String(format: "%.0f", pingInterval) : String(format: "%.1f", pingInterval))
        
        var commandString: String
        if customCommand.isEmpty {
            if let cli = tailscaleCLIPath {
                // Use JSON output for Tailscale probes so we can classify failures and extract direct/relay path details.
                commandString = "while true; do \(cli) ping --json --c=1 \(address); sleep \(interval); done"
            } else {
                commandString = "ping -i \(interval) \(address)"
            }
        } else {
            var result = customCommand.replacingOccurrences(of: "$address", with: address)
                                      .replacingOccurrences(of: "${address}", with: address)
            
            // 如果用户明确使用了占位符，则信任其命令结构
            // 如果未使用占位符，且命令中不包含地址，则自动追加
            let usedPlaceholder = customCommand.contains("$address") || customCommand.contains("${address}")
            
            if !usedPlaceholder && !result.contains(address) {
                result += " \(address)"
            }
            commandString = result
        }
        
        LogManager.shared.info("Starting continuous ping: \(commandString)", host: hostName)
        
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        if isTailscaleProbe {
            process.arguments = ["-c", commandString]
        } else {
            process.arguments = ["-c", "exec " + commandString]
        }
        
        pingProcesses[hostId] = process
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }
            
            // Move parsing to background immediately
            Task.detached(priority: .background) { [weak self] in
                output.enumerateLines { line, _ in
                    self?.parsePingLine(line, hostId: hostId, index: index, hostName: hostName, isTailscaleProbe: isTailscaleProbe)
                }
            }
        }
        
        do {
            try process.run()
            hosts[index].isChecking = true
            LogManager.shared.debug("Ping process started for \(hostName)", host: hostName)
        } catch {
            LogManager.shared.error("Failed to start ping: \(error)", host: hostName)
            hosts[index].isChecking = false
            hosts[index].isReachable = false
            updateProbeDiagnostic(
                for: hostId,
                checkedAt: Date(),
                success: false,
                failureReason: ProbeFailureReason(category: .processError, detail: error.localizedDescription),
                pathSnapshot: nil,
                rawMessage: error.localizedDescription
            )
        }
        
        process.terminationHandler = { [weak self] process in
            let terminatedPID = process.processIdentifier
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let idx = self.hosts.firstIndex(where: { $0.id == hostId }) {
                    self.hosts[idx].isChecking = false
                    if process.terminationStatus != 0 {
                        self.hosts[idx].isReachable = false
                    }
                }
                
                // CRITICAL: Only remove if the current tracked process is the one that just terminated!
                if self.pingProcesses[hostId]?.processIdentifier == terminatedPID {
                    self.pingProcesses.removeValue(forKey: hostId)
                }
            }
        }
    }

    private func tailscaleProbeCLIPath(for host: HostConfig, address: String, customCommand: String) -> String? {
        guard customCommand.isEmpty, let cli = TailscaleManager.shared.cliPath else { return nil }
        guard host.isTailscaleNode || isKnownTailscaleNodeAddress(address) else { return nil }
        return cli
    }

    private func isKnownTailscaleNodeAddress(_ address: String) -> Bool {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAddress.isEmpty else { return false }

        let tailscale = TailscaleManager.shared
        let suffix = tailscale.magicDNSSuffix.lowercased()

        return tailscale.nodes.contains { node in
            let hostname = node.hostname.lowercased()
            if node.tailscaleIP.lowercased() == normalizedAddress { return true }
            if hostname == normalizedAddress { return true }
            if !suffix.isEmpty, "\(hostname).\(suffix)" == normalizedAddress { return true }
            return false
        }
    }
    
    nonisolated private func parsePingLine(_ line: String, hostId: UUID, index: Int, hostName: String, isTailscaleProbe: Bool) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }

        if isTailscaleProbe,
           let data = trimmedLine.data(using: .utf8),
           let response = try? JSONDecoder().decode(TailscalePingResponse.self, from: data) {
            let pathSnapshot = extractTailscalePathSnapshot(from: response)

            if let err = response.Err, !err.isEmpty {
                pendingUpdatesBuffer.append(
                    PendingUpdate(
                        hostId: hostId,
                        index: index,
                        latency: nil,
                        success: false,
                        failureReason: classifyFailureReason(from: err) ?? ProbeFailureReason(category: .unknown, detail: err),
                        pathSnapshot: pathSnapshot,
                        rawMessage: err,
                        checkedAt: Date()
                    )
                )
                return
            }

            if let latencySeconds = response.LatencySeconds {
                pendingUpdatesBuffer.append(
                    PendingUpdate(
                        hostId: hostId,
                        index: index,
                        latency: latencySeconds * 1000,
                        success: true,
                        failureReason: nil,
                        pathSnapshot: pathSnapshot,
                        rawMessage: trimmedLine,
                        checkedAt: Date()
                    )
                )
                return
            }
        }

        let patterns = [
            #"time[=<>](\d+\.?\d*)\s*ms"#,
            #"time[=<>](\d+)"#,
            #"in (\d+\.?\d*)ms"#, // For tailscale ping output: "... in 12ms"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                if let timeRange = Range(match.range(at: 1), in: trimmedLine) {
                    let timeStr = String(trimmedLine[timeRange])
                    if let latency = Double(timeStr) {
                        pendingUpdatesBuffer.append(
                            PendingUpdate(
                                hostId: hostId,
                                index: index,
                                latency: latency,
                                success: true,
                                failureReason: nil,
                                pathSnapshot: nil,
                                rawMessage: trimmedLine,
                                checkedAt: Date()
                            )
                        )
                        return
                    }
                }
            }
        }

        if let failureReason = classifyFailureReason(from: trimmedLine) {
            pendingUpdatesBuffer.append(
                PendingUpdate(
                    hostId: hostId,
                    index: index,
                    latency: nil,
                    success: false,
                    failureReason: failureReason,
                    pathSnapshot: nil,
                    rawMessage: trimmedLine,
                    checkedAt: Date()
                )
            )
        }
    }

    private func startTCPProbe(for host: HostConfig, at index: Int) {
        guard index < hosts.count else { return }

        let hostId = host.id
        let hostName = host.name
        let address = host.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = UInt16(clamping: host.tcpPort)

        if tcpProbeTimers[hostId] != nil {
            LogManager.shared.debug("TCP probe already running for \(hostName), skipping spawn.", host: hostName)
            return
        }

        let interval = max(pingInterval, 1.0)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task.detached(priority: .utility) {
                let result = await self.measureTCPConnectLatency(host: address, port: port, timeout: min(interval, 3.0))
                self.pendingUpdatesBuffer.append(
                    PendingUpdate(
                        hostId: hostId,
                        index: index,
                        latency: result.latency,
                        success: result.latency != nil,
                        failureReason: result.failureReason,
                        pathSnapshot: nil,
                        rawMessage: result.failureReason?.detail,
                        checkedAt: Date()
                    )
                )
            }
        }

        tcpProbeTimers[hostId] = timer
        hosts[index].isChecking = true
        timer.resume()
        LogManager.shared.info("Starting TCP probe: \(address):\(port)", host: hostName)
    }

    nonisolated private func measureTCPConnectLatency(host: String, port: UInt16, timeout: TimeInterval) async -> TCPProbeResult {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.pingmonitor.tcp-probe.\(host).\(port)", qos: .utility)
            let endpoint = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: TCPProbeResult(latency: nil, failureReason: ProbeFailureReason(category: .processError, detail: "Invalid TCP port")))
                return
            }

            let connection = NWConnection(host: endpoint, port: nwPort, using: .tcp)
            let startedAt = DispatchTime.now()
            let resolution = ProbeResolutionBox()
            let failureBox = ProbeFailureBox()

            let finish: @Sendable (TCPProbeResult) -> Void = { result in
                guard resolution.tryResolve() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
                    finish(TCPProbeResult(latency: elapsed, failureReason: nil))
                case let .waiting(error):
                    failureBox.set(Self.classifyTCPError(error))
                case let .failed(error):
                    finish(TCPProbeResult(latency: nil, failureReason: Self.classifyTCPError(error)))
                case .cancelled:
                    finish(TCPProbeResult(latency: nil, failureReason: failureBox.get() ?? ProbeFailureReason(category: .timeout, detail: nil)))
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(TCPProbeResult(latency: nil, failureReason: failureBox.get() ?? ProbeFailureReason(category: .timeout, detail: nil)))
            }

            connection.start(queue: queue)
        }
    }

    nonisolated private func classifyFailureReason(from message: String) -> ProbeFailureReason? {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()

        if lowered.contains("no route to host") {
            return ProbeFailureReason(category: .noRoute, detail: normalized)
        }
        if lowered.contains("network is unreachable") || lowered.contains("network unreachable") {
            return ProbeFailureReason(category: .networkUnreachable, detail: normalized)
        }
        if lowered.contains("host is down") || lowered.contains("host down") {
            return ProbeFailureReason(category: .hostDown, detail: normalized)
        }
        if lowered.contains("connection refused") {
            return ProbeFailureReason(category: .connectionRefused, detail: normalized)
        }
        if lowered.contains("permission denied") || lowered.contains("operation not permitted") {
            return ProbeFailureReason(category: .permissionDenied, detail: normalized)
        }
        if lowered.contains("cannot resolve")
            || lowered.contains("unknown host")
            || lowered.contains("name or service not known")
            || lowered.contains("nodename nor servname provided")
            || lowered.contains("temporary failure in name resolution") {
            return ProbeFailureReason(category: .dnsFailure, detail: normalized)
        }
        if lowered.contains("request timeout")
            || lowered.contains("timed out")
            || lowered.contains("100% packet loss")
            || lowered.contains("100.0% packet loss")
            || lowered.contains("100 percent packet loss")
            || lowered.contains("no reply") {
            return ProbeFailureReason(category: .timeout, detail: normalized)
        }
        if lowered.contains("failed") || lowered.contains("error") {
            return ProbeFailureReason(category: .processError, detail: normalized)
        }
        return nil
    }

    nonisolated private func extractTailscalePathSnapshot(from response: TailscalePingResponse) -> ProbePathSnapshot? {
        if response.IsP2P == true {
            let endpoint = response.Endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ProbePathSnapshot(kind: .direct, endpoint: endpoint)
        }
        if let derp = response.DERPRegionCode?.trimmingCharacters(in: .whitespacesAndNewlines), !derp.isEmpty {
            return ProbePathSnapshot(kind: .relay, endpoint: derp.uppercased())
        }
        if response.IsP2P == false {
            return ProbePathSnapshot(kind: .relay, endpoint: nil)
        }
        return nil
    }

    nonisolated private static func classifyTCPError(_ error: NWError) -> ProbeFailureReason {
        switch error {
        case let .dns(code):
            return ProbeFailureReason(category: .dnsFailure, detail: "DNS error \(code)")
        case let .posix(code):
            let detail = String(describing: code)
            switch code {
            case .ETIMEDOUT:
                return ProbeFailureReason(category: .timeout, detail: nil)
            case .EHOSTUNREACH:
                return ProbeFailureReason(category: .noRoute, detail: detail)
            case .ENETUNREACH, .ENETDOWN:
                return ProbeFailureReason(category: .networkUnreachable, detail: detail)
            case .EHOSTDOWN:
                return ProbeFailureReason(category: .hostDown, detail: detail)
            case .ECONNREFUSED:
                return ProbeFailureReason(category: .connectionRefused, detail: detail)
            case .EACCES, .EPERM:
                return ProbeFailureReason(category: .permissionDenied, detail: detail)
            default:
                return ProbeFailureReason(category: .unknown, detail: detail)
            }
        case .tls(let status):
            return ProbeFailureReason(category: .processError, detail: "TLS status \(status)")
        case .wifiAware(let code):
            return ProbeFailureReason(category: .networkUnreachable, detail: "Wi-Fi Aware error \(code)")
        @unknown default:
            return ProbeFailureReason(category: .unknown, detail: error.localizedDescription)
        }
    }

    private func checkNotification(host: HostConfig) {
        if host.lastLatency ?? 999 > 100 {
            sendNotification(title: "⚠️ \(LanguageManager.shared.t("stats.legend.poor"))", body: "\(host.name): \(String(format: "%.1f", host.lastLatency ?? 0))ms")
        } else if !host.isReachable {
            let failureText = hostDiagnostics[host.id]?.lastFailureReason?.localizedDescription() ?? LanguageManager.shared.t("dashboard.timeout")
            sendNotification(title: "❌ \(LanguageManager.shared.t("dashboard.failed"))", body: "\(host.name): \(failureText)")
        }
    }

    private func sendNotification(title: String, body: String) {
        if notificationType == "bark" && !barkURL.isEmpty {
            sendBarkNotification(title: title, body: body)
        } else {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func sendBarkNotification(title: String, body: String) {
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? body
        let urlString = barkURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/\(encodedTitle)/\(encodedBody)"
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    func syncToWidget() {
        // Legacy updates (optional, for internal app state persistence)
        defaults.set(isRunning, forKey: "isRunning")
        
        // Prepare entries
        var widgetEntries: [WidgetData.HostStatus] = []
        
        let mode = WidgetData.DisplayMode(rawValue: widgetDisplayMode) ?? .auto
        var title = "PingMonitor"
        
        if mode == .specific, let host = hosts.first(where: { $0.id.uuidString == widgetSelectedHostId }) {
            // Specific Host Mode
            title = host.name
            widgetEntries.append(createWidgetStatus(for: host))
        } else {
            // Auto/Summary Mode: Top 5 hosts (prioritize high latency/offline if running, else by order)
            // For now, just take first 5 active hosts
            title = isRunning ? "Monitoring" : "Stopped"
            let sortedHosts = hosts.sorted { h1, h2 in
                // Sort concept: Offline > High Latency > Low Latency
                let l1 = h1.lastLatency ?? 0
                let l2 = h2.lastLatency ?? 0
                // If one is 0 (timeout/offline) and running, it's "worse" than high latency
                if isRunning {
                     if l1 == 0 && l2 > 0 { return true } // h1 timeout
                     if l1 > 0 && l2 == 0 { return false } // h2 timeout
                     return l1 > l2 // Higher latency first
                }
                return false // Keep user order if not running
            }
            
            for host in sortedHosts.prefix(5) {
                widgetEntries.append(createWidgetStatus(for: host))
            }
        }
        
        // File-based update for Widget
        let data = WidgetData(
            displayMode: mode,
            title: title,
            entries: widgetEntries,
            lastUpdated: Date()
        )
        WidgetDataManager.shared.save(data)
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func createWidgetStatus(for host: HostConfig) -> WidgetData.HostStatus {
        let latency = host.lastLatency ?? 0
        let color: String
        if !isRunning {
            color = "gray"
        } else if latency == 0 {
            color = "red" // Timeout
        } else if latency < 50 {
            color = "green"
        } else if latency < 100 {
            color = "yellow"
        } else {
            color = "orange"
        }
        
        return WidgetData.HostStatus(
            name: host.name,
            latency: latency,
            status: color,
            isRunning: isRunning
        )
    }

    func getDisplayText(for host: HostConfig?) -> String {
        guard let host = host else { return LanguageManager.shared.t("header.stopped") }
        var parts: [String] = []

        if showLatencyInMenu, let latency = host.lastLatency {
            parts.append("\(Int(latency))ms")
        }

        if showLabelsInMenu {
            for rule in host.displayRules where rule.enabled {
                let conditionMet = rule.condition == "less" ? (host.lastLatency ?? 999) < rule.threshold : (host.lastLatency ?? 0) > rule.threshold
                if conditionMet {
                    parts.append(rule.label)
                }
            }
        }

        return parts.isEmpty ? (isRunning ? "●" : LanguageManager.shared.t("header.stopped")) : parts.joined(separator: " ")
    }
    
    func getStatusBarDisplayHost() -> HostConfig? {
        guard !hosts.isEmpty else { return nil }
        
        let activeHosts = hosts.filter { $0.isReachable && $0.lastLatency != nil }
        
        switch statusBarDisplayMode {
        case .first:
            return hosts.first
        case .best:
            return activeHosts.min { ($0.lastLatency ?? Double.infinity) < ($1.lastLatency ?? Double.infinity) } ?? hosts.first
        case .worst:
            if let unreachable = hosts.first(where: { !$0.isReachable }) {
                return unreachable
            }
            return activeHosts.max { ($0.lastLatency ?? 0) < ($1.lastLatency ?? 0) } ?? hosts.first
        case .average:
            return hosts.first
        }
    }
    
    func getStatusBarDisplayText() -> String {
        guard isRunning else { return LanguageManager.shared.t("header.stopped") }
        guard !hosts.isEmpty else { return LanguageManager.shared.t("monitor.no_hosts") }
        
        switch statusBarDisplayMode {
        case .average:
            let activeHosts = hosts.filter { $0.isReachable && $0.lastLatency != nil }
            if activeHosts.isEmpty {
                return LanguageManager.shared.t("dashboard.no_data")
            }
            let avgLatency = activeHosts.map { $0.lastLatency! }.reduce(0, +) / Double(activeHosts.count)
            var parts = ["\(Int(avgLatency))ms"]
            if showLabelsInMenu {
                parts.append(LanguageManager.shared.t("settings.avg_latency"))
            }
            return parts.joined(separator: " ")
        case .first, .best, .worst:
            if let host = getStatusBarDisplayHost() {
                return getDisplayText(for: host)
            }
            return LanguageManager.shared.t("header.stopped")
        }
    }
    
    func updateStatusBarDisplay() {
        statusBarController?.updateStatusBar()
    }
    
    func getStatusBarLabelCount() -> Int {
        guard let host = getStatusBarDisplayHost() else { return 0 }
        guard showLabelsInMenu else { return 0 }
        
        return host.displayRules.filter { rule in
            guard rule.enabled else { return false }
            guard let latency = host.lastLatency else { return false }
            if rule.condition == "less" {
                return latency < rule.threshold
            } else {
                return latency > rule.threshold
            }
        }.count
    }

    func addHost(name: String, address: String, command: String = "", displayRules: [DisplayRule]? = nil, probeMode: HostProbeMode = .icmp, tcpPort: Int = 443) {
        var newHost = HostConfig(name: name, address: address, command: command, probeMode: probeMode, tcpPort: tcpPort)
        if let rules = displayRules {
            newHost.displayRules = rules
        }
        hosts.append(newHost)
        hostStats[newHost.id] = HostStats(hostId: newHost.id)
        probeSamples[newHost.id] = []
        saveSettings()
        LogManager.shared.info("Added host: \(name) (\(address))")
        
        if isRunning {
            if let index = hosts.firstIndex(where: { $0.id == newHost.id }) {
                startPingProcess(for: hosts[index], at: index)
            }
        }
    }

    func removeHost(at index: Int) {
        guard index < hosts.count else { return }
        let host = hosts[index]
        
        stopPingProcess(for: host.id)
        
        hostStats.removeValue(forKey: host.id)
        hostDiagnostics.removeValue(forKey: host.id)
        probeSamples.removeValue(forKey: host.id)
        hosts.remove(at: index)
        saveSettings()
        LogManager.shared.info("Removed host: \(host.name)")
    }
    
    func updateHost(at index: Int, name: String, address: String, command: String, displayRules: [DisplayRule]? = nil, probeMode: HostProbeMode, tcpPort: Int) {
        guard index < hosts.count else { return }
        let oldName = hosts[index].name
        let hostId = hosts[index].id
        
        let needRestart =
            hosts[index].address != address ||
            hosts[index].command != command ||
            hosts[index].probeMode != probeMode ||
            hosts[index].tcpPort != tcpPort
        
        if needRestart && isRunning {
            stopPingProcess(for: hostId)
        }
        
        hosts[index].name = name
        hosts[index].address = address
        hosts[index].command = command
        hosts[index].probeMode = probeMode
        hosts[index].tcpPort = tcpPort
        if let rules = displayRules {
            hosts[index].displayRules = rules
        }
        
        saveSettings()
        LogManager.shared.info("Updated host: \(oldName) -> \(name)")
        
        if needRestart && isRunning {
            startPingProcess(for: hosts[index], at: index)
        }
    }
    
    func addPreset(name: String, address: String, command: String = "") {
        presets.append(HostPreset(name: name, address: address, command: command))
        saveSettings()
        LogManager.shared.info("Added preset: \(name)")
    }
    
    func updatePreset(at index: Int, name: String, address: String, command: String) {
        guard index < presets.count else { return }
        presets[index].name = name
        presets[index].address = address
        presets[index].command = command
        saveSettings()
        LogManager.shared.info("Updated preset: \(name)")
    }
    
    func removePreset(at index: Int) {
        guard index < presets.count else { return }
        let preset = presets[index]
        presets.remove(at: index)
        saveSettings()
        LogManager.shared.info("Removed preset: \(preset.name)")
    }
    
    func addHostFromPreset(_ preset: HostPreset) {
        hosts.append(HostConfig(name: preset.name, address: preset.address, command: preset.command))
        let newHost = hosts.last!
        hostStats[newHost.id] = HostStats(hostId: newHost.id)
        probeSamples[newHost.id] = []
        saveSettings()
        LogManager.shared.info("Added host from preset: \(preset.name)")
        
        if isRunning {
            if let index = hosts.firstIndex(where: { $0.name == preset.name && $0.address == preset.address }) {
                startPingProcess(for: hosts[index], at: index)
            }
        }
    }
    
    func moveHost(from source: IndexSet, to destination: Int) {
        hosts.move(fromOffsets: source, toOffset: destination)
        saveSettings()
        LogManager.shared.info("Reordered hosts")
    }
}

struct ServiceShortcut: Codable, Identifiable {
    let id: UUID
    var name: String          // e.g. "Synology DSM"
    var url: String           // e.g. "http://100.100.1.30:5000" or host address for SSH
    var icon: String          // SF Symbol name, e.g. "globe"
    var type: ServiceType
    
    // SSH-specific fields
    var sshUser: String = ""
    var sshPort: Int = 22
    var sshAuthMode: SSHAuthMode = .key
    var sshKeyPath: String = ""   // e.g. "~/.ssh/id_rsa"
    var sshPassword: String = ""  // stored for display only

    enum ServiceType: String, Codable, CaseIterable {
        case web = "web"
        case ssh = "ssh"
        case custom = "custom"
    }
    
    enum SSHAuthMode: String, Codable {
        case password = "password"
        case key = "key"
    }

    init(name: String, url: String, icon: String = "globe", type: ServiceType = .web,
         sshUser: String = "", sshPort: Int = 22, sshAuthMode: SSHAuthMode = .key,
         sshKeyPath: String = "", sshPassword: String = "") {
        self.id = UUID()
        self.name = name
        self.url = url
        self.icon = icon
        self.type = type
        self.sshUser = sshUser
        self.sshPort = sshPort
        self.sshAuthMode = sshAuthMode
        self.sshKeyPath = sshKeyPath
        self.sshPassword = sshPassword
    }
    
    // Custom decoder for backward compatibility with older saved data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        icon = try container.decode(String.self, forKey: .icon)
        type = try container.decode(ServiceType.self, forKey: .type)
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshAuthMode = try container.decodeIfPresent(SSHAuthMode.self, forKey: .sshAuthMode) ?? .key
        sshKeyPath = try container.decodeIfPresent(String.self, forKey: .sshKeyPath) ?? ""
        sshPassword = try container.decodeIfPresent(String.self, forKey: .sshPassword) ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, icon, type
        case sshUser, sshPort, sshAuthMode, sshKeyPath, sshPassword
    }
    
    /// Build the full SSH command string
    var sshCommand: String {
        var cmd = "ssh"
        if sshPort != 22 {
            cmd += " -p \(sshPort)"
        }
        if sshAuthMode == .key && !sshKeyPath.isEmpty {
            cmd += " -i \(sshKeyPath)"
        }
        if !sshUser.isEmpty {
            cmd += " \(sshUser)@\(url)"
        } else {
            cmd += " \(url)"
        }
        
        // If password auth with password configured, wrap in expect script
        if sshAuthMode == .password && !sshPassword.isEmpty {
            let escapedPwd = sshPassword.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "'", with: "'\\''")
            return "expect -c 'spawn \(cmd); expect \"*assword*\"; send \"\(escapedPwd)\\r\"; interact'"
        }
        
        return cmd
    }
}

struct HostRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var content: String
    var createdAt: Date = Date()
}

enum HostProbeMode: String, Codable, CaseIterable {
    case icmp = "icmp"
    case tcp = "tcp"
}

struct HostConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var address: String
    var command: String = ""
    var lastLatency: Double?
    var isReachable = false
    var isChecking = false
    var displayRules: [DisplayRule] = [
        DisplayRule(condition: "less", threshold: 50, label: "Direct", enabled: true),
        DisplayRule(condition: "greater", threshold: 100, label: "Relay", enabled: true)
    ]
    var serviceShortcuts: [ServiceShortcut] = []
    var isTailscaleNode: Bool = false
    var tailscaleHostname: String?
    var isPaused: Bool = false
    var records: [HostRecord] = []
    var probeMode: HostProbeMode = .icmp
    var tcpPort: Int = 443
    
    init(id: UUID = UUID(), name: String, address: String, command: String = "",
         displayRules: [DisplayRule]? = nil, serviceShortcuts: [ServiceShortcut] = [],
         isTailscaleNode: Bool = false, tailscaleHostname: String? = nil,
         isPaused: Bool = false,
         records: [HostRecord] = [],
         probeMode: HostProbeMode = .icmp,
         tcpPort: Int = 443) {
        self.id = id
        self.name = name
        self.address = address
        self.command = command
        if let rules = displayRules {
            self.displayRules = rules
        }
        self.serviceShortcuts = serviceShortcuts
        self.isTailscaleNode = isTailscaleNode
        self.tailscaleHostname = tailscaleHostname
        self.isPaused = isPaused
        self.records = records
        self.probeMode = probeMode
        self.tcpPort = tcpPort
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        lastLatency = try container.decodeIfPresent(Double.self, forKey: .lastLatency)
        isReachable = try container.decodeIfPresent(Bool.self, forKey: .isReachable) ?? false
        isChecking = try container.decodeIfPresent(Bool.self, forKey: .isChecking) ?? false
        displayRules = try container.decodeIfPresent([DisplayRule].self, forKey: .displayRules) ?? [
            DisplayRule(condition: "less", threshold: 50, label: "Direct", enabled: true),
            DisplayRule(condition: "greater", threshold: 100, label: "Relay", enabled: true)
        ]
        serviceShortcuts = try container.decodeIfPresent([ServiceShortcut].self, forKey: .serviceShortcuts) ?? []
        isTailscaleNode = try container.decodeIfPresent(Bool.self, forKey: .isTailscaleNode) ?? false
        tailscaleHostname = try container.decodeIfPresent(String.self, forKey: .tailscaleHostname)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        records = try container.decodeIfPresent([HostRecord].self, forKey: .records) ?? []
        probeMode = try container.decodeIfPresent(HostProbeMode.self, forKey: .probeMode) ?? .icmp
        tcpPort = try container.decodeIfPresent(Int.self, forKey: .tcpPort) ?? 443
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HostConfig, rhs: HostConfig) -> Bool {
        lhs.id == rhs.id
    }
}

extension HostConfig {
    var probeDisplayLabel: String {
        probeMode == .tcp ? "TCP \(tcpPort)" : "ICMP"
    }
}

struct HostPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var address: String
    var command: String = ""
    var serviceShortcuts: [ServiceShortcut] = []
}

struct DisplayRule: Codable, Identifiable {
    var id = UUID()
    var condition: String
    var threshold: Double
    var label: String
    var enabled: Bool
}

enum StatusBarDisplayMode: String, Codable, CaseIterable {
    case average = "average"
    case worst = "worst"
    case best = "best"
    case first = "first"
}

@MainActor
class StatusBarController: NSObject, ObservableObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    var viewModel: PingMonitorViewModel
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    // 固定宽度：仅图标
    private let widthIconOnly: CGFloat = 32

    override init() {
        viewModel = PingMonitorViewModel()
        super.init()
        viewModel.statusBarController = self
        setupStatusBar()

        // 监听所有相关属性的变化
        viewModel.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)

        viewModel.$hosts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
        
        viewModel.$statusBarDisplayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
        
        viewModel.$showLatencyInMenu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
        
        viewModel.$showLabelsInMenu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
        
        viewModel.$showSpeedInMenu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSpeedMonitoring()
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
        
        viewModel.$speedUnit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
        
        viewModel.$statusBarWidth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)
            
        viewModel.$appAppearance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAppearance()
            }
            .store(in: &cancellables)
    }
    
    private var speedTimer: Timer?
    
    private func updateSpeedMonitoring() {
        speedTimer?.invalidate()
        speedTimer = nil
        if viewModel.showSpeedInMenu {
            NetworkSpeedManager.shared.startMonitoring()
            speedTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusBar()
                }
            }
        } else {
            // Don't stop the global manager, other views may use it
        }
    }

    func setupStatusBar() {
        // 初始使用图标模式（最短宽度）
        statusItem = NSStatusBar.system.statusItem(withLength: widthIconOnly)

        guard let button = statusItem?.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Ping Monitor")?.withSymbolConfiguration(config)
        button.image?.isTemplate = true
        button.action = #selector(toggleWindow)
        button.target = self

        updateStatusBar()
    }

    @objc func toggleWindow() {
        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
                NSApp.setActivationPolicy(.accessory)
            } else {
                showWindow()
            }
        } else {
            createWindow()
            showWindow()
        }
    }
    
    private func createWindow() {
        let contentView = MainView(viewModel: viewModel)
            .contentTransition(.identity)
        
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        mainWindow?.title = "Ping Monitor"
        mainWindow?.contentView = NSHostingView(rootView: contentView)
        mainWindow?.center()
        mainWindow?.setFrameAutosaveName("PingMonitorMainWindow")
        
        updateAppearance()
        
        // 设置窗口关闭时只是隐藏，不是销毁
        mainWindow?.isReleasedWhenClosed = false
        mainWindow?.delegate = self
    }
    
    private func updateAppearance() {
        guard let window = mainWindow else { return }
        switch viewModel.appAppearance {
        case "light":
            window.appearance = NSAppearance(named: .aqua)
        case "dark":
            window.appearance = NSAppearance(named: .darkAqua)
        default:
            window.appearance = nil
        }
    }
    
    private func showWindow() {
        guard let window = mainWindow else { return }
        
        NSApp.setActivationPolicy(.regular)
        
        // 如果窗口被最小化了，先恢复
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func updateStatusBar() {
        guard let button = statusItem?.button else { return }

        let displayText = viewModel.getStatusBarDisplayText()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.font = font
        button.imagePosition = .imageLeft
        button.alignment = .left

        if viewModel.showIconInMenu {
            if viewModel.isRunning {
                button.image = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: nil)
            } else {
                button.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            }
        } else {
            button.image = nil
        }

        let showingText = viewModel.showLatencyInMenu || viewModel.showLabelsInMenu
        var latencyStr = ""
        if viewModel.isRunning && showingText && !displayText.isEmpty && displayText != "●" {
            latencyStr = viewModel.showIconInMenu ? " \(displayText)" : displayText
        }

        if viewModel.showSpeedInMenu {
            let speedImage = renderSpeedImage()
            let fullAttr = NSMutableAttributedString()
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byClipping
            
            if !latencyStr.isEmpty {
                fullAttr.append(NSAttributedString(string: latencyStr, attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle
                ]))
            }
            
            let iconWidth: CGFloat = viewModel.showIconInMenu ? widthIconOnly : 8
            let textWidth = measureWidth(text: latencyStr, font: font)
            let currentWidth = textWidth + iconWidth
            let targetWidth = CGFloat(viewModel.statusBarWidth)
            let speedWidth = speedImage.size.width
            let availableSpace = targetWidth - currentWidth - speedWidth - 10 // Adjusted margin
            
            if availableSpace > 0 {
                fullAttr.append(NSAttributedString(string: " ", attributes: [
                    .font: font,
                    .kern: availableSpace,
                    .paragraphStyle: paragraphStyle
                ]))
            } else {
                // Keep it exactly clipping without breaking
                fullAttr.append(NSAttributedString(string: " ", attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle
                ]))
            }
            
            let attachment = NSTextAttachment()
            attachment.image = speedImage
            // Vertically center with the text (font cap height center)
            let yOffset = (font.capHeight - speedImage.size.height) / 2.0
            attachment.bounds = CGRect(x: 0, y: yOffset, width: speedImage.size.width, height: speedImage.size.height)
            let attachStr = NSAttributedString(attachment: attachment)
            fullAttr.append(attachStr)
            
            fullAttr.addAttributes([.paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: fullAttr.length))
            
            button.attributedTitle = fullAttr
            statusItem?.length = targetWidth
        } else {
            button.attributedTitle = NSAttributedString()
            button.title = latencyStr
            if !latencyStr.isEmpty {
                statusItem?.length = measureWidth(text: latencyStr, font: font) + (viewModel.showIconInMenu ? widthIconOnly : 16)
            } else {
                statusItem?.length = viewModel.showIconInMenu ? widthIconOnly : 0
            }
        }
    }
    
    private func renderSpeedImage() -> NSImage {
        let mgr = NetworkSpeedManager.shared
        let upStr = "↑ \(formatSpeed(mgr.totalSpeedOut))"
        let downStr = "↓ \(formatSpeed(mgr.totalSpeedIn))"
        
        let weight: NSFont.Weight
        switch viewModel.statusBarFontWeight {
        case "bold": weight = .bold
        case "regular": weight = .regular
        default: weight = .medium
        }
        
        // Use monospaced font for all digits and symbols to ensure absolute width stability
        let smallFont = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(viewModel.statusBarFontSize), weight: weight)
        let upAttrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: NSColor.systemGreen]
        let downAttrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: NSColor.systemBlue]
        
        // Template for 6-digit number + unit + arrow symbol + padding
        let templateStr = "↑ 9999.99 MB/s"
        let templateSize = (templateStr as NSString).size(withAttributes: upAttrs)
        let fixedWidth = ceil(templateSize.width) + 2
        let height = ceil(templateSize.height) * 2
        
        let image = NSImage(size: NSSize(width: fixedWidth, height: height))
        image.lockFocus()
        
        // Symbols and text stay next to each other, anchored to the left of the image container
        (upStr as NSString).draw(at: NSPoint(x: 0, y: height / 2), withAttributes: upAttrs)
        (downStr as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: downAttrs)
        
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let unit = viewModel.speedUnit
        switch unit {
        case "KB":
            return String(format: "%.0f KB/s", bytesPerSec / 1024)
        case "MB":
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        default: // auto
            if bytesPerSec < 1024 {
                return String(format: "%.0f B/s", bytesPerSec)
            } else if bytesPerSec < 1024 * 1024 {
                return String(format: "%.1f KB/s", bytesPerSec / 1024)
            } else {
                return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
            }
        }
    }
    
    private func measureWidth(text: String, font: NSFont) -> CGFloat {
        let iconBase: CGFloat = 28
        let padding: CGFloat = 4
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        return ceil(iconBase + textSize.width + padding)
    }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}
