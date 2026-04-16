# Canopy User Guide

## The problem

You're using Claude Code to build a feature. Halfway through, a critical bug comes in. You need to context-switch, but Claude is mid-conversation on your feature branch. You can't just `git checkout` -- Claude's changes are uncommitted, and even if they weren't, you'd lose the conversation context.

The manual workaround is:

```bash
# Create a separate checkout for the bug fix
git worktree add ../hotfix-auth -b fix/auth-crash main
cd ../hotfix-auth
cp ../myproject/.env .
ln -s ../myproject/node_modules .
npm install  # maybe
claude --resume <some-session-id>
```

Then do it again for the next task. And remember to clean up afterwards. And remember which Claude session was in which directory.

Canopy does all of this in two clicks.

## Core concepts

### Git worktrees

A [git worktree](https://git-scm.com/docs/git-worktree) is a linked checkout of your repository at a different path. It has its own working directory and its own branch, but shares the same `.git` object store as your main checkout. This means:

- Creating a worktree is fast (no clone, no copy of history)
- Each worktree has its own branch -- changes don't interfere
- Commits, branches, and stashes are shared across all worktrees
- You can have as many as you want

This is the foundation of parallel development. Instead of juggling stashes or having multiple clones, you just have multiple directories, each on a different branch. See [the Git docs on worktrees](https://git-scm.com/docs/git-worktree#_description) for more.

### Projects

A project in Canopy is a pointer to a git repository plus configuration for how to set up worktrees:

- **Files to copy**: Configuration files (`.env`, `.env.local`) that aren't tracked by git but are needed to run your project. Canopy copies them from the main repo into each new worktree.
- **Symlink paths**: Heavy directories (`node_modules`, `.venv`, `vendor`) that you don't want duplicated. Canopy symlinks them from the main repo.
- **Setup commands**: Shell commands to run after creating a worktree (`npm install`, `bundle install`, `make setup`).

### Sessions

A session is a terminal running in a directory. There are two kinds:

- **Worktree sessions**: Tied to a project and a git worktree. Canopy manages their lifecycle.
- **Plain sessions**: A terminal in any directory. Use these for one-off tasks.

### Claude Code integration

When Canopy creates or opens a session, it can auto-start Claude Code with your preferred flags (e.g., `--permission-mode auto`). When reopening a worktree that had a previous Claude session, Canopy passes `--resume <session-id>` so you continue the conversation where you left off.

Session IDs are found automatically by scanning `~/.claude/projects/`.

### Docker Sandbox mode

Canopy can optionally run Claude Code inside a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) microVM for hard process isolation. When enabled, the command becomes `sbx run claude -- [flags]` instead of `claude [flags]`. Your working directory is bind-mounted into the sandbox, so file edits work normally, but the agent can't touch the rest of your system.

Key behaviors in sandbox mode:
- **Session resume is disabled** -- session files (`~/.claude/projects/`) live inside the ephemeral microVM and don't persist across runs
- **A shield icon** appears next to the session name in the sidebar
- **The split terminal** still opens a host shell (not sandboxed), which is useful for inspecting the real filesystem

Sandbox mode requires [Docker Desktop](https://www.docker.com/products/docker-desktop/) and `sbx` (`brew install docker/tap/sbx`). Canopy validates both are installed before enabling the toggle.

## Workflows

### Starting a new feature

1. Add your project if you haven't already: **File > Add Project** (`Cmd+Shift+P`)
   - Browse to your git repository
   - Configure files to copy, symlinks, and setup commands
   - These settings apply to every worktree you create from this project

2. Create a worktree session: **File > New Worktree Session** (`Cmd+Shift+T`)
   - Pick your project
   - Select a base branch (Canopy auto-detects `main`, `master`, `develop`, or `dev`)
   - Name your feature branch (e.g., `feat/user-auth`)

3. Canopy will:
   - Run `git worktree add` with your branch
   - Copy config files from the main repo
   - Create symlinks for heavy directories
   - Run your setup commands
   - Open a terminal in the worktree
   - Start Claude Code if auto-start is enabled

4. Work normally. Your main repo is untouched.

### Working on multiple tasks

Repeat the above for each task. Each gets its own branch and worktree. Switch between them using the tab bar or sidebar. Activity dots (green = active, gray = idle) show which sessions have output streaming.

This is the core value proposition: **true parallel development** where each Claude instance is isolated and focused on one task.

### Resuming work on an existing worktree

Click your project in the sidebar to see the project detail view. It lists all worktrees with their branches and status:

- **Green dot + "Running"**: A session already exists for this worktree
- **"Open" button**: Creates a new session in the worktree and resumes the last Claude conversation

You can also click **"Open All"** to resume all inactive worktrees at once.

### Merging and cleaning up

When your feature is done:

1. **Close the session first.** The Merge button only appears on worktree rows that don't have a running session. This is intentional -- it prevents merging while Claude might still have uncommitted work in the worktree.

2. Right-click the session in the sidebar > **Merge & Finish**
   (or close the session, then click the **Merge** button on the worktree row in the project detail view)

2. **Phase 1**: Confirm the target branch and review the commit count. Click **Merge & Finish**.
   - Canopy checks for uncommitted changes and already-merged branches
   - If there are merge conflicts, Canopy aborts and lists the conflicting files

3. **Phase 2**: After a successful merge, choose what to clean up:
   - Delete the worktree directory
   - Delete the feature branch

This replaces the manual `git checkout main && git merge feat/... && git worktree remove ... && git branch -d feat/...` dance.

### Deleting a worktree without merging

In the project detail view, click the trash icon on a worktree row. Canopy warns you about:

- Uncommitted changes that would be lost
- Commits not merged into the main branch

### Plain sessions

For tasks that don't need a worktree (quick shell commands, working in a non-git directory), use **File > New Session** (`Cmd+T`). This opens a directory picker and creates a plain terminal session.

## UI reference

### Sidebar

The sidebar shows:

- **Sessions section**: Plain sessions (not tied to a project)
- **Project sections**: Collapsible, showing worktree sessions under each project

Right-click context menus are available on both session rows and project headers.

**Session context menu:**
- Rename
- Copy Session Output / Working Directory / Branch Name
- Open in IDE / Terminal / Finder
- Merge & Finish (worktree sessions)
- Session Info
- Close

**Project context menu:**
- New Worktree Session
- Edit Project
- Open in Terminal / Finder
- Copy Repository Path
- Delete Project

### Tab bar

Horizontal tabs at the top. Drag to reorder (auto-switches to Manual sort mode). The sort button lets you switch between Manual, Name, Project, Creation Date, and Directory ordering.

### Project detail view

Shown when you click a project header in the sidebar. Displays:

- Repository info (current branch, branch count)
- All worktrees with status, base branch, and action buttons (Open, Merge, Delete)
- "Open All" to resume all inactive worktrees
- Worktree configuration summary

### Settings

**File > Settings** (`Cmd+,`):

| Setting | Default | Purpose |
|---------|---------|---------|
| Auto-start Claude | On | Launch Claude Code when opening a session |
| Claude flags | `--permission-mode auto` | Flags passed to the `claude` command |
| Docker Sandbox | Off | Run Claude inside a `sbx` microVM (requires Docker Desktop + `sbx`) |
| Sandbox flags | *(empty)* | Additional flags passed to `sbx run` (e.g., `--memory 8g`) |
| Confirm before closing | On | Ask before closing a session |
| IDE path | `/Applications/Cursor.app` | App used for "Open in IDE" |

Per-project overrides for auto-start, Claude flags, and sandbox mode are available in the project edit sheet.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New plain session (directory picker) |
| `Cmd+Shift+T` | New worktree session |
| `Cmd+Shift+P` | Add project |
| `Cmd+K` | Command palette (fuzzy-match sessions, projects, branches, actions) |
| `Cmd+F` | Find in terminal output |
| `Cmd+Shift+D` | Toggle split terminal |
| `Cmd+Shift+A` | Activity dashboard |
| `Cmd+Shift+S` | Cycle tab sort mode |
| `Cmd+1`–`Cmd+9` | Jump to tab N |
| `Cmd+,` | Settings |
| `Cmd+?` | Help |

The same list is available at any time via **Help > Keyboard Shortcuts**.

## Configuration files

All configuration lives in `~/.config/canopy/`:

| File | Contents |
|------|----------|
| `settings.json` | Global preferences |
| `projects.json` | Project list and per-project config |
| `projects.backup.json` | Automatic backup (created on every launch) |
| `sessions.json` | Persisted sessions, restored on app restart |

## Tips

- **Text selection in the terminal**: Hold `Option` while dragging. Claude Code enables mouse reporting which captures normal clicks -- `Option` bypasses it.
- **Copy full session output**: Right-click a session > Copy Session Output. Useful for sharing Claude's work.
- **Session resume**: When you reopen an existing worktree, Canopy finds the last Claude session ID automatically. You continue exactly where you left off. Note: sandbox sessions are not resumable -- the session data lives inside the ephemeral microVM and is discarded when the sandbox stops.
- **Worktree base directory**: By default, worktrees are created at `../canopy-worktrees/<project>/` (as siblings of your repo). Override this per-project if you prefer a different location.
- **Quick rebuild**: Run `bash scripts/bundle.sh` then `open build/Canopy.app`.

## Further reading

- [Git Worktrees documentation](https://git-scm.com/docs/git-worktree) -- the Git feature Canopy builds on
- [Parallel development with worktrees](https://git-scm.com/docs/git-worktree#_description) -- why worktrees beat multiple clones
- [Git branching workflows](https://git-scm.com/book/en/v2/Git-Branching-Branching-Workflows) -- strategies for using branches effectively
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) -- the AI coding assistant Canopy manages
- [Claude Code session management](https://docs.anthropic.com/en/docs/claude-code) -- how `--resume` works
