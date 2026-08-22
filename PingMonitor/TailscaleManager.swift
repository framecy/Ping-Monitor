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

    // MARK: 控制面（全局监管）状态
    // 数据来自 Tailscale API，覆盖整个 tailnet；本机 CLI 只提供「本机视角」的路径信息。
    @Published var tailnetDevices: [TailnetDevice] = []
    @Published var inventoryState: InventoryState = .notConfigured
    @Published var isFetchingInventory = false
    @Published var lastInventorySync: Date?
    /// 凭据是否就绪的缓存。视图里直接读钥匙串会造成每帧一次 Keychain 查询。
    @Published private(set) var hasInventoryCredentials = false

    enum InventoryState: Equatable {
        case notConfigured          // 未填 OAuth client
        case ok
        case failed(String)         // 已本地化的错误文案
    }

    public var cliPath: String?

    // 集成总闸（与设置页的 pm.enableTailscale 同键）。关闭时不做 CLI 探测、
    // 不发 API 请求、探测进程一律退回普通 ping —— 而不是仅隐藏界面。
    @Published private(set) var isEnabled: Bool

    static let enableDefaultsKey = "pm.enableTailscale"

    private var inventoryTimer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: TailscaleManager.enableDefaultsKey)
        if isEnabled {
            detectCLI()
        }
        refreshInventoryConfiguration()
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: TailscaleManager.enableDefaultsKey)
        LogManager.shared.info("Tailscale integration \(on ? "enabled" : "disabled")")
        if on {
            detectCLI()
            if isAvailable { fetchStatus() }
        } else {
            resetState()
        }
        refreshInventoryConfiguration()
    }

    private func resetState() {
        isConnected = false
        isLoading = false
        lastError = nil
        selfIP = ""
        selfHostname = ""
        magicDNSSuffix = ""
        nodes = []
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
        pendingActionDeviceID = nil
        lastActionError = nil
        isFetchingInventory = false
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
                    self.mergeLocalNodes(parsedNodes)
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

    // MARK: - Tailnet Inventory (control plane)

    /// 本机 CLI 拉到的节点列表落库；控制面清单独立存在，两者按 IP 关联。
    private func mergeLocalNodes(_ parsed: [TailscaleNode]) {
        nodes = parsed
    }

    /// 本机视角的节点信息（连接方式 / 收发字节），供控制面清单行做增强展示。
    func localNode(forIP ip: String) -> TailscaleNode? {
        nodes.first { $0.tailscaleIP == ip }
    }

    var isInventoryConfigured: Bool {
        KeychainStore.has(.tailscaleOAuthClientID) && KeychainStore.has(.tailscaleOAuthClientSecret)
    }

    struct InventorySummary {
        var total = 0
        var online = 0
        var updateAvailable = 0
        var keyExpiring = 0
        var unauthorized = 0
        var monitored = 0
    }

    func inventorySummary(monitoredAddresses: Set<String>) -> InventorySummary {
        var summary = InventorySummary()
        summary.total = tailnetDevices.count
        for device in tailnetDevices {
            if device.isOnline { summary.online += 1 }
            if device.updateAvailable { summary.updateAvailable += 1 }
            if device.keyExpiringSoon || device.keyExpired { summary.keyExpiring += 1 }
            if !device.authorized { summary.unauthorized += 1 }
            if monitoredAddresses.contains(device.tailscaleIP) { summary.monitored += 1 }
        }
        return summary
    }

    /// 凭据变更 / 开关切换后调用：重置 token 缓存并重建轮询。
    func refreshInventoryConfiguration() {
        guard isEnabled else {
            stopInventoryPolling()
            Task { await TailscaleAPIClient.shared.invalidateToken() }
            hasInventoryCredentials = false
            tailnetDevices = []
            lastInventorySync = nil
            inventoryState = .notConfigured
            return
        }
        Task { await TailscaleAPIClient.shared.invalidateToken() }
        hasInventoryCredentials = isInventoryConfigured

        guard hasInventoryCredentials else {
            stopInventoryPolling()
            tailnetDevices = []
            lastInventorySync = nil
            inventoryState = .notConfigured
            return
        }

        refreshInventory()
        startInventoryPolling()
    }

    /// 主线程 Timer：避免后台 DispatchSource 回调捕获 @MainActor self
    /// （见 CLAUDE.md 中 macOS 26 executor-isolation 的说明）。
    private func startInventoryPolling() {
        stopInventoryPolling()
        let stored = UserDefaults.standard.double(forKey: "pm.tailscaleInventoryInterval")
        let interval = stored >= 30 ? stored : 60
        inventoryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                TailscaleManager.shared.refreshInventory()
            }
        }
    }

    private func stopInventoryPolling() {
        inventoryTimer?.invalidate()
        inventoryTimer = nil
    }

    func refreshInventory() {
        guard isEnabled, isInventoryConfigured else {
            inventoryState = .notConfigured
            return
        }
        guard !isFetchingInventory else { return }
        isFetchingInventory = true

        Task {
            do {
                let devices = try await TailscaleAPIClient.shared.fetchDevices()
                self.tailnetDevices = devices
                self.lastInventorySync = Date()
                self.inventoryState = .ok
                self.isFetchingInventory = false
            } catch let error as TailscaleAPIError {
                self.inventoryState = .failed(Self.describe(error))
                self.isFetchingInventory = false
                LogManager.shared.warning("Tailnet inventory sync failed: \(error.rawDescription)")
            } catch {
                self.inventoryState = .failed(error.localizedDescription)
                self.isFetchingInventory = false
                LogManager.shared.warning("Tailnet inventory sync failed: \(error.localizedDescription)")
            }
        }
    }

    static func describe(_ error: TailscaleAPIError) -> String {
        if let key = error.localizationKey {
            return LanguageManager.shared.t(key)
        }
        return error.rawDescription
    }

    // MARK: - 控制面写操作
    //
    // 改的是 tailnet 配置，不是本机路由 —— 依旧不承载任何 tailnet 流量。
    // 所有动作完成后立即回拉清单，界面以服务端结果为准，不做乐观更新。

    @Published var pendingActionDeviceID: String?
    @Published var lastActionError: String?

    enum DeviceAction {
        case authorize(Bool)
        case keyExpiryDisabled(Bool)
        case tags([String])
        case enabledRoutes([String])
        case delete
    }

    func perform(_ action: DeviceAction, on device: TailnetDevice) {
        guard isEnabled else { return }
        guard pendingActionDeviceID == nil else { return }
        pendingActionDeviceID = device.id
        lastActionError = nil

        Task {
            do {
                let client = TailscaleAPIClient.shared
                switch action {
                case .authorize(let value):
                    try await client.setAuthorized(deviceID: device.id, authorized: value)
                    LogManager.shared.info("Tailnet: \(value ? "authorized" : "deauthorized") \(device.hostname)")
                case .keyExpiryDisabled(let value):
                    try await client.setKeyExpiryDisabled(deviceID: device.id, disabled: value)
                    LogManager.shared.info("Tailnet: key expiry \(value ? "disabled" : "enabled") for \(device.hostname)")
                case .tags(let tags):
                    try await client.setTags(deviceID: device.id, tags: tags)
                    LogManager.shared.info("Tailnet: tags of \(device.hostname) set to \(tags.joined(separator: ","))")
                case .enabledRoutes(let routes):
                    try await client.setEnabledRoutes(deviceID: device.id, routes: routes)
                    LogManager.shared.info("Tailnet: routes of \(device.hostname) set to \(routes.joined(separator: ","))")
                case .delete:
                    try await client.deleteDevice(deviceID: device.id)
                    LogManager.shared.warning("Tailnet: deleted device \(device.hostname)")
                }
                pendingActionDeviceID = nil
                refreshInventory()
            } catch let error as TailscaleAPIError {
                lastActionError = Self.describe(error)
                pendingActionDeviceID = nil
                LogManager.shared.error("Tailnet action failed on \(device.hostname): \(error.rawDescription)")
            } catch {
                lastActionError = error.localizedDescription
                pendingActionDeviceID = nil
                LogManager.shared.error("Tailnet action failed on \(device.hostname): \(error.localizedDescription)")
            }
        }
    }

    /// 切换单条路由的启用状态，按 routes 接口的全量覆盖语义拼出新集合。
    func toggleRoute(_ route: String, on device: TailnetDevice) {
        var routes = Set(device.enabledRoutes)
        if routes.contains(route) {
            routes.remove(route)
        } else {
            routes.insert(route)
        }
        perform(.enabledRoutes(Array(routes).sorted()), on: device)
    }

    /// 把控制面设备导入监控列表；探测仍走本机已有的 Tailscale 数据面。
    func importDevice(_ device: TailnetDevice, into viewModel: PingMonitorViewModel) {
        let address = device.tailscaleIP
        guard !address.isEmpty else { return }
        guard !viewModel.hosts.contains(where: { $0.address == address }) else { return }

        var newHost = HostConfig(name: device.hostname, address: address)
        newHost.isTailscaleNode = true
        newHost.tailscaleHostname = device.hostname
        newHost.displayRules = []

        viewModel.hosts.append(newHost)
        viewModel.hostStats[newHost.id] = HostStats(hostId: newHost.id)
        viewModel.saveSettings()

        if viewModel.isRunning, let index = viewModel.hosts.firstIndex(where: { $0.id == newHost.id }) {
            viewModel.startPingProcess(for: viewModel.hosts[index], at: index)
        }
    }

    func importAllOnlineDevices(into viewModel: PingMonitorViewModel) {
        // 跳过本机：ping 自己没有监控价值。
        for device in tailnetDevices where device.isOnline && device.tailscaleIP != selfIP {
            importDevice(device, into: viewModel)
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
