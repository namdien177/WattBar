import Foundation

struct AppPowerUse: Identifiable, Sendable, Equatable {
    let name: String
    let cpuPercent: Double
    /// The `.app` bundle the process runs from, used for the app icon.
    let bundlePath: String

    var id: String { name }
}

enum ProcessReader {
    static func topApps(limit: Int = 3) -> [AppPowerUse] {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aww", "-o", "pid=,pcpu=,comm="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return parse(String(decoding: data, as: UTF8.self), limit: limit)
        } catch {
            return []
        }
    }

    static func parse(_ output: String, limit: Int = 3) -> [AppPowerUse] {
        var totals: [String: Double] = [:]
        var bundlePaths: [String: String] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard
                columns.count == 3,
                let cpuPercent = Double(columns[1]),
                cpuPercent > 0,
                let appBundle = bundlePath(from: String(columns[2])),
                appBundle.name != "WattBar"
            else {
                continue
            }
            totals[appBundle.name, default: 0] += cpuPercent
            // Every process of one app resolves to the same outer bundle.
            if bundlePaths[appBundle.name] == nil {
                bundlePaths[appBundle.name] = appBundle.path
            }
        }

        return totals
            .map { AppPowerUse(name: $0.key, cpuPercent: $0.value, bundlePath: bundlePaths[$0.key] ?? "") }
            .sorted {
                if $0.cpuPercent == $1.cpuPercent {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.cpuPercent > $1.cpuPercent
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func bundlePath(from command: String) -> (name: String, path: String)? {
        let components = command.split(separator: "/", omittingEmptySubsequences: false)
        // Only processes inside an .app bundle count as apps.
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        let path = components[...appIndex].joined(separator: "/")
        return (String(components[appIndex].dropLast(4)), path)
    }
}
