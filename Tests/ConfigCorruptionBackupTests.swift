import Testing
import Foundation
@testable import Canopy

/// A corrupt config file must be PRESERVED (backed up) before it is discarded,
/// never silently dropped.
///
/// Without this, a single malformed entry makes the whole `projects.json` /
/// `prompts.json` decode to nothing, and the next save overwrites the file with
/// `[]` — permanently losing every project's repository path and worktree
/// config, or the entire prompt library. `loadSessions` already backs up before
/// decoding; `loadProjects` backed up only *after* a successful decode (so a
/// corrupt file was never captured) and `loadPrompts` did not back up at all.
@Suite("Config Corruption Backup")
@MainActor
struct ConfigCorruptionBackupTests {

    private func makeConfigDir() -> String {
        let dir = NSTemporaryDirectory() + "canopy-corrupt-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func corruptProjectsFileIsBackedUpNotLost() throws {
        let dir = makeConfigDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let projectsPath = (dir as NSString).appendingPathComponent("projects.json")
        let corrupt = "not valid json {{{"
        try corrupt.write(toFile: projectsPath, atomically: true, encoding: .utf8)

        let state = AppState(configDir: dir)
        state.loadProjects()

        // Decode failed → no projects loaded …
        #expect(state.projects.isEmpty)
        // … but the corrupt file was preserved for recovery, not abandoned.
        let backupPath = (dir as NSString).appendingPathComponent("projects.backup.json")
        let backup = try #require(
            FileManager.default.contents(atPath: backupPath),
            "corrupt projects.json was not backed up before being discarded"
        )
        #expect(String(data: backup, encoding: .utf8) == corrupt)
    }

    @Test func corruptPromptsFileIsBackedUpNotLost() throws {
        let dir = makeConfigDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let promptsPath = (dir as NSString).appendingPathComponent("prompts.json")
        let corrupt = "}}} not json"
        try corrupt.write(toFile: promptsPath, atomically: true, encoding: .utf8)

        let state = AppState(configDir: dir)
        state.loadPrompts()

        #expect(state.prompts.isEmpty)
        let backupPath = (dir as NSString).appendingPathComponent("prompts.backup.json")
        let backup = try #require(
            FileManager.default.contents(atPath: backupPath),
            "corrupt prompts.json was not backed up before being discarded"
        )
        #expect(String(data: backup, encoding: .utf8) == corrupt)
    }

    @Test func validProjectsStillLoadAfterBackupChange() throws {
        // Backing up before decode must not break the happy path.
        let dir = makeConfigDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let project = Project(name: "demo", repositoryPath: "/tmp/demo")
        let data = try JSONEncoder().encode([project])
        try data.write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent("projects.json")))

        let state = AppState(configDir: dir)
        state.loadProjects()
        #expect(state.projects.count == 1)
        #expect(state.projects.first?.name == "demo")
    }

    /// A config dir whose parent is a *file* can never be created, so the atomic
    /// write fails. The save path must log and return — not crash via `try!` —
    /// so the data-loss-prevention work never introduces a crash on a failed
    /// save, and the in-memory state survives.
    private func unwritableConfigDir() throws -> (dir: String, cleanup: () -> Void) {
        let blocker = NSTemporaryDirectory() + "canopy-blocker-\(UUID().uuidString)"
        try "x".write(toFile: blocker, atomically: true, encoding: .utf8)
        return ("\(blocker)/cfg", { try? FileManager.default.removeItem(atPath: blocker) })
    }

    @Test func savePromptsSurvivesWriteFailure() throws {
        let (dir, cleanup) = try unwritableConfigDir()
        defer { cleanup() }
        let state = AppState(configDir: dir)
        state.prompts = [SavedPrompt(title: "t", body: "b")]
        state.savePrompts() // must not crash
        #expect(state.prompts.count == 1)
        #expect(!FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("prompts.json")))
    }

    @Test func saveProjectsSurvivesWriteFailure() throws {
        let (dir, cleanup) = try unwritableConfigDir()
        defer { cleanup() }
        let state = AppState(configDir: dir)
        state.addProject(Project(name: "demo", repositoryPath: "/tmp/demo-\(UUID().uuidString)")) // triggers saveProjects
        #expect(state.projects.count == 1) // in-memory append survives a failed save
        #expect(!FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("projects.json")))
    }
}
