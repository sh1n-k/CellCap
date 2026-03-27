import Foundation
import Shared

public struct CommandExecutionResult: Sendable, Equatable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CommandExecuting: Sendable {
    func run(_ launchPath: String, arguments: [String]) throws -> CommandExecutionResult
}

public struct ProcessCommandExecutor: CommandExecuting {
    public init() {}

    public func run(_ launchPath: String, arguments: [String]) throws -> CommandExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandExecutionResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self)
        )
    }
}

public protocol FileSystemInspecting: Sendable {
    func fileExists(atPath path: String) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
}

extension FileManager: FileSystemInspecting {}

public protocol HelperInstallChecking: Sendable {
    func currentStatus(now: Date) async -> HelperInstallStatus
}

public struct SystemHelperInstallChecker: HelperInstallChecking {
    private let fileSystem: any FileSystemInspecting
    private let commandExecutor: any CommandExecuting

    public init(
        fileSystem: any FileSystemInspecting = FileManager.default,
        commandExecutor: any CommandExecuting = ProcessCommandExecutor()
    ) {
        self.fileSystem = fileSystem
        self.commandExecutor = commandExecutor
    }

    public func currentStatus(now: Date) async -> HelperInstallStatus {
        let helperPath = CellCapHelperXPC.installedBinaryPath
        let plistPath = CellCapHelperXPC.launchDaemonPlistPath
        let serviceName = CellCapHelperXPC.serviceName
        let expectedVersion = CellCapHelperXPC.contractVersion

        let helperExists = fileSystem.fileExists(atPath: helperPath)
        let helperExecutable = fileSystem.isExecutableFile(atPath: helperPath)
        let plistExists = fileSystem.fileExists(atPath: plistPath)

        guard helperExists, helperExecutable, plistExists else {
            var missing: [String] = []
            if !helperExists { missing.append("helper binary") }
            if helperExists && !helperExecutable { missing.append("helper binary permissions") }
            if !plistExists { missing.append("launchd plist") }

            return HelperInstallStatus(
                state: .notInstalled,
                serviceName: serviceName,
                helperPath: helperPath,
                plistPath: plistPath,
                helperVersion: nil,
                expectedVersion: expectedVersion,
                reason: "설치 누락: \(missing.joined(separator: ", "))",
                checkedAt: now
            )
        }

        do {
            let result = try commandExecutor.run("/bin/launchctl", arguments: ["print", "system/\(serviceName)"])
            if result.exitCode == 0 {
                return HelperInstallStatus(
                    state: .bootstrapped,
                    serviceName: serviceName,
                    helperPath: helperPath,
                    plistPath: plistPath,
                    helperVersion: nil,
                    expectedVersion: expectedVersion,
                    reason: "launchd에 helper가 등록되어 있습니다.",
                    checkedAt: now
                )
            }

            return HelperInstallStatus(
                state: .installedButNotBootstrapped,
                serviceName: serviceName,
                helperPath: helperPath,
                plistPath: plistPath,
                helperVersion: nil,
                expectedVersion: expectedVersion,
                reason: trimmedReason(stdout: result.standardOutput, stderr: result.standardError, fallback: "helper가 설치되었지만 launchd bootstrap 상태가 아닙니다."),
                checkedAt: now
            )
        } catch {
            return HelperInstallStatus(
                state: .installedButNotBootstrapped,
                serviceName: serviceName,
                helperPath: helperPath,
                plistPath: plistPath,
                helperVersion: nil,
                expectedVersion: expectedVersion,
                reason: "launchctl 조회 실패: \(error.localizedDescription)",
                checkedAt: now
            )
        }
    }
}

private func trimmedReason(stdout: String, stderr: String, fallback: String) -> String {
    let candidate = [stderr, stdout]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

    return candidate ?? fallback
}
