/// A navigation change invalidates animation completions from the previous route.
/// The window's main-actor owner supplies scheduling; this type has no UI or timer dependency.
final class OverlayDismissalState {
    struct Ticket: Equatable {
        fileprivate let sequence: UInt64
    }

    private var sequence: UInt64 = 0
    private var pending: Ticket?

    func navigationChanged() {
        sequence &+= 1
        pending = nil
    }

    func beginDismissal() -> Ticket {
        sequence &+= 1
        let ticket = Ticket(sequence: sequence)
        pending = ticket
        return ticket
    }

    @discardableResult
    func completeDismissal(_ ticket: Ticket, then: () -> Void) -> Bool {
        guard pending == ticket else { return false }
        // Consume before calling back: handleBack itself changes the route.
        pending = nil
        then()
        return true
    }
}
