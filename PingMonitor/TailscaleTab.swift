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
                
                // Nodes List
                nodesCard
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
        .onAppear {
            tailscale.fetchStatus()
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.title"), icon: "network")
                    Spacer()
                    Button(action: { tailscale.fetchStatus() }) {
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
                    // Status
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
                    
                    // My IP
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("tailscale.my_ip"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.selfIP.isEmpty ? "—" : tailscale.selfIP)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    // Node count
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
            // OS Icon
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
            
            // Online indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(node.online ? Color.green : Color.red.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(node.online ? languageManager.t("tailscale.online") : languageManager.t("tailscale.offline"))
                    .font(Theme.Fonts.body(11))
                    .foregroundStyle(node.online ? .green : Theme.Colors.textTertiary)
            }
            .frame(width: 60)
            
            // Import button
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
