import Foundation

struct AppPowerUse: Identifiable, Sendable, Equatable {
    let name: String
    let cpuPercent: Double

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

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard
                columns.count == 3,
                let cpuPercent = Double(columns[1]),
                cpuPercent > 0,
                let appName = appName(from: String(columns[2])),
                appName != "WattBar"
            else {
                continue
            }
            totals[appName, default: 0] += cpuPercent
        }

        return totals
            .map { AppPowerUse(name: $0.key, cpuPercent: $0.value) }
            .sorted {
                if $0.cpuPercent == $1.cpuPercent {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.cpuPercent > $1.cpuPercent
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func appName(from command: String) -> String? {
        let components = command.split(separator: "/")
        guard let appComponent = components.first(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        return String(appComponent.dropLast(4))
    }
}
