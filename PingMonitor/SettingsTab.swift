import SwiftUI

// MARK: - Settings Tab
struct SettingsTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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

                        HStack {
                            Text(languageManager.t("settings.version"))
                            Spacer()
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .trailing)
                        }
                    }
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, -8)

                        let activeMenuCount = [viewModel.showIconInMenu, viewModel.showLatencyInMenu, viewModel.showLabelsInMenu, viewModel.showSpeedInMenu].filter { $0 }.count

                        Divider()

                        HStack(spacing: 24) {
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

                            Divider()

                            HStack {
                                Text(languageManager.t("settings.bar_width"))
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        if viewModel.statusBarWidth > 50 {
                                            viewModel.statusBarWidth -= 10
                                            viewModel.saveSettings()
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarWidth <= 50)

                                    Text("\(viewModel.statusBarWidth)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 36, alignment: .center)

                                    Button {
                                        if viewModel.statusBarWidth < 250 {
                                            viewModel.statusBarWidth += 10
                                            viewModel.saveSettings()
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.statusBarWidth >= 250)
                                }
                                .frame(width: 220, alignment: .trailing)
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
                                    } label: { Image(systemName: "minus.circle").font(.system(size: 16)) }
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
                                    } label: { Image(systemName: "plus.circle").font(.system(size: 16)) }
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
                                Text(languageManager.t("settings.interval.30s")).tag(30.0)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                            .onChange(of: viewModel.pingInterval) { _, newValue in
                                LogManager.shared.info("Ping interval changed to \(Int(newValue))s")
                                viewModel.saveSettings()
                                if viewModel.isRunning {
                                    viewModel.stopAll()
                                    viewModel.startAll()
                                }
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
        .padding()
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
}
