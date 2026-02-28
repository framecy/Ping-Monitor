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
    
    // GeoLocation Data
    var geoLocation: GeoLocation?

    
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
        geoLocation: nil,
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
        
        // Fetch origin location (Hop 0)
        fetchOriginLocation()
        
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
            LogManager.shared.info("Traceroute tail process terminated")
        }
        
        // Ensure any running traceroute process spawned by osascript is killed
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProc.arguments = ["-9", "-f", "traceroute -I"]
        try? killProc.run()
        
        process = nil
        mtrRound = 0
        isRunning = false
        if !hops.isEmpty {
            progress = String(format: LanguageManager.shared.t("traceroute.complete"), hops.count)
        }
    }
    
    func clear() {
        stop()
        hops.removeAll()
        targetHost = ""
        progress = ""
    }
    
    // MARK: - Single Traceroute
    
    private func startSingleTrace(host: String) {
        let proc = Process()
        let pipe = Pipe()
        
        proc.standardOutput = pipe
        proc.standardError = pipe
        // On macOS, ICMP traceroute (-I) requires root.
        // We'll use osascript to run it with administrator privileges and pipe output to a file, then tail it
        let scriptFile = "/tmp/pm_trace_\(UUID().uuidString.prefix(8)).sh"
        let outFile = "/tmp/pm_trace_\(UUID().uuidString.prefix(8)).out"
        let traceCmd = "/usr/sbin/traceroute -I -m \(maxHops) -q 3 -w 1 \(host) > \(outFile) 2>&1"
        
        let scriptContent = "#!/bin/bash\n\(traceCmd)\n"
        try? scriptContent.write(toFile: scriptFile, atomically: true, encoding: .utf8)
        let chmodProc = Process()
        chmodProc.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProc.arguments = ["+x", scriptFile]
        try? chmodProc.run()
        chmodProc.waitUntilExit()

        // Create empty output file
        FileManager.default.createFile(atPath: outFile, contents: nil)
        
        // Start the privileged traceroute in the background
        let osaProc = Process()
        osaProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osaProc.arguments = ["-e", "do shell script \"\(scriptFile)\" with administrator privileges"]
        
        do {
            try osaProc.run()
            
            // Tail the output file to read results in real-time
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            proc.arguments = ["-f", outFile]
            self.process = proc
        } catch {
            LogManager.shared.error("Failed to start privileged traceroute: \(error)")
            isRunning = false
            progress = "Error: \(error.localizedDescription)"
        }
        
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
                
                // Cleanup
                try? FileManager.default.removeItem(atPath: scriptFile)
                try? FileManager.default.removeItem(atPath: outFile)
            }
        }
    }
    
    // MARK: - MTR Mode (continuous traceroute loop)
    
    private func startMTRTrace(host: String) {
        let proc = Process()
        let pipe = Pipe()
        
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        let scriptFile = "/tmp/pm_mtr_\(UUID().uuidString.prefix(8)).sh"
        let outFile = "/tmp/pm_mtr_\(UUID().uuidString.prefix(8)).out"
        
        // MTR mode: quick probes (-q 1), wait 1s (-w 1), continuous loop in bash
        // To separate rounds in output parsing, we echo a marker line (---MTR-ROUND---)
        let traceCmd = "/usr/sbin/traceroute -I -m \(maxHops) -q 1 -w 1 \(host) >> \(outFile) 2>&1"
        
        let scriptContent = """
        #!/bin/bash
        while true; do
            echo "---MTR-ROUND---" >> \(outFile)
            \(traceCmd)
            sleep 1
        done
        """
        
        try? scriptContent.write(toFile: scriptFile, atomically: true, encoding: .utf8)
        let chmodProc = Process()
        chmodProc.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProc.arguments = ["+x", scriptFile]
        try? chmodProc.run()
        chmodProc.waitUntilExit()

        FileManager.default.createFile(atPath: outFile, contents: nil)
        
        // Start the infinite loop script with privileges
        let osaProc = Process()
        osaProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osaProc.arguments = ["-e", "do shell script \"\(scriptFile)\" with administrator privileges"]
        
        do {
            try osaProc.run()
            
            // Tail the output file
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            proc.arguments = ["-f", outFile]
            self.process = proc
        } catch {
            LogManager.shared.error("Failed to start MTR privileges root process: \(error)")
            isRunning = false
            progress = "Error: \(error.localizedDescription)"
            return
        }
        
        let currentRoundHops = LockedArray<TracerouteHop>()
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                if line.contains("---MTR-ROUND---") {
                    // Flush previous round if we have any hops
                    let collectedHops = currentRoundHops.values
                    if !collectedHops.isEmpty {
                        Task { @MainActor [weak self] in
                            self?.mergeRoundResults(collectedHops)
                        }
                        currentRoundHops.clear()
                    }
                } else if let hop = parseHopLine(line) {
                    currentRoundHops.append(hop)
                }
            }
        }
        
        do {
            try proc.run()
        } catch {
            LogManager.shared.error("Failed to start MTR tail process: \(error)")
            isRunning = false
            progress = "Error: \(error.localizedDescription)"
            return
        }
        
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRunning = false
                
                // Merge any remaining hops
                let collectedHops = currentRoundHops.values
                if !collectedHops.isEmpty {
                    self.mergeRoundResults(collectedHops)
                }
                
                if !self.hops.isEmpty {
                    self.progress = String(format: LanguageManager.shared.t("traceroute.complete"), self.hops.count)
                }
                LogManager.shared.info("MTR trace completed")
                
                // Cleanup
                // Clean up the running script loop using pkill
                let killProc = Process()
                killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                killProc.arguments = ["-9", "-f", scriptFile]
                try? killProc.run()
                
                try? FileManager.default.removeItem(atPath: scriptFile)
                try? FileManager.default.removeItem(atPath: outFile)
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
        
        fetchGeoLocation(for: hop.hopNumber, ip: hop.ip)
    }
    
    private func fetchOriginLocation() {
        Task {
            if let loc = await GeoIPCache.shared.fetchLocalLocation() {
                await MainActor.run {
                    // Check if we already have Hop 0 (edge case where it fetches very fast)
                    if !self.hops.contains(where: { $0.hopNumber == 0 }) {
                        let origin = TracerouteHop(
                            hopNumber: 0,
                            hostName: LanguageManager.shared.t("traceroute.your_location"),
                            ip: "",
                            latencies: [],
                            avgLatency: nil,
                            packetLoss: 0,
                            isTimeout: false,
                            geoLocation: loc
                        )
                        self.hops.insert(origin, at: 0)
                    }
                }
            }
        }
    }
    
    private func fetchGeoLocation(for hopNumber: Int, ip: String) {
        // Only fetch if valid IP
        guard !ip.isEmpty, ip != "*" else { return }
        
        Task {
            if let loc = await GeoIPCache.shared.fetch(ip: ip) {
                await MainActor.run {
                    if let idx = self.hops.firstIndex(where: { $0.hopNumber == hopNumber }) {
                        self.hops[idx].geoLocation = loc
                    }
                }
            }
        }
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
                
                if existing.geoLocation == nil, existing.ip != "*" {
                    fetchGeoLocation(for: existing.hopNumber, ip: existing.ip)
                }
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
                
                if newHop.ip != "*" {
                    fetchGeoLocation(for: newHop.hopNumber, ip: newHop.ip)
                }
            }
        }
    }
    
    // MARK: - Export
    
    func copyResultsToClipboard() {
        var text = "Traceroute to \(targetHost)\n"
        text += String(repeating: "-", count: 100) + "\n"
        text += "Hop  Host/IP                        Avg Latency  Loss   Location                ISP\n"
        text += String(repeating: "-", count: 100) + "\n"
        
        for hop in hops {
            let hostStr = hop.hostName == hop.ip ? hop.ip : "\(hop.hostName) (\(hop.ip))"
            let hopNum = String(hop.hopNumber).padding(toLength: 4, withPad: " ", startingAt: 0)
            let hostPad = String(hostStr.prefix(30)).padding(toLength: 30, withPad: " ", startingAt: 0)
            let avgPad = hop.formattedAvg.padding(toLength: 12, withPad: " ", startingAt: 0)
            let lossPad = hop.formattedLoss.padding(toLength: 6, withPad: " ", startingAt: 0)
            let locStr = hop.geoLocation?.locationString ?? "-"
            let locPad = String(locStr.prefix(22)).padding(toLength: 22, withPad: " ", startingAt: 0)
            let ispStr = hop.geoLocation?.isp ?? "-"
            
            text += "\(hopNum) \(hostPad) \(avgPad) \(lossPad) \(locPad) \(ispStr)\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
// MARK: - Thread-safe array for collecting hops in background

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
    
    func clear() {
        lock.lock()
        array.removeAll()
        lock.unlock()
    }
}

// MARK: - GeoLocation Service

struct GeoLocation: Codable, Equatable, Sendable {
    let status: String
    let country: String?
    let city: String?
    let lat: Double?
    let lon: Double?
    let isp: String?
    let `as`: String? // AS number
    
    var locationString: String? {
        var components: [String] = []
        if let city = city, !city.isEmpty { components.append(city) }
        if let country = country, !country.isEmpty { components.append(country) }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}

actor GeoIPCache: Sendable {
    static let shared = GeoIPCache()
    private var cache: [String: GeoLocation] = [:]
    private var inFlight: [String: Task<GeoLocation?, Never>] = [:]
    
    func getIfCached(_ ip: String) -> GeoLocation? {
        return cache[ip]
    }
    
    func fetch(ip: String) async -> GeoLocation? {
        if let cached = cache[ip] { return cached }
        
        if let task = inFlight[ip] {
            return await task.value
        }
        
        let task = Task<GeoLocation?, Never> {
            let result = await performFetch(ip: ip)
            if let res = result {
                self.cache[ip] = res
            }
            self.inFlight[ip] = nil
            return result
        }
        
        inFlight[ip] = task
        return await task.value
    }
    
    func fetchLocalLocation() async -> GeoLocation? {
        let key = "local"
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }
        
        let task = Task<GeoLocation?, Never> {
            guard let url = URL(string: "http://ip-api.com/json/?fields=status,country,city,lat,lon,isp,as") else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let location = try JSONDecoder().decode(GeoLocation.self, from: data)
                if location.status == "success" {
                    self.cache[key] = location
                    return location
                }
            } catch {}
            self.inFlight[key] = nil
            return nil
        }
        inFlight[key] = task
        return await task.value
    }
    
    private func performFetch(ip: String) async -> GeoLocation? {
        // Skip local, multicast, broadcast, and invalid IPs
        guard !isPrivateOrInvalidIP(ip) else { return nil }
        
        guard let url = URL(string: "http://ip-api.com/json/\(ip)?fields=status,country,city,lat,lon,isp,as") else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let location = try decoder.decode(GeoLocation.self, from: data)
            if location.status == "success" {
                return location
            }
            return nil
        } catch {
            await LogManager.shared.error("GeoIP fetch failed for \(ip): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func isPrivateOrInvalidIP(_ ip: String) -> Bool {
        if ip == "127.0.0.1" || ip == "*" || ip.isEmpty { return true }
        // Simple prefix checks for private IPv4
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("172.") {
            // Check 172.16.x.x - 172.31.x.x
            let parts = ip.split(separator: ".")
            if parts.count == 4, let second = Int(parts[1]), second >= 16 && second <= 31 {
                return true
            }
        }
        return false
    }
}
