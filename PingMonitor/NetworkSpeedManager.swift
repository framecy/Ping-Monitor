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
    
    private var timer: Timer?
    private var previousStats: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTimestamp: Date?
    private let maxHistoryCount = 60  // 60 samples = 1 minute at 1s interval
    
    private init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Initial fetch
        fetchStats()
        
        // Update every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchStats()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
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
                if a.isActive != b.isActive { return a.isActive }
                return (a.speedIn + a.speedOut) > (b.speedIn + b.speedOut)
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
            // netstat -bni format:
            // Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes
            // en0  1500  <Link#4>      ...  12345  0     67890  54321  0     98765
            
            guard parts.count >= 10 else { continue }
            
            let name = parts[0]
            // Skip non-link entries (we want <Link#N> rows for byte counts)
            guard parts[2].contains("Link") else { continue }
            
            guard let pktsIn = UInt64(parts[4]),
                  let errIn = UInt64(parts[5]),
                  let bytIn = UInt64(parts[6]),
                  let pktsOut = UInt64(parts[7]),
                  let errOut = UInt64(parts[8]),
                  let bytOut = UInt64(parts[9]) else { continue }
            
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
}
