# Canopy — TODO

## High Priority
- [x] Session persistence across app restarts (restore sessions + auto-resume Claude)
- [x] Cmd+1/2/3… keyboard tab switching
- [x] macOS notifications when a session finishes ("Claude finished in `feat/auth`")
- [ ] Agent tree view: display background agents as a tree under session name in sidebar
  - Scan `.claude/projects/{path}/` for agent session JSONL files
  - Build parent→child relationships from JSONL metadata
  - Live status updates (running/completed/failed)
  - Click to view formatted agent log
  - Detect agent spawn/complete from terminal output patterns

## Phase 4: Command Palette & Search
- [x] Cmd+K command palette (fuzzy-match sessions, projects, branches, actions)
- [x] Terminal output search (Cmd+F)
- [ ] Menu bar extra showing active session count

## Phase 5: Session UX
- [ ] Token/cost tracking per session and per project (parse Claude JSONL files)
- [ ] Session notes — small text field per session for pinned context
- [ ] Drag session between projects (reassign projectId)
- [x] Split view — two terminals side-by-side
- [ ] Export session transcript as clean markdown

## Phase 6: Advanced
- [ ] Voice transcription via WhisperKit (local, on-device)
- [ ] iCloud sync for project configs
- [ ] Spectator mode (read-only view of another session)
- [ ] Session recording/playback (terminal replay)
- [ ] Auto-cleanup stale worktrees (detect merged branches, prompt for removal)

## Polish
- [ ] Onboarding flow for new users
- [x] App icon
- [x] Homebrew cask distribution
- [x] Notarization for Gatekeeper
