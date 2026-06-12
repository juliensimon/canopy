import Testing
import Foundation
@testable import Canopy

@Suite("ClaudeSessionFinder")
struct ClaudeSessionFinderTests {

    // MARK: - Helpers

    /// Creates a fake Claude projects directory structure for testing.
    private func withFakeClaudeDir(
        directory: String,
        files: [(name: String, age: TimeInterval)],
        body: () throws -> Void
    ) throws {
        let fm = FileManager.default
        let projectDir = ClaudeSessionFinder.projectDirectory(for: directory)

        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: projectDir) }

        let now = Date()
        for file in files {
            let path = (projectDir as NSString).appendingPathComponent(file.name)
            fm.createFile(atPath: path, contents: Data("test".utf8))
            let modDate = now.addingTimeInterval(-file.age)
            try fm.setAttributes([.modificationDate: modDate], ofItemAtPath: path)
        }

        try body()
    }

    // MARK: - Encoding contract with Claude Code

    @Test func encodesEveryNonAlphanumericLikeClaudeCode() {
        // Claude Code 2.x encodes cwd with replace(/[^a-zA-Z0-9]/g, "-").
        // Only handling "/" and "." (the old behavior) made Canopy look in a
        // directory Claude never writes for paths containing _, spaces, etc.
        // -- silently breaking resume, transcripts, and cost tracking.
        let dir = ClaudeSessionFinder.projectDirectory(for: "/Users/x/my_proj.v2 (beta)")
        #expect(dir.hasSuffix("/.claude/projects/-Users-x-my-proj-v2--beta-"))
    }

    @Test func resolvesTmpLikeClaudeCwd() throws {
        // Claude's process.cwd() yields /private/tmp/... for /tmp paths;
        // the encoding must match or the lookup misses.
        let dir = "/tmp/canopy-enc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let projectDir = ClaudeSessionFinder.projectDirectory(for: dir)
        #expect(projectDir.contains("/.claude/projects/-private-tmp-canopy-enc-"))
    }

    // MARK: - Tests

    @Test func returnsNilForNonexistentDirectory() {
        let result = ClaudeSessionFinder.findLatestSessionId(for: "/nonexistent/path/\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test func findsLatestSession() throws {
        let testDir = "/tmp/canopy-finder-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: testDir) }

        let oldId = UUID().uuidString
        let newId = UUID().uuidString

        try withFakeClaudeDir(directory: testDir, files: [
            (name: "\(oldId).jsonl", age: 3600), // 1 hour old
            (name: "\(newId).jsonl", age: 0),     // just now
        ]) {
            let result = ClaudeSessionFinder.findLatestSessionId(for: testDir)
            #expect(result == newId)
        }
    }

    @Test func ignoresNonJsonlFiles() throws {
        let testDir = "/tmp/canopy-finder-nonjsonl-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: testDir) }

        let validId = UUID().uuidString

        try withFakeClaudeDir(directory: testDir, files: [
            (name: "not-a-session.txt", age: 0),
            (name: "\(validId).jsonl", age: 60),
        ]) {
            let result = ClaudeSessionFinder.findLatestSessionId(for: testDir)
            #expect(result == validId)
        }
    }

    @Test func returnsNilForNonUuidFilenames() throws {
        let testDir = "/tmp/canopy-finder-nonuuid-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: testDir) }

        try withFakeClaudeDir(directory: testDir, files: [
            (name: "not-a-uuid.jsonl", age: 0),
        ]) {
            let result = ClaudeSessionFinder.findLatestSessionId(for: testDir)
            #expect(result == nil)
        }
    }

    @Test func returnsNilForEmptyDirectory() throws {
        let testDir = "/tmp/canopy-finder-empty-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: testDir) }

        try withFakeClaudeDir(directory: testDir, files: []) {
            let result = ClaudeSessionFinder.findLatestSessionId(for: testDir)
            #expect(result == nil)
        }
    }
}
