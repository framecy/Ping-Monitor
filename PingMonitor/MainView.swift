
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
        case .monitor: return Theme.Colors.accentGreen
        case .statistics: return Theme.Colors.accentBlue
        case .traceroute: return Theme.Colors.accentCyan
        case .netspeed: return Theme.Colors.accentTeal
        case .tailscale: return Theme.Colors.accentIndigo
        case .services: return Theme.Colors.accentMint
        case .hosts: return Theme.Colors.accentPurple
        case .logs: return Theme.Colors.accentOrange
        case .settings: return Theme.Colors.textSecondary
        }
    }
}

struct MainView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedItem: SidebarItem = .monitor
    @ObservedObject private var languageManager = LanguageManager.shared
    // 固定默认宽度、可拖动调节、持久化；width 为硬约束，detail 内容无法反向挤压。
    @AppStorage("pm.sidebarWidth") private var sidebarWidth: Double = Double(Theme.Layout.sidebarDefaultWidth)
    // Tailscale 功能总闸：关闭后隐藏侧边栏/header 入口；CLI 不可用且开启时仍不展示。
    @AppStorage("pm.enableTailscale") private var enableTailscale: Bool = false
    @State private var dragStartWidth: Double?
    @ObservedObject private var tailscale = TailscaleManager.shared

    // CLI 可用（本机视角）或已配置控制面凭据（全局监管）任一成立即展示入口。
    private var tailscaleVisible: Bool {
        (tailscale.isAvailable || tailscale.hasInventoryCredentials) && enableTailscale
    }

    /// 侧边栏被夹紧后的实际宽度：@AppStorage 里可能残留越界值（旧版本 / 手改 plist）。
    private var clampedSidebarWidth: CGFloat {
        min(Theme.Layout.sidebarMaxWidth, max(Theme.Layout.sidebarMinWidth, CGFloat(sidebarWidth)))
    }

    /// 窗口最小宽度随侧边栏宽度推导，保证 detail 区始终有 detailMinWidth 可用，
    /// 不会出现「窗口够小 → HStack 空间不足 → 侧边栏被一起压扁」。
    private var minContentWidth: CGFloat {
        clampedSidebarWidth + Theme.Layout.detailMinWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedItem: $selectedItem)
                .frame(width: clampedSidebarWidth)
                // fixedSize + 高 layoutPriority：宽度是硬约束，空间不足时先压 detail，绝不压侧边栏。
                .fixedSize(horizontal: true, vertical: false)
                .background(Theme.Colors.sidebarBackground)
                .layoutPriority(1)

            VStack(spacing: 0) {
                headerView

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // minWidth: 0 让 detail 成为唯一可压缩列；clipped 防止超宽内容盖到侧边栏上。
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(Theme.Colors.background)
            // 1pt 发丝线画在 detail 的左边缘，两个色块直接相接，中间不留任何一列。
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1)
            }
            .clipped()
            .layoutPriority(0)
        }
        // 拖拽热区浮在边界上，不参与 HStack 布局 —— 一旦它占一列宽度，
        // 无论填什么颜色都会在 header 的材质层旁边露出一条色差。
        .overlay(alignment: .leading) {
            SidebarResizer(width: $sidebarWidth, dragStartWidth: $dragStartWidth)
                .offset(x: clampedSidebarWidth - Theme.Layout.sidebarResizerWidth / 2)
        }
        .frame(minWidth: minContentWidth, minHeight: 650)
        // 同步 NSWindow 的最小尺寸：只靠 SwiftUI 的 minWidth 挡不住标题栏拖拽缩小，
        // 窗口一旦被拖到比内容还窄，HStack 就会连带压缩侧边栏。
        .background(WindowMinSizeSetter(minSize: NSSize(width: minContentWidth, height: 650)))
        .onChange(of: languageManager.currentLanguage) { _, _ in
            viewModel.updateStatusBarDisplay()
            viewModel.syncToWidget()
        }
        .onChange(of: tailscaleVisible) { _, visible in
            // Tailscale 不可见时，把残留在 .tailscale 的选中回退到监控页，避免高亮孤儿。
            if !visible && selectedItem == .tailscale {
                selectedItem = .monitor
            }
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
            // 总闸关闭时（用户在设置页关掉、或残留选中 .tailscale）回退到监控页，不渲染 Tailscale。
            if tailscaleVisible {
                TailscaleTab(viewModel: viewModel)
            } else {
                MonitorTab(viewModel: viewModel)
            }
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
                        .fill(Theme.Colors.accentGreen.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .scaleEffect(viewModel.isRunning ? 1.6 : 1.0)
                        .opacity(viewModel.isRunning ? 0 : 0.6)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isRunning)
                }
                Circle()
                    .fill(viewModel.isRunning ? Theme.Colors.accentGreen : Theme.Colors.textTertiary.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .shadow(color: viewModel.isRunning ? Theme.Colors.accentGreen.opacity(0.5) : .clear, radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedItem.title)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .bold))
                Text(viewModel.isRunning ? String(format: languageManager.t("header.monitoring"), viewModel.hosts.count) : languageManager.t("header.stopped"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            // Language Toggle
            Button(action: { languageManager.toggle() }) {
                Text(languageManager.currentLanguage == .zh ? "EN" : "中")
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(6)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(languageManager.t("common.switch_language"))

            // Tailnet 监管状态（只读，点击进入 Tailscale 页）
            if tailscaleVisible {
                TailnetStatusPill(selectedItem: $selectedItem)
            }

            Button(action: { viewModel.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                    Text(viewModel.isRunning ? languageManager.t("header.stop") : languageManager.t("header.start"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(viewModel.isRunning ? Theme.Colors.accentRed.opacity(0.15) : Theme.Colors.accentGreen.opacity(0.15))
                )
                .foregroundStyle(viewModel.isRunning ? Theme.Colors.accentRed : Theme.Colors.accentGreen)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    viewModel.isRunning ? Theme.Colors.accentGreen.opacity(0.04) : Theme.Colors.textTertiary.opacity(0.03),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sidebar Resizer
// 可拖动的侧边栏分隔条：实时改变宽度并通过 @AppStorage 持久化。
// 宽度被夹在 Theme.Layout.sidebarMin/MaxWidth，避免过窄压坏内容或过宽挤占主区域。
//
// 纯透明的 8pt 拖拽热区，浮在侧栏与 detail 的交界上，不占任何布局宽度。
// 发丝线由 detail 区自己画，这里不上色 —— 上色就会变成一道灰带或色差缝。
private struct SidebarResizer: View {
    @Binding var width: Double
    @Binding var dragStartWidth: Double?

    private let minWidth = Double(Theme.Layout.sidebarMinWidth)
    private let maxWidth = Double(Theme.Layout.sidebarMaxWidth)

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Theme.Layout.sidebarResizerWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        if let start = dragStartWidth {
                            let candidate = start + value.translation.width
                            width = min(maxWidth, max(minWidth, candidate))
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}

// MARK: - Window min size bridge
// 把 SwiftUI 侧算出的最小内容尺寸同步给宿主 NSWindow，随侧边栏宽度变化实时更新。
private struct WindowMinSizeSetter: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window, window.contentMinSize != minSize else { return }
        window.contentMinSize = minSize
        window.minSize = NSSize(
            width: minSize.width,
            height: minSize.height + (window.frame.height - window.contentLayoutRect.height)
        )
        // 已经比新最小值更窄时，主动放大，避免停留在压缩态。
        if window.frame.width < minSize.width {
            var frame = window.frame
            frame.size.width = minSize.width
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

// MARK: - Tailscale OAuth 设置卡

// 这里刻意不提供 exit-node 切换 —— 本机的 Tailscale app 才是路由的唯一控制者。
struct TailnetStatusPill: View {
    @Binding var selectedItem: SidebarItem
    @ObservedObject private var tailscale = TailscaleManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    private var summary: (text: String, color: Color) {
        if tailscale.hasInventoryCredentials {
            switch tailscale.inventoryState {
            case .failed:
                return (languageManager.t("tailscale.inventory.sync_failed"), Theme.Colors.accentRed)
            case .notConfigured:
                return ("Tailscale", Theme.Colors.textTertiary)
            case .ok:
                let online = tailscale.tailnetDevices.filter { $0.isOnline }.count
                return ("\(online)/\(tailscale.tailnetDevices.count)", Theme.Colors.accentBlue)
            }
        }
        return (tailscale.isConnected ? "Tailscale" : languageManager.t("tailscale.disconnected"),
                tailscale.isConnected ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
    }

    var body: some View {
        Button(action: { selectedItem = .tailscale }) {
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                Text(summary.text)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(summary.color.opacity(0.15)))
            .foregroundStyle(summary.color)
        }
        .buttonStyle(.plain)
        .help(languageManager.t("tailscale.inventory.title"))
        .fixedSize()
    }
}
