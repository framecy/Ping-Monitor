import SwiftUI
import Charts

// 读取 Dashboard 容器宽，用于在 2 列 Grid / 单列 VStack 间切换。
private struct DetailWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 800
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let n = nextValue()
        if n > 0 { value = n }
    }
}

struct DashboardView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @StateObject private var speedManager = NetworkSpeedManager.shared
    @State private var selectedWindow: NetworkQualityWindow = .fiveMinutes
    @ObservedObject private var languageManager = LanguageManager.shared
    // 容器宽下方按 2 列 Grid / 单列 VStack 切换；Grid 让同行卡等高(取最高内容高)，不塌不拉伸。
    @State private var detailWidth: CGFloat = 800

    private var globalSnapshot: GlobalQualitySnapshot {
        viewModel.globalQualitySnapshot(window: selectedWindow)
    }

    private var trendPoints: [QualityTrendPoint] {
        viewModel.qualityTrend(window: selectedWindow)
    }

    private var showsTwoColumns: Bool {
        detailWidth >= Theme.Layout.twoColumnMinWidth * 2 + Theme.Layout.gridSpacing
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.gridSpacing) {
                if showsTwoColumns {
                    // 每行独立 Grid：单 GridRow 2 个 cell → 列等分跟随窗口；cell maxHeight:.infinity 撑满行高实现同行等高。
                    Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                        GridRow {
                            QualityScoreCard(snapshot: globalSnapshot, selectedWindow: $selectedWindow)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            QualityDimensionsCard(snapshot: globalSnapshot)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                        GridRow {
                            QualityTrendCard(snapshot: globalSnapshot, trendPoints: trendPoints)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            RecentEventsCard(events: globalSnapshot.recentEvents)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else {
                    QualityScoreCard(snapshot: globalSnapshot, selectedWindow: $selectedWindow)
                        .frame(maxWidth: .infinity)
                    QualityDimensionsCard(snapshot: globalSnapshot)
                        .frame(maxWidth: .infinity)
                    QualityTrendCard(snapshot: globalSnapshot, trendPoints: trendPoints)
                        .frame(maxWidth: .infinity)
                    RecentEventsCard(events: globalSnapshot.recentEvents)
                        .frame(maxWidth: .infinity)
                }

                // 长卡：整行全宽自然高度，无并排对手 → 不存在等高/重叠问题。
                HostHealthCard(snapshots: globalSnapshot.worstHosts)
                    .frame(maxWidth: .infinity)
                TrafficContextCard(speedManager: speedManager, snapshot: globalSnapshot)
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: DetailWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(DetailWidthKey.self) { detailWidth = $0 }
        .background(Theme.Colors.background)
        .onAppear {
            speedManager.startMonitoring()
        }
        .onDisappear {
            if !viewModel.showSpeedInMenu {
                speedManager.stopMonitoring()
            }
        }
    }
}

private struct QualityScoreCard: View {
    let snapshot: GlobalQualitySnapshot
    @Binding var selectedWindow: NetworkQualityWindow
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(title: languageManager.t("dashboard.quality_score"), icon: "waveform.badge.magnifyingglass")
                    Spacer()
                    Picker("", selection: $selectedWindow) {
                        Text("1m").tag(NetworkQualityWindow.oneMinute)
                        Text("5m").tag(NetworkQualityWindow.fiveMinutes)
                        Text("1h").tag(NetworkQualityWindow.oneHour)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.small)
                }

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(snapshot.score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(qualityColor(snapshot.score))
                    Text("/ 100")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                HStack(spacing: 12) {
                    metricBlock(
                        title: languageManager.t("dashboard.p95_latency"),
                        value: snapshot.averageP95Latency.map { String(format: "%.0f ms", $0) } ?? "—",
                        color: Theme.Colors.accentBlue
                    )
                    metricBlock(
                        title: languageManager.t("dashboard.avg_loss"),
                        value: String(format: "%.1f%%", snapshot.averagePacketLoss),
                        color: Theme.Colors.accentRed
                    )
                    metricBlock(
                        title: languageManager.t("dashboard.avg_jitter"),
                        value: String(format: "%.1f ms", snapshot.averageJitter),
                        color: Theme.Colors.accentOrange
                    )
                }

                Divider().opacity(0.15)

                HStack(spacing: 12) {
                    statusPill(
                        title: languageManager.t("dashboard.healthy_hosts"),
                        value: "\(snapshot.healthyHostCount)",
                        color: Theme.Colors.accentGreen
                    )
                    statusPill(
                        title: languageManager.t("dashboard.degraded_hosts"),
                        value: "\(snapshot.degradedHostCount)",
                        color: Theme.Colors.accentOrange
                    )
                    statusPill(
                        title: languageManager.t("dashboard.critical_hosts"),
                        value: "\(snapshot.criticalHostCount)",
                        color: Theme.Colors.accentRed
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func metricBlock(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Fonts.body(10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Fonts.body(10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}

private struct QualityDimensionsCard: View {
    let snapshot: GlobalQualitySnapshot
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("dashboard.dimension_breakdown"), icon: "slider.horizontal.3")

                dimensionRow(languageManager.t("dashboard.latency_trend"), value: snapshot.dimensions.latency, color: Theme.Colors.accentBlue)
                dimensionRow(languageManager.t("dashboard.network_status"), value: snapshot.dimensions.stability, color: Theme.Colors.accentGreen)
                dimensionRow(languageManager.t("dashboard.path_health"), value: snapshot.dimensions.path, color: Theme.Colors.accentOrange)
                dimensionRow(languageManager.t("dashboard.bandwidth_pressure"), value: snapshot.dimensions.bandwidth, color: Theme.Colors.accentPurple)
                dimensionRow(languageManager.t("dashboard.resolution"), value: snapshot.dimensions.resolution, color: Theme.Colors.accentCyan)
                dimensionRow(languageManager.t("dashboard.overlay"), value: snapshot.dimensions.overlay, color: Theme.Colors.accentRed)

                Divider().opacity(0.15)

                HStack {
                    Text(languageManager.t("dashboard.tunnel_ratio"))
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", snapshot.tunnelShare * 100))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(snapshot.tunnelShare > 0.7 ? Theme.Colors.accentOrange : Theme.Colors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func dimensionRow(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.Fonts.body(11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.cardBackground)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(6, geometry.size.width * CGFloat(value) / 100.0))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct QualityTrendCard: View {
    let snapshot: GlobalQualitySnapshot
    let trendPoints: [QualityTrendPoint]
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: languageManager.t("dashboard.latency_trend"), icon: "chart.xyaxis.line")
                    Spacer()
                    Text(languageManager.t("dashboard.samples"))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if trendPoints.isEmpty {
                    Text(languageManager.t("dashboard.no_data"))
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    Chart {
                        ForEach(trendPoints) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Score", point.score)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentBlue.opacity(0.28), Theme.Colors.accentBlue.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Score", point.score)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.Colors.accentBlue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
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
                    .frame(height: 180)

                    HStack(spacing: 16) {
                        summaryTag(
                            title: languageManager.t("dashboard.quality_score"),
                            value: "\(snapshot.score)",
                            color: qualityColor(snapshot.score)
                        )
                        summaryTag(
                            title: languageManager.t("dashboard.p95_latency"),
                            value: snapshot.averageP95Latency.map { String(format: "%.0f ms", $0) } ?? "—",
                            color: Theme.Colors.accentBlue
                        )
                        summaryTag(
                            title: languageManager.t("dashboard.avg_loss"),
                            value: String(format: "%.1f%%", snapshot.averagePacketLoss),
                            color: Theme.Colors.accentRed
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func summaryTag(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Fonts.body(10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

private struct RecentEventsCard: View {
    let events: [NetworkQualityEvent]
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("dashboard.recent_events"), icon: "exclamationmark.bubble")

                if events.isEmpty {
                    Text(languageManager.t("dashboard.no_events"))
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(eventColor(event.severity))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 2) {
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
                                        .font(Theme.Fonts.body(11))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

// 读取 HostHealthCard 表格区实际宽，用于按宽度降级列数（不阻塞内容高度）。
private struct HostHealthTableWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 480
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let n = nextValue()
        if n > 0 { value = n }
    }
}

private struct HostHealthCard: View {
    let snapshots: [HostQualitySnapshot]
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var tableWidth: CGFloat = 480

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("dashboard.host_health"), icon: "server.rack")

                if snapshots.isEmpty {
                    Text(languageManager.t("dashboard.no_data"))
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                } else {
                    let mode = hostHealthDisplayMode(width: tableWidth)
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            headerCell(languageManager.t("traceroute.ip"), width: mode.ipWidth, alignment: .leading)
                            headerCell(languageManager.t("dashboard.quality_score"), width: mode.scoreWidth, alignment: .trailing)
                            if mode.showsP95 {
                                headerCell(languageManager.t("dashboard.p95_latency"), width: mode.valueWidth, alignment: .trailing)
                            }
                            if mode.showsExtra {
                                headerCell(languageManager.t("host_detail.jitter"), width: mode.valueWidth, alignment: .trailing)
                                headerCell(languageManager.t("stats.loss_rate"), width: mode.valueWidth, alignment: .trailing)
                                headerCell(languageManager.t("host_detail.path"), width: mode.valueWidth, alignment: .trailing)
                            }
                        }

                        ForEach(snapshots) { snapshot in
                            hostHealthRow(snapshot: snapshot, mode: mode)

                            if snapshot.id != snapshots.last?.id {
                                Divider().opacity(0.08)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HostHealthTableWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(HostHealthTableWidthKey.self) { tableWidth = $0 }
        }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: width, alignment: alignment)
    }

    private func valueCell(_ value: String, width: CGFloat, suffix: String = "", color: Color = Theme.Colors.textPrimary) -> some View {
        Text("\(value)\(suffix)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
            .lineLimit(1)
    }

    // 按可用宽度降级：≥480 六列 / 320..<480 三列(IP+score+p95) / <320 单列竖排。
    private struct HostHealthDisplayMode: Equatable {
        let ipWidth: CGFloat
        let scoreWidth: CGFloat
        let valueWidth: CGFloat
        let showsP95: Bool
        let showsExtra: Bool
    }

    private func hostHealthDisplayMode(width w: CGFloat) -> HostHealthDisplayMode {
        let cellSpacing: CGFloat = 10
        if w >= 480 {
            // 六列(ip/score/p95/jitter/loss/path)：扣 5 个间距后按比例分配
            let net = max(0, w - cellSpacing * 5)
            return .init(ipWidth: net * 0.30, scoreWidth: net * 0.14, valueWidth: net * 0.14, showsP95: true, showsExtra: true)
        } else if w >= 320 {
            // 三列(ip/score/p95)：扣 2 个间距
            let net = max(0, w - cellSpacing * 2)
            return .init(ipWidth: net * 0.50, scoreWidth: net * 0.25, valueWidth: net * 0.25, showsP95: true, showsExtra: false)
        } else {
            return .init(ipWidth: w, scoreWidth: 0, valueWidth: 0, showsP95: false, showsExtra: false)
        }
    }

    @ViewBuilder
    private func hostHealthRow(snapshot: HostQualitySnapshot, mode: HostHealthDisplayMode) -> some View {
        if !mode.showsP95 {
            // 单列竖排：主机名 + 评分/指标堆叠
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.hostName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if let failure = snapshot.lastFailureText {
                        Text(failure)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 12) {
                    valueCell("\(snapshot.score)", width: 60, color: qualityColor(snapshot.score))
                    valueCell(snapshot.p95Latency.map { String(format: "%.0f", $0) } ?? "—", width: 70, suffix: "ms")
                    Text(pathLabel(snapshot.pathKind))
                        .font(.system(size: 11))
                        .foregroundStyle(pathColor(snapshot.pathKind))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.hostName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if let failure = snapshot.lastFailureText {
                        Text(failure)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(width: mode.ipWidth, alignment: .leading)

                valueCell("\(snapshot.score)", width: mode.scoreWidth, color: qualityColor(snapshot.score))
                if mode.showsP95 {
                    valueCell(snapshot.p95Latency.map { String(format: "%.0f", $0) } ?? "—", width: mode.valueWidth, suffix: "ms")
                }
                if mode.showsExtra {
                    valueCell(String(format: "%.1f", snapshot.jitter), width: mode.valueWidth, suffix: "ms")
                    valueCell(String(format: "%.1f", snapshot.packetLoss), width: mode.valueWidth, suffix: "%", color: snapshot.packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                    valueCell(pathLabel(snapshot.pathKind), width: mode.valueWidth, color: pathColor(snapshot.pathKind))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func pathLabel(_ kind: ProbePathKind) -> String {
        switch kind {
        case .direct:
            return languageManager.t("diagnostics.path.direct")
        case .relay:
            return languageManager.t("diagnostics.path.relay")
        case .unknown:
            return "—"
        }
    }

    private func pathColor(_ kind: ProbePathKind) -> Color {
        switch kind {
        case .direct:
            return Theme.Colors.accentGreen
        case .relay:
            return Theme.Colors.accentOrange
        case .unknown:
            return Theme.Colors.textTertiary
        }
    }
}

private struct TrafficContextCard: View {
    @ObservedObject var speedManager: NetworkSpeedManager
    let snapshot: GlobalQualitySnapshot
    @ObservedObject private var languageManager = LanguageManager.shared

    private var topProcess: ProcessSummary? {
        speedManager.processList.first
    }

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: languageManager.t("netspeed.title"), icon: "chart.line.uptrend.xyaxis")

                HStack(spacing: 12) {
                    trafficPanel(
                        title: languageManager.t("dashboard.physical_traffic"),
                        down: NetworkSpeedManager.formatSpeed(speedManager.totalSpeedIn),
                        up: NetworkSpeedManager.formatSpeed(speedManager.totalSpeedOut),
                        accent: Theme.Colors.accentBlue
                    )
                    trafficPanel(
                        title: languageManager.t("dashboard.tunnel_traffic"),
                        down: NetworkSpeedManager.formatSpeed(speedManager.tunnelSpeedIn),
                        up: NetworkSpeedManager.formatSpeed(speedManager.tunnelSpeedOut),
                        accent: Theme.Colors.accentPurple
                    )
                }

                Divider().opacity(0.15)

                HStack {
                    Text(languageManager.t("dashboard.tunnel_ratio"))
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", snapshot.tunnelShare * 100))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(snapshot.tunnelShare > 0.7 ? Theme.Colors.accentOrange : Theme.Colors.textPrimary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.Colors.cardBackground)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(snapshot.tunnelShare > 0.7 ? Theme.Colors.accentOrange : Theme.Colors.accentBlue)
                            .frame(width: geometry.size.width * CGFloat(snapshot.tunnelShare))
                    }
                }
                .frame(height: 10)

                Divider().opacity(0.15)

                VStack(alignment: .leading, spacing: 6) {
                    Text(languageManager.t("dashboard.top_consumer"))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let topProcess {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topProcess.processName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("PID \(topProcess.pid)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("↓ \(NetworkSpeedManager.formatSpeed(topProcess.speedIn))")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.accentCyan)
                                Text("↑ \(NetworkSpeedManager.formatSpeed(topProcess.speedOut))")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.accentPurple)
                            }
                        }
                    } else {
                        Text(languageManager.t("dashboard.no_data"))
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func trafficPanel(title: String, down: String, up: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Fonts.body(10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("↓ \(down)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
            Text("↑ \(up)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(accent.opacity(0.08))
        .cornerRadius(10)
    }
}

private func scoreBadge(_ score: Int) -> some View {
    Text("\(score)")
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundStyle(qualityColor(score))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(qualityColor(score).opacity(0.12))
        .cornerRadius(999)
}

private func qualityColor(_ score: Int) -> Color {
    switch score {
    case 90...:
        return Theme.Colors.accentGreen
    case 75..<90:
        return Theme.Colors.accentBlue
    case 60..<75:
        return Theme.Colors.accentOrange
    case 40..<60:
        return Color.orange
    default:
        return Theme.Colors.accentRed
    }
}
