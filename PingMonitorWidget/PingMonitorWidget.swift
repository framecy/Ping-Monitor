import WidgetKit
import SwiftUI

@main
struct PingMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        PingMonitorWidget()
    }
}

struct PingMonitorWidget: Widget {
    let kind: String = "PingMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(.windowBackgroundColor).opacity(0.95),
                            Color(.windowBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Ping Monitor")
        .description("显示网络延迟状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), latency: 25, host: "8.8.8.8", isRunning: true, displayText: "25ms", color: "green")
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> Entry {
        let defaults = UserDefaults(suiteName: "group.com.pingmonitor.shared") ?? UserDefaults.standard
        let isRunning = defaults.bool(forKey: "isRunning")
        let latency = defaults.double(forKey: "lastLatency")
        let host = defaults.string(forKey: "targetHost") ?? "8.8.8.8"
        let color = defaults.string(forKey: "color") ?? "gray"
        let displayText = defaults.string(forKey: "displayText") ?? (isRunning ? "请求中..." : "未运行")

        return Entry(
            date: Date(),
            latency: latency > 0 ? latency : nil,
            host: host,
            isRunning: isRunning,
            displayText: displayText,
            color: color
        )
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let latency: Double?
    let host: String
    let isRunning: Bool
    let displayText: String
    let color: String
}

struct WidgetView: View {
    var entry: Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(entry: entry)
        case .systemMedium:
            MediumView(entry: entry)
        case .systemLarge:
            LargeView(entry: entry)
        default:
            SmallView(entry: entry)
        }
    }
}

// MARK: - Small Widget
struct SmallView: View {
    let entry: Entry

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        .linearGradient(
                            colors: [statusColor.opacity(0.25), statusColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: entry.isRunning ? "network.badge.shield.half.filled" : "network")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            Text(entry.displayText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
            
            Text(entry.host)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch entry.color {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Medium Widget
struct MediumView: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 20) {
            // Left: status display
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            .linearGradient(
                                colors: [statusColor.opacity(0.2), statusColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                Text(entry.displayText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
            }
            
            // Divider with gradient
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    .linearGradient(
                        colors: [statusColor.opacity(0.3), .gray.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .padding(.vertical, 8)

            // Right: details
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.host)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isRunning ? .green : .gray)
                        .frame(width: 6, height: 6)
                    Text(entry.isRunning ? "运行中" : "已停止")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                if let latency = entry.latency {
                    Text("延迟: \(Int(latency))ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var statusColor: Color {
        switch entry.color {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Large Widget
struct LargeView: View {
    let entry: Entry

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Ping Monitor")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                Text(entry.host)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Divider
            Rectangle()
                .fill(
                    .linearGradient(
                        colors: [.blue.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Main display
            HStack(spacing: 24) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                .linearGradient(
                                    colors: [statusColor.opacity(0.2), statusColor.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(statusColor)
                    }
                    
                    Text(entry.displayText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.isRunning ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(entry.isRunning ? "运行中" : "已停止")
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    if let latency = entry.latency {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("\(Int(latency))ms")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(entry.date, style: .time)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(4)
    }

    private var statusColor: Color {
        switch entry.color {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}
