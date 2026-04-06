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
                            "Claude resumes with --resume to continue the previous conversation",
                        ]
                    )
                    workflow(
                        "Run parallel tasks",
                        steps: [
                            "Create multiple worktree sessions from the same project",
                            "Each session gets its own branch and Claude instance",
                            "Switch between them using the tab bar or sidebar",
                            "Activity dots show which sessions are active",
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

                // Keyboard shortcuts
                section("Keyboard Shortcuts") {
                    shortcutGroup([
                        ("⌘T", "New plain session (with directory picker)"),
                        ("⌘⇧T", "New worktree session"),
                        ("⌘⇧P", "Add a project"),
                        ("⌘,", "Settings"),
                        ("⌘W", "Close window"),
                    ])
                }

                // Tips
                section("Tips") {
                    concept("Text selection",
                            "Hold ⌥ Option while dragging to select text when Claude Code is running. Claude uses mouse reporting which hijacks normal selection — Option bypasses it.")
                    concept("Copy session output",
                            "Right-click a session → Copy Session Output to copy the full terminal history to the clipboard.")
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
                            "Green pulsing = output streaming. Gray = idle (no output for 5 seconds).")
                    concept("Auto-start Claude",
                            "When enabled in Settings, new sessions automatically run `claude` with your configured flags. Per-project overrides available.")
                    concept("Session Resume",
                            "When opening an existing worktree, Canopy finds the last Claude session ID and passes --resume so you continue where you left off.")
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

    private func shortcutGroup(_ shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(shortcuts, id: \.0) { key, desc in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                        .frame(width: 60, alignment: .trailing)
                    Text(desc)
                        .font(.system(size: 12))
                }
            }
        }
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
