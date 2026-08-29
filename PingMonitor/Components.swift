import SwiftUI

struct ModernCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Theme.Layout.cardPadding
    var backgroundColor: Color = Theme.Colors.cardBackground
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .cornerRadius(Theme.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
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
        .padding(.bottom, 8)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(Theme.Fonts.ui(Theme.Fonts.Size.caption, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(Theme.Radius.xs)
    }
}

// MARK: - 卡片化工具栏样式

extension View {
    /// 页面顶部工具栏的卡片化样式：与 ModernCard 同一视觉语言（cardBackground +
    /// 12pt 圆角 + 1pt cardBorder 描边），但不改变内容布局，用于替换原先
    /// 通栏铺满的 ultraThinMaterial 工具条。
    ///
    /// - Parameters:
    ///   - topInset: 卡片距页首的间距
    ///   - bottomInset: 卡片与下方内容的间距
    func cardBar(topInset: CGFloat = 12, bottomInset: CGFloat = 8) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, Theme.Layout.cardPadding)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
    }
}

// MARK: - 统一分段切换控件

/// 卡片式分段切换控件：surfaceOverlay 滑轨 + accentBlue 滑动高亮（matchedGeometryEffect），
/// 等宽分段。此前网速页与主机管理页各有一套私有实现（宽度/滑轨/字号互不一致），已统一到此。
struct CardSegmentedControl: View {
    let segments: [String]
    @Binding var selection: Int
    @Namespace private var sliderNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments.indices, id: \.self) { index in
                segmentButton(title: segments[index], index: index)
            }
        }
        .padding(3)
        .background(Theme.Colors.surfaceOverlay)
        .cornerRadius(Theme.Radius.md)
    }

    private func segmentButton(title: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = index
            }
        } label: {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.body))
                .fontWeight(selection == index ? .medium : .regular)
                .foregroundStyle(selection == index ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        if selection == index {
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(Theme.Colors.accentBlue)
                                .matchedGeometryEffect(id: "CardSegmentedSlider", in: sliderNamespace)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
