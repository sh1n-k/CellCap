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

public struct DefaultFileSystemInspector: FileSystemInspecting {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

public protocol HelperInstallChecking: Sendable {
    func currentStatus(now: Date) async -> HelperInstallStatus
    func currentStatus(now: Date, forceRefresh: Bool) async -> HelperInstallStatus
}

public extension HelperInstallChecking {
    // forceRefresh를 모르는 구현(주로 테스트 mock)은 기본 동작으로 위임한다.
    func currentStatus(now: Date, forceRefresh: Bool) async -> HelperInstallStatus {
        await currentStatus(now: now)
    }
}

public actor SystemHelperInstallChecker: HelperInstallChecking {
    private let fileSystem: any FileSystemInspecting
    private let commandExecutor: any CommandExecuting
    private let cacheTTL: TimeInterval
    private var cachedStatus: HelperInstallStatus?
    private var cachedAt: Date?

    public init(
        fileSystem: any FileSystemInspecting = DefaultFileSystemInspector(),
        commandExecutor: any CommandExecuting = ProcessCommandExecutor(),
        cacheTTL: TimeInterval = 3
    ) {
        self.fileSystem = fileSystem
        self.commandExecutor = commandExecutor
        self.cacheTTL = cacheTTL
    }

    public func currentStatus(now: Date) async -> HelperInstallStatus {
        await currentStatus(now: now, forceRefresh: false)
    }

    // launchctl 프로세스 spawn은 비싸고 설치 상태는 런타임 중 거의 불변이므로
    // 짧은 TTL 동안 결과를 캐시한다. 설치/제거 직후 즉시 반영이 필요한 트리거
    // (appLaunch·manualRefresh·policyChanged·resynchronization·sleep/wake)는
    // 호출부에서 forceRefresh=true로 캐시를 우회한다. 시계 역행 시에도 캐시를 무시한다.
    public func currentStatus(now: Date, forceRefresh: Bool) async -> HelperInstallStatus {
        if !forceRefresh,
           let cachedStatus,
           let cachedAt,
           now >= cachedAt,
           now.timeIntervalSince(cachedAt) < cacheTTL {
            var refreshed = cachedStatus
            refreshed.checkedAt = now
            return refreshed
        }

        let status = computeStatus(now: now)
        cachedStatus = status
        cachedAt = now
        return status
    }

    private func computeStatus(now: Date) -> HelperInstallStatus {
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
