import SwiftUI

struct Theme {
    struct Colors {
        static var background: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor(hex: "141414")
                } else {
                    return NSColor(hex: "F5F5F7")
                }
            })
        }
        
        static var cardBackground: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor(hex: "1F1F1F")
                } else {
                    return NSColor.white
                }
            })
        }
        
        static var sidebarBackground: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor(hex: "1A1A1A")
                } else {
                    return NSColor(hex: "EBEBEB")
                }
            })
        }
        
        static let accentBlue = Color(hex: "4b5cc4")
        static let accentGreen = Color(hex: "34C759")
        static let accentPurple = Color(hex: "AF52DE")
        static let accentOrange = Color(hex: "FF9500")
        static let accentRed = Color(hex: "FF3B30")
        static let accentCyan = Color(hex: "32ADE6")
        static let accentTeal = Color(hex: "30B0C7")
        static let accentIndigo = Color(hex: "5856D6")
        static let accentMint = Color(hex: "00C7BE")
        static let accentPink = Color(hex: "FF2D55")

        /// 填充色之上的前景色（按钮文字、徽标图标）。
        static let onAccent = Color.white

        /// 卡片/悬浮容器的统一描边。
        static var cardBorder: Color {
            overlayTint(dark: 0.05, light: 0.06)
        }

        /// 斑马纹、hover、次级表面的统一浅色叠加。
        static var surfaceOverlay: Color {
            overlayTint(dark: 0.04, light: 0.03)
        }

        /// 行 hover 高亮，必须比 surfaceOverlay 更明显。
        static var hoverOverlay: Color {
            overlayTint(dark: 0.09, light: 0.07)
        }

        /// 图表网格线。
        static var chartGrid: Color {
            overlayTint(dark: 0.06, light: 0.08)
        }

        /// 命令/SSH 预览的终端风黑底（恒为黑，明暗模式同值）。
        static let codeBackground = Color.black.opacity(0.3)

        /// 结果胶囊（如 Tailscale ping 结果）的黑底。
        static let chipOverlay = Color.black.opacity(0.1)

        /// 明暗两套外观下的中性叠加色，避免各处硬编码 white/black + opacity。
        private static func overlayTint(dark: CGFloat, light: CGFloat) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.name == .darkAqua || appearance.name == .vibrantDark {
                    return NSColor.white.withAlphaComponent(dark)
                } else {
                    return NSColor.black.withAlphaComponent(light)
                }
            })
        }

        static var textPrimary: Color {
            Color(nsColor: .labelColor)
        }
        
        static var textSecondary: Color {
            Color(nsColor: .secondaryLabelColor)
        }
        
        static var textTertiary: Color {
            Color(nsColor: .tertiaryLabelColor)
        }
        
        static var separator: Color {
            Color(nsColor: .separatorColor)
        }
    }
    
    struct Fonts {
        /// 字号阶梯，按 macOS 常规控件尺度收敛。所有文本必须从这里取值，禁止再写字面量。
        struct Size {
            static let micro: CGFloat = 9      // 徽标、密集表格角标
            static let caption: CGFloat = 10   // 次要说明、表头
            static let footnote: CGFloat = 11  // 辅助信息（≈ macOS small system font）
            static let body: CGFloat = 12      // 正文、列表行
            static let callout: CGFloat = 13   // 强调正文、按钮（≈ macOS system font）
            static let headline: CGFloat = 15  // 卡片标题
            static let title: CGFloat = 17     // 页面标题
            static let display: CGFloat = 22   // 关键指标数字
            static let hero: CGFloat = 28      // 空态图标、超大数字
            static let giant: CGFloat = 40
        }

        /// SF Pro Text 是否可按名取用；取不到就回落系统字体
        /// （系统字体在 20pt 以下本就是 SF Pro Text 的光学尺寸）。
        private static let sfProTextName: String? =
            NSFont(name: "SF Pro Text", size: 12) != nil ? "SF Pro Text" : nil

        /// 中文用 PingFang SC，英文用 SF Pro Text，随语言切换实时生效。
        @MainActor
        private static var uiFamily: String? {
            LanguageManager.shared.currentLanguage == .zh ? "PingFang SC" : sfProTextName
        }

        /// PingFang SC 没有 Bold/Heavy/Black 字重，落到 Semibold，避免系统合成出脏笔画。
        private static func normalized(_ weight: Font.Weight, family: String) -> Font.Weight {
            guard family == "PingFang SC" else { return weight }
            switch weight {
            case .bold, .heavy, .black: return .semibold
            default: return weight
            }
        }

        /// 常规 UI 文本。
        @MainActor
        static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            guard let family = uiFamily else {
                return .system(size: size, weight: weight)
            }
            return .custom(family, fixedSize: size).weight(normalized(weight, family: family))
        }

        /// 数字 / IP / 延迟等需要对齐的等宽场景，中英一致用 SF Mono。
        static func number(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// SF Symbols 必须走系统字体：套自定义字体会破坏符号的基线与度量。
        static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }
    
    /// 全局圆角标度。所有视图必须引用这里的档位，禁止再写字面量。
    struct Radius {
        static let xs: CGFloat = 4      // badge / 细指示条
        static let sm: CGFloat = 6      // 小控件、输入框
        static let md: CGFloat = 8      // 按钮、列表行、次级容器
        static let lg: CGFloat = 12     // 卡片
        static let xl: CGFloat = 16     // 大面板 / 弹层
        static let pill: CGFloat = 999  // 胶囊
    }

    struct Layout {
        static let cardCornerRadius: CGFloat = Radius.lg
        static let cardPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 16
        // 自适应布局断点：detail 区宽度低于阈值时并排两列降为单列堆叠。
        static let twoColumnMinWidth: CGFloat = 280
        static let hostGridMinWidth: CGFloat = 260
        static let narrowTableBreakpoint: CGFloat = 540
        // 侧边栏：默认宽度 + 拖拽区间 + 分隔条宽度，窗口最小宽度由它们推导。
        static let sidebarDefaultWidth: CGFloat = 220
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 360
        static let sidebarResizerWidth: CGFloat = 8
        // detail 区可用的最小宽度，低于此值内容开始出现挤压。
        static let detailMinWidth: CGFloat = 672
        // 表格单元格留白（斑马纹行高由它决定）。
        static let tableCellHorizontalPadding: CGFloat = 10
        static let tableCellVerticalPadding: CGFloat = 8
    }
}

