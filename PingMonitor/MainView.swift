import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar Navigation Item
enum SidebarItem: String, CaseIterable, Identifiable {
    case monitor = "监控"
    case statistics = "统计"
    case hosts = "主机管理"
    case logs = "日志"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .monitor: return "waveform.path.ecg"
        case .statistics: return "chart.bar.fill"
        case .hosts: return "server.rack"
        case .logs: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    var activeColor: Color {
        switch self {
        case .monitor: return .green
        case .statistics: return .blue
        case .hosts: return .purple
        case .logs: return .orange
        case .settings: return .gray
        }
    }
}

struct MainView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedItem: SidebarItem = .monitor

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            VStack(spacing: 0) {
                headerView
                detailContent
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
    }
    
    // MARK: - Sidebar
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // App branding
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.linearGradient(
                            colors: [.blue.opacity(0.7), .cyan.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 32, height: 32)
                    Image(systemName: "network")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ping Monitor")
                        .font(.system(size: 13, weight: .bold))
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("v\(version)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider().padding(.horizontal, 12)
            
            // Navigation items
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                sidebarRow(for: item)
                    .tag(item)
            }
            .listStyle(.sidebar)
        }
        .background(.ultraThinMaterial)
    }
    
    private func sidebarRow(for item: SidebarItem) -> some View {
        Label {
            Text(item.rawValue)
                .font(.system(size: 13, weight: selectedItem == item ? .semibold : .regular))
        } icon: {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(selectedItem == item ? item.activeColor : .secondary)
                .frame(width: 20)
        }
    }
    
    // MARK: - Detail Content
    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem {
        case .monitor:
            MonitorTab(viewModel: viewModel)
        case .statistics:
            StatisticsTab(viewModel: viewModel)
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
                Text(selectedItem.rawValue)
                    .font(.system(size: 16, weight: .bold))
                Text(viewModel.isRunning ? "正在监控 \(viewModel.hosts.count) 个主机" : "已停止")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { viewModel.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(viewModel.isRunning ? "停止" : "开始")
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

// MARK: - 统计 Tab
struct StatisticsTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedHost: HostConfig?
    
    var body: some View {
        VStack(spacing: 0) {
            // 主机选择器
            if viewModel.hosts.count > 1 {
                Picker("选择主机", selection: $selectedHost) {
                    Text("全部主机").tag(nil as HostConfig?)
                    ForEach(viewModel.hosts) { host in
                        Text(host.name).tag(host as HostConfig?)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView("没有主机", systemImage: "network", description: Text("添加主机查看统计"))
            } else {
                StatisticsContentView(viewModel: viewModel, host: selectedHost)
            }
        }
    }
}

struct StatisticsContentView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    let host: HostConfig?
    
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
            
            for (hostId, stats) in viewModel.hostStats {
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
                        Button("重置当前主机统计") {
                            viewModel.resetStats(for: singleHost.id)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("重置所有统计") {
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
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct OverviewCardsView: View {
    let stats: AggregatedStats
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: stats.isAggregated ? "总请求数" : "请求数",
                value: "\(stats.totalPings)",
                icon: "number.circle.fill",
                color: .blue
            )
            
            StatCard(
                title: "成功率",
                value: String(format: "%.1f%%", stats.successRate),
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            StatCard(
                title: "丢包率",
                value: String(format: "%.1f%%", stats.packetLossRate),
                icon: "xmark.circle.fill",
                color: stats.packetLossRate > 5 ? .red : .orange
            )
            
            StatCard(
                title: "总流量",
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("延迟趋势")
                        .font(.system(size: 14, weight: .semibold))
                }
                
                Spacer()
                
                if let last = history.last {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(latencyColor(for: last.latency))
                            .frame(width: 6, height: 6)
                        Text("当前 \(Int(last.latency))ms")
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
                latencyLegend("<50ms 优秀", color: .green)
                latencyLegend("<100ms 良好", color: .orange)
                latencyLegend(">100ms 较差", color: .red)
                Spacer()
                Text("共 \(history.count) 次")
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
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo)
                Text(stats.isAggregated ? "详细统计 (\(stats.hostCount) 个主机)" : "详细统计")
                    .font(.system(size: 14, weight: .semibold))
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                DetailStatCard(icon: "checkmark.circle", color: .green, label: "成功请求", value: "\(stats.successfulPings)")
                DetailStatCard(icon: "xmark.circle", color: .red, label: "失败请求", value: "\(stats.failedPings)")
                DetailStatCard(icon: "timer", color: .blue, label: "运行时间", value: formatDuration(stats.startTime))
                DetailStatCard(icon: "arrow.down.to.line", color: .cyan, label: "最小延迟", value: stats.minLatency != nil ? String(format: "%.1fms", stats.minLatency!) : "N/A")
                DetailStatCard(icon: "arrow.up.to.line", color: .orange, label: "最大延迟", value: stats.maxLatency != nil ? String(format: "%.1fms", stats.maxLatency!) : "N/A")
                DetailStatCard(icon: "equal.circle", color: .purple, label: "平均延迟", value: String(format: "%.1fms", stats.avgLatency))
            }
            
            // Traffic cards
            HStack(spacing: 12) {
                TrafficCard(icon: "arrow.up.circle.fill", color: .blue, label: "发送流量", value: formatBytes(stats.totalBytesSent))
                TrafficCard(icon: "arrow.down.circle.fill", color: .green, label: "接收流量", value: formatBytes(stats.totalBytesReceived))
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
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ startDate: Date) -> String {
        let interval = Date().timeIntervalSince(startDate)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d小时%d分", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%d分%d秒", minutes, seconds)
        } else {
            return String(format: "%d秒", seconds)
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

// MARK: - 监控 Tab
struct MonitorTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var editingHost: HostConfig?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostCommand = ""
    @State private var newHostRules: [DisplayRule] = []
    @State private var showingAddHost = false

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("监控中主机 (\(viewModel.hosts.count))")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddHost = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView("没有主机", systemImage: "network", description: Text("点击右上角添加主机"))
            } else {
                ScrollView {
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
                                },
                                onDelete: {
                                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                                        viewModel.removeHost(at: index)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAddHost) {
            HostEditorSheet(
                isPresented: $showingAddHost,
                title: "添加主机",
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                onSave: {
                    viewModel.addHost(name: newHostName, address: newHostAddress, command: newHostCommand, displayRules: newHostRules.isEmpty ? nil : newHostRules)
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
                title: "编辑主机",
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                onSave: {
                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                        viewModel.updateHost(at: index, name: newHostName, address: newHostAddress, command: newHostCommand, displayRules: newHostRules)
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
    }
}

struct EditableHostCard: View {
    let host: HostConfig
    let viewModel: PingMonitorViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false
    @State private var isHovered = false
    @State private var breathe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                statusIndicator
                
                Text(host.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                Spacer()
                
                latencyDisplay
            }
            
            Text(host.address)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            // Mini sparkline
            if let stats = viewModel.hostStats[host.id],
               stats.latencyHistory.count > 1 {
                MiniSparkline(
                    points: Array(stats.latencyHistory.suffix(15)),
                    color: statusColor
                )
                .frame(height: 24)
            }
            
            HStack(spacing: 0) {
                rulesSection
                Spacer()
                activeRulesSection
            }
        }
        .frame(height: 140)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    .linearGradient(
                        colors: [
                            statusColor.opacity(isHovered ? 0.08 : 0.04),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovered ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    statusColor.opacity(isHovered ? 0.4 : 0.15),
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: statusColor.opacity(isHovered ? 0.12 : 0.05), radius: isHovered ? 10 : 5, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear { breathe = true }
        .contextMenu {
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
        }
    }
    
    private var statusIndicator: some View {
        ZStack {
            if viewModel.isRunning && host.isReachable {
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(breathe ? 1.5 : 1.0)
                    .opacity(breathe ? 0 : 0.6)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false), value: breathe)
            }
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.5), radius: 3)
        }
    }
    
    @ViewBuilder
    private var latencyDisplay: some View {
        if host.isChecking {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 50, height: 20)
        } else if let latency = host.lastLatency {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                Text("\(Int(latency))ms")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
        } else if viewModel.isRunning {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("超时")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 2) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 10))
                Text("未运行")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.1))
            .clipShape(Capsule())
        }
    }
    
    private var rulesSection: some View {
        Group {
            if !host.displayRules.filter({ $0.enabled }).isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    
                    ForEach(host.displayRules.filter { $0.enabled }.prefix(2)) { rule in
                        Text("\(rule.condition == "less" ? "<" : ">")\(Int(rule.threshold))ms")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    
                    if host.displayRules.filter({ $0.enabled }).count > 2 {
                        Text("+\(host.displayRules.filter({ $0.enabled }).count - 2)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    
    private var activeRulesSection: some View {
        Group {
            let activeRules = host.displayRules.filter { rule in
                guard rule.enabled else { return false }
                guard let latency = host.lastLatency else { return false }
                if rule.condition == "less" {
                    return latency < rule.threshold
                } else {
                    return latency > rule.threshold
                }
            }
            
            if !activeRules.isEmpty {
                HStack(spacing: 4) {
                    ForEach(activeRules.prefix(2)) { rule in
                        Label(rule.label, systemImage: rule.condition == "less" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(rule.condition == "less" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .foregroundStyle(rule.condition == "less" ? .green : .orange)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    private var statusColor: Color {
        guard !host.isChecking else { return .blue }
        guard let latency = host.lastLatency else { return .gray }
        if latency < 50 { return .green }
        if latency < 100 { return .orange }
        return .red
    }
    
    private var statusIcon: String {
        guard !host.isChecking else { return "checkmark" }
        guard let latency = host.lastLatency else { return "circle" }
        if latency < 50 { return "arrow.down" }
        if latency < 100 { return "arrow.right" }
        return "arrow.up"
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
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSection) {
                Text("已保存主机 (\(viewModel.hosts.count))").tag(0)
                Text("预设 (\(viewModel.presets.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedSection == 0 {
                HostsManagementView(viewModel: viewModel)
            } else {
                PresetsManagementView(viewModel: viewModel)
            }
        }
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
    @State private var hoveredHostId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("管理监控主机")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddHost = true
                } label: {
                    Label("添加主机", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView("没有主机", systemImage: "server.rack", description: Text("添加主机开始监控"))
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
                title: "添加主机",
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                onSave: {
                    viewModel.addHost(name: newHostName, address: newHostAddress, command: newHostCommand, displayRules: newHostRules.isEmpty ? nil : newHostRules)
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
                title: "编辑主机",
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                onSave: {
                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                        viewModel.updateHost(at: index, name: newHostName, address: newHostAddress, command: newHostCommand, displayRules: newHostRules)
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
    }
}

struct HostManagementCard: View {
    let host: HostConfig
    let isHovered: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    
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
                    .help("编辑")
                    
                    Button { onDelete() } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("删除")
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
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预设快速添加")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddPreset = true
                } label: {
                    Label("添加预设", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            if viewModel.presets.isEmpty {
                ContentUnavailableView("没有预设", systemImage: "bookmark", description: Text("添加预设快速创建主机"))
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
                title: "添加预设",
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
                title: "编辑预设",
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
                .help("添加到监控")
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
            Button { onAdd() } label: { Label("添加到监控", systemImage: "plus.circle") }
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
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
    let onSave: () -> Void
    @State private var showingAddRule = false

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            ScrollView {
                Form {
                    Section("基本信息") {
                        TextField("名称", text: $name)
                        TextField("地址", text: $address)
                            .textContentType(.URL)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("命令 (可选)", text: $command)
                            Text("留空使用默认: ping -c 1 -W 3 $address")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Section("显示规则") {
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
                            Label("添加规则", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存") {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("启用", isOn: $rule.enabled)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            
            HStack {
                Picker("条件", selection: $rule.condition) {
                    Text("< 小于").tag("less")
                    Text("> 大于").tag("greater")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                
                TextField("阈值(ms)", value: $rule.threshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                TextField("显示文本", text: $rule.label)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddRuleSheet: View {
    @Binding var isPresented: Bool
    @Binding var rules: [DisplayRule]
    @State private var condition = "less"
    @State private var threshold: Double = 100
    @State private var label = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("添加显示规则")
                .font(.headline)
            
            Form {
                Picker("条件", selection: $condition) {
                    Text("延迟小于").tag("less")
                    Text("延迟大于").tag("greater")
                }
                .pickerStyle(.segmented)
                
                HStack {
                    Text("阈值")
                    Spacer()
                    TextField("ms", value: $threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                TextField("显示文本 (如: P2P/转发)", text: $label)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("添加") {
                    rules.append(DisplayRule(condition: condition, threshold: threshold, label: label, enabled: true))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty)
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

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)

            Form {
                TextField("名称", text: $name)
                TextField("地址", text: $address)
                    .textContentType(.URL)
                
                VStack(alignment: .leading, spacing: 4) {
                    TextField("命令 (可选)", text: $command)
                    Text("留空使用默认: ping -c 1 -W 3 $address")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存") {
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
    
    var filteredLogs: [LogManager.LogEntry] {
        if let level = selectedLevel {
            return logManager.logs.filter { $0.level == level }
        }
        return logManager.logs
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("日志级别", selection: $selectedLevel) {
                    Text("全部").tag(nil as LogManager.LogLevel?)
                    ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level as LogManager.LogLevel?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                Spacer()
                
                Button(action: {
                    logManager.clear()
                }) {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                
                Button(action: {
                    if let url = logManager.exportToFile() {
                        exportURL = url
                        showingExportSheet = true
                    }
                }) {
                    Label("导出", systemImage: "square.and.arrow.up")
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
                print("Log exported successfully")
            }
        }
    }
}

struct LogRow: View {
    let entry: LogManager.LogEntry
    
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
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.formattedTimestamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    
                    Text(entry.level.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(levelColor)
                    
                    if let host = entry.host {
                        Text(host)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Text(entry.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
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

    var body: some View {
        Form {
            Section {

                Picker("显示策略", selection: $viewModel.statusBarDisplayMode) {
                    Text("平均延迟").tag(StatusBarDisplayMode.average)
                    Text("最差主机").tag(StatusBarDisplayMode.worst)
                    Text("最快主机").tag(StatusBarDisplayMode.best)
                    Text("首个主机").tag(StatusBarDisplayMode.first)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.statusBarDisplayMode) { _, _ in
                    viewModel.saveSettings()
                }
                
                Text(statusBarDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Toggle("显示延迟数值", isOn: $viewModel.showLatencyInMenu)
                    .onChange(of: viewModel.showLatencyInMenu) { _, _ in
                        viewModel.saveSettings()
                    }

                Toggle("显示规则标签", isOn: $viewModel.showLabelsInMenu)
                    .onChange(of: viewModel.showLabelsInMenu) { _, _ in
                        viewModel.saveSettings()
                    }
            } header: {
                Label("状态栏显示", systemImage: "menubar.rectangle")
            }

            Section {

                HStack {
                    Text("监控间隔")
                    Spacer()
                    Picker("", selection: $viewModel.pingInterval) {
                        Text("3秒").tag(3.0)
                        Text("5秒").tag(5.0)
                        Text("10秒").tag(10.0)
                        Text("30秒").tag(30.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .onChange(of: viewModel.pingInterval) { _, _ in
                    viewModel.saveSettings()
                    if viewModel.isRunning {
                        viewModel.stopAll()
                        viewModel.startAll()
                    }
                }
                
                Picker("日志级别", selection: $viewModel.logLevel) {
                    ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.logLevel) { _, _ in
                    viewModel.saveSettings()
                }
            } header: {
                Label("监控", systemImage: "waveform.path.ecg")
            }

            Section {

                Toggle("启用通知", isOn: $viewModel.notificationEnabled)
                    .onChange(of: viewModel.notificationEnabled) { _, _ in
                        viewModel.saveSettings()
                    }

                Picker("通知方式", selection: $viewModel.notificationType) {
                    Text("系统通知").tag("system")
                    Text("Bark推送").tag("bark")
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.notificationType) { _, _ in
                        viewModel.saveSettings()
                    }

                if viewModel.notificationType == "bark" {
                    TextField("Bark URL", text: $viewModel.barkURL)
                        .onChange(of: viewModel.barkURL) { _, _ in
                            viewModel.saveSettings()
                        }
                }
            } header: {
                Label("通知", systemImage: "bell.badge.fill")
            }

            Section {

                Toggle("开机自启动", isOn: $viewModel.autoStart)
                    .onChange(of: viewModel.autoStart) { _, newValue in
                        viewModel.toggleAutoStart(newValue)
                    }
            } header: {
                Label("系统", systemImage: "gear")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private var statusBarDescription: String {
        switch viewModel.statusBarDisplayMode {
        case .average:
            return "显示所有主机的平均延迟"
        case .worst:
            return "显示延迟最高或不可达的主机"
        case .best:
            return "显示延迟最低的主机"
        case .first:
            return "显示列表中的第一个主机"
        }
    }
}
