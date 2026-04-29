
import SwiftUI
import UniformTypeIdentifiers
import Charts

// MARK: - Sidebar Navigation Item
enum SidebarItem: String, CaseIterable, Identifiable {
    case monitor
    case statistics
    case traceroute
    case netspeed
    case tailscale
    case services
    case hosts
    case logs
    case settings
    
    var id: String { rawValue }
    
    @MainActor var title: String {
        switch self {
        case .monitor: return LanguageManager.shared.t("sidebar.monitor")
        case .statistics: return LanguageManager.shared.t("sidebar.dashboard")
        case .traceroute: return LanguageManager.shared.t("sidebar.traceroute")
        case .netspeed: return LanguageManager.shared.t("sidebar.netspeed")
        case .tailscale: return LanguageManager.shared.t("sidebar.tailscale")
        case .services: return LanguageManager.shared.t("sidebar.services")
        case .hosts: return LanguageManager.shared.t("sidebar.hosts")
        case .logs: return LanguageManager.shared.t("sidebar.logs")
        case .settings: return LanguageManager.shared.t("sidebar.settings")
        }
    }
    
    var icon: String {
        switch self {
        case .monitor: return "waveform.path.ecg"
        case .statistics: return "chart.bar.fill"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .netspeed: return "chart.line.uptrend.xyaxis"
        case .tailscale: return "network"
        case .services: return "square.grid.2x2.fill"
        case .hosts: return "server.rack"
        case .logs: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    var activeColor: Color {
        switch self {
        case .monitor: return .green
        case .statistics: return .blue
        case .traceroute: return .cyan
        case .netspeed: return .teal
        case .tailscale: return .indigo
        case .services: return .mint
        case .hosts: return .purple
        case .logs: return .orange
        case .settings: return .gray
        }
    }
}

struct MainView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedItem: SidebarItem = .monitor
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedItem: $selectedItem)
                .frame(width: 220)
                .background(Theme.Colors.sidebarBackground)
            
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)
            
            VStack(spacing: 0) {
                headerView
                
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.Colors.background)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onChange(of: languageManager.currentLanguage) { _, _ in
            viewModel.updateStatusBarDisplay()
            viewModel.syncToWidget()
        }
    }
    
    // MARK: - Detail Content
    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem {
        case .monitor:
            MonitorTab(viewModel: viewModel)
        case .statistics:
            DashboardView(viewModel: viewModel)
        case .traceroute:
            TracerouteView(viewModel: viewModel)
        case .netspeed:
            NetworkSpeedTab(viewModel: viewModel)
        case .tailscale:
            TailscaleTab(viewModel: viewModel)
        case .services:
            ServicesTab(viewModel: viewModel)
        case .hosts:
            HostManagementTab(viewModel: viewModel)
        case .logs:
            LogsTab()
        case .settings:
            SettingsTab(viewModel: viewModel)
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 14) {
            // Animated status indicator
            ZStack {
                if viewModel.isRunning {
                    Circle()
                        .fill(.green.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .scaleEffect(viewModel.isRunning ? 1.6 : 1.0)
                        .opacity(viewModel.isRunning ? 0 : 0.6)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isRunning)
                }
                Circle()
                    .fill(viewModel.isRunning ? .green : .gray.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .shadow(color: viewModel.isRunning ? .green.opacity(0.5) : .clear, radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedItem.title)
                    .font(.system(size: 16, weight: .bold))
                Text(viewModel.isRunning ? String(format: languageManager.t("header.monitoring"), viewModel.hosts.count) : languageManager.t("header.stopped"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Language Toggle
            Button(action: { languageManager.toggle() }) {
                Text(languageManager.currentLanguage == .zh ? "EN" : "中")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(6)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Switch Language")

            // Tailscale Quick Action
            TailscaleQuickActionView()

            Button(action: { viewModel.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(viewModel.isRunning ? languageManager.t("header.stop") : languageManager.t("header.start"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(viewModel.isRunning ? .red.opacity(0.15) : .green.opacity(0.15))
                )
                .foregroundStyle(viewModel.isRunning ? .red : .green)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    viewModel.isRunning ? Color.green.opacity(0.04) : Color.gray.opacity(0.03),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .background(.ultraThinMaterial)
    }
}

struct TailscaleQuickActionView: View {
    @ObservedObject var tailscale = TailscaleManager.shared
    @ObservedObject var languageManager = LanguageManager.shared
    
    var body: some View {
        Menu {
            if tailscale.availableExitNodes.isEmpty {
                Text(languageManager.t("tailscale.no_exit_nodes"))
            } else {
                Button(action: { tailscale.disableExitNode() }) {
                    HStack {
                        Text(languageManager.t("settings.none"))
                        if tailscale.currentExitNode == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                ForEach(tailscale.availableExitNodes) { exitNode in
                    Button(action: { tailscale.switchExitNode(to: exitNode.node) }) {
                        HStack {
                            Text(exitNode.node.hostname)
                            if let lat = exitNode.latency {
                                Text("(\(Int(lat))ms)").foregroundStyle(.secondary)
                            }
                            if tailscale.currentExitNode?.tailscaleIP == exitNode.node.tailscaleIP {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(.system(size: 12))
                if let current = tailscale.currentExitNode {
                    Text(current.hostname)
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Text("Tailscale")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tailscale.currentExitNode != nil ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .foregroundStyle(tailscale.currentExitNode != nil ? .blue : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - 统计 Tab
struct StatisticsTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedHost: HostConfig?
    @State private var selectedWindow: NetworkQualityWindow = .fiveMinutes
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if viewModel.hosts.count > 1 {
                    Picker(languageManager.t("stats.select_host"), selection: $selectedHost) {
                        Text(languageManager.t("stats.all_hosts")).tag(nil as HostConfig?)
                        ForEach(viewModel.hosts) { host in
                            Text(host.name).tag(host as HostConfig?)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("stats.quality_assessment"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(languageManager.t("stats.dimension_readability"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Picker("", selection: $selectedWindow) {
                        Text(languageManager.t("dashboard.window_1m")).tag(NetworkQualityWindow.oneMinute)
                        Text(languageManager.t("dashboard.window_5m")).tag(NetworkQualityWindow.fiveMinutes)
                        Text(languageManager.t("dashboard.window_1h")).tag(NetworkQualityWindow.oneHour)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView(languageManager.t("monitor.no_hosts"), systemImage: "network", description: Text(languageManager.t("monitor.add_host_hint")))
            } else {
                StatisticsContentView(host: selectedHost, window: selectedWindow, viewModel: viewModel)
            }
        }
    }
}

struct StatisticsContentView: View {
    let host: HostConfig?
    let window: NetworkQualityWindow
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    private var aggregatedStats: AggregatedStats {
        if let singleHost = host {
            let stats = viewModel.hostStats[singleHost.id]
            return AggregatedStats(
                totalPings: stats?.totalPings ?? 0,
                successfulPings: stats?.successfulPings ?? 0,
                failedPings: stats?.failedPings ?? 0,
                totalBytesSent: stats?.totalBytesSent ?? 0,
                totalBytesReceived: stats?.totalBytesReceived ?? 0,
                minLatency: stats?.minLatency,
                maxLatency: stats?.maxLatency,
                avgLatency: stats?.avgLatency ?? 0,
                latencyHistory: stats?.latencyHistory ?? [],
                startTime: stats?.startTime ?? Date(),
                isAggregated: false,
                hostCount: 1
            )
        }

        var totalPings = 0
        var successfulPings = 0
        var failedPings = 0
        var totalBytesSent: Int64 = 0
        var totalBytesReceived: Int64 = 0
        var minLatency: Double?
        var maxLatency: Double?
        var totalAvgLatency: Double = 0
        var allLatencyHistory: [LatencyPoint] = []
        var earliestStartTime = Date()
        var hostCount = 0

        for (_, stats) in viewModel.hostStats {
            totalPings += stats.totalPings
            successfulPings += stats.successfulPings
            failedPings += stats.failedPings
            totalBytesSent += stats.totalBytesSent
            totalBytesReceived += stats.totalBytesReceived

            if let hostMinLatency = stats.minLatency {
                minLatency = minLatency == nil ? hostMinLatency : Swift.min(minLatency!, hostMinLatency)
            }
            if let hostMaxLatency = stats.maxLatency {
                maxLatency = maxLatency == nil ? hostMaxLatency : Swift.max(maxLatency!, hostMaxLatency)
            }

            totalAvgLatency += stats.avgLatency
            allLatencyHistory.append(contentsOf: stats.latencyHistory)

            if stats.startTime < earliestStartTime {
                earliestStartTime = stats.startTime
            }

            hostCount += 1
        }

        allLatencyHistory.sort { $0.timestamp < $1.timestamp }
        if allLatencyHistory.count > 100 {
            allLatencyHistory = Array(allLatencyHistory.suffix(100))
        }

        return AggregatedStats(
            totalPings: totalPings,
            successfulPings: successfulPings,
            failedPings: failedPings,
            totalBytesSent: totalBytesSent,
            totalBytesReceived: totalBytesReceived,
            minLatency: minLatency,
            maxLatency: maxLatency,
            avgLatency: hostCount > 0 ? totalAvgLatency / Double(hostCount) : 0,
            latencyHistory: allLatencyHistory,
            startTime: earliestStartTime,
            isAggregated: true,
            hostCount: hostCount
        )
    }

    private var hostSnapshot: HostQualitySnapshot? {
        host.map { viewModel.qualitySnapshot(for: $0, window: window) }
    }

    private var globalSnapshot: GlobalQualitySnapshot {
        viewModel.globalQualitySnapshot(window: window)
    }

    private var score: Int {
        hostSnapshot?.score ?? globalSnapshot.score
    }

    private var dimensions: QualityDimensionScores {
        hostSnapshot?.dimensions ?? globalSnapshot.dimensions
    }

    private var p95Latency: Double? {
        hostSnapshot?.p95Latency ?? globalSnapshot.averageP95Latency
    }

    private var packetLoss: Double {
        hostSnapshot?.packetLoss ?? globalSnapshot.averagePacketLoss
    }

    private var jitter: Double {
        hostSnapshot?.jitter ?? globalSnapshot.averageJitter
    }

    private var currentPath: ProbePathKind {
        hostSnapshot?.pathKind ?? .unknown
    }

    private var pathFlaps: Int {
        hostSnapshot?.pathFlapCount ?? globalSnapshot.worstHosts.reduce(0) { $0 + $1.pathFlapCount }
    }

    private var consecutiveFailures: Int {
        hostSnapshot?.consecutiveFailures ?? globalSnapshot.worstHosts.map(\.consecutiveFailures).max() ?? 0
    }

    private var trendPoints: [QualityTrendPoint] {
        if let host {
            return viewModel.qualityTrend(for: host, window: window)
        }
        return viewModel.qualityTrend(window: window)
    }

    private var recentEvents: [NetworkQualityEvent] {
        viewModel.recentQualityEvents(for: host?.id, limit: 10)
    }

    private var targetName: String {
        host?.name ?? languageManager.t("stats.all_hosts")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    StatsQualityHeroCard(
                        targetName: targetName,
                        window: window,
                        score: score,
                        p95Latency: p95Latency,
                        packetLoss: packetLoss,
                        jitter: jitter,
                        hostCount: host == nil ? globalSnapshot.hostCount : 1,
                        path: currentPath
                    )

                    StatsDimensionBreakdownCard(dimensions: dimensions)
                }

                HStack(alignment: .top, spacing: 18) {
                    StatsQualityTrendCard(
                        trendPoints: trendPoints,
                        score: score,
                        packetLoss: packetLoss
                    )
                    StatsEventTimelineCard(events: recentEvents)
                }

                StatsDimensionStandardsCard()

                HStack(alignment: .top, spacing: 18) {
                    StatsRawMetricsCard(
                        stats: aggregatedStats,
                        score: score,
                        p95Latency: p95Latency,
                        jitter: jitter,
                        packetLoss: packetLoss,
                        consecutiveFailures: consecutiveFailures,
                        pathFlaps: pathFlaps,
                        currentPath: currentPath
                    )

                    StatsWorstHostsCard(
                        snapshots: host == nil ? globalSnapshot.worstHosts : hostSnapshot.map { [$0] } ?? []
                    )
                }

                HStack {
                    if let singleHost = host {
                        Button(languageManager.t("stats.export_current")) {
                            viewModel.exportStats(for: singleHost.id)
                        }
                        .buttonStyle(.bordered)

                        Button(languageManager.t("stats.reset_current")) {
                            viewModel.resetStats(for: singleHost.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(languageManager.t("stats.export_all")) {
                        viewModel.exportAllStats()
                    }
                    .buttonStyle(.bordered)

                    Button(languageManager.t("stats.reset_all")) {
                        viewModel.resetAllStats()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }
}

struct AggregatedStats {
    var totalPings: Int
    var successfulPings: Int
    var failedPings: Int
    var totalBytesSent: Int64
    var totalBytesReceived: Int64
    var minLatency: Double?
    var maxLatency: Double?
    var avgLatency: Double
    var latencyHistory: [LatencyPoint]
    var startTime: Date
    var isAggregated: Bool
    var hostCount: Int
    
    var packetLossRate: Double {
        guard totalPings > 0 else { return 0 }
        return Double(failedPings) / Double(totalPings) * 100
    }
    
    var successRate: Double {
        guard totalPings > 0 else { return 0 }
        return Double(successfulPings) / Double(totalPings) * 100
    }
    
    var totalTraffic: String {
        let total = totalBytesSent + totalBytesReceived
        return formatBytes(total)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct StatsQualityHeroCard: View {
    let targetName: String
    let window: NetworkQualityWindow
    let score: Int
    let p95Latency: Double?
    let packetLoss: Double
    let jitter: Double
    let hostCount: Int
    let path: ProbePathKind
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("stats.quality_assessment"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(targetName)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text(windowLabel(window))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.Colors.accentBlue.opacity(0.12))
                        .cornerRadius(999)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(score))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gradeText(score))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(scoreColor(score))
                        Text(languageManager.t("stats.current_score_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                HStack(spacing: 12) {
                    compactStat(title: languageManager.t("dashboard.p95_latency"), value: p95Latency.map { String(format: "%.0f ms", $0) } ?? "—", color: Theme.Colors.accentBlue)
                    compactStat(title: languageManager.t("stats.loss_rate"), value: String(format: "%.1f%%", packetLoss), color: packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                    compactStat(title: languageManager.t("host_detail.jitter"), value: String(format: "%.1f ms", jitter), color: Theme.Colors.accentOrange)
                }

                HStack(spacing: 12) {
                    compactStat(title: languageManager.t("stats.current_path"), value: pathLabel(path), color: pathColor(path))
                    compactStat(title: languageManager.t("dashboard.hosts_count"), value: "\(hostCount)", color: Theme.Colors.accentPurple)
                    compactStat(title: languageManager.t("stats.window"), value: windowLabel(window), color: Theme.Colors.textPrimary)
                }
            }
        }
    }

    private func compactStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.cardBackground.opacity(0.55))
        .cornerRadius(10)
    }

    private func gradeText(_ score: Int) -> String {
        switch score {
        case 90...: return languageManager.t("stats.grade.excellent")
        case 75..<90: return languageManager.t("stats.grade.good")
        case 60..<75: return languageManager.t("stats.grade.fair")
        case 40..<60: return languageManager.t("stats.grade.poor")
        default: return languageManager.t("stats.grade.critical")
        }
    }
}

private struct StatsDimensionBreakdownCard: View {
    let dimensions: QualityDimensionScores
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(languageManager.t("stats.dimension_scores"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(dimensions.average)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreColor(dimensions.average))
                }

                dimensionRow(title: languageManager.t("stats.dimension.latency"), value: dimensions.latency, color: Theme.Colors.accentBlue, weight: "30%")
                dimensionRow(title: languageManager.t("stats.dimension.stability"), value: dimensions.stability, color: Theme.Colors.accentGreen, weight: "30%")
                dimensionRow(title: languageManager.t("stats.dimension.path"), value: dimensions.path, color: Theme.Colors.accentOrange, weight: "15%")
                dimensionRow(title: languageManager.t("stats.dimension.bandwidth"), value: dimensions.bandwidth, color: Theme.Colors.accentPurple, weight: "10%")
                dimensionRow(title: languageManager.t("stats.dimension.resolution"), value: dimensions.resolution, color: Theme.Colors.accentCyan, weight: "5%")
                dimensionRow(title: languageManager.t("stats.dimension.overlay"), value: dimensions.overlay, color: Theme.Colors.accentRed, weight: "10%")
            }
        }
    }

    private func dimensionRow(title: String, value: Int, color: Color, weight: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(weight)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("\(value)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.cardBackground)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(6, geo.size.width * CGFloat(value) / 100))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct StatsQualityTrendCard: View {
    let trendPoints: [QualityTrendPoint]
    let score: Int
    let packetLoss: Double
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(languageManager.t("stats.quality_trend"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(trendPoints.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                if trendPoints.isEmpty {
                    Text(languageManager.t("dashboard.no_data"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    Chart {
                        ForEach(trendPoints) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Score", point.score)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(scoreColor(Int(point.score)))
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Score", point.score)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.Colors.accentBlue.opacity(0.24), Theme.Colors.accentBlue.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date.formatted(.dateTime.hour().minute()))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel {
                                if let score = value.as(Double.self) {
                                    Text("\(Int(score))")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(height: 190)
                }

                HStack(spacing: 12) {
                    trendBadge(title: languageManager.t("dashboard.quality_score"), value: "\(score)", color: scoreColor(score))
                    trendBadge(title: languageManager.t("stats.loss_rate"), value: String(format: "%.1f%%", packetLoss), color: packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                }
            }
        }
    }

    private func trendBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatsEventTimelineCard: View {
    let events: [NetworkQualityEvent]
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(languageManager.t("stats.recent_anomalies"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                if events.isEmpty {
                    Text(languageManager.t("stats.no_events"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(eventColor(event.severity))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(event.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                        Spacer()
                                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }

                                    if let hostName = event.hostName {
                                        Text(hostName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(eventColor(event.severity))
                                    }

                                    Text(event.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                            .background(Theme.Colors.cardBackground.opacity(0.65))
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }

    private func eventColor(_ severity: QualityEventSeverity) -> Color {
        switch severity {
        case .info:
            return Theme.Colors.accentBlue
        case .warning:
            return Theme.Colors.accentOrange
        case .critical:
            return Theme.Colors.accentRed
        }
    }
}

private struct StatsDimensionStandardsCard: View {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(languageManager.t("stats.scoring_standard"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text(languageManager.t("stats.scoring_hint"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                VStack(spacing: 10) {
                    standardRow(
                        dimension: languageManager.t("stats.dimension.latency"),
                        weight: "30%",
                        signal: languageManager.t("stats.standard.latency.signal"),
                        standard: languageManager.t("stats.standard.latency.rule"),
                        accent: Theme.Colors.accentBlue
                    )
                    standardRow(
                        dimension: languageManager.t("stats.dimension.stability"),
                        weight: "30%",
                        signal: languageManager.t("stats.standard.stability.signal"),
                        standard: languageManager.t("stats.standard.stability.rule"),
                        accent: Theme.Colors.accentGreen
                    )
                    standardRow(
                        dimension: languageManager.t("stats.dimension.path"),
                        weight: "15%",
                        signal: languageManager.t("stats.standard.path.signal"),
                        standard: languageManager.t("stats.standard.path.rule"),
                        accent: Theme.Colors.accentOrange
                    )
                    standardRow(
                        dimension: languageManager.t("stats.dimension.bandwidth"),
                        weight: "10%",
                        signal: languageManager.t("stats.standard.bandwidth.signal"),
                        standard: languageManager.t("stats.standard.bandwidth.rule"),
                        accent: Theme.Colors.accentPurple
                    )
                    standardRow(
                        dimension: languageManager.t("stats.dimension.resolution"),
                        weight: "5%",
                        signal: languageManager.t("stats.standard.resolution.signal"),
                        standard: languageManager.t("stats.standard.resolution.rule"),
                        accent: Theme.Colors.accentCyan
                    )
                    standardRow(
                        dimension: languageManager.t("stats.dimension.overlay"),
                        weight: "10%",
                        signal: languageManager.t("stats.standard.overlay.signal"),
                        standard: languageManager.t("stats.standard.overlay.rule"),
                        accent: Theme.Colors.accentRed
                    )
                }
            }
        }
    }

    private func standardRow(dimension: String, weight: String, signal: String, standard: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dimension)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(weight)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(signal)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(standard)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.Colors.cardBackground.opacity(0.55))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct StatsRawMetricsCard: View {
    let stats: AggregatedStats
    let score: Int
    let p95Latency: Double?
    let jitter: Double
    let packetLoss: Double
    let consecutiveFailures: Int
    let pathFlaps: Int
    let currentPath: ProbePathKind
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(languageManager.t("stats.raw_metrics"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    metricCard(label: languageManager.t("dashboard.quality_score"), value: "\(score)", color: scoreColor(score))
                    metricCard(label: languageManager.t("dashboard.p95_latency"), value: p95Latency.map { String(format: "%.0fms", $0) } ?? "—", color: Theme.Colors.accentBlue)
                    metricCard(label: languageManager.t("host_detail.jitter"), value: String(format: "%.1fms", jitter), color: Theme.Colors.accentOrange)
                    metricCard(label: languageManager.t("stats.success_rate"), value: String(format: "%.1f%%", stats.successRate), color: Theme.Colors.accentGreen)
                    metricCard(label: languageManager.t("stats.loss_rate"), value: String(format: "%.1f%%", packetLoss), color: packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                    metricCard(label: languageManager.t("stats.availability"), value: String(format: "%.1f%%", max(0, 100 - packetLoss)), color: Theme.Colors.accentGreen)
                    metricCard(label: languageManager.t("stats.current_path"), value: pathLabel(currentPath), color: pathColor(currentPath))
                    metricCard(label: languageManager.t("stats.path_flaps"), value: "\(pathFlaps)", color: pathFlaps > 1 ? Theme.Colors.accentOrange : Theme.Colors.textPrimary)
                    metricCard(label: languageManager.t("stats.consecutive_failures"), value: "\(consecutiveFailures)", color: consecutiveFailures >= 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                    metricCard(label: languageManager.t("stats.requests"), value: "\(stats.totalPings)", color: Theme.Colors.textPrimary)
                    metricCard(label: languageManager.t("stats.avg_latency"), value: String(format: "%.1fms", stats.avgLatency), color: Theme.Colors.accentPurple)
                    metricCard(label: languageManager.t("stats.traffic"), value: stats.totalTraffic, color: Theme.Colors.accentCyan)
                }
            }
        }
    }

    private func metricCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.cardBackground.opacity(0.55))
        .cornerRadius(10)
    }
}

private struct StatsWorstHostsCard: View {
    let snapshots: [HostQualitySnapshot]
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        statsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(languageManager.t("stats.worst_hosts"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                if snapshots.isEmpty {
                    Text(languageManager.t("dashboard.no_data"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    VStack(spacing: 10) {
                        ForEach(snapshots) { snapshot in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(snapshot.hostName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(pathLabel(snapshot.pathKind))
                                        .font(.system(size: 10))
                                        .foregroundStyle(pathColor(snapshot.pathKind))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(snapshot.score)")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(scoreColor(snapshot.score))
                                    Text(snapshot.p95Latency.map { String(format: "P95 %.0fms", $0) } ?? "P95 —")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .padding(10)
                            .background(Theme.Colors.cardBackground.opacity(0.55))
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }
}

private func statsPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
}

@MainActor
private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 90...: return Theme.Colors.accentGreen
    case 75..<90: return Theme.Colors.accentBlue
    case 60..<75: return Theme.Colors.accentOrange
    case 40..<60: return Color.orange
    default: return Theme.Colors.accentRed
    }
}

@MainActor
private func pathLabel(_ path: ProbePathKind) -> String {
    let languageManager = LanguageManager.shared
    switch path {
    case .direct:
        return languageManager.t("diagnostics.path.direct")
    case .relay:
        return languageManager.t("diagnostics.path.relay")
    case .unknown:
        return "—"
    }
}

@MainActor
private func pathColor(_ path: ProbePathKind) -> Color {
    switch path {
    case .direct:
        return Theme.Colors.accentGreen
    case .relay:
        return Theme.Colors.accentOrange
    case .unknown:
        return Theme.Colors.textTertiary
    }
}

@MainActor
private func windowLabel(_ window: NetworkQualityWindow) -> String {
    let languageManager = LanguageManager.shared
    switch window {
    case .oneMinute:
        return languageManager.t("dashboard.window_1m")
    case .fiveMinutes:
        return languageManager.t("dashboard.window_5m")
    case .oneHour:
        return languageManager.t("dashboard.window_1h")
    }
}

// MARK: - 监控 Tab
struct MonitorTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var editingHost: HostConfig?
    @State private var selectedHost: HostConfig?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostCommand = ""
    @State private var newHostRules: [DisplayRule] = []
    @State private var newHostProbeMode: HostProbeMode = .icmp
    @State private var newHostTCPPort = 443
    @State private var showingAddHost = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    Text("\(languageManager.t("monitor.title")) (\(viewModel.hosts.count))")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddHost = true
                    } label: {
                        Label(languageManager.t("monitor.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                if viewModel.hosts.isEmpty {
                    ContentUnavailableView(languageManager.t("monitor.no_hosts"), systemImage: "network", description: Text(languageManager.t("monitor.add_host_hint")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // Insert Quick Access Services Ribbon here
                        QuickAccessServicesRibbon(viewModel: viewModel)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 280, maximum: .infinity), spacing: 12)
                        ], spacing: 12) {
                            ForEach(viewModel.hosts) { host in
                                EditableHostCard(
                                    host: host,
                                    viewModel: viewModel,
                                    onEdit: {
                                        editingHost = host
                                        newHostName = host.name
                                        newHostAddress = host.address
                                        newHostCommand = host.command
                                        newHostRules = host.displayRules
                                        newHostProbeMode = host.probeMode
                                        newHostTCPPort = host.tcpPort
                                    },
                                    onDelete: {
                                        if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                                            viewModel.removeHost(at: index)
                                        }
                                    }
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedHost = host
                                    }
                                }
                                .onDrag {
                                    NSItemProvider(object: host.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: HostDropDelegate(item: host, viewModel: viewModel))
                            }
                        }
                        .padding()
                    }
                }
            }
            .blur(radius: selectedHost != nil ? 2 : 0)
            
            // Detail Overlay
            if let host = selectedHost {
                Color.black.opacity(0.001) // Invisible backdrop to catch taps if needed, or just let view take full space
                    .onTapGesture {
                        withAnimation { selectedHost = nil }
                    }
                
                HostDetailView(
                    viewModel: viewModel,
                    host: host,
                    onClose: {
                        withAnimation { selectedHost = nil }
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showingAddHost) {
            HostEditorSheet(
                isPresented: $showingAddHost,
                title: languageManager.t("editor.add_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    viewModel.addHost(
                        name: newHostName,
                        address: newHostAddress,
                        command: newHostCommand,
                        displayRules: newHostRules.isEmpty ? nil : newHostRules,
                        probeMode: newHostProbeMode,
                        tcpPort: newHostTCPPort
                    )
                    resetForm()
                }
            )
        }
        .sheet(item: $editingHost) { host in
            HostEditorSheet(
                isPresented: Binding(
                    get: { editingHost != nil },
                    set: { if !$0 { editingHost = nil } }
                ),
                title: languageManager.t("editor.edit_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                        viewModel.updateHost(
                            at: index,
                            name: trimmedName,
                            address: trimmedAddress,
                            command: trimmedCommand,
                            displayRules: newHostRules,
                            probeMode: newHostProbeMode,
                            tcpPort: newHostTCPPort
                        )
                    }
                    editingHost = nil
                }
            )
        }
    }
    
    private func resetForm() {
        newHostName = ""
        newHostAddress = ""
        newHostCommand = ""
        newHostRules = []
        newHostProbeMode = .icmp
        newHostTCPPort = 443
    }
}

// MARK: - Quick Access Services Ribbon
struct QuickAccessServicesRibbon: View {
    @ObservedObject var viewModel: PingMonitorViewModel

    private var hostGroups: [(host: HostConfig, shortcuts: [ServiceShortcut])] {
        viewModel.hosts.compactMap { host in
            guard !host.serviceShortcuts.isEmpty else { return nil }
            return (host: host, shortcuts: host.serviceShortcuts)
        }
    }

    private var totalShortcutCount: Int {
        hostGroups.reduce(0) { $0 + $1.shortcuts.count }
    }
    
    var body: some View {
        if !hostGroups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Label
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.accentOrange)
                        Text(LanguageManager.shared.t("monitor.quick_access"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 14)

                    // Host groups
                    ForEach(hostGroups, id: \.host.id) { group in
                        HStack(spacing: 0) {
                            // Separator
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 12)

                            // Status dot + host name
                            Circle()
                                .fill(hostStatusColor(group.host))
                                .frame(width: 6, height: 6)
                                .shadow(color: hostStatusColor(group.host).opacity(0.6), radius: 2)
                            Text(group.host.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                                .padding(.leading, 5)

                            // Service icon buttons
                            HStack(spacing: 3) {
                                ForEach(group.shortcuts) { shortcut in
                                    Button {
                                        openService(shortcut, host: group.host)
                                    } label: {
                                        Image(systemName: shortcut.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(serviceColor(for: shortcut.type))
                                            .frame(width: 28, height: 28)
                                            .background(serviceColor(for: shortcut.type).opacity(0.10))
                                            .cornerRadius(7)
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(shortcut.name)  \(serviceTargetPreview(shortcut))")
                                    .contextMenu {
                                        Button {
                                            openService(shortcut, host: group.host)
                                        } label: {
                                            Label(LanguageManager.shared.t("monitor.quick_access_open"), systemImage: "arrow.up.forward.app")
                                        }
                                        Button {
                                            copyServiceTarget(shortcut, host: group.host)
                                        } label: {
                                            Label(LanguageManager.shared.t("monitor.quick_access_copy"), systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }

                    Spacer(minLength: 14)
                }
                .frame(height: 44)
            }
            .background(Theme.Colors.cardBackground.opacity(0.42))
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private func typePill(_ type: ServiceShortcut.ServiceType) -> some View {
        Text(shortcutTypeLabel(type))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(serviceColor(for: type))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(serviceColor(for: type).opacity(0.12))
            .cornerRadius(999)
    }
    
    private func serviceColor(for type: ServiceShortcut.ServiceType) -> Color {
        switch type {
        case .web: return Theme.Colors.accentBlue
        case .ssh: return Theme.Colors.accentGreen
        case .custom: return Theme.Colors.accentOrange
        }
    }

    private func shortcutTypeLabel(_ type: ServiceShortcut.ServiceType) -> String {
        switch type {
        case .web: return "WEB"
        case .ssh: return "SSH"
        case .custom: return "CMD"
        }
    }

    private func serviceTargetPreview(_ shortcut: ServiceShortcut) -> String {
        switch shortcut.type {
        case .web, .custom:
            return shortcut.url
        case .ssh:
            return shortcut.sshCommand
        }
    }

    private func copyServiceTarget(_ shortcut: ServiceShortcut, host: HostConfig) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(serviceTargetPreview(shortcut), forType: .string)
        LogManager.shared.info("Copied service target: \(shortcut.name)", host: host.name)
    }

    private func hostStatusColor(_ host: HostConfig) -> Color {
        if host.isPaused { return Theme.Colors.textTertiary }
        if host.isChecking { return Theme.Colors.accentBlue }
        if !host.isReachable { return Theme.Colors.accentRed }
        if let latency = host.lastLatency {
            if latency < 80 { return Theme.Colors.accentGreen }
            if latency < 180 { return Theme.Colors.accentOrange }
            return Theme.Colors.accentRed
        }
        return Theme.Colors.textSecondary
    }
    
    private func openService(_ shortcut: ServiceShortcut, host: HostConfig) {
        switch shortcut.type {
        case .web:
            if let url = URL(string: shortcut.url) {
                NSWorkspace.shared.open(url)
            }
        case .ssh:
            let cmdFile = "/tmp/pm_ssh_\(UUID().uuidString.prefix(8)).command"
            let scriptContent = "#!/bin/bash\nrm -f \"\(cmdFile)\"\n\(shortcut.sshCommand)\n"
            do {
                try scriptContent.write(toFile: cmdFile, atomically: true, encoding: .utf8)
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", cmdFile]
                try chmod.run()
                chmod.waitUntilExit()
                NSWorkspace.shared.open(URL(fileURLWithPath: cmdFile))
            } catch {
                LogManager.shared.error("Failed to create SSH script: \(error)")
            }
        case .custom:
            if let url = URL(string: shortcut.url) {
                NSWorkspace.shared.open(url)
            }
        }
        LogManager.shared.info("Opened service: \(shortcut.name)", host: host.name)
    }
}

// MARK: - Mini Sparkline
struct MiniSparkline: View {
    let points: [LatencyPoint]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = points.map { $0.latency }.min() ?? 0
            let maxV = max(points.map { $0.latency }.max() ?? 1, minV + 1)
            
            Path { path in
                for (i, pt) in points.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(points.count - 1, 1))
                    let y = h - (CGFloat(pt.latency - minV) / CGFloat(maxV - minV)) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else {
                        let prev = points[i - 1]
                        let px = w * CGFloat(i - 1) / CGFloat(max(points.count - 1, 1))
                        let py = h - (CGFloat(prev.latency - minV) / CGFloat(maxV - minV)) * h
                        let mx = (px + x) / 2
                        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: mx, y: py), control2: CGPoint(x: mx, y: y))
                    }
                }
            }
            .stroke(color.opacity(0.5), lineWidth: 1.5)
            
            // Fill under
            Path { path in
                for (i, pt) in points.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(points.count - 1, 1))
                    let y = h - (CGFloat(pt.latency - minV) / CGFloat(maxV - minV)) * h
                    if i == 0 {
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        let prev = points[i - 1]
                        let px = w * CGFloat(i - 1) / CGFloat(max(points.count - 1, 1))
                        let py = h - (CGFloat(prev.latency - minV) / CGFloat(maxV - minV)) * h
                        let mx = (px + x) / 2
                        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: mx, y: py), control2: CGPoint(x: mx, y: y))
                    }
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.15), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - 主机管理 Tab
struct HostManagementTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedSection = 0
    @ObservedObject private var languageManager = LanguageManager.shared
    @Namespace private var animation
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Segmented Control
            HStack(spacing: 0) {
                customTabButton(title: "\(languageManager.t("host.manage.section.saved")) (\(viewModel.hosts.count))", section: 0)
                customTabButton(title: "\(languageManager.t("host.manage.section.presets")) (\(viewModel.presets.count))", section: 1)
            }
            .padding(4)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(8)
            .padding()
            
            if selectedSection == 0 {
                HostsManagementView(viewModel: viewModel)
            } else {
                PresetsManagementView(viewModel: viewModel)
            }
        }
    }
    
    @ViewBuilder
    private func customTabButton(title: String, section: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSection = section
            }
        } label: {
            Text(title)
                .font(Theme.Fonts.body(12))
                .fontWeight(selectedSection == section ? .medium : .regular)
                .foregroundStyle(selectedSection == section ? Color.white : Theme.Colors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.Colors.accentBlue)
                                .matchedGeometryEffect(id: "HostManageTabBackground", in: animation)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HostsManagementView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var showingAddHost = false
    @State private var editingHost: HostConfig?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostCommand = ""
    @State private var newHostRules: [DisplayRule] = []
    @State private var newHostProbeMode: HostProbeMode = .icmp
    @State private var newHostTCPPort = 443
    @State private var hoveredHostId: UUID?
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageManager.t("sidebar.hosts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddHost = true
                } label: {
                    Label(languageManager.t("host.manage.add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_hosts"), systemImage: "server.rack", description: Text(languageManager.t("host.manage.add_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(viewModel.hosts) { host in
                            HostManagementCard(
                                host: host,
                                isHovered: hoveredHostId == host.id,
                                onEdit: {
                                    editingHost = host
                                    newHostName = host.name
                                    newHostAddress = host.address
                                    newHostCommand = host.command
                                    newHostRules = host.displayRules
                                    newHostProbeMode = host.probeMode
                                    newHostTCPPort = host.tcpPort
                                },
                                onDelete: {
                                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                                        viewModel.removeHost(at: index)
                                    }
                                }
                            )
                            .onHover { isHovered in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    hoveredHostId = isHovered ? host.id : nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .sheet(isPresented: $showingAddHost) {
            HostEditorSheet(
                isPresented: $showingAddHost,
                title: languageManager.t("editor.add_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !trimmedName.isEmpty && !trimmedAddress.isEmpty {
                        viewModel.addHost(
                            name: trimmedName,
                            address: trimmedAddress,
                            command: trimmedCommand,
                            displayRules: newHostRules.isEmpty ? nil : newHostRules,
                            probeMode: newHostProbeMode,
                            tcpPort: newHostTCPPort
                        )
                        resetForm()
                    }
                }
            )
        }
        .sheet(item: $editingHost) { host in
            HostEditorSheet(
                isPresented: Binding(
                    get: { editingHost != nil },
                    set: { if !$0 { editingHost = nil } }
                ),
                title: languageManager.t("editor.edit_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !trimmedName.isEmpty && !trimmedAddress.isEmpty {
                        if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                            viewModel.updateHost(
                                at: index,
                                name: trimmedName,
                                address: trimmedAddress,
                                command: trimmedCommand,
                                displayRules: newHostRules,
                                probeMode: newHostProbeMode,
                                tcpPort: newHostTCPPort
                            )
                        }
                    }
                    editingHost = nil
                }
            )
        }
    }
    
    private func resetForm() {
        newHostName = ""
        newHostAddress = ""
        newHostCommand = ""
        newHostRules = [
            DisplayRule(condition: "less", threshold: 50, label: "Direct", enabled: true),
            DisplayRule(condition: "greater", threshold: 100, label: "Relay", enabled: true)
        ]
        newHostProbeMode = .icmp
        newHostTCPPort = 443
    }
}

struct HostManagementCard: View {
    let host: HostConfig
    let isHovered: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: name + actions
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text(host.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                
                HStack(spacing: 6) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("menu.edit"))
                    
                    Button { onDelete() } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("menu.delete"))
                }
                .opacity(isHovered ? 1 : 0.3)
            }
            
            // Address
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(host.address)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Display rules
            if !host.displayRules.filter({ $0.enabled }).isEmpty {
                HStack(spacing: 4) {
                    ForEach(host.displayRules.filter { $0.enabled }.prefix(3)) { rule in
                        Text("\(rule.condition == "less" ? "<" : ">")\(Int(rule.threshold))ms→\(rule.label)")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(rule.condition == "less" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            )
                            .foregroundStyle(rule.condition == "less" ? .green : .orange)
                    }
                }
            }

            HStack(spacing: 4) {
                Image(systemName: host.probeMode == .tcp ? "cable.connector" : "waveform.path.ecg")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(host.probeMode == .tcp ? "TCP \(host.tcpPort)" : "ICMP")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            // Custom command
            if !host.command.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.7))
                    Text(host.command)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isHovered ? Color.blue.opacity(0.15) : Color.gray.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .contextMenu {
            Button { onEdit() } label: { Label(languageManager.t("menu.edit"), systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label(languageManager.t("menu.delete"), systemImage: "trash") }
        }
    }
}

// MARK: - Presets Management View
struct PresetsManagementView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var showingAddPreset = false
    @State private var editingPreset: HostPreset?
    @State private var newPresetName = ""
    @State private var newPresetAddress = ""
    @State private var newPresetCommand = ""
    @State private var hoveredPresetId: UUID?
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageManager.t("host.manage.quick_add"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddPreset = true
                } label: {
                    Label(languageManager.t("host.manage.add_preset"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            if viewModel.presets.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_presets"), systemImage: "bookmark", description: Text(languageManager.t("host.manage.add_preset_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(viewModel.presets) { preset in
                            PresetManagementCard(
                                preset: preset,
                                isHovered: hoveredPresetId == preset.id,
                                onAdd: { viewModel.addHostFromPreset(preset) },
                                onEdit: {
                                    editingPreset = preset
                                    newPresetName = preset.name
                                    newPresetAddress = preset.address
                                    newPresetCommand = preset.command
                                },
                                onDelete: {
                                    if let index = viewModel.presets.firstIndex(where: { $0.id == preset.id }) {
                                        viewModel.removePreset(at: index)
                                    }
                                }
                            )
                            .onHover { isHovered in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    hoveredPresetId = isHovered ? preset.id : nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .sheet(isPresented: $showingAddPreset) {
            PresetEditorSheet(
                isPresented: $showingAddPreset,
                title: languageManager.t("editor.add_preset"),
                name: $newPresetName,
                address: $newPresetAddress,
                command: $newPresetCommand,
                onSave: {
                    viewModel.addPreset(name: newPresetName, address: newPresetAddress, command: newPresetCommand)
                    resetForm()
                }
            )
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(
                isPresented: Binding(
                    get: { editingPreset != nil },
                    set: { if !$0 { editingPreset = nil } }
                ),
                title: languageManager.t("editor.edit_preset"),
                name: $newPresetName,
                address: $newPresetAddress,
                command: $newPresetCommand,
                onSave: {
                    if let index = viewModel.presets.firstIndex(where: { $0.id == preset.id }) {
                        viewModel.updatePreset(at: index, name: newPresetName, address: newPresetAddress, command: newPresetCommand)
                    }
                    editingPreset = nil
                }
            )
        }
    }
    
    private func resetForm() {
        newPresetName = ""
        newPresetAddress = ""
        newPresetCommand = ""
    }
}

struct PresetManagementCard: View {
    let preset: HostPreset
    let isHovered: Bool
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(preset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                
                Button { onAdd() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help(languageManager.t("menu.add_to_monitor"))
            }
            
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(preset.address)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            if !preset.command.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.7))
                    Text(preset.command)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Action buttons
            HStack(spacing: 8) {
                Spacer()
                Button { onEdit() } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Button { onDelete() } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovered ? 1 : 0.2)
        }
        .padding(14)
        .frame(height: 110, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isHovered ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .contextMenu {
            Button { onAdd() } label: { Label(languageManager.t("menu.add_to_monitor"), systemImage: "plus.circle") }
            Button { onEdit() } label: { Label(languageManager.t("menu.edit"), systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label(languageManager.t("menu.delete"), systemImage: "trash") }
        }
    }
}

// MARK: - Editor Sheets
struct HostEditorSheet: View {
    @Binding var isPresented: Bool
    let title: String
    @Binding var name: String
    @Binding var address: String
    @Binding var command: String
    @Binding var displayRules: [DisplayRule]
    @Binding var probeMode: HostProbeMode
    @Binding var tcpPort: Int
    let onSave: () -> Void
    @State private var showingAddRule = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            ScrollView {
                Form {
                    Section(languageManager.t("editor.section.basic")) {
                        TextField(languageManager.t("editor.name"), text: $name)
                        TextField(languageManager.t("editor.address"), text: $address)
                            .textContentType(.URL)

                        Picker("Probe", selection: $probeMode) {
                            Text("ICMP").tag(HostProbeMode.icmp)
                            Text("TCP").tag(HostProbeMode.tcp)
                        }
                        .pickerStyle(.segmented)

                        if probeMode == .tcp {
                            Stepper(value: $tcpPort, in: 1...65535) {
                                HStack {
                                    Text("TCP Port")
                                    Spacer()
                                    Text("\(tcpPort)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(languageManager.t("editor.command"), text: $command)
                            Text(languageManager.t("editor.command_hint"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Section(languageManager.t("editor.section.rules")) {
                        ForEach($displayRules) { $rule in
                            RuleEditorRow(rule: $rule, onDelete: {
                                if let index = displayRules.firstIndex(where: { $0.id == rule.id }) {
                                    displayRules.remove(at: index)
                                }
                            })
                        }
                        
                        Button {
                            showingAddRule = true
                        } label: {
                            Label(languageManager.t("editor.add_rule"), systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(languageManager.t("common.save")) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || address.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 500)
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(isPresented: $showingAddRule, rules: $displayRules)
        }
    }
}

struct RuleEditorRow: View {
    @Binding var rule: DisplayRule
    let onDelete: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Enable toggle + Delete
            HStack {
                Toggle(languageManager.t("editor.rule.enable"), isOn: $rule.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            
            // Row 2: Condition + Threshold + Label (properly spaced)
            HStack(spacing: 8) {
                // Condition picker
                Picker("", selection: $rule.condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                
                // Threshold
                HStack(spacing: 4) {
                    TextField("", value: $rule.threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 45)
                    Text("ms")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer(minLength: 4)
                
                // Static Label "显示文本"
                Text(languageManager.t("editor.rule.label"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                // Label TextField
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $rule.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            .frame(height: 28) // Force consistent height to fix vertical alignment
        }
        .padding(.vertical, 8)
    }
}

struct AddRuleSheet: View {
    @Binding var isPresented: Bool
    @Binding var rules: [DisplayRule]
    @State private var condition = "less"
    @State private var threshold: Double = 100
    @State private var label = ""
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text(languageManager.t("editor.add_rule"))
                .font(.headline)
            
            Form {
                Picker(languageManager.t("editor.rule.condition"), selection: $condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                
                HStack {
                    Text(languageManager.t("editor.rule.threshold"))
                    Spacer()
                    TextField("ms", value: $threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $label)
            }
            .formStyle(.grouped)
            
            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(languageManager.t("common.add")) {
                    let finalLabel = label.isEmpty ? "\(condition == "less" ? "<" : ">") \(Int(threshold))ms" : label
                    rules.append(DisplayRule(condition: condition, threshold: threshold, label: finalLabel, enabled: true))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct PresetEditorSheet: View {
    @Binding var isPresented: Bool
    let title: String
    @Binding var name: String
    @Binding var address: String
    @Binding var command: String
    let onSave: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)

            Form {
                TextField(languageManager.t("editor.name"), text: $name)
                TextField(languageManager.t("editor.address"), text: $address)
                    .textContentType(.URL)
                
                VStack(alignment: .leading, spacing: 4) {
                    TextField(languageManager.t("editor.command"), text: $command)
                    Text(languageManager.t("editor.command_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(languageManager.t("common.save")) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || address.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }
}

// MARK: - Logs Tab
struct LogsTab: View {
    @StateObject private var logManager = LogManager.shared
    @State private var selectedLevel: LogManager.LogLevel?
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var filteredLogs: [LogManager.LogEntry] {
        if let level = selectedLevel {
            return logManager.logs.filter { $0.level == level }
        }
        return logManager.logs
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(languageManager.t("logs.level"), selection: $selectedLevel) {
                    Text(languageManager.t("logs.level.all")).tag(nil as LogManager.LogLevel?)
                    ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                        Text(languageManager.t("logs.level.\(level.rawValue.lowercased())")).tag(level as LogManager.LogLevel?)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                
                Spacer()
                
                Button(action: {
                    logManager.clear()
                }) {
                    Label(languageManager.t("logs.clear"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                
                Button(action: {
                    if let url = logManager.exportToFile() {
                        exportURL = url
                        showingExportSheet = true
                    }
                }) {
                    Label(languageManager.t("logs.export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            List(filteredLogs.reversed()) { entry in
                LogRow(entry: entry)
                    .listRowSeparator(.visible)
            }
            .listStyle(.plain)
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: LogFileDocument(url: exportURL),
            contentType: .plainText,
            defaultFilename: "PingMonitor_Logs.txt"
        ) { result in
            if case .success = result {
                LogManager.shared.info("Log exported successfully")
            }
        }
    }
}

struct LogRow: View {
    let entry: LogManager.LogEntry
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
            
            HStack(alignment: .top, spacing: 12) {
                Text(entry.formattedTimestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 130, alignment: .leading)
                
                Text(languageManager.t("logs.level.\(entry.level.rawValue.lowercased())"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(levelColor)
                    .frame(width: 50, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 3) {
                    if let host = entry.host {
                        Text(host)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(entry.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct LogFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var url: URL?
    
    init(url: URL?) {
        self.url = url
    }
    
    init(configuration: ReadConfiguration) throws {
        self.url = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url,
              let data = try? Data(contentsOf: url) else {
            return FileWrapper(regularFileWithContents: Data())
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Settings Tab
struct SettingsTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - General
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.system"), icon: "gear")
                        
                        HStack {
                            Text(languageManager.t("settings.language"))
                            Spacer()
                            Picker("", selection: $languageManager.currentLanguage) {
                                Text("中文").tag(Language.zh)
                                Text("English").tag(Language.en)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: languageManager.currentLanguage) { _, newValue in
                                LogManager.shared.info("Language changed to \(newValue.rawValue)")
                                languageManager.languageString = newValue.rawValue
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.appearance"))
                            Spacer()
                            Picker("", selection: $viewModel.appAppearance) {
                                Text(languageManager.t("settings.appearance.light")).tag("light")
                                Text(languageManager.t("settings.appearance.system")).tag("system")
                                Text(languageManager.t("settings.appearance.dark")).tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.appAppearance) { _, newValue in
                                LogManager.shared.info("Appearance changed to \(newValue)")
                                viewModel.saveSettings()
                            }
                        }
                        
                        Divider()
                        
                        Toggle(languageManager.t("settings.auto_start"), isOn: $viewModel.autoStart)
                            .onChange(of: viewModel.autoStart) { _, newValue in
                                viewModel.toggleAutoStart(newValue)
                            }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.version"))
                            Spacer()
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .trailing)
                        }
                    }
                }
                
                // MARK: - Display (Status Bar & Widget)
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.status_bar"), icon: "menubar.rectangle")
                        
                        HStack {
                            Text(languageManager.t("settings.display_mode"))
                            Spacer()
                            Picker("", selection: $viewModel.statusBarDisplayMode) {
                                Text(languageManager.t("settings.display.average")).tag(StatusBarDisplayMode.average)
                                Text(languageManager.t("settings.display.worst")).tag(StatusBarDisplayMode.worst)
                                Text(languageManager.t("settings.display.best")).tag(StatusBarDisplayMode.best)
                                Text(languageManager.t("settings.display.first")).tag(StatusBarDisplayMode.first)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.statusBarDisplayMode) { _, newValue in
                                LogManager.shared.info("Display mode changed to \(newValue.rawValue)")
                                viewModel.saveSettings()
                            }
                        }
                        
                        Text(statusBarDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, -8)
                        
                        let activeMenuCount = [viewModel.showIconInMenu, viewModel.showLatencyInMenu, viewModel.showLabelsInMenu, viewModel.showSpeedInMenu].filter { $0 }.count
                        
                        Divider()
                        
                        HStack(spacing: 24) {
                            Toggle(languageManager.t("settings.show_icon"), isOn: $viewModel.showIconInMenu)
                                .disabled((viewModel.showIconInMenu && activeMenuCount <= 1) || (!viewModel.showIconInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showIconInMenu) { _, newValue in
                                    LogManager.shared.info("Show icon in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            
                            Toggle(languageManager.t("settings.show_latency"), isOn: $viewModel.showLatencyInMenu)
                                .disabled((viewModel.showLatencyInMenu && activeMenuCount <= 1) || (!viewModel.showLatencyInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showLatencyInMenu) { _, newValue in
                                    LogManager.shared.info("Show latency in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
    
                            Toggle(languageManager.t("settings.show_labels"), isOn: $viewModel.showLabelsInMenu)
                                .disabled((viewModel.showLabelsInMenu && activeMenuCount <= 1) || (!viewModel.showLabelsInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showLabelsInMenu) { _, newValue in
                                    LogManager.shared.info("Show labels in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            
                            Toggle(languageManager.t("settings.show_speed"), isOn: $viewModel.showSpeedInMenu)
                                .disabled((viewModel.showSpeedInMenu && activeMenuCount <= 1) || (!viewModel.showSpeedInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showSpeedInMenu) { _, newValue in
                                    LogManager.shared.info("Show speed in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
                        }
                        
                        if viewModel.showSpeedInMenu {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.speed_unit"))
                                Spacer()
                                Picker("", selection: $viewModel.speedUnit) {
                                    Text(languageManager.t("settings.speed_unit.auto")).tag("auto")
                                    Text("KB/s").tag("KB")
                                    Text("MB/s").tag("MB")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220, alignment: .trailing)
                                .onChange(of: viewModel.speedUnit) { _, newValue in
                                    LogManager.shared.info("Speed unit changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                Text(languageManager.t("settings.bar_width"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarWidth > 50 {
                                            viewModel.statusBarWidth -= 10
                                            viewModel.saveSettings()
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarWidth <= 50)
                                    
                                    Text("\(viewModel.statusBarWidth)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)
                                    
                                    Button {
                                        if viewModel.statusBarWidth < 250 {
                                            viewModel.statusBarWidth += 10
                                            viewModel.saveSettings()
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarWidth >= 250)
                                }
                                .frame(width: 220, alignment: .trailing)
                            }
                            Divider()
                            
                            HStack {
                                Text(languageManager.t("settings.font_size"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarFontSize > 6 {
                                            viewModel.statusBarFontSize -= 1
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "minus.circle").font(.system(size: 16)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarFontSize <= 6)
                                    
                                    Text("\(viewModel.statusBarFontSize)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)
                                    
                                    Button {
                                        if viewModel.statusBarFontSize < 18 {
                                            viewModel.statusBarFontSize += 1
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "plus.circle").font(.system(size: 16)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarFontSize >= 18)
                                }
                                .frame(width: 220, alignment: .trailing)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text(languageManager.t("settings.font_weight"))
                                Spacer()
                                Picker("", selection: $viewModel.statusBarFontWeight) {
                                    Text(languageManager.t("settings.font_weight.regular")).tag("regular")
                                    Text(languageManager.t("settings.font_weight.medium")).tag("medium")
                                    Text(languageManager.t("settings.font_weight.bold")).tag("bold")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220, alignment: .trailing)
                                .onChange(of: viewModel.statusBarFontWeight) { _, newValue in
                                    LogManager.shared.info("Status bar font weight changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.widget.mode"))
                            Spacer()
                            Picker("", selection: $viewModel.widgetDisplayMode) {
                                Text(languageManager.t("settings.widget.auto")).tag("auto")
                                Text(languageManager.t("settings.widget.specific")).tag("specific")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.widgetDisplayMode) { _, newValue in
                                LogManager.shared.info("Widget display mode changed to \(newValue)")
                                viewModel.syncToWidget()
                            }
                        }
                        
                        if viewModel.widgetDisplayMode == "specific" {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.widget.select_host"))
                                Spacer()
                                Picker("", selection: $viewModel.widgetSelectedHostId) {
                                    Text(languageManager.t("settings.widget.none")).tag("")
                                    ForEach(viewModel.hosts) { host in
                                        Text(host.name).tag(host.id.uuidString)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220, alignment: .trailing)
                                .onChange(of: viewModel.widgetSelectedHostId) { _, newValue in
                                    LogManager.shared.info("Widget host changed to \(newValue)")
                                    viewModel.syncToWidget()
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Monitor & Logs
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.monitor"), icon: "waveform.path.ecg")
                        
                        HStack {
                            Text(languageManager.t("settings.interval"))
                            Spacer()
                            Picker("", selection: $viewModel.pingInterval) {
                                Text(languageManager.t("settings.interval.3s")).tag(3.0)
                                Text(languageManager.t("settings.interval.5s")).tag(5.0)
                                Text(languageManager.t("settings.interval.10s")).tag(10.0)
                                Text(languageManager.t("settings.interval.15s")).tag(15.0)
                                Text(languageManager.t("settings.interval.30s")).tag(30.0)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.pingInterval) { _, newValue in
                                LogManager.shared.info("Ping interval changed to \(Int(newValue))s")
                                viewModel.saveSettings()
                                if viewModel.isRunning {
                                    viewModel.stopAll()
                                    viewModel.startAll()
                                }
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("logs.level"))
                            Spacer()
                            Picker("", selection: $viewModel.logLevel) {
                                ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                                    Text(languageManager.t("logs.level.\(level.rawValue.lowercased())")).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.logLevel) { _, newValue in
                                LogManager.shared.info("Log level changed to \(newValue.rawValue)")
                                viewModel.saveSettings()
                            }
                        }
                    }
                }
                
                // MARK: - Notifications
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.notify"), icon: "bell.badge.fill")
                        
                        Toggle(languageManager.t("settings.notify.enable"), isOn: $viewModel.notificationEnabled)
                            .onChange(of: viewModel.notificationEnabled) { _, newValue in
                                LogManager.shared.info("Notifications enabled: \(newValue)")
                                viewModel.saveSettings()
                            }
                        
                        if viewModel.notificationEnabled {
                            Divider()
                            
                            HStack {
                                Text(languageManager.t("settings.notify.type"))
                                Spacer()
                                Picker("", selection: $viewModel.notificationType) {
                                    Text(languageManager.t("settings.notify.system")).tag("system")
                                    Text(languageManager.t("settings.notify.bark")).tag("bark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220, alignment: .trailing)
                                .onChange(of: viewModel.notificationType) { _, newValue in
                                    LogManager.shared.info("Notification type changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }
                            
                            if viewModel.notificationType == "bark" {
                                Divider()
                                HStack {
                                    Text("Bark URL")
                                    Spacer()
                                    TextField("https://api.day.app/...", text: $viewModel.barkURL)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 220, alignment: .trailing)
                                        .onChange(of: viewModel.barkURL) { _, _ in
                                            viewModel.saveSettings()
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
        .padding()
    }
    
    private var statusBarDescription: String {
        switch viewModel.statusBarDisplayMode {
        case .average:
            return languageManager.t("settings.desc.average")
        case .worst:
            return languageManager.t("settings.desc.worst")
        case .best:
            return languageManager.t("settings.desc.best")
        case .first:
            return languageManager.t("settings.desc.first")
        }
    }
}

// MARK: - Draggable Sorting Delegate
struct HostDropDelegate: DropDelegate {
    let item: HostConfig
    @ObservedObject var viewModel: PingMonitorViewModel
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return }
        
        itemProvider.loadObject(ofClass: NSString.self) { string, error in
            guard let idString = string as? String,
                  let draggingId = UUID(uuidString: idString),
                  draggingId != item.id else { return }
            
            Task { @MainActor in
                if let fromIndex = viewModel.hosts.firstIndex(where: { $0.id == draggingId }),
                   let toIndex = viewModel.hosts.firstIndex(where: { $0.id == item.id }) {
                    withAnimation {
                        viewModel.moveHost(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                    }
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
