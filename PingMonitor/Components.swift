import SwiftUI

// MARK: - 卡片底座
// 统一卡片容器 = 内容留白 + 白底 + lg 圆角 + 1pt cardBorder 描边。
// 新代码优先用 .card() modifier；ModernCard 保留为源兼容的薄封装。

struct CardModifier: ViewModifier {
    var padding: CGFloat
    var background: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .cornerRadius(Theme.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// 统一卡片容器。padding 默认页面级留白，background 默认卡面白。
    func card(padding: CGFloat = Theme.Space.pagePadding,
              background: Color = Theme.Colors.cardBackground) -> some View {
        modifier(CardModifier(padding: padding, background: background))
    }
}

struct ModernCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Theme.Layout.cardPadding
    var backgroundColor: Color = Theme.Colors.cardBackground

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.card(padding: padding, background: backgroundColor)
    }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.accentBlue)
            }
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            if let action = action {
                Button(action: action) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Theme.Space.sm)
    }
}

struct Badge: View {
    enum Style {
        case tinted   // 彩色浅底小方块
        case pill     // 胶囊 + 细描边（质量分、连接类型等）
    }

    let text: String
    let color: Color
    var icon: String? = nil
    var style: Style = .tinted

    var body: some View {
        Group {
            switch style {
            case .tinted:
                label
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(color.opacity(0.2))
                    .cornerRadius(Theme.Radius.xs)
            case .pill:
                label
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(color.opacity(0.12))
                    .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 0.5))
                    .clipShape(Capsule())
            }
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Space.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(iconFont)
            }
            Text(text)
                .font(textFont)
        }
        .foregroundStyle(color)
    }

    /// tinted 沿用历史视觉（caption 加粗）；pill 用于密集小徽标（micro）。
    private var textFont: Font {
        switch style {
        case .tinted: return Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .bold)
        case .pill: return Theme.Fonts.ui(Theme.Fonts.Size.micro, weight: .medium)
        }
    }

    private var iconFont: Font {
        switch style {
        case .tinted: return Theme.Fonts.icon(Theme.Fonts.Size.caption, weight: .semibold)
        case .pill: return Theme.Fonts.icon(Theme.Fonts.Size.micro, weight: .medium)
        }
    }
}
