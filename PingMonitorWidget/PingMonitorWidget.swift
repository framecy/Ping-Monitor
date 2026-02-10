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
                .containerBackground(.fill.tertiary, for: .widget)
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

struct SmallView: View {
    let entry: Entry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(statusColor)

            Text(entry.displayText)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
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

struct MediumView: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 32))
                    .foregroundStyle(statusColor)

                Text(entry.displayText)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.host)
                    .font(.headline)
                Text(entry.isRunning ? "运行中" : "已停止")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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

struct LargeView: View {
    let entry: Entry

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                Text("Ping Monitor")
                    .font(.headline)
                Spacer()
                Text(entry.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundStyle(statusColor)
                    Text(entry.displayText)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(entry.isRunning ? "运行中" : "已停止", systemImage: "checkmark.circle")
                    if let latency = entry.latency {
                        Label("\(Int(latency))ms", systemImage: "clock")
                    }
                }
            }
        }
        .padding()
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
