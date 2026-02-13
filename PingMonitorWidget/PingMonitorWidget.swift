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
        Entry(
            date: Date(),
            displayMode: .auto,
            title: "PingMonitor",
            entries: [
                WidgetData.HostStatus(name: "Google DNS", latency: 25, status: "green", isRunning: true),
                WidgetData.HostStatus(name: "Cloudflare", latency: 12, status: "green", isRunning: true),
                WidgetData.HostStatus(name: "Gateway", latency: 3, status: "green", isRunning: true)
            ],
            lastUpdated: Date(),
            primaryHost: WidgetData.HostStatus(name: "Google DNS", latency: 25, status: "green", isRunning: true)
        )
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
        // Try to load from shared file
        if let data = WidgetDataManager.shared.load() {
            return Entry(
                date: Date(),
                displayMode: data.displayMode,
                title: data.title,
                entries: data.entries,
                lastUpdated: data.lastUpdated,
                // Backward compatibility helpers
                primaryHost: data.entries.first,
                debugMessage: data.debugMessage
            )
        }
        
        // Fallback or default
        return Entry(
            date: Date(),
            displayMode: .auto,
            title: "PingMonitor",
            entries: [],
            lastUpdated: Date(),
            primaryHost: nil,
            debugMessage: "Load returned nil completely."
        )
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let displayMode: WidgetData.DisplayMode
    let title: String
    let entries: [WidgetData.HostStatus]
    let lastUpdated: Date
    let primaryHost: WidgetData.HostStatus? // Helper for Small view
    var debugMessage: String? = nil
}

struct WidgetView: View {
    var entry: Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let debug = entry.debugMessage {
            VStack {
                Text("⚠️ Debug Info")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                Text(debug)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
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
}

// MARK: - Small Widget
struct SmallView: View {
    let entry: Entry

    var body: some View {
        VStack(spacing: 8) {
            // Header / Title
            if entry.displayMode == .auto {
                 Text(entry.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            if let host = entry.primaryHost {
                // Single Host View
                ZStack {
                    Circle()
                        .fill(statusColor(for: host.status).opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(statusColor(for: host.status))
                }
                
                Text("\(Int(host.latency))ms")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor(for: host.status))
                    .contentTransition(.numericText())
                
                Text(host.name)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            } else {
                // Summary View (Auto mode but no primary host logic hit?)
                // Just verify if entries exist
                if let first = entry.entries.first {
                     // Fallback to first entry display
                     Text(first.name)
                } else {
                    Text("No Hosts (v2.0.51)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("v2.0.51")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
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
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text(entry.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            // List of top 3
            VStack(spacing: 8) {
                ForEach(entry.entries.prefix(3)) { host in
                    HStack {
                        Circle()
                            .fill(statusColor(for: host.status))
                            .frame(width: 6, height: 6)
                        
                        Text(host.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if host.isRunning {
                            Text("\(Int(host.latency))ms")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(statusColor(for: host.status))
                        } else {
                             Text("Stopped")
                                 .font(.system(size: 10))
                                 .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                if entry.entries.isEmpty {
                   Text("No hosts available")
                       .font(.caption)
                       .foregroundStyle(.secondary)
                       .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(10)
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
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
        VStack(spacing: 12) {
             // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
                Text(entry.title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(entry.lastUpdated, style: .time)
                     .font(.system(size: 10))
                     .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 4)
            
            // List of top 6
            VStack(spacing: 6) {
                ForEach(entry.entries.prefix(6)) { host in
                    HStack {
                        // Status Indicator
                        Capsule()
                            .fill(statusColor(for: host.status))
                            .frame(width: 3, height: 12)
                        
                        Text(host.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if host.isRunning {
                            HStack(spacing: 4) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Text("\(Int(host.latency))ms")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(statusColor(for: host.status))
                            }
                        } else {
                             Text("STOPPED")
                                 .font(.system(size: 9, weight: .bold))
                                 .foregroundStyle(.secondary)
                                 .padding(.horizontal, 4)
                                 .padding(.vertical, 2)
                                 .background(Color.secondary.opacity(0.1))
                                 .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.05)) // Dynamic background
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                 if entry.entries.isEmpty {
                   Text("No hosts monitored")
                       .font(.title3)
                       .foregroundStyle(.secondary)
                       .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
             Spacer()
        }
        .padding(12)
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}
