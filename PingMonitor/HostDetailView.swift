import SwiftUI
import Charts

struct HostDetailView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    let host: HostConfig
    let onClose: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var logManager = LogManager.shared
    @State private var showShortcutEditor = false
    @State private var editingShortcut: ServiceShortcut? = nil
    @State private var showRecordEditor = false
    @State private var editingRecord: HostRecord? = nil
    @State private var detailWidth: CGFloat = 800
    @State private var showResetConfirmation = false

    private var showsTwoColumns: Bool {
        Theme.Layout.fitsTwoColumns(detailWidth)
    }

    private var stats: HostStats? {
        viewModel.hostStats[host.id]
    }
    
    private var currentHost: HostConfig? {
        viewModel.hosts.first(where: { $0.id == host.id })
    }

    private var probeDiagnostic: HostProbeDiagnostic? {
        viewModel.hostDiagnostics[host.id]
    }

    private var qualitySnapshot: HostQualitySnapshot {
        viewModel.qualitySnapshot(for: currentHost ?? host)
    }

    private var lastResultText: String {
        if let diagnostic = probeDiagnostic {
            switch diagnostic.lastOutcome {
            case .success:
                return languageManager.t("diagnostics.result.reachable")
            case .failure:
                return diagnostic.lastFailureReason?.localizedDescription(using: languageManager) ?? languageManager.t("diagnostics.failure.unknown")
            case nil:
                break
            }
        }

        if currentHost?.isChecking == true {
            return languageManager.t("host_detail.checking")
        }
        if currentHost?.isReachable == true {
            return languageManager.t("diagnostics.result.reachable")
        }
        return languageManager.t("host_detail.offline")
    }

    private var lastResultColor: Color {
        if probeDiagnostic?.lastOutcome == .success || currentHost?.isReachable == true {
            return Theme.Colors.accentGreen
        }
        if let category = probeDiagnostic?.lastFailureReason?.category, category == .dnsFailure {
            return Theme.Colors.accentOrange
        }
        return Theme.Colors.accentRed
    }

    private var pathText: String? {
        probeDiagnostic?.lastPathSnapshot?.localizedDescription(using: languageManager)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            ScrollView {
                VStack(spacing: Theme.Layout.gridSpacing) {
                    // Row 1: Status + Latency
                    // 不能用 GridItem(.adaptive(minimum:))：adaptive 会塞进尽可能多的列，
                    // 宽窗口下排出 6 列而只填 2 个，卡片被挤在左侧、右边留大片空白。
                    if showsTwoColumns {
                        Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                            GridRow {
                                statusCard.gridCell()
                                latencyStatsCard.gridCell()
                            }
                        }
                    } else {
                        statusCard.frame(maxWidth: .infinity)
                        latencyStatsCard.frame(maxWidth: .infinity)
                    }

                    // Row 2: Chart
                    latencyChartCard

                    // Row 3: Packet Stats + Traffic
                    if showsTwoColumns {
                        Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                            GridRow {
                                packetStatsCard.gridCell()
                                trafficCard.gridCell()
                            }
                        }
                    } else {
                        packetStatsCard.frame(maxWidth: .infinity)
                        trafficCard.frame(maxWidth: .infinity)
                    }

                    // Row 4: Actions
                    HStack {
                        Spacer()
                        Button(languageManager.t("stats.export_current")) {
                            viewModel.exportStats(for: host.id)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(languageManager.t("stats.reset_current")) {
                            showResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(Theme.Colors.accentRed)
                        .alert(languageManager.t("stats.reset_current"), isPresented: $showResetConfirmation) {
                            Button(role: .destructive) {
                                viewModel.resetStats(for: host.id)
                            } label: {
                                Text(languageManager.t("common.confirm"))
                            }
                            Button(languageManager.t("common.cancel"), role: .cancel) {}
                        } message: {
                            Text(languageManager.t("stats.reset_confirm_message"))
                        }
                    }
                    
                    // Row 5: Display Rules
                    if !host.displayRules.isEmpty {
                        displayRulesCard
                    }
                    
                    // Row 5: Service Shortcuts
                    serviceShortcutsCard
                    
                    // Row 6: Records
                    recordsCard
                    
                    // Row 6: Logs
                    logsCard
                }
                .padding(Theme.Layout.cardPadding)
            }
            .measureContainerWidth { detailWidth = $0 }
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: $showShortcutEditor) {
            ShortcutEditorSheet(existingShortcut: editingShortcut, hostAddress: host.address) { shortcut in
                if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                    if let existing = editingShortcut,
                       let sIndex = viewModel.hosts[index].serviceShortcuts.firstIndex(where: { $0.id == existing.id }) {
                        // Edit existing
                        viewModel.hosts[index].serviceShortcuts[sIndex] = shortcut
                        LogManager.shared.info("Updated shortcut: \(shortcut.name)", host: host.name)
                    } else {
                        // Add new
                        viewModel.hosts[index].serviceShortcuts.append(shortcut)
                        LogManager.shared.info("Added shortcut: \(shortcut.name)", host: host.name)
                    }
                    viewModel.saveSettings()
                }
                editingShortcut = nil
            }
        }
        .sheet(isPresented: $showRecordEditor) {
            RecordEditorSheet(existingRecord: editingRecord) { record in
                if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                    if let existing = editingRecord,
                       let rIndex = viewModel.hosts[index].records.firstIndex(where: { $0.id == existing.id }) {
                        viewModel.hosts[index].records[rIndex] = record
                        LogManager.shared.info("Updated record: \(record.title)", host: host.name)
                    } else {
                        viewModel.hosts[index].records.append(record)
                        LogManager.shared.info("Added record: \(record.title)", host: host.name)
                    }
                    viewModel.saveSettings()
                }
                editingRecord = nil
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.body, weight: .semibold))
                    Text(languageManager.t("monitor.title"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .medium))
                }
                .foregroundStyle(Theme.Colors.accentBlue)
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Host indicator
            Circle()
                .fill(currentHost?.isReachable == true ? Theme.Colors.accentGreen : Theme.Colors.accentRed.opacity(0.6))
                .frame(width: 8, height: 8)
                .shadow(color: currentHost?.isReachable == true ? Theme.Colors.accentGreen.opacity(0.5) : .clear, radius: 4)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(host.name)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(host.address)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
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
                        .font(Theme.Fonts.number(Theme.Fonts.Size.headline, weight: .bold))
                        .foregroundStyle(latencyColor(latency))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(latencyColor(latency).opacity(0.1))
                )
            } else if currentHost?.isChecking == true {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(languageManager.t("host_detail.checking"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("host_detail.status"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(currentHost?.isReachable == true ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
                                .frame(width: 10, height: 10)
                            Text(currentHost?.isReachable == true ? languageManager.t("host_detail.online") : languageManager.t("host_detail.offline"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .semibold))
                                .foregroundStyle(currentHost?.isReachable == true ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
                        }
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("host_detail.uptime"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        if let stats = stats {
                            Text(formatDuration(from: stats.startTime))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accentBlue)
                        } else {
                            Text("--")
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticInfoRow(
                        title: languageManager.t("host_detail.probe_mode"),
                        icon: currentHost?.probeMode == .tcp ? "cable.connector" : "waveform.path.ecg",
                        text: currentHost?.probeDisplayLabel ?? host.probeDisplayLabel,
                        color: Theme.Colors.textTertiary
                    )

                    diagnosticInfoRow(
                        title: languageManager.t("dashboard.quality_score"),
                        icon: "waveform.badge.magnifyingglass",
                        text: "\(qualitySnapshot.score) / 100 · P95 \(qualitySnapshot.p95Latency.map { String(format: "%.0fms", $0) } ?? "—") · Loss \(String(format: "%.1f%%", qualitySnapshot.packetLoss))",
                        color: lastResultColor
                    )

                    diagnosticInfoRow(
                        title: languageManager.t("host_detail.last_result"),
                        icon: probeDiagnostic?.lastOutcome == .success ? "checkmark.circle" : "exclamationmark.triangle",
                        text: lastResultText,
                        color: lastResultColor
                    )

                    if let pathText, let pathSnapshot = probeDiagnostic?.lastPathSnapshot {
                        diagnosticInfoRow(
                            title: languageManager.t("host_detail.path"),
                            icon: pathSnapshot.kind == .relay ? "arrow.triangle.2.circlepath" : "point.topleft.down.to.point.bottomright.curvepath",
                            text: pathText,
                            color: pathSnapshot.kind == .relay ? Theme.Colors.accentOrange : Theme.Colors.accentGreen
                        )
                    }

                    if let lastCheckedAt = probeDiagnostic?.lastCheckedAt {
                        diagnosticInfoRow(
                            title: languageManager.t("host_detail.last_checked"),
                            icon: "clock",
                            text: lastCheckedAt.formatted(date: .omitted, time: .standard),
                            color: Theme.Colors.textTertiary
                        )
                    }

                    if let command = currentHost?.command, !command.isEmpty {
                        diagnosticInfoRow(
                            title: languageManager.t("host_detail.command"),
                            icon: "terminal",
                            text: command,
                            color: Theme.Colors.textTertiary
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func diagnosticInfoRow(title: String, icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 72, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                    .foregroundStyle(color)
                Text(text)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                    .foregroundStyle(color)
                    // 质量分那行含 P95/Loss，窄卡片下换行展示，不要截断成省略号。
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
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
                        color: Theme.Colors.accentGreen
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.max"),
                        value: stats?.maxLatency != nil ? String(format: "%.1f ms", stats!.maxLatency!) : "--",
                        color: Theme.Colors.accentRed
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
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(String(format: "%.1f ms", max - min))
                            .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accentOrange)
                    }
                }
            }
        }
    }
    
    // MARK: - Latency Chart
    
    @State private var selectedWindow: NetworkQualityWindow = .fiveMinutes
    
    private var latencyChartCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(Theme.Colors.accentPurple)
                    Text(languageManager.t("host_detail.latency_chart"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
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
                
                let cutoff = Date().addingTimeInterval(-selectedWindow.duration)
                let recentSamples = (viewModel.probeSamples[host.id] ?? []).filter { $0.timestamp >= cutoff }
                
                if !recentSamples.isEmpty {
                    Chart {
                        ForEach(recentSamples) { sample in
                            if let latency = sample.latency {
                                LineMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value("Latency", latency)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [Theme.Colors.accentBlue, Theme.Colors.accentCyan, Theme.Colors.accentGreen],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Theme.Colors.accentBlue.opacity(0.35), radius: 3)
                                
                                AreaMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value("Latency", latency)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [Theme.Colors.accentBlue.opacity(0.2), Theme.Colors.accentBlue.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            } else {
                                // Packet Loss marker (red dashed line)
                                RuleMark(x: .value("Time", sample.timestamp))
                                    .foregroundStyle(Theme.Colors.accentRed.opacity(0.8))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                    .annotation(position: .bottom) {
                                        Circle()
                                            .fill(Theme.Colors.accentRed)
                                            .frame(width: 4, height: 4)
                                    }
                            }
                        }
                        
                        // Avg line
                        if let avg = stats?.avgLatency, avg > 0 {
                            RuleMark(y: .value("Avg", avg))
                                .foregroundStyle(Theme.Colors.accentOrange.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text(String(format: "%.0f ms", avg))
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.accentOrange)
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: true))
                    .chartYScale(domain: 0...chartMaxLatency(for: recentSamples))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(Theme.Colors.chartGrid)
                            AxisValueLabel {
                                if let val = value.as(Double.self) {
                                    Text("\(Int(val))")
                                        .frame(width: 40, alignment: .trailing)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(date.formatted(.dateTime.hour().minute().second()))
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
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
                        color: Theme.Colors.accentGreen
                    )
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    DetailStatItem(
                        label: languageManager.t("host_detail.failed"),
                        value: "\(stats?.failedPings ?? 0)",
                        color: Theme.Colors.accentRed
                    )
                }
                
                Spacer()
                
                // Success rate bar
                HStack(spacing: 8) {
                    Text(languageManager.t("host_detail.success_rate"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Theme.Radius.xs)
                                .fill(Theme.Colors.cardBackground.opacity(0.5))
                            
                            RoundedRectangle(cornerRadius: Theme.Radius.xs)
                                .fill(successRateColor)
                                .frame(width: geo.size.width * CGFloat((stats?.successRate ?? 0) / 100.0))
                        }
                        .animation(.easeInOut, value: stats?.successRate)
                    }
                    .frame(height: 6)
                    
                    Text(String(format: "%.1f%%", stats?.successRate ?? 0))
                        .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.accentGreen)
                            Text(languageManager.t("host_detail.sent"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(formatTrafficBytes(stats?.totalBytesSent ?? 0))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accentGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 30).padding(.horizontal, 8).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.accentBlue)
                            Text(languageManager.t("host_detail.received"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(formatTrafficBytes(stats?.totalBytesReceived ?? 0))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Total traffic
                HStack(spacing: 6) {
                    Text(languageManager.t("host_detail.total_traffic"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(stats?.totalTraffic ?? "0 B")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
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
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                ForEach(host.displayRules) { rule in
                    HStack(spacing: 10) {
                        // Status dot
                        let isActive = isRuleActive(rule)
                        Circle()
                            .fill(isActive ? Theme.Colors.accentGreen : Theme.Colors.textTertiary.opacity(0.4))
                            .frame(width: 8, height: 8)
                        
                        // Rule label
                        Text(rule.label)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                            .foregroundStyle(isActive ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        
                        // Condition
                        Text(rule.condition == "less" ? "< \(Int(rule.threshold)) ms" : "> \(Int(rule.threshold)) ms")
                            .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                        
                        // Enabled badge
                        Text(rule.enabled ? languageManager.t("host_detail.enabled") : languageManager.t("host_detail.disabled"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
                            .foregroundStyle(rule.enabled ? Theme.Colors.accentGreen : Theme.Colors.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(rule.enabled ? Theme.Colors.accentGreen.opacity(0.1) : Theme.Colors.cardBackground)
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
        Theme.Status.latency(latency, .hop)
    }
    
    private func chartMaxLatency(for points: [ProbeSample]) -> Double {
        let values = points.compactMap { $0.latency }
        let maxVal = values.max() ?? 100
        let avgVal = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        
        // Cap the display scale to at most 5x the average or a minimum of 200
        let adaptiveCap = max(200, avgVal * 5)
        let displayMax = min(maxVal, adaptiveCap)
        
        return max(10, displayMax * 1.1)
    }
    
    // MARK: - Service Shortcuts Card
    
    private var serviceShortcutsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundStyle(Theme.Colors.accentGreen)
                    Text(languageManager.t("services.title"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    
                    Button(action: {
                        editingShortcut = nil
                        showShortcutEditor = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            Text(languageManager.t("services.add"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentGreen.opacity(0.15))
                        .cornerRadius(Theme.Radius.sm)
                    }
                    .buttonStyle(.plain)
                }
                
                let shortcuts = currentHost?.serviceShortcuts ?? []
                
                if shortcuts.isEmpty {
                    Text(languageManager.t("services.empty"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(shortcuts) { shortcut in
                            Button(action: {
                                openShortcut(shortcut)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: shortcut.icon)
                                        .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                                        .foregroundStyle(shortcutColor(for: shortcut.type))
                                        .frame(width: 28, height: 28)
                                        .background(shortcutColor(for: shortcut.type).opacity(0.12))
                                        .cornerRadius(Theme.Radius.sm)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(shortcut.name)
                                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                            .lineLimit(1)
                                        Text(shortcut.type.rawValue.uppercased())
                                            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .bold))
                                            .foregroundStyle(shortcutColor(for: shortcut.type))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                .padding(8)
                                .background(Theme.Colors.cardBackground)
                                .cornerRadius(Theme.Radius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                                        .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editingShortcut = shortcut
                                    showShortcutEditor = true
                                } label: {
                                    Label(languageManager.t("services.edit"), systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    if let hostIndex = viewModel.hosts.firstIndex(where: { $0.id == host.id }),
                                       let sIndex = viewModel.hosts[hostIndex].serviceShortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                                        viewModel.hosts[hostIndex].serviceShortcuts.remove(at: sIndex)
                                        viewModel.saveSettings()
                                    }
                                } label: {
                                    Label(languageManager.t("menu.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func shortcutColor(for type: ServiceShortcut.ServiceType) -> Color {
        Theme.Status.service(type)
    }
    
    private func openShortcut(_ shortcut: ServiceShortcut) {
        switch shortcut.type {
        case .web:
            if let url = URL(string: shortcut.url) {
                NSWorkspace.shared.open(url)
            }
        case .ssh:
            let sshCmd = shortcut.sshCommand
            let cmdFile = "/tmp/pm_ssh_\(UUID().uuidString.prefix(8)).command"
            let scriptContent = "#!/bin/bash\nrm -f \"\(cmdFile)\"\n\(sshCmd)\n"
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
    
    // MARK: - Records Card
    
    private var recordsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundStyle(Theme.Colors.accentOrange)
                    Text(languageManager.t("host.records.title"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    
                    Button(action: {
                        editingRecord = nil
                        showRecordEditor = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            Text(languageManager.t("host.records.add"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentOrange.opacity(0.15))
                        .cornerRadius(Theme.Radius.sm)
                    }
                    .buttonStyle(.plain)
                }
                
                let records = currentHost?.records ?? []
                
                if records.isEmpty {
                    Text(languageManager.t("host.records.empty"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 12) {
                        ForEach(records.sorted(by: { $0.createdAt > $1.createdAt })) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(record.title)
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Spacer()
                                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                
                                Text(record.content)
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(3)
                            }
                            .padding(12)
                            .background(Theme.Colors.background.opacity(0.5))
                            .cornerRadius(Theme.Radius.md)
                            .contextMenu {
                                Button {
                                    editingRecord = record
                                    showRecordEditor = true
                                } label: {
                                    Label(languageManager.t("host.records.edit"), systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                                        viewModel.hosts[index].records.removeAll(where: { $0.id == record.id })
                                        viewModel.saveSettings()
                                    }
                                } label: {
                                    Label(languageManager.t("host.records.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Logs Card
    
    private var logsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(Theme.Colors.accentOrange)
                    Text(languageManager.t("logs.title"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    
                    Button(action: {
                        if let url = logManager.exportHostLogs(for: host.name) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            Text(languageManager.t("logs.export"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.cardBackground)
                        .cornerRadius(Theme.Radius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                let hostLogs = logManager.logs.filter { $0.host == host.name }.suffix(50).reversed()
                
                if hostLogs.isEmpty {
                    Text(languageManager.t("logs.empty"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                         ForEach(Array(hostLogs), id: \.id) { log in
                             HStack(alignment: .top, spacing: 8) {
                                 Text(log.formattedTimestamp)
                                     .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .regular))
                                     .foregroundStyle(Theme.Colors.textSecondary)
                                     .frame(width: 140, alignment: .leading)
                                 
                                 Text(log.level.rawValue)
                                     .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .bold))
                                     .foregroundStyle(logColor(for: log.level))
                                     .frame(width: 45, alignment: .leading)
                                 
                                 Text(log.message)
                                     .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                                     .foregroundStyle(Theme.Colors.textPrimary)
                             }
                        }
                    }
                }
            }
        }
    }
    
    private func logColor(for level: LogManager.LogLevel) -> Color {
        Theme.Status.logLevel(level)
    }

    
    private var successRateColor: Color {
        Theme.Status.ratio(stats?.successRate ?? 0, good: 95, warning: 80)
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
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .semibold))
                .foregroundStyle(color)
                // 四个指标共用一行，"999.0 ms" 这类长值宁可整体缩小也不要折行。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Record Editor Sheet

struct RecordEditorSheet: View {
    let existingRecord: HostRecord?
    let onSave: (HostRecord) -> Void

    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var title: String = ""
    @State private var content: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingRecord == nil ? "Add Record" : "Edit Record")
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Theme.Colors.sidebarBackground)
            
            // Form
            Form {
                Section(header: Text(languageManager.t("host.records.field_title"))) {
                    TextField(languageManager.t("host.records.placeholder_title"), text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section(header: Text(languageManager.t("host.records.field_content"))) {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Theme.Colors.textTertiary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .padding()
            
            // Footer
            HStack {
                Spacer()
                Button(languageManager.t("common.cancel")) {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(languageManager.t("common.save")) {
                    let record = HostRecord(
                        id: existingRecord?.id ?? UUID(),
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        createdAt: existingRecord?.createdAt ?? Date()
                    )
                    onSave(record)
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Theme.Colors.sidebarBackground)
        }
        .frame(width: 400, height: 350)
        .onAppear {
            if let record = existingRecord {
                title = record.title
                content = record.content
            }
        }
    }
}
