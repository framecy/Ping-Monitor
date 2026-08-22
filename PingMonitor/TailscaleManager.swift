import Foundation
import Combine

// MARK: - Tailscale Node Model

enum TailscaleConnectionType: String, Codable {
    case p2p = "P2P"       // Direct peer-to-peer
    case relay = "Relay"    // Via DERP relay
    case derp = "DERP"     // Using DERP server
    case unknown = "—"
}

struct TailscaleNode: Identifiable, Codable {
    var id: String { tailscaleIP }
    let hostname: String
    let tailscaleIP: String
    let os: String
    let online: Bool
    let isSelf: Bool
    let exitNode: Bool
    let exitNodeOption: Bool
    
    // Connection info
    var connectionType: TailscaleConnectionType = .unknown
    var currentNode: String? = nil
    var rxBytes: Int64 = 0
    var txBytes: Int64 = 0
    
    // Subnet routes advertised by this peer (e.g. ["10.1.1.0/24"])
    var primaryRoutes: [String] = []

    // Diagnostic info
    var lastPingResult: String? = nil
    var isCheckingPath: Bool = false
    var relayCode: String? = nil
    var directAddr: String? = nil
    
    var osIcon: String {
        switch os.lowercased() {
        case let o where o.contains("macos") || o.contains("darwin"):
            return "laptopcomputer"
        case let o where o.contains("windows"):
            return "desktopcomputer"
        case let o where o.contains("linux"):
            return "server.rack"
        case let o where o.contains("ios"):
            return "iphone"
        case let o where o.contains("android"):
            return "smartphone"
        default:
            return "network"
        }
    }
}

// MARK: - Exit Node Model

struct ExitNode: Identifiable {
    var id: String { node.tailscaleIP }
    let node: TailscaleNode
    var latency: Double?  // average milliseconds, nil = not tested
    var packetLoss: Double?  // percentage, nil = not tested
    var jitter: Double? // stddev, nil = not tested
    var isReachable: Bool = true
    
    var latencyString: String {
        guard let lat = latency else { return "—" }
        return String(format: "%.0fms", lat)
    }
    
    var score: Int {
        guard let lat = latency else { return 0 }
        
        // RTT score (40%)
        let rttScore: Double
        if lat < 30 { rttScore = 100 }
        else if lat < 100 { rttScore = 80 }
        else if lat < 200 { rttScore = 50 }
        else { rttScore = 20 }
        
        // Packet Loss score (30%)
        let loss = packetLoss ?? 0
        let lossScore: Double
        if loss == 0 { lossScore = 100 }
        else if loss < 2 { lossScore = 70 }
        else if loss < 5 { lossScore = 40 }
        else { lossScore = 0 }
        
        // Jitter score (20%)
        let jit = jitter ?? 0
        let jitterScore: Double
        if jit < 5 { jitterScore = 100 }
        else if jit < 15 { jitterScore = 70 }
        else if jit < 30 { jitterScore = 40 }
        else { jitterScore = 10 }
        
        // Network Type score (10%)
        // P2P = 100, Relay = 20
        let typeScore: Double = node.connectionType == .p2p ? 100 : 20
        
        let totalScore = (rttScore * 0.4) + (lossScore * 0.3) + (jitterScore * 0.2) + (typeScore * 0.1)
        return Int(totalScore)
    }
}

// MARK: - Tailscale Status Response

private struct TailscaleStatus: Codable {
    let `Self`: TailscalePeer?
    let Peer: [String: TailscalePeer]?
    let MagicDNSSuffix: String?
    let CurrentTailnet: TailnetInfo?
    
    enum CodingKeys: String, CodingKey {
        case `Self` = "Self"
        case Peer = "Peer"
        case MagicDNSSuffix = "MagicDNSSuffix"
        case CurrentTailnet = "CurrentTailnet"
    }
}

private struct TailnetInfo: Codable {
    let MagicDNSSuffix: String?
    let MagicDNSEnabled: Bool?
    let MagicDNSSuffixOverride: Bool?
}

