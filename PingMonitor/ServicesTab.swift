import SwiftUI

// MARK: - Services Tab

struct ServicesTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var showShortcutEditor = false
    @State private var editingShortcut: ServiceShortcut? = nil
    @State private var editingHostId: UUID? = nil
    @State private var filterType: ServiceShortcut.ServiceType? = nil
    
    private var allShortcuts: [(host: HostConfig, shortcut: ServiceShortcut)] {
        var result: [(host: HostConfig, shortcut: ServiceShortcut)] = []
        for host in viewModel.hosts {
            for shortcut in host.serviceShortcuts {
                if let filter = filterType {
                    if shortcut.type == filter {
                        result.append((host: host, shortcut: shortcut))
                    }
                } else {
                    result.append((host: host, shortcut: shortcut))
                }
            }
        }
        return result
    }
    
    private var hostsWithServices: [HostConfig] {
        viewModel.hosts.filter { host in
            host.serviceShortcuts.contains { shortcut in
                filterType == nil || shortcut.type == filterType
            }
        }
    }
    
    private var webCount: Int {
        viewModel.hosts.flatMap(\.serviceShortcuts).filter { $0.type == .web }.count
    }
    private var sshCount: Int {
        viewModel.hosts.flatMap(\.serviceShortcuts).filter { $0.type == .ssh }.count
    }
    private var customCount: Int {
        viewModel.hosts.flatMap(\.serviceShortcuts).filter { $0.type == .custom }.count
    }
    private var totalCount: Int { webCount + sshCount + customCount }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.gridSpacing) {
                // Stats + Controls header
                statsCard
                
                // Services list
                if hostsWithServices.isEmpty {
                    emptyState
                } else {
                    ForEach(hostsWithServices) { host in
                        hostServicesCard(host)
                    }
                }
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: $showShortcutEditor) {
            ShortcutEditorSheet(
                existingShortcut: editingShortcut,
                hostAddress: editingHostId.flatMap { hid in viewModel.hosts.first(where: { $0.id == hid })?.address },
                hostSelector: editingShortcut == nil ? viewModel.hosts : nil,
                selectedHostId: $editingHostId
            ) { shortcut in
                if let hid = editingHostId,
                   let hIndex = viewModel.hosts.firstIndex(where: { $0.id == hid }) {
                    if let existing = editingShortcut,
                       let sIndex = viewModel.hosts[hIndex].serviceShortcuts.firstIndex(where: { $0.id == existing.id }) {
                        viewModel.hosts[hIndex].serviceShortcuts[sIndex] = shortcut
                        LogManager.shared.info("Updated shortcut: \(shortcut.name)", host: viewModel.hosts[hIndex].name)
                    } else {
                        viewModel.hosts[hIndex].serviceShortcuts.append(shortcut)
                        LogManager.shared.info("Added shortcut: \(shortcut.name)", host: viewModel.hosts[hIndex].name)
                    }
                    viewModel.saveSettings()
                }
                editingShortcut = nil
                editingHostId = nil
            }
        }
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: languageManager.t("services.title"), icon: "square.grid.2x2.fill")
                    Spacer()
                    
                    // Add button
                    Button(action: {
                        editingShortcut = nil
                        editingHostId = viewModel.hosts.first?.id
                        showShortcutEditor = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            Text(languageManager.t("services.add"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(Theme.Radius.sm)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.hosts.isEmpty)
                }
                
                // Stats badges row
                HStack(spacing: 10) {
                    statBadge(
                        label: languageManager.t("services.all"),
                        count: totalCount,
                        color: Theme.Colors.textPrimary,
                        isSelected: filterType == nil
                    ) { filterType = nil }
                    
                    statBadge(
                        label: "Web",
                        count: webCount,
                        color: Theme.Colors.accentBlue,
                        isSelected: filterType == .web
                    ) { filterType = filterType == .web ? nil : .web }
                    
                    statBadge(
                        label: "SSH",
                        count: sshCount,
                        color: Theme.Colors.accentGreen,
                        isSelected: filterType == .ssh
                    ) { filterType = filterType == .ssh ? nil : .ssh }
                    
                    statBadge(
                        label: languageManager.t("services.type.custom"),
                        count: customCount,
                        color: Theme.Colors.accentOrange,
                        isSelected: filterType == .custom
                    ) { filterType = filterType == .custom ? nil : .custom }
                    
                    Spacer()
                }
            }
        }
    }
    
    private func statBadge(label: String, count: Int, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("\(count)")
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .bold))
                    .foregroundStyle(isSelected ? color : Theme.Colors.textSecondary)
                Text(label)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.12) : Theme.Colors.cardBackground)
            .cornerRadius(Theme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? color.opacity(0.3) : Theme.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ModernCard {
            VStack(spacing: 16) {
                Image(systemName: "square.grid.2x2")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.giant))
                    .foregroundStyle(Theme.Colors.textTertiary)
                
                Text(languageManager.t("services.empty"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Text(languageManager.t("services.empty_hint"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                    .foregroundStyle(Theme.Colors.textTertiary)
                
                if !viewModel.hosts.isEmpty {
                    Button(action: {
                        editingShortcut = nil
                        editingHostId = viewModel.hosts.first?.id
                        showShortcutEditor = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                            Text(languageManager.t("services.add"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(Theme.Radius.md)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    // MARK: - Host Services Card
    
    private func hostServicesCard(_ host: HostConfig) -> some View {
        let shortcuts = host.serviceShortcuts.filter { shortcut in
            filterType == nil || shortcut.type == filterType
        }
        
        return ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(host.isReachable ? Theme.Colors.accentGreen : Theme.Colors.accentRed.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(host.name)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(host.address)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    
                    Spacer()
                    
                    // Per-host add button
                    Button(action: {
                        editingShortcut = nil
                        editingHostId = host.id
                        showShortcutEditor = true
                    }) {
                        Image(systemName: "plus.circle")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .help(languageManager.t("services.add"))
                    
                    Text("\(shortcuts.count)")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.cardBackground)
                        .cornerRadius(Theme.Radius.xs)
                }
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200), spacing: 10)
                ], spacing: 10) {
                    ForEach(shortcuts) { shortcut in
                        serviceItem(shortcut, host: host)
                    }
                }
            }
        }
    }
    
    // MARK: - Service Item
    
    private func serviceItem(_ shortcut: ServiceShortcut, host: HostConfig) -> some View {
        Button(action: {
            openService(shortcut, host: host)
        }) {
            HStack(spacing: 10) {
                Image(systemName: shortcut.icon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                    .foregroundStyle(serviceColor(for: shortcut.type))
                    .frame(width: 32, height: 32)
                    .background(serviceColor(for: shortcut.type).opacity(0.12))
                    .cornerRadius(Theme.Radius.md)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.name)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    // Show useful info based on type
                    Group {
                        if shortcut.type == .ssh {
                            Text(shortcut.sshUser.isEmpty ? shortcut.url : "\(shortcut.sshUser)@\(shortcut.url)")
                                .lineLimit(1)
                        } else {
                            Text(shortcut.url)
                                .lineLimit(1)
                        }
                    }
                    .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                // Type badge
                Text(shortcut.type.rawValue.uppercased())
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .bold))
                    .foregroundStyle(serviceColor(for: shortcut.type))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(serviceColor(for: shortcut.type).opacity(0.12))
                    .cornerRadius(Theme.Radius.xs)
                
                Image(systemName: "arrow.up.right")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(10)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { openService(shortcut, host: host) } label: {
                Label(languageManager.t("services.open"), systemImage: "arrow.up.right.square")
            }
            Button {
                editingShortcut = shortcut
                editingHostId = host.id
                showShortcutEditor = true
            } label: {
                Label(languageManager.t("services.edit"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                if let hIndex = viewModel.hosts.firstIndex(where: { $0.id == host.id }),
                   let sIndex = viewModel.hosts[hIndex].serviceShortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                    viewModel.hosts[hIndex].serviceShortcuts.remove(at: sIndex)
                    viewModel.saveSettings()
                }
            } label: {
                Label(languageManager.t("menu.delete"), systemImage: "trash")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func serviceColor(for type: ServiceShortcut.ServiceType) -> Color {
        switch type {
        case .web: return Theme.Colors.accentBlue
        case .ssh: return Theme.Colors.accentGreen
        case .custom: return Theme.Colors.accentOrange
        }
    }
    
    private func openService(_ shortcut: ServiceShortcut, host: HostConfig) {
        switch shortcut.type {
        case .web:
            if let url = URL(string: shortcut.url) {
                NSWorkspace.shared.open(url)
            }
        case .ssh:
            let sshCmd = shortcut.sshCommand
            // Use .command file — Terminal natively opens these, no AppleScript permissions needed
            let cmdFile = "/tmp/pm_ssh_\(UUID().uuidString.prefix(8)).command"
            let scriptContent = "#!/bin/bash\nrm -f \"\(cmdFile)\"\n\(sshCmd)\n"
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
        LogManager.shared.info("Opened service: \(shortcut.name) (\(shortcut.type.rawValue))", host: host.name)
    }
}

// MARK: - Add/Edit Shortcut Sheet

struct ShortcutEditorSheet: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    let existingShortcut: ServiceShortcut?
    let hostAddress: String?
    let hostSelector: [HostConfig]?
    @Binding var selectedHostId: UUID?
    let onSave: (ServiceShortcut) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var icon: String = "globe"
    @State private var type: ServiceShortcut.ServiceType = .web
    @State private var sshUser: String = ""
    @State private var sshPort: String = "22"
    @State private var sshAuthMode: ServiceShortcut.SSHAuthMode = .key
    @State private var sshKeyPath: String = ""
    @State private var sshPassword: String = ""
    
    private let iconOptions = [
        "globe", "network", "server.rack", "desktopcomputer",
        "externaldrive.connected.to.line.below", "house.fill",
        "film.fill", "music.note", "doc.text.fill", "photo.fill",
        "gamecontroller.fill", "chart.bar.fill", "lock.shield.fill",
        "terminal.fill", "cloud.fill", "gear"
    ]
    
    init(existingShortcut: ServiceShortcut? = nil, hostAddress: String? = nil, hostSelector: [HostConfig]? = nil, selectedHostId: Binding<UUID?>? = nil, onSave: @escaping (ServiceShortcut) -> Void) {
        self.existingShortcut = existingShortcut
        self.hostAddress = hostAddress
        self.hostSelector = hostSelector
        self._selectedHostId = selectedHostId ?? .constant(nil)
        self.onSave = onSave
    }
    
    private var effectiveHostAddress: String? {
        if let hostAddress { return hostAddress }
        if let hosts = hostSelector, let hid = selectedHostId {
            return hosts.first(where: { $0.id == hid })?.address
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(existingShortcut != nil ? languageManager.t("services.edit") : languageManager.t("services.add"))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: 14) {
                // Host selector (only in add mode from ServicesTab)
                if let hosts = hostSelector, existingShortcut == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("services.select_host"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Picker("", selection: Binding(
                            get: { selectedHostId ?? hosts.first?.id },
                            set: { selectedHostId = $0 }
                        )) {
                            ForEach(hosts) { host in
                                Text("\(host.name) (\(host.address))").tag(Optional(host.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                // Type
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.type"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Picker("", selection: $type) {
                        Text(languageManager.t("services.type.web")).tag(ServiceShortcut.ServiceType.web)
                        Text(languageManager.t("services.type.ssh")).tag(ServiceShortcut.ServiceType.ssh)
                        Text(languageManager.t("services.type.custom")).tag(ServiceShortcut.ServiceType.custom)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        if newType == .ssh {
                            icon = "terminal.fill"
                            if url.isEmpty, let addr = effectiveHostAddress {
                                url = addr
                            }
                        } else if newType == .web {
                            icon = "globe"
                        }
                    }
                }
                
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.name"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField(type == .ssh ? "My Server SSH" : "Synology DSM", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                // URL / Host
                VStack(alignment: .leading, spacing: 4) {
                    Text(type == .ssh ? languageManager.t("services.ssh.host") : languageManager.t("services.url"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField(type == .ssh ? "100.100.1.30" : "http://100.100.1.30:5000", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
                
                // SSH-specific fields
                if type == .ssh {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.t("services.ssh.user"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("root", text: $sshUser)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.t("services.ssh.port"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("22", text: $sshPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                    
                    // Auth Mode Toggle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("services.ssh.auth_mode"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Picker("", selection: $sshAuthMode) {
                            Text(languageManager.t("services.ssh.auth_key")).tag(ServiceShortcut.SSHAuthMode.key)
                            Text(languageManager.t("services.ssh.auth_password")).tag(ServiceShortcut.SSHAuthMode.password)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Conditional: Key Path or Password
                    if sshAuthMode == .key {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.t("services.ssh.key"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("~/.ssh/id_rsa (\(languageManager.t("services.ssh.key_optional")))", text: $sshKeyPath)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.t("services.ssh.password"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            SecureField(languageManager.t("services.ssh.password_hint"), text: $sshPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("services.ssh.preview"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(previewSSHCommand)
                            .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                            .foregroundStyle(Theme.Colors.accentGreen)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.codeBackground)
                            .cornerRadius(Theme.Radius.sm)
                    }
                }
                
                // Icon
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.icon"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Button(action: { icon = iconName }) {
                                Image(systemName: iconName)
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                                    .frame(width: 32, height: 32)
                                    .background(icon == iconName ? Theme.Colors.accentBlue.opacity(0.2) : Theme.Colors.cardBackground)
                                    .cornerRadius(Theme.Radius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                            .stroke(icon == iconName ? Theme.Colors.accentBlue : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Buttons
            HStack {
                Button(languageManager.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(languageManager.t("common.save")) {
                    let port = Int(sshPort) ?? 22
                    let shortcut = ServiceShortcut(
                        name: name, url: url, icon: icon, type: type,
                        sshUser: sshUser, sshPort: port, sshAuthMode: sshAuthMode,
                        sshKeyPath: sshKeyPath, sshPassword: sshPassword
                    )
                    onSave(shortcut)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if let s = existingShortcut {
                name = s.name
                url = s.url
                icon = s.icon
                type = s.type
                sshUser = s.sshUser
                sshPort = String(s.sshPort)
                sshAuthMode = s.sshAuthMode
                sshKeyPath = s.sshKeyPath
                sshPassword = s.sshPassword
            }
        }
    }
    
    private var previewSSHCommand: String {
        var cmd = "ssh"
        let port = Int(sshPort) ?? 22
        if port != 22 { cmd += " -p \(port)" }
        if sshAuthMode == .key && !sshKeyPath.isEmpty { cmd += " -i \(sshKeyPath)" }
        if !sshUser.isEmpty {
            cmd += " \(sshUser)@\(url.isEmpty ? "host" : url)"
        } else {
            cmd += " \(url.isEmpty ? "host" : url)"
        }
        return cmd
    }
}
