// SPDX-License-Identifier: AGPL-3.0-only
import GameController

extension MouseSession {
    // UI permission only. start() remains responsible for pending releases, connection and actual lock.
    var canArmEdgeHandoff: Bool {
        canStart && !isRelaying && !typing.isSending && pointerIsLocked?() != true
    }
    var pointerButtonsReleased: Bool {
        guard let input = (GCMouse.current ?? GCMouse.mice().first)?.mouseInput else { return false }
        return !input.leftButton.isPressed && input.rightButton?.isPressed != true &&
            input.middleButton?.isPressed != true && input.auxiliaryButtons?.contains(where: { $0.isPressed }) != true
    }
}
