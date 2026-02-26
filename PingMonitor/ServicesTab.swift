import SwiftUI

// MARK: - Services Tab

struct ServicesTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    
    private var hostsWithServices: [HostConfig] {
        viewModel.hosts.filter { !$0.serviceShortcuts.isEmpty }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ModernCard {
            VStack(spacing: 16) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.textTertiary)
                
                Text(languageManager.t("services.empty"))
                    .font(Theme.Fonts.display(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Text(languageManager.t("services.empty_hint"))
                    .font(Theme.Fonts.body(12))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    // MARK: - Host Services Card
    
    private func hostServicesCard(_ host: HostConfig) -> some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(host.isReachable ? Color.green : Color.red.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(host.name)
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(host.address)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                }
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140), spacing: 12)
                ], spacing: 12) {
                    ForEach(host.serviceShortcuts) { shortcut in
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
                    .font(.system(size: 16))
                    .foregroundStyle(serviceColor(for: shortcut.type))
                    .frame(width: 32, height: 32)
                    .background(serviceColor(for: shortcut.type).opacity(0.12))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.name)
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(shortcut.type.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(serviceColor(for: shortcut.type))
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(10)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            let script = "tell application \"Terminal\" to do script \"ssh \(shortcut.url)\""
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
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
    let onSave: (ServiceShortcut) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var icon: String = "globe"
    @State private var type: ServiceShortcut.ServiceType = .web
    
    private let iconOptions = [
        "globe", "network", "server.rack", "desktopcomputer",
        "externaldrive.connected.to.line.below", "house.fill",
        "film.fill", "music.note", "doc.text.fill", "photo.fill",
        "gamecontroller.fill", "chart.bar.fill", "lock.shield.fill",
        "terminal.fill", "cloud.fill", "gear"
    ]
    
    init(existingShortcut: ServiceShortcut? = nil, onSave: @escaping (ServiceShortcut) -> Void) {
        self.existingShortcut = existingShortcut
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(existingShortcut != nil ? languageManager.t("services.edit") : languageManager.t("services.add"))
                .font(Theme.Fonts.display(16))
                .foregroundStyle(Theme.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: 14) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.name"))
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("Synology DSM", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                // URL
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.url"))
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("http://100.100.1.30:5000", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Type
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.type"))
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Picker("", selection: $type) {
                        Text(languageManager.t("services.type.web")).tag(ServiceShortcut.ServiceType.web)
                        Text(languageManager.t("services.type.ssh")).tag(ServiceShortcut.ServiceType.ssh)
                        Text(languageManager.t("services.type.custom")).tag(ServiceShortcut.ServiceType.custom)
                    }
                    .pickerStyle(.segmented)
                }
                
                // Icon
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("services.icon"))
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Button(action: { icon = iconName }) {
                                Image(systemName: iconName)
                                    .font(.system(size: 14))
                                    .frame(width: 32, height: 32)
                                    .background(icon == iconName ? Theme.Colors.accentBlue.opacity(0.2) : Theme.Colors.cardBackground)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
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
                    let shortcut = ServiceShortcut(name: name, url: url, icon: icon, type: type)
                    onSave(shortcut)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            if let s = existingShortcut {
                name = s.name
                url = s.url
                icon = s.icon
                type = s.type
            }
        }
    }
}
