import SwiftUI

// MARK: - Tailscale Tab

struct TailscaleTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @ObservedObject private var tailscale = TailscaleManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    /// 管理模式总闸，在设置页开启；关闭时清单是纯只读的。
    @AppStorage("pm.tailscaleAdminMode") private var adminMode: Bool = false

    @State private var confirmTarget: ConfirmTarget?
    @State private var tagTarget: TailnetDevice?
    @State private var tagDraft: String = ""

    /// 破坏性动作的二次确认目标。
    struct ConfirmTarget: Identifiable {
        enum Kind { case deauthorize, delete }
        let device: TailnetDevice
        let kind: Kind
        var id: String { device.id + String(describing: kind) }
    }

    var body: some View {
        ScrollPage {
            // Status Card
            statusCard

            // 全局监管清单（控制面）
            tailnetInventoryCard

            // NAT / Netcheck Card
            netcheckCard

            // Health Advice
            healthAdviceCard

            // Quick Commands
            quickCommandsCard

            // DERP Region Latency
            if !tailscale.regionLatencies.isEmpty {
                derpLatencyCard
            }

            // Nodes List
            nodesCard
        }
        .onAppear {
            tailscale.fetchStatus()
            tailscale.fetchNetcheck()
            tailscale.refreshInventory()
        }
        .alert(item: $confirmTarget) { target in
            switch target.kind {
            case .deauthorize:
                return Alert(
                    title: Text(languageManager.t("tailscale.admin.confirm_deauthorize_title")),
                    message: Text(String(format: languageManager.t("tailscale.admin.confirm_deauthorize_body"), target.device.hostname)),
                    primaryButton: .destructive(Text(languageManager.t("tailscale.admin.deauthorize"))) {
                        tailscale.perform(.authorize(false), on: target.device)
                    },
                    secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                )
            case .delete:
                return Alert(
                    title: Text(languageManager.t("tailscale.admin.confirm_delete_title")),
                    message: Text(String(format: languageManager.t("tailscale.admin.confirm_delete_body"), target.device.hostname)),
                    primaryButton: .destructive(Text(languageManager.t("tailscale.admin.delete"))) {
                        tailscale.perform(.delete, on: target.device)
                    },
                    secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                )
            }
        }
        .sheet(item: $tagTarget) { device in
            tagEditor(device)
        }
    }

    // MARK: - 标签编辑

    private func tagEditor(_ device: TailnetDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: languageManager.t("tailscale.admin.edit_tags_title"), device.hostname))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))

            TextField("tag:server, tag:prod", text: $tagDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.accentOrange)
                Text(languageManager.t("tailscale.admin.tags_note"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 360, alignment: .leading)

            HStack {
                Spacer()
                Button(languageManager.t("common.cancel")) { tagTarget = nil }
                Button(languageManager.t("common.save")) {
                    let tags = tagDraft
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        // 控制面要求 tag 必须带 tag: 前缀，这里替用户补全。
                        .map { $0.hasPrefix("tag:") ? $0 : "tag:\($0)" }
                    tailscale.perform(.tags(tags), on: device)
                    tagTarget = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
    }
    
    // MARK: - Tailnet Inventory Card（控制面全局监管）

    private var monitoredAddresses: Set<String> {
        Set(viewModel.hosts.map { $0.address })
    }

    private var tailnetInventoryCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.inventory.title"), icon: "list.bullet.rectangle.portrait")
                    Spacer()

                    if tailscale.hasInventoryCredentials {
                        Button(action: { tailscale.importAllOnlineDevices(into: viewModel) }) {
                            Text(languageManager.t("tailscale.inventory.import_all_online"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .padding(.horizontal, Theme.Space.sm)
                                .padding(.vertical, Theme.Space.xs)
                                .background(Theme.Colors.accentBlue.opacity(0.15))
                                .foregroundStyle(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.Radius.sm)
                        }
                        .buttonStyle(.plain)
                        .disabled(tailscale.tailnetDevices.isEmpty)

                        Button(action: { tailscale.refreshInventory() }) {
                            HStack(spacing: Theme.Space.xs) {
                                if tailscale.isFetchingInventory {
                                    ProgressView().controlSize(.small).scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.clockwise").font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                }
                                Text(languageManager.t("tailscale.refresh"))
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            }
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, Theme.Space.xs)
                            .background(Theme.Colors.cardBackground)
                            .cornerRadius(Theme.Radius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(tailscale.isFetchingInventory)
                    }
                }

                HStack(spacing: 6) {
                    Text(languageManager.t("tailscale.inventory.subtitle"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if adminMode {
                        Badge(text: languageManager.t("tailscale.admin.mode"), color: Theme.Colors.accentOrange)
                    }
                }

                if let actionError = tailscale.lastActionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                        Text(actionError)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(action: { tailscale.lastActionError = nil }) {
                            Image(systemName: "xmark")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.micro))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(Theme.Colors.accentRed)
                    .padding(Theme.Space.sm)
                    .background(Theme.Colors.accentRed.opacity(0.1))
                    .cornerRadius(Theme.Radius.sm)
                }

                switch tailscale.inventoryState {
                case .notConfigured:
                    inventoryPlaceholder(
                        icon: "key.slash",
                        text: languageManager.t("tailscale.inventory.not_configured"),
                        color: Theme.Colors.accentOrange
                    )
                case .failed(let message):
                    inventoryPlaceholder(icon: "exclamationmark.triangle.fill", text: message, color: Theme.Colors.accentRed)
                case .ok:
                    if tailscale.tailnetDevices.isEmpty {
                        inventoryPlaceholder(
                            icon: "tray",
                            text: languageManager.t("tailscale.inventory.empty"),
                            color: Theme.Colors.textTertiary
                        )
                    } else {
                        inventorySummaryRow
                        Divider().opacity(0.15)
                        ForEach(tailscale.tailnetDevices) { device in
                            inventoryRow(device)
                            if device.id != tailscale.tailnetDevices.last?.id {
                                Divider().opacity(0.1)
                            }
                        }
                    }
                }

                if let synced = tailscale.lastInventorySync {
                    Text("\(languageManager.t("tailscale.inventory.last_sync"))  \(synced.formatted(date: .omitted, time: .standard))")
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private func inventoryPlaceholder(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                .foregroundStyle(color)
            Text(text)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(Theme.Radius.md)
    }

    private var inventorySummaryRow: some View {
        let summary = tailscale.inventorySummary(monitoredAddresses: monitoredAddresses)
        return HStack(spacing: Theme.Space.sm) {
            inventoryStat(languageManager.t("tailscale.inventory.total"), summary.total, Theme.Colors.accentBlue)
            inventoryStat(languageManager.t("tailscale.online"), summary.online, Theme.Colors.accentGreen)
            inventoryStat(languageManager.t("tailscale.inventory.monitored"), summary.monitored, Theme.Colors.accentPurple)
            if summary.updateAvailable > 0 {
                inventoryStat(languageManager.t("tailscale.inventory.update_available"), summary.updateAvailable, Theme.Colors.accentOrange)
            }
            if summary.keyExpiring > 0 {
                inventoryStat(languageManager.t("tailscale.inventory.key_expiring"), summary.keyExpiring, Theme.Colors.accentOrange)
            }
            if summary.unauthorized > 0 {
                inventoryStat(languageManager.t("tailscale.inventory.unauthorized"), summary.unauthorized, Theme.Colors.accentRed)
            }
            Spacer()
        }
    }

    private func inventoryStat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("\(value)")
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(Theme.Radius.sm)
    }

    private func inventoryRow(_ device: TailnetDevice) -> some View {
        let isMonitored = monitoredAddresses.contains(device.tailscaleIP)
        let localPath = tailscale.localNode(forIP: device.tailscaleIP)

        return HStack(spacing: 10) {
            Circle()
                .fill(device.isOnline ? Theme.Colors.accentGreen : Theme.Colors.textTertiary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: 6) {
                    Text(device.hostname)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    ForEach(device.tags, id: \.self) { tag in
                        Badge(text: tag.replacingOccurrences(of: "tag:", with: ""), color: Theme.Colors.accentCyan)
                    }
                    if device.keyExpired {
                        Badge(text: languageManager.t("tailscale.inventory.key_expired"), color: Theme.Colors.accentRed)
                    } else if device.keyExpiringSoon {
                        Badge(text: languageManager.t("tailscale.inventory.key_expiring"), color: Theme.Colors.accentOrange)
                    }
                    if !device.authorized {
                        Badge(text: languageManager.t("tailscale.inventory.unauthorized"), color: Theme.Colors.accentRed)
                    }
                    if device.updateAvailable {
                        Badge(text: languageManager.t("tailscale.inventory.update_available"), color: Theme.Colors.accentOrange)
                    }
                }

                HStack(spacing: Theme.Space.sm) {
                    Text(device.tailscaleIP)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(device.os)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    if let localPath, localPath.connectionType != .unknown {
                        Text(localPath.connectionType.rawValue)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                            .foregroundStyle(localPath.connectionType == .p2p ? Theme.Colors.accentGreen : Theme.Colors.accentOrange)
                    }
                    if !device.isOnline, let lastSeen = device.lastSeen {
                        Text("\(languageManager.t("tailscale.inventory.last_seen")) \(lastSeen.formatted(date: .abbreviated, time: .shortened))")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            if isMonitored {
                Text(languageManager.t("tailscale.already_monitored"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                    .foregroundStyle(Theme.Colors.accentGreen)
            } else {
                Button(action: { tailscale.importDevice(device, into: viewModel) }) {
                    Text(languageManager.t("tailscale.import"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .foregroundStyle(Theme.Colors.accentBlue)
                        .cornerRadius(Theme.Radius.xs)
                }
                .buttonStyle(.plain)
                .disabled(device.tailscaleIP.isEmpty)
            }

            if adminMode {
                adminMenu(device)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 管理动作（仅管理模式可见）

    @ViewBuilder
    private func adminMenu(_ device: TailnetDevice) -> some View {
        if tailscale.pendingActionDeviceID == device.id {
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 22)
        } else {
            Menu {
                Button(device.authorized
                       ? languageManager.t("tailscale.admin.deauthorize")
                       : languageManager.t("tailscale.admin.authorize")) {
                    if device.authorized {
                        confirmTarget = ConfirmTarget(device: device, kind: .deauthorize)
                    } else {
                        tailscale.perform(.authorize(true), on: device)
                    }
                }

                Button(device.keyExpiryDisabled
                       ? languageManager.t("tailscale.admin.enable_key_expiry")
                       : languageManager.t("tailscale.admin.disable_key_expiry")) {
                    tailscale.perform(.keyExpiryDisabled(!device.keyExpiryDisabled), on: device)
                }

                if !device.advertisedRoutes.isEmpty {
                    Menu(languageManager.t("tailscale.admin.routes")) {
                        ForEach(device.advertisedRoutes, id: \.self) { route in
                            let enabled = device.enabledRoutes.contains(route)
                            Button {
                                tailscale.toggleRoute(route, on: device)
                            } label: {
                                HStack {
                                    Text(route == "0.0.0.0/0" || route == "::/0"
                                         ? "\(route)  (\(languageManager.t("tailscale.admin.exit_route")))"
                                         : route)
                                    if enabled { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }

                Button(languageManager.t("tailscale.admin.edit_tags")) {
                    tagDraft = device.tags.joined(separator: ", ")
                    tagTarget = device
                }

                Divider()

                Button(languageManager.t("tailscale.admin.delete"), role: .destructive) {
                    confirmTarget = ConfirmTarget(device: device, kind: .delete)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .disabled(tailscale.pendingActionDeviceID != nil)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.title"), icon: "network")
                    Spacer()
                    Button(action: {
                        tailscale.fetchStatus()
                        tailscale.fetchNetcheck()
                    }) {
                        HStack(spacing: Theme.Space.xs) {
                            if tailscale.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.footnote, weight: .semibold))
                            }
                            Text(languageManager.t("tailscale.refresh"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, Theme.Space.xs)
                        .background(Theme.Colors.cardBackground)
                        .cornerRadius(Theme.Radius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(tailscale.isLoading)
                }
                
                HStack(spacing: Theme.Space.xxl) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(languageManager.t("tailscale.status"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tailscale.isConnected ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
                                .frame(width: 8, height: 8)
                            Text(tailscale.isConnected ? languageManager.t("tailscale.connected") : languageManager.t("tailscale.disconnected"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                                .foregroundStyle(tailscale.isConnected ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(languageManager.t("tailscale.my_ip"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.selfIP.isEmpty ? "—" : tailscale.selfIP)
                            .font(Theme.Fonts.number(Theme.Fonts.Size.headline, weight: .bold))
                            .foregroundStyle(Theme.Colors.accentBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    Divider().frame(height: 30).opacity(0.3)
                    
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(languageManager.t("tailscale.nodes"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("\(tailscale.nodes.count)")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    
                    Spacer()
                }
                
                if let error = tailscale.lastError {
                    Text(error)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.accentRed)
                        .padding(Theme.Space.sm)
                        .background(Theme.Colors.accentRed.opacity(0.1))
                        .cornerRadius(Theme.Radius.sm)
                }
            }
        }
    }
    
    // MARK: - Quick Commands Card
    
    private var quickCommandsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeader(title: "Quick Commands", icon: "command")
                
                HStack(spacing: Theme.Space.md) {
                    CommandButton(title: "Status", icon: "terminal", action: { tailscale.fetchStatus() })
                    CommandButton(title: "Netcheck", icon: "shield.checkered", action: { tailscale.fetchNetcheck() })
                    CommandButton(title: "Ping All", icon: "waveform", action: { executeTailscale("ping --all") })
                }
            }
        }
    }
    
    private func executeTailscale(_ cmd: String) {
        let args = cmd.components(separatedBy: " ")
        Task {
            await tailscale.runTailscaleCommand(args)
        }
    }
    
    struct CommandButton: View {
        let title: String
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                    Text(title)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.Colors.cardBackground)
                .cornerRadius(Theme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Colors.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Netcheck Card
    
    private var netcheckCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.netcheck"), icon: "shield.checkered")
                    Spacer()
                    if tailscale.netcheckLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
                
                // NAT Type (prominent)
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: natIcon)
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.display))
                        .foregroundStyle(natColor)
                        .frame(width: 36, height: 36)
                        .background(natColor.opacity(0.12))
                        .cornerRadius(Theme.Radius.md)
                    
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(languageManager.t("tailscale.nat_type"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.natType)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                            .foregroundStyle(natColor)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                        Text(languageManager.t("tailscale.preferred_derp"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(tailscale.preferredDERP)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accentBlue)
                    }
                }
                
                Divider().opacity(0.2)
                
                // Protocol indicators
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    protocolBadge(label: "UDP", enabled: tailscale.udpEnabled)
                    protocolBadge(label: "IPv4", enabled: tailscale.ipv4Enabled)
                    protocolBadge(label: "IPv6", enabled: tailscale.ipv6Enabled)
                    protocolBadge(label: "UPnP", enabled: tailscale.upnp ?? false)
                    protocolBadge(label: "Hairpin", enabled: tailscale.hairPinning ?? false)
                    protocolBadge(label: languageManager.t("tailscale.captive_portal"), enabled: !tailscale.captivePortal, invertColor: true)
                }
                
                // Global IPs
                if tailscale.globalIPv4 != "—" || tailscale.globalIPv6 != "—" {
                    Divider().opacity(0.2)
                    HStack(spacing: Theme.Space.xl) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("Global IPv4")
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(tailscale.globalIPv4)
                                .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("Global IPv6")
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(tailscale.globalIPv6)
                                .font(Theme.Fonts.number(Theme.Fonts.Size.body))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - DERP Latency Card
    
    private var derpLatencyCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeader(title: languageManager.t("tailscale.derp_latency"), icon: "globe.americas.fill")
                
                ForEach(tailscale.regionLatencies.prefix(10)) { region in
                    HStack(spacing: 10) {
                        Text(region.regionName)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 120, alignment: .leading)
                        
                        GeometryReader { geo in
                            let maxLatency = tailscale.regionLatencies.map(\.latency).max() ?? 1
                            let ratio = min(region.latency / maxLatency, 1.0)
                            RoundedRectangle(cornerRadius: Theme.Radius.xs)
                                .fill(latencyBarColor(region.latency))
                                .frame(width: max(geo.size.width * ratio, 4))
                        }
                        .frame(height: 8)
                        
                        Text(String(format: "%.0fms", region.latency))
                            .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .medium))
                            .foregroundStyle(latencyBarColor(region.latency))
                            .frame(width: 55, alignment: .trailing)
                    }
                    .frame(height: 20)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func protocolBadge(label: String, enabled: Bool, invertColor: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(invertColor ? (enabled ? Theme.Colors.accentGreen : Theme.Colors.accentRed) : (enabled ? Theme.Colors.accentGreen : Theme.Colors.accentRed.opacity(0.5)))
                .frame(width: 6, height: 6)
            Text(label)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(enabled ? "✓" : "✗")
                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .bold))
                .foregroundStyle(enabled ? Theme.Colors.accentGreen : Theme.Colors.accentRed.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Radius.sm)
    }
    
    private var natIcon: String {
        switch tailscale.natType {
        case "Easy NAT", "Full Cone NAT": return "checkmark.shield.fill"
        case "Symmetric NAT": return "exclamationmark.shield.fill"
        default: return "xmark.shield.fill"
        }
    }
    
    private var natColor: Color {
        switch tailscale.natType {
        case "Easy NAT", "Full Cone NAT": return Theme.Colors.accentGreen
        case "Symmetric NAT": return Theme.Colors.accentOrange
        default: return Theme.Colors.accentRed
        }
    }
    
    private func latencyBarColor(_ ms: Double) -> Color {
        Theme.Status.latency(ms, .overlay)
    }
    
    private var healthAdviceCard: some View {
        Group {
            if !tailscale.healthAdvice.isEmpty {
                ModernCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: languageManager.t("tailscale.health_report"), icon: "heart.text.square.fill")
                        
                        ForEach(tailscale.healthAdvice, id: \.self) { advice in
                            HStack(alignment: .top, spacing: Theme.Space.sm) {
                                Image(systemName: "lightbulb.fill")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.body))
                                    .foregroundStyle(Theme.Colors.accentOrange)
                                    .padding(.top, Theme.Space.xxs)
                                Text(advice)
                                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.cardBackground.opacity(0.5))
                            .cornerRadius(Theme.Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .stroke(Theme.Colors.accentOrange.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func connectionTypeBadge(_ type: TailscaleConnectionType) -> some View {
        let (color, icon): (Color, String) = {
            switch type {
            case .p2p: return (Theme.Colors.accentGreen, "bolt.fill")
            case .relay: return (Theme.Colors.accentOrange, "arrow.triangle.2.circlepath")
            case .derp: return (Theme.Colors.accentPurple, "cloud.fill")
            case .unknown: return (Theme.Colors.textTertiary, "questionmark.circle")
            }
        }()

        return Badge(text: type.rawValue, color: color, icon: icon, style: .pill)
    }
    
    // MARK: - Nodes Card
    
    private var nodesCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    SectionHeader(title: languageManager.t("tailscale.nodes"), icon: "desktopcomputer")
                    Spacer()
                    
                    Button(action: {
                        tailscale.importAllOnlineNodes(into: viewModel)
                    }) {
                        HStack(spacing: Theme.Space.xs) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold))
                            Text(languageManager.t("tailscale.import_all"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, Theme.Space.xs)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(Theme.Radius.sm)
                    }
                    .buttonStyle(.plain)
                }
                
                if tailscale.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 30)
                        Spacer()
                    }
                } else if tailscale.nodes.isEmpty {
                    Text(languageManager.t("tailscale.not_available"))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tailscale.nodes) { node in
                            nodeRow(node)
                            if node.id != tailscale.nodes.last?.id {
                                Divider().padding(.vertical, Theme.Space.xxs)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Node Row
    
    private func nodeRow(_ node: TailscaleNode) -> some View {
        let isMonitored = viewModel.hosts.contains(where: { $0.address == node.tailscaleIP })
        
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: node.osIcon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.headline))
                    .foregroundStyle(node.online ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: 6) {
                        Text(node.hostname)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if node.isSelf {
                            Text(languageManager.t("tailscale.self"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .bold))
                                .foregroundStyle(Theme.Colors.onAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, Theme.Space.xxs)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.Radius.xs)
                                .layoutPriority(1)
                        }
                    }
                    
                    Text(node.tailscaleIP)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    HStack(spacing: Theme.Space.xs) {
                        Circle()
                            .fill(node.online ? Theme.Colors.accentGreen : Theme.Colors.accentRed.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(node.online ? languageManager.t("tailscale.online") : languageManager.t("tailscale.offline"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                            .foregroundStyle(node.online ? Theme.Colors.accentGreen : Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    
                    // Connection type badge
                    if node.connectionType != .unknown {
                        connectionTypeBadge(node.connectionType)
                            .layoutPriority(1)
                    }
                    
                    if node.online && !node.isSelf {
                        Button(action: {
                            tailscale.runPathDiagnosis(for: node)
                        }) {
                            if node.isCheckingPath {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                                    .frame(width: 20)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                                    .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                    .foregroundStyle(Theme.Colors.accentBlue)
                                    .frame(width: 20)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(node.isCheckingPath)
                    }
                    
                    if node.exitNode || node.exitNodeOption {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.accentPurple)
                            .help(node.exitNode ? "Active Exit Node" : "Exit Node Available")
                    }
                    
                    if !node.isSelf {
                        if isMonitored {
                            Text(languageManager.t("tailscale.already_monitored"))
                                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Space.sm)
                                .padding(.vertical, Theme.Space.xs)
                                .background(Theme.Colors.cardBackground)
                                .cornerRadius(Theme.Radius.xs)
                                .layoutPriority(1)
                        } else {
                            Button(action: {
                                tailscale.importNode(node, into: viewModel)
                            }) {
                                HStack(spacing: Theme.Space.xs) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                    Text(languageManager.t("tailscale.import"))
                                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, Theme.Space.sm)
                                .padding(.vertical, Theme.Space.xs)
                                .background(Theme.Colors.accentBlue.opacity(0.15))
                                .cornerRadius(Theme.Radius.xs)
                            }
                            .buttonStyle(.plain)
                            .layoutPriority(1)
                        }
                    }
                }
            }
            
            if let result = node.lastPingResult {
                HStack {
                    Spacer().frame(width: 40)
                    Text(result)
                        .font(Theme.Fonts.number(Theme.Fonts.Size.micro))
                        .foregroundStyle(result.contains("P2P") ? Theme.Colors.accentGreen : (result.contains("Error") ? Theme.Colors.accentRed : Theme.Colors.accentOrange))
                        .padding(.horizontal, 6)
                        .padding(.vertical, Theme.Space.xxs)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(Theme.Radius.xs)
                    Spacer()
                }
                .padding(.top, -2)
            }
        }
        .padding(.vertical, Theme.Space.sm)
        .opacity(node.online ? 1.0 : 0.5)
    }
}
