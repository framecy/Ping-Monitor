import SwiftUI

// 从 MainView.swift 拆出：设置页 + Tailscale OAuth 凭据卡

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
            VStack(alignment: .leading, spacing: 16) {
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

                HStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 8) {
                    guideStep(1, "settings.tailscale.howto.step1")
                    guideStep(2, "settings.tailscale.howto.step2")
                    guideStep(3, "settings.tailscale.howto.step3")
                    guideStep(4, "settings.tailscale.howto.step4")
                    guideStep(5, "settings.tailscale.howto.step5")
                    guideStep(6, "settings.tailscale.howto.step6")

                    HStack(spacing: 8) {
                        Button(action: { NSWorkspace.shared.open(Self.consoleURL) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                Text(languageManager.t("settings.tailscale.open_console"))
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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
                                .padding(.vertical, 6)
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
                    .padding(.top, 2)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.accentOrange)
                        Text(languageManager.t("settings.tailscale.howto.note"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceOverlay)
                .cornerRadius(Theme.Radius.md)
            }
        }
    }

    private func guideStep(_ index: Int, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
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

// MARK: - Settings Tab
struct SettingsTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    // Tailscale 功能总闸：关闭后隐藏所有 Tailscale 入口；CLI 不可用且开关开启时仍不展示。
    @AppStorage("pm.enableTailscale") private var enableTailscale: Bool = false
    @ObservedObject private var tailscale = TailscaleManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.gridSpacing) {
                // MARK: - General
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.system"), icon: "gear")
                        
                        HStack {
                            Text(languageManager.t("settings.language"))
                            Spacer()
                            Picker("", selection: $languageManager.currentLanguage) {
                                Text("中文").tag(Language.zh)
                                Text("English").tag(Language.en)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: languageManager.currentLanguage) { _, newValue in
                                LogManager.shared.info("Language changed to \(newValue.rawValue)")
                                languageManager.languageString = newValue.rawValue
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.appearance"))
                            Spacer()
                            Picker("", selection: $viewModel.appAppearance) {
                                Text(languageManager.t("settings.appearance.light")).tag("light")
                                Text(languageManager.t("settings.appearance.system")).tag("system")
                                Text(languageManager.t("settings.appearance.dark")).tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.appAppearance) { _, newValue in
                                LogManager.shared.info("Appearance changed to \(newValue)")
                                viewModel.saveSettings()
                            }
                        }
                        
                        Divider()
                        
                        Toggle(languageManager.t("settings.auto_start"), isOn: $viewModel.autoStart)
                            .onChange(of: viewModel.autoStart) { _, newValue in
                                viewModel.toggleAutoStart(newValue)
                            }

                        Divider()

                        Toggle(languageManager.t("settings.tailscale"), isOn: $enableTailscale)
                            .help(languageManager.t("settings.tailscale.help"))
                            .onChange(of: enableTailscale) { _, newValue in
                                TailscaleManager.shared.setEnabled(newValue)
                            }

                        Text(tailscaleIntegrationStatus)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.top, -8)

                        Divider()

                        HStack {
                            Text(languageManager.t("settings.version"))
                            Spacer()
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 220, alignment: .trailing)
                        }
                    }
                }

                // MARK: - Tailscale 全局监管凭据
                if enableTailscale {
                    TailscaleOAuthSettingsCard()
                }

                // MARK: - Display (Status Bar & Widget)
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.status_bar"), icon: "menubar.rectangle")
                        
                        HStack {
                            Text(languageManager.t("settings.display_mode"))
                            Spacer()
                            Picker("", selection: $viewModel.statusBarDisplayMode) {
                                Text(languageManager.t("settings.display.average")).tag(StatusBarDisplayMode.average)
                                Text(languageManager.t("settings.display.worst")).tag(StatusBarDisplayMode.worst)
                                Text(languageManager.t("settings.display.best")).tag(StatusBarDisplayMode.best)
                                Text(languageManager.t("settings.display.first")).tag(StatusBarDisplayMode.first)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.statusBarDisplayMode) { _, newValue in
                                LogManager.shared.info("Display mode changed to \(newValue.rawValue)")
                                viewModel.saveSettings()
                            }
                        }
                        
                        Text(statusBarDescription)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.top, -8)
                        
                        let activeMenuCount = [viewModel.showIconInMenu, viewModel.showLatencyInMenu, viewModel.showLabelsInMenu, viewModel.showSpeedInMenu].filter { $0 }.count
                        
                        Divider()
                        
                        HStack(spacing: 16) {
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
                            HStack {
                                Text(languageManager.t("settings.speed_unit"))
                                Spacer()
                                Picker("", selection: $viewModel.speedUnit) {
                                    Text(languageManager.t("settings.speed_unit.auto")).tag("auto")
                                    Text("KB/s").tag("KB")
                                    Text("MB/s").tag("MB")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220, alignment: .trailing)
                                .onChange(of: viewModel.speedUnit) { _, newValue in
                                    LogManager.shared.info("Speed unit changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }
                        }
                        
                        if viewModel.showIconInMenu {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.icon_width"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarIconWidth > 10 {
                                            viewModel.statusBarIconWidth -= 2
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "minus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarIconWidth <= 10)
                                    
                                    Text("\(viewModel.statusBarIconWidth)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)
                                    
                                    Button {
                                        if viewModel.statusBarIconWidth < 100 {
                                            viewModel.statusBarIconWidth += 2
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "plus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarIconWidth >= 100)
                                }
                                .frame(width: 220, alignment: .trailing)
                            }
                        }
                        
                        if viewModel.showLatencyInMenu {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.latency_width"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarLatencyWidth > 20 {
                                            viewModel.statusBarLatencyWidth -= 5
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "minus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarLatencyWidth <= 20)
                                    
                                    Text("\(viewModel.statusBarLatencyWidth)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)
                                    
                                    Button {
                                        if viewModel.statusBarLatencyWidth < 200 {
                                            viewModel.statusBarLatencyWidth += 5
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "plus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarLatencyWidth >= 200)
                                }
                                .frame(width: 220, alignment: .trailing)
                            }
                        }
                        
                        if viewModel.showLabelsInMenu {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.label_width"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarLabelWidth > 20 {
                                            viewModel.statusBarLabelWidth -= 5
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "minus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarLabelWidth <= 20)
                                    
                                    Text("\(viewModel.statusBarLabelWidth)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)
                                    
                                    Button {
                                        if viewModel.statusBarLabelWidth < 200 {
                                            viewModel.statusBarLabelWidth += 5
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "plus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarLabelWidth >= 200)
                                }
                                .frame(width: 220, alignment: .trailing)
                            }
                        }
                        
                        if viewModel.showSpeedInMenu {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.speed_width"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarSpeedWidth > 40 {
                                            viewModel.statusBarSpeedWidth -= 5
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "minus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarSpeedWidth <= 40)
                                    
                                    Text("\(viewModel.statusBarSpeedWidth)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)
                                    
                                    Button {
                                        if viewModel.statusBarSpeedWidth < 250 {
                                            viewModel.statusBarSpeedWidth += 5
                                            viewModel.saveSettings()
                                        }
                                    } label: { Image(systemName: "plus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarSpeedWidth >= 250)
                                }
                                .frame(width: 220, alignment: .trailing)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.font_size"))
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    if viewModel.statusBarFontSize > 6 {
                                        viewModel.statusBarFontSize -= 1
                                        viewModel.saveSettings()
                                    }
                                } label: { Image(systemName: "minus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                .buttonStyle(.borderless)
                                .disabled(viewModel.statusBarFontSize <= 6)
                                
                                Text("\(viewModel.statusBarFontSize)")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 36, alignment: .center)
                                
                                Button {
                                    if viewModel.statusBarFontSize < 18 {
                                        viewModel.statusBarFontSize += 1
                                        viewModel.saveSettings()
                                    }
                                } label: { Image(systemName: "plus.circle").font(Theme.Fonts.icon(Theme.Fonts.Size.headline)) }
                                .buttonStyle(.borderless)
                                .disabled(viewModel.statusBarFontSize >= 18)
                            }
                            .frame(width: 220, alignment: .trailing)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.font_weight"))
                            Spacer()
                            Picker("", selection: $viewModel.statusBarFontWeight) {
                                Text(languageManager.t("settings.font_weight.regular")).tag("regular")
                                Text(languageManager.t("settings.font_weight.medium")).tag("medium")
                                Text(languageManager.t("settings.font_weight.bold")).tag("bold")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.statusBarFontWeight) { _, newValue in
                                LogManager.shared.info("Status bar font weight changed to \(newValue)")
                                viewModel.saveSettings()
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.status_bar_color"))
                            Spacer()
                            Picker("", selection: $viewModel.statusBarColorMode) {
                                Text(languageManager.t("settings.status_bar_color.auto")).tag("auto")
                                Text(languageManager.t("settings.status_bar_color.light")).tag("light")
                                Text(languageManager.t("settings.status_bar_color.dark")).tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.statusBarColorMode) { _, newValue in
                                LogManager.shared.info("Status bar color mode changed to \(newValue)")
                                viewModel.saveSettings()
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("settings.widget.mode"))
                            Spacer()
                            Picker("", selection: $viewModel.widgetDisplayMode) {
                                Text(languageManager.t("settings.widget.auto")).tag("auto")
                                Text(languageManager.t("settings.widget.specific")).tag("specific")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.widgetDisplayMode) { _, newValue in
                                LogManager.shared.info("Widget display mode changed to \(newValue)")
                                viewModel.syncToWidget()
                            }
                        }
                        
                        if viewModel.widgetDisplayMode == "specific" {
                            Divider()
                            HStack {
                                Text(languageManager.t("settings.widget.select_host"))
                                Spacer()
                                Picker("", selection: $viewModel.widgetSelectedHostId) {
                                    Text(languageManager.t("settings.widget.none")).tag("")
                                    ForEach(viewModel.hosts) { host in
                                        Text(host.name).tag(host.id.uuidString)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220, alignment: .trailing)
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
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.monitor"), icon: "waveform.path.ecg")
                        
                        HStack {
                            Text(languageManager.t("settings.interval"))
                            Spacer()
                            Picker("", selection: $viewModel.pingInterval) {
                                Text(languageManager.t("settings.interval.3s")).tag(3.0)
                                Text(languageManager.t("settings.interval.5s")).tag(5.0)
                                Text(languageManager.t("settings.interval.10s")).tag(10.0)
                                Text(languageManager.t("settings.interval.15s")).tag(15.0)
                                Text(languageManager.t("settings.interval.30s")).tag(30.0)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.pingInterval) { _, newValue in
                                LogManager.shared.info("Ping interval changed to \(Int(newValue))s")
                                viewModel.applyPingIntervalChange()
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(languageManager.t("logs.level"))
                            Spacer()
                            Picker("", selection: $viewModel.logLevel) {
                                ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                                    Text(languageManager.t("logs.level.\(level.rawValue.lowercased())")).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.logLevel) { _, newValue in
                                LogManager.shared.info("Log level changed to \(newValue.rawValue)")
                                viewModel.saveSettings()
                            }
                        }
                    }
                }
                
                // MARK: - Notifications
                ModernCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("settings.section.notify"), icon: "bell.badge.fill")
                        
                        Toggle(languageManager.t("settings.notify.enable"), isOn: $viewModel.notificationEnabled)
                            .onChange(of: viewModel.notificationEnabled) { _, newValue in
                                LogManager.shared.info("Notifications enabled: \(newValue)")
                                viewModel.saveSettings()
                            }
                        
                        if viewModel.notificationEnabled {
                            Divider()
                            
                            HStack {
                                Text(languageManager.t("settings.notify.type"))
                                Spacer()
                                Picker("", selection: $viewModel.notificationType) {
                                    Text(languageManager.t("settings.notify.system")).tag("system")
                                    Text(languageManager.t("settings.notify.bark")).tag("bark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220, alignment: .trailing)
                                .onChange(of: viewModel.notificationType) { _, newValue in
                                    LogManager.shared.info("Notification type changed to \(newValue)")
                                    viewModel.saveSettings()
                                }
                            }
                            
                            if viewModel.notificationType == "bark" {
                                Divider()
                                HStack {
                                    Text("Bark URL")
                                    Spacer()
                                    TextField("https://api.day.app/...", text: $viewModel.barkURL)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 220, alignment: .trailing)
                                        .onChange(of: viewModel.barkURL) { _, _ in
                                            viewModel.saveSettings()
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
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
