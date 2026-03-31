import SwiftUI

// MARK: - 统计 Tab
struct StatisticsTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedHost: HostConfig?
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // 主机选择器
            if viewModel.hosts.count > 1 {
                Picker(languageManager.t("stats.select_host"), selection: $selectedHost) {
                    Text(languageManager.t("stats.all_hosts")).tag(nil as HostConfig?)
                    ForEach(viewModel.hosts) { host in
                        Text(host.name).tag(host as HostConfig?)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            if viewModel.hosts.isEmpty {
                ContentUnavailableView(languageManager.t("monitor.no_hosts"), systemImage: "network", description: Text(languageManager.t("monitor.add_host_hint")))
            } else {
                StatisticsContentView(host: selectedHost, viewModel: viewModel)
            }
        }
    }
}

struct StatisticsContentView: View {
    let host: HostConfig?
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    // 聚合所有主机的统计数据
    var aggregatedStats: AggregatedStats {
        if let singleHost = host {
            // 单个主机模式
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
        } else {
            // 全部主机聚合模式
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

            // 按时间排序历史记录
            allLatencyHistory.sort { $0.timestamp < $1.timestamp }
            // 限制总数
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
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 概览卡片
                OverviewCardsView(stats: aggregatedStats)

                // 延迟图表
                if !aggregatedStats.latencyHistory.isEmpty {
                    LatencyChartView(history: aggregatedStats.latencyHistory)
                }

                // 详细统计
                DetailedStatsView(stats: aggregatedStats)

                // 操作按钮
                HStack {
                    if let singleHost = host {
                        Button(languageManager.t("stats.reset_current")) {
                            viewModel.resetStats(for: singleHost.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(languageManager.t("stats.reset_all")) {
                        viewModel.resetAllStats()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                .padding(.top)
            }
            .padding()
        }
    }
}

// 聚合统计数据结构
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

    nonisolated(unsafe) private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()
    private func formatBytes(_ bytes: Int64) -> String {
        AggregatedStats.byteCountFormatter.string(fromByteCount: bytes)
    }
}

struct OverviewCardsView: View {
    let stats: AggregatedStats
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: stats.isAggregated ? languageManager.t("dashboard.total") : languageManager.t("stats.requests"),
                value: "\(stats.totalPings)",
                icon: "number.circle.fill",
                color: .blue
            )

            StatCard(
                title: languageManager.t("stats.success_rate"),
                value: String(format: "%.1f%%", stats.successRate),
                icon: "checkmark.circle.fill",
                color: .green
            )

            StatCard(
                title: languageManager.t("stats.loss_rate"),
                value: String(format: "%.1f%%", stats.packetLossRate),
                icon: "xmark.circle.fill",
                color: stats.packetLossRate > 5 ? .red : .orange
            )

            StatCard(
                title: languageManager.t("stats.traffic"),
                value: stats.totalTraffic,
                icon: "arrow.up.arrow.down.circle.fill",
                color: .purple
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        .linearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: color.opacity(0.08), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }
}

struct LatencyChartView: View {
    let history: [LatencyPoint]
    @State private var animateEndpoint = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text(languageManager.t("dashboard.latency_trend"))
                        .font(.system(size: 14, weight: .semibold))
                }

                Spacer()

                if let last = history.last {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(latencyColor(for: last.latency))
                            .frame(width: 6, height: 6)
                        Text("\(languageManager.t("stats.chart.current")) \(Int(last.latency))ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Chart
            GeometryReader { geometry in
                chartContent(size: geometry.size)
            }
            .frame(height: 180)

            // Legend
            HStack(spacing: 16) {
                latencyLegend(languageManager.t("stats.legend.excellent"), color: .green)
                latencyLegend(languageManager.t("stats.legend.good"), color: .orange)
                latencyLegend(languageManager.t("stats.legend.poor"), color: .red)
                Spacer()
                Text(String(format: languageManager.t("stats.chart.count"), history.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.08), lineWidth: 1)
        )
        .onAppear { animateEndpoint = true }
    }

    private func chartContent(size: CGSize) -> some View {
        let leftPad: CGFloat = 40
        let rightPad: CGFloat = 10
        let topPad: CGFloat = 5
        let bottomPad: CGFloat = 22 // space for X-axis labels
        let chartWidth = size.width - leftPad - rightPad
        let chartHeight = size.height - topPad - bottomPad

        return ZStack(alignment: .topLeading) {
            // Y-axis labels and grid lines
            ForEach(yAxisValues(), id: \.self) { value in
                let normalizedY = (value - chartMinLatency) / (chartMaxLatency - chartMinLatency)
                let y = topPad + chartHeight - CGFloat(normalizedY) * chartHeight

                Path { path in
                    path.move(to: CGPoint(x: leftPad, y: y))
                    path.addLine(to: CGPoint(x: size.width - rightPad, y: y))
                }
                .stroke(Color.gray.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                Text("\(Int(value))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .position(x: 18, y: y)
            }

            // X-axis time labels
            ForEach(xAxisIndices(), id: \.self) { index in
                let point = history[index]
                let x = leftPad + chartWidth * CGFloat(index) / CGFloat(max(history.count - 1, 1))
                let y = topPad + chartHeight + 12

                Text(formatTime(point.timestamp))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .position(x: x, y: y)
            }

            // Threshold reference lines
            ForEach([50.0, 100.0], id: \.self) { threshold in
                if threshold >= chartMinLatency && threshold <= chartMaxLatency {
                    let normalizedY = (threshold - chartMinLatency) / (chartMaxLatency - chartMinLatency)
                    let y = topPad + chartHeight - CGFloat(normalizedY) * chartHeight

                    Path { path in
                        path.move(to: CGPoint(x: leftPad, y: y))
                        path.addLine(to: CGPoint(x: size.width - rightPad, y: y))
                    }
                    .stroke(
                        threshold == 50 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 3])
                    )
                }
            }

            // Gradient fill under curve
            Path { path in
                guard history.count > 1 else { return }
                let points = chartPoints(width: chartWidth, height: chartHeight, leftPad: leftPad, topPad: topPad)
                path.move(to: CGPoint(x: points.first!.x, y: topPad + chartHeight))
                path.addLine(to: points.first!)
                addSmoothCurve(to: &path, points: points)
                path.addLine(to: CGPoint(x: points.last!.x, y: topPad + chartHeight))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.15), .cyan.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Gradient colored Bézier line segments
            Canvas { context, canvasSize in
                guard history.count > 1 else { return }
                let points = chartPoints(width: chartWidth, height: chartHeight, leftPad: leftPad, topPad: topPad)

                // Draw line segments individually with per-point color
                for i in 1..<points.count {
                    let p0 = points[i - 1]
                    let p1 = points[i]
                    let midX = (p0.x + p1.x) / 2

                    var seg = Path()
                    seg.move(to: p0)
                    seg.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))

                    let avgLatency = (history[i-1].latency + history[i].latency) / 2
                    context.stroke(seg, with: .color(latencyColor(for: avgLatency)), lineWidth: 2.5)
                }

                // Data points — draw every Nth for clarity
                let step = max(1, history.count / 20)
                for (index, point) in history.enumerated() {
                    guard index % step == 0 || index == history.count - 1 else { continue }
                    let pt = points[index]
                    let isLast = index == history.count - 1
                    let dotSize: CGFloat = isLast ? 5 : 3
                    let dotPath = Path(ellipseIn: CGRect(x: pt.x - dotSize, y: pt.y - dotSize, width: dotSize * 2, height: dotSize * 2))
                    context.fill(dotPath, with: .color(latencyColor(for: point.latency)))
                    context.stroke(dotPath, with: .color(.white.opacity(0.8)), lineWidth: isLast ? 2 : 1)
                }
            }

            // Pulsing endpoint
            if let last = history.last {
                let points = chartPoints(width: chartWidth, height: chartHeight, leftPad: leftPad, topPad: topPad)
                if let lastPt = points.last {
                    Circle()
                        .fill(latencyColor(for: last.latency).opacity(0.3))
                        .frame(width: 16, height: 16)
                        .scaleEffect(animateEndpoint ? 1.8 : 1.0)
                        .opacity(animateEndpoint ? 0 : 0.5)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: animateEndpoint)
                        .position(lastPt)
                }
            }
        }
    }

    // MARK: - Helpers

    private func chartPoints(width: CGFloat, height: CGFloat, leftPad: CGFloat, topPad: CGFloat) -> [CGPoint] {
        let stepX = width / CGFloat(max(history.count - 1, 1))
        return history.enumerated().map { index, point in
            let x = leftPad + CGFloat(index) * stepX
            let normalizedY = (point.latency - chartMinLatency) / (chartMaxLatency - chartMinLatency)
            let y = topPad + height - CGFloat(normalizedY) * height
            return CGPoint(x: x, y: y)
        }
    }

    private func addSmoothCurve(to path: inout Path, points: [CGPoint]) {
        guard points.count > 1 else { return }
        for i in 1..<points.count {
            let p0 = points[i - 1]
            let p1 = points[i]
            let midX = (p0.x + p1.x) / 2
            path.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
        }
    }

    private func yAxisValues() -> [Double] {
        let range = chartMaxLatency - chartMinLatency
        guard range > 0 else { return [chartMinLatency] }
        let step = niceStep(for: range)
        var values: [Double] = []
        var v = (chartMinLatency / step).rounded(.down) * step
        while v <= chartMaxLatency {
            if v >= chartMinLatency { values.append(v) }
            v += step
        }
        return values
    }

    private func xAxisIndices() -> [Int] {
        guard history.count > 1 else { return history.isEmpty ? [] : [0] }
        let count = min(5, history.count)
        let step = Double(history.count - 1) / Double(count - 1)
        return (0..<count).map { Int(Double($0) * step) }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private func formatTime(_ date: Date) -> String {
        LatencyChartView.timeFormatter.string(from: date)
    }

    private func niceStep(for range: Double) -> Double {
        let rough = range / 4.0
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        if norm <= 1 { return 1 * mag }
        if norm <= 2 { return 2 * mag }
        if norm <= 5 { return 5 * mag }
        return 10 * mag
    }

    private func latencyLegend(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func latencyColor(for latency: Double) -> Color {
        if latency < 50 { return .green }
        if latency < 100 { return .orange }
        return .red
    }

    var chartMinLatency: Double {
        let minVal = history.map { $0.latency }.min() ?? 0
        return max(0, minVal - (chartMaxLatency - minVal) * 0.1)
    }

    var chartMaxLatency: Double {
        let maxVal = max(history.map { $0.latency }.max() ?? 100, 1)
        let minVal = history.map { $0.latency }.min() ?? 0
        let padding = max((maxVal - minVal) * 0.15, 5)
        return maxVal + padding
    }
}

struct DetailedStatsView: View {
    let stats: AggregatedStats
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo)
                Text(stats.isAggregated ? "\(languageManager.t("stats.detailed")) (\(stats.hostCount))" : languageManager.t("stats.detailed"))
                    .font(.system(size: 14, weight: .semibold))
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                DetailStatCard(icon: "checkmark.circle", color: .green, label: languageManager.t("stats.success"), value: "\(stats.successfulPings)")
                DetailStatCard(icon: "xmark.circle", color: .red, label: languageManager.t("stats.failed"), value: "\(stats.failedPings)")
                DetailStatCard(icon: "timer", color: .blue, label: languageManager.t("dashboard.uptime"), value: formatDuration(stats.startTime))
                DetailStatCard(icon: "arrow.down.to.line", color: .cyan, label: languageManager.t("stats.min_latency"), value: stats.minLatency != nil ? String(format: "%.1fms", stats.minLatency!) : "N/A")
                DetailStatCard(icon: "arrow.up.to.line", color: .orange, label: languageManager.t("stats.max_latency"), value: stats.maxLatency != nil ? String(format: "%.1fms", stats.maxLatency!) : "N/A")
                DetailStatCard(icon: "equal.circle", color: .purple, label: languageManager.t("stats.avg_latency"), value: String(format: "%.1fms", stats.avgLatency))
            }

            // Traffic cards
            HStack(spacing: 12) {
                TrafficCard(icon: "arrow.up.circle.fill", color: .blue, label: languageManager.t("stats.sent"), value: formatBytes(stats.totalBytesSent))
                TrafficCard(icon: "arrow.down.circle.fill", color: .green, label: languageManager.t("stats.received"), value: formatBytes(stats.totalBytesReceived))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.08), lineWidth: 1)
        )
    }

    nonisolated(unsafe) private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()
    private func formatBytes(_ bytes: Int64) -> String {
        DetailedStatsView.byteCountFormatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ startDate: Date) -> String {
        let interval = Date().timeIntervalSince(startDate)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return String(format: languageManager.t("stats.time.hours"), hours, minutes)
        } else if minutes > 0 {
            return String(format: languageManager.t("stats.time.minutes"), minutes, seconds)
        } else {
            return String(format: languageManager.t("stats.time.seconds"), seconds)
        }
    }
}

struct DetailStatCard: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct TrafficCard: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.1), lineWidth: 0.5)
        )
    }
}
