
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar Navigation Item
enum SidebarItem: String, CaseIterable, Identifiable {
    case monitor
    case statistics
    case traceroute
    case netspeed
    case tailscale
    case services
    case hosts
    case logs
    case settings

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .monitor: return LanguageManager.shared.t("sidebar.monitor")
        case .statistics: return LanguageManager.shared.t("sidebar.dashboard")
        case .traceroute: return LanguageManager.shared.t("sidebar.traceroute")
        case .netspeed: return LanguageManager.shared.t("sidebar.netspeed")
        case .tailscale: return LanguageManager.shared.t("sidebar.tailscale")
        case .services: return LanguageManager.shared.t("sidebar.services")
        case .hosts: return LanguageManager.shared.t("sidebar.hosts")
        case .logs: return LanguageManager.shared.t("sidebar.logs")
        case .settings: return LanguageManager.shared.t("sidebar.settings")
        }
    }

    var icon: String {
        switch self {
        case .monitor: return "waveform.path.ecg"
        case .statistics: return "chart.bar.fill"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .netspeed: return "chart.line.uptrend.xyaxis"
        case .tailscale: return "network"
        case .services: return "square.grid.2x2.fill"
        case .hosts: return "server.rack"
        case .logs: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var activeColor: Color {
        switch self {
        case .monitor: return .green
        case .statistics: return .blue
        case .traceroute: return .cyan
        case .netspeed: return .teal
        case .tailscale: return .indigo
        case .services: return .mint
        case .hosts: return .purple
        case .logs: return .orange
        case .settings: return .gray
        }
    }
}

struct MainView: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @State private var selectedItem: SidebarItem = .monitor
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedItem: $selectedItem)
                .frame(width: 220)
                .background(Theme.Colors.sidebarBackground)

            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)

            VStack(spacing: 0) {
                headerView

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.Colors.background)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onChange(of: languageManager.currentLanguage) { _, _ in
            viewModel.updateStatusBarDisplay()
            viewModel.syncToWidget()
        }
    }

    // MARK: - Detail Content
    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem {
        case .monitor:
            MonitorTab(viewModel: viewModel)
        case .statistics:
            DashboardView(viewModel: viewModel)
        case .traceroute:
            TracerouteView(viewModel: viewModel)
        case .netspeed:
            NetworkSpeedTab(viewModel: viewModel)
        case .tailscale:
            TailscaleTab(viewModel: viewModel)
        case .services:
            ServicesTab(viewModel: viewModel)
        case .hosts:
            HostManagementTab(viewModel: viewModel)
        case .logs:
            LogsTab()
        case .settings:
            SettingsTab(viewModel: viewModel)
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 14) {
            // Animated status indicator
            ZStack {
                if viewModel.isRunning {
                    Circle()
                        .fill(.green.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .scaleEffect(viewModel.isRunning ? 1.6 : 1.0)
                        .opacity(viewModel.isRunning ? 0 : 0.6)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isRunning)
                }
                Circle()
                    .fill(viewModel.isRunning ? .green : .gray.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .shadow(color: viewModel.isRunning ? .green.opacity(0.5) : .clear, radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedItem.title)
                    .font(.system(size: 16, weight: .bold))
                Text(viewModel.isRunning ? String(format: languageManager.t("header.monitoring"), viewModel.hosts.count) : languageManager.t("header.stopped"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Language Toggle
            Button(action: { languageManager.toggle() }) {
                Text(languageManager.currentLanguage == .zh ? "EN" : "中")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(6)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Switch Language")

            Button(action: { viewModel.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(viewModel.isRunning ? languageManager.t("header.stop") : languageManager.t("header.start"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(viewModel.isRunning ? .red.opacity(0.15) : .green.opacity(0.15))
                )
                .foregroundStyle(viewModel.isRunning ? .red : .green)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    viewModel.isRunning ? Color.green.opacity(0.04) : Color.gray.opacity(0.03),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .background(.ultraThinMaterial)
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
