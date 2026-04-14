import SwiftUI
import Charts

struct EditableHostCard: View {
    let host: HostConfig
    let viewModel: PingMonitorViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @ObservedObject private var languageManager = LanguageManager.shared

    private var probeDiagnostic: HostProbeDiagnostic? {
        viewModel.hostDiagnostics[host.id]
    }

    private var qualitySnapshot: HostQualitySnapshot {
        viewModel.qualitySnapshot(for: host)
    }
    
    var statusColor: Color {
        guard viewModel.isRunning else { return Theme.Colors.textSecondary }
        if host.isPaused { return Theme.Colors.textTertiary }
        if host.isChecking { return Theme.Colors.accentBlue }
        
        // Timeout/unreachable state
        if !host.isReachable { 
            // If it has history, it means it was timeout (Red)
            if let stats = viewModel.hostStats[host.id], !stats.latencyHistory.isEmpty {
                return Theme.Colors.accentRed
            } else {
                // Not yet pinged successfully ever
                return Theme.Colors.textSecondary
            }
        }
        
        // Reachable state (has latency)
        if let latency = host.lastLatency {
            if latency < 100 { return Theme.Colors.accentGreen }
            if latency < 300 { return Theme.Colors.accentOrange }
            return Theme.Colors.accentRed
        }
        
        return Theme.Colors.textSecondary
    }

    var borderColor: Color {
        isHovered ? statusColor.opacity(0.5) : Color.white.opacity(0.05)
    }

    private var diagnosticText: String? {
        if let failureReason = probeDiagnostic?.lastFailureReason {
            return failureReason.localizedDescription(using: languageManager)
        }
        if let pathSnapshot = probeDiagnostic?.lastPathSnapshot {
            return pathSnapshot.localizedDescription(using: languageManager)
        }
        return nil
    }

    private var diagnosticColor: Color {
        if let failureReason = probeDiagnostic?.lastFailureReason {
            switch failureReason.category {
            case .timeout, .noRoute, .networkUnreachable, .hostDown, .connectionRefused, .permissionDenied, .processError, .unknown:
                return Theme.Colors.accentRed
            case .dnsFailure:
                return Theme.Colors.accentOrange
            }
        }

        switch probeDiagnostic?.lastPathSnapshot?.kind {
        case .direct:
            return Theme.Colors.accentGreen
        case .relay:
            return Theme.Colors.accentOrange
        default:
            return Theme.Colors.textTertiary
        }
    }

    private var diagnosticIcon: String {
        if let failureReason = probeDiagnostic?.lastFailureReason {
            switch failureReason.category {
            case .timeout:
                return "clock.badge.exclamationmark"
            case .dnsFailure:
                return "globe.badge.chevron.backward"
            case .noRoute, .networkUnreachable:
                return "arrow.trianglehead.branch"
            case .hostDown:
                return "wifi.slash"
            case .connectionRefused:
                return "xmark.octagon"
            case .permissionDenied:
                return "lock.slash"
            case .processError, .unknown:
                return "exclamationmark.triangle"
            }
        }

        switch probeDiagnostic?.lastPathSnapshot?.kind {
        case .direct:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .relay:
            return "arrow.triangle.2.circlepath"
        default:
            return "info.circle"
        }
    }

    private var qualityColor: Color {
        switch qualitySnapshot.score {
        case 90...:
            return Theme.Colors.accentGreen
        case 75..<90:
            return Theme.Colors.accentBlue
        case 60..<75:
            return Theme.Colors.accentOrange
        case 40..<60:
            return Color.orange
        default:
            return Theme.Colors.accentRed
        }
    }

    private var pathLabel: String {
        switch qualitySnapshot.pathKind {
        case .direct:
            return languageManager.t("diagnostics.path.direct")
        case .relay:
            return languageManager.t("diagnostics.path.relay")
        case .unknown:
            return "—"
        }
    }