private struct TailscalePeer: Codable {
    let HostName: String?
    let DNSName: String?
    let TailscaleIPs: [String]?
    let OS: String?
    let Online: Bool?
    let ExitNode: Bool?
    let ExitNodeOption: Bool?
    let Relay: String?  // Current DERP relay node code (e.g., "sfo")
    let PeerRelay: String?  // Peer's relay node
    let CurAddr: String?  // Current direct address
    let Addrs: [String]?  // Available addresses
    let RxBytes: Int64?
    let TxBytes: Int64?
    let LastSeen: String?
    let PrimaryRoutes: [String]?
}

// MARK: - Netcheck Result Model

struct NetcheckRegionLatency: Identifiable {
    var id: String { regionName }
    let regionCode: String
    let regionName: String
    let latency: Double  // milliseconds
}

private struct NetcheckResponse: Codable {
    let UDP: Bool?
    let IPv6: Bool?
    let IPv4: Bool?
    let MappingVariesByDestIP: Bool?  // Symmetric NAT indicator
    let HairPinning: Bool?
    let PreferredDERP: Int?
    let RegionLatency: [String: Double]?  // regionID -> latency in nanoseconds
    let RegionV4Latency: [String: Double]?
    let UPnP: Bool?
    let PMP: Bool?
    let PCP: Bool?
    let GlobalV4: String?
    let GlobalV6: String?
    let CaptivePortal: Bool?
}

// MARK: - Tailscale Ping JSON Result

struct TailscalePingResponse: Codable {
    let IP: String?
    let NodeKey: String?
    let NodeName: String?
    let Err: String?
    let LatencySeconds: Double?
    let Endpoint: String?
    let DERPRegionID: Int?
    let DERPRegionCode: String?
    let IsP2P: Bool?
    
    enum CodingKeys: String, CodingKey {
        case IP, NodeKey, NodeName, Err, LatencySeconds, Endpoint, DERPRegionID, DERPRegionCode, IsP2P
    }
}

// MARK: - Tailscale Manager

@MainActor
class TailscaleManager: ObservableObject {
    static let shared = TailscaleManager()
    
    @Published var isAvailable = false
    @Published var isConnected = false
    @Published var selfIP: String = ""
    @Published var selfHostname: String = ""
    @Published var magicDNSSuffix: String = ""
    @Published var nodes: [TailscaleNode] = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    // Exit Node properties
    @Published var currentExitNode: TailscaleNode? = nil
    @Published var availableExitNodes: [ExitNode] = []
    @Published var isTestingExitNodes = false
    
    // Netcheck properties
    @Published var netcheckLoading = false
    @Published var natType: String = "—"
    @Published var udpEnabled: Bool = false
    @Published var ipv4Enabled: Bool = false
    @Published var ipv6Enabled: Bool = false
    @Published var hairPinning: Bool? = nil
    @Published var upnp: Bool? = nil
    @Published var preferredDERP: String = "—"
    @Published var globalIPv4: String = "—"
    @Published var globalIPv6: String = "—"
    @Published var regionLatencies: [NetcheckRegionLatency] = []
    @Published var captivePortal: Bool = false
    
    // Health Advice
    @Published var healthAdvice: [String] = []
    
    public var cliPath: String?
    
    // Integration master switch. Persisted and OFF by default, so machines
    // without Tailscale never spawn any CLI process.
    @Published private(set) var isEnabled: Bool
    
    static let enabledDefaultsKey = "tailscaleIntegrationEnabled"
    
