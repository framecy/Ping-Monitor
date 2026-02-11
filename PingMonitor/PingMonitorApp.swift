import SwiftUI
import UserNotifications
import ServiceManagement
import WidgetKit
import Combine

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

@MainActor
class LogManager: ObservableObject {
    static let shared = LogManager()
    @Published var logs: [LogEntry] = []
    private let maxLogs = 1000
    
    struct LogEntry: Identifiable, Codable {
        let id = UUID()
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
            print("Failed to export logs: \(error)")
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
    @Published var selectedStatHost: HostConfig?
    
    var statusBarController: StatusBarController?
    private var pingProcesses: [UUID: Process] = [:]
    private let defaults = UserDefaults(suiteName: "group.com.pingmonitor.shared") ?? UserDefaults.standard

    init() {
        loadSettings()
        setupAutoStart()
        LogManager.shared.info("PingMonitor initialized")
    }

    func loadSettings() {
        if let data = defaults.data(forKey: "hosts"),
           let savedHosts = try? JSONDecoder().decode([HostConfig].self, from: data) {
            hosts = savedHosts
        } else {
            hosts = [HostConfig(name: "Google DNS", address: "8.8.8.8")]
        }
        
        if let presetData = defaults.data(forKey: "presets"),
           let savedPresets = try? JSONDecoder().decode([HostPreset].self, from: presetData) {
            presets = savedPresets
        } else {
            presets = [
                HostPreset(name: "Google DNS", address: "8.8.8.8"),
                HostPreset(name: "Cloudflare", address: "1.1.1.1"),
                HostPreset(name: "百度", address: "www.baidu.com"),
                HostPreset(name: "淘宝", address: "www.taobao.com")
            ]
        }
        
        if let statsData = defaults.data(forKey: "hostStats"),
           let savedStats = try? JSONDecoder().decode([String: HostStats].self, from: statsData) {
            var stats: [UUID: HostStats] = [:]
            for (key, value) in savedStats {
                if let uuid = UUID(uuidString: key) {
                    stats[uuid] = value
                }
            }
            hostStats = stats
        }
        
        autoStart = defaults.bool(forKey: "autoStart")
        showLatencyInMenu = defaults.bool(forKey: "showLatencyInMenu", defaultValue: true)
        showLabelsInMenu = defaults.bool(forKey: "showLabelsInMenu", defaultValue: true)
        notificationEnabled = defaults.bool(forKey: "notificationEnabled", defaultValue: true)
        notificationType = defaults.string(forKey: "notificationType") ?? "system"
        barkURL = defaults.string(forKey: "barkURL") ?? ""
        pingInterval = defaults.double(forKey: "pingInterval")
        if pingInterval == 0 { pingInterval = 5.0 }
        
        if let levelRaw = defaults.string(forKey: "logLevel"),
           let level = LogManager.LogLevel(rawValue: levelRaw) {
            logLevel = level
        }
        
        if let modeRaw = defaults.string(forKey: "statusBarDisplayMode"),
           let mode = StatusBarDisplayMode(rawValue: modeRaw) {
            statusBarDisplayMode = mode
        }
        
        LogManager.shared.info("Settings loaded: \(hosts.count) hosts, \(presets.count) presets")
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(hosts) {
            defaults.set(data, forKey: "hosts")
        }
        if let presetData = try? JSONEncoder().encode(presets) {
            defaults.set(presetData, forKey: "presets")
        }
        
        var statsDict: [String: HostStats] = [:]
        for (key, value) in hostStats {
            statsDict[key.uuidString] = value
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
            startPingProcess(for: hosts[i], at: i)
        }
        
        saveSettings()
        syncToWidget()
    }

    func stopAll() {
        LogManager.shared.info("Stopping all monitors")
        
        for (hostId, process) in pingProcesses {
            if process.isRunning {
                process.terminate()
                LogManager.shared.debug("Terminated ping process for host: \(hostId)")
            }
        }
        pingProcesses.removeAll()
        
        isRunning = false
        for i in hosts.indices {
            hosts[i].isChecking = false
        }
        saveSettings()
        syncToWidget()
    }

    func toggle() {
        isRunning ? stopAll() : startAll()
    }
    
    func resetStats(for hostId: UUID) {
        hostStats[hostId] = HostStats(hostId: hostId)
        saveSettings()
        LogManager.shared.info("Reset stats for host: \(hostId)")
    }
    
