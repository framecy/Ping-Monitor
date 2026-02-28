import Foundation
import Combine

// MARK: - Network Interface Data

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
    @Published var speedHistory: [SpeedSample] = []
    @Published var isMonitoring = false
    @Published var refreshInterval: TimeInterval = 1.0
    @Published var trafficHistory: [TrafficSnapshot] = []
    
    private var timer: Timer?
    private var snapshotTimer: Timer?
    private var previousStats: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTimestamp: Date?
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
    
    private func fetchStats() {
        let currentStats = parseNetstat()
        let now = Date()
        
        if let prevTimestamp = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTimestamp)
            guard elapsed > 0 else { return }
            
            var updatedInterfaces: [NetworkInterfaceStats] = []
            
            for var iface in currentStats {
                if let prev = previousStats[iface.id] {
                    let deltaIn = iface.bytesIn >= prev.bytesIn ? iface.bytesIn - prev.bytesIn : 0
                    let deltaOut = iface.bytesOut >= prev.bytesOut ? iface.bytesOut - prev.bytesOut : 0
                    iface.speedIn = Double(deltaIn) / elapsed
                    iface.speedOut = Double(deltaOut) / elapsed
                }
                updatedInterfaces.append(iface)
            }
            
            interfaces = updatedInterfaces.sorted { a, b in
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
            let selectedIfaces: [NetworkInterfaceStats]
            if selectedInterface == "all" {
                // Exclude loopback
                selectedIfaces = interfaces.filter { !$0.name.starts(with: "lo") }
            } else {
                selectedIfaces = interfaces.filter { $0.id == selectedInterface }
            }
            
            totalSpeedIn = selectedIfaces.reduce(0) { $0 + $1.speedIn }
            totalSpeedOut = selectedIfaces.reduce(0) { $0 + $1.speedOut }
            totalBytesIn = selectedIfaces.reduce(0) { $0 + $1.bytesIn }
            totalBytesOut = selectedIfaces.reduce(0) { $0 + $1.bytesOut }
            
            // Add to history
            let sample = SpeedSample(timestamp: now, speedIn: totalSpeedIn, speedOut: totalSpeedOut)
            speedHistory.append(sample)
            if speedHistory.count > maxHistoryCount {
                speedHistory.removeFirst(speedHistory.count - maxHistoryCount)
            }
        }
        
        // Store for next iteration
        previousStats = [:]
        for iface in currentStats {
            previousStats[iface.id] = (bytesIn: iface.bytesIn, bytesOut: iface.bytesOut)
        }
        previousTimestamp = now
    }
    
    // MARK: - Parse netstat -bni
    
    private func parseNetstat() -> [NetworkInterfaceStats] {
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
    
    private func parseNetstatOutput(_ output: String) -> [NetworkInterfaceStats] {
        var results: [String: NetworkInterfaceStats] = [:]
        let lines = output.components(separatedBy: "\n")
        
        for line in lines.dropFirst() { // Skip header
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // netstat -bni format varies:
            // Standard: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
            // VPN/utun: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes (No Coll)
            
            let c = parts.count
            guard c >= 9 else { continue } // Minimum columns needed
            
            let name = parts[0]
            // Skip non-link entries
            guard parts[2].contains("<Link") else { continue }
            
            // Heuristic to detect column mapping:
            // If the last element is likely 'Collisions' (small number vs bytes), offsets are different.
            // Usually, 'bytes' are much larger than 'errors' or 'collisions'.
            
            // Indices from the end:
            // -1: Coll (optional)
            // -2: Obytes
            // -3: Oerrs
            // -4: Opkts
            // -5: Ibytes
            // -6: Ierrs
            // -7: Ipkts
            
            // In macOS 15+, for utun, if the last column is a large number, it's Obytes.
            // If it's a small number or 0 and followed by a large Obytes, it might be Coll.
            
            // Safer approach: netstat -bni always has:
            // ... Ipkts Ierrs Ibytes Opkts Oerrs Obytes [Coll]
            // We search for the pattern: [Number, Number, LargeNumber, Number, Number, LargeNumber]
            
            // Let's assume the standard 'Link' row for macOS:
            // If parts.last is NOT a huge number, it's probably 'Coll' (even if it's 0)
            // If parts.last IS a huge number, 'Coll' is missing.
            
            let hasCollisions = c >= 11 || (UInt64(parts[c-1]) ?? 0 < 1000000 && c >= 10)
            let offset = hasCollisions ? 1 : 0
            
            guard let pktsIn = UInt64(parts[c - 7 - offset]),
                  let errIn = UInt64(parts[c - 6 - offset]),
                  let bytIn = UInt64(parts[c - 5 - offset]),
                  let pktsOut = UInt64(parts[c - 4 - offset]),
                  let errOut = UInt64(parts[c - 3 - offset]),
                  let bytOut = UInt64(parts[c - 2 - offset]) else { continue }
            
            results[name] = NetworkInterfaceStats(
                id: name,
                name: name,
                bytesIn: bytIn,
                bytesOut: bytOut,
                packetsIn: pktsIn,
                packetsOut: pktsOut,
                errorsIn: errIn,
                errorsOut: errOut
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
