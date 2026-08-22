import Foundation

/// One live `claude` process, as reported by `claude agents --json`.
///
/// Only the fields Canopy actually uses are decoded -- the real payload also
/// carries `kind` and `name` -- because decoding fields we don't read only
/// adds ways for a schema change to break the whole array.
///
/// `pid` was long excluded on the grounds that a container session's pid is a
/// guest-namespace pid and names nothing on the host. That remains true, and
/// remains irrelevant here: nothing in Canopy resolves this pid to a process.
/// It is compared only against a pid the *same registry entry* reported
/// earlier, and a guest pid is perfectly stable for the process that owns it.
/// Paired with `startedAt`, which is namespace-independent, it works as an
/// opaque equality token in a container exactly as it does on the host -- and
/// that is what lets a tab tell its own claude re-keying itself under `/clear`
/// from a different claude appearing in the same directory.
///
/// `status` and `startedAt` are optional because they really are absent in
/// practice: sdk-cli entries carry no `status` key at all.
struct ClaudeAgent: Decodable, Equatable, Sendable {
    let cwd: String
    let sessionId: String
    let status: String?
    let startedAt: Double?
    /// The pid as the registry reports it: a host pid for host backends, a
    /// guest-namespace pid for a container. Absent on older CLIs.
    ///
    /// Deliberately not described as a host pid. It is never resolved to a
    /// process -- only compared against an earlier reading from the same entry
    /// -- so which namespace it belongs to does not matter.
    let pid: Int?

    /// Identifies the *process*, so a session id that changes underneath one
    /// can be told apart from a different claude appearing in the same
    /// directory. Nil when the CLI reports too little to prove either.
    ///
    /// pids are recycled, so the start time is part of the identity: a
    /// matching pid with a different start time is a new process wearing a
    /// dead one's number.
    var processIdentity: ClaudeProcessIdentity? {
        guard let pid, let startedAt else { return nil }
        return ClaudeProcessIdentity(pid: pid, startedAt: startedAt)
    }
}

/// A specific claude process, as reported by the agent registry.
struct ClaudeProcessIdentity: Equatable, Sendable {
    let pid: Int
    let startedAt: Double
}

/// Asks Claude Code which conversations are live, rather than inferring it.
///
/// Shaped like `ClaudeVersionChecker` / `SandboxChecker`: a `nonisolated` enum
/// of pure functions plus one impure `fetch()`. No protocol, no injected
/// provider -- the seam for tests is the pure functions.
enum ClaudeAgentsService {

    /// Which live agent, if any, belongs to a given worktree.
    enum Match: Equatable {
        case none
        case one(ClaudeAgent)
        /// Two or more agents under the same directory. Canopy cannot know
        /// which is this tab's, and guessing would bind the tab to the wrong
        /// transcript, so callers must fall back rather than pick.
        case ambiguous
    }

    /// Status values the CLI can report, from its own union
    /// (`["busy","shell","idle","waiting"]`).
    private enum Status {
        static let busy = "busy"
        /// A Bash tool call is running. Still working, not idle.
        static let shell = "shell"
        /// Blocked on a dialog -- which includes permission prompts. This is
        /// the signal the PTY cannot provide: a waiting prompt emits no bytes,
        /// so the silence heuristic reads it as "finished".
        static let waiting = "waiting"
        static let idle = "idle"
    }

    /// Decodes to nil rather than throwing, so one undecodable element
    /// cannot fail the whole array.
    private struct FailableAgent: Decodable {
        let agent: ClaudeAgent?
        init(from decoder: Decoder) throws {
            agent = try? ClaudeAgent(from: decoder)
        }
    }

    /// Decodes the CLI's output. Returns nil for anything that is not a
    /// top-level array, so an old CLI printing usage text or a shell error is
    /// **detected** rather than read as "zero sessions running" -- the latter
    /// would push every tab to a wrong state at once.
    static func parse(_ data: Data) -> [ClaudeAgent]? {
        // Per element, not all-or-nothing: ONE entry of a shape Canopy does
        // not care about -- a future kind without `cwd`, say -- would
        // otherwise return nil for the entire poll, and consecutive nils
        // permanently disable reconciliation.
        //
        // A non-array still fails outright, because "old or missing CLI" must
        // stay distinguishable from "no claude running".
        guard let wrapped = try? JSONDecoder().decode([FailableAgent].self, from: data) else {
            return nil
        }
        return wrapped.compactMap(\.agent)
    }

