import SwiftUI

// 从 MainView.swift 拆出：主机管理页 + 常用模板 + 模板编辑器

// MARK: - 主机管理 Tab
struct HostManagementTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedSection = 0
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Segmented Control（统一分段控件，卡片式）
            CardSegmentedControl(
                segments: [
                    "\(languageManager.t("host.manage.section.saved")) (\(viewModel.hosts.count))",
                    "\(languageManager.t("host.manage.section.presets")) (\(viewModel.presets.count))"
                ],
                selection: $selectedSection
            )
            .cardBar()
            
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
            .cardBar(bottomInset: 12)
            
            if viewModel.hosts.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_hosts"), systemImage: "server.rack", description: Text(languageManager.t("host.manage.add_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: Theme.Layout.hostGridMinWidth), spacing: 12)
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
            HStack(spacing: 4) {
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
                HStack(spacing: 4) {
                    ForEach(host.displayRules.filter { $0.enabled }.prefix(3)) { rule in
                        Text("\(rule.condition == "less" ? "<" : ">")\(Int(rule.threshold))ms→\(rule.label)")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(rule.condition == "less" ? Theme.Colors.accentGreen.opacity(0.15) : Theme.Colors.accentOrange.opacity(0.15))
                            )
                            .foregroundStyle(rule.condition == "less" ? Theme.Colors.accentGreen : Theme.Colors.accentOrange)
                    }
                }
            }

            HStack(spacing: 4) {
                Image(systemName: host.probeMode == .tcp ? "cable.connector" : "waveform.path.ecg")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(host.probeMode == .tcp ? "TCP \(host.tcpPort)" : "ICMP")
                    .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            // Custom command
            if !host.command.isEmpty {
                HStack(spacing: 4) {
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.Colors.cardBackground)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(isHovered ? Theme.Colors.accentBlue.opacity(0.45) : Theme.Colors.cardBorder, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
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
            .cardBar(bottomInset: 12)
            
            if viewModel.presets.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_presets"), systemImage: "bookmark", description: Text(languageManager.t("host.manage.add_preset_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: Theme.Layout.hostGridMinWidth), spacing: 12)
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
            
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(preset.address)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            
            if !preset.command.isEmpty {
                HStack(spacing: 4) {
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
            HStack(spacing: 8) {
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
        .padding(14)
        .frame(height: 110, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.Colors.cardBackground)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(isHovered ? Theme.Colors.accentOrange.opacity(0.45) : Theme.Colors.cardBorder, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .contextMenu {
            Button { onAdd() } label: { Label(languageManager.t("menu.add_to_monitor"), systemImage: "plus.circle") }
            Button { onEdit() } label: { Label(languageManager.t("menu.edit"), systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label(languageManager.t("menu.delete"), systemImage: "trash") }
        }
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
        VStack(spacing: 20) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))

            Form {
                TextField(languageManager.t("editor.name"), text: $name)
                TextField(languageManager.t("editor.address"), text: $address)
                    .textContentType(.URL)
                
                VStack(alignment: .leading, spacing: 4) {
                    TextField(languageManager.t("editor.command"), text: $command)
                    Text(languageManager.t("editor.command_hint"))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(languageManager.t("editor.command_follows_interval"))
                        .font(.caption2)
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
        .padding()
        .frame(width: 380)
    }
}
