<div align="center">

<img src="docs/screenshots/splash.png" alt="Canopy" width="820"/>

**Parallel Claude Code sessions with git worktrees — a native macOS app.**

*One window. Parallel branches. Parallel Claudes. Zero context switching.*

<br/>

[![Latest release](https://img.shields.io/github/v/release/juliensimon/canopy?display_name=tag&sort=semver&color=4c9a6a)](https://github.com/juliensimon/canopy/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/juliensimon/canopy/total?color=4c9a6a&logo=github)](https://github.com/juliensimon/canopy/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/juliensimon/canopy/ci.yml?branch=master&logo=github)](https://github.com/juliensimon/canopy/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/juliensimon/canopy/branch/master/graph/badge.svg)](https://codecov.io/gh/juliensimon/canopy)
[![Stars](https://img.shields.io/github/stars/juliensimon/canopy?color=4c9a6a&logo=github)](https://github.com/juliensimon/canopy/stargazers)
[![Issues](https://img.shields.io/github/issues/juliensimon/canopy?color=4c9a6a)](https://github.com/juliensimon/canopy/issues)
[![Last commit](https://img.shields.io/github/last-commit/juliensimon/canopy?color=4c9a6a)](https://github.com/juliensimon/canopy/commits/master)

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

<br/>

### [⬇ Download Canopy for macOS](https://github.com/juliensimon/canopy/releases/latest/download/Canopy.dmg)

<sub>Universal binary · Apple Silicon + Intel · Notarized · macOS 14+</sub>

</div>

---

<div align="center">

https://github.com/user-attachments/assets/e455e1a9-884c-46e5-bd14-9c0fc3424672

</div>

---

## Why I built this

I've been using Canopy every day for months on my own projects. I'm sharing it now because it has earned its place on my dock, and I think it might earn a place on yours too.

Here's the honest pitch: **Claude Code is a superpower. Canopy feels like wearing all five Infinity Stones.**

When you use Claude Code seriously — not just for experiments, but for real production work — you hit a wall the tool wasn't designed to push through. Claude is brilliant at focusing on *one* thing in *one* directory. But real engineering work doesn't come one thing at a time. A bug report lands while you're refactoring. A teammate asks you to review a change while you're writing tests. The roadmap demands you keep shipping while you investigate a flaky test. You need to work on three things at once, but Claude — and `git` — want you to work on one.

You *can* hack around it: stash, checkout, maybe a second clone, maybe `git worktree add` and a hand-written shell script to copy your `.env`, maybe remember which of your six Terminal.app tabs was running which session. You end up with a tab graveyard, stale worktrees littering your disk, Claude sessions you can't find, and a quiet tax on every task you do.

Canopy removes that tax. Completely.

## What you actually get back

Every Canopy feature exists because I was tired of doing something manually. Each one saves a few seconds. Do the math over a day — over a week, over a month — and the compound is real.

| You used to do this | With Canopy |
|---|---|
| Stash your work, checkout another branch, lose Claude's conversation context | Open a new worktree session — your old session keeps running in another tab |
| Hunt through `~/.claude/projects/<hash>/` for a session ID, then `claude --resume abc123…` | Click the tab. Canopy resumes the right session automatically. |
| Juggle six Terminal.app windows, cmd-tabbing to find the right one | One window, one tab bar, `Cmd+1`–`Cmd+9` to jump anywhere |
| Copy-paste the working directory into Cursor/VS Code with cmd-c / cmd-shift-o / cmd-v | Right-click → **Open in IDE** |
| Switch windows to run `git log` while Claude is working | `Cmd+Shift+D` — shell pane drops in below Claude, no interruption |
| Re-run `npm install`, copy `.env`, symlink `node_modules` every time you make a worktree | Configure once per project. Canopy does it on every new worktree. |
| Wonder which of your branches are merged and safe to delete | Project view lists every worktree with status and a one-click **Merge & Finish** |
| `git checkout main && git pull && git merge feat/… && git worktree remove … && git branch -d …` | Right-click → **Merge & Finish** — two panels, one button |
| Squint at `ls ~/.claude/projects/` trying to guess how many tokens you've burned this week | Open **Activity** — token counts, session history, 12-week heatmap |

None of these are big problems on their own. All of them are papercuts. Canopy is a tool for people who notice papercuts.

---

## Install

### Homebrew (recommended)

```bash
brew install --cask juliensimon/canopy/canopy
```

### Direct download

Grab the latest signed and notarized `.dmg` from **[Releases](https://github.com/juliensimon/canopy/releases/latest)**. Open, drag to Applications, launch.

**Requirements:** macOS 14 Sonoma or later. Apple Silicon or Intel. Claude Code installed (`claude` available in your `$PATH`).

---

## Quick start

1. **Add a project** (`Cmd+Shift+P`) — point at any git repository. Configure files to copy (`.env`), symlink paths (`node_modules`), and setup commands (`npm install`).
2. **Create a worktree session** (`Cmd+Shift+T`) — pick a base branch, name your feature branch.
3. Canopy creates the worktree, copies config, runs your setup, and launches Claude Code. Start prompting.
4. Need a parallel task? `Cmd+Shift+T` again. Each session is completely isolated.
5. When you're done with a session, right-click → **Merge & Finish**. Canopy merges your branch and cleans up the worktree.

That's the whole loop. Repeat forever.

---

## Features in depth

### 🪟 Parallel sessions, one window

![Main window with multiple tabs](docs/screenshots/hero.png)

Each tab is a separate worktree running its own Claude Code instance. Switch between them with `Cmd+1`–`Cmd+9`. Drag tabs to reorder. Sort by name, project, creation date, or directory with `Cmd+Shift+S`. Activity dots show which sessions have output streaming, so you know at a glance which Claude is still thinking.

When you close and reopen Canopy, every session comes back — **with its Claude conversation resumed automatically**. No session IDs to remember, no `--resume` flags to type. Canopy finds the right session by scanning `~/.claude/projects/` and passes it to `claude` for you.

---

### 📊 Activity dashboard — know where your tokens go

![Activity dashboard](docs/screenshots/activity.png)

Token usage is the one thing Claude Code doesn't surface well. Canopy fixes that.

The **Activity** view parses your `~/.claude/projects/` JSONL files and gives you a full picture of how you've been using Claude:

- **All-time token totals** — input and output, across every session you've ever run
- **Last 12 weeks** — same breakdown, so you can see recent trends
- **Session count** — how many conversations you've had in the window
- **Busiest day** — when were you deep in Claude?
- **Model breakdown** — percentage split across Opus, Sonnet, and Haiku
- **Hour-by-hour heatmap** — 12 weeks of your actual working hours, visualized

This is the view I use to answer "am I on track for my API budget this month" and "when am I most productive." No third-party tools, no scraping, no estimation — it's reading the same JSONL files Claude Code writes.

---

### ⌨️ Command palette — fuzzy search everything

`Cmd+K` opens a fuzzy-match palette over every session, project, branch, and action Canopy knows about. Type three letters of a branch name, hit return, you're there. Type the name of a project, hit return, the project view opens. Type "merge", hit return, the merge flow fires on the current session.

If you have more than four or five sessions open, this is the fastest way to navigate. Faster than clicking. Faster than Mission Control. Fast enough to feel instant.

---

### 🔎 Find in terminal — stop scrolling

![Terminal search](docs/screenshots/terminal-search.png)

`Cmd+F` inside any session opens an incremental search over the terminal output. Matches highlight as you type. Return jumps to the next match. Shift-return jumps to the previous one. Escape closes the search.

This is a small feature that turns out to matter a lot: when Claude produces a 400-line plan and you need to jump to the part about "database migration," you used to scroll. Now you don't.

---

### ⬓ Split terminal — Claude up top, shell below

![Split terminal](docs/screenshots/split-terminal.png)

`Cmd+Shift+D` toggles a secondary shell pane below Claude's terminal. Need to run `git status` while Claude is mid-thought? Peek at the test output from another tool? Tail a log? You don't need to interrupt Claude or open a new window. The split pane is a full interactive shell, scoped to the same worktree, and you can hide it the same way you showed it.

This is the feature I was most skeptical I'd use, and now I can't imagine working without it.

---

### 🛡 Docker Sandbox — run Claude in isolation

Enable **Run in Docker Sandbox** in Settings or per-project to launch Claude inside a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) microVM via `sbx run`. Your working directory is bind-mounted into the sandbox, so file edits work normally, but the agent can't touch the rest of your system — network, Docker socket, home directory, and tools are all isolated.

Canopy checks that both Docker Desktop and `sbx` are installed before enabling the toggle. When sandbox mode is active:

- The command becomes `sbx run [sbx-flags] claude -- [claude-flags]`
- Session resume is disabled (session files live inside the ephemeral microVM)
- A shield icon appears next to the session name in the sidebar
- The split terminal still opens a host shell (useful for inspecting the real filesystem)

**Requirements:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) and `sbx` (`brew install docker/tap/sbx`).

---

### ✅ Merge & Finish — one click, one worktree retired

![Merge and Finish flow](docs/screenshots/merge-finish.png)

The last step of every feature used to be a four-command dance:

```bash
git checkout main
git pull
git merge feat/whatever
git worktree remove ../canopy-worktrees/myproject/feat-whatever
git branch -d feat/whatever
```

…except you never actually did all of it, and now you have 11 stale worktrees and 40 merged branches on your laptop. Canopy replaces the whole thing with a two-phase confirmation sheet. Phase 1: pick the target branch, confirm the commit count, see any conflicts before they happen. Phase 2: pick what to clean up — worktree directory, feature branch, both, or neither. One click. Done. No debt.

---

### 🌳 Project view — see every worktree at once

![Project detail view](docs/screenshots/project-detail.png)

Click any project in the sidebar to see every worktree, its branch, its status, and a one-click button to open, merge, or delete it. "Open All" resumes every inactive worktree at once with their prior Claude sessions — the fastest way to get back into a multi-branch project after a weekend away.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+T` | New plain session (directory picker) |
| `Cmd+Shift+T` | New worktree session |
| `Cmd+Shift+P` | Add project |
| `Cmd+K` | Command palette |
| `Cmd+F` | Find in terminal |
| `Cmd+Shift+D` | Toggle split terminal |
| `Cmd+Shift+A` | Activity dashboard |
| `Cmd+Shift+S` | Cycle tab sort mode |
| `Cmd+1`–`Cmd+9` | Jump to tab N |
| `Cmd+,` | Settings |
| `Cmd+?` | Keyboard shortcuts reference |

---

## How it works

Canopy builds on two ideas that play well together:

- **[Git worktrees](https://git-scm.com/docs/git-worktree)** let you check out multiple branches of the same repo simultaneously, each in its own directory, sharing one `.git` store. Creating one is cheap and fast.
- **Claude Code sessions** are directory-scoped and resumable. Canopy finds the last session ID for each worktree and passes it via `--resume`, so conversations survive restarts.

Everything else — the tabs, the project view, the Activity dashboard, the palette, the split pane — is a native SwiftUI app wrapped around [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation. No Electron, no webviews, no bundled Node. It launches fast, idles quiet, and behaves like a Mac app.

For a deeper walkthrough, read the **[User Guide](docs/guide.md)**.

---

## Per-project configuration

Every project can be configured independently from the **Add Project** sheet:

| Setting | Example | Why |
|---|---|---|
| Files to copy | `.env`, `.env.local` | Untracked config files Claude needs at runtime |
| Symlink paths | `node_modules`, `.venv`, `vendor` | Heavy directories; symlinks save disk and install time |
| Setup commands | `npm install`, `bundle install`, `make setup` | Run once in each fresh worktree |
| Worktree base directory | `~/worktrees/myproject` | Where new worktrees live (default: `../canopy-worktrees/<project>`) |
| Auto-start Claude | on/off | Per-project override of the global default |
| Claude flags | `--permission-mode auto` | Per-project override of the global flags |
| Docker Sandbox | on/off | Run Claude inside a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) microVM |
| Sandbox flags | `--memory 8g` | Additional flags passed to `sbx run` |

All configuration lives in `~/.config/canopy/`:

- `settings.json` — global preferences
- `projects.json` — project list and per-project config
- `projects.backup.json` — automatic backup created on every launch
- `sessions.json` — persisted sessions, restored on app restart

---

## Contributing

Found a bug, have a feature request, or want to send a patch? **[Open an issue](https://github.com/juliensimon/canopy/issues)** or a PR.

Because Canopy is dual-licensed (see below), contributors are asked to sign the **[Contributor License Agreement](CLA.md)** by submitting a pull request. This is a lightweight CLA that grants the project maintainer the right to relicense contributions. It's what makes dual licensing possible while keeping the open source version free under AGPL.

---

## Author

Built by **Julien Simon** — [julien@julien.org](mailto:julien@julien.org).

I've been writing software for a long time. I built Canopy because I use Claude Code every day and the rough edges were getting in the way of the work. It started as a weekend experiment and turned into the tool I now reach for first every morning.

If Canopy saves you time, the best thank-you is to tell someone else who might also find it useful — post it on social, drop it in a Slack, submit a PR. A star on the repo never hurts either.

---

## License

Copyright © 2026 Julien Simon.

Canopy is licensed under the **[GNU Affero General Public License v3.0](LICENSE)** (AGPL-3.0). You can use it, modify it, and redistribute it under the terms of that license.

**Commercial licensing**: If you need to use Canopy under terms other than AGPL-3.0 — for example, embedding it in a proprietary product or redistributing without source disclosure — commercial licenses are available. Contact [julien@julien.org](mailto:julien@julien.org).
