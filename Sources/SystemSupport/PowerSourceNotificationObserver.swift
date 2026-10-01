import CoreFoundation
import Foundation
import IOKit.ps

/// IOKit 전원 상태 변화 알림(`IOPSNotificationCreateRunLoopSource`)을 main run loop에서 받는다.
/// 앱의 `BatteryMonitor`와 helper가 같은 구독 코드를 공유한다.
public final class PowerSourceNotificationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var runLoopSource: CFRunLoopSource?
    private var retainedBox: Unmanaged<HandlerBox>?

    public init() {}

    deinit {
        stop()
    }

    /// 이미 구독 중이면 기존 구독을 정리하고 다시 시작한다. 구독에 실패하면 false.
    @discardableResult
    public func start(_ handler: @escaping @Sendable () -> Void) -> Bool {
        stop()

        let box = Unmanaged.passRetained(HandlerBox(handler: handler))
        guard let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                Unmanaged<HandlerBox>.fromOpaque(context).takeUnretainedValue().handler()
            },
            box.toOpaque()
        )?.takeRetainedValue() else {
            box.release()
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        lock.lock()
        runLoopSource = source
        retainedBox = box
        lock.unlock()
        return true
    }

    public func stop() {
        lock.lock()
        let source = runLoopSource
        let box = retainedBox
        runLoopSource = nil
        retainedBox = nil
        lock.unlock()

        if let source {
            // invalidate는 스레드 안전하며 이후 콜백 전달을 막는다.
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        box?.release()
    }
}

private final class HandlerBox {
    let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}
