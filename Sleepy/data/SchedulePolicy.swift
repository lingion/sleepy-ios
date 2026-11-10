/// A shared schedule edit changes only this table, creates a new owner, or syncs its owner.
/// Kept in the data layer because repositories are compiled by the app and widget targets.
enum SchedulePolicy: Equatable {
    case none
    case detachCopy
    case createNew
    case sync
}
