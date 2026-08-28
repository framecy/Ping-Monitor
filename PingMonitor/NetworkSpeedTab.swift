import SwiftUI
import Charts

// MARK: - Network Speed Tab Mode
enum NetSpeedTabMode: String, CaseIterable {
    case interfaces
    case processes
}

// MARK: - Network Speed Tab

struct NetworkSpeedTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @StateObject private var speedManager = NetworkSpeedManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var trafficRange: TrafficTimeRange = .oneHour
    @State private var tabMode: NetSpeedTabMode = .interfaces
    /// 默认只展开承载真实流量的两族，其余（管理口、回环等）收起。
    @State private var expandedFamilies: Set<InterfaceFamily> = [.wifi, .ethernet]
    @State private var showResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Switcher
            HStack {
                HStack(spacing: 2) {
                    customTabButton(title: languageManager.t("netspeed.tab.interfaces"), mode: .interfaces)
                    customTabButton(title: languageManager.t("netspeed.tab.processes"), mode: .processes)
                }
                .padding(3)
                .background(Theme.Colors.cardBackground)
                .cornerRadius(Theme.Radius.md)
                .frame(width: 200)
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.cardPadding)
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            // Content
            if tabMode == .interfaces {
                ScrollView {
                    VStack(spacing: 20) {
                        speedOverviewCard
                        speedChartCard
                        topProcessesCard
                        trafficStatsCard
                        trafficTrendCard
                        interfaceDetailsCard
                    }
                    .padding(Theme.Layout.cardPadding)
                }
            } else {
                ProcessListView(speedManager: speedManager)
            }
        }
        .background(Theme.Colors.background)
        .onAppear {
            speedManager.startMonitoring()
            speedManager.startProcessMonitoring()
        }
        .onDisappear {
            if !viewModel.showSpeedInMenu {
                speedManager.stopMonitoring()
            }
            speedManager.stopProcessMonitoring()
        }
    }
    
    private func customTabButton(title: String, mode: NetSpeedTabMode) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                tabMode = mode
            }
        }) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.callout))
                .fontWeight(tabMode == mode ? .semibold : .regular)
                .foregroundStyle(tabMode == mode ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(tabMode == mode ? Theme.Colors.accentBlue : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Speed Overview Card
    
    private var speedOverviewCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: languageManager.t("netspeed.title"), icon: "chart.line.uptrend.xyaxis")
                    Spacer()
                    
                    // Refresh interval selector
                    Picker("", selection: Binding(
                        get: { speedManager.refreshInterval },
                        set: { speedManager.setRefreshInterval($0) }
                    )) {
                        Text("1s").tag(1.0 as TimeInterval)
                        Text("2s").tag(2.0 as TimeInterval)
                        Text("3s").tag(3.0 as TimeInterval)
                        Text("5s").tag(5.0 as TimeInterval)
                        Text("10s").tag(10.0 as TimeInterval)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    
                    // Interface selector
                    Picker("", selection: $speedManager.selectedInterface) {
                        Text(languageManager.t("netspeed.all_interfaces")).tag("all")
                        ForEach(speedManager.interfaces.filter { $0.isActive }) { iface in
                            Text(iface.displayName).tag(iface.id)
                        }
                    }
                    .frame(width: 180)
                }
                
                Divider().opacity(0.15)
                
                HStack(spacing: 0) {
                    // Upload speed
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .bold))
                                .foregroundStyle(Theme.Colors.accentPurple)
                            Text(languageManager.t("netspeed.upload"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        
                        Text(NetworkSpeedManager.formatSpeed(speedManager.totalSpeedOut))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.hero, weight: .bold))
                            .foregroundStyle(Theme.Colors.accentPurple)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(NetworkSpeedManager.formatBytes(speedManager.totalBytesOut))
                                .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 50).opacity(0.2)
                    
                    // Download speed
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 5) {
                            Text(languageManager.t("netspeed.download"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Image(systemName: "arrow.down")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .bold))
                                .foregroundStyle(Theme.Colors.accentCyan)
                        }
                        
                        Text(NetworkSpeedManager.formatSpeed(speedManager.totalSpeedIn))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.hero, weight: .bold))
                            .foregroundStyle(Theme.Colors.accentCyan)
                        
                        HStack(spacing: 4) {
                            Text(NetworkSpeedManager.formatBytes(speedManager.totalBytesIn))
                                .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Image(systemName: "arrow.down.circle")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if speedManager.selectedInterface == "all" {
                    Divider().opacity(0.15)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.t("netspeed.tunnel_row"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            HStack(spacing: 8) {
                                Text("↓ \(NetworkSpeedManager.formatSpeed(speedManager.tunnelSpeedIn))")
                                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.accentCyan)
                                Text("↑ \(NetworkSpeedManager.formatSpeed(speedManager.tunnelSpeedOut))")
                                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.accentPurple)
                            }
                        }

                        Spacer()

                        Text(languageManager.t("netspeed.tunnel_note"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
    }
    
    // MARK: - Speed Chart Card
    
    private var speedChartCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("netspeed.realtime_chart"), icon: "waveform.path.ecg")
                
                if speedManager.speedHistory.count < 2 {
                    Text(languageManager.t("netspeed.collecting"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                } else {
                    let samples = speedManager.speedHistory
                    
                    Chart {
                        // Upload Series
                        ForEach(samples) { sample in
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Upload", sample.speedOut),
                                series: .value("Type", "Upload")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.Colors.accentPurple)
                            
                            AreaMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Upload", sample.speedOut),
                                series: .value("Type", "Upload"),
                                stacking: .unstacked
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentPurple.opacity(0.3), Theme.Colors.accentPurple.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }
                        
                        // Download Series
                        ForEach(samples) { sample in
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Download", sample.speedIn),
                                series: .value("Type", "Download")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.Colors.accentCyan)
                            
                            AreaMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Download", sample.speedIn),
                                series: .value("Type", "Download"),
                                stacking: .unstacked
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentCyan.opacity(0.3), Theme.Colors.accentCyan.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(Theme.Colors.chartGrid)
                            
                            if let speed = value.as(Double.self) {
                                AxisValueLabel {
                                    Text(NetworkSpeedManager.formatSpeed(speed))
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in }
                    }
                    .frame(height: 120)
                    
                    // Legend
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Colors.accentPurple).frame(width: 6, height: 6)
                            Text(languageManager.t("netspeed.upload"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Colors.accentCyan).frame(width: 6, height: 6)
                            Text(languageManager.t("netspeed.download"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Text(languageManager.t("netspeed.last_60s"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
    }
    

    
    private var topProcessesCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: languageManager.t("netspeed.top_processes"), icon: "apps.ipad.hack")
                    Spacer()
                    Button(action: {
                        withAnimation { tabMode = .processes }
                    }) {
                        Text(languageManager.t("monitor.title"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
                
                let topProcs = Array(speedManager.processList.prefix(5))
                
                if topProcs.isEmpty {
                    Text(languageManager.t("netspeed.collecting"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(topProcs) { proc in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(proc.processName)
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text("PID \(proc.pid)")
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    if proc.speedOut > 1024 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "arrow.up")
                                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .bold))
                                                .foregroundStyle(Theme.Colors.accentPurple)
                                            Text(NetworkSpeedManager.formatSpeed(proc.speedOut))
                                                .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .semibold))
                                                .foregroundStyle(Theme.Colors.accentPurple)
                                        }
                                    }
                                    
                                    if proc.speedIn > 1024 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "arrow.down")
                                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .bold))
                                                .foregroundStyle(Theme.Colors.accentCyan)
                                            Text(NetworkSpeedManager.formatSpeed(proc.speedIn))
                                                .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .semibold))
                                                .foregroundStyle(Theme.Colors.accentCyan)
                                        }
                                    }
                                }
                            }
                            
                            if proc.id != topProcs.last?.id {
                                Divider().opacity(0.05)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Interface Details Card
    
    private var interfaceDetailsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("netspeed.interfaces"), icon: "network")
                
                if speedManager.interfaces.isEmpty {
                    Text(languageManager.t("netspeed.no_interfaces"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    // 同族接口合并成一组，默认收起；行底色用半透明色块交替区分。
                    let groups = interfaceGroups
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.family) { index, group in
                            interfaceGroupRow(group, striped: !index.isMultiple(of: 2))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
        }
    }

    // MARK: - 接口分组

    private struct InterfaceGroup {
        let family: InterfaceFamily
        let members: [NetworkInterfaceStats]

        /// 隧道族的成员会对同一份载荷重复计数（链式封装），求和没有物理意义，
        /// 取最忙的一条作为该族的代表速率；其余族的成员互相独立，求和即总量。
        private var isStacked: Bool { family == .tunnel }

        var speedIn: Double {
            isStacked ? (members.map(\.speedIn).max() ?? 0) : members.reduce(0) { $0 + $1.speedIn }
        }
        var speedOut: Double {
            isStacked ? (members.map(\.speedOut).max() ?? 0) : members.reduce(0) { $0 + $1.speedOut }
        }
        var bytesIn: UInt64 {
            isStacked ? (members.map(\.bytesIn).max() ?? 0) : members.reduce(0) { $0 + $1.bytesIn }
        }
        var bytesOut: UInt64 {
            isStacked ? (members.map(\.bytesOut).max() ?? 0) : members.reduce(0) { $0 + $1.bytesOut }
        }
        var hasTraffic: Bool { members.contains { $0.isActive } }
    }

    private var interfaceGroups: [InterfaceGroup] {
        let grouped = Dictionary(grouping: speedManager.interfaces) { $0.family }
        return InterfaceFamily.allCases.compactMap { family in
            guard let members = grouped[family], !members.isEmpty else { return nil }
            return InterfaceGroup(
                family: family,
                members: members.sorted { ($0.speedIn + $0.speedOut) > ($1.speedIn + $1.speedOut) }
            )
        }
    }

    @ViewBuilder
    private func interfaceGroupRow(_ group: InterfaceGroup, striped: Bool) -> some View {
        let isExpanded = expandedFamilies.contains(group.family)

        VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedFamilies.remove(group.family)
                } else {
                    expandedFamilies.insert(group.family)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: 10)

                    Image(systemName: group.family.iconName)
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                        .foregroundStyle(group.hasTraffic ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                        .frame(width: 18)

                    Text(languageManager.t(group.family.localizationKey))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("\(group.members.count)")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.Colors.surfaceOverlay)
                        .cornerRadius(Theme.Radius.xs)

                    if group.members.contains(where: { $0.id == speedManager.defaultRouteInterface }) {
                        Badge(text: languageManager.t("netspeed.default_route"), color: Theme.Colors.accentGreen)
                    }

                    Spacer()

                    speedPair(speedIn: group.speedIn, speedOut: group.speedOut)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(group.members) { iface in
                    interfaceRow(iface)
                }
            }
        }
        .background(striped ? Theme.Colors.surfaceOverlay : Color.clear)
    }

    /// 上/下行速率对，组行与成员行共用。
    private func speedPair(speedIn: Double, speedOut: Double) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(speedOut > 0 ? Theme.Colors.accentPurple : Theme.Colors.textTertiary)
                Text(NetworkSpeedManager.formatSpeed(speedOut))
                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium))
                    .foregroundStyle(speedOut > 0 ? Theme.Colors.accentPurple : Theme.Colors.textTertiary)
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(speedIn > 0 ? Theme.Colors.accentCyan : Theme.Colors.textTertiary)
                Text(NetworkSpeedManager.formatSpeed(speedIn))
                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium))
                    .foregroundStyle(speedIn > 0 ? Theme.Colors.accentCyan : Theme.Colors.textTertiary)
            }
        }
    }

    private func interfaceRow(_ iface: NetworkInterfaceStats) -> some View {
        HStack(spacing: 12) {
            // Interface icon + name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(iface.isActive ? Theme.Colors.accentGreen : Theme.Colors.textTertiary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(iface.displayName)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(iface.isActive ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .lineLimit(1)
                    if iface.role == .tunnel {
                        Badge(text: "Tunnel", color: Theme.Colors.accentPurple)
                    } else if iface.role == .physical {
                        Badge(text: "Physical", color: Theme.Colors.accentBlue)
                    }
                }
                
                // Errors
                if iface.errorsIn > 0 || iface.errorsOut > 0 {
                    Text("Errors: ↑\(iface.errorsOut) ↓\(iface.errorsIn)")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.accentOrange)
                }
            }
            .frame(minWidth: 110, alignment: .leading)
            
            Spacer()
            
            // Speed
            HStack(spacing: 16) {
                // Upload
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.accentPurple)
                        Text(NetworkSpeedManager.formatSpeed(iface.speedOut))
                            .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium))
                            .foregroundStyle(iface.speedOut > 0 ? Theme.Colors.accentPurple : Theme.Colors.textTertiary)
                    }
                    Text(NetworkSpeedManager.formatBytes(iface.bytesOut))
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                // Download
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.accentCyan)
                        Text(NetworkSpeedManager.formatSpeed(iface.speedIn))
                            .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium))
                            .foregroundStyle(iface.speedIn > 0 ? Theme.Colors.accentCyan : Theme.Colors.textTertiary)
                    }
                    Text(NetworkSpeedManager.formatBytes(iface.bytesIn))
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                // Packets
                VStack(alignment: .trailing, spacing: 1) {
                    Text("PKT ↑\(formatPackets(iface.packetsOut))")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("PKT ↓\(formatPackets(iface.packetsIn))")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            speedManager.selectedInterface = (speedManager.selectedInterface == iface.id) ? "all" : iface.id
        }
        .background(speedManager.selectedInterface == iface.id ? Theme.Colors.accentBlue.opacity(0.10) : Color.clear)
    }
    
    private func formatPackets(_ count: UInt64) -> String {
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fK", Double(count) / 1000) }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }
    
    // MARK: - Traffic Stats Card
    
    private var trafficStatsCard: some View {
        let totals = speedManager.trafficTotals(for: trafficRange)
        let totalBytes = totals.bytesIn + totals.bytesOut
        
        return ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: languageManager.t("netspeed.traffic_stats"), icon: "chart.bar.fill")
                    Spacer()
                    Picker("", selection: $trafficRange) {
                        ForEach(TrafficTimeRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                
                Divider().opacity(0.15)
                
                HStack(spacing: 12) {
                    trafficStatItem(
                        icon: "arrow.down.circle.fill",
                        color: Theme.Colors.accentCyan,
                        label: languageManager.t("netspeed.total_download"),
                        value: NetworkSpeedManager.formatBytes(totals.bytesIn)
                    )
                    
                    trafficStatItem(
                        icon: "arrow.up.circle.fill",
                        color: Theme.Colors.accentPurple,
                        label: languageManager.t("netspeed.total_upload"),
                        value: NetworkSpeedManager.formatBytes(totals.bytesOut)
                    )
                    
                    trafficStatItem(
                        icon: "arrow.up.arrow.down.circle.fill",
                        color: Theme.Colors.accentOrange,
                        label: languageManager.t("netspeed.total_traffic"),
                        value: NetworkSpeedManager.formatBytes(totalBytes)
                    )
                }
            }
        }
    }
    
    private func trafficStatItem(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(Theme.Fonts.icon(Theme.Fonts.Size.display))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.title, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(color.opacity(0.06))
        )
    }
    
    // MARK: - Traffic Trend Card
    
    private var trafficTrendCard: some View {
        let snapshots = speedManager.trafficSnapshots(for: trafficRange)
        let totals = speedManager.trafficTotals(for: trafficRange)
        
        return ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: languageManager.t("netspeed.traffic_trend"), icon: "waveform.path.ecg.rectangle")
                    Spacer()
                    
                    Button {
                        speedManager.exportTrafficStats(for: trafficRange)
                    } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .help(languageManager.t("stats.export_current"))
                    
                    Button {
                        showResetConfirmation = true
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.accentRed)
                    .help(languageManager.t("stats.reset_current"))
                    .alert(languageManager.t("stats.reset_current"), isPresented: $showResetConfirmation) {
                        Button(role: .destructive) {
                            speedManager.resetTrafficStats()
                        } label: {
                            Text(languageManager.t("common.confirm"))
                        }
                        Button(languageManager.t("common.cancel"), role: .cancel) {}
                    } message: {
                        Text(languageManager.t("stats.reset_confirm_message"))
                    }
                }
                
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                        Text(languageManager.t("netspeed.total_download") + ":")
                        Text(NetworkSpeedManager.formatBytes(totals.bytesIn))
                            .foregroundStyle(Theme.Colors.accentCyan)
                    }
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                        Text(languageManager.t("netspeed.total_upload") + ":")
                        Text(NetworkSpeedManager.formatBytes(totals.bytesOut))
                            .foregroundStyle(Theme.Colors.accentPurple)
                    }
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text(languageManager.t("netspeed.total_traffic") + ":")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(NetworkSpeedManager.formatBytes(totals.bytesIn + totals.bytesOut))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .bold()
                    }
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                }
                .padding(.bottom, 4)
                
                if snapshots.count < 2 {
                    Text(languageManager.t("netspeed.collecting"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                } else {
                    Chart {
                        // Upload Series
                        ForEach(snapshots) { snap in
                            let date = Date(timeIntervalSince1970: snap.timestamp)
                            
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Upload", snap.speedOut),
                                series: .value("Type", "Upload")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.Colors.accentPurple)
                            
                            AreaMark(
                                x: .value("Time", date),
                                y: .value("Upload", snap.speedOut),
                                series: .value("Type", "Upload"),
                                stacking: .unstacked
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentPurple.opacity(0.25), Theme.Colors.accentPurple.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }
                        
                        // Download Series
                        ForEach(snapshots) { snap in
                            let date = Date(timeIntervalSince1970: snap.timestamp)
                            
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Download", snap.speedIn),
                                series: .value("Type", "Download")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.Colors.accentCyan)
                            
                            AreaMark(
                                x: .value("Time", date),
                                y: .value("Download", snap.speedIn),
                                series: .value("Type", "Download"),
                                stacking: .unstacked
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.Colors.accentCyan.opacity(0.25), Theme.Colors.accentCyan.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(Theme.Colors.chartGrid)
                            
                            if let speed = value.as(Double.self) {
                                AxisValueLabel {
                                    Text(NetworkSpeedManager.formatSpeed(speed))
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(formatTime(date.timeIntervalSince1970))
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(height: 140)
                }

            }
        }
    }
    

    
    private func formatTime(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = trafficRange == .sevenDays ? "MM/dd" : "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Process List View

struct ProcessListView: View {
    @ObservedObject var speedManager: NetworkSpeedManager
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var searchText = ""
    @State private var expandedPIDs: Set<Int32> = []
    @State private var killTarget: ProcessSummary? = nil
    @State private var showKillAlert = false
    @State private var killResultMessage: String? = nil
    
    private var filteredProcesses: [ProcessSummary] {
        if searchText.isEmpty { return speedManager.processList }
        let query = searchText.lowercased()
        return speedManager.processList.filter {
            $0.processName.lowercased().contains(query) ||
            String($0.pid).contains(query) ||
            $0.user.lowercased().contains(query) ||
            $0.connections.contains { conn in
                conn.localPort.contains(query) ||
                conn.remotePort.contains(query) ||
                conn.remoteAddress.contains(query) ||
                conn.localAddress.contains(query)
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search & Refresh bar
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.footnote))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField(languageManager.t("netspeed.process.search"), text: $searchText)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.Colors.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                    )
                    
                    Button(action: { speedManager.refreshProcessList() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            Text(languageManager.t("netspeed.process.refresh"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Theme.Colors.accentBlue.opacity(0.12))
                        )
                        .foregroundStyle(Theme.Colors.accentBlue)
                    }
                    .buttonStyle(.plain)
                    
                    // Summary badge
                    Text("\(filteredProcesses.count) \(languageManager.t("netspeed.tab.processes"))")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                if filteredProcesses.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "network.slash")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.hero))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(languageManager.t("netspeed.process.no_connections"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.callout))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredProcesses) { proc in
                            processCard(proc)
                        }
                    }
                }
            }
            .padding(Theme.Layout.cardPadding)
        }
        .alert(isPresented: $showKillAlert) {
            Alert(
                title: Text(languageManager.t("netspeed.process.kill")),
                message: Text(String(format: languageManager.t("netspeed.process.kill_confirm"),
                                     killTarget?.processName ?? "", killTarget?.pid ?? 0)),
                primaryButton: .destructive(Text(languageManager.t("netspeed.process.kill"))) {
                    if let target = killTarget {
                        speedManager.killProcess(pid: target.pid) { success in
                            killResultMessage = success
                                ? languageManager.t("netspeed.process.kill_success")
                                : languageManager.t("netspeed.process.kill_failed")
                            // Auto-clear after 2s
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                killResultMessage = nil
                            }
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .overlay(alignment: .bottom) {
            if let msg = killResultMessage {
                Text(msg)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(msg.contains(languageManager.t("netspeed.process.kill_success")) ? Theme.Colors.accentGreen : Theme.Colors.accentRed))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: killResultMessage)
        .onAppear { speedManager.startProcessMonitoring() }
    }
    
    // MARK: - Process Card
    
    private func processCard(_ proc: ProcessSummary) -> some View {
        let isExpanded = expandedPIDs.contains(proc.pid)
        
        return ModernCard {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 10) {
                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: 14)
                    
                    // Process icon
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(processColor(proc.processName).opacity(0.15))
                            .frame(width: 28, height: 28)
                        Text(String(proc.processName.prefix(1)).uppercased())
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .bold))
                            .foregroundStyle(processColor(proc.processName))
                    }
                    
                    // Name + PID
                    VStack(alignment: .leading, spacing: 1) {
                        Text(proc.processName)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text("PID \(proc.pid)")
                                .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(proc.user)
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    
                    // Real-time Speed
                    if proc.totalSpeed > 100 { // Only show if more than 100B/s
                        HStack(spacing: 8) {
                            if proc.speedOut > 10 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up")
                                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .bold))
                                        .foregroundStyle(Theme.Colors.accentPurple)
                                    Text(NetworkSpeedManager.formatSpeed(proc.speedOut))
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.accentPurple)
                                }
                            }
                            if proc.speedIn > 10 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down")
                                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .bold))
                                        .foregroundStyle(Theme.Colors.accentCyan)
                                    Text(NetworkSpeedManager.formatSpeed(proc.speedIn))
                                        .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.accentCyan)
                                }
                            }
                        }
                        .padding(.leading, 4)
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    // Connection stats badges
                    HStack(spacing: 6) {
                        ForEach(Array(proc.protocols).sorted(), id: \.self) { proto in
                            Badge(text: proto, color: proto == "TCP" ? Theme.Colors.accentBlue : Theme.Colors.accentOrange)
                        }
                        
                        Badge(text: "\(proc.connectionCount) \(languageManager.t("netspeed.process.connections"))",
                              color: Theme.Colors.accentCyan)
                        
                        if proc.establishedCount > 0 {
                            Badge(text: "\(proc.establishedCount) EST", color: Theme.Colors.accentGreen)
                        }
                    }
                    
                    // Kill button
                    Button(action: {
                        killTarget = proc
                        showKillAlert = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                            .foregroundStyle(Theme.Colors.accentRed.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("netspeed.process.kill"))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedPIDs.remove(proc.pid)
                        } else {
                            expandedPIDs.insert(proc.pid)
                        }
                    }
                }
                
                // Expanded connections
                if isExpanded {
                    Divider().opacity(0.1).padding(.vertical, 6)
                    
                    // Connection table header
                    HStack(spacing: 0) {
                        Text(languageManager.t("netspeed.process.protocol"))
                            .frame(width: 50, alignment: .leading)
                        Text(languageManager.t("netspeed.process.local"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(languageManager.t("netspeed.process.remote"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(languageManager.t("netspeed.process.state"))
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    
                    ForEach(proc.connections) { conn in
                        connectionRow(conn)
                    }
                }
            }
        }
    }
    
    // MARK: - Connection Row
    
    private func connectionRow(_ conn: ProcessNetworkInfo) -> some View {
        HStack(spacing: 0) {
            // Protocol
            Text(conn.protocolType)
                .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium))
                .foregroundStyle(conn.protocolType == "TCP" ? Theme.Colors.accentBlue : Theme.Colors.accentOrange)
                .frame(width: 50, alignment: .leading)
            
            // Local address:port
            VStack(alignment: .leading, spacing: 0) {
                Text(conn.localAddress.isEmpty ? "*" : conn.localAddress)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if !conn.localPort.isEmpty && conn.localPort != "*" {
                    Text(":\(conn.localPort)")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accentPurple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Arrow
            if !conn.remoteAddress.isEmpty {
                Image(systemName: "arrow.right")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 4)
            }
            
            // Remote address:port
            VStack(alignment: .leading, spacing: 0) {
                Text(conn.remoteAddress.isEmpty ? "-" : conn.remoteAddress)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if !conn.remotePort.isEmpty && conn.remotePort != "*" {
                    Text(":\(conn.remotePort)")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accentCyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // State badge
            Text(conn.state)
                .font(Theme.Fonts.number(Theme.Fonts.Size.micro, weight: .medium))
                .foregroundStyle(stateColor(conn.state))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(stateColor(conn.state).opacity(0.1))
                .cornerRadius(Theme.Radius.xs)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xs)
                .fill(Theme.Colors.surfaceOverlay)
        )
    }
    
    // MARK: - Helpers
    
    private func processColor(_ name: String) -> Color {
        let colors: [Color] = [
            Theme.Colors.accentBlue, Theme.Colors.accentPurple, Theme.Colors.accentCyan,
            Theme.Colors.accentOrange, Theme.Colors.accentGreen, Theme.Colors.accentRed,
            Theme.Colors.accentIndigo, Theme.Colors.accentMint, Theme.Colors.accentTeal, Theme.Colors.accentPink
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
    
    private func stateColor(_ state: String) -> Color {
        switch state {
        case "ESTABLISHED": return Theme.Colors.accentGreen
        case "LISTEN": return Theme.Colors.accentBlue
        case "CLOSE_WAIT", "TIME_WAIT": return Theme.Colors.accentOrange
        case "SYN_SENT", "SYN_RECEIVED": return Theme.Colors.accentCyan
        case "FIN_WAIT_1", "FIN_WAIT_2", "CLOSING", "LAST_ACK": return Theme.Colors.accentRed
        default: return Theme.Colors.textTertiary
        }
    }
}
