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

### Sandbox modes

Canopy can optionally run Claude Code inside a sandbox for hard process isolation. Your working directory is bind-mounted into the sandbox, so file edits work normally, but everything that isn't explicitly mounted — SSH keys, the Keychain, other repos, the rest of your home directory — is out of reach. Two backends are available.

The backend can be set at three levels -- resolution order is **session → project → global**:

| Level | Where | Notes |
|---|---|---|
| Global | Settings (`Cmd+,`) → Claude Code → Sandbox picker | Default for everything |
| Per project | Edit Project → Override global Claude settings → Sandbox picker | Overrides global |
| Per session | New Worktree Session sheet (`Cmd+Shift+T`) → Sandbox picker | Overrides both, for that session only; "Use project default" inherits |

Canopy validates the required tools before enabling a backend and shows a specific fix (install command, `container system start`, kernel install) when something is missing.

#### Prerequisites

**Docker Sandbox (sbx)**
- macOS with [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- `sbx` CLI: `brew install docker/tap/sbx`

**Apple container**
- **macOS 26+ on Apple silicon only**
- `container` CLI: `brew install container` (or the `.pkg` from [github.com/apple/container](https://github.com/apple/container/releases))
- Start the runtime once per boot: `container system start` (or `brew services start container` to keep it running)
- First run only: install the Linux kernel with `container system kernel set --recommended` (~16 MB download)
- Build the sandbox image once: **Settings → Build Image** (a few minutes; creates the default `canopy-claude` image)
- First sandboxed session only: run `/login` inside it (see below)

#### Docker Sandbox (sbx)

Runs Claude inside a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) microVM. The command becomes `sbx run [sbx-flags] claude -- [claude-flags]`.

- **Session resume is disabled** -- session files (`~/.claude/projects/`) live inside the ephemeral microVM and don't persist across runs

#### Apple container

Runs Claude inside a lightweight VM using Apple's open-source [container](https://github.com/apple/container) runtime -- no Docker Desktop needed.

Unlike sbx, `container` is a generic runtime, so an image is needed. The image name defaults to `canopy-claude`; click **Build Image** in Settings to create it (one-time) from Canopy's built-in recipe:

```dockerfile
FROM node:22-slim
RUN apt-get update && apt-get install -y git ripgrep curl ca-certificates && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 DISABLE_AUTOUPDATER=1
```

Claude Code is installed with the native installer (not npm) on purpose: your host `~/.claude.json` is mounted into the container and declares a native install, so `/doctor` inside the sandbox expects a binary at `/root/.local/bin/claude`. You can also point the image field at any custom image that has claude, node, and git installed. After a Claude Code update, click **Build Image** again to refresh the image.

What Canopy mounts into the VM (all at their host paths, so everything lines up):

- **Your worktree** (`$PWD`) -- file edits land directly in the worktree
- **The project's main repository** (worktree sessions only) -- a worktree's `.git` file points at the main repo, so git inside the sandbox would be broken without it
- **`~/.claude/` and `~/.claude.json`** -- Claude state lives on the host, which is why **session resume, Show Transcript, and `--resume` all work** (unlike sbx)
- **`~/.gitconfig`** -- so commits inside the sandbox have your git identity

Things to know:

- **One-time login**: macOS stores Claude OAuth credentials in the Keychain, which the Linux VM can't read. Run `/login` inside the first sandboxed session; the credentials land in the mounted `~/.claude` and persist for all later sessions
- **Resources**: the VM defaults to 1 GB RAM / 4 CPUs, which is tight for real builds. Put `--memory 8g --cpus 8` in the "Container flags" setting
- **MCP servers**: because your host config is mounted, MCP servers launched via `npx` work (the image includes node), but servers pointing at macOS binaries or apps won't resolve inside the Linux VM
- **Home-directory sessions are blocked**: a sandboxed session can't run in `~` (or above it) -- that mount would overlap the `~/.claude` mounts, which the runtime can't handle. Use a project directory, or turn the sandbox off for that session
- **Terminal rendering**: Canopy passes `TERM`, `COLORTERM`, and a UTF-8 locale into the VM and waits for the VM's terminal to pick up the real window size before starting claude -- without this, output renders garbled

#### What sandboxing does — and doesn't — protect against

Sandboxing limits what an autonomous agent can reach if it misbehaves (a bad command, a prompt injection from something it read, an over-eager cleanup). Be precise about the boundary:

**Protected.** Everything that isn't mounted: your home directory and documents (apart from the few mounted paths listed below), `~/.ssh` keys, browser data, the macOS Keychain, other repositories, host processes, and system settings. Both backends are VMs, so isolation is at the hardware-virtualization level — there is no shared kernel with the host. `~/.gitconfig` is mounted read-only (a writable copy would let an agent plant a git alias or hook path that executes on the host the next time *you* run git).

**Deliberately not protected — know what you're trusting:**

- **The worktree itself** is writable by design. Code the agent writes there runs with full host privileges the moment *you* build or execute it. Sandboxing buys you a review checkpoint, not a guarantee about the code's contents.
- **The project's main repository** is mounted writable in worktree sessions (git requires it: a worktree's commits write into the main repo's `.git`). The agent can therefore touch other branches and `.git` contents — including `.git/hooks`, which execute on the host when you run git there. Review hooks if a sandboxed session did something you didn't expect.
- **Claude's own state** (`~/.claude`, `~/.claude.json`) is writable — that's what makes login persistence and session resume work. An agent could in principle alter its own configuration; if a sandboxed session behaved oddly, `~/.claude/settings.json` and `~/.claude.json` are worth a glance.
- **Outbound network is unrestricted** (Claude needs its API). Anything the agent can read — your repo's code and any secrets in it or in copied `.env` files — it can also transmit. Sandboxing is not an exfiltration barrier.

In short: sandboxing protects *your machine* from the agent. It does not protect *the project it's working on*, and it doesn't replace reviewing what the agent did.

#### In both modes

- **A shield icon** appears next to the session name in the sidebar (hover to see which backend)
- **The split terminal** still opens a host shell (not sandboxed), which is useful for inspecting the real filesystem

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
   - Optionally pick a sandbox just for this session (defaults to the project/global setting -- see [Sandbox modes](#sandbox-modes))

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

3. **Phase 1**: Confirm the target branch and review the commit count. Click **Merge & Finish**.
   - Canopy checks for uncommitted changes and already-merged branches
   - **Cross-worktree pre-flight**: when the project has other worktrees, Phase 1 lists how this branch collides with their branches before you merge — **will conflict** (a real textual conflict, computed with `git merge-tree` without touching your tree) and **shared surface** (both branches touch a package manifest, lockfile, migration, or generated type that may merge cleanly yet still break, e.g. two `0007_*.sql` migrations with different names). This is advisory and never blocks the merge.
   - If there are merge conflicts when you proceed, Canopy aborts and lists the conflicting files

4. **Phase 2**: After a successful merge, choose what to clean up:
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
- **Show Transcript…** — open a scrollable view of the conversation
- Copy Working Directory / Branch Name
- Open in IDE / Terminal / Finder
- **Send Prompt** — fire a saved prompt at this session (see [Prompt Library](#prompt-library))
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
- A collision badge (⚠) on a worktree row when it overlaps another worktree — red for a textual conflict, orange for a shared-surface overlap; hover for the colliding branches and files
- "Open All" to resume all inactive worktrees
- Worktree configuration summary
- Open pull requests for the repository, pulled via `gh pr list`

### Status bar and git awareness

A thin status bar runs along the bottom of the window. For the active session it shows the session name and working directory, plus three git pills driven by a 10-second poller:

- **Changes** — modified-file count with `+insertions` / `−deletions`, hover for the full file list
- **Commits ahead** — how many commits your branch has that the upstream doesn't
- **Pull requests** — open PR count (with draft count in parentheses), hover for titles and numbers

The right side of the status bar shows an activity strip: one dot per session, green if Claude is currently producing output, gray if idle.

The sidebar mirrors the same data per session in compact form: a `+N / −N` diffstat, an up-arrow count for commits-ahead, and a pull-request pill if any. This lets you scan the state of every worktree without switching tabs.

Pull request data comes from `gh pr list`. If `gh` is not installed, the PR pills simply don't appear — everything else keeps working. Install with `brew install gh` and authenticate with `gh auth login`.

### Prompt Library

The Prompt Library lets you save prompts you use repeatedly and fire them at any session from the right-click context menu.

**Sending a prompt:**

Right-click a session → **Send Prompt**. The submenu shows your starred prompts at the top for quick access. **Browse All…** opens a searchable picker over the full library — type a few letters to filter by title or content, click to send.

**Managing prompts** (`Cmd+,` → **Prompt Library** tab):

- **Add**: Click `+` at the bottom of the list.
- **Edit**: Select a row — a title field and body editor appear below the list.
- **Star**: Click the star icon on a row. Starred prompts appear in the right-click submenu without opening the picker.
- **Reorder**: Drag rows to rearrange.
- **Delete**: Hover a row and click the trash icon, or swipe left.

All changes save immediately.

**Template variables** are substituted at send time:

| Variable | Resolves to |
|---|---|
| `{{branch}}` | Current git branch of the session |
| `{{project}}` | Project name |
| `{{dir}}` | Working directory name (last path component) |

Example: a prompt saved as `"Review {{branch}} — check for edge cases and write tests"` becomes `"Review feat/login — check for edge cases and write tests"` when sent to that session.

Prompts are stored globally in `~/.config/canopy/prompts.json` and shared across all projects and sessions.

---

### Settings

**File > Settings** (`Cmd+,`):

| Setting | Default | Purpose |
|---------|---------|---------|
| Auto-start Claude | On | Launch Claude Code when opening a session |
| Claude flags | `--permission-mode auto` | Flags passed to the `claude` command |
| Sandbox | Off | Backend for isolated sessions: Docker Sandbox (`sbx`, requires Docker Desktop) or Apple container (requires macOS 26+, Apple silicon) |
| Sandbox flags | *(empty)* | Additional flags passed to `sbx run` (e.g., `--memory 8g`) |
| Container image | `canopy-claude` | OCI image used by the Apple container backend; **Build Image** creates it from the built-in recipe (see [Sandbox modes](#sandbox-modes)) |
| Container flags | *(empty)* | Additional flags passed to `container run` (e.g., `--memory 8g --cpus 8`) |
| Confirm before closing | On | Ask before closing a session |
| IDE path | `/Applications/Cursor.app` | App used for "Open in IDE" |
| `gh` CLI path | *auto-detected* | Used for open PR data. Leave blank to use `PATH` lookup; override if Homebrew is in a non-standard location. |
| `sbx` CLI path | *auto-detected* | Used when the Docker Sandbox backend is enabled. Same auto-detect/override behavior as `gh`. |
| `container` CLI path | *auto-detected* | Used when the Apple container backend is enabled. Same auto-detect/override behavior as `gh`. |

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
| `sessions.backup.json` | Automatic backup (created on every launch) |
| `prompts.json` | Saved prompt library |

## Tips

- **Text selection in the terminal**: Hold `Option` while dragging. Claude Code enables mouse reporting which captures normal clicks -- `Option` bypasses it.
- **Show Transcript**: Right-click a session > Show Transcript… for a clean scrollable view of the conversation. When Claude Code is running, Canopy reads the structured JSONL session log (`~/.claude/projects/...`) and renders user/assistant turns with markdown formatting. The Copy button (⌘⇧C) puts the formatted markdown on the clipboard -- handy for pasting into PR descriptions or notes.
- **Scrolling with `CLAUDE_CODE_NO_FLICKER=1`**: That flag puts Claude Code into the alternate screen buffer (DECSET 1049), which has no scrollback by terminal protocol design. The live viewport intentionally can't scroll back in that mode -- use Show Transcript to read history, or `Cmd+F` to search.
- **Session resume**: When you reopen an existing worktree, Canopy finds the last Claude session ID automatically. You continue exactly where you left off. Note: Docker Sandbox (sbx) sessions are not resumable -- their session data lives inside the ephemeral microVM and is discarded when the sandbox stops. Apple container sessions resume normally, since `~/.claude` is mounted from the host.
- **Worktree base directory**: By default, worktrees are created at `../canopy-worktrees/<project>/` (as siblings of your repo). Override this per-project if you prefer a different location.
- **Quick rebuild**: Run `bash scripts/bundle.sh` then `open /Applications/Canopy.app`.

## Further reading

- [Git Worktrees documentation](https://git-scm.com/docs/git-worktree) -- the Git feature Canopy builds on
- [Parallel development with worktrees](https://git-scm.com/docs/git-worktree#_description) -- why worktrees beat multiple clones
- [Git branching workflows](https://git-scm.com/book/en/v2/Git-Branching-Branching-Workflows) -- strategies for using branches effectively
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) -- the AI coding assistant Canopy manages
- [Claude Code session management](https://docs.anthropic.com/en/docs/claude-code) -- how `--resume` works
