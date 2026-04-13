---
title: Canopy Release Infrastructure
date: 2026-04-07
status: approved
---

# Canopy Release Infrastructure Design

## Overview

A fully automated, bulletproof release pipeline for distributing Canopy as a signed and notarized macOS app through three channels: GitHub Releases, Homebrew, and Sparkle in-app updates.

Single command to ship: `git tag v0.2.0 && git push --tags`

---

## Prerequisites (one-time setup)

### Apple Developer Program
Enroll at developer.apple.com ($99/year). This unlocks:
- **Developer ID Application certificate** — signs the app with your identity
- **Notarization** via `notarytool` — required for Gatekeeper to allow silent install
- Does NOT require sandboxing or App Store participation

### App Store
Not viable for Canopy. The app requires `com.apple.security.app-sandbox: false` because it spawns shell processes (`claude`, `git`, arbitrary setup commands) and accesses user-chosen directories. Sandboxing would gut core functionality. The correct path is Developer ID + notarization for direct distribution.

### Sparkle EdDSA key pair
Generate once using Sparkle's `generate_keys` tool. Commit the **public key** to the repo (goes in `Info.plist` as `SUPublicEDKey`). Store the **private key** in GitHub Secrets as `SPARKLE_PRIVATE_KEY`. Never commit the private key.

### Version source of truth
A single `VERSION` file at the repo root (e.g. `0.2.0`). All other version references — `bundle.sh`, `project.yml`, CI workflows, Sparkle appcast, Homebrew formula — read from this file. The release workflow validates that the pushed tag matches `VERSION` before proceeding.

### GitHub Secrets
| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | .p12 Developer ID cert exported from Keychain, base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 |
| `APPLE_ID` | Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | 10-character team ID from developer.apple.com |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for signing update artifacts |
| `HOMEBREW_TAP_TOKEN` | GitHub PAT with write access to `juliensimon/homebrew-canopy` |

---

## Architecture

```
git tag v0.2.0 && git push --tags
        │
        ▼
┌─────────────────────────────────┐
│  release.yml (tag trigger)      │
│  build → test → sign →          │
│  notarize → DMG → release       │
└────────────────┬────────────────┘
                 │ "release published" event
        ┌────────┴─────────┐
        ▼                  ▼
┌──────────────┐   ┌───────────────────┐
│ homebrew.yml │   │ appcast.xml       │
│ PR to tap    │   │ committed to repo │
│ repo with    │   │ → Sparkle picks   │
│ new formula  │   │   up in-app       │
└──────────────┘   └───────────────────┘

ci.yml: independent, runs on every push/PR
```

---

## GitHub Actions Workflows

### `ci.yml` — continuous integration
**Trigger:** push to `main`, any PR  
**Runner:** `macos-15` (free for public repos)

Steps:
1. Checkout
2. `swift build -c release`
3. `swift test`

No signing. Purpose: catch regressions before they reach a tag.

---

### `release.yml` — release pipeline
**Trigger:** push tag matching `v*.*.*`

Steps:
1. Checkout
2. Validate tag matches `VERSION` file — abort if mismatch
3. Import Developer ID certificate into a temporary keychain
4. `swift build -c release`
5. `swift test` — release aborts if any test fails
6. Bundle `.app` (inline `bundle.sh` logic, reading version from `VERSION`)
7. `codesign --deep --force --options runtime --entitlements ... --sign "Developer ID Application: Julien Simon (TEAMID)"` 
8. Verify signature: `codesign --verify --deep --strict` + `spctl --assess --type execute` — abort if invalid
9. Create DMG using `create-dmg` (background image, Applications folder alias)
10. Sign the DMG with Developer ID
11. `xcrun notarytool submit --wait` — blocks until Apple responds (2–10 min)
12. `xcrun stapler staple` — attaches notarization ticket to DMG
13. Run Sparkle's `sign_update` tool against the DMG using `SPARKLE_PRIVATE_KEY`
14. Run `generate_appcast` to update `appcast.xml`
15. Commit and push updated `appcast.xml` to `main`
16. Extract latest section from `CHANGELOG.md` as release notes
17. `gh release create v$VERSION --notes "..." Canopy-$VERSION.dmg`
18. Release is published → triggers `homebrew.yml`

**Artifact upload:** upload the notarized DMG as a workflow artifact at step 12, before the GitHub Release step. If steps 13–17 fail, the notarized DMG is recoverable without rebuilding.

---

### `homebrew.yml` — tap update
**Trigger:** `release published` (not `release created` — draft releases do not fire this)

