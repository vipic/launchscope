on run arguments
    if (count of arguments) is not 1 then error "用法：layout_dmg.applescript <挂载路径>"
    set volumeFolder to POSIX file (item 1 of arguments) as alias

    tell application "Finder"
        open volumeFolder
        set volumeWindow to container window of volumeFolder
        tell volumeWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {200, 200, 860, 600}
        end tell

        tell icon view options of volumeWindow
            set arrangement to not arranged
            set icon size to 120
            set text size to 13
            set background picture to file ".background:background.tiff" of volumeFolder
        end tell

        set position of item "LaunchScope.app" of volumeFolder to {139, 194}
        set position of item "Applications" of volumeFolder to {521, 194}
        update volumeFolder without registering applications
        delay 2
        close volumeWindow
        delay 1
    end tell
end run