    /// Resolves both sides before comparing: /tmp is a symlink to /private/tmp
    /// on macOS and claude reports its resolved cwd. Matches "at or under" the
    /// worktree, mirroring the CLI's own `--cwd` semantics -- but never
    /// upward, since a claude in the parent directory is a different session.
    /// - Parameter preferring: the process this tab took its session id from,
    ///   when it has one. Two claudes under a directory normally make the tab
    ///   give up, because picking the wrong one binds it to a stranger's
    ///   transcript -- but a tab that knows its own process is not guessing,
    ///   and giving up costs it a `/clear` it would otherwise follow along
    ///   with its live status. Only an exact match counts: if our process is
    ///   not in the set, the result is still ambiguous.
    static func agent(
        forWorktree worktree: String,
        in agents: [ClaudeAgent],
        preferring preferred: ClaudeProcessIdentity? = nil
    ) -> Match {
        let target = SandboxBackend.realResolvedPath(worktree)
        guard !target.isEmpty else { return .none }

        let matches = agents.filter { agent in
            let resolved = SandboxBackend.realResolvedPath(agent.cwd)
            return resolved == target || resolved.hasPrefix(target + "/")
        }
        switch matches.count {
        case 0: return .none
        case 1: return .one(matches[0])
        default:
            // Exactly one of them being ours resolves it. Two would mean the
            // registry reported one process twice, which is not something to
            // guess through.
            guard let preferred else { return .ambiguous }
            let ours = matches.filter { $0.processIdentity == preferred }
            return ours.count == 1 ? .one(ours[0]) : .ambiguous
        }
    }

    /// Maps a reported status to an activity, or nil for "no opinion".
    ///
    /// Unknown and absent both map to nil deliberately. Treating them as
    /// `.idle` would fire a false "finished" notification for every sdk-cli
    /// entry and for every status value the CLI adds in future; nil leaves the
    /// existing PTY heuristic in charge, which is the current behaviour and
    /// therefore always a safe fallback.
    static func activity(for status: String?) -> SessionActivity? {
        switch status {
        case Status.busy, Status.shell: return .working
        case Status.waiting: return .needsInput
        case Status.idle: return .idle
        default: return nil
        }
    }

    /// Cached absolute path to `claude`, resolved through a login shell.
    /// `nonisolated(unsafe)` matches the shared-formatter precedent in
    /// ClaudeSessionFinder: written once from the poll loop, read from it.
    private nonisolated(unsafe) static var cachedClaudePath: String?
    /// Cache the FAILURE too. Without this, a claude exposed only as a shell
    /// function or alias (which `isExecutableFile` rightly rejects) makes every
    /// poll spawn two login shells instead of one -- re-sourcing the user's rc
    /// files ~3600x/hour, the precise cost this resolution exists to avoid.
    private nonisolated(unsafe) static var didAttemptClaudePathResolution = false

    private static func resolvedClaudePath() async -> String? {
        // Re-check the cached path is still executable. claude auto-updates
        // and can be moved or removed while Canopy runs; a stale path would
        // fail every poll, and consecutive failures disable reconciliation for
        // the rest of the session. A stale entry re-opens the resolution.
        if let cached = cachedClaudePath {
            if FileManager.default.isExecutableFile(atPath: cached) { return cached }
            cachedClaudePath = nil
            didAttemptClaudePathResolution = false
        }
        // Nothing cached and we already tried: don't spawn a login shell every
        // poll only to fail the same way.
        if didAttemptClaudePathResolution { return nil }
        didAttemptClaudePathResolution = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: SandboxChecker.loginShell())
        process.arguments = ["-ilc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        // Same watchdog as fetch(): a hung rc file must not wedge the poll
        // loop, and this process is spawned before fetch()'s own watchdog.
        let watchdog = DispatchWorkItem { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { return nil }

        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        cachedClaudePath = path
        return path
    }

    /// Runs `claude agents --json` and decodes it. Returns nil on any failure,
    /// which callers treat as "no data this cycle", not as "no sessions".
    ///
    /// ONE invocation per poll cycle for ALL sessions -- deliberately no
    /// `--cwd`. At ~0.3 s per call, filtering per worktree would cost
    /// 0.3 × N for data a single call already contains.
    static func fetch() async -> [ClaudeAgent]? {
        let process = Process()
        // Resolve claude through a login shell ONCE, then invoke it directly.
        // The GUI PATH is not the shell PATH (claude is usually only on PATH
        // via .zshrc), but re-sourcing the rc files on a 2-second loop costs
        // ~0.1 s of the 0.33 s per call and re-runs the user's shell startup
        // 1800 times an hour for a path that does not change.
        if let path = await resolvedClaudePath() {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["agents", "--json"]
        } else {
            process.executableURL = URL(fileURLWithPath: SandboxChecker.loginShell())
            process.arguments = ["-ilc", "claude agents --json"]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            NSLog("Canopy: could not run `claude agents --json` (%@)", "\(error)")
            return nil
        }

        // A hung rc file would otherwise wedge the poll loop forever.
        let watchdog = DispatchWorkItem { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)

        // Read to EOF BEFORE waiting: a full pipe buffer with the parent
        // blocked in waitUntilExit is the classic deadlock, and this repo has
        // a regression test for exactly that shape in GitService.
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}
