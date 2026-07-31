import Foundation
import Combine
import AppKit

// MARK: - Network Interface Data

enum InterfaceRole {
    case physical
    case tunnel
    case loopback
    case virtual
}

/// 接口归类：用于分组展示，也决定谁参与总速率统计。
enum InterfaceFamily: String, CaseIterable {
    case wifi
    case ethernet
    case tunnel
    case bridge
    case airdrop
    case management   // anpi* / vmenet* / vnic* 等系统内部口
    case loopback
    case other

    var iconName: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .tunnel: return "lock.shield"
        case .bridge: return "arrow.triangle.branch"
        case .airdrop: return "airplayaudio"
        case .management: return "cpu"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .other: return "network"
        }
    }

    var localizationKey: String { "netspeed.family.\(rawValue)" }
}

struct NetworkInterfaceStats: Identifiable {
    let id: String  // interface name, e.g. "en0"
    var name: String
    var bytesIn: UInt64
    var bytesOut: UInt64
    var packetsIn: UInt64
    var packetsOut: UInt64
    var errorsIn: UInt64
    var errorsOut: UInt64
    
    // Computed speed (bytes per second)
    var speedIn: Double = 0
    var speedOut: Double = 0
    
    var displayName: String {
        switch name {
        case let n where n.starts(with: "en0"): return "Wi-Fi (en0)"
        case let n where n.starts(with: "en"): return "Ethernet (\(n))"
        case let n where n.starts(with: "utun"): return "VPN/Tailscale (\(n))"
        case let n where n.starts(with: "lo"): return "Loopback (\(n))"
        case let n where n.starts(with: "bridge"): return "Bridge (\(n))"
        case let n where n.starts(with: "awdl"): return "AirDrop (\(n))"
        case let n where n.starts(with: "llw"): return "Low Latency (\(n))"
        case let n where n.starts(with: "ap"): return "AP (\(n))"
        default: return name
        }
    }
    
    var isActive: Bool {
        bytesIn > 0 || bytesOut > 0
    }

    /// 接口族。注意判定顺序：`anpi*` 必须排在 `ap*` 之前，否则会被误判成 AP。
    var family: InterfaceFamily {
        let n = name.replacingOccurrences(of: "*", with: "")
        if n.hasPrefix("utun") || n.hasPrefix("ipsec") { return .tunnel }
        if n.hasPrefix("lo") { return .loopback }
        if n.hasPrefix("awdl") || n.hasPrefix("llw") { return .airdrop }
        // gif/stf 是 IPv6-over-IPv4 伪接口，归虚拟而非 tunnel ——
        // tunnel 的速率会进「隧道流量」指标，那是给 VPN/Tailscale 看的。
        if n.hasPrefix("bridge") || n.hasPrefix("gif") || n.hasPrefix("stf") { return .bridge }
        // anpi = Apple Network Processor Interface，系统内部管理口，永远不该计入用户网速。
        if n.hasPrefix("anpi") || n.hasPrefix("vmenet") || n.hasPrefix("vnic") || n.hasPrefix("ap") { return .management }
        if n == "en0" { return .wifi }
        if n.hasPrefix("en") { return .ethernet }
        return .other
    }

    var role: InterfaceRole {
        switch family {
        case .tunnel: return .tunnel
        case .loopback: return .loopback
        case .airdrop, .bridge, .management: return .virtual
        case .wifi, .ethernet, .other: return .physical
        }
    }
}

struct SpeedSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let speedIn: Double   // bytes per second
    let speedOut: Double   // bytes per second
}

struct TrafficSnapshot: Codable, Identifiable {
    var id: String { String(timestamp) }
    let timestamp: TimeInterval  // Date().timeIntervalSince1970
    let bytesIn: UInt64
    let bytesOut: UInt64
    let speedIn: Double
    let speedOut: Double
}

// MARK: - Process Network Data

