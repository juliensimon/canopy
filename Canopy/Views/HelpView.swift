import SwiftUI

/// Inline help showing rationale, keyboard shortcuts, and typical workflows.
struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 12) {
                    Text("🌳")
                        .font(.system(size: 36))
                    VStack(alignment: .leading) {
                        Text("Canopy")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Parallel Claude Code sessions with git worktrees")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Why Canopy
                section("Why Canopy?") {
                    Text("""
                    When working with Claude Code, you often want to run multiple tasks in parallel — a feature branch, a bug fix, and a refactor, all at the same time. But each Claude session needs its own working directory to avoid conflicts.

                    Canopy manages this with **git worktrees**: lightweight checkouts of the same repo at different paths, each with its own branch. Claude Code runs in each worktree independently, and Canopy keeps them organized.
                    """)
                }

                // Typical workflows
                section("Typical Workflows") {
                    workflow(
                        "Start a new feature",
                        steps: [
                            "Add your project (⌘⇧P) — point to a git repo",
                            "Create a worktree session (⌘⇧T) — pick a base branch, name your feature branch",
                            "Canopy creates the worktree, copies .env files, and launches Claude",
                        ]
                    )
                    workflow(
                        "Resume work on an existing branch",
                        steps: [
                            "Click your project in the sidebar to see the project overview",
                            "Find the worktree and click \"Open\"",
                            "Canopy adopts that worktree's existing Claude conversation and resumes it — sessions it created keep the ID they were assigned",
                        ]
                    )
                    workflow(
                        "Run parallel tasks",
                        steps: [
                            "Create multiple worktree sessions from the same project",
                            "Each session gets its own branch and Claude instance",
                            "Switch between them using the tab bar or sidebar",
                            "Activity dots show which sessions are working, and which are blocked waiting on you",
                        ]
                    )
                    workflow(
                        "Clean up when done",
                        steps: [
                            "Go to the project overview and delete worktrees you no longer need",
                            "This removes the worktree directory and its branch",
                            "Canopy warns you about uncommitted or unmerged changes",
                        ]
                    )
                }

                // Tips
                section("Tips") {
                    concept("Command palette (⌘K)",
                            "Search sessions by name, branch, project, or anything that appeared in the terminal. Selecting a match that came from terminal content jumps to the session and highlights the results inline.")
                    concept("Text selection",
                            "Hold ⌥ Option while dragging to select text when Claude Code is running. Claude uses mouse reporting which hijacks normal selection — Option bypasses it.")
                    concept("Show transcript",
                            "Right-click a session → Show Transcript… for a scrollable read-only view of the conversation. When Claude Code is running, Canopy reads the structured JSONL session log and renders user/assistant turns with markdown formatting — much cleaner than the raw terminal output. Falls back to the raw 500 KB capture for plain (non-Claude) sessions. The footer's Copy button (⌘⇧C) puts the formatted markdown on your clipboard.")
                    concept("Why the live terminal doesn't scroll with NO_FLICKER",
                            "CLAUDE_CODE_NO_FLICKER=1 switches Claude Code into the alternate screen buffer (DECSET 1049), which has no scrollback by terminal protocol design. The live viewport intentionally can't scroll back through past conversation in that mode — use Show Transcript to read history, or Cmd+F to search.")
                }

                // Concepts
                section("Key Concepts") {
                    concept("Project",
                            "A git repository you work with. Stores config for worktree setup: which .env files to copy, what to symlink, setup commands to run.")
                    concept("Worktree Session",
                            "A terminal running Claude Code in a git worktree — an isolated checkout with its own branch. Changes in one worktree don't affect others.")
                    concept("Plain Session",
                            "A terminal in any directory, not tied to a project or worktree. Good for one-off tasks.")
                    concept("Activity Dot",
                            "Green pulsing = working. Amber with a raised hand = blocked waiting on you, usually a permission prompt. Blue check = just finished. Gray = idle. The amber state comes from Claude Code itself, so it needs a backend that runs Claude on the host (Off or Claude sandbox); otherwise the dot falls back to output-versus-silence.")
                    concept("Auto-start Claude",
                            "When enabled in Settings, new sessions automatically run `claude` with your configured flags. Per-project overrides available.")
                    concept("Session Resume",
                            "Canopy assigns each session its own Claude conversation ID at launch (--session-id) and resumes that exact one afterwards (--resume), so a tab stays bound to its own conversation. Opening a worktree that already has history adopts the most recent conversation instead.")
                    concept("Per-Session Claude Flags",
                            "The New Worktree Session sheet has a Claude Flags field. Any `claude` flag works — --model, --effort, --permission-mode. It overrides the project and global flags for that session only, so you can run one branch on a different model without touching its siblings. Leave it empty to inherit.")
                    concept("Session Info",
                            "Right-click a session for Session Info: working directory, branch, token counts, and — so you can check rather than assume — which sandbox it resolved to and the exact Claude flags it launched with.")
                    concept("Status Bar Session State",
                            "The status bar names the active session's Claude run: the model that produced its last turn, the reasoning effort, and how much context that turn had to read (for example opus-5 · xhigh · 402.3K). Hover for the exact token count and the full model ID. It is an absolute count rather than a percentage, because a 200k and a 1M context session look the same in the transcript and a percentage would be wrong for one of them. Model and effort follow the last completed turn, so /model and /effort show up on the next turn rather than immediately. After /clear the segment resets on its own.")
                    concept("Transcript Attribution",
                            "Show Transcript labels each Claude turn with the model and reasoning effort that produced it (for example opus-5 · xhigh). Older transcripts and models without an effort setting simply show less. Copy includes it, so a transcript pasted into an issue says which model wrote it.")
                    concept("Sandbox Backends",
                            "Optional isolation for Claude sessions, set globally (Settings), per project, or per session (New Worktree Session sheet). They protect different amounts. Claude sandbox uses Claude Code's own macOS Seatbelt sandbox: nothing to install, resume works, but it confines Bash only, and restricts writes while leaving reads on a deny-list, so credentials stay readable. Docker Sandbox (legacy) runs Claude in an sbx microVM (requires Docker Desktop; no session resume). Apple container runs it in a lightweight VM via Apple's container runtime (macOS 26+, Apple silicon; resume works) and is the strongest — the only one that confines the whole Claude process rather than just its shell commands. Sandboxed sessions show a shield icon in the sidebar — hover it to see which backend. For the VM backends, everything not explicitly mounted (SSH keys, Keychain, other repos, the rest of your home dir) stays out of reach — but not the mounted project and its main repo, or Claude state, and outbound network stays open. See the User Guide for the full boundary. If a backend isn't ready when a session starts — for example the container runtime was stopped — Canopy prints the fix in the terminal instead of a cryptic error.")
                    concept("Sandbox Login (Apple container)",
                            "macOS keeps Claude's credentials in the Keychain, which the Linux VM can't read. Run /login once inside your first sandboxed session — credentials persist in the mounted ~/.claude for all later sessions.")
                    concept("Sandbox Image (Apple container)",
                            "The Apple container backend runs Claude inside an image you build once from Settings → Build Image. Claude Code is baked into the image with its auto-updater disabled, so its version is frozen until you rebuild. To pull a newer Claude Code, click Update (next to Build Image) — it rebuilds from scratch so the latest version is fetched.")
                }

                // Config
                section("Configuration") {
                    Text("""
                    **Settings** are stored at `~/.config/canopy/settings.json`
                    **Projects** are stored at `~/.config/canopy/projects.json`

                    Per-project Claude settings (auto-start, flags) override the global defaults. Edit a project to configure these.

                    Worktrees are created at `../canopy-worktrees/<project>/` by default, as siblings of your repo directory.
                    """)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(width: 560, height: 600)
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    // MARK: - Components

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.system(size: 13))
        }
    }

    private func workflow(_ title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(i + 1).")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    Text(step)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func concept(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}
