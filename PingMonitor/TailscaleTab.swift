import SwiftUI

// MARK: - Tailscale Tab

struct TailscaleTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var tailscale = TailscaleManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !tailscale.isEnabled {
                    integrationHintCard(text: languageManager.t("tailscale.integration_disabled"))
                } else if !tailscale.isAvailable {
                    integrationHintCard(text: languageManager.t("tailscale.cli_not_detected"))
                } else {
                    // Status Card
                    statusCard

                    // Exit Node Card
                    exitNodeCard

                    // NAT / Netcheck Card
                    netcheckCard

                    // Health Advice
                    healthAdviceCard

                    // Quick Commands
                    quickCommandsCard

                    // DERP Region Latency
                    if !tailscale.regionLatencies.isEmpty {
                        derpLatencyCard
                    }

                    // Nodes List
                    nodesCard
                }
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
        .onAppear {
            guard tailscale.isFunctional else { return }
            tailscale.fetchStatus()
            tailscale.fetchNetcheck()
        }
    }

    private func integrationHintCard(text: String) -> some View {
        ModernCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Colors.accentOrange)
                Text(text)
                    .font(Theme.Fonts.body(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Exit Node Card
    
    private var exitNodeCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Exit Node", icon: "arrow.up.forward.app.fill")
                    Spacer()
                    
                    Button(action: {
                        tailscale.testAllExitNodesLatency()
                    }) {
                        HStack(spacing: 4) {
                            if tailscale.isTestingExitNodes {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                            }
                            Text("Test Latency")
                                .font(Theme.Fonts.body(10))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentPurple.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(tailscale.isTestingExitNodes || tailscale.availableExitNodes.isEmpty)
                }
                
                // Current Exit Node
                if let currentExit = tailscale.currentExitNode {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Exit Node")
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(currentExit.hostname)
                                .font(Theme.Fonts.display(14))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            tailscale.disableExitNode()
                        }) {
                            Text("Disable")
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(8)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("No Exit Node active")
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider().opacity(0.15)
                
                // Available Exit Nodes
                if tailscale.availableExitNodes.isEmpty {
                    Text("No Exit Nodes available")
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    Text("Available Exit Nodes (click to switch)")
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.bottom, 4)
                    
                    ForEach(tailscale.availableExitNodes) { exitNode in
                        exitNodeRow(exitNode)
                        
                        if exitNode.id != tailscale.availableExitNodes.last?.id {
                            Divider().opacity(0.1)
                        }
                    }
                }
            }
        }
    }
    
    private func exitNodeRow(_ exitNode: ExitNode) -> some View {
        let isActive = tailscale.currentExitNode?.tailscaleIP == exitNode.node.tailscaleIP
        let scoreColor: Color = {
            switch exitNode.score {
            case 80...100: return .green
            case 60..<80: return Theme.Colors.accentOrange
            default: return .red
            }
        }()
        
        return Button(action: {
            if !isActive {
                tailscale.switchExitNode(to: exitNode.node)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: exitNode.node.osIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? .green : Theme.Colors.accentBlue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exitNode.node.hostname)
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(isActive ? .green : Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if isActive {
                            Text("Active")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.green)
                                .cornerRadius(3)
                        }
                    }
                    
                    Text(exitNode.node.tailscaleIP)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                // Score and Latency indicator
                VStack(alignment: .trailing, spacing: 2) {
                    if let _ = exitNode.latency {
                        HStack(spacing: 4) {
                            Text("Score: \(exitNode.score)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(scoreColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(scoreColor.opacity(0.1))
                                .cornerRadius(3)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(scoreColor)
                                    .frame(width: 6, height: 6)
                                Text(exitNode.latencyString)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(scoreColor)
                            }
                        }
                        
                        if let loss = exitNode.packetLoss, loss > 0 {
                            Text("Loss: \(String(format: "%.1f%%", loss))")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.green.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isActive)
    }
    
    // MARK: - Status Card
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.title"), icon: "network")
                    Spacer()
                    Button(action: {
                        tailscale.fetchStatus()
                        tailscale.fetchNetcheck()
                    }) {
                        HStack(spacing: 4) {
                            if tailscale.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(languageManager.t("tailscale.refresh"))
                                .font(Theme.Fonts.body(11))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.cardBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(tailscale.isLoading)
                }
                
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("tailscale.status"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tailscale.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(tailscale.isConnected ? languageManager.t("tailscale.connected") : languageManager.t("tailscale.disconnected"))
                                .font(Theme.Fonts.display(16))
                                .foregroundStyle(tailscale.isConnected ? .green : .red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("tailscale.my_ip"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.selfIP.isEmpty ? "—" : tailscale.selfIP)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.accentBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("tailscale.nodes"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("\(tailscale.nodes.count)")
                            .font(Theme.Fonts.display(16))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    
                    Spacer()
                }
                
                if let error = tailscale.lastError {
                    Text(error)
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
    }
    
    // MARK: - Quick Commands Card
    
    private var quickCommandsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Quick Commands", icon: "command")
                
                HStack(spacing: 12) {
                    CommandButton(title: "Status", icon: "terminal", action: { tailscale.fetchStatus() })
                    CommandButton(title: "Netcheck", icon: "shield.checkered", action: { tailscale.fetchNetcheck() })
                    CommandButton(title: "Ping All", icon: "waveform", action: { executeTailscale("ping --all") })
                    CommandButton(title: "Reset Exit", icon: "arrow.uturn.backward.circle", action: { tailscale.disableExitNode() })
                }
            }
        }
    }
    
    private func executeTailscale(_ cmd: String) {
        let args = cmd.components(separatedBy: " ")
        Task {
            await tailscale.runTailscaleCommand(args)
        }
    }
    
    struct CommandButton: View {
        let title: String
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                    Text(title)
                        .font(Theme.Fonts.body(10))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Netcheck Card
    
    private var netcheckCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.netcheck"), icon: "shield.checkered")
                    Spacer()
                    if tailscale.netcheckLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
                
                // NAT Type (prominent)
                HStack(spacing: 12) {
                    Image(systemName: natIcon)
                        .font(.system(size: 22))
                        .foregroundStyle(natColor)
                        .frame(width: 36, height: 36)
                        .background(natColor.opacity(0.12))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(languageManager.t("tailscale.nat_type"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.natType)
                            .font(Theme.Fonts.display(16))
                            .foregroundStyle(natColor)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(languageManager.t("tailscale.preferred_derp"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.preferredDERP)
                            .font(Theme.Fonts.display(14))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                }
                
                Divider().opacity(0.2)
                
                // Protocol indicators
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    protocolBadge(label: "UDP", enabled: tailscale.udpEnabled)
                    protocolBadge(label: "IPv4", enabled: tailscale.ipv4Enabled)
                    protocolBadge(label: "IPv6", enabled: tailscale.ipv6Enabled)
                    protocolBadge(label: "UPnP", enabled: tailscale.upnp ?? false)
                    protocolBadge(label: "Hairpin", enabled: tailscale.hairPinning ?? false)
                    protocolBadge(label: languageManager.t("tailscale.captive_portal"), enabled: !tailscale.captivePortal, invertColor: true)
                }
                
                // Global IPs
                if tailscale.globalIPv4 != "—" || tailscale.globalIPv6 != "—" {
                    Divider().opacity(0.2)
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Global IPv4")
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(tailscale.globalIPv4)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Global IPv6")
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(tailscale.globalIPv6)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - DERP Latency Card
    
    private var derpLatencyCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("tailscale.derp_latency"), icon: "globe.americas.fill")
                
                ForEach(tailscale.regionLatencies.prefix(10)) { region in
                    HStack(spacing: 10) {
                        Text(region.regionName)
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 120, alignment: .leading)
                        
                        GeometryReader { geo in
                            let maxLatency = tailscale.regionLatencies.map(\.latency).max() ?? 1
                            let ratio = min(region.latency / maxLatency, 1.0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(latencyBarColor(region.latency))
                                .frame(width: max(geo.size.width * ratio, 4))
                        }
                        .frame(height: 8)
                        
                        Text(String(format: "%.0fms", region.latency))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(latencyBarColor(region.latency))
                            .frame(width: 55, alignment: .trailing)
                    }
                    .frame(height: 20)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func protocolBadge(label: String, enabled: Bool, invertColor: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(invertColor ? (enabled ? Color.green : Color.red) : (enabled ? Color.green : Color.red.opacity(0.5)))
                .frame(width: 6, height: 6)
            Text(label)
                .font(Theme.Fonts.body(11))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(enabled ? "✓" : "✗")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Color.green : Color.red.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(6)
    }
    
    private var natIcon: String {
        switch tailscale.natType {
        case "Easy NAT", "Full Cone NAT": return "checkmark.shield.fill"
        case "Symmetric NAT": return "exclamationmark.shield.fill"
        default: return "xmark.shield.fill"
        }
    }
    
    private var natColor: Color {
        switch tailscale.natType {
        case "Easy NAT", "Full Cone NAT": return .green
        case "Symmetric NAT": return Theme.Colors.accentOrange
        default: return .red
        }
    }
    
    private func latencyBarColor(_ ms: Double) -> Color {
        if ms < 50 { return .green }
        if ms < 150 { return Theme.Colors.accentOrange }
        return .red
    }
    
    private var healthAdviceCard: some View {
        Group {
            if !tailscale.healthAdvice.isEmpty {
                ModernCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: languageManager.t("tailscale.health_report"), icon: "heart.text.square.fill")
                        
                        ForEach(tailscale.healthAdvice, id: \.self) { advice in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Colors.accentOrange)
                                    .padding(.top, 2)
                                Text(advice)
                                    .font(Theme.Fonts.body(11))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.cardBackground.opacity(0.5))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.Colors.accentOrange.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func connectionTypeBadge(_ type: TailscaleConnectionType) -> some View {
        let (color, icon): (Color, String) = {
            switch type {
            case .p2p: return (.green, "bolt.fill")
            case .relay: return (Theme.Colors.accentOrange, "arrow.triangle.2.circlepath")
            case .derp: return (Theme.Colors.accentPurple, "cloud.fill")
            case .unknown: return (Theme.Colors.textTertiary, "questionmark.circle")
            }
        }()
        
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(type.rawValue)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .cornerRadius(4)
    }
    
    // MARK: - Nodes Card
    
    private var nodesCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.nodes"), icon: "desktopcomputer")
                    Spacer()
                    
                    Button(action: {
                        tailscale.importAllOnlineNodes(into: viewModel)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 10, weight: .semibold))
                            Text(languageManager.t("tailscale.import_all"))
                                .font(Theme.Fonts.body(11))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                if tailscale.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 30)
                        Spacer()
                    }
                } else if tailscale.nodes.isEmpty {
                    Text(languageManager.t("tailscale.not_available"))
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tailscale.nodes) { node in
                            nodeRow(node)
                            if node.id != tailscale.nodes.last?.id {
                                Divider().padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Node Row
    
    private func nodeRow(_ node: TailscaleNode) -> some View {
        let isMonitored = viewModel.hosts.contains(where: { $0.address == node.tailscaleIP })
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: node.osIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(node.online ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(node.hostname)
                            .font(Theme.Fonts.display(13))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if node.isSelf {
                            Text(languageManager.t("tailscale.self"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(4)
                                .layoutPriority(1)
                        }
                    }
                    
                    Text(node.tailscaleIP)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(node.online ? Color.green : Color.red.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(node.online ? languageManager.t("tailscale.online") : languageManager.t("tailscale.offline"))
                            .font(Theme.Fonts.body(11))
                            .foregroundStyle(node.online ? .green : Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    
                    // Connection type badge
                    if node.connectionType != .unknown {
                        connectionTypeBadge(node.connectionType)
                            .layoutPriority(1)
                    }
                    
                    if node.online && !node.isSelf {
                        Button(action: {
                            tailscale.runPathDiagnosis(for: node)
                        }) {
                            if node.isCheckingPath {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                                    .frame(width: 20)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.Colors.accentBlue)
                                    .frame(width: 20)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(node.isCheckingPath)
                    }
                    
                    if node.exitNode || node.exitNodeOption {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.accentPurple)
                            .help(node.exitNode ? "Active Exit Node" : "Exit Node Available")
                    }
                    
                    if !node.isSelf {
                        if isMonitored {
                            Text(languageManager.t("tailscale.already_monitored"))
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.cardBackground)
                                .cornerRadius(4)
                                .layoutPriority(1)
                        } else {
                            Button(action: {
                                tailscale.importNode(node, into: viewModel)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 10))
                                    Text(languageManager.t("tailscale.import"))
                                        .font(Theme.Fonts.body(10))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.accentBlue.opacity(0.15))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .layoutPriority(1)
                        }
                    }
                }
            }
            
            if let result = node.lastPingResult {
                HStack {
                    Spacer().frame(width: 40)
                    Text(result)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(result.contains("P2P") ? .green : (result.contains("Error") ? .red : Theme.Colors.accentOrange))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.top, -2)
            }
        }
        .padding(.vertical, 8)
        .opacity(node.online ? 1.0 : 0.5)
    }
}