struct ProcessNetworkInfo: Identifiable {
    let id = UUID()
    let pid: Int32
    let processName: String
    let user: String
    let fileDescriptor: String
    let protocolType: String  // TCP, UDP
    let localAddress: String
    let localPort: String
    let remoteAddress: String
    let remotePort: String
    let state: String  // ESTABLISHED, LISTEN, CLOSE_WAIT, etc.
    
    // Optional speed info from nettop
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var speedIn: Double = 0
    var speedOut: Double = 0
}

struct ProcessSummary: Identifiable {
    let id: Int32  // PID
    let pid: Int32
    let processName: String
    let user: String
    var connections: [ProcessNetworkInfo]
    
    // Speed info
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var speedIn: Double = 0
    var speedOut: Double = 0
    
    var totalSpeed: Double { speedIn + speedOut }
    
    var connectionCount: Int { connections.count }
    
    var protocols: Set<String> {
        Set(connections.map { $0.protocolType })
    }
    
    var listeningPorts: [String] {
        connections.filter { $0.state == "LISTEN" }.map { $0.localPort }
    }
    
    var establishedCount: Int {
        connections.filter { $0.state == "ESTABLISHED" }.count
    }
}

// MARK: - Network Speed Manager

@MainActor
class NetworkSpeedManager: ObservableObject {
    static let shared = NetworkSpeedManager()
    
    @Published var interfaces: [NetworkInterfaceStats] = []
    @Published var selectedInterface: String = "all"  // "all" or specific interface name
    @Published var totalSpeedIn: Double = 0            // bytes/sec
    @Published var totalSpeedOut: Double = 0           // bytes/sec
    @Published var totalBytesIn: UInt64 = 0
    @Published var totalBytesOut: UInt64 = 0
    @Published var tunnelSpeedIn: Double = 0
    @Published var tunnelSpeedOut: Double = 0
    @Published var tunnelBytesIn: UInt64 = 0
    @Published var tunnelBytesOut: UInt64 = 0
    @Published var speedHistory: [SpeedSample] = []
    @Published var isMonitoring = false
    @Published var refreshInterval: TimeInterval = 1.0
    @Published var trafficHistory: [TrafficSnapshot] = []
    @Published var processList: [ProcessSummary] = []
    @Published var isProcessMonitoring = false
    
    /// 当前承载默认路由的接口（`route -n get default`），总速率只认它。
    @Published private(set) var defaultRouteInterface: String?

    private var timer: Timer?
    private var snapshotTimer: Timer?
    private var processTimer: Timer?
    private var routeTimer: Timer?
    private var previousStats: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTimestamp: Date?
    private var isFetchingStats = false

    private var lastProcessStats: [Int32: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var lastProcessTimestamp: Date?
    private var isRefreshingProcessList = false
    private let maxHistoryCount = 60
    
    private var trafficFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PingMonitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("traffic_history.json")
    }
    