    func resetAllStats() {
        hostStats.removeAll()
        for host in hosts {
            hostStats[host.id] = HostStats(hostId: host.id)
        }
        saveSettings()
        LogManager.shared.info("Reset all stats")
    }
    
    private func updateStats(for hostId: UUID, latency: Double?, success: Bool) {
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
            
            // Add to history (keep last 100 points)
            stats.latencyHistory.append(LatencyPoint(timestamp: Date(), latency: lat))
            if stats.latencyHistory.count > 100 {
                stats.latencyHistory.removeFirst()
            }
        } else {
            stats.failedPings += 1
        }
        
        hostStats[hostId] = stats
    }
    
    private func startPingProcess(for host: HostConfig, at index: Int) {
        guard index < hosts.count else { return }
        
        let hostName = host.name
        let address = host.address
        let customCommand = host.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostId = host.id
        
        let commandString: String
        if customCommand.isEmpty {
            commandString = "ping -i 1 \(address)"
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
        process.arguments = ["-c", commandString]
        
        pingProcesses[hostId] = process
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                Task { @MainActor [weak self] in
                    self?.parsePingLine(line, for: index, hostName: hostName)
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
        }
        
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let idx = self.hosts.firstIndex(where: { $0.id == hostId }) {
                    self.hosts[idx].isChecking = false
                    if process.terminationStatus != 0 {
                        self.hosts[idx].isReachable = false
                    }
                }
                self.pingProcesses.removeValue(forKey: hostId)
            }
        }
    }
    
    private func parsePingLine(_ line: String, for index: Int, hostName: String) {
        guard index < hosts.count else { return }
        let hostId = hosts[index].id
        
        let patterns = [
            #"time[=<>](\d+\.?\d*)\s*ms"#,
            #"time[=<>](\d+)"#,
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let timeRange = Range(match.range(at: 1), in: line) {
                    let timeStr = String(line[timeRange])
                    if let latency = Double(timeStr) {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, index < self.hosts.count else { return }
                            self.hosts[index].lastLatency = latency
                            self.hosts[index].isReachable = true
                            self.hosts[index].isChecking = false
                            
                            self.updateStats(for: hostId, latency: latency, success: true)
                            
                            if self.notificationEnabled {
                                self.checkNotification(host: self.hosts[index])
                            }
                            
                            self.syncToWidget()
                        }
                        return
                    }
                }
            }
        }
        
        if line.contains("Request timeout") || line.contains("No route to host") || line.contains("100% packet loss") {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, index < self.hosts.count else { return }
                self.hosts[index].isReachable = false
                self.updateStats(for: hostId, latency: nil, success: false)
                if self.notificationEnabled {
                    self.checkNotification(host: self.hosts[index])
                }
                self.syncToWidget()
            }
        }
    }

    private func checkNotification(host: HostConfig) {
        if host.lastLatency ?? 999 > 100 {
            sendNotification(title: "⚠️ 延迟过高", body: "\(host.name): \(String(format: "%.1f", host.lastLatency ?? 0))ms")
        } else if !host.isReachable {
            sendNotification(title: "❌ 连接失败", body: "\(host.name) 无法连接")
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
        defaults.set(isRunning, forKey: "isRunning")
        defaults.set(hosts.first?.lastLatency ?? 0, forKey: "lastLatency")
        defaults.set(hosts.first?.address ?? "8.8.8.8", forKey: "targetHost")
        defaults.set(hosts.first?.lastLatency.map { $0 < 50 ? "green" : $0 < 100 ? "yellow" : "red" } ?? "gray", forKey: "color")
        defaults.set(getDisplayText(for: hosts.first), forKey: "displayText")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func getDisplayText(for host: HostConfig?) -> String {
        guard let host = host else { return "未运行" }
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

        return parts.isEmpty ? (isRunning ? "●" : "已停止") : parts.joined(separator: " ")
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
        guard isRunning else { return "已停止" }
        guard !hosts.isEmpty else { return "无主机" }
        
        switch statusBarDisplayMode {
        case .average:
            let activeHosts = hosts.filter { $0.isReachable && $0.lastLatency != nil }
            if activeHosts.isEmpty {
                return "无响应"
            }
            let avgLatency = activeHosts.map { $0.lastLatency! }.reduce(0, +) / Double(activeHosts.count)
            var parts = ["\(Int(avgLatency))ms"]
            if showLabelsInMenu {
                parts.append("平均")
            }
            return parts.joined(separator: " ")
        case .first, .best, .worst:
            if let host = getStatusBarDisplayHost() {
                return getDisplayText(for: host)
            }
            return "未运行"
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

    func addHost(name: String, address: String, command: String = "", displayRules: [DisplayRule]? = nil) {
        var newHost = HostConfig(name: name, address: address, command: command)
        if let rules = displayRules {
            newHost.displayRules = rules
        }
        hosts.append(newHost)
        hostStats[newHost.id] = HostStats(hostId: newHost.id)
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
        
        if let process = pingProcesses[host.id], process.isRunning {
            process.terminate()
            pingProcesses.removeValue(forKey: host.id)
        }
        
        hostStats.removeValue(forKey: host.id)
        hosts.remove(at: index)
        saveSettings()
        LogManager.shared.info("Removed host: \(host.name)")
    }
    
    func updateHost(at index: Int, name: String, address: String, command: String, displayRules: [DisplayRule]? = nil) {
        guard index < hosts.count else { return }
        let oldName = hosts[index].name
        let hostId = hosts[index].id
        
        let needRestart = hosts[index].address != address || hosts[index].command != command
        
        if needRestart && isRunning {
            if let process = pingProcesses[hostId], process.isRunning {
                process.terminate()
                pingProcesses.removeValue(forKey: hostId)
            }
        }
        
        hosts[index].name = name
        hosts[index].address = address
        hosts[index].command = command
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
        saveSettings()
        LogManager.shared.info("Added host from preset: \(preset.name)")
        
        if isRunning {
            if let index = hosts.firstIndex(where: { $0.name == preset.name && $0.address == preset.address }) {
                startPingProcess(for: hosts[index], at: index)
            }
        }
    }
}

struct HostConfig: Codable, Identifiable, Hashable {
    let id = UUID()
    var name: String
    var address: String
    var command: String = ""
    var lastLatency: Double?
    var isReachable = false
    var isChecking = false
    var displayRules: [DisplayRule] = [
        DisplayRule(condition: "less", threshold: 50, label: "P2P", enabled: true),
        DisplayRule(condition: "greater", threshold: 50, label: "转发", enabled: true)
    ]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HostConfig, rhs: HostConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct HostPreset: Codable, Identifiable {
    let id = UUID()
    var name: String
    var address: String
    var command: String = ""
}

struct DisplayRule: Codable, Identifiable {
    let id = UUID()
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
class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    var viewModel: PingMonitorViewModel
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    // 固定宽度定义
    private let widthIconOnly: CGFloat = 28
    private let widthWithLatency: CGFloat = 75
    private let widthWithLatencyAndLabel: CGFloat = 110
    private let widthWithTwoLabels: CGFloat = 145

    init() {
        viewModel = PingMonitorViewModel()
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
        
        // 设置窗口关闭时只是隐藏，不是销毁
        mainWindow?.isReleasedWhenClosed = false
    }
    
    private func showWindow() {
        guard let window = mainWindow else { return }
        
        // 如果窗口被最小化了，先恢复
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateStatusBar() {
        guard let button = statusItem?.button else { return }

        let displayText = viewModel.getStatusBarDisplayText()
        let labelCount = viewModel.getStatusBarLabelCount()

        if viewModel.isRunning {
            button.image = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: nil)
            button.title = " \(displayText)"
            
            // 根据内容动态调整宽度
            let targetWidth = calculateWidth(labelCount: labelCount)
            statusItem?.length = targetWidth
        } else {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            button.title = ""
            statusItem?.length = widthIconOnly
        }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }
    
    private func calculateWidth(labelCount: Int) -> CGFloat {
        if !viewModel.showLatencyInMenu && !viewModel.showLabelsInMenu {
            return widthIconOnly
        } else if viewModel.showLatencyInMenu && !viewModel.showLabelsInMenu {
            return widthWithLatency
        } else if viewModel.showLatencyInMenu && viewModel.showLabelsInMenu {
            if labelCount >= 2 {
                return widthWithTwoLabels
            } else {
                return widthWithLatencyAndLabel
            }
        } else {
            // 只显示标签，使用自适应宽度避免空白或截断
            return NSStatusItem.variableLength
        }
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
