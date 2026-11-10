/// Serializes method and direct-JW sheets through their complete UIKit lifecycle.
struct ImportPresentationState {
    enum Flow: Equatable { case methods, jw }
    private(set) var active: Flow?

    mutating func begin(_ flow: Flow) -> Bool {
        guard active == nil else { return false }
        active = flow
        return true
    }

    @discardableResult
    mutating func didDismiss(_ flow: Flow) -> Bool {
        guard active == flow else { return false }
        active = nil
        return true
    }
}