    var isFunctional: Bool { isEnabled && isAvailable }
    
    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: TailscaleManager.enabledDefaultsKey)
        if isEnabled {
            detectCLI()
        }
    }
    
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: TailscaleManager.enabledDefaultsKey)
        LogManager.shared.info("Tailscale integration \(on ? "enabled" : "disabled")")
        if on {
            detectCLI()
            if isAvailable { fetchStatus() }
        } else {
            resetState()
        }
    }
    
    private func resetState() {
        isConnected = false
        isLoading = false
        lastError = nil
        selfIP = ""
        selfHostname = ""
        magicDNSSuffix = ""
        nodes = []
        currentExitNode = nil
        availableExitNodes = []
        isTestingExitNodes = false
        netcheckLoading = false
        natType = "—"
        udpEnabled = false
        ipv4Enabled = false
        ipv6Enabled = false
        hairPinning = nil
        upnp = nil
        preferredDERP = "—"
        globalIPv4 = "—"
        globalIPv6 = "—"
        regionLatencies = []
        captivePortal = false
        healthAdvice = []
    }
    
    // MARK: - CLI Detection
    
    func detectCLI() {
        let possiblePaths = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                cliPath = path
                isAvailable = true
                return
            }
        }
        
        // Try `which tailscale`
        let whichProcess = Process()
        let pipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["tailscale"]
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                cliPath = path
                isAvailable = true
                return
            }
        } catch {}
        
        isAvailable = false
    }
    
    // MARK: - Fetch Status
    
    func fetchStatus() {
        guard isEnabled else { return }
        guard let cli = cliPath else {
            lastError = "Tailscale CLI not found"
            return
        }
        
        isLoading = true
        lastError = nil
        
        Task.detached { [cli] in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["status", "--json"]
            process.standardOutput = pipe
            process.standardError = errPipe
            
            var dataSize = 0
            var stderrOutput = ""
            var dataForDebug = Data()
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                dataSize = data.count
                dataForDebug = data
                
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                stderrOutput = String(data: errData, encoding: .utf8) ?? ""
                
                guard process.terminationStatus == 0 else {
                    await MainActor.run {
                        self.isLoading = false
                        self.isConnected = false
                        self.lastError = "Tailscale not running (exit code \(process.terminationStatus))"
                    }
                    return
                }
                
                // Validate data before parsing
                guard dataSize > 0 else {
                    await MainActor.run {
                        self.isLoading = false
                        self.lastError = "No data received from tailscale"
                    }
                    return
                }
                
                let decoder = JSONDecoder()
                let status = try decoder.decode(TailscaleStatus.self, from: data)
                
                var parsedNodes: [TailscaleNode] = []
                
                // Self node
                var selfIP = ""
                var selfHostname = ""
                if let selfPeer = status.Self {
                    selfIP = selfPeer.TailscaleIPs?.first ?? ""
                    selfHostname = selfPeer.HostName ?? ""
                    
                    var connType: TailscaleConnectionType = .unknown
                    if let relay = selfPeer.Relay, !relay.isEmpty {
                        connType = .derp
                    } else if let curAddr = selfPeer.CurAddr, !curAddr.isEmpty {
                        connType = .p2p
                    }
                    
                    parsedNodes.append(TailscaleNode(
                        hostname: selfPeer.HostName ?? "Unknown",
                        tailscaleIP: selfIP,
                        os: selfPeer.OS ?? "unknown",
                        online: true,
                        isSelf: true,
                        exitNode: selfPeer.ExitNode ?? false,
                        exitNodeOption: selfPeer.ExitNodeOption ?? false,
                        connectionType: connType,
                        currentNode: selfPeer.Relay ?? selfPeer.CurAddr,
                        rxBytes: selfPeer.RxBytes ?? 0,
                        txBytes: selfPeer.TxBytes ?? 0
                    ))
                }
                
                // Peer nodes
                if let peers = status.Peer {
                    for (_, peer) in peers {
                        let ip = peer.TailscaleIPs?.first ?? ""
                        var connType: TailscaleConnectionType = .unknown
                        if let relay = peer.Relay, !relay.isEmpty {
                            connType = .derp
                        } else if let curAddr = peer.CurAddr, !curAddr.isEmpty {
                            connType = .p2p
                        }
                        
                        parsedNodes.append(TailscaleNode(
                            hostname: peer.HostName ?? "Unknown",
                            tailscaleIP: ip,
                            os: peer.OS ?? "unknown",
                            online: peer.Online ?? false,
                            isSelf: false,
                            exitNode: peer.ExitNode ?? false,
                            exitNodeOption: peer.ExitNodeOption ?? false,
                            connectionType: connType,
                            currentNode: peer.Relay ?? peer.CurAddr,
                            rxBytes: peer.RxBytes ?? 0,
                            txBytes: peer.TxBytes ?? 0,
                            primaryRoutes: peer.PrimaryRoutes ?? [],
                            relayCode: peer.Relay,
                            directAddr: peer.CurAddr
                        ))
                    }
                }
                
                parsedNodes.sort { a, b in
                    if a.isSelf != b.isSelf { return a.isSelf }
                    if a.online != b.online { return a.online }
                    return a.hostname < b.hostname
                }
                
                await MainActor.run {
                    self.isLoading = false
                    self.isConnected = true
                    self.selfIP = selfIP
                    self.selfHostname = selfHostname
                    self.magicDNSSuffix = status.MagicDNSSuffix ?? ""
                    self.nodes = parsedNodes
                    self.updateExitNodeInfo()
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.lastError = "Failed to parse Tailscale status: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Import Nodes
    
    func importNode(_ node: TailscaleNode, into viewModel: PingMonitorViewModel) {
        if viewModel.hosts.contains(where: { $0.address == node.tailscaleIP }) {
            return
        }
        
        var newHost = HostConfig(name: node.hostname, address: node.tailscaleIP)
        newHost.isTailscaleNode = true
        newHost.tailscaleHostname = node.hostname
        newHost.displayRules = []
        
        viewModel.hosts.append(newHost)
        viewModel.hostStats[newHost.id] = HostStats(hostId: newHost.id)
        viewModel.saveSettings()
        
        if viewModel.isRunning {
            if let index = viewModel.hosts.firstIndex(where: { $0.id == newHost.id }) {
                viewModel.startPingProcess(for: viewModel.hosts[index], at: index)
            }
        }
    }
    
    func importAllOnlineNodes(into viewModel: PingMonitorViewModel) {
        let onlineNodes = nodes.filter { $0.online && !$0.isSelf }
        for node in onlineNodes {
            importNode(node, into: viewModel)
        }
    }
    
    // MARK: - Exit Node Management
    
    private func updateExitNodeInfo() {
        currentExitNode = nodes.first { $0.exitNode }
        let optionNodes = nodes.filter { $0.exitNodeOption && $0.online && !$0.isSelf }
        var updatedNodes: [ExitNode] = []
        for node in optionNodes {
            if let existing = availableExitNodes.first(where: { $0.node.tailscaleIP == node.tailscaleIP }) {
                updatedNodes.append(ExitNode(
                    node: node,
                    latency: existing.latency,
                    packetLoss: existing.packetLoss,
                    isReachable: existing.isReachable
                ))
            } else {
                updatedNodes.append(ExitNode(node: node, latency: nil, packetLoss: nil))
            }
        }
        availableExitNodes = updatedNodes.sorted { a, b in
            if a.latency != nil && b.latency != nil {
                return a.latency! < b.latency!
            }
            if a.latency != nil { return true }
            if b.latency != nil { return false }
            return a.node.hostname < b.node.hostname
        }
    }
    
    nonisolated func testAllExitNodesLatency() {
        Task { @MainActor in
            guard isEnabled, !availableExitNodes.isEmpty else { return }
            isTestingExitNodes = true
            let nodesToTest = availableExitNodes
            let results = await withTaskGroup(of: ExitNode.self) { group in
                for exitNode in nodesToTest {
                    group.addTask {
                        let metrics = await self.pingNodeMetrics(exitNode.node.tailscaleIP, count: 5)
                        return ExitNode(
                            node: exitNode.node,
                            latency: metrics.avg,
                            packetLoss: metrics.loss,
                            jitter: metrics.stddev,
                            isReachable: metrics.avg != nil
                        )
                    }
                }
                var results: [ExitNode] = []
                for await result in group { results.append(result) }
                return results
            }
            availableExitNodes = results.sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if let al = a.latency, let bl = b.latency { return al < bl }
                return a.node.hostname < b.node.hostname
            }
            isTestingExitNodes = false
        }
    }
    
    private struct PingMetrics {
        var avg: Double?
        var loss: Double?
        var stddev: Double?
    }
    
    private func pingNodeMetrics(_ ip: String, count: Int) async -> PingMetrics {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "\(count)", "-W", "2", ip]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var metrics = PingMetrics()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return metrics }
            let lossPattern = #"([\d.]+)\% packet loss"#
            if let regex = try? NSRegularExpression(pattern: lossPattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) {
                metrics.loss = Double(output[range])
            }
            let rttPattern = #"min/avg/max/stddev = ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)"#
            if let regex = try? NSRegularExpression(pattern: rttPattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                if let avgRange = Range(match.range(at: 2), in: output) { metrics.avg = Double(output[avgRange]) }
                if let stddevRange = Range(match.range(at: 4), in: output) { metrics.stddev = Double(output[stddevRange]) }
            }
            return metrics
        } catch { return metrics }
    }
    
    func switchExitNode(to node: TailscaleNode) {
        guard isEnabled else { return }
        Task {
            await runTailscaleCommand(["set", "--exit-node="], background: true)
            await runTailscaleCommand(["set", "--exit-node=\(node.tailscaleIP)"], background: true)
            fetchStatus()
        }
    }
    
    func disableExitNode() {
        guard isEnabled else { return }
        Task {
            await runTailscaleCommand(["set", "--exit-node="], background: true)
            fetchStatus()
        }
    }
    
    // MARK: - Netcheck
    
    private let derpRegionNames: [String: String] = [
        "1": "New York", "2": "San Francisco", "3": "Singapore",
        "4": "Frankfurt", "5": "Sydney", "6": "Bangalore",
        "7": "Tokyo", "8": "London", "9": "Dallas",
        "10": "Seattle", "11": "São Paulo", "12": "Toronto",
        "13": "Johannesburg", "14": "Nairobi", "15": "Dubai",
        "16": "Chicago", "17": "Hong Kong", "18": "Honolulu",
        "19": "Warsaw", "20": "Paris", "21": "Madrid",
        "22": "Amsterdam", "23": "Mumbai", "24": "Los Angeles",
        "25": "Denver", "26": "Miami"
    ]
    
    func fetchNetcheck() {
        guard isEnabled, let cli = cliPath else { return }
        netcheckLoading = true
        
        Task.detached { [cli, derpRegionNames] in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["netcheck", "--format=json"]
            process.standardOutput = pipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    await MainActor.run { self.netcheckLoading = false }
                    return
                }
                
                let decoder = JSONDecoder()
                let result = try decoder.decode(NetcheckResponse.self, from: data)
                
                let natType: String
                if result.MappingVariesByDestIP == true { natType = "Symmetric NAT" }
                else if result.HairPinning == true { natType = "Full Cone NAT" }
                else if result.UDP == true { natType = "Easy NAT" }
                else { natType = "Hard NAT" }
                
                var latencies: [NetcheckRegionLatency] = []
                if let regions = result.RegionLatency {
                    for (regionId, nsLatency) in regions {
                        let msLatency = nsLatency / 1_000_000.0
                        if msLatency > 0 {
                            let name = derpRegionNames[regionId] ?? "DERP \(regionId)"
                            latencies.append(NetcheckRegionLatency(regionCode: regionId, regionName: name, latency: msLatency))
                        }
                    }
                }
                latencies.sort { $0.latency < $1.latency }
                let preferredDERP = derpRegionNames[String(result.PreferredDERP ?? 0)] ?? "DERP \(result.PreferredDERP ?? 0)"
                
                await MainActor.run {
                    self.netcheckLoading = false
                    self.natType = natType
                    self.udpEnabled = result.UDP ?? false
                    self.ipv4Enabled = result.IPv4 ?? false
                    self.ipv6Enabled = result.IPv6 ?? false
                    self.hairPinning = result.HairPinning
                    self.upnp = result.UPnP
                    self.preferredDERP = preferredDERP
                    self.globalIPv4 = result.GlobalV4 ?? "—"
                    self.globalIPv6 = result.GlobalV6 ?? "—"
                    self.regionLatencies = latencies
                    self.captivePortal = result.CaptivePortal ?? false
                    
                    var advice: [String] = []
                    let lang = LanguageManager.shared
                    if result.UDP == false { advice.append(lang.t("tailscale.advice.udp_blocked")) }
                    else if result.MappingVariesByDestIP == true { advice.append(lang.t("tailscale.advice.symmetric_nat")) }
                    else if result.UDP == true { advice.append(lang.t("tailscale.advice.easy_nat")) }
                    if result.CaptivePortal == true { advice.append(lang.t("tailscale.advice.captive_portal")) }
                    self.healthAdvice = advice
                }
            } catch { await MainActor.run { self.netcheckLoading = false } }
        }
    }
    
    // MARK: - Path Diagnosis
    
    func runPathDiagnosis(for node: TailscaleNode) {
        guard isEnabled, let cli = cliPath else { return }
        
        if let index = nodes.firstIndex(where: { $0.tailscaleIP == node.tailscaleIP }) {
            nodes[index].isCheckingPath = true
            nodes[index].lastPingResult = nil
        }
        
        Task.detached { [cli, ip = node.tailscaleIP] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["ping", "--json", "--c=1", ip]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let decoder = JSONDecoder()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                
                var finalResult = ""
                if let lastLine = lines.last, let lineData = lastLine.data(using: .utf8) {
                    if let pingRes = try? decoder.decode(TailscalePingResponse.self, from: lineData) {
                        if let err = pingRes.Err, !err.isEmpty {
                            finalResult = "Error: \(err)"
                        } else {
                            let type = pingRes.IsP2P == true ? "P2P" : "Relay"
                            let endpoint = pingRes.Endpoint ?? pingRes.DERPRegionCode ?? "unknown"
                            let latency = String(format: "%.1fms", (pingRes.LatencySeconds ?? 0) * 1000)
                            finalResult = "\(type) via \(endpoint) (\(latency))"
                        }
                    } else { finalResult = "Failed to parse result" }
                } else { finalResult = "Check complete" }
                
                await MainActor.run {
                    if let index = self.nodes.firstIndex(where: { $0.tailscaleIP == ip }) {
                        self.nodes[index].isCheckingPath = false
                        self.nodes[index].lastPingResult = finalResult
                        if finalResult.contains("P2P") { self.nodes[index].connectionType = .p2p }
                        else if finalResult.contains("Relay") { self.nodes[index].connectionType = .relay }
                    }
                }
            } catch {
                await MainActor.run {
                    if let index = self.nodes.firstIndex(where: { $0.tailscaleIP == ip }) {
                        self.nodes[index].isCheckingPath = false
                        self.nodes[index].lastPingResult = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func runTailscaleCommand(_ args: [String], background: Bool = false) async {
        guard isEnabled else {
            LogManager.shared.info("Tailscale integration is disabled; command skipped: tailscale \(args.joined(separator: " "))")
            return
        }
        guard let cli = cliPath else {
            LogManager.shared.error("Tailscale CLI not found")
            return
        }
        let commandStr = args.joined(separator: " ")
        LogManager.shared.info("Executing: tailscale \(commandStr)")
        let task = Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines.prefix(20) { await LogManager.shared.info("[Tailscale] \(line)") }
                }
                if process.terminationStatus == 0 { await LogManager.shared.info("Command executed successfully") }
                else { await LogManager.shared.error("Command failed with exit code \(process.terminationStatus)") }
            } catch { await LogManager.shared.error("Failed to run command: \(error.localizedDescription)") }
        }
        if !background { await task.value }
    }
}
