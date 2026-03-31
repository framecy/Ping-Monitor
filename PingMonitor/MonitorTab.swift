import SwiftUI

// MARK: - 监控 Tab
struct MonitorTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var editingHost: HostConfig?
    @State private var selectedHost: HostConfig?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostCommand = ""
    @State private var newHostRules: [DisplayRule] = []
    @State private var showingAddHost = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    Text("\(languageManager.t("monitor.title")) (\(viewModel.hosts.count))")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddHost = true
                    } label: {
                        Label(languageManager.t("monitor.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(.ultraThinMaterial)

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
                onSave: {
                    viewModel.addHost(name: newHostName, address: newHostAddress, command: newHostCommand, displayRules: newHostRules.isEmpty ? nil : newHostRules)
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
                onSave: {
                    let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAddress = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCommand = newHostCommand.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                        viewModel.updateHost(at: index, name: trimmedName, address: trimmedAddress, command: trimmedCommand, displayRules: newHostRules)
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
    }
}

// MARK: - Quick Access Services Ribbon
struct QuickAccessServicesRibbon: View {
    @ObservedObject var viewModel: PingMonitorViewModel

    var allShortcuts: [(host: HostConfig, shortcut: ServiceShortcut)] {
        viewModel.hosts.flatMap { host in
            host.serviceShortcuts.map { (host: host, shortcut: $0) }
        }
    }

    var body: some View {
        if !allShortcuts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.accentOrange)
                    Text("Quick Access")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: .infinity), spacing: 12)
                ], spacing: 12) {
                    ForEach(allShortcuts, id: \.shortcut.id) { item in
                        Button(action: {
                            openService(item.shortcut, host: item.host)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: item.shortcut.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(serviceColor(for: item.shortcut.type))
                                    .frame(width: 24, height: 24)
                                    .background(serviceColor(for: item.shortcut.type).opacity(0.12))
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.shortcut.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text(item.host.name)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.cardBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Theme.Colors.cardBackground.opacity(0.5))
        }
    }

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
