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
}
