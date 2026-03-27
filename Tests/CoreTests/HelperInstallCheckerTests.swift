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