// MARK: - 容器宽度测量
// 响应式栅格统一用它拿可用宽度：GeometryReader 放进 .background，
// 只读宽度不参与主轴布局，避免影响内容高度。
struct ContainerWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 800
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

extension View {
    func measureContainerWidth(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContainerWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ContainerWidthKey.self) { onChange($0) }
    }

    /// 两列栅格的成员：等分宽度并撑满行高，保证同行卡片等高。
    func gridCell() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Theme.Layout {
    /// 容器宽度能否容纳两列（两个最小列宽 + 一个间距）。
    static func fitsTwoColumns(_ width: CGFloat) -> Bool {
        width >= twoColumnMinWidth * 2 + gridSpacing
    }
}

// MARK: - 自适应表格
// 列宽交给 Grid 按内容自适应，禁止按容器宽度的百分比算死像素值 ——
// 测量值拿不到真实宽度时，百分比会在宽卡片里画出一张窄表并留下大片空白。
extension View {
    /// 表格单元格内边距。行底色画在单元格上，所以留白必须由单元格自己带，
    /// Grid 的 horizontalSpacing 要保持 0，否则斑马纹会被间距切断。
    func tableCellPadding() -> some View {
        padding(.horizontal, Theme.Layout.tableCellHorizontalPadding)
            .padding(.vertical, Theme.Layout.tableCellVerticalPadding)
    }
}

// MARK: - Semantic status colors
// 语义状态色的唯一来源：各视图不得再各自实现 latencyColor / scoreColor / levelColor。
extension Theme {
    struct Status {
        /// 不同场景的延迟量级不同（主机 RTT / 逐跳 / overlay），阈值分档，配色统一。
        struct LatencyThresholds {
            let good: Double
            let warning: Double

            static let host = LatencyThresholds(good: 80, warning: 180)
            static let hop = LatencyThresholds(good: 50, warning: 100)
            static let overlay = LatencyThresholds(good: 50, warning: 150)
        }

        static func latency(_ ms: Double?, _ thresholds: LatencyThresholds = .host) -> Color {
            guard let ms else { return Theme.Colors.textTertiary }
            if ms < thresholds.good { return Theme.Colors.accentGreen }
            if ms < thresholds.warning { return Theme.Colors.accentOrange }
            return Theme.Colors.accentRed
        }

        /// 0–100 质量分的统一配色（与 gradeLabel 的分档保持一致）。
        static func score(_ score: Int) -> Color {
            switch score {
            case 90...: return Theme.Colors.accentGreen
            case 75..<90: return Theme.Colors.accentBlue
            case 40..<75: return Theme.Colors.accentOrange
            default: return Theme.Colors.accentRed
            }
        }

        /// 百分比类指标（可用率 / 成功率）：>= good 绿，>= warning 橙，其余红。
        static func ratio(_ value: Double, good: Double, warning: Double) -> Color {
            if value >= good { return Theme.Colors.accentGreen }
            if value >= warning { return Theme.Colors.accentOrange }
            return Theme.Colors.accentRed
        }

        static func path(_ kind: ProbePathKind?) -> Color {
            switch kind {
            case .direct: return Theme.Colors.accentGreen
            case .relay: return Theme.Colors.accentOrange
            case .unknown, nil: return Theme.Colors.textTertiary
            }
        }

        static func severity(_ severity: QualityEventSeverity) -> Color {
            switch severity {
            case .info: return Theme.Colors.accentBlue
            case .warning: return Theme.Colors.accentOrange
            case .critical: return Theme.Colors.accentRed
            }
        }

        static func logLevel(_ level: LogManager.LogLevel) -> Color {
            switch level {
            case .debug: return Theme.Colors.textSecondary
            case .info: return Theme.Colors.accentBlue
            case .warning: return Theme.Colors.accentOrange
            case .error: return Theme.Colors.accentRed
            }
        }

        static func service(_ type: ServiceShortcut.ServiceType) -> Color {
            switch type {
            case .web: return Theme.Colors.accentBlue
            case .ssh: return Theme.Colors.accentGreen
            case .custom: return Theme.Colors.accentOrange
            }
        }
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

