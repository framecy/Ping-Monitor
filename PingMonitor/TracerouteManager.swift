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
    
    // NTrace Data
    var asn: String?
    var location: String?
    
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
        if sent > 0 {
             let loss = Double(sent - received) / Double(sent) * 100
             return String(format: "%.0f%%", loss)
        }
        return String(format: "%.0f%%", packetLoss)
    }
}

// MARK: - Hop Line Parser (nonisolated, Sendable-safe)

/// Parse a single traceroute output line from standard macOS traceroute
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
    let tokens = content.split(separator: " ").map { String($0) }
    
    var hostName = "*"
    var ip = "*"
    var latencies: [Double?] = []
    
    var i = 0
    var latencyStartIndex = 0
    var foundLatencyStart = false
    
    // Scan for latencies
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
            i += 1
        } else {
            i += 1
        }
    }
    
    let validLatencies = latencies.compactMap { $0 }
    let avg = validLatencies.isEmpty ? nil : validLatencies.reduce(0, +) / Double(validLatencies.count)
    let totalProbes = max(latencies.count, 1)
    let timeoutCount = latencies.filter { $0 == nil }.count
    let loss = Double(timeoutCount) / Double(totalProbes) * 100
    
    // FIX: Traceroute local IP bug. Standard traceroute often outputs the localhost as hop 1 on some setups, or doesn't resolve remote correctly.
    // If we only get a 0ms local ping on hop 1, we can optionally filter it, but parseHopLine itself should just faithfully parse.
    
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
        worst: validLatencies.max(),
        asn: nil,
        location: nil
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
    
    @Published var isDownloading = false
    @Published var downloadProgress: String = ""
    @Published var mapUrl: String? = nil
    
    private var process: Process?
    private var mtrRound: Int = 0
    private var currentParsingHop: TracerouteHop?
    
    // MARK: - CLI Management
    
    private func getNextTracePath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let binDir = appSupport.appendingPathComponent("PingMonitor/bin")
        if !FileManager.default.fileExists(atPath: binDir.path) {
            try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        }
        return binDir.appendingPathComponent("nexttrace")
    }
    
    private func downloadNextTraceIfNeeded() async throws {
        let cliUrl = getNextTracePath()
        if FileManager.default.fileExists(atPath: cliUrl.path) {
            return
        }
        
        isDownloading = true
        downloadProgress = "Downloading NTrace-core..."
        
        var realArch = "arm64"
        #if arch(x86_64)
        realArch = "amd64"
        #endif
        
        let downloadStr = "https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_darwin_\(realArch)"
        guard let downloadUrl = URL(string: downloadStr) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: downloadUrl)
            try data.write(to: cliUrl)
            
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", cliUrl.path]
            try chmod.run()
            chmod.waitUntilExit()
            
            isDownloading = false
        } catch {
            isDownloading = false
            throw error
        }
    }
    
    private func fetchMapUrlInBackground(host: String) {
        Task.detached {
            let cliPath = await self.getNextTracePath().path
            let tempProc = Process()
            let pipe = Pipe()
            tempProc.standardOutput = pipe
            tempProc.standardError = pipe
            tempProc.executableURL = URL(fileURLWithPath: "/bin/sh")
            // Run nexttrace uniquely to fetch MapTrace URL (-t for table, simple fast trace)
            tempProc.arguments = ["-c", "'\(cliPath)' -t -m 20 -q 1 \(host) 2>&1"]
            
            do {
                try tempProc.run()
                tempProc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if let range = output.range(of: "MapTrace URL: https://") {
                         let urlStr = String(output[range.lowerBound...]).replacingOccurrences(of: "MapTrace URL: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                         let finalUrl = urlStr.components(separatedBy: "\n").first ?? urlStr
                         await MainActor.run {
                             self.mapUrl = finalUrl
                         }
                    }
                }
            } catch {
                // Ignore NextTrace failure
            }
        }
    }
    
    // MARK: - Traceroute
    
    func startTrace(host: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }
        
        stop()
        
        targetHost = trimmedHost
        hops = []
        mapUrl = nil
        isRunning = true
        progress = String(format: LanguageManager.shared.t("traceroute.tracing"), trimmedHost)
        
        LogManager.shared.info("Starting traceroute to \(trimmedHost)")
        
        Task {
            do {
                try await downloadNextTraceIfNeeded()
                fetchMapUrlInBackground(host: trimmedHost)
                
                if self.isMTRMode {
                    self.startMTRTrace(host: trimmedHost)
                } else {
                    self.startSingleTrace(host: trimmedHost)
                }
            } catch {
                self.isRunning = false
                self.progress = "Download failed: \(error.localizedDescription)"
                LogManager.shared.error("Failed to download nexttrace: \(error)")
            }
        }
    }
    
    func stop() {
        if let process = process, process.isRunning {
            process.terminate()
            LogManager.shared.info("Traceroute process terminated")
        }
        flushCurrentHop()
        process = nil
        mtrRound = 0
        isRunning = false
        if !hops.isEmpty {
            progress = String(format: LanguageManager.shared.t("traceroute.complete"), hops.count)
        }
    }
    
    // MARK: - Single Traceroute
    
    private func startSingleTrace(host: String) {
        let cliPath = getNextTracePath().path
        let proc = Process()
        let pipe = Pipe()
        
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "'\(cliPath)' -t -I -m \(maxHops) -q 3 \(host) 2>&1"]
        
        self.process = proc
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                Task { @MainActor [weak self] in
                    self?.parseTableLine(line)
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
                self.flushCurrentHop()
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
        
        let cliPath = getNextTracePath().path
        let proc = Process()
        let pipe = Pipe()
        
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "'\(cliPath)' -t -I -m \(maxHops) -q 1 \(host) 2>&1"]
        
        self.process = proc
        let roundHops = LockedArray<TracerouteHop>()
        let parser = MTRRoundParser(roundHops: roundHops)
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                parser.parseLine(line)
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
            parser.flush()
            let hops = roundHops.values
            
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                
                self.mergeRoundResults(hops)
                
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                if self.isRunning {
                    self.runMTRRound(host: host)
                }
            }
        }
    }
    
    // MARK: - Table Line Parser
    
    private func parseTableLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("Hop ") { return }
        
        if line.contains("MapTrace URL:") {
            if let urlRange = line.range(of: "https://") {
                let url = String(line[urlRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                self.mapUrl = url
            }
            return
        }
        
        let isNewHop = line.first?.isNumber == true
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
        
        if tokens.isEmpty { return }
        
        if isNewHop {
            flushCurrentHop()
            
            let hopNum = Int(tokens[0]) ?? 0
            var host = "*"
            var ip = "*"
            var lat: Double? = nil
            var asn: String? = nil
            var location: String? = nil
            
            var latencyIdx = -1
            for (idx, token) in tokens.enumerated() {
                if token.hasSuffix("ms") {
                    latencyIdx = idx
                    break
                }
            }
            
            if latencyIdx > 0 {
                lat = Double(tokens[latencyIdx].replacingOccurrences(of: "ms", with: ""))
                let hostTokens = tokens[1..<latencyIdx]
                if let first = hostTokens.first {
                    host = first
                    if hostTokens.count >= 2 {
                        let second = hostTokens[1]
                        if second.hasPrefix("(") && second.hasSuffix(")") {
                            ip = String(second.dropFirst().dropLast())
                        } else {
                            ip = host
                        }
                    } else {
                        ip = host
                    }
                }
                if latencyIdx + 1 < tokens.count {
                    let possibleAsn = tokens[latencyIdx + 1]
                    if possibleAsn != "*" {
                        asn = (possibleAsn.hasPrefix("AS") || Int(possibleAsn) != nil) ? (possibleAsn.hasPrefix("AS") ? possibleAsn : "AS\(possibleAsn)") : possibleAsn
                    }
                }
                if latencyIdx + 2 < tokens.count {
                    let locTokens = tokens[(latencyIdx + 2)...]
                    if !locTokens.isEmpty {
                        location = locTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    }
                }
            } else {
                if let starIdx = tokens.firstIndex(of: "*") {
                    let hostTokens = tokens[1..<starIdx]
                    if let first = hostTokens.first {
                        host = first
                        if hostTokens.count >= 2 {
                            let second = hostTokens[1]
                            if second.hasPrefix("(") && second.hasSuffix(")") {
                                ip = String(second.dropFirst().dropLast())
                            }
                        }
                    }
                }
            }
            
            var initLatencies: [Double?] = []
            if lat != nil { initLatencies.append(lat) }
            else if tokens.contains("*") { initLatencies.append(nil) }
            
            currentParsingHop = TracerouteHop(
                 hopNumber: hopNum, hostName: host, ip: ip, latencies: initLatencies, 
                 avgLatency: lat, packetLoss: lat == nil ? 100 : 0, isTimeout: lat == nil,
                 sent: 1, received: lat != nil ? 1 : 0, best: lat, worst: lat,
                 asn: asn, location: location
            )
        } else {
            guard var hop = currentParsingHop else { return }
            
            var lat: Double? = nil
            if let msIndex = tokens.firstIndex(where: { $0.hasSuffix("ms") }) {
                 lat = Double(tokens[msIndex].replacingOccurrences(of: "ms", with: ""))
            }
            
            hop.latencies.append(lat)
            hop.sent += 1
            if let lat = lat {
                 hop.received += 1
                 hop.best = min(hop.best ?? lat, lat)
                 hop.worst = max(hop.worst ?? lat, lat)
            }
            
            let validLats = hop.latencies.compactMap { $0 }
            hop.avgLatency = validLats.isEmpty ? nil : validLats.reduce(0, +) / Double(validLats.count)
            hop.packetLoss = Double(hop.sent - hop.received) / Double(hop.sent) * 100.0
            hop.isTimeout = validLats.isEmpty
            
            currentParsingHop = hop
        }
        
        if let hop = currentParsingHop {
            self.addOrUpdateHop(hop)
        }
    }
    
    private func flushCurrentHop() {
        if let hop = currentParsingHop {
            self.addOrUpdateHop(hop)
            currentParsingHop = nil
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
                var existing = hops[idx]
                
                if !roundHop.isTimeout && (existing.hostName == "*" || existing.hostName.isEmpty) {
                    existing.hostName = roundHop.hostName
                    existing.ip = roundHop.ip
                }
                
                existing.sent += roundHop.sent
                existing.received += roundHop.received
                
                let newLatency = roundHop.latencies.first ?? nil
                var displayLatencies = existing.latencies
                displayLatencies.append(newLatency)
                if displayLatencies.count > 3 {
                    displayLatencies = Array(displayLatencies.suffix(3))
                }
                existing.latencies = displayLatencies
                
                if let newLat = newLatency {
                    existing.best = min(existing.best ?? newLat, newLat)
                    existing.worst = max(existing.worst ?? newLat, newLat)
                    
                    let oldRec = Double(existing.received - 1)
                     let oldAvg = existing.avgLatency ?? 0
                     let newTotal = (oldAvg * oldRec) + newLat
                     existing.avgLatency = newTotal / Double(existing.received)
                }
                
                existing.isTimeout = (existing.received == 0)
                if existing.sent > 0 {
                    existing.packetLoss = Double(existing.sent - existing.received) / Double(existing.sent) * 100.0
                }
                
                hops[idx] = existing
            } else {
                var newHop = roundHop
                if newHop.sent == 0 {
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
        var text = "NextTrace to \(targetHost)\n"
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
        
        if let map = mapUrl {
            text += "\nMapTrace URL: \(map)\n"
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

// MARK: - MTR Parser Helper

final class MTRRoundParser: @unchecked Sendable {
    private let roundHops: LockedArray<TracerouteHop>
    private let lock = NSLock()
    
    init(roundHops: LockedArray<TracerouteHop>) {
        self.roundHops = roundHops
    }
    
    func parseLine(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if let hop = parseHopLine(line) {
            roundHops.append(hop)
        }
    }
    
    func flush() {
        // No-op for standard traceroute which parses completely line by line
    }
}
