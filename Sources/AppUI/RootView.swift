import Core
import Shared
import SwiftUI

struct RootView: View {
    let state: AppState
    let transitionReason: ChargeTransitionReason

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CellCap")
                .font(.largeTitle.weight(.semibold))

            Group {
                Text("현재 상태: \(state.chargeState.rawValue)")
                Text("배터리: \(state.battery?.chargePercent ?? 0)%")
                Text("제어 모드: \(state.controllerStatus.mode.rawValue)")
                Text("상태 결정 사유: \(transitionReason.rawValue)")
            }
            .font(.body.monospaced())

            Text("TODO: 메뉴 막대 UI, 설정 화면, helper 연동은 다음 단계에서 연결합니다.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}
