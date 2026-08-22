import Foundation
@testable import Canopy

/// An `AppState` whose persistence is confined to a throwaway directory.
///
/// A default-constructed `AppState` writes to the developer's real
/// `~/.config/canopy` (the `configDir` parameter defaults to it), so any test
/// that constructs one and then writes corrupts the developer's own config.
/// `ConfigIsolationGuardTests` enforces that tests use this instead.
///
/// Shared rather than copied per suite: this encodes the isolation policy, not
/// a one-line convenience, and five copies of it would drift the first time
/// the policy changed. The write is not always obvious at the call site --
/// `renameSession`, `updateProject`, `assignClaudeSessionId` and
/// `openWorktreeSession` all persist without saying so -- which is the reason
/// the guard bans the bare initialiser outright rather than trying to spot
/// the writes.
///
/// ponytail: the directories are left in place under one parent rather than
/// cleaned per test. NSTemporaryDirectory is periodically cleared, and
/// threading a `defer` through every call site would mean restructuring tests
/// that are not otherwise changing.
@MainActor
func isolatedAppState() -> AppState {
    AppState(configDir: NSTemporaryDirectory()
        + "canopy-isolated-tests/\(UUID().uuidString)")
}
