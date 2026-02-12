import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // App Branding
            HStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.Colors.accentBlue, Theme.Colors.accentPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("PingMonitor")
                    .font(Theme.Fonts.display(18))
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            
            ScrollView {
                VStack(spacing: 4) {
                    SidebarSectionHeader(title: languageManager.t("sidebar.overview"))
                    SidebarRow(item: .monitor, selectedItem: $selectedItem, icon: SidebarItem.monitor.icon, title: SidebarItem.monitor.title)
                    SidebarRow(item: .statistics, selectedItem: $selectedItem, icon: SidebarItem.statistics.icon, title: SidebarItem.statistics.title)
                    
                    Spacer().frame(height: 16)
                    
                    SidebarSectionHeader(title: languageManager.t("sidebar.management"))
                    SidebarRow(item: .hosts, selectedItem: $selectedItem, icon: SidebarItem.hosts.icon, title: SidebarItem.hosts.title)
                    SidebarRow(item: .logs, selectedItem: $selectedItem, icon: SidebarItem.logs.icon, title: SidebarItem.logs.title)
                    
                    Spacer().frame(height: 16)
                    
                    SidebarSectionHeader(title: languageManager.t("sidebar.config"))
                     // Placeholder link
                     SidebarRow(item: .settings, selectedItem: $selectedItem, icon: SidebarItem.settings.icon, title: SidebarItem.settings.title)

                }
                .padding(.horizontal, 10)
            }
            
            // Bottom Area (User/Version)
            VStack(spacing: 12) {
                 Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                
                HStack {
                    Circle()
                         .fill(Theme.Colors.cardBackground)
                         .frame(width: 32, height: 32)
                         .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.Colors.textSecondary))
                    
                    VStack(alignment: .leading) {
                         let userName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
                         Text(userName)
                            .font(Theme.Fonts.body(12))
                            .foregroundStyle(Theme.Colors.textPrimary)
                         if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                             Text("v\(version)")
                                 .font(Theme.Fonts.body(10))
                                 .foregroundStyle(Theme.Colors.textSecondary)
                         }
                    }
                    Spacer()
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .onTapGesture {
                            selectedItem = .settings
                        }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    @Binding var selectedItem: SidebarItem
    let icon: String
    let title: String
    
    var isSelected: Bool {
        selectedItem == item
    }
    
    var body: some View {
        Button(action: { selectedItem = item }) {
            HStack(spacing: 10) {
                // Colored Bar Indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? item.activeColor : Color.clear)
                    .frame(width: 4, height: 16)
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? item.activeColor : Theme.Colors.textSecondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                isSelected ? Theme.Colors.cardBackground : Color.clear
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.body(10))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
