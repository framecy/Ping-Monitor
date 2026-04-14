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

    var role: InterfaceRole {
        switch name {
        case let n where n.starts(with: "utun") || n.starts(with: "ipsec"):
            return .tunnel
        case let n where n.starts(with: "lo"):
            return .loopback
        case let n where
            n.starts(with: "awdl") ||
            n.starts(with: "llw") ||
            n.starts(with: "gif") ||
            n.starts(with: "stf") ||
            n.starts(with: "bridge") ||
            n.starts(with: "ap"):
            return .virtual
        default:
            return .physical
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
    
    private var timer: Timer?
    private var snapshotTimer: Timer?
    private var processTimer: Timer?
    private var previousStats: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTimestamp: Date?
    
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
            let connections = self.parseLsof()
            let traffic = self.fetchProcessTraffic()
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
            
            var results: [Int32: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
            let lines = output.components(separatedBy: "\n")
            
            for line in lines {
                let parts = line.components(separatedBy: ",")
                // nettop -P CSV columns: time(0), process.pid(1), bytes_in(2), bytes_out(3), ...
                guard parts.count >= 4 else { continue }
                
                // Column 1 is "name.PID"
                let procPart = parts[1]
                let procComponents = procPart.components(separatedBy: ".")
                guard let lastPart = procComponents.last, let pid = Int32(lastPart) else { continue }
                
                // Column 2 is bytes_in, 3 is bytes_out
                if let bin = UInt64(parts[2]), let bout = UInt64(parts[3]) {
                    // Aggregate just in case multiple entries appear for same PID
                    let current = results[pid] ?? (0, 0)
                    results[pid] = (current.bytesIn + bin, current.bytesOut + bout)
                }
            }
            return results
        } catch {
            return [:]
        }
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
            return parseLsofOutput(output)
        } catch {
            return []
        }
    }
    
    nonisolated private func parseLsofOutput(_ output: String) -> [ProcessNetworkInfo] {
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
                    (localAddr, localPort) = splitAddressPort(sides[0])
                    (remoteAddr, remotePort) = splitAddressPort(sides[1])
                }
            } else {
                // Listening or single address
                (localAddr, localPort) = splitAddressPort(addrPart)
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
    
    nonisolated private func splitAddressPort(_ str: String) -> (String, String) {
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
    
    private func fetchStats() {
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let currentStats = self.parseNetstat()
            let now = Date()
            
            await MainActor.run {
                if let prevTimestamp = self.previousTimestamp {
                    let elapsed = now.timeIntervalSince(prevTimestamp)
                    guard elapsed > 0 else { return }
                    
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
                    
                    // Calculate totals based on selection
                    let physicalIfaces = self.interfaces.filter { $0.role == .physical }
                    let tunnelIfaces = self.interfaces.filter { $0.role == .tunnel }

                    let selectedIfaces: [NetworkInterfaceStats]
                    if self.selectedInterface == "all" {
                        // Preserve physical totals for "internet-facing" traffic and
                        // expose tunnel traffic separately to avoid VPN double-counting.
                        selectedIfaces = physicalIfaces
                    } else {
                        selectedIfaces = self.interfaces.filter { $0.id == self.selectedInterface }
                    }
                    
                    self.totalSpeedIn = selectedIfaces.reduce(0) { $0 + $1.speedIn }
                    self.totalSpeedOut = selectedIfaces.reduce(0) { $0 + $1.speedOut }
                    self.totalBytesIn = selectedIfaces.reduce(0) { $0 + $1.bytesIn }
                    self.totalBytesOut = selectedIfaces.reduce(0) { $0 + $1.bytesOut }
                    self.tunnelSpeedIn = tunnelIfaces.reduce(0) { $0 + $1.speedIn }
                    self.tunnelSpeedOut = tunnelIfaces.reduce(0) { $0 + $1.speedOut }
                    self.tunnelBytesIn = tunnelIfaces.reduce(0) { $0 + $1.bytesIn }
                    self.tunnelBytesOut = tunnelIfaces.reduce(0) { $0 + $1.bytesOut }
                    
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
            
            return parseNetstatOutput(output)
        } catch {
            return []
        }
    }
    
    nonisolated private func parseNetstatOutput(_ output: String) -> [NetworkInterfaceStats] {
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
            
            results[name] = NetworkInterfaceStats(
                id: name,
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
    
    static func formatSpeed(_ bytesPerSec: Double) -> String {
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
    
    static func formatBytes(_ bytes: UInt64) -> String {
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
        // Use the latest snapshot's cumulative bytes vs the earliest in range
        let snapshots = trafficSnapshots(for: range)
        guard let first = snapshots.first, let last = snapshots.last else { return (0, 0) }
        let deltaIn = last.bytesIn >= first.bytesIn ? last.bytesIn - first.bytesIn : last.bytesIn
        let deltaOut = last.bytesOut >= first.bytesOut ? last.bytesOut - first.bytesOut : last.bytesOut
        return (deltaIn, deltaOut)
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
