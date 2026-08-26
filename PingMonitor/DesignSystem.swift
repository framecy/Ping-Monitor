import SwiftUI

// MARK: - 页面骨架
// 页面留白节奏的唯一数值出处：工具行与滚动内容的边距、间距全部走 Theme.Space 语义别名。
// 标准滚动页用 ScrollPage；非标准结构（VSplitView、整页单卡）直接引用同一批常量，不得自创数值。

/// 标准滚动页骨架：可选工具行（上）+ 滚动内容（下）。
/// 工具行是任意视图插槽——外观（裸行 / 卡片 / 切换器）由调用方决定，本组件只管定位与留白。
struct ScrollPage<Toolbar: View, Content: View>: View {
    var toolbar: () -> Toolbar
    var content: () -> Content

    init(@ViewBuilder toolbar: @escaping () -> Toolbar,
         @ViewBuilder content: @escaping () -> Content) {
        self.toolbar = toolbar
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar()
                .padding(.horizontal, Theme.Space.pagePadding)
                .padding(.top, Theme.Space.pageTopGap)
                .padding(.bottom, Theme.Space.controlGap)

            ScrollView {
                VStack(spacing: Theme.Space.cardGap) {
                    content()
                }
                .padding(.horizontal, Theme.Space.pagePadding)
                .padding(.bottom, Theme.Space.pagePadding)
            }
        }
        .background(Theme.Colors.background)
    }
}

extension ScrollPage where Toolbar == EmptyView {
    /// 无工具行的页面：内容从 pageTopGap 开始。
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(toolbar: { EmptyView() }, content: content)
    }
}

/// 页面工具行：标题（左）+ 操作区（右）的统一字号与行高节奏。
/// 行的左右留白归 ScrollPage 管，这里只负责行内布局。
struct ToolbarRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.Space.controlGap) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            trailing
        }
        .frame(minHeight: 28)
    }
}

// MARK: - 分段切换器
// 胶囊轨道 + matchedGeometryEffect 滑块。全 App 唯一的自定义分段实现：
// 新页面需要"接口/进程""已保存/预设"这类页级切换时必须用它，禁止再手写。

struct SegmentedSwitcher<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    /// 已解析好的本地化文案（调用方经 languageManager.t 取串）
    let title: (Option) -> String
    /// 可选计数，显示为 "标题 (n)"
    var count: ((Option) -> Int)? = nil
    /// nil = 平铺撑满可用宽度；给定值 = 固定轨道宽（如网速页 200）
    var trackWidth: CGFloat? = nil

    @Namespace private var slider

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    guard selection != option else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = option
                    }
                } label: {
                    Text(switcherLabel(option))
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                        .fontWeight(selection == option ? .medium : .regular)
                        .foregroundStyle(selection == option ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                        .padding(.vertical, Theme.Space.sm)
                        .padding(.horizontal, Theme.Space.lg)
                        .frame(maxWidth: trackWidth == nil ? .infinity : nil)
                        .background(
                            Group {
                                if selection == option {
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .fill(Theme.Colors.accentBlue)
                                        .matchedGeometryEffect(id: "slider", in: slider)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Space.xs)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Radius.md)
        .frame(width: trackWidth)
    }

    private func switcherLabel(_ option: Option) -> String {
        if let count {
            return "\(title(option)) (\(count(option)))"
        }
        return title(option)
    }
}

// MARK: - 筛选 Chip
// 可点筛选块：计数 + 标签，选中时着色描边。服务页分类筛选等场景的标准件。

struct FilterChip: View {
    let label: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Text("\(count)")
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.callout, weight: .bold))
                    .foregroundStyle(isSelected ? color : Theme.Colors.textSecondary)
                Text(label)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(isSelected ? color.opacity(0.12) : Theme.Colors.cardBackground)
            .cornerRadius(Theme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? color.opacity(0.3) : Theme.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 指标瓦片
// "标签在上、数值在下"的小块。卡片内统计区（质量分拆解、流量统计等）的标准件。

struct StatTile: View {
    enum Style {
        case plain    // 无底色，直接排在卡片里
        case tinted   // 彩色浅底小块
    }

    let title: String
    let value: String
    /// tinted 的着色来源；plain 瓦片不参与着色，可省略
    var color: Color = Theme.Colors.textPrimary
    var icon: String? = nil
    var style: Style = .plain

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(Theme.Fonts.icon(Theme.Fonts.Size.display))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.number(Theme.Fonts.Size.headline, weight: .semibold))
                .foregroundStyle(style == .tinted ? color : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .applyStatTileBackground(style: style, color: color)
    }
}

private extension View {
    @ViewBuilder
    func applyStatTileBackground(style: StatTile.Style, color: Color) -> some View {
        switch style {
        case .plain:
            self
        case .tinted:
            self.padding(Theme.Space.md)
                .background(color.opacity(0.08))
                .cornerRadius(Theme.Radius.md)
        }
    }
}

// MARK: - 设置行
// 左标签(+可选说明)、右控件固定宽尾对齐。width:220 与说明文字的对齐只在这里定义一次，
// 禁止在设置页散写 frame(width:) 或负 padding 补偿。

struct SettingsRow<Control: View>: View {
    let label: String
    var description: String? = nil
    var controlWidth: CGFloat = 220
    @ViewBuilder var control: () -> Control

    init(label: String,
         description: String? = nil,
         controlWidth: CGFloat = 220,
         @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.description = description
        self.controlWidth = controlWidth
        self.control = control
    }

    var body: some View {
        HStack(alignment: description == nil ? .center : .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(label)
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let description {
                    Text(description)
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control()
                .frame(width: controlWidth, alignment: .trailing)
        }
    }
}

// MARK: - 悬浮抬升卡
// 主机卡 / 预设卡等可悬浮网格瓦片的统一外壳：实心卡底 + hover 阴影加深、
// 强调色描边、轻微放大。hover 状态由调用方持有（网格需要 hoveredId 驱动操作按钮显隐）。

extension View {
    func hoverLift(isHovered: Bool, accent: Color = Theme.Colors.accentBlue) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                    .fill(Theme.Colors.cardBackground)
                    .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03),
                            radius: isHovered ? 8 : 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                    .stroke(isHovered ? accent.opacity(0.15) : Theme.Colors.textTertiary.opacity(0.08),
                            lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
    }
}

// MARK: - 日志表列宽规格
// 表头与 LogRow 共享的唯一出处（仿 Traceroute 的 HopColumnWidths 模式）。
// message 列 maxWidth:.infinity 弹性伸缩，不入规格。

struct LogColumnWidths {
    static let marker: CGFloat = 18      // 级别状态点
    static let time: CGFloat = 150       // 时间（等宽字体）
    static let level: CGFloat = 52       // 级别
    static let host: CGFloat = 120       // 主机
    static let rowSpacing: CGFloat = Theme.Space.md
}
