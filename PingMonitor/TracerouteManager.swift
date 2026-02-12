import Foundation
import SwiftUI

// MARK: - Data Models

struct TracerouteHop: Identifiable, Sendable {
    let id = UUID()
    let hopNumber: Int
    var hostName: String
    var ip: String
    var latencies: [Double?]  // Up to 3 latency probes
    var avgLatency: Double?
    var packetLoss: Double     // 0.0 - 100.0
    var isTimeout: Bool
    
    var latencyColor: Color {
        guard let avg = avgLatency else { return .gray }
        if avg < 50 { return .green }
        if avg < 100 { return .orange }
        return .red
    }
    
    var formattedAvg: String {
        guard let avg = avgLatency else { return "*" }
        return String(format: "%.1f ms", avg)
    }
    
    var formattedLoss: String {
        if isTimeout { return "100%" }
        return String(format: "%.0f%%", packetLoss)
    }
}

// MARK: - Hop Line Parser (nonisolated, Sendable-safe)

/// Parse a single traceroute output line like:
///  1  router.local (192.168.1.1)  1.234 ms  1.456 ms  1.789 ms
///  2  * * *
///  3  10.0.0.1 (10.0.0.1)  5.678 ms  * 6.123 ms
func parseHopLine(_ line: String) -> TracerouteHop? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    
    // Must start with a hop number
    guard let firstSpaceIdx = trimmed.firstIndex(of: " "),
          let hopNumber = Int(trimmed[trimmed.startIndex..<firstSpaceIdx]) else {
        return nil
    }
    
    // Ignore hop 0 or negative
    guard hopNumber > 0 else { return nil }
    
    let rest = String(trimmed[firstSpaceIdx...]).trimmingCharacters(in: .whitespaces)
    
    // Check if all timeouts: "* * *"
    if rest.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: " ", with: "").isEmpty {
        return TracerouteHop(
            hopNumber: hopNumber,
            hostName: "*",
            ip: "*",
            latencies: [nil, nil, nil],
            avgLatency: nil,
            packetLoss: 100,
            isTimeout: true
        )
    }
    
    // Extract hostname and IP
    var hostName = ""
    var ip = ""
    var latencies: [Double?] = []
    
    // Try to extract hostname (IP) pattern
    let ipPattern = #"(\S+)\s+\(([^)]+)\)"#
    if let regex = try? NSRegularExpression(pattern: ipPattern),
       let match = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) {
        if let nameRange = Range(match.range(at: 1), in: rest) {
            hostName = String(rest[nameRange])
        }
        if let ipRange = Range(match.range(at: 2), in: rest) {
            ip = String(rest[ipRange])
        }
    } else {
        // Try simple IP-only format
        let parts = rest.split(separator: " ")
        if let first = parts.first {
            let firstStr = String(first)
            if firstStr.contains(".") || firstStr.contains(":") {
                ip = firstStr
                hostName = firstStr
            }
        }
    }
    
    // Extract latency values (ms)
    let latencyPattern = #"(\d+\.?\d*)\s*ms"#
    if let regex = try? NSRegularExpression(pattern: latencyPattern) {
        let matches = regex.matches(in: rest, range: NSRange(rest.startIndex..., in: rest))
        for match in matches {
            if let range = Range(match.range(at: 1), in: rest),
               let val = Double(String(rest[range])) {
                latencies.append(val)
            }
        }
    }
    
    // Count timeouts in the rest (standalone *)
    let starPattern = #"(?<!\S)\*(?!\S)"#
    if let regex = try? NSRegularExpression(pattern: starPattern) {
        let starCount = regex.numberOfMatches(in: rest, range: NSRange(rest.startIndex..., in: rest))
        for _ in 0..<starCount {
            latencies.append(nil)
        }
    }
    
    // Calculate average
    let validLatencies = latencies.compactMap { $0 }
    let avg = validLatencies.isEmpty ? nil : validLatencies.reduce(0, +) / Double(validLatencies.count)
    let totalProbes = max(latencies.count, 1)
    let timeoutCount = latencies.filter { $0 == nil }.count
    let loss = Double(timeoutCount) / Double(totalProbes) * 100
    
    return TracerouteHop(
        hopNumber: hopNumber,
        hostName: hostName.isEmpty ? ip : hostName,
        ip: ip.isEmpty ? hostName : ip,
        latencies: latencies,
        avgLatency: avg,
        packetLoss: loss,
        isTimeout: validLatencies.isEmpty
    )
}

// MARK: - Traceroute Manager

@MainActor
class TracerouteManager: ObservableObject {
    @Published var hops: [TracerouteHop] = []
    @Published var isRunning = false
    @Published var progress: String = ""
    @Published var isMTRMode = false
    @Published var targetHost: String = ""
    @Published var maxHops: Int = 30
    
    private var process: Process?
    private var mtrRound: Int = 0
    
    // MARK: - Traceroute
    
    func startTrace(host: String) {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        stop()
        
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        targetHost = trimmedHost
        hops = []
        isRunning = true
        progress = String(format: LanguageManager.shared.t("traceroute.tracing"), trimmedHost)
        
        LogManager.shared.info("Starting traceroute to \(trimmedHost)")
        
        if isMTRMode {
            startMTRTrace(host: trimmedHost)
        } else {
            startSingleTrace(host: trimmedHost)
        }
    }
    
