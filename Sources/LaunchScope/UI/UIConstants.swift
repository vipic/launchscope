import SwiftUI

enum LaunchScopePalette {
    static let accent = Color.indigo
    static let healthy = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let secondaryFill = Color.secondary.opacity(0.09)
    static let selectedFill = Color.accentColor.opacity(0.13)
}

enum UIConstants {
    static let sidebarWidth: CGFloat = 218
    static let listMinimumWidth: CGFloat = 390
    static let detailMinimumWidth: CGFloat = 360
    static let itemIconSize: CGFloat = 34
    static let largeIconSize: CGFloat = 54
    static let cornerRadius: CGFloat = 9
    static let compactSpacing: CGFloat = 6
    static let regularSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 18
}
