import Foundation
import notify

/// macOS가 배터리 게이지 보정을 위해 충전 한도를 잠시 무시하고 100%까지 충전하는 상태(보정 완충)를 알리는 Darwin notification.
///
/// - 비공개·비문서 키다. macOS 26.7.1(25G241) powerd가 보정 완충을 시작할 때 상태 1, 끝낼 때 0으로 설정하고 post하는 것을
///   디스어셈블과 시스템 로그(`chargeControl charge to full requested:%d`, `posted '...'`)로 확인했다.
/// - `com.apple.system.*` 네임스페이스라 root만 쓸 수 있고 일반 사용자 프로세스는 읽기만 한다. 다른 시스템 프로세스도
///   구독하므로 개발·검증 중에 이 키의 상태를 바꾸거나 post하지 않는다. 테스트는 다른 이름을 주입해 같은 경로를 검증한다.
/// - macOS 업데이트로 키가 바뀌거나 사라지면 상태를 읽지 못하거나 항상 0이 되어 표시만 꺼진다.
public enum SystemFullChargeNotification {
    public static let name = "com.apple.system.powersources.chargingtofulloverride"
}

public protocol SystemFullChargeStateReading: Sendable {
    /// 보정 완충 중이면 true. 상태를 읽지 못하면 nil.
    func isFullChargeRequested() -> Bool?
}

/// `notify_get_state`로 보정 완충 상태를 읽는다. 토큰은 처음 읽을 때 만들고 재사용한다.
public final class NotifySystemFullChargeStateReader: SystemFullChargeStateReading, @unchecked Sendable {
    private let name: String
    private let lock = NSLock()
    private var token: Int32?

    public init(name: String = SystemFullChargeNotification.name) {
        self.name = name
    }

    deinit {
        if let token {
            notify_cancel(token)
        }
    }

    public func isFullChargeRequested() -> Bool? {
        lock.lock()
        defer { lock.unlock() }

        let token: Int32
        if let existing = self.token {
            token = existing
        } else {
            var registered: Int32 = 0
            guard notify_register_check(name, &registered) == UInt32(NOTIFY_STATUS_OK) else {
                return nil
            }
            self.token = registered
            token = registered
        }

        var state: UInt64 = 0
        guard notify_get_state(token, &state) == UInt32(NOTIFY_STATUS_OK) else {
            return nil
        }
        return state != 0
    }
}

/// 보정 완충 상태 변화 알림을 구독한다. 상태 값은 `SystemFullChargeStateReading`으로 다시 읽는다.
public final class SystemFullChargeNotificationObserver: @unchecked Sendable {
    private let name: String
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var token: Int32?

    public init(name: String = SystemFullChargeNotification.name, queue: DispatchQueue = .main) {
        self.name = name
        self.queue = queue
    }

    deinit {
        stop()
    }

    /// 이미 구독 중이면 기존 구독을 정리하고 다시 시작한다. 구독에 실패하면 false.
    @discardableResult
    public func start(_ handler: @escaping @Sendable () -> Void) -> Bool {
        stop()

        var registered: Int32 = 0
        let status = notify_register_dispatch(name, &registered, queue) { _ in
            handler()
        }
        guard status == UInt32(NOTIFY_STATUS_OK) else {
            return false
        }

        lock.lock()
        token = registered
        lock.unlock()
        return true
    }

    public func stop() {
        lock.lock()
        let token = self.token
        self.token = nil
        lock.unlock()

        if let token {
            notify_cancel(token)
        }
    }
}
