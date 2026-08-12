import SwiftUI

struct StatusBadge: View {
    var title: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
    }
}
