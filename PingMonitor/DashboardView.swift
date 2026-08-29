import SwiftUI
import Charts

// 读取 Dashboard 容器宽，用于在 2 列 Grid / 单列 VStack 间切换。
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
        Theme.Layout.fitsTwoColumns(detailWidth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.gridSpacing) {
                if showsTwoColumns {
                    // 每行独立 Grid：单 GridRow 2 个 cell → 列等分跟随窗口；cell maxHeight:.infinity 撑满行高实现同行等高。
                    Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                        GridRow {
                            QualityScoreCard(snapshot: globalSnapshot, selectedWindow: $selectedWindow)
                                .gridCell()
                            QualityDimensionsCard(snapshot: globalSnapshot)
                                .gridCell()
                        }
                    }
                    Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                        GridRow {
                            QualityTrendCard(snapshot: globalSnapshot, trendPoints: trendPoints)
                                .gridCell()
                            RecentEventsCard(events: globalSnapshot.recentEvents)
                                .gridCell()
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
        .measureContainerWidth { detailWidth = $0 }
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

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text("\(snapshot.score)")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.giant, weight: .bold))
                        .foregroundStyle(qualityColor(snapshot.score))
                    Text("/ 100")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                HStack(spacing: 12) {
                    metricBlock(
                        title: languageManager.t("dashboard.p95_latency"),
                        value: snapshot.averageP95Latency.map { String(format: "%.0fms", $0) } ?? "—",
                        color: Theme.Colors.accentBlue
                    )
                    metricBlock(
                        title: languageManager.t("dashboard.avg_loss"),
                        value: String(format: "%.1f%%", snapshot.averagePacketLoss),
                        color: Theme.Colors.accentRed
                    )
                    metricBlock(
                        title: languageManager.t("dashboard.avg_jitter"),
                        value: String(format: "%.1fms", snapshot.averageJitter),
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
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.number(Theme.Fonts.Size.title, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08))
        .cornerRadius(Theme.Radius.md)
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", snapshot.tunnelShare * 100))
                        .font(Theme.Fonts.number(Theme.Fonts.Size.callout, weight: .semibold))
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
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(value)")
                    .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.xs)
                        .fill(Theme.Colors.cardBackground)
                    RoundedRectangle(cornerRadius: Theme.Radius.xs)
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if trendPoints.isEmpty {
                    Text(languageManager.t("dashboard.no_data"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
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
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(Theme.Colors.chartGrid)
                            AxisValueLabel {
                                if let score = value.as(Double.self) {
                                    Text("\(Int(score))")
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
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
                            value: snapshot.averageP95Latency.map { String(format: "%.0fms", $0) } ?? "—",
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
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                } else {
                    VStack(spacing: 12) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(eventColor(event.severity))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(event.title)
                                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                        Spacer()
                                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }

                                    if let hostName = event.hostName {
                                        Text(hostName)
                                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
                                            .foregroundStyle(eventColor(event.severity))
                                    }

                                    Text(event.detail)
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .background(Theme.Colors.cardBackground.opacity(0.65))
                            .cornerRadius(Theme.Radius.md)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func eventColor(_ severity: QualityEventSeverity) -> Color {
        Theme.Status.severity(severity)
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                } else {
                    let mode = hostHealthDisplayMode(width: tableWidth)
                    // Grid 天然按「该列最宽单元格」定宽，列宽自适应内容；
                    // horizontalSpacing 归零 + 单元格自带内边距，行底色才能连成一条不断裂的色块。
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            headerCell(languageManager.t("traceroute.ip"))
                                .gridColumnAlignment(.leading)
                            headerCell(languageManager.t("dashboard.quality_score"), alignment: .trailing)
                                .gridColumnAlignment(.trailing)
                            if mode.showsP95 {
                                headerCell(languageManager.t("dashboard.p95_latency"), alignment: .trailing)
                                    .gridColumnAlignment(.trailing)
                            }
                            if mode.showsExtra {
                                headerCell(languageManager.t("host_detail.jitter"), alignment: .trailing)
                                    .gridColumnAlignment(.trailing)
                                headerCell(languageManager.t("stats.loss_rate"), alignment: .trailing)
                                    .gridColumnAlignment(.trailing)
                                headerCell(languageManager.t("host_detail.path"), alignment: .trailing)
                                    .gridColumnAlignment(.trailing)
                            }
                        }

                        Divider().opacity(0.5)

                        ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                            hostHealthRow(snapshot: snapshot, mode: mode, striped: !index.isMultiple(of: 2))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
            // .top 在水平方向等于居中，会把整张表摁到卡片中间；必须是 .topLeading。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HostHealthTableWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(HostHealthTableWidthKey.self) { tableWidth = $0 }
        }
    }

    private func headerCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: alignment == .leading ? .infinity : nil, alignment: alignment)
            .tableCellPadding()
    }

    private func valueCell(_ value: String, suffix: String = "", color: Color = Theme.Colors.textPrimary) -> some View {
        Text("\(value)\(suffix)")
            .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .tableCellPadding()
    }

    // 测量值只用来决定「显示几列」，绝不参与算像素宽度 —— 列宽一旦按测量值的百分比算死，
    // 测量取不到真实值时就会在宽卡片里画出一张窄表。
    // ≥480 六列 / 320..<480 三列(IP+score+p95) / <320 单列竖排。
    private struct HostHealthDisplayMode: Equatable {
        let showsP95: Bool
        let showsExtra: Bool
    }

    private func hostHealthDisplayMode(width w: CGFloat) -> HostHealthDisplayMode {
        if w >= 480 { return .init(showsP95: true, showsExtra: true) }
        if w >= 320 { return .init(showsP95: true, showsExtra: false) }
        return .init(showsP95: false, showsExtra: false)
    }

    private func nameCell(_ snapshot: HostQualitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.hostName)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            if let failure = snapshot.lastFailureText {
                Text(failure)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        // 名称列吃掉指标列自适应后剩下的空间，行底色因此能铺满整行。
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableCellPadding()
    }

    @ViewBuilder
    private func hostHealthRow(snapshot: HostQualitySnapshot, mode: HostHealthDisplayMode, striped: Bool) -> some View {
        GridRow {
            if !mode.showsP95 {
                // 单列竖排：主机名 + 指标堆叠
                VStack(alignment: .leading, spacing: 6) {
                    nameCell(snapshot)
                    HStack(spacing: 12) {
                        valueCell("\(snapshot.score)", color: qualityColor(snapshot.score))
                        valueCell(snapshot.p95Latency.map { String(format: "%.0f", $0) } ?? "—", suffix: "ms")
                        Text(pathLabel(snapshot.pathKind))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                            .foregroundStyle(pathColor(snapshot.pathKind))
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                nameCell(snapshot)
                valueCell("\(snapshot.score)", color: qualityColor(snapshot.score))
                if mode.showsP95 {
                    valueCell(snapshot.p95Latency.map { String(format: "%.0f", $0) } ?? "—", suffix: "ms")
                }
                if mode.showsExtra {
                    valueCell(String(format: "%.1f", snapshot.jitter), suffix: "ms")
                    valueCell(String(format: "%.1f", snapshot.packetLoss), suffix: "%", color: snapshot.packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                    valueCell(pathLabel(snapshot.pathKind), color: pathColor(snapshot.pathKind))
                }
            }
        }
        // 加在 GridRow 上的修饰器会作用到该行每个单元格：横向间距为 0，
        // 单元格底色便首尾相接，视觉上就是一条完整的斑马纹。
        .background(striped ? Theme.Colors.surfaceOverlay : Color.clear)
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
        Theme.Status.path(kind)
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
            VStack(alignment: .leading, spacing: 16) {
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", snapshot.tunnelShare * 100))
                        .font(Theme.Fonts.number(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(snapshot.tunnelShare > 0.7 ? Theme.Colors.accentOrange : Theme.Colors.textPrimary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.Colors.cardBackground)
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(snapshot.tunnelShare > 0.7 ? Theme.Colors.accentOrange : Theme.Colors.accentBlue)
                            .frame(width: geometry.size.width * CGFloat(snapshot.tunnelShare))
                    }
                }
                .frame(height: 10)

                Divider().opacity(0.15)

                VStack(alignment: .leading, spacing: 6) {
                    Text(languageManager.t("dashboard.top_consumer"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let topProcess {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topProcess.processName)
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("PID \(topProcess.pid)")
                                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("↓ \(NetworkSpeedManager.formatSpeed(topProcess.speedIn))")
                                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.accentCyan)
                                Text("↑ \(NetworkSpeedManager.formatSpeed(topProcess.speedOut))")
                                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.accentPurple)
                            }
                        }
                    } else {
                        Text(languageManager.t("dashboard.no_data"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
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
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("↓ \(down)")
                .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
                .foregroundStyle(accent)
            Text("↑ \(up)")
                .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
                .foregroundStyle(accent.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.08))
        .cornerRadius(Theme.Radius.md)
    }
}

private func scoreBadge(_ score: Int) -> some View {
    Text("\(score)")
        .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .bold))
        .foregroundStyle(qualityColor(score))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(qualityColor(score).opacity(0.12))
        .cornerRadius(Theme.Radius.pill)
}

private func qualityColor(_ score: Int) -> Color {
    Theme.Status.score(score)
}
