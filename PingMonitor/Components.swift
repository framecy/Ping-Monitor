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
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
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
                .font(Theme.Fonts.display(16))
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
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(4)
    }
}
