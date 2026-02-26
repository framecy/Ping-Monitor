import SwiftUI

// MARK: - Tailscale Tab

struct TailscaleTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var tailscale = TailscaleManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Card
                statusCard
                
                // NAT / Netcheck Card
                netcheckCard
                
                // DERP Region Latency
                if !tailscale.regionLatencies.isEmpty {
                    derpLatencyCard
                }
                
                // Nodes List
                nodesCard
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
        .onAppear {
            tailscale.fetchStatus()
            tailscale.fetchNetcheck()
        }
    }
    
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
        
        return HStack(spacing: 12) {
            Image(systemName: node.osIcon)
                .font(.system(size: 16))
                .foregroundStyle(node.online ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.hostname)
                        .font(Theme.Fonts.display(13))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    if node.isSelf {
                        Text(languageManager.t("tailscale.self"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accentBlue)
                            .cornerRadius(4)
                    }
                }
                
                Text(node.tailscaleIP)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(node.online ? Color.green : Color.red.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(node.online ? languageManager.t("tailscale.online") : languageManager.t("tailscale.offline"))
                    .font(Theme.Fonts.body(11))
                    .foregroundStyle(node.online ? .green : Theme.Colors.textTertiary)
            }
            .frame(width: 60)
            
            if !node.isSelf {
                if isMonitored {
                    Text(languageManager.t("tailscale.already_monitored"))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.cardBackground)
                        .cornerRadius(4)
                } else {
                    Button(action: {
                        tailscale.importNode(node, into: viewModel)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                            Text(languageManager.t("tailscale.import"))
                                .font(Theme.Fonts.body(10))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(node.online ? 1.0 : 0.5)
    }
}
