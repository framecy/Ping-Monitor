import SwiftUI

struct TracerouteView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @StateObject private var manager = TracerouteManager()
    @State private var targetHost = ""
    @State private var showCopied = false
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            if manager.hops.isEmpty && !manager.isRunning {
                // Empty state
                emptyStateView
            } else {
                // Results
                ScrollView {
                    VStack(spacing: 16) {
                        // Status bar
                        statusBar
                        
                        // Hop table
                        hopTableView
                    }
                    .padding()
                }
            }
        }
        .background(Theme.Colors.background)
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Host input
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Theme.Colors.accentBlue)
                        .font(.system(size: 14))
                    
                    TextField(languageManager.t("traceroute.input_placeholder"), text: $targetHost)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .onSubmit {
                            if !manager.isRunning {
                                manager.startTrace(host: targetHost)
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.Colors.cardBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )
                
                // MTR toggle
                Toggle(isOn: $manager.isMTRMode) {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                        Text(languageManager.t("traceroute.mtr_mode"))
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(manager.isRunning)
                
                // Start/Stop button
                Button(action: {
                    if manager.isRunning {
                        manager.stop()
                    } else {
                        manager.startTrace(host: targetHost)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                        Text(manager.isRunning ? languageManager.t("traceroute.stop") : languageManager.t("traceroute.start"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(manager.isRunning ? Color.red.opacity(0.15) : Theme.Colors.accentBlue.opacity(0.15))
                    )
                    .foregroundStyle(manager.isRunning ? .red : Theme.Colors.accentBlue)
                }
                .buttonStyle(.plain)
                .disabled(targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !manager.isRunning)
                
                // Copy button
                if !manager.hops.isEmpty {
                    Button(action: {
                        manager.copyResultsToClipboard()
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(showCopied ? languageManager.t("traceroute.copied") : languageManager.t("traceroute.copy"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(showCopied ? Color.green.opacity(0.15) : Theme.Colors.cardBackground)
                        )
                        .foregroundStyle(showCopied ? .green : Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // MTR hint
            if manager.isMTRMode {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(languageManager.t("traceroute.mtr_hint"))
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)
                
                ZStack {
                    Circle()
                        .fill(
                            .linearGradient(
                                colors: [Theme.Colors.accentBlue.opacity(0.15), Theme.Colors.accentPurple.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Theme.Colors.accentBlue, Theme.Colors.accentPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text(languageManager.t("traceroute.no_result"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(languageManager.t("traceroute.hint"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                
                // Quick targets
                HStack(spacing: 8) {
                    QuickTargetButton(label: "8.8.8.8", icon: "globe") {
                        targetHost = "8.8.8.8"
                        manager.startTrace(host: targetHost)
                    }
                    QuickTargetButton(label: "1.1.1.1", icon: "shield") {
                        targetHost = "1.1.1.1"
                        manager.startTrace(host: targetHost)
                    }
                    QuickTargetButton(label: "baidu.com", icon: "network") {
                        targetHost = "www.baidu.com"
                        manager.startTrace(host: targetHost)
                    }
                }
                .padding(.top, 4)
                
                // Monitored hosts section
                if viewModel.isRunning && !viewModel.hosts.isEmpty {
                    monitoredHostsSection
                }
                
                Spacer(minLength: 30)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Monitored Hosts Section
    
    private var monitoredHostsSection: some View {
        VStack(spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Theme.Colors.accentPurple)
                    .font(.system(size: 13))
                Text(languageManager.t("traceroute.monitored_hosts"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Badge(
                    text: "\(viewModel.hosts.count)",
                    color: Theme.Colors.accentBlue
                )
            }
            .padding(.horizontal, 16)
            
            // Host cards grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ForEach(viewModel.hosts) { host in
                    MonitoredHostCard(host: host) {
                        targetHost = host.address
                        manager.startTrace(host: host.address)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack(spacing: 10) {
            if manager.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else if !manager.hops.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            }
            
            Text(manager.progress)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            
            Spacer()
            
            if !manager.hops.isEmpty {
                // Summary stats
                let validHops = manager.hops.filter { !$0.isTimeout }
                let timeoutHops = manager.hops.filter { $0.isTimeout }
                
                HStack(spacing: 12) {
                    HopSummaryBadge(
                        icon: "arrow.triangle.branch",
                        value: "\(manager.hops.count)",
                        label: languageManager.t("traceroute.hop"),
                        color: Theme.Colors.accentBlue
                    )
                    
                    if let avgAll = validHops.compactMap({ $0.avgLatency }).isEmpty ? nil :
                        validHops.compactMap({ $0.avgLatency }).reduce(0, +) / Double(validHops.compactMap({ $0.avgLatency }).count) {
                        HopSummaryBadge(
                            icon: "timer",
                            value: String(format: "%.1f ms", avgAll),
                            label: languageManager.t("traceroute.avg"),
                            color: latencyColor(avgAll)
                        )
                    }
                    
                    if !timeoutHops.isEmpty {
                        HopSummaryBadge(
                            icon: "exclamationmark.triangle",
                            value: "\(timeoutHops.count)",
                            label: languageManager.t("traceroute.timeout"),
                            color: Theme.Colors.accentOrange
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Hop Table
    
    private var hopTableView: some View {
        VStack(spacing: 0) {
            // Table header
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 40, alignment: .center)
                Text(languageManager.t("traceroute.ip"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(0..<3, id: \.self) { i in
                    Text("\(languageManager.t("traceroute.latency")) \(i + 1)")
                        .frame(width: 90, alignment: .trailing)
                }
                
                Text(languageManager.t("traceroute.avg"))
                    .frame(width: 90, alignment: .trailing)
                Text(languageManager.t("traceroute.loss"))
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.Colors.cardBackground.opacity(0.5))
            
            Divider().opacity(0.3)
            
            // Table rows
            ForEach(Array(manager.hops.enumerated()), id: \.element.id) { index, hop in
                HopRowView(hop: hop, isEven: index % 2 == 0)
                
                if index < manager.hops.count - 1 {
                    Divider().opacity(0.15).padding(.horizontal, 16)
                }
            }
            
            // Loading indicator for running trace
            if manager.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func latencyColor(_ latency: Double) -> Color {
        if latency < 50 { return .green }
        if latency < 100 { return .orange }
        return .red
    }
}

// MARK: - Subviews

struct HopRowView: View {
    let hop: TracerouteHop
    let isEven: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Hop number with color bar
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(hop.latencyColor)
                    .frame(width: 3, height: 20)
                
                Text("\(hop.hopNumber)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: 40, alignment: .center)
            
            // Host / IP
            VStack(alignment: .leading, spacing: 2) {
                if hop.isTimeout {
                    Text("* * *")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    Text(hop.hostName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if hop.hostName != hop.ip {
                        Text(hop.ip)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Individual latencies
            ForEach(0..<3, id: \.self) { i in
                if i < hop.latencies.count, let lat = hop.latencies[i] {
                    Text(String(format: "%.1f", lat))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(latencyColor(lat))
                        .frame(width: 90, alignment: .trailing)
                } else {
                    Text(i < hop.latencies.count ? "*" : "-")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            
            // Average
            Text(hop.formattedAvg)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(hop.latencyColor)
                .frame(width: 90, alignment: .trailing)
            
            // Loss
            Text(hop.formattedLoss)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(hop.packetLoss > 0 ? Theme.Colors.accentOrange : Theme.Colors.accentGreen)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.white.opacity(0.03) : (isEven ? Color.clear : Color.white.opacity(0.01)))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func latencyColor(_ latency: Double) -> Color {
        if latency < 50 { return .green }
        if latency < 100 { return .orange }
        return .red
    }
}

struct QuickTargetButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
            )
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct HopSummaryBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

struct MonitoredHostCard: View {
    let host: HostConfig
    let onTrace: () -> Void
    @State private var isHovered = false
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        Button(action: onTrace) {
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(host.isReachable ? latencyColor : .gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .shadow(color: host.isReachable ? latencyColor.opacity(0.5) : .clear, radius: 3)
                
                // Host info
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(host.address)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Latency badge
                if let latency = host.lastLatency {
                    Text("\(Int(latency))ms")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(latencyColor)
                } else if host.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Text("--")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.accentBlue.opacity(isHovered ? 1 : 0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Theme.Colors.accentBlue.opacity(0.3) : Theme.Colors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var latencyColor: Color {
        guard let latency = host.lastLatency else { return .gray }
        if latency < 50 { return .green }
        if latency < 100 { return .orange }
        return .red
    }
}
