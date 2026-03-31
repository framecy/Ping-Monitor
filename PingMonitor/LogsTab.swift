import SwiftUI
import UniformTypeIdentifiers

// MARK: - Logs Tab
struct LogsTab: View {
    @StateObject private var logManager = LogManager.shared
    @State private var selectedLevel: LogManager.LogLevel?
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @ObservedObject private var languageManager = LanguageManager.shared

    var filteredLogs: [LogManager.LogEntry] {
        if let level = selectedLevel {
            return logManager.logs.filter { $0.level == level }
        }
        return logManager.logs
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(languageManager.t("logs.level"), selection: $selectedLevel) {
                    Text(languageManager.t("logs.level.all")).tag(nil as LogManager.LogLevel?)
                    ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                        Text(languageManager.t("logs.level.\(level.rawValue.lowercased())")).tag(level as LogManager.LogLevel?)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button(action: {
                    logManager.clear()
                }) {
                    Label(languageManager.t("logs.clear"), systemImage: "trash")
                }
                .buttonStyle(.borderless)

                Button(action: {
                    if let url = logManager.exportToFile() {
                        exportURL = url
                        showingExportSheet = true
                    }
                }) {
                    Label(languageManager.t("logs.export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(.ultraThinMaterial)

            List(filteredLogs.reversed()) { entry in
                LogRow(entry: entry)
                    .listRowSeparator(.visible)
            }
            .listStyle(.plain)
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: LogFileDocument(url: exportURL),
            contentType: .plainText,
            defaultFilename: "PingMonitor_Logs.txt"
        ) { result in
            if case .success = result {
                print("Log exported successfully")
            }
        }
    }
}

struct LogRow: View {
    let entry: LogManager.LogEntry
    @ObservedObject private var languageManager = LanguageManager.shared

    var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)

            HStack(alignment: .top, spacing: 12) {
                Text(entry.formattedTimestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 130, alignment: .leading)

                Text(languageManager.t("logs.level.\(entry.level.rawValue.lowercased())"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(levelColor)
                    .frame(width: 50, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    if let host = entry.host {
                        Text(host)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(entry.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct LogFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var url: URL?

    init(url: URL?) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        self.url = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url,
              let data = try? Data(contentsOf: url) else {
            return FileWrapper(regularFileWithContents: Data())
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
