import Darwin
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
    var isTailscaleHop: Bool = false
    
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

struct TraceRouteContext: Sendable {
    let targetHost: String
    let resolvedAddress: String?
    let interfaceName: String?
    let sourceAddress: String?
    let gateway: String?
    let isTunnelInterface: Bool
}

struct NSLookupRecord: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: String
}

struct NSLookupResult: Sendable {
    let query: String
    let server: String?
    let records: [NSLookupRecord]
    let rawOutput: String
    let createdAt: Date
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
        isTailscaleHop: ip.starts(with: "100."),
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
    @Published var routeContext: TraceRouteContext?
    @Published var nsLookupResult: NSLookupResult?
    @Published var isNSLookupRunning = false
    @Published var nsLookupError: String?
    
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
        routeContext = resolveRouteContext(for: trimmedHost)
        
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
        routeContext = nil
        nsLookupResult = nil
        nsLookupError = nil
    }
    
    // MARK: - Single Traceroute
    
    private func startSingleTrace(host: String) {
        let traceProcess = Process()
        let pipe = Pipe()
        
        traceProcess.standardOutput = pipe
        traceProcess.standardError = pipe
        traceProcess.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        traceProcess.arguments = ["-q", "/dev/null"] + tracerouteArguments(for: host, queryCount: 3)
        self.process = traceProcess
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                let sanitizedLine = Self.sanitizeOutputLine(line)
                guard !sanitizedLine.isEmpty else { return }
                if let hop = parseHopLine(sanitizedLine) {
                    Task { @MainActor [weak self] in
                        self?.addOrUpdateHop(hop)
                    }
                } else if let errorLine = Self.parseTracerouteError(sanitizedLine) {
                    Task { @MainActor [weak self] in
                        self?.progress = errorLine
                    }
                }
            }
        }
        
        do {
            try traceProcess.run()
        } catch {
            LogManager.shared.error("Failed to start traceroute: \(error)")
            isRunning = false
            progress = "Error: \(error.localizedDescription)"
        }
        
        traceProcess.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRunning = false
                if !self.hops.isEmpty {
                    self.progress = String(format: LanguageManager.shared.t("traceroute.complete"), self.hops.count)
                }
                LogManager.shared.info("Traceroute completed with \(self.hops.count) hops")
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }
    }
    
    // MARK: - MTR Mode (continuous traceroute loop)
    
    private func startMTRTrace(host: String) {
        let traceProcess = Process()
        let pipe = Pipe()
        
        traceProcess.standardOutput = pipe
        traceProcess.standardError = pipe
        let mtrLoop = """
        while true; do
            echo "---MTR-ROUND---"
            \(tracerouteCommand(for: host, queryCount: 1))
            sleep 1
        done
        """
        traceProcess.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        traceProcess.arguments = ["-q", "/dev/null", "/bin/bash", "-lc", mtrLoop]
        self.process = traceProcess
        
        let currentRoundHops = LockedArray<TracerouteHop>()
        
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            output.enumerateLines { line, _ in
                let sanitizedLine = Self.sanitizeOutputLine(line)
                guard !sanitizedLine.isEmpty else { return }
                if sanitizedLine.contains("---MTR-ROUND---") {
                    // Flush previous round if we have any hops
                    let collectedHops = currentRoundHops.values
                    if !collectedHops.isEmpty {
                        Task { @MainActor [weak self] in
                            self?.mergeRoundResults(collectedHops)
                        }
                        currentRoundHops.clear()
                    }
                } else if let hop = parseHopLine(sanitizedLine) {
                    currentRoundHops.append(hop)
                } else if let errorLine = Self.parseTracerouteError(sanitizedLine) {
                    Task { @MainActor [weak self] in
                        self?.progress = errorLine
                    }
                }
            }
        }
        
        do {
            try traceProcess.run()
        } catch {
            LogManager.shared.error("Failed to start MTR process: \(error)")
            isRunning = false
            progress = "Error: \(error.localizedDescription)"
            return
        }
        
        traceProcess.terminationHandler = { [weak self] _ in
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
                pipe.fileHandleForReading.readabilityHandler = nil
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
    
    private func tracerouteCommand(for host: String, queryCount: Int) -> String {
        tracerouteArguments(for: host, queryCount: queryCount).map(shellEscape).joined(separator: " ")
    }

    private func tracerouteArguments(for host: String, queryCount: Int) -> [String] {
        var args = [
            "/usr/sbin/traceroute",
            "-n",
            "-I",
            "-m", "\(maxHops)",
            "-q", "\(queryCount)",
            "-w", "1"
        ]

        if let routeContext, let interfaceName = routeContext.interfaceName, !interfaceName.isEmpty {
            args.append(contentsOf: ["-i", interfaceName])
        }
        if let routeContext, let sourceAddress = routeContext.sourceAddress, !sourceAddress.isEmpty {
            args.append(contentsOf: ["-s", sourceAddress])
        }

        args.append(host)
        return args
    }

    nonisolated private static func parseTracerouteError(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        if lowered.hasPrefix("traceroute to ") {
            return nil
        }
        if lowered.contains("cannot assign requested address") ||
            lowered.contains("network is unreachable") ||
            lowered.contains("no route to host") ||
            lowered.contains("unknown host") ||
            lowered.contains("can't resolve") {
            return trimmed
        }
        return nil
    }

    nonisolated private static func sanitizeOutputLine(_ line: String) -> String {
        let filteredScalars = line.unicodeScalars.filter { scalar in
            if scalar == "\t" || scalar == "\n" || scalar == "\r" {
                return true
            }
            return scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            } else if ip.starts(with: "100.") || ip.starts(with: "fd7a:115c:a1e0:") {
                // Tailscale IP lookup
                await MainActor.run {
                    if let idx = self.hops.firstIndex(where: { $0.hopNumber == hopNumber }) {
                        let nodes = TailscaleManager.shared.nodes
                        if let node = nodes.first(where: { $0.tailscaleIP == ip }) {
                            self.hops[idx].isTailscaleHop = true
                            self.hops[idx].hostName = node.hostname
                            if let relay = node.currentNode {
                                self.hops[idx].geoLocation = GeoLocation(
                                    status: "success",
                                    country: "Relay: \(relay)",
                                    city: node.os,
                                    lat: nil,
                                    lon: nil,
                                    isp: "Tailscale (\(node.connectionType.rawValue))",
                                    as: nil
                                )
                            } else {
                                self.hops[idx].geoLocation = GeoLocation(
                                    status: "success",
                                    country: "Tailscale Node",
                                    city: node.os,
                                    lat: nil,
                                    lon: nil,
                                    isp: "Tailscale",
                                    as: nil
                                )
                            }
                        }
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

    func runNSLookup(host: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }

        isNSLookupRunning = true
        nsLookupError = nil

        Task.detached { [trimmedHost] in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/nslookup")
            process.arguments = [trimmedHost]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let mergedOutput = [stdout, stderr]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")

                await MainActor.run {
                    self.isNSLookupRunning = false
                    if process.terminationStatus == 0 {
                        self.nsLookupResult = Self.parseNSLookupOutput(mergedOutput, query: trimmedHost)
                    } else {
                        self.nsLookupResult = nil
                        self.nsLookupError = mergedOutput.isEmpty ? LanguageManager.shared.t("traceroute.lookup_failed") : mergedOutput
                    }
                }
            } catch {
                await MainActor.run {
                    self.isNSLookupRunning = false
                    self.nsLookupResult = nil
                    self.nsLookupError = error.localizedDescription
                }
            }
        }
    }

    private func resolveRouteContext(for host: String) -> TraceRouteContext {
        let interfaceAddresses = Self.collectInterfaceAddresses()
        let defaultLANContext = Self.resolveDefaultLANContext(from: interfaceAddresses)
        var interfaceName: String?
        var sourceAddress: String?
        var gateway: String?
        var resolvedAddress: String?

        if let output = Self.runCommand("/sbin/route", arguments: ["-n", "get", host]), !output.isEmpty {
            let fields = Self.parseColonSeparatedOutput(output)
            interfaceName = fields["interface"]
            gateway = fields["gateway"]
            resolvedAddress = fields["destination"] ?? fields["route to"]
            sourceAddress = fields["if address"] ?? fields["source"] ?? fields["source address"] ?? fields["local addr"] ?? fields["local address"]
        }

        if sourceAddress == nil, let interfaceName {
            sourceAddress = Self.addressForInterface(named: interfaceName, preferIPv4: true, from: interfaceAddresses)
                ?? Self.addressForInterface(named: interfaceName, preferIPv4: false, from: interfaceAddresses)
        }

        if interfaceName == nil || sourceAddress == nil {
            let fallback = Self.bestFallbackInterface(for: host, from: interfaceAddresses, defaultLANContext: defaultLANContext)
            interfaceName = interfaceName ?? fallback?.interfaceName
            sourceAddress = sourceAddress ?? fallback?.address
        }

        if Self.shouldPreferPhysicalInterface(for: host, resolvedAddress: resolvedAddress, interfaceName: interfaceName),
           let defaultLANContext {
            interfaceName = defaultLANContext.interfaceName
            sourceAddress = defaultLANContext.sourceAddress
            gateway = defaultLANContext.gateway
        }

        return TraceRouteContext(
            targetHost: host,
            resolvedAddress: resolvedAddress,
            interfaceName: interfaceName,
            sourceAddress: sourceAddress,
            gateway: gateway,
            isTunnelInterface: Self.isTunnelInterface(interfaceName)
        )
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runCommand(_ launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let merged = [stdout, stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return merged.isEmpty ? nil : merged
    }

    private static func parseColonSeparatedOutput(_ output: String) -> [String: String] {
        var fields: [String: String] = [:]

        output.enumerateLines { line, _ in
            guard let separatorIndex = line.firstIndex(of: ":") else { return }
            let key = line[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                fields[key] = value
            }
        }

        return fields
    }

    private static func parseNSLookupOutput(_ output: String, query: String) -> NSLookupResult {
        let lines = output.components(separatedBy: .newlines)
        var server: String?
        var records: [NSLookupRecord] = []
        var sawAnswerSection = false
        var currentName: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("Server:") {
                server = line.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.lowercased().contains("non-authoritative answer") || line.lowercased().contains("authoritative answers") {
                sawAnswerSection = true
                continue
            }

            if line.hasPrefix("Name:") {
                currentName = line.replacingOccurrences(of: "Name:", with: "").trimmingCharacters(in: .whitespaces)
                sawAnswerSection = true
                continue
            }

            if line.contains("canonical name =") {
                let value = line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? line
                records.append(NSLookupRecord(label: "CNAME", value: value))
                sawAnswerSection = true
                continue
            }

            if line.hasPrefix("Address:") || line.hasPrefix("Addresses:") {
                let value = line
                    .replacingOccurrences(of: "Addresses:", with: "")
                    .replacingOccurrences(of: "Address:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if sawAnswerSection || currentName != nil {
                    let label = currentName?.isEmpty == false ? currentName! : "Address"
                    records.append(NSLookupRecord(label: label, value: value))
                }
            }
        }

        return NSLookupResult(
            query: query,
            server: server,
            records: records,
            rawOutput: output,
            createdAt: Date()
        )
    }

    private static func resolveDefaultLANContext(from addresses: [InterfaceAddress]) -> TraceRouteContext? {
        guard let output = runCommand("/sbin/route", arguments: ["-n", "get", "0.0.0.0"]), !output.isEmpty else {
            return nil
        }

        let fields = parseColonSeparatedOutput(output)
        guard let interfaceName = fields["interface"], !interfaceName.isEmpty else {
            return nil
        }

        let gateway = fields["gateway"]
        let sourceAddress = runCommand("/usr/sbin/ipconfig", arguments: ["getifaddr", interfaceName])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? addressForInterface(named: interfaceName, preferIPv4: true, from: addresses)
            ?? addressForInterface(named: interfaceName, preferIPv4: false, from: addresses)

        return TraceRouteContext(
            targetHost: "0.0.0.0",
            resolvedAddress: "0.0.0.0",
            interfaceName: interfaceName,
            sourceAddress: sourceAddress,
            gateway: gateway,
            isTunnelInterface: isTunnelInterface(interfaceName)
        )
    }

    private static func collectInterfaceAddresses() -> [InterfaceAddress] {
        var results: [InterfaceAddress] = []
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacePointer) == 0, let first = interfacePointer else {
            return results
        }
        defer { freeifaddrs(interfacePointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)

            if let addressPointer = interface.ifa_addr {
                let family = Int32(addressPointer.pointee.sa_family)
                if family == AF_INET || family == AF_INET6 {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        addressPointer,
                        socklen_t(addressPointer.pointee.sa_len),
                        &hostBuffer,
                        socklen_t(hostBuffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let address = String(decoding: hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        results.append(
                            InterfaceAddress(
                                interfaceName: String(cString: interface.ifa_name),
                                address: address,
                                family: family,
                                flags: flags
                            )
                        )
                    }
                }
            }

            pointer = interface.ifa_next
        }

        return results
    }

    private static func addressForInterface(named interfaceName: String, preferIPv4: Bool, from addresses: [InterfaceAddress]) -> String? {
        let preferredFamily = preferIPv4 ? AF_INET : AF_INET6
        if let exact = addresses.first(where: { $0.interfaceName == interfaceName && $0.family == preferredFamily && $0.isUsable }) {
            return exact.address
        }
        return addresses.first(where: { $0.interfaceName == interfaceName && $0.isUsable })?.address
    }

    private static func bestFallbackInterface(for host: String, from addresses: [InterfaceAddress], defaultLANContext: TraceRouteContext?) -> InterfaceAddress? {
        let preferTunnel = host.hasPrefix("100.") || host.lowercased().hasPrefix("fd7a:115c:a1e0:")

        if !preferTunnel,
           let defaultLANContext,
           let interfaceName = defaultLANContext.interfaceName,
           let sourceAddress = defaultLANContext.sourceAddress {
            return InterfaceAddress(interfaceName: interfaceName, address: sourceAddress, family: AF_INET, flags: IFF_UP | IFF_RUNNING)
        }

        let usableAddresses = addresses.filter { $0.isUsable }

        let sorted = usableAddresses.sorted { lhs, rhs in
            let lhsScore = interfacePriority(for: lhs.interfaceName, preferTunnel: preferTunnel)
            let rhsScore = interfacePriority(for: rhs.interfaceName, preferTunnel: preferTunnel)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            if lhs.family != rhs.family {
                return lhs.family == AF_INET
            }
            return lhs.interfaceName < rhs.interfaceName
        }

        return sorted.first
    }

    private static func interfacePriority(for name: String, preferTunnel: Bool) -> Int {
        if preferTunnel {
            if isTunnelInterface(name) { return 0 }
            if name.hasPrefix("en") { return 1 }
            if name.hasPrefix("bridge") { return 2 }
            return 3
        }

        if name.hasPrefix("en") { return 0 }
        if name.hasPrefix("bridge") { return 1 }
        if isTunnelInterface(name) { return 2 }
        return 3
    }

    private static func shouldPreferPhysicalInterface(for host: String, resolvedAddress: String?, interfaceName: String?) -> Bool {
        guard isTunnelInterface(interfaceName) else { return false }
        let target = ((resolvedAddress?.isEmpty == false ? resolvedAddress : nil) ?? host).lowercased()
        return !isInternalTarget(target)
    }

    private static func isInternalTarget(_ target: String) -> Bool {
        if target.hasPrefix("10.") ||
            target.hasPrefix("192.168.") ||
            target.hasPrefix("127.") ||
            target.hasPrefix("169.254.") ||
            target.hasPrefix("100.") ||
            target.hasPrefix("fd7a:115c:a1e0:") ||
            target.hasPrefix("fc") ||
            target.hasPrefix("fd") {
            return true
        }

        if target.hasPrefix("172.") {
            let parts = target.split(separator: ".")
            if parts.count == 4, let secondOctet = Int(parts[1]), secondOctet >= 16 && secondOctet <= 31 {
                return true
            }
        }

        return false
    }

    private static func isTunnelInterface(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.hasPrefix("utun") ||
            name.hasPrefix("tun") ||
            name.hasPrefix("tap") ||
            name.hasPrefix("ppp") ||
            name.hasPrefix("ipsec") ||
            name.hasPrefix("wg")
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

private struct InterfaceAddress: Sendable {
    let interfaceName: String
    let address: String
    let family: Int32
    let flags: Int32

    var isUsable: Bool {
        let isUp = (flags & IFF_UP) != 0
        let isRunning = (flags & IFF_RUNNING) != 0
        let isLoopback = (flags & IFF_LOOPBACK) != 0

        if !isUp || !isRunning || isLoopback {
            return false
        }
        if family == AF_INET6 && address.hasPrefix("fe80:") {
            return false
        }
        return true
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

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
        // ALLOW 100.x.y.z for Tailscale processing
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
