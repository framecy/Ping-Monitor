import SwiftUI

// MARK: - Network Speed Tab

struct NetworkSpeedTab: View {
    @ObservedObject var viewModel: PingMonitorViewModel
    @StateObject private var speedManager = NetworkSpeedManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Speed overview card
                speedOverviewCard
                
                // Speed chart
                speedChartCard
                
                // Interface details
                interfaceDetailsCard
            }
            .padding(Theme.Layout.cardPadding)
        }
        .background(Theme.Colors.background)
        .onAppear { speedManager.startMonitoring() }
        .onDisappear {
            // Don't stop if status bar still needs speed data
            if !viewModel.showSpeedInMenu {
                speedManager.stopMonitoring()
            }
        }
    }
    
    // MARK: - Speed Overview Card
    
    private var speedOverviewCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: languageManager.t("netspeed.title"), icon: "chart.line.uptrend.xyaxis")
                    Spacer()
                    
                    // Refresh interval selector
                    Picker("", selection: Binding(
                        get: { speedManager.refreshInterval },
                        set: { speedManager.setRefreshInterval($0) }
                    )) {
                        Text("1s").tag(1.0 as TimeInterval)
                        Text("2s").tag(2.0 as TimeInterval)
                        Text("3s").tag(3.0 as TimeInterval)
                        Text("5s").tag(5.0 as TimeInterval)
                        Text("10s").tag(10.0 as TimeInterval)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    
                    // Interface selector
                    Picker("", selection: $speedManager.selectedInterface) {
                        Text(languageManager.t("netspeed.all_interfaces")).tag("all")
                        ForEach(speedManager.interfaces.filter { $0.isActive }) { iface in
                            Text(iface.displayName).tag(iface.id)
                        }
                    }
                    .frame(width: 180)
                }
                
                Divider().opacity(0.15)
                
                HStack(spacing: 0) {
                    // Upload speed
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.Colors.accentPurple)
                            Text(languageManager.t("netspeed.upload"))
                                .font(Theme.Fonts.body(11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        
                        Text(NetworkSpeedManager.formatSpeed(speedManager.totalSpeedOut))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.accentPurple)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(NetworkSpeedManager.formatBytes(speedManager.totalBytesOut))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 50).opacity(0.2)
                    
                    // Download speed
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 5) {
                            Text(languageManager.t("netspeed.download"))
                                .font(Theme.Fonts.body(11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.Colors.accentCyan)
                        }
                        
                        Text(NetworkSpeedManager.formatSpeed(speedManager.totalSpeedIn))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.accentCyan)
                        
                        HStack(spacing: 4) {
                            Text(NetworkSpeedManager.formatBytes(speedManager.totalBytesIn))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
    
    // MARK: - Speed Chart Card
    
    private var speedChartCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("netspeed.realtime_chart"), icon: "waveform.path.ecg")
                
                if speedManager.speedHistory.count < 2 {
                    Text(languageManager.t("netspeed.collecting"))
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                } else {
                    // Chart area
                    GeometryReader { geo in
                        let width = geo.size.width
                        let height: CGFloat = 120
                        let samples = speedManager.speedHistory
                        let maxSpeed = max(
                            samples.map(\.speedIn).max() ?? 1,
                            samples.map(\.speedOut).max() ?? 1,
                            1024 // minimum 1 KB/s scale
                        ) * 1.2
                        
                        ZStack(alignment: .topLeading) {
                            // Grid lines
                            ForEach(0..<4, id: \.self) { i in
                                let y = height * CGFloat(i) / 3
                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: width, y: y))
                                }
                                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                            }
                            
                            // Upload line (purple)
                            speedLine(samples: samples, keyPath: \.speedOut, maxSpeed: maxSpeed,
                                     width: width, height: height, color: Theme.Colors.accentPurple)
                            
                            // Download line (cyan)
                            speedLine(samples: samples, keyPath: \.speedIn, maxSpeed: maxSpeed,
                                     width: width, height: height, color: Theme.Colors.accentCyan)
                            
                            // Scale labels
                            VStack {
                                Text(NetworkSpeedManager.formatSpeed(maxSpeed))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                Spacer()
                                Text("0")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .frame(height: height)
                        }
                        .frame(height: height)
                    }
                    .frame(height: 120)
                    
                    // Legend
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Colors.accentPurple).frame(width: 6, height: 6)
                            Text(languageManager.t("netspeed.upload"))
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Theme.Colors.accentCyan).frame(width: 6, height: 6)
                            Text(languageManager.t("netspeed.download"))
                                .font(Theme.Fonts.body(10))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Text(languageManager.t("netspeed.last_60s"))
                            .font(Theme.Fonts.body(9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
    }
    
    private func speedLine(samples: [SpeedSample], keyPath: KeyPath<SpeedSample, Double>,
                           maxSpeed: Double, width: CGFloat, height: CGFloat, color: Color) -> some View {
        let points: [CGPoint] = samples.enumerated().map { idx, sample in
            let x = width * CGFloat(idx) / CGFloat(max(samples.count - 1, 1))
            let y = height - (height * CGFloat(sample[keyPath: keyPath]) / CGFloat(maxSpeed))
            return CGPoint(x: x, y: max(0, min(height, y)))
        }
        
        return ZStack {
            // Fill gradient
            Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x, y: height))
                path.addLine(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(colors: [color.opacity(0.2), color.opacity(0.02)],
                              startPoint: .top, endPoint: .bottom)
            )
            
            // Line
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(color, lineWidth: 1.5)
            
            // Current value dot
            if let last = points.last {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .position(last)
            }
        }
    }
    
    // MARK: - Interface Details Card
    
    private var interfaceDetailsCard: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: languageManager.t("netspeed.interfaces"), icon: "network")
                
                if speedManager.interfaces.isEmpty {
                    Text(languageManager.t("netspeed.no_interfaces"))
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    ForEach(speedManager.interfaces) { iface in
                        interfaceRow(iface)
                        
                        if iface.id != speedManager.interfaces.last?.id {
                            Divider().opacity(0.1)
                        }
                    }
                }
            }
        }
    }
    
    private func interfaceRow(_ iface: NetworkInterfaceStats) -> some View {
        HStack(spacing: 12) {
            // Interface icon + name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(iface.isActive ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(iface.displayName)
                        .font(Theme.Fonts.body(12))
                        .foregroundStyle(iface.isActive ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                
                // Errors
                if iface.errorsIn > 0 || iface.errorsOut > 0 {
                    Text("Errors: ↑\(iface.errorsOut) ↓\(iface.errorsIn)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.orange)
                }
            }
            .frame(minWidth: 150, alignment: .leading)
            
            Spacer()
            
            // Speed
            HStack(spacing: 16) {
                // Upload
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.Colors.accentPurple)
                        Text(NetworkSpeedManager.formatSpeed(iface.speedOut))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(iface.speedOut > 0 ? Theme.Colors.accentPurple : Theme.Colors.textTertiary)
                    }
                    Text(NetworkSpeedManager.formatBytes(iface.bytesOut))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                // Download
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.Colors.accentCyan)
                        Text(NetworkSpeedManager.formatSpeed(iface.speedIn))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(iface.speedIn > 0 ? Theme.Colors.accentCyan : Theme.Colors.textTertiary)
                    }
                    Text(NetworkSpeedManager.formatBytes(iface.bytesIn))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                // Packets
                VStack(alignment: .trailing, spacing: 1) {
                    Text("PKT ↑\(formatPackets(iface.packetsOut))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("PKT ↓\(formatPackets(iface.packetsIn))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            speedManager.selectedInterface = (speedManager.selectedInterface == iface.id) ? "all" : iface.id
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(speedManager.selectedInterface == iface.id ? Theme.Colors.accentBlue.opacity(0.08) : Color.clear)
                .padding(.horizontal, -6)
        )
    }
    
    private func formatPackets(_ count: UInt64) -> String {
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fK", Double(count) / 1000) }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }
}