Steps:
1. Download `Canopy-$VERSION.dmg` from the new release
2. Compute `sha256sum`
3. Open a PR against `juliensimon/homebrew-canopy` with updated `version` and `sha256` in `Casks/canopy.rb`

PR-based (not direct commit) so a bad SHA256 doesn't immediately break `brew upgrade` for all users.

---

## Homebrew Tap

Repository: `juliensimon/homebrew-canopy`

```ruby
# Casks/canopy.rb
cask "canopy" do
  version "0.2.0"
  sha256 "..."

  url "https://github.com/juliensimon/canopy/releases/download/v#{version}/Canopy-#{version}.dmg"
  name "Canopy"
  desc "Parallel Claude Code sessions with git worktrees"
  homepage "https://github.com/juliensimon/canopy"

  depends_on macos: ">= :sonoma"

  app "Canopy.app"

  zap trash: [
    "~/.config/canopy",
  ]
end
```

Install: `brew install --cask juliensimon/canopy/canopy`

When the project reaches ~500 stars and is actively maintained, submit to `homebrew-cask` (becomes `brew install --cask canopy`).

---

## Sparkle In-App Updates

### Dependency
Add to `Package.swift`:
```swift
.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0")
```

### `Info.plist` additions (via `project.yml`)
```yaml
SUFeedURL: https://raw.githubusercontent.com/juliensimon/canopy/main/appcast.xml
SUPublicEDKey: <public EdDSA key — committed to repo>
```

### App wiring (~10 lines)
```swift
import Sparkle

@main struct CanopyApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}
```

Add "Check for Updates…" to the app menu using Sparkle's standard `checkForUpdates` action.

### `appcast.xml` (root of repo, generated by CI)
```xml
<rss version="2.0" xmlns:sparkle="http://www.andymatefoundation.com/xml/rss/module/software-update/">
  <channel>
    <item>
      <title>Version 0.2.0</title>
      <pubDate>Mon, 07 Apr 2026 10:00:00 +0000</pubDate>
      <sparkle:version>0.2.0</sparkle:version>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/juliensimon/canopy/releases/download/v0.2.0/Canopy-0.2.0.dmg"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

---

## Versioning

**SemVer 0.x** — `0.1.0` → `0.2.0` → ... → `1.0.0` when stable.

Single source of truth: `VERSION` file at repo root. All tooling reads from it.

**CHANGELOG.md** — Keep a Changelog format. CI extracts the latest `## [x.y.z]` section for GitHub Release notes. Edit before tagging.

**Release process:**
1. Edit `VERSION` and `CHANGELOG.md`
2. Commit: `git commit -m "chore: release v0.2.0"`
3. Tag: `git tag v0.2.0 && git push --tags`
4. Everything else is automated

---

## Anthropic Ecosystem Visibility

### Before launch
- Add GitHub topics: `claude-code`, `anthropic`, `git-worktrees`, `macos`, `developer-tools`
- Ensure README has a crisp one-liner and a GIF showing worktree creation + Claude launch
- Submit PRs to `awesome-claude-code` community lists on GitHub

### At launch
- Post in Claude Code Discord (`#community` or `#showcase`)
- Tweet at `@AnthropicAI`; tag `@alexalbert__` (Claude Code developer relations)
- Post on Hacker News: `Show HN: Canopy — parallel Claude Code sessions with git worktrees`
- Blog post + tweet from HuggingFace account (audience overlap with Claude Code users is high)

### Longer term
- Open a discussion on the Claude Code GitHub repo asking about community showcase opportunities
- If Claude Code ships an extensions/plugins API, Canopy is a natural candidate for docs inclusion

---

## Additional Items Before v1 Launch

| Item | Priority | Notes |
|---|---|---|
| App icon | High | Required for polished launch; Homebrew displays it |
| DMG background image | Medium | `create-dmg` supports custom backgrounds |
| Crash reporting | Medium | Sentry free tier, or pre-filled GitHub issue link in Help menu |
| GitHub Pages landing page | Medium | Home for the install command and screenshot |
| Certificate expiry reminder | Low | Developer ID certs expire in 5 years; set calendar reminder |
| Rollback plan | Low | Know the answer: yank GitHub Release + revert Homebrew PR + push hotfix tag |

---

## Rollback Plan

If a critical bug ships:
1. Edit the GitHub Release to draft (stops new downloads, doesn't affect notarization)
2. Revert or close the Homebrew tap PR (or push a formula revert)
3. Push a hotfix tag (`v0.2.1`) — pipeline runs automatically
4. Sparkle's `minimumAutoupdateVersion` can be used to force users past a bad version
