import Core
import Foundation
import Shared
import Testing

private let bundleURL = URL(fileURLWithPath: "/Applications/CellCap.app")
private let bundledArtifacts = [
    bundleURL.appendingPathComponent(CellCapHelperXPC.bundledHelperProgramPath).path,
    bundleURL.appendingPathComponent(CellCapHelperXPC.bundledLaunchDaemonPlistPath).path
]

private func makeChecker(
    files: [String] = bundledArtifacts,
    registration: HelperDaemonRegistrationStatus = .enabled,
    launchctl: CommandExecutionResult = .init(exitCode: 0, standardOutput: "service = {\n}", standardError: ""),
    bundle: URL = bundleURL
) -> SystemHelperInstallChecker {
    SystemHelperInstallChecker(
        fileSystem: MockFileSystem(existingFiles: files),
        commandExecutor: MockCommandExecutor(result: launchctl),
        daemon: MockHelperDaemon(bundleURL: bundle, status: registration)
    )
}

@Test
func helperInstallCheckerReportsLegacyInstallationBeforeRegistrationState() async {
    let checker = makeChecker(files: bundledArtifacts + [CellCapHelperXPC.legacyLaunchDaemonPlistPath])

    let status = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .legacyInstalled)
    #expect(status.reason.contains("uninstall_helper.sh"))
}

@Test
func helperInstallCheckerReturnsNotInstalledOutsideAppBundle() async {
    let checker = makeChecker(files: [], bundle: URL(fileURLWithPath: "/tmp/.build/debug"))

    let status = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .notInstalled)
    #expect(status.reason.contains("build_install_app.sh"))
}

@Test
func helperInstallCheckerMapsRegistrationStatus() async {
    let missingJob = CommandExecutionResult(exitCode: 113, standardOutput: "", standardError: "Could not find service")
    let notRegistered = await makeChecker(registration: .notRegistered, launchctl: missingJob).currentStatus(now: .now)
    let requiresApproval = await makeChecker(registration: .requiresApproval).currentStatus(now: .now)
    // 자체 서명 helper가 바뀌어 백그라운드 허용이 꺼지면 SMAppService는 미등록으로 보고하지만 launchd job은 남는다.
    let disallowedAfterRebuild = await makeChecker(registration: .notRegistered).currentStatus(now: .now)

    #expect(notRegistered.state == .notInstalled)
    #expect(requiresApproval.state == .requiresApproval)
    #expect(requiresApproval.installationSupport == .readOnlyFallback)
    #expect(disallowedAfterRebuild.state == .requiresApproval)
}

@Test
func helperInstallCheckerReturnsInstalledButNotBootstrappedWhenLaunchctlFails() async {
    let checker = makeChecker(
        launchctl: .init(
            exitCode: 113,
            standardOutput: "",
            standardError: "Could not find service \"com.shin.cellcap.helper\" in domain for system"
        )
    )

    let status = await checker.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .installedButNotBootstrapped)
    #expect(status.reason.contains("Could not find service"))
}

@Test
func helperInstallCheckerReturnsBootstrappedWhenRegisteredAndLoaded() async {
    let status = await makeChecker().currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.state == .bootstrapped)
    #expect(status.expectedVersion == CellCapHelperXPC.contractVersion)
    #expect(status.helperPath == "/Applications/CellCap.app/Contents/MacOS/CellCapHelper")
}

@Test
func helperInstallCheckerCachesLaunchctlResultWithinTTL() async {
    let executor = CountingCommandExecutor(
        result: .init(exitCode: 0, standardOutput: "service = {\n}", standardError: "")
    )
    let checker = SystemHelperInstallChecker(
        fileSystem: MockFileSystem(existingFiles: bundledArtifacts),
        commandExecutor: executor,
        daemon: MockHelperDaemon(bundleURL: bundleURL, status: .enabled),
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

private struct MockCommandExecutor: CommandExecuting {
    let result: CommandExecutionResult

    func run(_ launchPath: String, arguments: [String]) throws -> CommandExecutionResult {
        result
    }
}
