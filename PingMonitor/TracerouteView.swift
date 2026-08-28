import SwiftUI

struct TracerouteView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @StateObject private var manager = TracerouteManager()
    @State private var targetHost = ""
    @State private var showCopied = false
    @State private var tableContentWidth: CGFloat = 640
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            if manager.hops.isEmpty && !manager.isRunning {
                // Empty state
                emptyStateView
            } else {
                // Results
                VSplitView {
                    TracerouteMapView(manager: manager)
                        .frame(minHeight: 200, idealHeight: 300)
                        
                    ScrollView {
                        VStack(spacing: 16) {
                            // Status bar
                            statusBar

                            if manager.isNSLookupRunning || manager.nsLookupResult != nil || manager.nsLookupError != nil {
                                nsLookupSection
                            }
                            
                            // Hop table
                            hopTableView
                        }
                        .padding()
                    }
                    .frame(minHeight: 200)
                }
            }
        }
        .background(Theme.Colors.background)
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        VStack(spacing: 12) {
            if !manager.hops.isEmpty || manager.isRunning {
                HStack {
                    Button(action: {
                        manager.stop()
                        manager.clear()
                        targetHost = ""
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            Text(languageManager.t("common.back"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.cardBackground)
                        )
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Host input
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .foregroundStyle(Theme.Colors.accentBlue)
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                        
                        TextField(languageManager.t("traceroute.input_placeholder"), text: $targetHost)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.number(Theme.Fonts.Size.callout))
                            .onSubmit {
                                if !manager.isRunning {
                                    manager.startTrace(host: targetHost)
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.cardBackground)
                    .cornerRadius(Theme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(Theme.Colors.separator, lineWidth: 1)
                    )
                    .frame(width: 320)
                    
                    Toggle(isOn: $manager.isMTRMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            Text(languageManager.t("traceroute.mtr_mode"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(manager.isRunning)
                    
                    Button(action: {
                        if manager.isRunning {
                            manager.stop()
                        } else {
                            manager.startTrace(host: targetHost)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            Text(manager.isRunning ? languageManager.t("traceroute.stop") : languageManager.t("traceroute.start"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(manager.isRunning ? Theme.Colors.accentRed.opacity(0.15) : Theme.Colors.accentBlue.opacity(0.15))
                        )
                        .foregroundStyle(manager.isRunning ? Theme.Colors.accentRed : Theme.Colors.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .disabled(targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !manager.isRunning)

                    Button(action: {
                        manager.runNSLookup(host: targetHost)
                    }) {
                        HStack(spacing: 6) {
                            if manager.isNSLookupRunning {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            }
                            Text(languageManager.t("traceroute.nslookup"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.cardBackground)
                        )
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isNSLookupRunning)
                    
                    if !manager.hops.isEmpty {
                        Button(action: {
                            manager.copyResultsToClipboard()
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopied = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                Text(showCopied ? languageManager.t("traceroute.copied") : languageManager.t("traceroute.copy"))
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(showCopied ? Theme.Colors.accentGreen.opacity(0.15) : Theme.Colors.cardBackground)
                            )
                            .foregroundStyle(showCopied ? Theme.Colors.accentGreen : Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // MTR hint
            if manager.isMTRMode {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                    Text(languageManager.t("traceroute.mtr_hint"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                }
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)
                
                ZStack {
                    Circle()
                        .fill(
                            .linearGradient(
                                colors: [Theme.Colors.accentBlue.opacity(0.15), Theme.Colors.accentPurple.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.hero))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Theme.Colors.accentBlue, Theme.Colors.accentPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text(languageManager.t("traceroute.no_result"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(languageManager.t("traceroute.hint"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                
                // Quick targets
                HStack(spacing: 8) {
                    QuickTargetButton(label: "8.8.8.8", icon: "globe") {
                        targetHost = "8.8.8.8"
                        manager.startTrace(host: targetHost)
                    }
                    QuickTargetButton(label: "1.1.1.1", icon: "shield") {
                        targetHost = "1.1.1.1"
                        manager.startTrace(host: targetHost)
                    }
                    QuickTargetButton(label: "baidu.com", icon: "network") {
                        targetHost = "www.baidu.com"
                        manager.startTrace(host: targetHost)
                    }
                }
                .padding(.top, 4)
                
                // Monitored hosts section
                if viewModel.isRunning && !viewModel.hosts.isEmpty {
                    monitoredHostsSection
                }

                if manager.isNSLookupRunning || manager.nsLookupResult != nil || manager.nsLookupError != nil {
                    nsLookupSection
                        .padding(.horizontal, 20)
                }
                
                Spacer(minLength: 30)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Monitored Hosts Section
    
    private var monitoredHostsSection: some View {
        VStack(spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Theme.Colors.accentPurple)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                Text(languageManager.t("traceroute.monitored_hosts"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Badge(
                    text: "\(viewModel.hosts.count)",
                    color: Theme.Colors.accentBlue
                )
            }
            .padding(.horizontal, 16)
            
            // Host cards grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ForEach(viewModel.hosts) { host in
                    MonitoredHostCard(host: host) {
                        targetHost = host.address
                        manager.startTrace(host: host.address)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if manager.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else if !manager.hops.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accentGreen)
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                }
                
                Text(manager.progress)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                if !manager.hops.isEmpty {
                    let validHops = manager.hops.filter { !$0.isTimeout }
                    let timeoutHops = manager.hops.filter { $0.isTimeout }
                    
                    HStack(spacing: 12) {
                        HopSummaryBadge(
                            icon: "arrow.triangle.branch",
                            value: "\(manager.hops.count)",
                            label: languageManager.t("traceroute.hop"),
                            color: Theme.Colors.accentBlue
                        )
                        
                        if let avgAll = validHops.compactMap({ $0.avgLatency }).isEmpty ? nil :
                            validHops.compactMap({ $0.avgLatency }).reduce(0, +) / Double(validHops.compactMap({ $0.avgLatency }).count) {
                            HopSummaryBadge(
                                icon: "timer",
                                value: String(format: "%.1f ms", avgAll),
                                label: languageManager.t("traceroute.avg"),
                                color: latencyColor(avgAll)
                            )
                        }
                        
                        if !timeoutHops.isEmpty {
                            HopSummaryBadge(
                                icon: "exclamationmark.triangle",
                                value: "\(timeoutHops.count)",
                                label: languageManager.t("traceroute.timeout"),
                                color: Theme.Colors.accentOrange
                            )
                        }
                    }
                }
            }

            if let routeContext = manager.routeContext {
                routeContextView(routeContext)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Hop Table
    
    private var hopTableView: some View {
        let w = HopColumnWidths.scaled(total: max(0, tableContentWidth - 32))
        return VStack(spacing: 0) {
            // Table header
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: w.hop, alignment: .center)
                Text(languageManager.t("traceroute.ip"))
                    .frame(width: w.ip, alignment: .leading)

                ForEach(0..<3, id: \.self) { i in
                    Text("\(languageManager.t("traceroute.latency")) \(i + 1)")
                        .frame(width: w.latency, alignment: .trailing)
                }

                Text(languageManager.t("traceroute.avg"))
                    .frame(width: w.avg, alignment: .trailing)
                Text(languageManager.t("traceroute.loss"))
                    .frame(width: w.loss, alignment: .trailing)
                Text(languageManager.t("traceroute.location"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .semibold))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.Colors.cardBackground.opacity(0.5))

            Divider().opacity(0.3)

            // Table rows
            ForEach(Array(manager.hops.enumerated()), id: \.element.id) { index, hop in
                HopRowView(hop: hop, isEven: index % 2 == 0, columnWidths: w)

                if index < manager.hops.count - 1 {
                    Divider().opacity(0.15).padding(.horizontal, 16)
                }
            }

            // Loading indicator for running trace
            if manager.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("...")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HopTableWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HopTableWidthKey.self) { tableContentWidth = $0 }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
    
    private func latencyColor(_ latency: Double) -> Color {
        Theme.Status.latency(latency, .hop)
    }

    @ViewBuilder
    private func routeContextView(_ routeContext: TraceRouteContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                RouteContextBadge(
                    icon: routeContext.isTunnelInterface ? "point.3.connected.trianglepath.dotted" : "network",
                    title: languageManager.t("traceroute.source"),
                    value: routeContext.sourceAddress ?? "—",
                    color: routeContext.isTunnelInterface ? Theme.Colors.accentOrange : Theme.Colors.accentGreen
                )

                if let interfaceName = routeContext.interfaceName, !interfaceName.isEmpty {
                    RouteContextBadge(
                        icon: "cable.connector",
                        title: languageManager.t("traceroute.interface"),
                        value: interfaceName,
                        color: Theme.Colors.accentBlue
                    )
                }

                if let gateway = routeContext.gateway, !gateway.isEmpty {
                    RouteContextBadge(
                        icon: "arrow.triangle.swap",
                        title: languageManager.t("traceroute.gateway"),
                        value: gateway,
                        color: Theme.Colors.accentPurple
                    )
                }
            }
        }
    }

    private var nsLookupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "network.badge.shield.half.filled")
                    .foregroundStyle(Theme.Colors.accentBlue)
                Text(languageManager.t("traceroute.nslookup"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if manager.isNSLookupRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let result = manager.nsLookupResult {
                if let server = result.server, !server.isEmpty {
                    RouteContextBadge(
                        icon: "server.rack",
                        title: languageManager.t("traceroute.nslookup_server"),
                        value: server,
                        color: Theme.Colors.accentBlue
                    )
                }

                if !result.records.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(result.records) { record in
                            HStack(alignment: .top, spacing: 10) {
                                Text(record.label)
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 90, alignment: .leading)
                                Text(record.value)
                                    .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Text(result.rawOutput)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.Colors.surfaceOverlay)
                    .cornerRadius(Theme.Radius.md)
            } else if let error = manager.nsLookupError {
                Text(error)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.accentRed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(languageManager.t("traceroute.nslookup_empty"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Subviews

// 跳表列宽：原图固定列总宽 ~640pt。按容器宽等比缩放，避免窄屏横向溢出。
// Location 列保持弹性（maxWidth:.infinity），不纳入缩放。
struct HopColumnWidths {
    let hop: CGFloat
    let ip: CGFloat
    let latency: CGFloat
    let avg: CGFloat
    let loss: CGFloat

    // 原始固定列宽（不含 Location）：40 + 200 + 90×3 + 70 + 60 = 640
    private static let baseTotal: CGFloat = 640

    static func scaled(total: CGFloat) -> HopColumnWidths {
        let s = max(0.55, total / baseTotal) // 不缩到 55% 以下，避免数字不可读
        return .init(
            hop: 40 * s,
            ip: 200 * s,
            latency: 90 * s,
            avg: 70 * s,
            loss: 60 * s
        )
    }
}

// 读取跳表实际渲染宽，用于按比例缩放列宽（不阻塞内容高度）。
private struct HopTableWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 640
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let n = nextValue()
        if n > 0 { value = n }
    }
}

struct HopRowView: View {
    let hop: TracerouteHop
    let isEven: Bool
    var columnWidths: HopColumnWidths = .scaled(total: 640)
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Hop number with color bar
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: Theme.Radius.xs)
                    .fill(hop.latencyColor)
                    .frame(width: 3, height: 20)
                
                Text("\(hop.hopNumber)")
                    .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: columnWidths.hop, alignment: .center)

            // Host / IP
            VStack(alignment: .leading, spacing: 2) {
                if hop.isTimeout {
                    Text("* * *")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    Text(hop.hostName)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if hop.hostName != hop.ip {
                        Text(hop.ip)
                            .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: columnWidths.ip, alignment: .leading)

            // Individual latencies
            ForEach(0..<3, id: \.self) { i in
                if i < hop.latencies.count, let lat = hop.latencies[i] {
                    Text(String(format: "%.1f", lat))
                        .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                        .foregroundStyle(latencyColor(lat))
                        .frame(width: columnWidths.latency, alignment: .trailing)
                } else {
                    Text(i < hop.latencies.count ? "*" : "-")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: columnWidths.latency, alignment: .trailing)
                }
            }

            // Average
            Text(hop.formattedAvg)
                .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .semibold))
                .foregroundStyle(hop.latencyColor)
                .frame(width: columnWidths.avg, alignment: .trailing)

            // Loss
            Text(hop.formattedLoss)
                .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .medium))
                .foregroundStyle(hop.packetLoss > 0 ? Theme.Colors.accentOrange : Theme.Colors.accentGreen)
                .frame(width: columnWidths.loss, alignment: .trailing)
                
            // Location
            VStack(alignment: .leading, spacing: 2) {
                if let locString = hop.geoLocation?.locationString {
                    Text(locString)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                } else if !hop.isTimeout {
                    Text("-")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                if let isp = hop.geoLocation?.isp, !isp.isEmpty {
                    Text(isp)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Theme.Colors.hoverOverlay : (isEven ? Color.clear : Theme.Colors.surfaceOverlay))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func latencyColor(_ latency: Double) -> Color {
        Theme.Status.latency(latency, .hop)
    }
}

struct QuickTargetButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.footnote))
                Text(label)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.body, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
            )
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct HopSummaryBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                .foregroundStyle(color)
            Text(value)
                .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

struct RouteContextBadge: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                .foregroundStyle(color)
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Colors.surfaceOverlay)
        .cornerRadius(Theme.Radius.md)
    }
}

struct MonitoredHostCard: View {
    let host: HostConfig
    let onTrace: () -> Void
    @State private var isHovered = false
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        Button(action: onTrace) {
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(host.isReachable ? latencyColor : Theme.Colors.textTertiary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .shadow(color: host.isReachable ? latencyColor.opacity(0.5) : .clear, radius: 3)
                
                // Host info
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(host.address)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Latency badge
                if let latency = host.lastLatency {
                    Text("\(Int(latency))ms")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                        .foregroundStyle(latencyColor)
                } else if host.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Text("--")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Image(systemName: "arrow.right.circle")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                    .foregroundStyle(Theme.Colors.accentBlue.opacity(isHovered ? 1 : 0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isHovered ? Theme.Colors.hoverOverlay : Theme.Colors.surfaceOverlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isHovered ? Theme.Colors.accentBlue.opacity(0.3) : Theme.Colors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var latencyColor: Color {
        Theme.Status.latency(host.lastLatency, .hop)
    }
}

// MARK: - Map View

import MapKit

struct TracerouteMapView: View {
    @ObservedObject var manager: TracerouteManager
    
    // We want to auto-adjust camera based on hops
    @State private var position: MapCameraPosition = .automatic
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let validLocations = getValidLocations()
        
        Map(position: $position) {
            // Draw lines between consecutive hops with locations
            if validLocations.count > 1 {
                let coordinates = validLocations.map { $0.coord }
                MapPolyline(coordinates: coordinates)
                    .stroke(Theme.Colors.accentBlue, lineWidth: 2)
            }
            
            // Draw markers for each hop
            ForEach(validLocations, id: \.hop.id) { loc in
                Annotation(loc.hop.hostName, coordinate: loc.coord) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(loc.hop.latencyColor)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Theme.Colors.onAccent, lineWidth: 2)
                            )
                            .shadow(radius: 2)
                        
                        Text("\(loc.hop.hopNumber)")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.cardBackground)
                            .cornerRadius(Theme.Radius.xs)
                            .shadow(radius: 1)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapZoomStepper()
        }
        .onChange(of: manager.hops.count) {
            updatePosition(getValidLocations())
        }
    }
    
    private struct LocData {
        let hop: TracerouteHop
        let coord: CLLocationCoordinate2D
    }
    
    private func getValidLocations() -> [LocData] {
        return manager.hops.compactMap { hop in
            guard let lat = hop.geoLocation?.lat, let lon = hop.geoLocation?.lon else { return nil }
            return LocData(hop: hop, coord: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
    
    private func updatePosition(_ locs: [LocData]) {
        guard !locs.isEmpty else { return }
        
        // If there's only 1 point, just center on it
        if locs.count == 1 {
            position = .region(MKCoordinateRegion(center: locs[0].coord, latitudinalMeters: 500000, longitudinalMeters: 500000))
            return
        }
        
        let coords = locs.map { $0.coord }
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!
        
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(maxLat - minLat + 5, 20), longitudeDelta: max(maxLon - minLon + 5, 20)) // Pad edges
        
        withAnimation {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
