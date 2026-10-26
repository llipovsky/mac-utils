import AppKit

struct JigglePattern: Identifiable {
    let id: String
    let name: String
    let summary: String
    let steps: [JiggleStep]
    /// Set when a user script failed to parse.
    let error: String?
}

/// Built-in patterns plus user scripts in ~/Library/Application Support/MacUtils/Scripts.
final class ScriptLibrary {
    static let shared = ScriptLibrary()
    static let fileExtension = "jiggle"

    let folder = AppInfo.supportDirectory.appendingPathComponent("Scripts", isDirectory: true)

    static let builtins: [JigglePattern] = [
        builtin("zen", "Zen (no movement)", "Only resets the idle timer; the cursor never moves.", ""),
        builtin("subtle", "Subtle", "Nudges the cursor one pixel and back.", """
            move 1 0 over 0.05
            move -1 0 over 0.05
            """),
        builtin("nudge", "Nudge", "A small diagonal hop and back.", """
            move 12 8 over 0.2
            back over 0.2
            """),
        builtin("circle", "Circle", "Draws a small circle.", """
            circle 40 over 1.2
            """),
        builtin("square", "Square", "Traces a small square.", """
            move 60 0 over 0.4
            move 0 60 over 0.4
            move -60 0 over 0.4
            move 0 -60 over 0.4
            """),
        builtin("zigzag", "Zigzag", "Zigzags right, then returns.", """
            repeat 3
              move 30 15 over 0.2
              move 30 -15 over 0.2
            end
            back over 0.5
            """),
        builtin("wander", "Wander", "Drifts around like a person reading, then returns.", """
            repeat 4
              random 150 over 0.6
              wait 0.2-0.8
            end
            back over 0.6
            """),
    ]

    private static func builtin(_ id: String, _ name: String, _ summary: String, _ source: String) -> JigglePattern {
        do {
            return JigglePattern(id: id, name: name, summary: summary, steps: try JiggleScriptParser.parse(source), error: nil)
        } catch {
            preconditionFailure("Built-in pattern \(id) is invalid: \(error.localizedDescription)")
        }
    }

    func userPatterns() -> [JigglePattern] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == Self.fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(load)
    }

    func allPatterns() -> [JigglePattern] {
        Self.builtins + userPatterns()
    }

    func pattern(id: String) -> JigglePattern? {
        if let builtin = Self.builtins.first(where: { $0.id == id }) { return builtin }
        guard id.hasPrefix("file:") else { return nil }
        let url = folder.appendingPathComponent(String(id.dropFirst(5)))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return load(url)
    }

    private func load(_ url: URL) -> JigglePattern {
        let id = "file:" + url.lastPathComponent
        let name = url.deletingPathExtension().lastPathComponent
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            return JigglePattern(id: id, name: name, summary: url.path, steps: try JiggleScriptParser.parse(source), error: nil)
        } catch {
            return JigglePattern(id: id, name: name, summary: url.path, steps: [], error: error.localizedDescription)
        }
    }

    func revealFolder() {
        installExampleIfNeeded()
        NSWorkspace.shared.open(folder)
    }

    func installExampleIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let example = folder.appendingPathComponent("Example.\(Self.fileExtension)")
        let reference = folder.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: example.path) {
            try? Self.exampleScript.write(to: example, atomically: true, encoding: .utf8)
        }
        try? Self.reference.write(to: reference, atomically: true, encoding: .utf8)
    }

    static let exampleScript = """
        # Example MacUtils jiggle script. Edit it, or copy it to a new .jiggle file.
        # It appears under Pattern › Your Scripts in the menu. See README.txt for every command.

        move 40 0 over 0.3      # right 40 points
        wait 0.5
        circle 20 over 0.8
        repeat 2
          random 60 over 0.4
          wait 0.2-0.6
        end
        back over 0.4           # return to where the cursor started

        """

    static let reference = """
        MacUtils jiggle scripts
        =======================

        Put files ending in .jiggle in this folder. Each one becomes a pattern under
        Pattern › Your Scripts in the menu bar menu. The whole script runs once every
        jiggle interval, starting from wherever the cursor is.

        One command per line. Anything after # is a comment. Units are screen points;
        y grows downwards.

          move DX DY [over SECONDS]     move relative to the current position
          moveto X Y [over SECONDS]     move to a spot on the current screen, X/Y in
                                        points from its top-left corner or as 0–100%
                                        (e.g. `moveto 50% 50%` is the centre)
          circle RADIUS [over SECONDS]  a full circle that starts and ends here
          random RADIUS [over SECONDS]  a random spot within RADIUS of the start
          back [over SECONDS]           return to where the run started
          wait SECONDS                  pause, e.g. `wait 1.5`
          wait MIN-MAX                  pause a random time, e.g. `wait 0.5-2`
          scroll LINES                  scroll (negative = up); needs Accessibility
          repeat COUNT ... end          repeat the lines in between

        Movements default to `over 0.25` seconds. A run stops early if you touch the
        mouse, and is capped at 2 minutes.

        """
}
