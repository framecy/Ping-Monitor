import SwiftUI
import UniformTypeIdentifiers

// 从 MainView.swift 拆出：日志页 + 日志行 + 导出文档类型

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
                LogManager.shared.info("Log exported successfully")
            }
        }
    }
}

struct LogRow: View {
    let entry: LogManager.LogEntry
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var levelColor: Color {
        Theme.Status.logLevel(entry.level)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
            
            HStack(alignment: .top, spacing: 12) {
                Text(entry.formattedTimestamp)
                    .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                    .foregroundStyle(.tertiary)
                    .frame(width: 130, alignment: .leading)
                
                Text(languageManager.t("logs.level.\(entry.level.rawValue.lowercased())"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .bold))
                    .foregroundStyle(levelColor)
                    .frame(width: 50, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 3) {
                    if let host = entry.host {
                        Text(host)
                            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Text(entry.message)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .foregroundStyle(Theme.Colors.textPrimary)
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
