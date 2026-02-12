import SwiftUI
import Charts

struct HostDetailView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    let host: HostConfig
    let onClose: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    
    private var stats: HostStats? {
        viewModel.hostStats[host.id]
    }
    
    private var currentHost: HostConfig? {
        viewModel.hosts.first(where: { $0.id == host.id })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    // Row 1: Status + Latency
                    HStack(alignment: .top, spacing: 16) {
                        statusCard
                        latencyStatsCard
                    }
                    
                    // Row 2: Chart
                    latencyChartCard
                    
                    // Row 3: Packet Stats + Traffic
                    HStack(alignment: .top, spacing: 16) {
                        packetStatsCard
                        trafficCard
                    }
                    
                    // Row 4: Display Rules
                    if !host.displayRules.isEmpty {
                        displayRulesCard
                    }
                }
                .padding()
            }
        }
        .background(Theme.Colors.background)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(languageManager.t("monitor.title"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.Colors.accentBlue)
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Host indicator
            Circle()
                .fill(currentHost?.isReachable == true ? Color.green : Color.red.opacity(0.6))
                .frame(width: 8, height: 8)
                .shadow(color: currentHost?.isReachable == true ? .green.opacity(0.5) : .clear, radius: 4)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(host.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(host.address)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            
            Spacer()
            
            // Live latency badge
            if let latency = currentHost?.lastLatency {
                HStack(spacing: 6) {
                    Circle()
                        .fill(latencyColor(latency))
                        .frame(width: 6, height: 6)
                    Text("\(Int(latency)) ms")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(latencyColor(latency))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(latencyColor(latency).opacity(0.1))
                )
            } else if currentHost?.isChecking == true {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(languageManager.t("host_detail.checking"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Theme.Colors.accentBlue)
                    Text(languageManager.t("host_detail.connection_status"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("host_detail.status"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(currentHost?.isReachable == true ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(currentHost?.isReachable == true ? languageManager.t("host_detail.online") : languageManager.t("host_detail.offline"))
                                .font(Theme.Fonts.display(18))
                                .foregroundStyle(currentHost?.isReachable == true ? .green : .red)
                        }
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("host_detail.uptime"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        if let stats = stats {
                            Text(formatDuration(from: stats.startTime))
                                .font(Theme.Fonts.display(18))
                                .foregroundStyle(Theme.Colors.accentBlue)
                        } else {
                            Text("--")
                                .font(Theme.Fonts.display(18))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                
                Spacer()
                
                // Ping command
                if !host.command.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(host.command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
    
    // MARK: - Latency Stats Card
    
    private var latencyStatsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .foregroundStyle(Theme.Colors.accentGreen)
                    Text(languageManager.t("host_detail.latency_stats"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 0) {
                    DetailStatItem(
                        label: languageManager.t("host_detail.current"),
                        value: currentHost?.lastLatency != nil ? "\(Int(currentHost!.lastLatency!)) ms" : "--",
                        color: currentHost?.lastLatency != nil ? latencyColor(currentHost!.lastLatency!) : Theme.Colors.textTertiary
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.min"),
                        value: stats?.minLatency != nil ? String(format: "%.1f ms", stats!.minLatency!) : "--",
                        color: .green
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.max"),
                        value: stats?.maxLatency != nil ? String(format: "%.1f ms", stats!.maxLatency!) : "--",
                        color: .red
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.avg"),
                        value: stats != nil && stats!.avgLatency > 0 ? String(format: "%.1f ms", stats!.avgLatency) : "--",
                        color: Theme.Colors.accentBlue
                    )
                }
                
                Spacer()
                
                // Jitter (max - min)
                if let min = stats?.minLatency, let max = stats?.maxLatency {
                    HStack(spacing: 6) {
                        Text(languageManager.t("host_detail.jitter"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(String(format: "%.1f ms", max - min))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.accentOrange)
                    }
                }
            }
        }
    }
    
    // MARK: - Latency Chart
    
    private var latencyChartCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(Theme.Colors.accentPurple)
                    Text(languageManager.t("host_detail.latency_chart"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    
                    if let history = stats?.latencyHistory, !history.isEmpty {
                        Text("\(history.count) " + languageManager.t("host_detail.data_points"))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                
                if let history = stats?.latencyHistory, !history.isEmpty {
                    let recent = Array(history.suffix(60))
                    
                    Chart {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, point in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Latency", point.latency)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentBlue, Theme.Colors.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            
                            AreaMark(
                                x: .value("Time", index),
                                y: .value("Latency", point.latency)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentBlue.opacity(0.25), Theme.Colors.accentBlue.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        
                        // Avg line
                        if let avg = stats?.avgLatency, avg > 0 {
                            RuleMark(y: .value("Avg", avg))
                                .foregroundStyle(Theme.Colors.accentOrange.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text(String(format: "%.0f ms", avg))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.accentOrange)
                                }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel()
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .font(.system(size: 9))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in }
                    }
                    .frame(minHeight: 160)
                } else {
                    VStack {
                        Spacer()
                        Text(languageManager.t("dashboard.no_data"))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                    .frame(minHeight: 120)
                }
            }
        }
    }
    
    // MARK: - Packet Stats Card
    
    private var packetStatsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(Theme.Colors.accentOrange)
                    Text(languageManager.t("host_detail.packet_stats"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 0) {
                    DetailStatItem(
                        label: languageManager.t("host_detail.total_pings"),
                        value: "\(stats?.totalPings ?? 0)",
                        color: Theme.Colors.accentBlue
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.success"),
                        value: "\(stats?.successfulPings ?? 0)",
                        color: .green
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.failed"),
                        value: "\(stats?.failedPings ?? 0)",
                        color: .red
                    )
                }
                
                Spacer()
                
                // Success rate bar
                HStack(spacing: 8) {
                    Text(languageManager.t("host_detail.success_rate"))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Colors.cardBackground.opacity(0.5))
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(successRateColor)
                                .frame(width: geo.size.width * CGFloat((stats?.successRate ?? 0) / 100.0))
                        }
                    }
                    .frame(height: 6)
                    
                    Text(String(format: "%.1f%%", stats?.successRate ?? 0))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(successRateColor)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
    
    // MARK: - Traffic Card
    
    private var trafficCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundStyle(Theme.Colors.accentPurple)
                    Text(languageManager.t("host_detail.traffic"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                            Text(languageManager.t("host_detail.sent"))
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(formatTrafficBytes(stats?.totalBytesSent ?? 0))
                            .font(Theme.Fonts.display(18))
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.accentBlue)
                            Text(languageManager.t("host_detail.received"))
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(formatTrafficBytes(stats?.totalBytesReceived ?? 0))
                            .font(Theme.Fonts.display(18))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Total traffic
                HStack(spacing: 6) {
                    Text(languageManager.t("host_detail.total_traffic"))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(stats?.totalTraffic ?? "0 B")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
    }
    
    // MARK: - Display Rules Card
    
    private var displayRulesCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "tag")
                        .foregroundStyle(Theme.Colors.accentBlue)
                    Text(languageManager.t("host_detail.display_rules"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                ForEach(host.displayRules) { rule in
                    HStack(spacing: 10) {
                        // Status dot
                        let isActive = isRuleActive(rule)
                        Circle()
                            .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        
                        // Rule label
                        Text(rule.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        
                        // Condition
                        Text(rule.condition == "less" ? "< \(Int(rule.threshold)) ms" : "> \(Int(rule.threshold)) ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                        
                        // Enabled badge
                        Text(rule.enabled ? languageManager.t("host_detail.enabled") : languageManager.t("host_detail.disabled"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(rule.enabled ? .green : Theme.Colors.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(rule.enabled ? Color.green.opacity(0.1) : Theme.Colors.cardBackground)
                            )
                    }
                    .padding(.vertical, 4)
                    
                    if rule.id != host.displayRules.last?.id {
                        Divider().opacity(0.15)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func latencyColor(_ latency: Double) -> Color {
        if latency < 50 { return .green }
        if latency < 100 { return .orange }
        return .red
    }
    
    private var successRateColor: Color {
        let rate = stats?.successRate ?? 0
        if rate >= 95 { return .green }
        if rate >= 80 { return .orange }
        return .red
    }
    
    private func isRuleActive(_ rule: DisplayRule) -> Bool {
        guard rule.enabled, let latency = currentHost?.lastLatency else { return false }
        return rule.condition == "less" ? latency < rule.threshold : latency > rule.threshold
    }
    
    private func formatDuration(from startTime: Date) -> String {
        let interval = Date().timeIntervalSince(startTime)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }
    
    private func formatTrafficBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Detail Stat Item

struct DetailStatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Fonts.body(10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.display(18))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
