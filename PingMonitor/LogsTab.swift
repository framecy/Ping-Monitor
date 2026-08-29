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
            .cardBar()
            
            // 日志列表装入卡片容器；顶部为对齐 LogRow 列宽的表头（固定不随列表滚动）
            VStack(spacing: 0) {
                HStack(spacing: LogColumn.gutter) {
                    Color.clear
                        .frame(width: LogColumn.dot, height: 1)
                    Text(languageManager.t("logs.header.time"))
                        .frame(width: LogColumn.time, alignment: .leading)
                    Text(languageManager.t("logs.header.level"))
                        .frame(width: LogColumn.level, alignment: .leading)
                    Text(languageManager.t("logs.header.host"))
                        .frame(width: LogColumn.host, alignment: .leading)
                    Text(languageManager.t("logs.header.content"))
                    Spacer(minLength: 0)
                }
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, LogColumn.gutter)
                .padding(.vertical, 8)
                .background(Theme.Colors.surfaceOverlay)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredLogs.reversed().enumerated()), id: \.element.id) { index, entry in
                            LogRow(entry: entry, striped: index.isMultiple(of: 2))
                        }
                    }
                }
            }
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, Theme.Layout.cardPadding)
            .padding(.top, 4)
            .padding(.bottom, Theme.Layout.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - 日志表列宽（表头与行共用同一常量，保证逐列对齐）
private enum LogColumn {
    static let dot: CGFloat = 6      // 行首级别圆点
    static let time: CGFloat = 155   // "yyyy-MM-dd HH:mm:ss.SSS" 单行放下
    static let level: CGFloat = 50
    static let host: CGFloat = 140
    static let gutter: CGFloat = 12  // 列间距 + 行内水平边距
}

struct LogRow: View {
    let entry: LogManager.LogEntry
    var striped: Bool = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var levelColor: Color {
        Theme.Status.logLevel(entry.level)
    }

    var body: some View {
        HStack(spacing: LogColumn.gutter) {
            Circle()
                .fill(levelColor)
                .frame(width: LogColumn.dot, height: LogColumn.dot)

            Text(entry.formattedTimestamp)
                .font(Theme.Fonts.number(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .frame(width: LogColumn.time, alignment: .leading)

            Text(languageManager.t("logs.level.\(entry.level.rawValue.lowercased())"))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .bold))
                .foregroundStyle(levelColor)
                .frame(width: LogColumn.level, alignment: .leading)

            Text(entry.host ?? "")
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: LogColumn.host, alignment: .leading)

            Text(entry.message)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, LogColumn.gutter)
        .padding(.vertical, 6)
        .background(striped ? Theme.Colors.surfaceOverlay.opacity(0.45) : Color.clear)
        .help(entry.message)
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
