import SwiftUI

struct EditableHostCard: View {
    let host: HostConfig
    let viewModel: PingMonitorViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var statusColor: Color {
        guard viewModel.isRunning else { return Theme.Colors.textSecondary }
        if host.isChecking { return Theme.Colors.accentBlue }
        guard host.isReachable else { return Theme.Colors.accentRed }
        if let latency = host.lastLatency {
            if latency < 50 { return Theme.Colors.accentGreen }
            if latency < 100 { return Theme.Colors.accentOrange }
            return Theme.Colors.accentRed
        }
        return Theme.Colors.textSecondary
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
                    Text(host.name)
                        .font(Theme.Fonts.display(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    
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
                 GeometryReader { geometry in
                     let points = stats.latencyHistory.suffix(20).map { $0.latency }
                     if !points.isEmpty {
                         Path { path in
                             let width = geometry.size.width
                             let height = geometry.size.height
                             let minVal = points.min() ?? 0
                             let maxVal = max(points.max() ?? 100, 1)
                             let range = maxVal - minVal + 1 // avoid div by zero
                             
                             let stepX = width / CGFloat(max(points.count - 1, 1))
                             
                             for (index, value) in points.enumerated() {
                                 let x = CGFloat(index) * stepX
                                 let normalizedY = (value - minVal) / range
                                 let y = height - (CGFloat(normalizedY) * height)
                                 
                                 if index == 0 {
                                     path.move(to: CGPoint(x: x, y: y))
                                 } else {
                                     path.addLine(to: CGPoint(x: x, y: y))
                                 }
                             }
                         }
                         .stroke(
                             LinearGradient(
                                 colors: [statusColor.opacity(0.8), statusColor.opacity(0.3)],
                                 startPoint: .leading,
                                 endPoint: .trailing
                             ),
                             style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                         )
                     }
                 }
                 .frame(height: 30)
                 .background(Color.white.opacity(0.02))
                 .cornerRadius(4)
            } else {
                Spacer().frame(height: 30)
            }
            
            // Footer: Rules & Actions
            HStack {
                if !host.displayRules.isEmpty {
                    Image(systemName: "checklist")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(String(format: languageManager.t("card.rules"), host.displayRules.count))
                        .font(Theme.Fonts.body(10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                Spacer()
                
                if isHovered {
                    HStack(spacing: 10) {
                        Button { onEdit() } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .help(languageManager.t("menu.edit"))
                        
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.Colors.accentRed)
                        }
                        .help(languageManager.t("menu.delete"))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .padding(Theme.Layout.cardPadding)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(isHovered ? statusColor.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: isHovered ? statusColor.opacity(0.1) : Color.clear, radius: 8, y: 4)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