    @ViewBuilder
    private func compactMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.Colors.cardBackground.opacity(0.65))
        .cornerRadius(8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Icon, Name, Status
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundStyle(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(host.name)
                            .font(Theme.Fonts.display(14))
                            .foregroundStyle(host.isPaused ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                            .lineLimit(1)
                            
                        if host.isPaused {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    
                    Text(host.address)
                        .font(Theme.Fonts.body(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Live Latency
                if let latency = host.lastLatency, viewModel.isRunning {
                    Text("\(Int(latency)) ms")
                        .font(Theme.Fonts.number(14))
                        .foregroundStyle(statusColor)
                } else if !host.isReachable && viewModel.isRunning && !host.isChecking {
                    Text(languageManager.t("card.timeout"))
                        .font(Theme.Fonts.number(12))
                        .foregroundStyle(Theme.Colors.accentRed)
                }
            }
            
            // Sparkline
            if let stats = viewModel.hostStats[host.id], stats.latencyHistory.count > 1 {
                let history = Array(stats.latencyHistory.suffix(20))
                Chart {
                    ForEach(history) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Latency", point.latency)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(statusColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Latency", point.latency)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [statusColor.opacity(0.3), statusColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(height: 32) // Slightly increased for visibility
                .background(Color.white.opacity(0.02))
                .cornerRadius(4)
                .padding(.horizontal, 2)
            } else {
                Color.clear.frame(height: 32)
            }

            if qualitySnapshot.sampleCount > 0 {
                HStack(spacing: 8) {
                    compactMetric(title: languageManager.t("card.score"), value: "\(qualitySnapshot.score)", color: qualityColor)
                    compactMetric(
                        title: languageManager.t("card.p95"),
                        value: qualitySnapshot.p95Latency.map { String(format: "%.0fms", $0) } ?? "—",
                        color: Theme.Colors.accentBlue
                    )
                    compactMetric(
                        title: languageManager.t("card.loss"),
                        value: String(format: "%.1f%%", qualitySnapshot.packetLoss),
                        color: qualitySnapshot.packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary
                    )
                    compactMetric(title: languageManager.t("card.path"), value: pathLabel, color: diagnosticColor)
                }
            } else {
                HStack(spacing: 8) {
                    compactMetric(title: languageManager.t("card.score"), value: "—", color: Theme.Colors.textTertiary)
                    compactMetric(title: languageManager.t("card.p95"), value: "—", color: Theme.Colors.textTertiary)
                    compactMetric(title: languageManager.t("card.loss"), value: "—", color: Theme.Colors.textTertiary)
                    compactMetric(title: languageManager.t("card.path"), value: "—", color: Theme.Colors.textTertiary)
                }
            }
            
            // Footer: Rules & Actions
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: host.probeMode == .tcp ? "cable.connector" : "waveform.path.ecg")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(host.probeDisplayLabel)
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    if let diagnosticText {
                        Circle()
                            .fill(Theme.Colors.textTertiary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        Image(systemName: diagnosticIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(diagnosticColor)
                        Text(diagnosticText)
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(diagnosticColor)
                            .lineLimit(1)
                    }
                }
                
                Spacer()

                if !host.displayRules.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(String(format: languageManager.t("card.rules"), host.displayRules.count))
                            .font(Theme.Fonts.body(10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                
                if isHovered {
                    HStack(spacing: 6) {
                        Button {
                            viewModel.togglePing(for: host.id)
                        } label: {
                            Image(systemName: host.isPaused ? "play.fill" : "pause.fill")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .help(host.isPaused ? languageManager.t("header.start") : languageManager.t("header.stop"))
                        
                        Button { onEdit() } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .help(languageManager.t("menu.edit"))
                        
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.Colors.accentRed)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .help(languageManager.t("menu.delete"))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(height: 24)
        }
        .frame(height: 164, alignment: .top)
        .padding(Theme.Layout.cardPadding)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: isHovered ? statusColor.opacity(0.1) : Color.clear, radius: 8, y: 4)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                viewModel.togglePing(for: host.id)
            } label: {
                Label(host.isPaused ? languageManager.t("header.start") : languageManager.t("header.stop"), systemImage: host.isPaused ? "play.fill" : "pause.fill")
            }
            Divider()
            Button { onEdit() } label: { Label(languageManager.t("menu.edit"), systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label(languageManager.t("menu.delete"), systemImage: "trash") }
        }
    }
}
