import AppKit
import SwiftUI

struct AppIconView: View {
    var item: StartupItem
    var size: CGFloat = UIConstants.itemIconSize

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: item.source.systemImage)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
                    .background(LaunchScopePalette.secondaryFill)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .accessibilityHidden(true)
    }

    private var icon: NSImage? {
        let candidates = [item.attribution?.iconPath, item.attribution?.bundlePath]
            .compactMap { $0 }
        for path in candidates
        where PathAccessPolicy.canProbeMetadata(at: path) && FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let executable = item.executablePath,
           PathAccessPolicy.canProbeMetadata(at: executable),
           let appURL = AttributionResolver.enclosingAppURL(path: executable) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }
}
