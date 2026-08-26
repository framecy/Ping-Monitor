import SwiftUI

// MARK: - 单侧边栏（LM Studio 二级导航风格）
// 图标在导航行内，不再保留独立图标栏——应用只有一级导航，两段式会重复且占宽度。
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("pm.enableTailscale") private var enableTailscale: Bool = false
    @ObservedObject private var tailscale = TailscaleManager.shared

    /// Tailscale 入口可见性总闸：用户在设置页开启，且「本机 CLI 可用」或「已配置控制面凭据」。
    private var tailscaleVisible: Bool {
        (tailscale.isAvailable || tailscale.hasInventoryCredentials) && enableTailscale
    }

    var body: some View {
        NavPanel(selectedItem: $selectedItem, tailscaleVisible: tailscaleVisible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.navBackground)
    }
}

// MARK: - 导航面板
private struct NavPanel: View {
    @Binding var selectedItem: SidebarItem
    let tailscaleVisible: Bool
    @ObservedObject private var languageManager = LanguageManager.shared
    /// 折叠分组集合，默认全部展开。
    @State private var collapsedSections: Set<String> = []

    private func itemVisible(_ item: SidebarItem) -> Bool {
        item != .tailscale || tailscaleVisible
    }

    var body: some View {
        VStack(spacing: 0) {
            // 面板头部：App 图标 + 名称
            HStack(spacing: Theme.Space.controlGap) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.Colors.accentBlue, Theme.Colors.accentPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("PingMonitor")
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            // 横向留白取 lg，与下方导航行（滚动容器 sm + 行内 sm）的图标左缘对齐。
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.pageTopGap)
            .padding(.bottom, Theme.Space.controlGap)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    NavSection(
                        title: languageManager.t("sidebar.overview"),
                        isCollapsed: collapsedSections.contains("overview"),
                        onToggle: { toggle("overview") }
                    ) {
                        NavRow(item: .monitor, selectedItem: $selectedItem)
                        NavRow(item: .statistics, selectedItem: $selectedItem)
                        NavRow(item: .traceroute, selectedItem: $selectedItem)
                        NavRow(item: .netspeed, selectedItem: $selectedItem)
                        if itemVisible(.tailscale) {
                            NavRow(item: .tailscale, selectedItem: $selectedItem)
                        }
                    }

                    Spacer().frame(height: Theme.Space.xl)

                    NavSection(
                        title: languageManager.t("sidebar.management"),
                        isCollapsed: collapsedSections.contains("management"),
                        onToggle: { toggle("management") }
                    ) {
                        NavRow(item: .hosts, selectedItem: $selectedItem)
                        NavRow(item: .services, selectedItem: $selectedItem)
                        NavRow(item: .logs, selectedItem: $selectedItem)
                    }

                    Spacer().frame(height: Theme.Space.xl)

                    NavSection(
                        title: languageManager.t("sidebar.config"),
                        isCollapsed: collapsedSections.contains("config"),
                        onToggle: { toggle("config") }
                    ) {
                        NavRow(item: .settings, selectedItem: $selectedItem)
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
            }

            // 底部：Tailnet 入口 + 用户/版本 + 语言切换
            VStack(spacing: Theme.Space.sm) {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)

                // Tailnet 监管状态（只读，点击进入 Tailscale 页）
                if tailscaleVisible {
                    HStack {
                        TailnetStatusPill(selectedItem: $selectedItem)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Space.md)
                }

                HStack(spacing: Theme.Space.controlGap) {
                    Circle()
                        .fill(Theme.Colors.cardBackground)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        let userName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
                        Text(userName)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text("v\(version)")
                                .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    Spacer()

                    // 语言切换：chip 显示将要切换到的语言，点击即切换
                    Button {
                        languageManager.toggle()
                    } label: {
                        Text(languageManager.currentLanguage == .zh ? "EN" : "中")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, Theme.Space.xxs)
                            .background(Capsule().fill(Theme.Colors.navSelection))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("settings.language"))
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.md)
            }
        }
    }

    private func toggle(_ section: String) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }
}

// MARK: - 分组头（可折叠）
private struct NavSection<Content: View>: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Button(action: onToggle) {
                HStack(spacing: Theme.Space.xs) {
                    Text(title)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                content
            }
        }
    }
}

// MARK: - 导航行（LM Studio 式浅灰胶囊选中态）
private struct NavRow: View {
    let item: SidebarItem
    @Binding var selectedItem: SidebarItem
    @State private var hovering = false

    private var isSelected: Bool { selectedItem == item }

    var body: some View {
        Button(action: { selectedItem = item }) {
            HStack(spacing: Theme.Space.controlGap) {
                Image(systemName: item.icon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.body, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Colors.accentBlue : Theme.Colors.textSecondary)
                    .frame(width: 20)

                Text(item.title)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)

                Spacer()
            }
            .padding(.vertical, Theme.Space.sm)
            .padding(.horizontal, Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isSelected ? Theme.Colors.navSelection
                                     : (hovering ? Theme.Colors.hoverOverlay : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
