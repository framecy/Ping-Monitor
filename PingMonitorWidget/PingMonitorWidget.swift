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

// MARK: - Components
struct StatItem: View {
    let label: String
    let value: String
    var color: Color = .secondary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LatencyBadge: View {
    let latency: Double
    let status: String
    let isRunning: Bool
    var size: CGFloat = 12
    
    var body: some View {
        HStack(spacing: 3) {
            if isRunning {
                Text("\(Int(latency))")
                    .font(.system(size: size, weight: .bold, design: .monospaced))
                Text("ms")
                    .font(.system(size: size * 0.7, weight: .medium))
                    .baselineOffset(1)
            } else {
                Text("OFF")
                    .font(.system(size: size * 0.8, weight: .bold))
            }
        }
        .foregroundStyle(statusColor(for: status))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(for: status).opacity(0.1))
        .clipShape(Capsule())
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

// MARK: - Small Widget
struct SmallView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let host = entry.primaryHost {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                    Text(host.name)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Circle()
                        .fill(statusColor(for: host.status))
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor(for: host.status).opacity(0.5), radius: 2)
                }
                .padding(.bottom, 8)
                
                // Main Latency
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(host.latency))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor(for: host.status))
                    Text("ms")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                .padding(.bottom, 8)
                
                // Stats Grid
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        StatItem(label: "Min", value: formatMs(host.minLatency))
                        StatItem(label: "Max", value: formatMs(host.maxLatency))
                    }
                    GridRow {
                        StatItem(label: "Avg", value: formatMs(host.avgLatency))
                        StatItem(label: "Loss", value: formatLoss(host.packetLoss), color: (host.packetLoss ?? 0) > 0 ? .red : .secondary)
                    }
                }
            } else {
                VStack {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("No Data")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    private func formatMs(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return "\(Int(v))ms"
    }
    
    private func formatLoss(_ value: Double?) -> String {
        guard let v = value else { return "0%" }
        return "\(Int(v))%"
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
        HStack(spacing: 0) {
            // Left Panel: Primary Host Details
            VStack(alignment: .leading, spacing: 0) {
                if let host = entry.primaryHost {
                    HStack {
                        Label(host.name, systemImage: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                        Spacer()
                        LatencyBadge(latency: host.latency, status: host.status, isRunning: host.isRunning, size: 14)
                    }
                    .padding(.bottom, 12)
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            StatItem(label: "Minimum", value: formatMs(host.minLatency))
                            StatItem(label: "Maximum", value: formatMs(host.maxLatency))
                        }
                        HStack(spacing: 16) {
                            StatItem(label: "Average", value: formatMs(host.avgLatency))
                            StatItem(label: "Loss Rate", value: formatLoss(host.packetLoss), color: (host.packetLoss ?? 0) > 0 ? .red : .secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Simple Trend indicator (last updated)
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text("Updated \(entry.lastUpdated, style: .time)")
                            .font(.system(size: 8))
                        Spacer()
                        Text("v2.1.0")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.tertiary)
                } else {
                    Text("Select a host")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Right Panel: Top Hosts List
            VStack(alignment: .leading, spacing: 8) {
                Text("MONITORING")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                
                ForEach(entry.entries.prefix(4).dropFirst()) { host in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.name)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Text(statusText(for: host.status))
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(statusColor(for: host.status))
                        }
                        Spacer()
                        Text("\(Int(host.latency))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor(for: host.status))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(statusColor(for: host.status).opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                if entry.entries.count <= 1 {
                    Spacer()
                    Text("No other hosts")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    Spacer()
                }
            }
            .padding(12)
            .frame(width: 140)
        }
    }
    
    private func formatMs(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return "\(Int(v)) ms"
    }
    
    private func formatLoss(_ value: Double?) -> String {
        guard let v = value else { return "0%" }
        return "\(String(format: "%.1f", v))%"
    }
    
    private func statusText(for status: String) -> String {
        switch status {
        case "green": return "STABLE"
        case "yellow": return "JITTER"
        case "red": return "OFFLINE"
        case "orange": return "HIGH"
        default: return "UNKNOWN"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - Large Widget
struct LargeView: View {
    let entry: Entry

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.blue)
                    Text("\(entry.entries.count) Hosts Active")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            
            // Grid of Hosts
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(entry.entries.prefix(8)) { host in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(host.name)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                            Spacer()
                            Circle()
                                .fill(statusColor(for: host.status))
                                .frame(width: 5, height: 5)
                        }
                        
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(Int(host.latency))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("ms")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(statusColor(for: host.status))
                        
                        HStack {
                            Text("LOSS \(formatLoss(host.packetLoss))")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(host.packetLoss ?? 0 > 0 ? Color.red : Color.secondary)
                            Spacer()
                            Text("AVG \(Int(host.avgLatency ?? 0))")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Footer
            HStack {
                Text(entry.lastUpdated, style: .date)
                Text(entry.lastUpdated, style: .time)
                Spacer()
                Text("v2.1.0")
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(12)
        }
    }

    private func formatLoss(_ value: Double?) -> String {
        guard let v = value else { return "0%" }
        return "\(Int(v))%"
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
