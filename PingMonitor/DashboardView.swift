import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    
    var body: some View {
        ScrollView {
            Grid(horizontalSpacing: Theme.Layout.gridSpacing, verticalSpacing: Theme.Layout.gridSpacing) {
                // Row 1: Running Status & Network Status
                GridRow {
                    RunningStatusCard(viewModel: viewModel)
                        .gridCellColumns(1)
                    NetworkStatusCard(viewModel: viewModel)
                        .gridCellColumns(1)
                }
                .frame(minHeight: 180)
                
                // Row 2: Traffic Stats & Traffic Trend
                GridRow {
                    TrafficAndLatencyCard(viewModel: viewModel)
                        .gridCellColumns(1)
                    TrafficTrendCard(viewModel: viewModel)
                        .gridCellColumns(1)
                }
                .frame(minHeight: 220)
                
                // Row 3: Summary & Ranking
                GridRow {
                    SummaryDonutCard(viewModel: viewModel)
                        .gridCellColumns(1)
                    RankingListCard(viewModel: viewModel)
                        .gridCellColumns(1)
                }
                .frame(minHeight: 220)
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
    }
}

// MARK: - Components

struct RunningStatusCard: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    
    // Get real memory usage
    private var memoryUsage: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "N/A" }
        let bytes = info.resident_size
        let mb = Double(bytes) / 1024.0 / 1024.0
        if mb >= 100 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f MB", mb)
    }
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(Theme.Colors.accentBlue)
                    Text(languageManager.t("dashboard.running_status"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Circle()
                        .fill(viewModel.isRunning ? Theme.Colors.accentGreen : Theme.Colors.textSecondary)
                        .frame(width: 8, height: 8)
                }
                .padding(.bottom, 16)
                
                HStack(spacing: 0) {
                    StatItem(
                        icon: "clock",
                        label: languageManager.t("dashboard.uptime"),
                        value: viewModel.isRunning ? languageManager.t("dashboard.running") : languageManager.t("header.stopped"),
                        color: Theme.Colors.accentBlue
                    )
                    Divider().frame(height: 30).padding(.horizontal, 10).opacity(0.3)
                    StatItem(
                        icon: "link",
                        label: languageManager.t("dashboard.hosts_count"),
                        value: "\(viewModel.hosts.count)",
                        color: Theme.Colors.accentOrange
                    )
                    Divider().frame(height: 30).padding(.horizontal, 10).opacity(0.3)
                    StatItem(
                        icon: "memorychip",
                        label: languageManager.t("dashboard.memory"),
                        value: memoryUsage,
                        color: Theme.Colors.accentGreen
                    )
                    
                }
                
                Spacer()
                
                // System Info Placeholder
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text(languageManager.t("dashboard.system"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("macOS")
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    VStack(alignment: .leading) {
                        Text(languageManager.t("dashboard.version"))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                         if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text(version)
                                .font(Theme.Fonts.body(12))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(label)
                    .font(Theme.Fonts.body(10))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(value)
                .font(Theme.Fonts.display(18)) // Adjusted font for fit
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NetworkStatusCard: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(Theme.Colors.accentGreen)
                    Text(languageManager.t("dashboard.network_status"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                .padding(.bottom, 16)
                
                // Display avg latencies for top 3 hosts or aggregated
                let sortedHosts = viewModel.hosts.sorted {
                    ($0.lastLatency ?? 9999) < ($1.lastLatency ?? 9999)
                }.prefix(3)
                
                HStack(spacing: 0) {
                    if sortedHosts.isEmpty {
                        Text(languageManager.t("dashboard.no_data"))
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(sortedHosts.enumerated()), id: \.element.id) { index, host in
                            if index > 0 {
                                Divider().frame(height: 30).padding(.horizontal, 10).opacity(0.3)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    Text(host.name)
                                        .font(Theme.Fonts.body(10))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                                if let latency = host.lastLatency {
                                    Text("\(Int(latency)) ms")
                                        .font(Theme.Fonts.display(18))
                                        .foregroundStyle(latency < 50 ? Theme.Colors.accentGreen : (latency < 100 ? Theme.Colors.accentOrange : Theme.Colors.accentRed))
                                } else {
                                    Text("---")
                                        .font(Theme.Fonts.display(18))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                
                Spacer()
                
                // Network Info Placeholder
                 HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(Theme.Colors.accentBlue)
                    Text(languageManager.t("dashboard.network_wifi"))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("Wi-Fi") // Dynamic implementation would require more extensive networking code
                         .font(Theme.Fonts.body(12))
                         .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }
}

struct TrafficAndLatencyCard: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    
    // Aggregate latency history from all hosts to show a trend
    var avgLatencyHistory: [Double] {
        // Simplified: take the latency history of the first host for now, or calculate average
         // In a real app with many hosts, calculating the average of all histories at each point is complex.
         // Here we'll just use the first available host or empty
        guard let firstHost = viewModel.hosts.first(where: { viewModel.hostStats[$0.id]?.latencyHistory.isEmpty == false }) else { return [] }
        return viewModel.hostStats[firstHost.id]?.latencyHistory.suffix(30).map { $0.latency } ?? []
    }
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(Theme.Colors.accentBlue)
                    Text(languageManager.t("dashboard.latency_trend"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                Spacer()
                
                if avgLatencyHistory.isEmpty {
                     Text(languageManager.t("dashboard.no_data"))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Chart {
                         ForEach(Array(avgLatencyHistory.enumerated()), id: \.offset) { index, latency in
                            LineMark(
                                x: .value("Index", index),
                                y: .value("Latency", latency)
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
                                x: .value("Index", index),
                                y: .value("Latency", latency)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentBlue.opacity(0.3), Theme.Colors.accentBlue.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [5, 5]))
                                .foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .font(.system(size: 9))
                        }
                    }
                     .chartXAxis {
                         AxisMarks { _ in
                             // Hide X axis labels for clean look
                         }
                     }
                }
            }
        }
    }
}

struct TrafficTrendCard: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    
    // Improved Mock data for visual consistency
    let data: [Double] = [50, 60, 45, 80, 70, 65, 55]
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    var body: some View {
        ModernCard {
             VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(Theme.Colors.accentOrange)
                    Text(languageManager.t("dashboard.seven_day_trend")) // Mock title
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                 
                 VStack(alignment: .leading) {
                      Text(languageManager.t("dashboard.daily_avg"))
                         .font(Theme.Fonts.body(10))
                         .foregroundStyle(Theme.Colors.textSecondary)
                      Text("45.2 ms") // Mock value
                         .font(Theme.Fonts.display(24))
                         .foregroundStyle(Theme.Colors.textPrimary)
                 }
                 .padding(.vertical, 8)
                
                Spacer()
                
                Chart {
                     ForEach(0..<data.count, id: \.self) { index in
                        BarMark(
                            x: .value("Day", days[index]),
                            y: .value("Value", data[index])
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Theme.Colors.accentOrange, Theme.Colors.accentRed],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }
                    
                    RuleMark(y: .value("Average", 55))
                        .foregroundStyle(Theme.Colors.accentBlue)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Avg")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.Colors.accentBlue)
                        }
                }
                 .chartYAxis(.hidden)
                 .chartXAxis {
                     AxisMarks { value in
                         AxisValueLabel()
                             .foregroundStyle(Theme.Colors.textSecondary)
                             .font(.system(size: 9))
                     }
                 }
            }
        }
    }
}

struct SummaryDonutCard: View {
     @ObservedObject var viewModel: PingMonitorViewModel
     @ObservedObject private var languageManager = LanguageManager.shared
     @State private var hoveredSlice: Int? = nil
    
    // Compute real stats
    private var totalPings: Int {
        viewModel.hostStats.values.reduce(0) { $0 + $1.totalPings }
    }
    private var successPings: Int {
        viewModel.hostStats.values.reduce(0) { $0 + $1.successfulPings }
    }
    private var failedPings: Int {
        viewModel.hostStats.values.reduce(0) { $0 + $1.failedPings }
    }
    private var timeoutPings: Int {
        max(0, totalPings - successPings - failedPings)
    }
    
    private var slices: [(label: String, value: Double, color: Color)] {
        let total = Double(max(totalPings, 1))
        return [
            (languageManager.t("dashboard.success"), Double(successPings) / total, Theme.Colors.accentGreen),
            (languageManager.t("dashboard.failed"), Double(failedPings) / total, Theme.Colors.accentRed),
            (languageManager.t("dashboard.timeout"), Double(timeoutPings) / total, Theme.Colors.accentOrange),
        ]
    }
    
    var body: some View {
        ModernCard {
             VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .foregroundStyle(Theme.Colors.accentPurple)
                    Text(languageManager.t("dashboard.ping_summary"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                
                HStack(spacing: 8) {
                    // 3D Pie Chart
                    ZStack {
                        Pie3DView(slices: slices, hoveredSlice: $hoveredSlice)
                            .frame(width: 140, height: 140)
                        
                        // Center label
                        VStack(spacing: 2) {
                            Text(languageManager.t("dashboard.total"))
                                .font(Theme.Fonts.body(9))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("\(totalPings)")
                                .font(Theme.Fonts.display(14))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .offset(y: -10)
                    }
                    .padding(.vertical, 4)
                    
                    Spacer(minLength: 0)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            LegendItem(
                                color: slice.color,
                                label: slice.label,
                                value: String(format: "%.1f%%", slice.value * 100),
                                isHovered: hoveredSlice == index
                            )
                            .onHover { isHovering in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    hoveredSlice = isHovering ? index : nil
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - 3D Pie Chart

struct Pie3DView: View {
    let slices: [(label: String, value: Double, color: Color)]
    @Binding var hoveredSlice: Int?
    
    // 3D projection parameters
    private let radius: CGFloat = 65
    private let yScale: CGFloat = 0.5      // elliptical squash for perspective
    private let depth: CGFloat = 20          // thickness of the 3D extrusion
    private let gapAngle: Double = 0.04      // gap between slices in radians
    
    private var sliceAngles: [(start: Double, end: Double)] {
        var angles: [(start: Double, end: Double)] = []
        var current: Double = -.pi / 2
        for slice in slices {
            let sliceAngle = max(0, slice.value * 2 * .pi - gapAngle)
            angles.append((start: current + gapAngle / 2, end: current + gapAngle / 2 + sliceAngle))
            current += slice.value * 2 * .pi
        }
        return angles
    }
    
    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2 - depth / 4
            let angles = sliceAngles
            
            // Draw order back to front
            
            // 1) Outer side walls
            for (index, ang) in angles.enumerated() {
                let isHov = hoveredSlice == index
                let hoverOffset = isHov ? hoverOffsetFor(ang) : CGSize.zero
                drawOuterSideWall(context: &context, cx: cx + hoverOffset.width, cy: cy + hoverOffset.height, startAngle: ang.start, endAngle: ang.end, color: slices[index].color)
            }
            
            // 2) Cut side walls (start and end cuts)
            for (index, ang) in angles.enumerated() {
                let isHov = hoveredSlice == index
                let hoverOffset = isHov ? hoverOffsetFor(ang) : CGSize.zero
                drawCutWalls(context: &context, cx: cx + hoverOffset.width, cy: cy + hoverOffset.height, startAngle: ang.start, endAngle: ang.end, color: slices[index].color)
            }
            
            // 3) Top face
            for (index, ang) in angles.enumerated() {
                let isHov = hoveredSlice == index
                let hoverOffset = isHov ? hoverOffsetFor(ang) : CGSize.zero
                drawTopFace(context: &context, cx: cx + hoverOffset.width, cy: cy + hoverOffset.height, startAngle: ang.start, endAngle: ang.end, color: slices[index].color, isHovered: isHov)
            }
            
            // 4) Top highlight
            for (index, ang) in angles.enumerated() {
                let isHov = hoveredSlice == index
                let hoverOffset = isHov ? hoverOffsetFor(ang) : CGSize.zero
                drawTopHighlight(context: &context, cx: cx + hoverOffset.width, cy: cy + hoverOffset.height, startAngle: ang.start, endAngle: ang.end, isHovered: isHov)
            }
        }
    }
    
    private func hoverOffsetFor(_ ang: (start: Double, end: Double)) -> CGSize {
        let mid = (ang.start + ang.end) / 2
        return CGSize(width: cos(mid) * 8, height: sin(mid) * 8 * yScale)
    }
    
    private func point(_ angle: Double, radius r: CGFloat, cx: CGFloat, cy: CGFloat, yOff: CGFloat = 0) -> CGPoint {
        CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r * yScale + yOff)
    }
    
    private func drawOuterSideWall(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, startAngle: Double, endAngle: Double, color: Color) {
        let steps = 40
        let angleStep = (endAngle - startAngle) / Double(steps)
        
        for i in 0..<steps {
            let a1 = startAngle + Double(i) * angleStep
            let a2 = a1 + angleStep
            let midA = (a1 + a2) / 2
            if sin(midA) <= -0.1 { continue } // skip back-facing walls
            
            var wallPath = Path()
            let topLeft = point(a1, radius: radius, cx: cx, cy: cy)
            let topRight = point(a2, radius: radius, cx: cx, cy: cy)
            let botRight = point(a2, radius: radius, cx: cx, cy: cy, yOff: depth)
            let botLeft = point(a1, radius: radius, cx: cx, cy: cy, yOff: depth)
            wallPath.move(to: topLeft)
            wallPath.addLine(to: topRight)
            wallPath.addLine(to: botRight)
            wallPath.addLine(to: botLeft)
            wallPath.closeSubpath()
            
            let shade = 0.35 + 0.25 * (1 + cos(midA - .pi / 3)) / 2
            context.fill(wallPath, with: .color(color.opacity(shade)))
        }
    }
    
    private func drawCutWalls(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, startAngle: Double, endAngle: Double, color: Color) {
        // Start cut (facing viewer if its left side is exposed)
        let startNormal = startAngle - .pi/2
        if sin(startNormal) > 0 {
            var path = Path()
            let centerTop = CGPoint(x: cx, y: cy)
            let centerBot = CGPoint(x: cx, y: cy + depth)
            let outerTop = point(startAngle, radius: radius, cx: cx, cy: cy)
            let outerBot = point(startAngle, radius: radius, cx: cx, cy: cy, yOff: depth)
            path.move(to: centerTop)
            path.addLine(to: outerTop)
            path.addLine(to: outerBot)
            path.addLine(to: centerBot)
            path.closeSubpath()
            let shade = 0.25 + 0.15 * (1 + cos(startNormal)) / 2
            context.fill(path, with: .color(color.opacity(shade)))
        }
        
        // End cut (facing viewer if its right side is exposed)
        let endNormal = endAngle + .pi/2
        if sin(endNormal) > 0 {
            var path = Path()
            let centerTop = CGPoint(x: cx, y: cy)
            let centerBot = CGPoint(x: cx, y: cy + depth)
            let outerTop = point(endAngle, radius: radius, cx: cx, cy: cy)
            let outerBot = point(endAngle, radius: radius, cx: cx, cy: cy, yOff: depth)
            path.move(to: centerTop)
            path.addLine(to: outerTop)
            path.addLine(to: outerBot)
            path.addLine(to: centerBot)
            path.closeSubpath()
            let shade = 0.25 + 0.15 * (1 + cos(endNormal)) / 2
            context.fill(path, with: .color(color.opacity(shade)))
        }
    }
    
    private func drawTopFace(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, startAngle: Double, endAngle: Double, color: Color, isHovered: Bool) {
        let steps = 60
        let angleStep = (endAngle - startAngle) / Double(steps)
        
        var topPath = Path()
        topPath.move(to: CGPoint(x: cx, y: cy))
        for i in 0...steps {
            let a = startAngle + Double(i) * angleStep
            topPath.addLine(to: point(a, radius: radius, cx: cx, cy: cy))
        }
        topPath.closeSubpath()
        
        let brightness: CGFloat = isHovered ? 1.15 : 1.0
        let midAngle = (startAngle + endAngle) / 2
        let gradStart = point(midAngle - 0.5, radius: radius, cx: cx, cy: cy)
        let gradEnd = point(midAngle + 0.5, radius: radius, cx: cx, cy: cy)
        
        context.fill(topPath, with: .linearGradient(
            Gradient(colors: [
                adjustBrightness(color, by: brightness * 1.1),
                adjustBrightness(color, by: brightness * 0.85)
            ]),
            startPoint: gradStart,
            endPoint: gradEnd
        ))
        
        if isHovered {
            context.fill(topPath, with: .color(Color.white.opacity(0.12)))
        }
    }
    
    private func drawTopHighlight(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, startAngle: Double, endAngle: Double, isHovered: Bool) {
        let highlightStart = max(startAngle, -.pi)
        let highlightEnd = min(endAngle, -0.1)
        guard highlightStart < highlightEnd else { return }
        
        let steps = 30
        let angleStep = (highlightEnd - highlightStart) / Double(steps)
        
        var hlPath = Path()
        let hlOuter = radius * 0.9
        
        hlPath.move(to: CGPoint(x: cx, y: cy))
        for i in 0...steps {
            let a = highlightStart + Double(i) * angleStep
            hlPath.addLine(to: point(a, radius: hlOuter, cx: cx, cy: cy))
        }
        hlPath.closeSubpath()
        
        context.fill(hlPath, with: .color(Color.white.opacity(isHovered ? 0.22 : 0.12)))
    }
    
    private func adjustBrightness(_ color: Color, by factor: CGFloat) -> Color {
        if factor > 1.0 { return color.opacity(1.0) }
        return color.opacity(Double(factor))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String
    var isHovered: Bool = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: isHovered ? 8 : 6, height: isHovered ? 8 : 6)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
            Text(label)
                .font(Theme.Fonts.body(11))
                .foregroundStyle(isHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.body(11))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fontWeight(isHovered ? .bold : .regular)
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}


struct RankingListCard: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading) {
                 HStack {
                    Image(systemName: "list.number")
                        .foregroundStyle(Theme.Colors.accentRed)
                    Text(languageManager.t("dashboard.latency_ranking"))
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }
                .padding(.bottom, 8)
                
                VStack(spacing: 12) {
                     // Sort hosts by latency
                    let sorted = viewModel.hosts.sorted { ($0.lastLatency ?? 9999) < ($1.lastLatency ?? 9999) }.prefix(5)
                    
                    if sorted.isEmpty {
                        Text(languageManager.t("dashboard.no_data"))
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Grid(horizontalSpacing: 8, verticalSpacing: 12) {
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, host in
                                GridRow {
                                    Text("\(index + 1)")
                                        .font(Theme.Fonts.number(12))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Theme.Colors.accentBlue)
                                        .cornerRadius(4)
                                        .gridColumnAlignment(.leading)
                                    
                                    Text(host.name)
                                        .font(Theme.Fonts.body(12))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: 80, alignment: .leading)
                                        .gridColumnAlignment(.leading)
                                    
                                    // Visualization Bar
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Theme.Colors.cardBackground.opacity(0.5))
                                            
                                            if let latency = host.lastLatency {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Theme.Colors.accentBlue, Theme.Colors.accentPurple],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                     .frame(width: min(CGFloat(latency) / 200.0 * geometry.size.width, geometry.size.width))
                                            }
                                        }
                                    }
                                    .frame(height: 4)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 4)
                                    
                                    Text(String(format: "%.0f ms", host.lastLatency ?? 0))
                                        .font(Theme.Fonts.number(12))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 50, alignment: .trailing)
                                        .gridColumnAlignment(.trailing)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
