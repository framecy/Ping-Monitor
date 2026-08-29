import SwiftUI

// 从 MainView.swift 拆出：监控页 + 快捷服务带 + 拖拽排序

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
                HStack {
                    Text("\(languageManager.t("monitor.title")) (\(viewModel.hosts.count))")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                    Spacer()
                    Button {
                        showingAddHost = true
                    } label: {
                        Label(languageManager.t("monitor.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .cardBar()
                
                if viewModel.hosts.isEmpty {
                    ContentUnavailableView(languageManager.t("monitor.no_hosts"), systemImage: "network", description: Text(languageManager.t("monitor.add_host_hint")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // Insert Quick Access Services Ribbon here
                        QuickAccessServicesRibbon(viewModel: viewModel)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 280, maximum: .infinity), spacing: 12)
                        ], spacing: 12) {
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
                        .padding()
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
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.accentOrange)
                        Text(LanguageManager.shared.t("monitor.quick_access"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.leading, 14)

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
                    .padding(.trailing, 8)
                }
                .frame(height: 36)

                // Expanded content
                if isExpanded {
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(height: 1)
                        .padding(.horizontal, 14)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(hostGroups, id: \.host.id) { group in
                            hostRow(group: group)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .background(Theme.Colors.cardBackground.opacity(0.42))
            .overlay(
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    @ViewBuilder
    private func hostRow(group: (host: HostConfig, shortcuts: [ServiceShortcut])) -> some View {
        HStack(spacing: 10) {
            // Status dot + host name (fixed-width label column)
            HStack(spacing: 5) {
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
                HStack(spacing: 4) {
                    ForEach(group.shortcuts) { shortcut in
                        serviceChip(shortcut: shortcut, host: group.host)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
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
            .padding(.horizontal, 8)
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
            .padding(.vertical, 2)
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
