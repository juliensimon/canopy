# Canopy

**Parallel Claude Code sessions with git worktrees.**

Canopy is a native macOS app that lets you run multiple [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions in parallel, each in its own [git worktree](https://git-scm.com/docs/git-worktree). Work on a feature, a bug fix, and a refactor at the same time -- each with its own branch, its own directory, and its own Claude instance.

## Why

Claude Code is powerful, but it works in a single directory on a single branch. If you want to run two tasks in parallel, you need two checkouts. Managing those by hand (creating worktrees, copying `.env` files, symlinking `node_modules`, launching Claude in each one, cleaning up afterwards) gets tedious fast.

Canopy automates the entire lifecycle:

1. **Create** a worktree with a new branch from your base
2. **Set up** the environment (copy config files, symlink heavy directories, run setup commands)
3. **Launch** Claude Code with your preferred flags, resuming previous conversations
4. **Merge** the branch back when you're done
5. **Clean up** the worktree and branch

All from a single window with tabs, a sidebar, and right-click context menus.

## How it works

Canopy builds on two ideas:

- **[Git worktrees](https://git-scm.com/docs/git-worktree)** let you check out multiple branches of the same repo simultaneously, each in its own directory. They share the same `.git` object store, so they're lightweight and fast to create. See the [Git documentation on parallel development](https://git-scm.com/docs/git-worktree#_description) for background.

- **Claude Code sessions** are directory-scoped. Each worktree gets its own Claude instance. Canopy finds and resumes previous sessions automatically using `--resume`.

### Architecture

```
+-----------+----------------------------+
| Sidebar   | Tab Bar                    |
|           | [branch-a] [branch-b]  [+] |
| Projects  +----------------------------+
| & Sessions|                            |
|           |   Terminal (SwiftTerm)      |
|           |   Running Claude Code      |
|           |                            |
|           +----------------------------+
|           | Status Bar                 |
+-----------+----------------------------+
```

Each project in the sidebar maps to a git repo. Under each project, you see active sessions (one per worktree). Click a tab or sidebar entry to switch. Activity dots show which sessions have output streaming.

## Quick start

### Build

```bash
# Build and create .app bundle
bash scripts/bundle.sh

# Launch
open build/Canopy.app
```

Requires macOS 14+ and Swift 6.0.

### First steps

1. **Add a project** (`Cmd+Shift+P`) -- point to a git repository
2. **Create a worktree session** (`Cmd+Shift+T`) -- pick a base branch, name your feature branch
3. Canopy creates the worktree, copies your config files, runs setup commands, and launches Claude
4. Work on your feature. Open more worktree sessions for parallel tasks.
5. When done, right-click the session and choose **Merge & Finish**

### Project configuration

When adding a project, you can configure:

| Setting | Example | Purpose |
|---------|---------|---------|
| Files to copy | `.env`, `.env.local` | Copied from main repo into each new worktree |
| Symlink paths | `node_modules`, `.venv` | Symlinked (not copied) to save disk space |
| Setup commands | `npm install`, `bundle install` | Run in the worktree after creation |
| Worktree base dir | `~/worktrees/myproject` | Where worktrees are created (default: `../canopy-worktrees/<project>`) |
| Auto-start Claude | on/off | Override the global setting per project |
| Claude flags | `--permission-mode auto` | Override the global flags per project |

## Features

- **Worktree lifecycle**: create, open, merge, delete -- all from the UI
- **Session resume**: reopening a worktree continues the previous Claude conversation
- **Auto-start Claude**: configurable globally and per-project
- **Tab sorting**: manual, by name, project, creation date, or directory (`Cmd+Shift+S` to cycle)
- **Drag-and-drop**: reorder tabs and sidebar sessions
- **Context menus**: Open in Terminal, Finder, or IDE; copy paths and branch names; rename sessions
- **Merge & Finish**: merge your branch, then clean up the worktree and branch in one step
- **Config backup**: `projects.backup.json` is created on every launch

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New plain session (directory picker) |
| `Cmd+Shift+T` | New worktree session |
| `Cmd+Shift+P` | Add project |
| `Cmd+Shift+S` | Cycle tab sort mode |
| `Cmd+,` | Settings |
| `Cmd+?` | Help |

## Configuration

Settings and project data are stored in `~/.config/canopy/`:

- `settings.json` -- global preferences (auto-start, Claude flags, IDE path, etc.)
- `projects.json` -- your project list and per-project config
- `projects.backup.json` -- automatic backup created on launch

## Learn more

- [User Guide](docs/guide.md) -- detailed walkthrough of all features and workflows
- [Git Worktrees](https://git-scm.com/docs/git-worktree) -- the Git feature Canopy builds on
- [Parallel Development with Worktrees](https://git-scm.com/docs/git-worktree#_description) -- why worktrees are useful
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) -- the AI coding assistant Canopy manages

## Feedback

Found a bug or have a feature request? [Open an issue](https://github.com/juliensimon/canopy/issues).

## Author

**Julien Simon** -- julien@julien.org

## License

Copyright 2026 Julien Simon.

Canopy is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).

**Commercial licensing**: If you need to use Canopy under terms other than AGPL-3.0 (e.g., embedding in a proprietary product or redistributing without source disclosure), commercial licenses are available. Contact julien@julien.org.

**Contributing**: By submitting a pull request, you agree to the [Contributor License Agreement](CLA.md), which grants the project maintainer the right to relicense your contributions. This enables dual licensing while keeping the open source version free under AGPL.
