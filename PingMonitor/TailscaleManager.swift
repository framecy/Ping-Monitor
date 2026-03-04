import Foundation
import Combine

// MARK: - Tailscale Node Model

struct TailscaleNode: Identifiable, Codable {
    var id: String { tailscaleIP }
    let hostname: String
    let tailscaleIP: String
    let os: String
    let online: Bool
    let isSelf: Bool
    let exitNode: Bool
    let exitNodeOption: Bool
    
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

// MARK: - Tailscale Status Response

private struct TailscaleStatus: Codable {
    let `Self`: TailscalePeer?
    let Peer: [String: TailscalePeer]?
    let MagicDNSSuffix: String?
    
    enum CodingKeys: String, CodingKey {
        case `Self` = "Self"
        case Peer = "Peer"
        case MagicDNSSuffix = "MagicDNSSuffix"
    }
}

private struct TailscalePeer: Codable {
    let HostName: String?
    let DNSName: String?
    let TailscaleIPs: [String]?
    let OS: String?
    let Online: Bool?
    let ExitNode: Bool?
    let ExitNodeOption: Bool?
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
    
    private var cliPath: String?
    
    private init() {
        detectCLI()
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
        guard let cli = cliPath else {
            lastError = "Tailscale CLI not found"
            return
        }
        
        isLoading = true
        lastError = nil
        
        Task.detached { [cli] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["status", "--json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                guard process.terminationStatus == 0 else {
                    await MainActor.run {
                        self.isLoading = false
                        self.isConnected = false
                        self.lastError = "Tailscale not running (exit code \(process.terminationStatus))"
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
                    parsedNodes.append(TailscaleNode(
                        hostname: selfPeer.HostName ?? "Unknown",
                        tailscaleIP: selfIP,
                        os: selfPeer.OS ?? "unknown",
                        online: true,
                        isSelf: true,
                        exitNode: selfPeer.ExitNode ?? false,
                        exitNodeOption: selfPeer.ExitNodeOption ?? false
                    ))
                }
                
                // Peer nodes
                if let peers = status.Peer {
                    for (_, peer) in peers {
                        let ip = peer.TailscaleIPs?.first ?? ""
                        parsedNodes.append(TailscaleNode(
                            hostname: peer.HostName ?? "Unknown",
                            tailscaleIP: ip,
                            os: peer.OS ?? "unknown",
                            online: peer.Online ?? false,
                            isSelf: false,
                            exitNode: peer.ExitNode ?? false,
                            exitNodeOption: peer.ExitNodeOption ?? false
                        ))
                    }
                }
                
                // Sort: self first, then online, then offline
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
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.lastError = "Failed to parse: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Import Nodes
    
    func importNode(_ node: TailscaleNode, into viewModel: PingMonitorViewModel) {
        // Check if already exists
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
        LogManager.shared.info("Imported Tailscale node: \(node.hostname) (\(node.tailscaleIP))")
        
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
        guard let cli = cliPath else { return }
        
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
                    await MainActor.run {
                        self.netcheckLoading = false
                    }
                    return
                }
                
                let decoder = JSONDecoder()
                let result = try decoder.decode(NetcheckResponse.self, from: data)
                
                // Determine NAT type
                let natType: String
                if result.MappingVariesByDestIP == true {
                    natType = "Symmetric NAT"
                } else if result.HairPinning == true {
                    natType = "Full Cone NAT"
                } else if result.UDP == true {
                    natType = "Easy NAT"
                } else {
                    natType = "Hard NAT"
                }
                
                // Parse region latencies (nanoseconds → ms)
                var latencies: [NetcheckRegionLatency] = []
                if let regions = result.RegionLatency {
                    for (regionId, nsLatency) in regions {
                        let msLatency = nsLatency / 1_000_000.0  // ns to ms
                        if msLatency > 0 {
                            let name = derpRegionNames[regionId] ?? "DERP \(regionId)"
                            latencies.append(NetcheckRegionLatency(
                                regionCode: regionId,
                                regionName: name,
                                latency: msLatency
                            ))
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
                }
                
            } catch {
                await MainActor.run {
                    self.netcheckLoading = false
                }
            }
        }
    }
    func runTailscaleCommand(_ command: String) {
        guard let cli = cliPath else {
            LogManager.shared.error("Tailscale CLI not found")
            return
        }
        
        let args = command.components(separatedBy: " ")
        LogManager.shared.info("Executing: tailscale \(command)")
        
        Task.detached {
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
                    for line in lines.prefix(20) {
                        await LogManager.shared.info("[Tailscale] \(line)")
                    }
                    if lines.count > 20 {
                        await LogManager.shared.info("[Tailscale] ... (truncated)")
                    }
                }
                
                if process.terminationStatus == 0 {
                    await LogManager.shared.info("Command executed successfully")
                    if command.contains("status") || command.contains("netcheck") {
                        await MainActor.run {
                            self.fetchStatus()
                            self.fetchNetcheck()
                        }
                    }
                } else {
                    await LogManager.shared.error("Command failed with exit code \(process.terminationStatus)")
                }
            } catch {
                await LogManager.shared.error("Failed to run command: \(error.localizedDescription)")
            }
        }
    }
}
