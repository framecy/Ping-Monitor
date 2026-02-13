import SwiftUI

struct Theme {
    struct Colors {
        static let background = Color(hex: "141414")
        static let cardBackground = Color(hex: "1F1F1F")
        static let sidebarBackground = Color(hex: "1A1A1A")
        
        static let accentBlue = Color(hex: "2D8CFF")
        static let accentGreen = Color(hex: "30D158")
        static let accentPurple = Color(hex: "BF5AF2")
        static let accentOrange = Color(hex: "FF9F0A")
        static let accentRed = Color(hex: "FF453A")
        
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "8E8E93")
        static let textTertiary = Color(hex: "636366")
        
        static let separator = Color(hex: "38383A")
    }
    
    struct Fonts {
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        
        static func body(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .rounded)
        }
        
        static func number(_ size: CGFloat) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }
    }
    
    struct Layout {
        static let cardCornerRadius: CGFloat = 12
        static let cardPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 16
    }
}

extension Color {
    init(hex: String) {
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
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