    func stop() {
        if let process = process, process.isRunning {
            process.terminate()
            LogManager.shared.info("Traceroute process terminated")
        }
        process = nil
        mtrRound = 0
        isRunning = false
        if !hops.isEmpty {
            progress = String(format: LanguageManager.shared.t("traceroute.complete"), hops.count)
        }
    }
    
    // MARK: - Single Traceroute
    
    private func startSingleTrace(host: String) {
        let proc = Process()
        let pipe = Pipe()
        
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "/usr/sbin/traceroute -I -m \(maxHops) -q 3 \(host) 2>&1"]
        
        self.process = proc
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }
            
            // Process each line
            output.enumerateLines { line, _ in
                if let hop = parseHopLine(line) {
                    Task { @MainActor [weak self] in
                        self?.addOrUpdateHop(hop)
                    }
                }
            }
        }
        
        do {
            try proc.run()
        } catch {
            LogManager.shared.error("Failed to start traceroute: \(error)")
            isRunning = false
            progress = "Error: \(error.localizedDescription)"
        }
        
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRunning = false
                if !self.hops.isEmpty {
                    self.progress = String(format: LanguageManager.shared.t("traceroute.complete"), self.hops.count)
                }
                LogManager.shared.info("Traceroute completed with \(self.hops.count) hops")
            }
        }
    }
    
    // MARK: - MTR Mode (repeated traceroute)
    
    private func startMTRTrace(host: String) {
        mtrRound = 0
        runMTRRound(host: host)
    }
    
    private func runMTRRound(host: String) {
        guard isRunning else { return }
        
        mtrRound += 1
        let roundNum = mtrRound
        progress = "MTR Round #\(roundNum) → \(host)"
        
        let proc = Process()
        let pipe = Pipe()
        
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "/usr/sbin/traceroute -I -m \(maxHops) -q 1 -w 2 \(host) 2>&1"]
        
        self.process = proc
        
        let roundHops = LockedArray<TracerouteHop>()
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                if let hop = parseHopLine(line) {
                    roundHops.append(hop)
                }
            }
        }
        
        do {
            try proc.run()
        } catch {
            LogManager.shared.error("Failed to start MTR round: \(error)")
            isRunning = false
            return
        }
        
        proc.terminationHandler = { [weak self] _ in
            let hops = roundHops.values
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                
                // Merge round results into cumulative hops
                self.mergeRoundResults(hops)
                
                // Schedule next round after 1 second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                if self.isRunning {
                    self.runMTRRound(host: host)
                }
            }
        }
    }
    
    // MARK: - Hop Management
    
    private func addOrUpdateHop(_ hop: TracerouteHop) {
        if let idx = hops.firstIndex(where: { $0.hopNumber == hop.hopNumber }) {
            hops[idx] = hop
        } else {
            hops.append(hop)
        }
        progress = String(format: LanguageManager.shared.t("traceroute.tracing"), targetHost) + " (\(hops.count)/\(maxHops))"
    }
    
    private func mergeRoundResults(_ roundHops: [TracerouteHop]) {
        for roundHop in roundHops {
            if let idx = hops.firstIndex(where: { $0.hopNumber == roundHop.hopNumber }) {
                // Update existing hop with new data
                var existing = hops[idx]
                
                // Update hostname/ip if we got a real one
                if !roundHop.isTimeout {
                    existing.hostName = roundHop.hostName
                    existing.ip = roundHop.ip
                }
                
                // Add new latency and recalculate average
                let newLatency = roundHop.latencies.first ?? nil
                var allLatencies = existing.latencies
                allLatencies.append(newLatency)
                
                // Keep only last 10 latencies
                if allLatencies.count > 10 {
                    allLatencies = Array(allLatencies.suffix(10))
                }
                existing.latencies = allLatencies
                
                let validLatencies = allLatencies.compactMap { $0 }
                if !validLatencies.isEmpty {
                    existing.avgLatency = validLatencies.reduce(0, +) / Double(validLatencies.count)
                    let totalProbes = allLatencies.count
                    let timeouts = allLatencies.filter { $0 == nil }.count
                    existing.packetLoss = Double(timeouts) / Double(totalProbes) * 100
                    existing.isTimeout = false
                } else {
                    existing.isTimeout = true
                    existing.packetLoss = 100
                }
                
                hops[idx] = existing
            } else {
                // New hop number, add it
                hops.append(roundHop)
                hops.sort { $0.hopNumber < $1.hopNumber }
            }
        }
    }
    
    // MARK: - Export
    
    func copyResultsToClipboard() {
        var text = "Traceroute to \(targetHost)\n"
        text += String(repeating: "-", count: 70) + "\n"
        text += "Hop  Host/IP                        Avg Latency  Loss\n"
        text += String(repeating: "-", count: 70) + "\n"
        
        for hop in hops {
            let hostStr = hop.hostName == hop.ip ? hop.ip : "\(hop.hostName) (\(hop.ip))"
            let hopNum = String(hop.hopNumber).padding(toLength: 4, withPad: " ", startingAt: 0)
            let hostPad = String(hostStr.prefix(30)).padding(toLength: 30, withPad: " ", startingAt: 0)
            let avgPad = hop.formattedAvg.padding(toLength: 12, withPad: " ", startingAt: 0)
            text += "\(hopNum) \(hostPad) \(avgPad) \(hop.formattedLoss)\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Thread-safe array for collecting hops in background

final class LockedArray<T: Sendable>: @unchecked Sendable {
    private var array: [T] = []
    private let lock = NSLock()
    
    func append(_ element: T) {
        lock.lock()
        array.append(element)
        lock.unlock()
    }
    
    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return array
    }
}
