import SwiftUI

// MARK: - 主机管理 Tab
struct HostManagementTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedSection = 0
    @ObservedObject private var languageManager = LanguageManager.shared
    @Namespace private var animation

    var body: some View {
        VStack(spacing: 0) {
            // Custom Segmented Control
            HStack(spacing: 0) {
                customTabButton(title: "\(languageManager.t("host.manage.section.saved")) (\(viewModel.hosts.count))", section: 0)
                customTabButton(title: "\(languageManager.t("host.manage.section.presets")) (\(viewModel.presets.count))", section: 1)
            }
            .padding(4)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(8)
            .padding()

            if selectedSection == 0 {
                HostsManagementView(viewModel: viewModel)
            } else {
                PresetsManagementView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func customTabButton(title: String, section: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSection = section
            }
        } label: {
            Text(title)
                .font(Theme.Fonts.body(12))
                .fontWeight(selectedSection == section ? .medium : .regular)
                .foregroundStyle(selectedSection == section ? Color.white : Theme.Colors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.Colors.accentBlue)
                                .matchedGeometryEffect(id: "HostManageTabBackground", in: animation)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageManager.t("sidebar.hosts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .padding(.bottom, 12)

            if viewModel.hosts.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_hosts"), systemImage: "server.rack", description: Text(languageManager.t("host.manage.add_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                title: languageManager.t("editor.add_host"),
                name: $newHostName,
                address: $newHostAddress,
                command: $newHostCommand,
                displayRules: $newHostRules,
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmedName.isEmpty && !trimmedAddress.isEmpty {
                        viewModel.addHost(name: trimmedName, address: trimmedAddress, command: trimmedCommand, displayRules: newHostRules.isEmpty ? nil : newHostRules)
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
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmedName.isEmpty && !trimmedAddress.isEmpty {
                        if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                            viewModel.updateHost(at: index, name: trimmedName, address: trimmedAddress, command: trimmedCommand, displayRules: newHostRules)
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
                    .help(languageManager.t("menu.edit"))

                    Button { onDelete() } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("menu.delete"))
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
        .frame(maxHeight: .infinity, alignment: .top)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .padding(.bottom, 12)

            if viewModel.presets.isEmpty {
                ContentUnavailableView(languageManager.t("host.manage.no_presets"), systemImage: "bookmark", description: Text(languageManager.t("host.manage.add_preset_hint")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .help(languageManager.t("menu.add_to_monitor"))
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
        .frame(height: 110, alignment: .top)
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
    let onSave: () -> Void
    @State private var showingAddRule = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            ScrollView {
                Form {
                    Section(languageManager.t("editor.section.basic")) {
                        TextField(languageManager.t("editor.name"), text: $name)
                        TextField(languageManager.t("editor.address"), text: $address)
                            .textContentType(.URL)

                        VStack(alignment: .leading, spacing: 4) {
                            TextField(languageManager.t("editor.command"), text: $command)
                            Text(languageManager.t("editor.command_hint"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            // Row 2: Condition + Threshold + Label (properly spaced)
            HStack(spacing: 8) {
                // Condition picker
                Picker("", selection: $rule.condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                .frame(width: 90)

                // Threshold
                HStack(spacing: 4) {
                    TextField("", value: $rule.threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 45)
                    Text("ms")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 4)

                // Static Label "显示文本"
                Text(languageManager.t("editor.rule.label"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)

                // Label TextField
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $rule.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            .frame(height: 28) // Force consistent height to fix vertical alignment
        }
        .padding(.vertical, 8)
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
        VStack(spacing: 20) {
            Text(languageManager.t("editor.add_rule"))
                .font(.headline)

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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)

            Form {
                TextField(languageManager.t("editor.name"), text: $name)
                TextField(languageManager.t("editor.address"), text: $address)
                    .textContentType(.URL)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(languageManager.t("editor.command"), text: $command)
                    Text(languageManager.t("editor.command_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