    private init() {
        loadTrafficHistory()
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Initial fetch
        fetchStats()
        
        // Update at configured interval
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchStats()
            }
        }
        // Snapshot every 60 seconds for traffic history
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveTrafficSnapshot()
            }
        }
        // 默认路由变化频率很低（切 Wi-Fi / 插网线），15s 一次足够，不必每秒开一个进程。
        refreshDefaultRoute()
        routeTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDefaultRoute()
            }
        }
    }

    private func refreshDefaultRoute() {
        Task.detached(priority: .utility) { [weak self] in
            let iface = Self.readDefaultRouteInterface()
            await MainActor.run {
                guard let self else { return }
                if self.defaultRouteInterface != iface {
                    LogManager.shared.info("Default route interface: \(iface ?? "none")")
                    self.defaultRouteInterface = iface
                }
            }
        }
    }

    nonisolated static func readDefaultRouteInterface() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return parseDefaultRouteInterface(output)
        } catch {
            return nil
        }
    }

    nonisolated static func parseDefaultRouteInterface(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("interface:") else { continue }
            let value = trimmed.replacingOccurrences(of: "interface:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
    
    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if isMonitoring {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.fetchStats()
                }
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        routeTimer?.invalidate()
        routeTimer = nil
        isMonitoring = false
        saveTrafficSnapshot() // Save final snapshot
    }
    
    // MARK: - Process Monitoring
    
    func startProcessMonitoring() {
        guard !isProcessMonitoring else { return }
        isProcessMonitoring = true
        refreshProcessList()
        // Faster refresh for speed calculation (2s)
        processTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProcessList()
            }
        }
    }
    
    func stopProcessMonitoring() {
        processTimer?.invalidate()
        processTimer = nil
        isProcessMonitoring = false
    }
    
    func refreshProcessList() {
        guard !isRefreshingProcessList else { return }
        isRefreshingProcessList = true
        
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            // Run lsof and nettop concurrently: they're independent subprocesses,
            // so parallel dispatch halves the blocking time (~1s instead of ~1.5s)
            // and keeps the two snapshots temporally aligned.
            let connectionsTask = Task.detached(priority: .background) { self.parseLsof() }
            let trafficTask = Task.detached(priority: .background) { self.fetchProcessTraffic() }
            let connections = await connectionsTask.value
            let traffic = await trafficTask.value
            let now = Date()
            
            await MainActor.run {
                defer { self.isRefreshingProcessList = false }
                let interval = self.lastProcessTimestamp != nil ? now.timeIntervalSince(self.lastProcessTimestamp!) : 0
                
                // Group by PID
                var grouped: [Int32: ProcessSummary] = [:]
                for conn in connections {
                    if var existing = grouped[conn.pid] {
                        existing.connections.append(conn)
                        grouped[conn.pid] = existing
                    } else {
                        var summary = ProcessSummary(
                            id: conn.pid,
                            pid: conn.pid,
                            processName: conn.processName,
                            user: conn.user,
                            connections: [conn]
                        )
                        
                        // Add traffic info
                        if let stats = traffic[conn.pid] {
                            summary.bytesIn = stats.bytesIn
                            summary.bytesOut = stats.bytesOut
                            
                            if let prev = self.lastProcessStats[conn.pid], interval > 0 {
                                // Delta calculation
                                if stats.bytesIn >= prev.bytesIn {
                                    summary.speedIn = Double(stats.bytesIn - prev.bytesIn) / interval
                                }
                                if stats.bytesOut >= prev.bytesOut {
                                    summary.speedOut = Double(stats.bytesOut - prev.bytesOut) / interval
                                }
                            }
                        }
                        
                        grouped[conn.pid] = summary
                    }
                }
                
                // Store for next delta
                self.lastProcessStats = traffic
                self.lastProcessTimestamp = now
                
                // Sort by total speed descending, then connection count
                self.processList = Array(grouped.values).sorted {
                    if abs($0.totalSpeed - $1.totalSpeed) > 1024 { // More than 1KB/s difference
                        return $0.totalSpeed > $1.totalSpeed
                    }
                    if $0.connectionCount != $1.connectionCount {
                        return $0.connectionCount > $1.connectionCount
                    }
                    return $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending
                }
            }
        }
    }
    
    nonisolated private func fetchProcessTraffic() -> [Int32: (bytesIn: UInt64, bytesOut: UInt64)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P: Aggregate by process
        // -L 1: One sample
        // -k state,interface: skip columns to keep CSV shorter
        process.arguments = ["-P", "-L", "1", "-k", "state,interface"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [:] }
            return Self.parseNettopOutput(output)
        } catch {
            return [:]
        }
    }

    /// Pure parser exposed for unit tests. nettop -P CSV columns:
    /// time(0), process.pid(1), bytes_in(2), bytes_out(3), ...
    nonisolated static func parseNettopOutput(_ output: String) -> [Int32: (bytesIn: UInt64, bytesOut: UInt64)] {
        var results: [Int32: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 4 else { continue }

            // Column 1 is "name.PID"
            let procPart = parts[1]
            let procComponents = procPart.components(separatedBy: ".")
            guard let lastPart = procComponents.last, let pid = Int32(lastPart) else { continue }

            if let bin = UInt64(parts[2]), let bout = UInt64(parts[3]) {
                let current = results[pid] ?? (0, 0)
                results[pid] = (current.bytesIn + bin, current.bytesOut + bout)
            }
        }
        return results
    }
    
    nonisolated private func parseLsof() -> [ProcessNetworkInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // Use -a to AND conditions: -i (network files only) AND -u (current user only)
        // -P -n to skip DNS/Port resolution
        process.arguments = ["-i", "-n", "-P", "-a", "-u", NSUserName()]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return Self.parseLsofOutput(output)
        } catch {
            return []
        }
    }

    nonisolated static func parseLsofOutput(_ output: String) -> [ProcessNetworkInfo] {
        var results: [ProcessNetworkInfo] = []
        let lines = output.components(separatedBy: "\n")
        
        for line in lines.dropFirst() { // Skip header
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // lsof -i -n -P output columns:
            // COMMAND  PID  USER  FD  TYPE  DEVICE  SIZE/OFF  NODE  NAME
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }
            
            let command = parts[0]
            guard let pid = Int32(parts[1]) else { continue }
            let user = parts[2]
            let fd = parts[3]
            let node = parts[7]  // TCP or UDP
            let nameField = parts[8...].joined(separator: " ")
            
            // Parse the NAME field
            var localAddr = ""
            var localPort = ""
            var remoteAddr = ""
            var remotePort = ""
            var state = ""
            
            // Extract state from parentheses
            if let stateRange = nameField.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
                state = String(nameField[stateRange]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            }
            
            // Remove the state part for address parsing
            let addrPart = nameField.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            
            if addrPart.contains("->") {
                // Connection: local->remote
                let sides = addrPart.components(separatedBy: "->")
                if sides.count == 2 {
                    (localAddr, localPort) = Self.splitAddressPort(sides[0])
                    (remoteAddr, remotePort) = Self.splitAddressPort(sides[1])
                }
            } else {
                // Listening or single address
                (localAddr, localPort) = Self.splitAddressPort(addrPart)
                if state.isEmpty { state = node == "TCP" ? "LISTEN" : "" }
            }
            
            // Skip kernel/launchd noise with no useful info
            guard !localAddr.isEmpty || !remoteAddr.isEmpty else { continue }
            
            // Handle edge case of UDP *:* which maps to * and *
            if localAddr == "*" && localPort == "*" {
                localPort = ""
            }
            if remoteAddr == "*" && remotePort == "*" {
                remotePort = ""
            }
            
            results.append(ProcessNetworkInfo(
                pid: pid,
                processName: command,
                user: user,
                fileDescriptor: fd,
                protocolType: node,
                localAddress: localAddr,
                localPort: localPort,
                remoteAddress: remoteAddr,
                remotePort: remotePort,
                state: state
            ))
        }
        
        return results
    }
    
    nonisolated static func splitAddressPort(_ str: String) -> (String, String) {
        // IPv6: [::1]:8080 or *:8080 or 127.0.0.1:8080
        let s = str.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") {
            // IPv6 bracketed
            if let closeBracket = s.firstIndex(of: "]") {
                let addr = String(s[s.index(after: s.startIndex)..<closeBracket])
                let afterBracket = s[s.index(after: closeBracket)...]
                if afterBracket.hasPrefix(":") {
                    let port = String(afterBracket.dropFirst())
                    return (addr, port)
                }
                return (addr, "")
            }
        }
        // Regular: find last colon
        if let lastColon = s.lastIndex(of: ":") {
            let addr = String(s[s.startIndex..<lastColon])
            let port = String(s[s.index(after: lastColon)...])
            return (addr, port)
        }
        return (s, "")
    }
    
    func killProcess(pid: Int32, completion: @escaping (Bool) -> Void) {
        // First try SIGTERM
        let result = kill(pid, SIGTERM)
        if result == 0 {
            LogManager.shared.info("Terminated process PID \(pid)")
            // Wait a moment then refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshProcessList()
                completion(true)
            }
            return
        }
        
        // If SIGTERM fails (e.g. permission denied), try with privilege escalation
        PrivilegedManager.shared.run("kill -9 \(pid)")
        
        LogManager.shared.info("Force-terminated process PID \(pid) with PrivilegedManager")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshProcessList()
            completion(true)
        }
    }
    
    /// Maximum tolerated gap between samples before we treat the new sample as
    /// a "fresh start" (system slept, interface restarted, refresh paused).
    /// Anything larger and the (current - prev) / elapsed math produces an
    /// average over the whole gap that misrepresents instantaneous speed.
    nonisolated static let maxValidElapsedMultiplier: TimeInterval = 5

    /// Aggregate speeds/bytes for the user's selection.
    ///
    /// Strategy for `selection == "all"`:
    /// - speeds: `max(physical_sum, tunnel_sum)` per direction so that
    ///   pure-VPN users see the real throughput (tunnel) without
    ///   double-counting the encrypted copy on the physical NIC.
    /// - bytes: physical sum (the canonical "what left the box") to keep the
    ///   cumulative counter monotonic across VPN connect/disconnect.
    /// Tunnel speeds/bytes are also returned separately for UI breakdowns.
    nonisolated static func aggregateTotals(
        from interfaces: [NetworkInterfaceStats],
        selection: String,
        primaryInterface: String? = nil
    ) -> (totalSpeedIn: Double, totalSpeedOut: Double,
          totalBytesIn: UInt64, totalBytesOut: UInt64,
          tunnelSpeedIn: Double, tunnelSpeedOut: Double,
          tunnelBytesIn: UInt64, tunnelBytesOut: UInt64) {
        let tunnel = interfaces.filter { $0.role == .tunnel }

        // 物理侧只统计「真正承载默认路由的那一个口」。
        // 把所有 physical 求和会把 anpi*/en1..en8 这类内部口、桥接成员一起算进来，
        // 同一份流量被重复计数，总速率因此虚高。
        let candidates = interfaces.filter { $0.role == .physical }
        let physical: [NetworkInterfaceStats]
        if let primaryInterface, let primary = candidates.first(where: { $0.id == primaryInterface }) {
            physical = [primary]
        } else if let busiest = candidates.max(by: { ($0.speedIn + $0.speedOut) < ($1.speedIn + $1.speedOut) }) {
            // 拿不到默认路由（断网 / route 不可用）时退化为速率最高的物理口。
            physical = [busiest]
        } else {
            physical = []
        }

        let physSpeedIn  = physical.reduce(0) { $0 + $1.speedIn }
        let physSpeedOut = physical.reduce(0) { $0 + $1.speedOut }

        // 隧道侧取「最忙的一条」而不是求和：macOS 上同时存在十余个 utun，
        // 链式封装（VPN 套 VPN / 私密中继）会让同一份载荷在多条 utun 上各记一次，
        // 求和得到的数字没有物理意义 —— 实测隧道求和 21.3 MB/s 而物理口只有 5.7 MB/s。
        let tunSpeedIn   = tunnel.map(\.speedIn).max() ?? 0
        let tunSpeedOut  = tunnel.map(\.speedOut).max() ?? 0

        let totalSpeedIn: Double
        let totalSpeedOut: Double
        let totalBytesIn: UInt64
        let totalBytesOut: UInt64

        if selection == "all" {
            // 「全部接口」= 整机对外速率 = 承载默认路由的物理口速率。
            // 隧道流量本就封装在物理口内，再叠加上去会超过物理线速，物理上不可能；
            // 隧道量另有 tunnelSpeed* 单独呈现，不并入总量。
            totalSpeedIn  = physSpeedIn
            totalSpeedOut = physSpeedOut
            totalBytesIn  = physical.reduce(0) { $0 + $1.bytesIn }
            totalBytesOut = physical.reduce(0) { $0 + $1.bytesOut }
        } else {
            let chosen = interfaces.filter { $0.id == selection }
            totalSpeedIn  = chosen.reduce(0) { $0 + $1.speedIn }
            totalSpeedOut = chosen.reduce(0) { $0 + $1.speedOut }
            totalBytesIn  = chosen.reduce(0) { $0 + $1.bytesIn }
            totalBytesOut = chosen.reduce(0) { $0 + $1.bytesOut }
        }

        return (
            totalSpeedIn, totalSpeedOut, totalBytesIn, totalBytesOut,
            tunSpeedIn, tunSpeedOut,
            tunnel.map(\.bytesIn).max() ?? 0,
            tunnel.map(\.bytesOut).max() ?? 0
        )
    }

    private func fetchStats() {
        guard !isFetchingStats else { return }
        isFetchingStats = true

        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let currentStats = self.parseNetstat()
            let now = Date()

            await MainActor.run {
                defer { self.isFetchingStats = false }
                if let prevTimestamp = self.previousTimestamp {
                    let elapsed = now.timeIntervalSince(prevTimestamp)
                    guard elapsed > 0 else { return }

                    // Bug #3 fix: after sleep/wake (or any long stall) the
                    // delta over a 1h window averages out to a misleading
                    // sub-1KB/s sample. Rebase silently instead.
                    let maxValid = self.refreshInterval * Self.maxValidElapsedMultiplier
                    if elapsed > maxValid {
                        self.previousStats.removeAll(keepingCapacity: true)
                        for iface in currentStats {
                            self.previousStats[iface.id] = (bytesIn: iface.bytesIn, bytesOut: iface.bytesOut)
                        }
                        self.previousTimestamp = now
                        return
                    }

                    var updatedInterfaces: [NetworkInterfaceStats] = []

                    for var iface in currentStats {
                        if let prev = self.previousStats[iface.id] {
                            let deltaIn = iface.bytesIn >= prev.bytesIn ? iface.bytesIn - prev.bytesIn : 0
                            let deltaOut = iface.bytesOut >= prev.bytesOut ? iface.bytesOut - prev.bytesOut : 0
                            iface.speedIn = Double(deltaIn) / elapsed
                            iface.speedOut = Double(deltaOut) / elapsed
                        }
                        updatedInterfaces.append(iface)
                    }

                    self.interfaces = updatedInterfaces.sorted { a, b in
                        // Priority: active with traffic > active no traffic > loopback > inactive
                        let aIsLo = a.name.starts(with: "lo")
                        let bIsLo = b.name.starts(with: "lo")
                        if a.isActive != b.isActive { return a.isActive }
                        if aIsLo != bIsLo { return !aIsLo }
                        let aTraffic = a.speedIn + a.speedOut
                        let bTraffic = b.speedIn + b.speedOut
                        if aTraffic != bTraffic { return aTraffic > bTraffic }
                        return a.displayName < b.displayName
                    }

                    let totals = Self.aggregateTotals(
                        from: self.interfaces,
                        selection: self.selectedInterface,
                        primaryInterface: self.defaultRouteInterface
                    )
                    self.totalSpeedIn = totals.totalSpeedIn
                    self.totalSpeedOut = totals.totalSpeedOut
                    self.totalBytesIn = totals.totalBytesIn
                    self.totalBytesOut = totals.totalBytesOut
                    self.tunnelSpeedIn = totals.tunnelSpeedIn
                    self.tunnelSpeedOut = totals.tunnelSpeedOut
                    self.tunnelBytesIn = totals.tunnelBytesIn
                    self.tunnelBytesOut = totals.tunnelBytesOut

                    // Add to history
                    let sample = SpeedSample(timestamp: now, speedIn: self.totalSpeedIn, speedOut: self.totalSpeedOut)
                    self.speedHistory.append(sample)
                    if self.speedHistory.count > self.maxHistoryCount {
                        self.speedHistory.removeFirst(self.speedHistory.count - self.maxHistoryCount)
                    }
                }

                // Store for next iteration
                self.previousStats = [:]
                for iface in currentStats {
                    self.previousStats[iface.id] = (bytesIn: iface.bytesIn, bytesOut: iface.bytesOut)
                }
                self.previousTimestamp = now
            }
        }
    }
    
    // MARK: - Parse netstat -bni
    
    nonisolated private func parseNetstat() -> [NetworkInterfaceStats] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-bni"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            return Self.parseNetstatOutput(output)
        } catch {
            return []
        }
    }

    nonisolated static func parseNetstatOutput(_ output: String) -> [NetworkInterfaceStats] {
        var results: [String: NetworkInterfaceStats] = [:]
        let lines = output.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return [] }
        
        // Parse header to find column indices
        let headerParts = headerLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        
        func findIdx(_ name: String) -> Int? {
            headerParts.firstIndex(of: name)
        }
        
        // Standard netstat -bni headers: Name, Mtu, Network, Address, Ipkts, Ierrs, Ibytes, Opkts, Oerrs, Obytes, [Coll]
        guard let iPktsIdx = findIdx("Ipkts"),
              let iErrsIdx = findIdx("Ierrs"),
              let iBytIdx = findIdx("Ibytes"),
              let oPktsIdx = findIdx("Opkts"),
              let oErrsIdx = findIdx("Oerrs"),
              let oBytIdx = findIdx("Obytes") else {
            return []
        }
        
        for line in lines.dropFirst() { 
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 6 else { continue }
            
            let name = parts[0]
            // We specifically want <Link#N> rows for byte counts
            guard parts.count > 2, parts[2].contains("<Link") else { continue }
            
            // Adjust indices based on whether 'Address' is present for this specific row
            // Header usually assumes 'Address' is present. If parts[2] is <Link>, 
            // then parts[3] might be the MAC address or physical info. 
            // If parts[3] is a large number, it's actually Ipkts (Address column is skipped in this row).
            
            // Refined Logic: Standard netstat -bni header:
            // 0:Name 1:Mtu 2:Network 3:Address 4:Ipkts ...
            // If Name, Mtu, Network are fixed, stats start at 3 or 4.
            
            let hasAddress = UInt64(parts[3]) == nil && parts[3] != "-"
            let actualIPktsIdx = hasAddress ? iPktsIdx : iPktsIdx - 1
            let offset = actualIPktsIdx - iPktsIdx
            
            func val(_ baseIdx: Int) -> UInt64 {
                let idx = baseIdx + offset
                guard idx >= 0, idx < parts.count else { return 0 }
                let s = parts[idx]
                if s == "-" { return 0 }
                return UInt64(s) ?? 0
            }
            
            // Bug #2 fix: macOS marks "down" interfaces with a trailing `*`
            // (e.g. `gif0*`, `en1*`). The asterisk flips on/off as the link
            // toggles, so we use a stable id (sans asterisk) for previousStats
            // lookups while keeping the raw name for display.
            let stableID = name.replacingOccurrences(of: "*", with: "")
            results[stableID] = NetworkInterfaceStats(
                id: stableID,
                name: name,
                bytesIn: val(iBytIdx),
                bytesOut: val(oBytIdx),
                packetsIn: val(iPktsIdx),
                packetsOut: val(oPktsIdx),
                errorsIn: val(iErrsIdx),
                errorsOut: val(oErrsIdx)
            )
        }
        
        return Array(results.values)
    }
    
    // MARK: - Formatting
    
    nonisolated static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else {
            return String(format: "%.2f GB/s", bytesPerSec / (1024 * 1024 * 1024))
        }
    }
    
    nonisolated static func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return String(format: "%.0f B", b)
        } else if b < 1024 * 1024 {
            return String(format: "%.1f KB", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", b / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
        }
    }
    
    // MARK: - Traffic History
    
    private func saveTrafficSnapshot() {
        guard totalBytesIn > 0 || totalBytesOut > 0 else { return }
        let snapshot = TrafficSnapshot(
            timestamp: Date().timeIntervalSince1970,
            bytesIn: totalBytesIn,
            bytesOut: totalBytesOut,
            speedIn: totalSpeedIn,
            speedOut: totalSpeedOut
        )
        trafficHistory.append(snapshot)
        pruneTrafficHistory()
        persistTrafficHistory()
    }
    
    private func pruneTrafficHistory() {
        let cutoff = Date().timeIntervalSince1970 - 7 * 24 * 3600 // 7 days
        trafficHistory.removeAll { $0.timestamp < cutoff }
    }
    
    private func persistTrafficHistory() {
        do {
            let data = try JSONEncoder().encode(trafficHistory)
            try data.write(to: trafficFilePath)
        } catch {
            // Silent fail
        }
    }
    
    private func loadTrafficHistory() {
        guard let data = try? Data(contentsOf: trafficFilePath),
              let history = try? JSONDecoder().decode([TrafficSnapshot].self, from: data) else { return }
        trafficHistory = history
        pruneTrafficHistory()
    }
    
    func trafficSnapshots(for range: TrafficTimeRange) -> [TrafficSnapshot] {
        let cutoff = Date().timeIntervalSince1970 - range.seconds
        return trafficHistory.filter { $0.timestamp >= cutoff }
    }
    
    func exportTrafficStats(for range: TrafficTimeRange) {
        let snapshots = trafficSnapshots(for: range)
        guard !snapshots.isEmpty else { return }
        
        var csv = "Timestamp,Date,BytesIn,BytesOut,SpeedIn,SpeedOut\n"
        let formatter = ISO8601DateFormatter()
        for s in snapshots {
            let dateStr = formatter.string(from: Date(timeIntervalSince1970: s.timestamp))
            csv += "\(s.timestamp),\(dateStr),\(s.bytesIn),\(s.bytesOut),\(s.speedIn),\(s.speedOut)\n"
        }
        
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "network_traffic_\(range.rawValue).csv"
            panel.begin { result in
                if result == .OK, let url = panel.url {
                    do {
                        try csv.write(to: url, atomically: true, encoding: .utf8)
                        LogManager.shared.info("Exported traffic stats to \(url.path)")
                    } catch {
                        LogManager.shared.error("Failed to export traffic stats: \(error)")
                    }
                }
            }
        }
    }
    
    func resetTrafficStats() {
        trafficHistory.removeAll()
        persistTrafficHistory()
        totalBytesIn = 0
        totalBytesOut = 0
        LogManager.shared.info("Reset traffic history")
    }
    
    func trafficTotals(for range: TrafficTimeRange) -> (bytesIn: UInt64, bytesOut: UInt64) {
        Self.trafficTotals(snapshots: trafficSnapshots(for: range))
    }

    /// Bug #4 fix: the previous implementation took only the first/last
    /// snapshot delta, which under-counted (or wildly over-counted) traffic
    /// whenever the underlying byte counter reset within the window — e.g.
    /// after a VPN reconnect, an interface bounce, or a Mac reboot.
    ///
    /// Walk *all* adjacent pairs and discard any pair where the counter
    /// went backwards; that pair contributes 0 instead of poisoning the
    /// total. The remaining monotonic deltas accumulate correctly.
    nonisolated static func trafficTotals(snapshots: [TrafficSnapshot]) -> (bytesIn: UInt64, bytesOut: UInt64) {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 2 else { return (0, 0) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        for i in 1..<ordered.count {
            let prev = ordered[i - 1]
            let curr = ordered[i]
            if curr.bytesIn >= prev.bytesIn {
                totalIn += curr.bytesIn - prev.bytesIn
            }
            if curr.bytesOut >= prev.bytesOut {
                totalOut += curr.bytesOut - prev.bytesOut
            }
        }
        return (totalIn, totalOut)
    }
}

enum TrafficTimeRange: String, CaseIterable {
    case thirtyMin = "30m"
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    
    var seconds: TimeInterval {
        switch self {
        case .thirtyMin: return 30 * 60
        case .oneHour: return 60 * 60
        case .twentyFourHours: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        }
    }
    
    var displayName: String {
        switch self {
        case .thirtyMin: return "30min"
        case .oneHour: return "1h"
        case .twentyFourHours: return "24h"
        case .sevenDays: return "7d"
        }
    }
}
