import Foundation
import SwiftUI

// MARK: - Data Models

struct TracerouteHop: Identifiable, Sendable {
    let id = UUID()
    let hopNumber: Int
    var hostName: String
    var ip: String
    var latencies: [Double?]  // Up to 3 latency probes (most recent for MTR)
    var avgLatency: Double?
    var packetLoss: Double     // 0.0 - 100.0
    var isTimeout: Bool
    
    // MTR Cumulative Stats
    var sent: Int = 0
    var received: Int = 0
    var best: Double?
    var worst: Double?
    
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
        if sent == 0 { return "0%" }
        // If we have MTR stats, calculated based on sent/received
        // Otherwise use the snapshot loss
        if sent > 0 {
             let loss = Double(sent - received) / Double(sent) * 100
             return String(format: "%.0f%%", loss)
        }
        return String(format: "%.0f%%", packetLoss)
    }
}

// MARK: - Hop Line Parser (nonisolated, Sendable-safe)

/// Parse a single traceroute output line
func parseHopLine(_ line: String) -> TracerouteHop? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    
    // 1. Hop Number
    let range = NSRange(location: 0, length: trimmed.utf16.count)
    let hopRegex = try? NSRegularExpression(pattern: "^(\\d+)\\s+(.*)$")
    guard let regex = hopRegex,
          let match = regex.firstMatch(in: trimmed, options: [], range: range),
          let hopNumRange = Range(match.range(at: 1), in: trimmed),
          let hopNumber = Int(trimmed[hopNumRange]),
          let restRange = Range(match.range(at: 2), in: trimmed) else {
        return nil
    }
    
    // Ignore hop 0 or negative
    guard hopNumber > 0 else { return nil }
    
    let content = String(trimmed[restRange]).trimmingCharacters(in: .whitespaces)
    
    // Tokenize by spaces
    let tokens = content.split(separator: " ").map { String($0) }
    
    var hostName = "*"
    var ip = "*"
    var latencies: [Double?] = []
    
    var i = 0
    var latencyStartIndex = 0
    var foundLatencyStart = false
    
    // 2. Scan for start of latencies (number followed by ms, or *)
    while i < tokens.count {
        let t = tokens[i]
        
        if t == "*" {
            foundLatencyStart = true
            latencyStartIndex = i
            break
        }
        
        if let _ = Double(t), i + 1 < tokens.count, tokens[i+1] == "ms" {
            foundLatencyStart = true
            latencyStartIndex = i
            break
        }
        
        i += 1
    }
    
    if foundLatencyStart {
        // Everything before is Host/IP
        let hostTokens = tokens[0..<latencyStartIndex]
        if !hostTokens.isEmpty {
            let hostStr = hostTokens.joined(separator: " ")
            
            let ipParenRegex = try? NSRegularExpression(pattern: "^(\\S+)\\s+\\(([\\d\\.:]+)\\)")
            let simpleIpRegex = try? NSRegularExpression(pattern: "^([\\d\\.:]+)$")
            let hostRange = NSRange(location: 0, length: hostStr.utf16.count)
            
            if let regex = ipParenRegex,
               let m = regex.firstMatch(in: hostStr, options: [], range: hostRange),
               let r1 = Range(m.range(at: 1), in: hostStr),
               let r2 = Range(m.range(at: 2), in: hostStr) {
                hostName = String(hostStr[r1])
                ip = String(hostStr[r2])
            } else if let regex = simpleIpRegex,
                      let _ = regex.firstMatch(in: hostStr, options: [], range: hostRange) {
                hostName = hostStr
                ip = hostStr
            } else {
                 hostName = hostStr
                 ip = hostStr
            }
        }
    }
    
    // 3. Parse Latencies
    i = latencyStartIndex
    while i < tokens.count {
        let t = tokens[i]
        
        if t == "*" {
            latencies.append(nil)
            i += 1
        } else if let val = Double(t), i+1 < tokens.count, tokens[i+1] == "ms" {
            latencies.append(val)
            i += 2
        } else if t.hasPrefix("!") {
            // Error flag (e.g. !X), ignore for latency value but consume
            i += 1
        } else {
            // Unknown token, skip
            i += 1
        }
    }
    
    // Stats calculation
    let validLatencies = latencies.compactMap { $0 }
    let avg = validLatencies.isEmpty ? nil : validLatencies.reduce(0, +) / Double(validLatencies.count)
    let totalProbes = max(latencies.count, 1)
    let timeoutCount = latencies.filter { $0 == nil }.count
    let loss = Double(timeoutCount) / Double(totalProbes) * 100
    
    return TracerouteHop(
        hopNumber: hopNumber,
        hostName: hostName,
        ip: ip,
        latencies: latencies,
        avgLatency: avg,
        packetLoss: loss,
        isTimeout: validLatencies.isEmpty,
        sent: latencies.count,
        received: validLatencies.count,
        best: validLatencies.min(),
        worst: validLatencies.max()
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
        // Use -I (ICMP) as it's generally more standard for reading, but if it fails, we might want UDP.
        // For now sticking to -I as in original, but with better parsing.
        proc.arguments = ["-c", "/usr/sbin/traceroute -I -m \(maxHops) -q 3 -w 1 \(host) 2>&1"]
        
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
        // MTR mode: quick probes (-q 1), wait 1s (-w 1)
        proc.arguments = ["-c", "/usr/sbin/traceroute -I -m \(maxHops) -q 1 -w 1 \(host) 2>&1"]
        
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
            hops.sort { $0.hopNumber < $1.hopNumber }
        }
        progress = String(format: LanguageManager.shared.t("traceroute.tracing"), targetHost) + " (\(hops.count)/\(maxHops))"
    }
    
    private func mergeRoundResults(_ roundHops: [TracerouteHop]) {
        for roundHop in roundHops {
            if let idx = hops.firstIndex(where: { $0.hopNumber == roundHop.hopNumber }) {
                // Update existing hop with new data
                var existing = hops[idx]
                
                // Update hostname/ip if we got a real one (prioritize non-star)
                if !roundHop.isTimeout && (existing.hostName == "*" || existing.hostName.isEmpty) {
                    existing.hostName = roundHop.hostName
                    existing.ip = roundHop.ip
                }
                
                // Accumulate stats
                existing.sent += roundHop.sent
                existing.received += roundHop.received
                
                // Update latencies (keep last 3 for display)
                let newLatency = roundHop.latencies.first ?? nil
                var displayLatencies = existing.latencies
                displayLatencies.append(newLatency)
                if displayLatencies.count > 3 {
                    displayLatencies = Array(displayLatencies.suffix(3))
                }
                existing.latencies = displayLatencies
                
                // Accumulate Min/Max
                if let newLat = newLatency {
                    existing.best = min(existing.best ?? newLat, newLat)
                    existing.worst = max(existing.worst ?? newLat, newLat)
                    
                    // Update rolling Average
                    // We need a way to store sum. Since we don't have it in struct explicitly,
                    // we can approximate or if we want precision, calculate from avg * count.
                    // But `received` is the count of valid latencies.
                    // New Avg = ((Old Avg * Old Count) + New Val) / New Count
                    let oldRec = Double(existing.received - 1) // we already incremented received
                     let oldAvg = existing.avgLatency ?? 0
                     let newTotal = (oldAvg * oldRec) + newLat
                     existing.avgLatency = newTotal / Double(existing.received)
                }
                
                // Loss is calculated dynamically in the property based on sent/received
                
                existing.isTimeout = (existing.received == 0)
                // If it was a timeout this round, packetLoss property update handled by computed var?
                // No, existing.packetLoss is a stored property in struct, we need to update it for the View to see it if it uses the stored prop.
                // The struct has computed `formattedLoss` but stored `packetLoss`.
                // Let's update stored `packetLoss` too.
                if existing.sent > 0 {
                    existing.packetLoss = Double(existing.sent - existing.received) / Double(existing.sent) * 100.0
                }
                
                hops[idx] = existing
            } else {
                // New hop
                var newHop = roundHop
                // Initialize MTR counters if not already (parseHopLine does it, but check)
                if newHop.sent == 0 { // Should match latencies.count
                    newHop.sent = newHop.latencies.count
                    newHop.received = newHop.latencies.compactMap{$0}.count
                    newHop.best = newHop.latencies.compactMap{$0}.min()
                    newHop.worst = newHop.latencies.compactMap{$0}.max()
                }
                hops.append(newHop)
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
