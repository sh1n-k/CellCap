import Core
import Foundation
import Shared
import Testing

@Test
func helperInstallCheckerReturnsNotInstalledWhenArtifactsAreMissing() async {
    let checker = SystemHelperInstallChecker(
        fileSystem: MockFileSystem(existingFiles: []),
        commandExecutor: MockCommandExecutor(result: .init(exitCode: 113, standardOutput: "", standardError: "missing"))
    )

    let status = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .notInstalled)
    #expect(status.reason.contains("설치 누락"))
}

@Test
func helperInstallCheckerReturnsInstalledButNotBootstrappedWhenLaunchctlFails() async {
    let checker = SystemHelperInstallChecker(
        fileSystem: MockFileSystem(existingFiles: [
            CellCapHelperXPC.installedBinaryPath,
            CellCapHelperXPC.launchDaemonPlistPath
        ]),
        commandExecutor: MockCommandExecutor(
            result: .init(
                exitCode: 3,
                standardOutput: "",
                standardError: "Could not find service \"com.shin.cellcap.helper\" in domain for system"
            )
        )
    )

    let status = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .installedButNotBootstrapped)
    #expect(status.reason.contains("Could not find service"))
}

@Test
func helperInstallCheckerReturnsBootstrappedWhenLaunchctlSucceeds() async {
    let checker = SystemHelperInstallChecker(
        fileSystem: MockFileSystem(existingFiles: [
            CellCapHelperXPC.installedBinaryPath,
            CellCapHelperXPC.launchDaemonPlistPath
        ]),
        commandExecutor: MockCommandExecutor(
            result: .init(exitCode: 0, standardOutput: "service = {\n}", standardError: "")
        )
    )

    let status = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .bootstrapped)
    #expect(status.expectedVersion == CellCapHelperXPC.contractVersion)
}

@Test
func helperInstallCheckerCachesLaunchctlResultWithinTTL() async {
    let executor = CountingCommandExecutor(
        result: .init(exitCode: 0, standardOutput: "service = {\n}", standardError: "")
    )
    let checker = SystemHelperInstallChecker(
        fileSystem: MockFileSystem(existingFiles: [
            CellCapHelperXPC.installedBinaryPath,
            CellCapHelperXPC.launchDaemonPlistPath
        ]),
        commandExecutor: executor,
        cacheTTL: 100
    )

    let first = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))
    let cached = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_001))
    let forced = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_002), forceRefresh: true)
    let expired = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_500))

    // TTL 내 두 번째 호출은 캐시를 쓰므로 launchctl을 재실행하지 않는다.
    // forceRefresh와 TTL 만료는 캐시를 우회한다.
    #expect(executor.invocationCount() == 3)
    #expect(first.state == .bootstrapped)
    #expect(cached.state == .bootstrapped)
    // 캐시된 결과라도 checkedAt은 호출 시각으로 갱신된다.
    #expect(cached.checkedAt == Date(timeIntervalSince1970: 1_001))
    #expect(forced.state == .bootstrapped)
    #expect(expired.state == .bootstrapped)
}

private final class CountingCommandExecutor: CommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private let result: CommandExecutionResult
    private var count = 0

    init(result: CommandExecutionResult) {
        self.result = result
    }

    func run(_ launchPath: String, arguments: [String]) throws -> CommandExecutionResult {
        lock.lock()
        count += 1
        lock.unlock()
        return result
    }

    func invocationCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private struct MockFileSystem: FileSystemInspecting {
    let existingFiles: Set<String>

    init(existingFiles: [String]) {
        self.existingFiles = Set(existingFiles)
    }

    func fileExists(atPath path: String) -> Bool {
        existingFiles.contains(path)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        existingFiles.contains(path)
    }
}

private struct MockCommandExecutor: CommandExecuting {
    let result: CommandExecutionResult

    func run(_ launchPath: String, arguments: [String]) throws -> CommandExecutionResult {
        result
    }
}
