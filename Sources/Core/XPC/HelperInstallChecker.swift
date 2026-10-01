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
    private let daemon: any HelperDaemonServicing
    private let cacheTTL: TimeInterval
    private var cachedStatus: HelperInstallStatus?
    private var cachedAt: Date?

    public init(
        fileSystem: any FileSystemInspecting = DefaultFileSystemInspector(),
        commandExecutor: any CommandExecuting = ProcessCommandExecutor(),
        daemon: any HelperDaemonServicing = SMAppServiceHelperDaemon(),
        cacheTTL: TimeInterval = 3
    ) {
        self.fileSystem = fileSystem
        self.commandExecutor = commandExecutor
        self.daemon = daemon
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
        let helperURL = daemon.bundleURL.appendingPathComponent(CellCapHelperXPC.bundledHelperProgramPath)
        let plistURL = daemon.bundleURL.appendingPathComponent(CellCapHelperXPC.bundledLaunchDaemonPlistPath)

        func status(_ state: HelperInstallState, _ reason: String) -> HelperInstallStatus {
            HelperInstallStatus(
                state: state,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: helperURL.path,
                plistPath: plistURL.path,
                helperVersion: nil,
                expectedVersion: CellCapHelperXPC.contractVersion,
                reason: reason,
                checkedAt: now
            )
        }

        // 이전 방식 helper가 같은 label을 쓰고 있으면 앱 내장 helper 등록이 그 기록에 묶여 실행되지 않는다.
        if fileSystem.fileExists(atPath: CellCapHelperXPC.legacyInstalledBinaryPath)
            || fileSystem.fileExists(atPath: CellCapHelperXPC.legacyLaunchDaemonPlistPath) {
            return status(
                .legacyInstalled,
                "이전 방식으로 설치된 helper가 남아 있습니다. 터미널에서 sudo BuildSupport/dev/uninstall_helper.sh(또는 제거 pkg)를 실행한 뒤 새로고침하세요."
            )
        }

        guard daemon.bundleURL.pathExtension == "app",
              fileSystem.isExecutableFile(atPath: helperURL.path),
              fileSystem.fileExists(atPath: plistURL.path) else {
            return status(
                .notInstalled,
                "앱 번들 안에 helper가 없습니다. BuildSupport/dev/build_install_app.sh로 설치한 CellCap.app에서 실행하세요."
            )
        }

        let registration = daemon.registrationStatus()
        if registration == .requiresApproval {
            return status(.requiresApproval, CellCapHelperXPC.backgroundApprovalGuidance)
        }

        do {
            let result = try commandExecutor.run(
                "/bin/launchctl",
                arguments: ["print", "system/\(CellCapHelperXPC.serviceName)"]
            )

            if registration != .enabled {
                // 자체 서명 helper는 바이너리가 바뀌면 launch constraint 위반으로 백그라운드 허용이 꺼진다.
                // 이때 SMAppService는 미등록으로 보고하지만 launchd job은 남아 있으므로 승인 대기로 안내한다.
                if result.exitCode == 0 {
                    return status(.requiresApproval, CellCapHelperXPC.backgroundApprovalGuidance)
                }
                return status(.notInstalled, "helper가 등록되지 않았습니다. 고급 정보에서 helper를 설치하세요.")
            }

            if result.exitCode == 0 {
                return status(.bootstrapped, "launchd에 helper가 등록되어 있습니다.")
            }

            return status(
                .installedButNotBootstrapped,
                "helper가 등록됐지만 launchd에서 찾지 못했습니다. helper를 제거한 뒤 다시 설치하세요. "
                    + trimmedReason(stdout: result.standardOutput, stderr: result.standardError, fallback: "")
            )
        } catch {
            guard registration == .enabled else {
                return status(.notInstalled, "helper가 등록되지 않았습니다. 고급 정보에서 helper를 설치하세요.")
            }
            return status(.installedButNotBootstrapped, "launchctl 조회 실패: \(error.localizedDescription)")
        }
    }
}

private func trimmedReason(stdout: String, stderr: String, fallback: String) -> String {
    let candidate = [stderr, stdout]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

    return candidate ?? fallback
}
