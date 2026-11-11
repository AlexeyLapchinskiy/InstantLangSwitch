struct FnTap {
    private enum State {
        case idle
        case pressed
        case chord
    }

    private var state = State.idle

    mutating func fnChanged(isDown: Bool, hasOtherModifiers: Bool) -> Bool {
        if isDown {
            if state == .idle {
                state = hasOtherModifiers ? .chord : .pressed
            }
            return false
        }

        let shouldSwitch = state == .pressed && !hasOtherModifiers
        reset()
        return shouldSwitch
    }

    mutating func otherKeyPressed() {
        if state == .pressed {
            state = .chord
        }
    }

    mutating func reset() {
        state = .idle
    }
}
