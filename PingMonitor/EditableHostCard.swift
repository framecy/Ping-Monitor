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
        isHovered ? statusColor.opacity(0.5) : Theme.Colors.cardBorder
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
        Theme.Status.score(qualitySnapshot.score)
    }

    /// Score is only meaningful once we have collected enough samples.
    /// Below this threshold the dimensions fall back to defaults (e.g. 100% availability,
    /// 80 bandwidth) and produce a misleadingly high score.
    private var hasEnoughQualityData: Bool {
        qualitySnapshot.sampleCount >= 5
    }

    private var gradeLabel: String {
        switch qualitySnapshot.score {
        case 90...: return languageManager.t("stats.grade.excellent")
        case 75..<90: return languageManager.t("stats.grade.good")
        case 60..<75: return languageManager.t("stats.grade.fair")
        case 40..<60: return languageManager.t("stats.grade.poor")
        default: return languageManager.t("stats.grade.critical")
        }
    }

    private var availabilityColor: Color {
        guard hasEnoughQualityData else { return Theme.Colors.textSecondary }
        return Theme.Status.ratio(qualitySnapshot.availability, good: 99, warning: 95)
    }

    private var availabilityText: String {
        guard hasEnoughQualityData else { return "—" }
        return String(format: "%.1f%%", qualitySnapshot.availability)
    }

    private var stats: HostStats? {
        viewModel.hostStats[host.id]
    }

    private var successRateText: String {
        guard let stats else { return "—" }
        return String(format: "%.0f%%", stats.successRate)
    }

    private var serviceCountText: String {
        "\(host.serviceShortcuts.count)"
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
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Theme.Fonts.number(Theme.Fonts.Size.footnote, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 6)
        .background(Theme.Colors.cardBackground.opacity(0.65))
        .cornerRadius(Theme.Radius.md)
    }

    @ViewBuilder
    private var qualityBadge: some View {
        let scoreText = hasEnoughQualityData ? "\(qualitySnapshot.score)" : "—"
        let labelText = hasEnoughQualityData ? gradeLabel : languageManager.t("card.measuring")
        let badgeColor = hasEnoughQualityData ? qualityColor : Theme.Colors.textTertiary

        HStack(spacing: Theme.Space.xs) {
            Text(scoreText)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote, weight: .bold))
                .foregroundStyle(badgeColor)
            Text(labelText)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .medium))
                .foregroundStyle(badgeColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, Theme.Space.xxs)
        .background(badgeColor.opacity(0.14))
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.28), lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .help(languageManager.t("card.score_help"))
    }

    @ViewBuilder
    private func infoPill(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.micro))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(value)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 6)
        .background(Theme.Colors.background.opacity(0.45))
        .cornerRadius(Theme.Radius.md)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "server.rack")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.callout))
                        .foregroundStyle(statusColor)
                }
                
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.xs) {
                        Text(host.name)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                            .foregroundStyle(host.isPaused ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                            .lineLimit(1)
                            
                        if host.isPaused {
                            Image(systemName: "pause.circle.fill")
                                .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    
                    Text(host.address)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()

                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    if let latency = host.lastLatency, viewModel.isRunning {
                        Text("\(Int(latency)) ms")
                            .font(Theme.Fonts.number(Theme.Fonts.Size.headline, weight: .bold))
                            .foregroundStyle(statusColor)
                    } else if !host.isReachable && viewModel.isRunning && !host.isChecking {
                        Text(languageManager.t("card.timeout"))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accentRed)
                    } else if host.isChecking {
                        Text("…")
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    qualityBadge
                }
            }

            HStack(spacing: Theme.Space.sm) {
                compactMetric(
                    title: languageManager.t("stats.availability"),
                    value: availabilityText,
                    color: availabilityColor
                )
                compactMetric(
                    title: languageManager.t("card.p95"),
                    value: qualitySnapshot.p95Latency.map { String(format: "%.0fms", $0) } ?? "—",
                    color: Theme.Colors.accentBlue
                )
                compactMetric(
                    title: languageManager.t("card.loss"),
                    value: hasEnoughQualityData ? String(format: "%.1f%%", qualitySnapshot.packetLoss) : "—",
                    color: qualitySnapshot.packetLoss > 3 ? Theme.Colors.accentRed : Theme.Colors.textPrimary
                )
                compactMetric(
                    title: languageManager.t("host_detail.jitter"),
                    value: hasEnoughQualityData ? String(format: "%.1fms", qualitySnapshot.jitter) : "—",
                    color: Theme.Colors.accentOrange
                )
            }

            HStack(spacing: Theme.Space.sm) {
                infoPill(icon: "point.topleft.down.to.point.bottomright.curvepath", title: languageManager.t("card.path"), value: pathLabel, color: diagnosticColor)
                infoPill(icon: "checkmark.shield", title: languageManager.t("stats.success_rate"), value: successRateText, color: Theme.Colors.accentGreen)
                infoPill(icon: "bolt.horizontal.circle", title: languageManager.t("card.services"), value: serviceCountText, color: Theme.Colors.accentPurple)
            }

            if let stats, stats.latencyHistory.count > 1 {
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
                .background(Theme.Colors.surfaceOverlay)
                .cornerRadius(Theme.Radius.xs)
                .padding(.horizontal, Theme.Space.xxs)
            } else {
                Color.clear.frame(height: 32)
            }
            
            // Footer: Rules & Actions
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: host.probeMode == .tcp ? "cable.connector" : "waveform.path.ecg")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(host.probeDisplayLabel)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    if let diagnosticText {
                        Circle()
                            .fill(Theme.Colors.textTertiary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        Image(systemName: diagnosticIcon)
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            .foregroundStyle(diagnosticColor)
                        Text(diagnosticText)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                            .foregroundStyle(diagnosticColor)
                            .lineLimit(1)
                    }
                }
                
                Spacer()

                if !host.displayRules.isEmpty {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "checklist")
                            .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(String(format: languageManager.t("card.rules"), host.displayRules.count))
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
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
                                .padding(Theme.Space.xs)
                                .contentShape(Rectangle())
                        }
                        .help(host.isPaused ? languageManager.t("header.start") : languageManager.t("header.stop"))
                        
                        Button { onEdit() } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(Theme.Space.xs)
                                .contentShape(Rectangle())
                        }
                        .help(languageManager.t("menu.edit"))
                        
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.Colors.accentRed)
                                .padding(Theme.Space.xs)
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
        .padding(Theme.Layout.cardPadding)
        // 豁免 hoverLift：边框与悬停光晕携带主机状态色（正常/降级/故障），是信息不是装饰。
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
