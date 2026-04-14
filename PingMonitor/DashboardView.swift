import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @StateObject private var speedManager = NetworkSpeedManager.shared
    @State private var selectedWindow: NetworkQualityWindow = .fiveMinutes
    @ObservedObject private var languageManager = LanguageManager.shared

    private var globalSnapshot: GlobalQualitySnapshot {
        viewModel.globalQualitySnapshot(window: selectedWindow)
    }

    private var trendPoints: [QualityTrendPoint] {
        viewModel.qualityTrend(window: selectedWindow)
    }

    var body: some View {
        ScrollView {
            Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                GridRow {
                    QualityScoreCard(snapshot: globalSnapshot, selectedWindow: $selectedWindow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    QualityDimensionsCard(snapshot: globalSnapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                GridRow {
                    QualityTrendCard(snapshot: globalSnapshot, trendPoints: trendPoints)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    RecentEventsCard(events: globalSnapshot.recentEvents)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                GridRow {
                    HostHealthCard(
                        snapshots: globalSnapshot.worstHosts
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    TrafficContextCard(
                        speedManager: speedManager,
                        snapshot: globalSnapshot
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(Theme.Layout.cardPadding)
        }
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

private struct HostHealthCard: View {
    let snapshots: [HostQualitySnapshot]
    @ObservedObject private var languageManager = LanguageManager.shared

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
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            headerCell(languageManager.t("traceroute.ip"), width: 140, alignment: .leading)
                            headerCell(languageManager.t("dashboard.quality_score"), width: 52, alignment: .trailing)
                            headerCell(languageManager.t("dashboard.p95_latency"), width: 68, alignment: .trailing)
                            headerCell(languageManager.t("host_detail.jitter"), width: 58, alignment: .trailing)
                            headerCell(languageManager.t("stats.loss_rate"), width: 58, alignment: .trailing)
                            headerCell(languageManager.t("host_detail.path"), width: 60, alignment: .trailing)
                        }

                        ForEach(snapshots) { snapshot in
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
                                .frame(width: 140, alignment: .leading)

                                valueCell("\(snapshot.score)", width: 52, color: qualityColor(snapshot.score))
                                valueCell(snapshot.p95Latency.map { String(format: "%.0f", $0) } ?? "—", width: 68, suffix: "ms")
                                valueCell(String(format: "%.1f", snapshot.jitter), width: 58, suffix: "ms")
                                valueCell(String(format: "%.1f", snapshot.packetLoss), width: 58, suffix: "%", color: snapshot.packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary)
                                valueCell(pathLabel(snapshot.pathKind), width: 60, color: pathColor(snapshot.pathKind))
                            }
                            .padding(.vertical, 6)

                            if snapshot.id != snapshots.last?.id {
                                Divider().opacity(0.08)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
