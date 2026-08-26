
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
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, 10)
                    .padding(.bottom, Theme.Space.xs)

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
    // LM Studio 式工具栏卡片：白色圆角卡承载页面标题 + 全局状态开关，
    // 浮在内容区背景之上，不再用材质渐变条。
    private var headerView: some View {
        HStack(spacing: 14) {
            // 状态指示点（运行中呼吸脉冲）
            ZStack {
                if viewModel.isRunning {
                    Circle()
                        .fill(Theme.Colors.accentGreen.opacity(0.25))
                        .frame(width: 22, height: 22)
                        .scaleEffect(viewModel.isRunning ? 1.5 : 1.0)
                        .opacity(viewModel.isRunning ? 0 : 0.6)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isRunning)
                }
                Circle()
                    .fill(viewModel.isRunning ? Theme.Colors.accentGreen : Theme.Colors.textTertiary.opacity(0.5))
                    .frame(width: 9, height: 9)
            }

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(selectedItem.title)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
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
                    .background(Theme.Colors.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Switch Language")

            // Tailnet 监管状态（只读，点击进入 Tailscale 页）
            if tailscaleVisible {
                TailnetStatusPill(selectedItem: $selectedItem)
            }

            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1, height: 22)

            // 状态开关：LM Studio 的 "Status: Running" 同款
            HStack(spacing: Theme.Space.sm) {
                Text(viewModel.isRunning ? languageManager.t("header.stop") : languageManager.t("header.start"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)

                Toggle("", isOn: Binding(
                    get: { viewModel.isRunning },
                    set: { _ in viewModel.toggle() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.Colors.accentBlue)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, 10)
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
// client id / secret 只进钥匙串，不落 ConfigManager 的明文 JSON。
struct TailscaleOAuthSettingsCard: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var tailscale = TailscaleManager.shared
    @AppStorage("pm.tailscaleInventoryInterval") private var inventoryInterval: Double = 60
    /// 管理模式：开启后 Tailscale 页的设备行才出现写操作菜单。
    @AppStorage("pm.tailscaleAdminMode") private var adminMode: Bool = false

    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var isValidating = false
    @State private var resultMessage: String?
    @State private var resultIsError = false
    /// 未配置时默认展开引导，配置好后收起。
    @State private var showGuide: Bool?

    private static let consoleURL = URL(string: "https://login.tailscale.com/admin/settings/oauth")!

    private var isGuideExpanded: Bool {
        showGuide ?? !tailscale.hasInventoryCredentials
    }

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: languageManager.t("settings.tailscale.oauth"), icon: "key.horizontal.fill")

                Text(languageManager.t("settings.tailscale.oauth.help"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                guideSection

                HStack {
                    Text(languageManager.t("settings.tailscale.client_id"))
                    Spacer()
                    TextField("k123...", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                HStack {
                    Text(languageManager.t("settings.tailscale.client_secret"))
                    Spacer()
                    SecureField("tskey-client-...", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                HStack {
                    Text(languageManager.t("settings.tailscale.interval"))
                    Spacer()
                    Picker("", selection: $inventoryInterval) {
                        Text("30s").tag(30.0)
                        Text("60s").tag(60.0)
                        Text("5m").tag(300.0)
                        Text("15m").tag(900.0)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 260, alignment: .trailing)
                    .onChange(of: inventoryInterval) { _, _ in
                        tailscale.refreshInventoryConfiguration()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(languageManager.t("settings.tailscale.admin_mode"), isOn: $adminMode)
                    Text(languageManager.t("settings.tailscale.admin_mode.help"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(adminMode ? Theme.Colors.accentOrange : Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(action: saveAndValidate) {
                        HStack(spacing: 6) {
                            if isValidating {
                                ProgressView().controlSize(.small).scaleEffect(0.7)
                            }
                            Text(languageManager.t("settings.tailscale.save_validate"))
                        }
                    }
                    .disabled(isValidating || clientID.isEmpty || clientSecret.isEmpty)

                    if tailscale.hasInventoryCredentials {
                        Button(languageManager.t("settings.tailscale.clear"), role: .destructive, action: clearCredentials)
                            .disabled(isValidating)
                    }

                    Spacer()

                    if tailscale.hasInventoryCredentials {
                        Badge(text: languageManager.t("settings.tailscale.configured"), color: Theme.Colors.accentGreen)
                    }
                }

                if let resultMessage {
                    Text(resultMessage)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(resultIsError ? Theme.Colors.accentRed : Theme.Colors.accentGreen)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            // 只回填 client id（非机密）；secret 永远不从钥匙串读回界面。
            clientID = KeychainStore.load(.tailscaleOAuthClientID) ?? ""
        }
    }

    // MARK: 获取凭据的分步引导

    private var guideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { showGuide = !isGuideExpanded }) {
                HStack(spacing: 6) {
                    Image(systemName: isGuideExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .semibold))
                    Text(languageManager.t("settings.tailscale.howto"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.Colors.accentBlue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isGuideExpanded {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    guideStep(1, "settings.tailscale.howto.step1")
                    guideStep(2, "settings.tailscale.howto.step2")
                    guideStep(3, "settings.tailscale.howto.step3")
                    guideStep(4, "settings.tailscale.howto.step4")
                    guideStep(5, "settings.tailscale.howto.step5")
                    guideStep(6, "settings.tailscale.howto.step6")

                    HStack(spacing: Theme.Space.sm) {
                        Button(action: { NSWorkspace.shared.open(Self.consoleURL) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                Text(languageManager.t("settings.tailscale.open_console"))
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.Colors.accentBlue.opacity(0.15))
                            .foregroundStyle(Theme.Colors.accentBlue)
                            .cornerRadius(Theme.Radius.sm)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.consoleURL.absoluteString, forType: .string)
                        }) {
                            Text(languageManager.t("settings.tailscale.copy_link"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.Colors.cardBackground)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .cornerRadius(Theme.Radius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, Theme.Space.xxs)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.accentOrange)
                        Text(languageManager.t("settings.tailscale.howto.note"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Theme.Space.xxs)
                }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceOverlay)
                .cornerRadius(Theme.Radius.md)
            }
        }
    }

    private func guideStep(_ index: Int, _ key: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text("\(index)")
                .font(Theme.Fonts.number(Theme.Fonts.Size.micro, weight: .bold))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.Colors.accentBlue))

            Text(languageManager.t(key))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func saveAndValidate() {
        guard KeychainStore.save(clientID, for: .tailscaleOAuthClientID),
              KeychainStore.save(clientSecret, for: .tailscaleOAuthClientSecret) else {
            resultIsError = true
            resultMessage = languageManager.t("settings.tailscale.keychain_failed")
            return
        }

        isValidating = true
        resultMessage = nil
        clientSecret = ""

        Task {
            do {
                let count = try await TailscaleAPIClient.shared.validateCredentials()
                resultIsError = false
                resultMessage = String(format: languageManager.t("settings.tailscale.validated"), count)
                tailscale.refreshInventoryConfiguration()
                LogManager.shared.info("Tailscale OAuth validated, \(count) devices visible")
            } catch let error as TailscaleAPIError {
                resultIsError = true
                resultMessage = TailscaleManager.describe(error)
                LogManager.shared.error("Tailscale OAuth validation failed: \(error.rawDescription)")
            } catch {
                resultIsError = true
                resultMessage = error.localizedDescription
            }
            isValidating = false
        }
    }

    private func clearCredentials() {
        KeychainStore.delete(.tailscaleOAuthClientID)
        KeychainStore.delete(.tailscaleOAuthClientSecret)
        clientID = ""
        clientSecret = ""
        resultIsError = false
        resultMessage = nil
        tailscale.refreshInventoryConfiguration()
    }
}

// MARK: - Tailnet 状态胶囊
// 只读：展示控制面同步出来的在线/总数，点击跳转 Tailscale 页。
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
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "network")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                Text(summary.text)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(Capsule().fill(summary.color.opacity(0.15)))
            .foregroundStyle(summary.color)
        }
        .buttonStyle(.plain)
        .help(languageManager.t("tailscale.inventory.title"))
        .fixedSize()
    }
}

// MARK: - 监控 Tab
struct MonitorTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var editingHost: HostConfig?
    @State private var selectedHost: HostConfig?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostCommand = ""
    @State private var newHostRules: [DisplayRule] = []
    @State private var newHostProbeMode: HostProbeMode = .icmp
    @State private var newHostTCPPort = 443
    @State private var showingAddHost = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 工具栏
                ToolbarRow(
                    title: "\(languageManager.t("monitor.title")) (\(viewModel.hosts.count))"
                ) {
                    Button {
                        showingAddHost = true
                    } label: {
                        Label(languageManager.t("monitor.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, Theme.Space.pagePadding)
                .padding(.top, Theme.Space.pageTopGap)
                .padding(.bottom, Theme.Space.controlGap)

                if viewModel.hosts.isEmpty {
                    ContentUnavailableView(languageManager.t("monitor.no_hosts"), systemImage: "network", description: Text(languageManager.t("monitor.add_host_hint")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // 快捷服务条与主机网格各自成卡（解包原来的整页巨卡，消除"卡中卡"）。
                        VStack(alignment: .leading, spacing: Theme.Space.sectionGap) {
                            QuickAccessServicesRibbon(viewModel: viewModel)

                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 280, maximum: .infinity), spacing: Theme.Space.tileGap)
                            ], spacing: Theme.Space.tileGap) {
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
                                            newHostProbeMode = host.probeMode
                                            newHostTCPPort = host.tcpPort
                                        },
                                        onDelete: {
                                            if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                                                viewModel.removeHost(at: index)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            selectedHost = host
                                        }
                                    }
                                    .onDrag {
                                        NSItemProvider(object: host.id.uuidString as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: HostDropDelegate(item: host, viewModel: viewModel))
                                }
                            }
                            .padding(.top, Theme.Space.xs)
                        }
                        .padding(.horizontal, Theme.Space.pagePadding)
                        .padding(.bottom, Theme.Space.pagePadding)
                    }
                }
            }
            .blur(radius: selectedHost != nil ? 2 : 0)
            
            // Detail Overlay
            if let host = selectedHost {
                Color.black.opacity(0.001) // Invisible backdrop to catch taps if needed, or just let view take full space
                    .onTapGesture {
                        withAnimation { selectedHost = nil }
                    }
                
                HostDetailView(
                    viewModel: viewModel,
                    host: host,
                    onClose: {
                        withAnimation { selectedHost = nil }
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showingAddHost) {
            HostEditorSheet(
                isPresented: $showingAddHost,
                title: languageManager.t("editor.add_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    viewModel.addHost(
                        name: newHostName,
                        address: newHostAddress,
                        command: newHostCommand,
                        displayRules: newHostRules.isEmpty ? nil : newHostRules,
                        probeMode: newHostProbeMode,
                        tcpPort: newHostTCPPort
                    )
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
                title: languageManager.t("editor.edit_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                        viewModel.updateHost(
                            at: index,
                            name: trimmedName,
                            address: trimmedAddress,
                            command: trimmedCommand,
                            displayRules: newHostRules,
                            probeMode: newHostProbeMode,
                            tcpPort: newHostTCPPort
                        )
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
        newHostProbeMode = .icmp
        newHostTCPPort = 443
    }
}

// MARK: - Quick Access Services Ribbon
struct QuickAccessServicesRibbon: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @AppStorage("pm.quickAccessExpanded") private var isExpanded: Bool = true

    private var hostGroups: [(host: HostConfig, shortcuts: [ServiceShortcut])] {
        viewModel.hosts.compactMap { host in
            guard !host.serviceShortcuts.isEmpty else { return nil }
            return (host: host, shortcuts: host.serviceShortcuts)
        }
    }

    var body: some View {
        if !hostGroups.isEmpty {
            VStack(spacing: 0) {
                // Header — always visible
                HStack(spacing: 0) {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "bolt.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.accentOrange)
                        Text(LanguageManager.shared.t("monitor.quick_access"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.leading, Theme.Space.lg)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, Theme.Space.sm)
                }
                .frame(height: 36)

                // Expanded content
                if isExpanded {
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(height: 1)
                        .padding(.horizontal, Theme.Space.lg)

                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        ForEach(hostGroups, id: \.host.id) { group in
                            hostRow(group: group)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
            // 独立标准卡（原先嵌在整页巨卡里的半透明条，现与主机卡同级同观感）。
            .card(padding: 0)
        }
    }

    @ViewBuilder
    private func hostRow(group: (host: HostConfig, shortcuts: [ServiceShortcut])) -> some View {
        HStack(spacing: Theme.Space.controlGap) {
            // Status dot + host name (fixed-width label column)
            HStack(spacing: Theme.Space.xs) {
                Circle()
                    .fill(hostStatusColor(group.host))
                    .frame(width: 6, height: 6)
                    .shadow(color: hostStatusColor(group.host).opacity(0.6), radius: 2)
                Text(group.host.name)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            // All chips — horizontal scroll so every shortcut is reachable
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(group.shortcuts) { shortcut in
                        serviceChip(shortcut: shortcut, host: group.host)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Theme.Space.xs)
    }

    @ViewBuilder
    private func serviceChip(shortcut: ServiceShortcut, host: HostConfig) -> some View {
        Button {
            openService(shortcut, host: host)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: shortcut.icon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.footnote))
                    .foregroundStyle(serviceColor(for: shortcut.type))
                Text(shortcut.name)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                typePill(shortcut.type)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 5)
            .background(serviceColor(for: shortcut.type).opacity(0.10))
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
        .help(serviceTargetPreview(shortcut))
        .contextMenu {
            Button {
                openService(shortcut, host: host)
            } label: {
                Label(LanguageManager.shared.t("monitor.quick_access_open"), systemImage: "arrow.up.forward.app")
            }
            Button {
                copyServiceTarget(shortcut, host: host)
            } label: {
                Label(LanguageManager.shared.t("monitor.quick_access_copy"), systemImage: "doc.on.doc")
            }
        }
    }

    private func typePill(_ type: ServiceShortcut.ServiceType) -> some View {
        Text(shortcutTypeLabel(type))
            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .semibold))
            .foregroundStyle(serviceColor(for: type))
            .padding(.horizontal, 6)
            .padding(.vertical, Theme.Space.xxs)
            .background(serviceColor(for: type).opacity(0.12))
            .cornerRadius(Theme.Radius.pill)
    }
    
    private func serviceColor(for type: ServiceShortcut.ServiceType) -> Color {
        Theme.Status.service(type)
    }

    private func shortcutTypeLabel(_ type: ServiceShortcut.ServiceType) -> String {
        switch type {
        case .web: return "WEB"
        case .ssh: return "SSH"
        case .custom: return "CMD"
        }
    }

    private func serviceTargetPreview(_ shortcut: ServiceShortcut) -> String {
        switch shortcut.type {
        case .web, .custom:
            return shortcut.url
        case .ssh:
            return shortcut.sshCommand
        }
    }

    private func copyServiceTarget(_ shortcut: ServiceShortcut, host: HostConfig) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(serviceTargetPreview(shortcut), forType: .string)
        LogManager.shared.info("Copied service target: \(shortcut.name)", host: host.name)
    }

    private func hostStatusColor(_ host: HostConfig) -> Color {
        if host.isPaused { return Theme.Colors.textTertiary }
        if host.isChecking { return Theme.Colors.accentBlue }
        if !host.isReachable { return Theme.Colors.accentRed }
        if let latency = host.lastLatency {
            return Theme.Status.latency(latency)
        }
        return Theme.Colors.textSecondary
    }
    
    private func openService(_ shortcut: ServiceShortcut, host: HostConfig) {
        switch shortcut.type {
        case .web:
            if let url = URL(string: shortcut.url) {
                NSWorkspace.shared.open(url)
            }
        case .ssh:
            let cmdFile = "/tmp/pm_ssh_\(UUID().uuidString.prefix(8)).command"
            let scriptContent = "#!/bin/bash\nrm -f \"\(cmdFile)\"\n\(shortcut.sshCommand)\n"
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
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            SegmentedSwitcher(
                options: [0, 1],
                selection: $selectedSection,
                title: { section in
                    section == 0
                        ? languageManager.t("host.manage.section.saved")
                        : languageManager.t("host.manage.section.presets")
                },
                count: { section in
                    section == 0 ? viewModel.hosts.count : viewModel.presets.count
                }
            )
            .padding(.horizontal, Theme.Space.pagePadding)
            .padding(.top, Theme.Space.pageTopGap)
            .padding(.bottom, Theme.Space.controlGap)

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
    @State private var newHostProbeMode: HostProbeMode = .icmp
    @State private var newHostTCPPort = 443
    @State private var hoveredHostId: UUID?
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageManager.t("sidebar.hosts"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button {
                    showingAddHost = true
                } label: {
                    Label(languageManager.t("host.manage.add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, Theme.Space.md)
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_hosts"), systemImage: "server.rack", description: Text(languageManager.t("host.manage.add_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: Theme.Layout.hostGridMinWidth), spacing: Theme.Space.md)
                    ], spacing: Theme.Space.md) {
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
                                    newHostProbeMode = host.probeMode
                                    newHostTCPPort = host.tcpPort
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
                title: languageManager.t("editor.add_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !trimmedName.isEmpty && !trimmedAddress.isEmpty {
                        viewModel.addHost(
                            name: trimmedName,
                            address: trimmedAddress,
                            command: trimmedCommand,
                            displayRules: newHostRules.isEmpty ? nil : newHostRules,
                            probeMode: newHostProbeMode,
                            tcpPort: newHostTCPPort
                        )
                        resetForm()
                    }
                }
            )
        }
        .sheet(item: $editingHost) { host in
            HostEditorSheet(
                isPresented: Binding(
                    get: { editingHost != nil },
                    set: { if !$0 { editingHost = nil } }
                ),
                title: languageManager.t("editor.edit_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                probeMode: $newHostProbeMode,
                tcpPort: $newHostTCPPort,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !trimmedName.isEmpty && !trimmedAddress.isEmpty {
                        if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                            viewModel.updateHost(
                                at: index,
                                name: trimmedName,
                                address: trimmedAddress,
                                command: trimmedCommand,
                                displayRules: newHostRules,
                                probeMode: newHostProbeMode,
                                tcpPort: newHostTCPPort
                            )
                        }
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
        newHostRules = [
            DisplayRule(condition: "less", threshold: 50, label: "Direct", enabled: true),
            DisplayRule(condition: "greater", threshold: 100, label: "Relay", enabled: true)
        ]
        newHostProbeMode = .icmp
        newHostTCPPort = 443
    }
}

struct HostManagementCard: View {
    let host: HostConfig
    let isHovered: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: name + actions
            HStack {
                Image(systemName: "server.rack")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                    .foregroundStyle(Theme.Colors.accentBlue)
                Text(host.name)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                
                HStack(spacing: 6) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                            .foregroundStyle(Theme.Colors.accentBlue.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("menu.edit"))
                    
                    Button { onDelete() } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                            .foregroundStyle(Theme.Colors.accentRed.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("menu.delete"))
                }
                .opacity(isHovered ? 1 : 0.3)
            }
            
            // Address
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "globe")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(host.address)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            
            // Display rules
            if !host.displayRules.filter({ $0.enabled }).isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(host.displayRules.filter { $0.enabled }.prefix(3)) { rule in
                        Text("\(rule.condition == "less" ? "<" : ">")\(Int(rule.threshold))ms→\(rule.label)")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, Theme.Space.xxs)
                            .background(
                                Capsule()
                                    .fill(rule.condition == "less" ? Theme.Colors.accentGreen.opacity(0.15) : Theme.Colors.accentOrange.opacity(0.15))
                            )
                            .foregroundStyle(rule.condition == "less" ? Theme.Colors.accentGreen : Theme.Colors.accentOrange)
                    }
                }
            }

            HStack(spacing: Theme.Space.xs) {
                Image(systemName: host.probeMode == .tcp ? "cable.connector" : "waveform.path.ecg")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(host.probeMode == .tcp ? "TCP \(host.tcpPort)" : "ICMP")
                    .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            // Custom command
            if !host.command.isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "terminal")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.accentPurple.opacity(0.7))
                    Text(host.command)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(Theme.Space.md)
        // 统一实心卡外壳：原材质卡是本页独有样式，深浅色下与其他卡片不一致（有意视觉变更）。
        .hoverLift(isHovered: isHovered)
        .contextMenu {
            Button { onEdit() } label: { Label(languageManager.t("menu.edit"), systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label(languageManager.t("menu.delete"), systemImage: "trash") }
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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageManager.t("host.manage.quick_add"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button {
                    showingAddPreset = true
                } label: {
                    Label(languageManager.t("host.manage.add_preset"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, Theme.Space.md)
            
            if viewModel.presets.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_presets"), systemImage: "bookmark", description: Text(languageManager.t("host.manage.add_preset_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: Theme.Layout.hostGridMinWidth), spacing: Theme.Space.md)
                    ], spacing: Theme.Space.md) {
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
                title: languageManager.t("editor.add_preset"),
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
                title: languageManager.t("editor.edit_preset"),
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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.accentOrange)
                Text(preset.name)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                
                Button { onAdd() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.title))
                        .foregroundStyle(Theme.Colors.accentGreen)
                }
                .buttonStyle(.plain)
                .help(languageManager.t("menu.add_to_monitor"))
            }
            
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "globe")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(preset.address)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            
            if !preset.command.isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "terminal")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.accentPurple.opacity(0.7))
                    Text(preset.command)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            
            // Action buttons
            HStack(spacing: Theme.Space.sm) {
                Spacer()
                Button { onEdit() } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                        .foregroundStyle(Theme.Colors.accentBlue.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Button { onDelete() } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                        .foregroundStyle(Theme.Colors.accentRed.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovered ? 1 : 0.2)
        }
        .padding(Theme.Space.md)
        .frame(height: 110, alignment: .top)
        // 统一实心卡外壳：原材质卡是本页独有样式，深浅色下与其他卡片不一致（有意视觉变更）。
        .hoverLift(isHovered: isHovered, accent: Theme.Colors.accentOrange)
        .contextMenu {
            Button { onAdd() } label: { Label(languageManager.t("menu.add_to_monitor"), systemImage: "plus.circle") }
            Button { onEdit() } label: { Label(languageManager.t("menu.edit"), systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label(languageManager.t("menu.delete"), systemImage: "trash") }
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
    @Binding var probeMode: HostProbeMode
    @Binding var tcpPort: Int
    let onSave: () -> Void
    @State private var showingAddRule = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))

            ScrollView {
                Form {
                    Section(languageManager.t("editor.section.basic")) {
                        TextField(languageManager.t("editor.name"), text: $name)
                        TextField(languageManager.t("editor.address"), text: $address)
                            .textContentType(.URL)

                        Picker("Probe", selection: $probeMode) {
                            Text("ICMP").tag(HostProbeMode.icmp)
                            Text("TCP").tag(HostProbeMode.tcp)
                        }
                        .pickerStyle(.segmented)

                        if probeMode == .tcp {
                            Stepper(value: $tcpPort, in: 1...65535) {
                                HStack {
                                    Text("TCP Port")
                                    Spacer()
                                    Text("\(tcpPort)")
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            TextField(languageManager.t("editor.command"), text: $command)
                            Text(languageManager.t("editor.command_hint"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(languageManager.t("editor.command_follows_interval"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                                .foregroundStyle(Theme.Colors.accentBlue)
                        }
                    }
                    
                    Section(languageManager.t("editor.section.rules")) {
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
                            Label(languageManager.t("editor.add_rule"), systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(languageManager.t("common.save")) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || address.isEmpty)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 420, height: 500)
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(isPresented: $showingAddRule, rules: $displayRules)
        }
    }
}

struct RuleEditorRow: View {
    @Binding var rule: DisplayRule
    let onDelete: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Enable toggle + Delete
            HStack {
                Toggle(languageManager.t("editor.rule.enable"), isOn: $rule.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                }
                .buttonStyle(.borderless)
            }
            
            // Row 2: Condition + Threshold + Label (properly spaced)
            HStack(spacing: Theme.Space.sm) {
                // Condition picker
                Picker("", selection: $rule.condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 90)
                
                // Threshold
                HStack(spacing: Theme.Space.xs) {
                    TextField("", value: $rule.threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 45)
                    Text("ms")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer(minLength: 4)
                
                // Static Label "显示文本"
                Text(languageManager.t("editor.rule.label"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                // Label TextField
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $rule.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            .frame(height: 28) // Force consistent height to fix vertical alignment
        }
        .padding(.vertical, Theme.Space.sm)
    }
}

struct AddRuleSheet: View {
    @Binding var isPresented: Bool
    @Binding var rules: [DisplayRule]
    @State private var condition = "less"
    @State private var threshold: Double = 100
    @State private var label = ""
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Text(languageManager.t("editor.add_rule"))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
            
            Form {
                Picker(languageManager.t("editor.rule.condition"), selection: $condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                
                HStack {
                    Text(languageManager.t("editor.rule.threshold"))
                    Spacer()
                    TextField("ms", value: $threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $label)
            }
            .formStyle(.grouped)
            
            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(languageManager.t("common.add")) {
                    let finalLabel = label.isEmpty ? "\(condition == "less" ? "<" : ">") \(Int(threshold))ms" : label
                    rules.append(DisplayRule(condition: condition, threshold: threshold, label: finalLabel, enabled: true))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Space.lg)
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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))

            Form {
                TextField(languageManager.t("editor.name"), text: $name)
                TextField(languageManager.t("editor.address"), text: $address)
                    .textContentType(.URL)
                
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    TextField(languageManager.t("editor.command"), text: $command)
                    Text(languageManager.t("editor.command_hint"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(languageManager.t("editor.command_follows_interval"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.accentBlue)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(languageManager.t("common.save")) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || address.isEmpty)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 380)
    }
}

// MARK: - Logs Tab
struct LogsTab: View {
    @StateObject private var logManager = LogManager.shared
    @State private var selectedLevel: LogManager.LogLevel?
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var filteredLogs: [LogManager.LogEntry] {
        if let level = selectedLevel {
            return logManager.logs.filter { $0.level == level }
        }
        return logManager.logs
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏：统一的卡片式工具行（不用材质铺底），承载级别筛选 + 清空 / 导出。
            HStack(spacing: Theme.Space.md) {
                Text(languageManager.t("logs.level"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Picker("", selection: $selectedLevel) {
                    Text(languageManager.t("logs.level.all")).tag(nil as LogManager.LogLevel?)
                    ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                        Text(languageManager.t("logs.level.\(level.rawValue.lowercased())")).tag(level as LogManager.LogLevel?)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .controlSize(.small)

                Spacer()

                Button(action: { logManager.clear() }) {
                    Label(languageManager.t("logs.clear"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Colors.textSecondary)

                Button(action: {
                    if let url = logManager.exportToFile() {
                        exportURL = url
                        showingExportSheet = true
                    }
                }) {
                    Label(languageManager.t("logs.export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, Theme.Space.pagePadding)
            .padding(.vertical, Theme.Space.md)

            Divider()

            // 表头行：列宽与 LogRow 共用 LogColumnWidths 唯一出处。
            HStack(spacing: LogColumnWidths.rowSpacing) {
                Text("")
                    .frame(width: LogColumnWidths.marker)
                Text(languageManager.t("logs.time"))
                    .frame(width: LogColumnWidths.time, alignment: .leading)
                Text(languageManager.t("logs.level"))
                    .frame(width: LogColumnWidths.level, alignment: .leading)
                Text(languageManager.t("logs.host"))
                    .frame(width: LogColumnWidths.host, alignment: .leading)
                Text(languageManager.t("logs.message"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.Colors.surfaceOverlay)

            Divider()

            ScrollView {
                if filteredLogs.isEmpty {
                    ContentUnavailableView(languageManager.t("logs.empty"), systemImage: "doc.text")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLogs.reversed()) { entry in
                            LogRow(entry: entry)
                                .padding(.horizontal, Theme.Space.lg)
                            Divider()
                                .padding(.leading, Theme.Space.lg)
                        }
                    }
                }
            }
        }
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Layout.cardPadding)
        .padding(.top, Theme.Layout.cardPadding)
        .padding(.bottom, Theme.Layout.cardPadding)
        .fileExporter(
            isPresented: $showingExportSheet,
            document: LogFileDocument(url: exportURL),
            contentType: .plainText,
            defaultFilename: "PingMonitor_Logs.txt"
        ) { result in
            if case .success = result {
                LogManager.shared.info("Log exported successfully")
            }
        }
    }
}

struct LogRow: View {
    let entry: LogManager.LogEntry
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var levelColor: Color {
        Theme.Status.logLevel(entry.level)
    }
    
    var body: some View {
        HStack(spacing: LogColumnWidths.rowSpacing) {
            Circle()
                .fill(levelColor)
                .frame(width: 7, height: 7)
                .frame(width: LogColumnWidths.marker, alignment: .center)

            Text(entry.formattedTimestamp)
                .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: LogColumnWidths.time, alignment: .leading)

            Text(languageManager.t("logs.level.\(entry.level.rawValue.lowercased())"))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .semibold))
                .foregroundStyle(levelColor)
                .frame(width: LogColumnWidths.level, alignment: .leading)

            Text(entry.host ?? "-")
                .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .medium)) // 主机名走等宽数字字体，与时间列纵向对齐
                .foregroundStyle(entry.host == nil ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: LogColumnWidths.host, alignment: .leading)

            Text(entry.message)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2) // 消息最多两行截断；完整内容以导出文件为准
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.sm)
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
    @ObservedObject private var languageManager = LanguageManager.shared
    // Tailscale 功能总闸：关闭后隐藏所有 Tailscale 入口；CLI 不可用且开关开启时仍不展示。
    @AppStorage("pm.enableTailscale") private var enableTailscale: Bool = false
    @ObservedObject private var tailscale = TailscaleManager.shared

    var body: some View {
        ScrollPage {
            // MARK: - General
            ModernCard {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    SectionHeader(title: languageManager.t("settings.section.system"), icon: "gear")

                    SettingsRow(label: languageManager.t("settings.language")) {
                        Picker("", selection: $languageManager.currentLanguage) {
                            Text("中文").tag(Language.zh)
                            Text("English").tag(Language.en)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: languageManager.currentLanguage) { _, newValue in
                            LogManager.shared.info("Language changed to \(newValue.rawValue)")
                            languageManager.languageString = newValue.rawValue
                        }
                    }

                    Divider()

                    SettingsRow(label: languageManager.t("settings.appearance")) {
                        Picker("", selection: $viewModel.appAppearance) {
                            Text(languageManager.t("settings.appearance.light")).tag("light")
                            Text(languageManager.t("settings.appearance.system")).tag("system")
                            Text(languageManager.t("settings.appearance.dark")).tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.appAppearance) { _, newValue in
                            LogManager.shared.info("Appearance changed to \(newValue)")
                            viewModel.saveSettings()
                        }
                    }

                    Divider()

                    SettingsRow(label: languageManager.t("settings.auto_start")) {
                        Toggle("", isOn: $viewModel.autoStart)
                            .labelsHidden()
                            .onChange(of: viewModel.autoStart) { _, newValue in
                                viewModel.toggleAutoStart(newValue)
                            }
                    }

                    Divider()

                    SettingsRow(
                        label: languageManager.t("settings.tailscale"),
                        description: tailscaleIntegrationStatus
                    ) {
                        Toggle("", isOn: $enableTailscale)
                            .labelsHidden()
                            .help(languageManager.t("settings.tailscale.help"))
                            .onChange(of: enableTailscale) { _, newValue in
                                TailscaleManager.shared.setEnabled(newValue)
                            }
                    }

                    Divider()

                    SettingsRow(label: languageManager.t("settings.version")) {
                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

                // MARK: - Tailscale 全局监管凭据
                if enableTailscale {
                    TailscaleOAuthSettingsCard()
                }

                // MARK: - Display (Status Bar & Widget)
                ModernCard {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        SectionHeader(title: languageManager.t("settings.section.status_bar"), icon: "menubar.rectangle")

                        SettingsRow(
                            label: languageManager.t("settings.display_mode"),
                            description: statusBarDescription
                        ) {
                            Picker("", selection: $viewModel.statusBarDisplayMode) {
                                Text(languageManager.t("settings.display.average")).tag(StatusBarDisplayMode.average)
                                Text(languageManager.t("settings.display.worst")).tag(StatusBarDisplayMode.worst)
                                Text(languageManager.t("settings.display.best")).tag(StatusBarDisplayMode.best)
                                Text(languageManager.t("settings.display.first")).tag(StatusBarDisplayMode.first)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.statusBarDisplayMode) { _, newValue in
                                LogManager.shared.info("Display mode changed to \(newValue.rawValue)")
                                viewModel.saveSettings()
                            }
                        }

                        let activeMenuCount = [viewModel.showIconInMenu, viewModel.showLatencyInMenu, viewModel.showLabelsInMenu, viewModel.showSpeedInMenu].filter { $0 }.count

                        Divider()

                        HStack(spacing: Theme.Space.xxl) {
                            Toggle(languageManager.t("settings.show_icon"), isOn: $viewModel.showIconInMenu)
                                .disabled((viewModel.showIconInMenu && activeMenuCount <= 1) || (!viewModel.showIconInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showIconInMenu) { _, newValue in
                                    LogManager.shared.info("Show icon in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            
                            Toggle(languageManager.t("settings.show_latency"), isOn: $viewModel.showLatencyInMenu)
                                .disabled((viewModel.showLatencyInMenu && activeMenuCount <= 1) || (!viewModel.showLatencyInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showLatencyInMenu) { _, newValue in
                                    LogManager.shared.info("Show latency in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
    
                            Toggle(languageManager.t("settings.show_labels"), isOn: $viewModel.showLabelsInMenu)
                                .disabled((viewModel.showLabelsInMenu && activeMenuCount <= 1) || (!viewModel.showLabelsInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showLabelsInMenu) { _, newValue in
                                    LogManager.shared.info("Show labels in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            
                            Toggle(languageManager.t("settings.show_speed"), isOn: $viewModel.showSpeedInMenu)
                                .disabled((viewModel.showSpeedInMenu && activeMenuCount <= 1) || (!viewModel.showSpeedInMenu && activeMenuCount >= 3))
                                .onChange(of: viewModel.showSpeedInMenu) { _, newValue in
                                    LogManager.shared.info("Show speed in menu toggled to \(newValue)")
                                    viewModel.saveSettings()
                                }
                        }
                        
                        if viewModel.showSpeedInMenu {
                            Divider()
                            SettingsRow(label: languageManager.t("settings.speed_unit")) {
                                Picker("", selection: $viewModel.speedUnit) {
                                    Text(languageManager.t("settings.speed_unit.auto")).tag("auto")
                                    Text("KB/s").tag("KB")
                                    Text("MB/s").tag("MB")
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: viewModel.speedUnit) { _, newValue in
                                    LogManager.shared.info("Speed unit changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }
                        }

                        if viewModel.showIconInMenu {
                            Divider()
                            StepperRow(
                                label: languageManager.t("settings.icon_width"),
                                value: viewModel.statusBarIconWidth,
                                range: 10...100,
                                step: 2
                            ) { delta in
                                viewModel.statusBarIconWidth += delta
                                viewModel.saveSettings()
                            }
                        }

                        if viewModel.showLatencyInMenu {
                            Divider()
                            StepperRow(
                                label: languageManager.t("settings.latency_width"),
                                value: viewModel.statusBarLatencyWidth,
                                range: 20...200,
                                step: 5
                            ) { delta in
                                viewModel.statusBarLatencyWidth += delta
                                viewModel.saveSettings()
                            }
                        }

                        if viewModel.showLabelsInMenu {
                            Divider()
                            StepperRow(
                                label: languageManager.t("settings.label_width"),
                                value: viewModel.statusBarLabelWidth,
                                range: 20...200,
                                step: 5
                            ) { delta in
                                viewModel.statusBarLabelWidth += delta
                                viewModel.saveSettings()
                            }
                        }

                        if viewModel.showSpeedInMenu {
                            Divider()
                            StepperRow(
                                label: languageManager.t("settings.speed_width"),
                                value: viewModel.statusBarSpeedWidth,
                                range: 40...250,
                                step: 5
                            ) { delta in
                                viewModel.statusBarSpeedWidth += delta
                                viewModel.saveSettings()
                            }
                        }

                        Divider()

                        StepperRow(
                            label: languageManager.t("settings.font_size"),
                            value: viewModel.statusBarFontSize,
                            range: 6...18,
                            step: 1
                        ) { delta in
                            viewModel.statusBarFontSize += delta
                            viewModel.saveSettings()
                        }

                        Divider()

                        SettingsRow(label: languageManager.t("settings.font_weight")) {
                            Picker("", selection: $viewModel.statusBarFontWeight) {
                                Text(languageManager.t("settings.font_weight.regular")).tag("regular")
                                Text(languageManager.t("settings.font_weight.medium")).tag("medium")
                                Text(languageManager.t("settings.font_weight.bold")).tag("bold")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.statusBarFontWeight) { _, newValue in
                                LogManager.shared.info("Status bar font weight changed to \(newValue)")
                                viewModel.saveSettings()
                            }
                        }

                        Divider()

                        SettingsRow(label: languageManager.t("settings.status_bar_color")) {
                            Picker("", selection: $viewModel.statusBarColorMode) {
                                Text(languageManager.t("settings.status_bar_color.auto")).tag("auto")
                                Text(languageManager.t("settings.status_bar_color.light")).tag("light")
                                Text(languageManager.t("settings.status_bar_color.dark")).tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.statusBarColorMode) { _, newValue in
                                LogManager.shared.info("Status bar color mode changed to \(newValue)")
                                viewModel.saveSettings()
                            }
                        }

                        Divider()

                        SettingsRow(label: languageManager.t("settings.widget.mode")) {
                            Picker("", selection: $viewModel.widgetDisplayMode) {
                                Text(languageManager.t("settings.widget.auto")).tag("auto")
                                Text(languageManager.t("settings.widget.specific")).tag("specific")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.widgetDisplayMode) { _, newValue in
                                LogManager.shared.info("Widget display mode changed to \(newValue)")
                                viewModel.syncToWidget()
                            }
                        }

                        if viewModel.widgetDisplayMode == "specific" {
                            Divider()
                            SettingsRow(label: languageManager.t("settings.widget.select_host")) {
                                Picker("", selection: $viewModel.widgetSelectedHostId) {
                                    Text(languageManager.t("settings.widget.none")).tag("")
                                    ForEach(viewModel.hosts) { host in
                                        Text(host.name).tag(host.id.uuidString)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: viewModel.widgetSelectedHostId) { _, newValue in
                                    LogManager.shared.info("Widget host changed to \(newValue)")
                                    viewModel.syncToWidget()
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Monitor & Logs
                ModernCard {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        SectionHeader(title: languageManager.t("settings.section.monitor"), icon: "waveform.path.ecg")

                        SettingsRow(label: languageManager.t("settings.interval")) {
                            Picker("", selection: $viewModel.pingInterval) {
                                Text(languageManager.t("settings.interval.3s")).tag(3.0)
                                Text(languageManager.t("settings.interval.5s")).tag(5.0)
                                Text(languageManager.t("settings.interval.10s")).tag(10.0)
                                Text(languageManager.t("settings.interval.15s")).tag(15.0)
                                Text(languageManager.t("settings.interval.30s")).tag(30.0)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.pingInterval) { _, newValue in
                                LogManager.shared.info("Ping interval changed to \(Int(newValue))s")
                                viewModel.applyPingIntervalChange()
                            }
                        }

                        Divider()

                        SettingsRow(label: languageManager.t("logs.level")) {
                            Picker("", selection: $viewModel.logLevel) {
                                ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                                    Text(languageManager.t("logs.level.\(level.rawValue.lowercased())")).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.logLevel) { _, newValue in
                                LogManager.shared.info("Log level changed to \(newValue.rawValue)")
                                viewModel.saveSettings()
                            }
                        }
                    }
                }

                // MARK: - Notifications
                ModernCard {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        SectionHeader(title: languageManager.t("settings.section.notify"), icon: "bell.badge.fill")

                        SettingsRow(label: languageManager.t("settings.notify.enable")) {
                            Toggle("", isOn: $viewModel.notificationEnabled)
                                .labelsHidden()
                                .onChange(of: viewModel.notificationEnabled) { _, newValue in
                                    LogManager.shared.info("Notifications enabled: \(newValue)")
                                    viewModel.saveSettings()
                                }
                        }

                        if viewModel.notificationEnabled {
                            Divider()

                            SettingsRow(label: languageManager.t("settings.notify.type")) {
                                Picker("", selection: $viewModel.notificationType) {
                                    Text(languageManager.t("settings.notify.system")).tag("system")
                                    Text(languageManager.t("settings.notify.bark")).tag("bark")
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: viewModel.notificationType) { _, newValue in
                                    LogManager.shared.info("Notification type changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }

                            if viewModel.notificationType == "bark" {
                                Divider()
                                SettingsRow(label: "Bark URL") {
                                    TextField("https://api.day.app/...", text: $viewModel.barkURL)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: viewModel.barkURL) { _, _ in
                                            viewModel.saveSettings()
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
            // 安装 Tailscale 后无需重启应用：打开设置页即重新检测 CLI。
            if enableTailscale { TailscaleManager.shared.detectCLI() }
        }
    }

    private var statusBarDescription: String {
        switch viewModel.statusBarDisplayMode {
        case .average:
            return languageManager.t("settings.desc.average")
        case .worst:
            return languageManager.t("settings.desc.worst")
        case .best:
            return languageManager.t("settings.desc.best")
        case .first:
            return languageManager.t("settings.desc.first")
        }
    }

    private var tailscaleIntegrationStatus: String {
        if !enableTailscale {
            return languageManager.t("settings.tailscale.status.off")
        }
        if tailscale.isAvailable, let path = tailscale.cliPath {
            return languageManager.t("settings.tailscale.status.detected") + ": " + path
        }
        if tailscale.hasInventoryCredentials {
            return languageManager.t("settings.tailscale.status.control_plane")
        }
        return languageManager.t("settings.tailscale.status.not_detected")
    }
}

/// 设置页步进行：− / 值 / + 三段控件，右缘对齐 SettingsRow 的控件槽。
/// 仅设置页使用，不进公共组件层。
private struct StepperRow: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// delta 为 ±step；调用方负责改值并持久化。
    let onStep: (Int) -> Void

    var body: some View {
        SettingsRow(label: label) {
            HStack(spacing: Theme.Space.sm) {
                Button {
                    onStep(-step)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                }
                .buttonStyle(.borderless)
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                    .frame(width: 36, alignment: .center)

                Button {
                    onStep(step)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                }
                .buttonStyle(.borderless)
                .disabled(value >= range.upperBound)
            }
        }
    }
}

// MARK: - Draggable Sorting Delegate
struct HostDropDelegate: DropDelegate {
    let item: HostConfig
    @ObservedObject var viewModel: PingMonitorViewModel
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return }
        
        itemProvider.loadObject(ofClass: NSString.self) { string, error in
            guard let idString = string as? String,
                  let draggingId = UUID(uuidString: idString),
                  draggingId != item.id else { return }
            
            Task { @MainActor in
                if let fromIndex = viewModel.hosts.firstIndex(where: { $0.id == draggingId }),
                   let toIndex = viewModel.hosts.firstIndex(where: { $0.id == item.id }) {
                    withAnimation {
                        viewModel.moveHost(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                    }
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
