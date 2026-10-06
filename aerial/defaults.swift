// Prints Aerial's default contents for one of its settings files, encoded by Aerial's own types.
// install.sh compiles this against the Aerial source for the installed version, because Aerial
// decodes these files strictly: a file missing any older key is discarded for the defaults, and
// the defaults turn automatic downloads back on.
import Foundation

@main
struct Defaults {
    static func main() throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        switch CommandLine.arguments.dropFirst().first {
        case "screensaver.json": FileHandle.standardOutput.write(try e.encode(ScreensaverSettings.default))
        case "companion.json": FileHandle.standardOutput.write(try e.encode(CompanionSettings.default))
        case "overlay-config.json": FileHandle.standardOutput.write(try e.encode(OverlayConfig.default))
        default:
            FileHandle.standardError.write("usage: defaults screensaver.json|companion.json|overlay-config.json\n".data(using: .utf8)!)
            exit(2)
        }
    }
}
