// Sets a custom Finder icon on a file — used to give the .dmg the app's icon
// instead of the generic disk image. Takes an .icns and a target path.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, let icon = NSImage(contentsOfFile: arguments[0]) else {
    FileHandle.standardError.write(Data("usage: set-file-icon <icon.icns> <target>\n".utf8))
    exit(1)
}
let ok = NSWorkspace.shared.setIcon(icon, forFile: arguments[1], options: [])
print(ok ? "icon set on \(arguments[1])" : "could not set icon on \(arguments[1])")
exit(ok ? 0 : 1)
