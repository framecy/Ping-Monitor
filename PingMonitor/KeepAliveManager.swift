import Foundation
import Combine

enum KeepAliveStrategy: String, Codable, CaseIterable {
    case passive = "Passive"   // Normal monitoring
    case intensive = "Intensive" // High frequency (SSH/SFTP)
    case adaptive = "Adaptive"  // Based on traffic
}

struct KeepAliveRule: Identifiable, Codable {
    var id = UUID()
    var name: String
    var interface: String // e.g., "utun0"
    var strategy: KeepAliveStrategy = .adaptive
    var idleThreshold: TimeInterval = 300 // 5 minutes
    var activeInterval: TimeInterval = 10.0
    var keepAliveInterval: TimeInterval = 0.5 // 500ms
    var isEnabled: Bool = true
}

@MainActor
class KeepAliveManager: ObservableObject {
    static let shared = KeepAliveManager()
    
    @Published var rules: [KeepAliveRule] = []
    @Published var activeKeepAlives: Set<String> = [] // interfaces currently in keep-alive mode
    
    private var timer: Timer?
    private var lastTrafficSeen: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadRules()
        startMonitoring()
    }
    
    func loadRules() {
        // Default rules if none saved
        if rules.isEmpty {
            rules = [
                KeepAliveRule(name: "Tailscale Keep-Alive", interface: "utun", strategy: .adaptive)
            ]
        }
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkTrafficAndApplyRules()
            }
        }
    }
    
    private func checkTrafficAndApplyRules() async {
        let interfaces = NetworkSpeedManager.shared.interfaces
        let now = Date()
        
        for rule in rules where rule.isEnabled {
            // Find interface by prefix (e.g., "utun" matches "utun0", "utun1")
            let matchingIfaces = interfaces.filter { $0.name.starts(with: rule.interface) }
            
            for iface in matchingIfaces {
                let hasTraffic = iface.speedIn > 0 || iface.speedOut > 0
                
                if hasTraffic {
                    lastTrafficSeen[iface.name] = now
                    if activeKeepAlives.contains(iface.name) {
                        LogManager.shared.info("Traffic detected on \(iface.name), exiting keep-alive mode.")
                        activeKeepAlives.remove(iface.name)
                        // Trigger UI/Ping adjustment back to normal
                        NotificationCenter.default.post(name: .keepAliveStatusChanged, object: nil, userInfo: ["interface": iface.name, "active": false])
                    }
                } else {
                    let lastSeen = lastTrafficSeen[iface.name] ?? .distantPast
                    let idleTime = now.timeIntervalSince(lastSeen)
                    
                    if idleTime > rule.idleThreshold && !activeKeepAlives.contains(iface.name) {
                        LogManager.shared.info("Interface \(iface.name) idle for \(Int(idleTime))s, entering keep-alive mode.")
                        activeKeepAlives.insert(iface.name)
                        // Trigger UI/Ping adjustment to intensive
                        NotificationCenter.default.post(name: .keepAliveStatusChanged, object: nil, userInfo: ["interface": iface.name, "active": true])
                    }
                }
            }
        }
    }
}

extension NSNotification.Name {
    static let keepAliveStatusChanged = NSNotification.Name("keepAliveStatusChanged")
}
