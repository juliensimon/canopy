# Canopy Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fully automated release pipeline — push a tag, get a signed+notarized DMG on GitHub Releases, Homebrew tap updated via PR, all without human intervention.

**Architecture:** Three GitHub Actions workflows (`ci.yml`, `release.yml`, `homebrew.yml`) triggered in sequence. A single `VERSION` file is the source of truth for version numbers everywhere. `xcodebuild` handles building and signing via Developer ID certificate stored in GitHub Secrets.

**Tech Stack:** GitHub Actions (macos-15 runner), xcodebuild, notarytool, create-dmg (Homebrew), GitHub CLI (`gh`), Homebrew tap repo (`juliensimon/homebrew-canopy`)

---

## Pre-flight Checklist (human tasks — do these before running the pipeline)

These are one-time manual steps. None of them can be automated.

### P1: Enroll in Apple Developer Program
- Go to https://developer.apple.com/enroll/
- Enroll as an individual ($99/year)
- Note your **Team ID** (10-character string, visible at developer.apple.com/account → Membership)

### P2: Create a Developer ID Application certificate
- Open Xcode → Settings → Accounts → Manage Certificates
- Click `+` → Developer ID Application
- This creates the certificate in your login keychain

### P3: Export the certificate as a .p12 file
- Open Keychain Access
- Find "Developer ID Application: Your Name (TEAMID)" under My Certificates
- Right-click → Export → save as `certificate.p12` with a strong password
- Base64-encode it: `base64 -i certificate.p12 | pbcopy`
- Store the base64 string — this becomes `APPLE_CERTIFICATE_BASE64` in GitHub Secrets

### P4: Create an app-specific password for notarytool
- Go to https://appleid.apple.com → Sign-In and Security → App-Specific Passwords
- Generate a password labeled "Canopy CI notarytool"
- This becomes `APPLE_APP_PASSWORD` in GitHub Secrets

### P5: Create a GitHub Personal Access Token for the Homebrew tap
- Go to https://github.com/settings/tokens → Generate new token (classic)
- Scopes: `repo` (full)
- This becomes `HOMEBREW_TAP_TOKEN` in GitHub Secrets
- This token needs write access to `juliensimon/homebrew-canopy`

### P6: Add all GitHub Secrets to the canopy repo
Go to github.com/juliensimon/canopy → Settings → Secrets and variables → Actions → New repository secret

| Secret name | Value |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Output of `base64 -i certificate.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the .p12 |
| `APPLE_ID` | Your Apple ID email address |
| `APPLE_APP_PASSWORD` | App-specific password from P4 |
| `APPLE_TEAM_ID` | 10-character Team ID from P1 |
| `HOMEBREW_TAP_TOKEN` | PAT from P5 |

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `VERSION` | Create | Single source of truth for version number |
| `CHANGELOG.md` | Create | Release notes source; CI extracts latest section |
| `scripts/bundle.sh` | Modify | Read version from `VERSION` instead of hardcoded string |
| `ExportOptions.plist` | Create | Tells xcodebuild to export with Developer ID signing |
| `.github/workflows/ci.yml` | Create | Build + test on every push and PR |
| `.github/workflows/release.yml` | Create | Full release pipeline triggered by version tag |
| `.github/workflows/homebrew.yml` | Create | Open PR on Homebrew tap when release is published |

Homebrew tap is a separate repo (`juliensimon/homebrew-canopy`) with one file: `Casks/canopy.rb`.

---

## Task 1: VERSION file and bundle.sh update

**Files:**
- Create: `VERSION`
- Modify: `scripts/bundle.sh` (lines 24, 63)

- [ ] **Step 1: Create VERSION file**

```bash
echo "0.1.0" > VERSION
```

Verify: `cat VERSION` → `0.1.0`

- [ ] **Step 2: Update bundle.sh to read version from VERSION**

In `scripts/bundle.sh`, replace the two hardcoded `0.1.0` strings:

Line 24 — change:
```bash
    static let version = "0.1.0"
```
to:
```bash
    static let version = "$(cat VERSION)"
```

Line 63 — change:
```xml
    <string>0.1.0</string>
```
to:
```xml
    <string>$(cat VERSION)</string>
```

- [ ] **Step 3: Verify bundle.sh still works**

```bash
bash scripts/bundle.sh
```
Expected: builds successfully, `build/Canopy.app` exists.

Check the version was embedded:
```bash
defaults read build/Canopy.app/Contents/Info.plist CFBundleShortVersionString
```
Expected: `0.1.0`

- [ ] **Step 4: Commit**

```bash
git add VERSION scripts/bundle.sh
git commit -m "chore: add VERSION file as single source of truth for version number"
```

---

## Task 2: CHANGELOG.md

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create CHANGELOG.md**

```bash
cat > CHANGELOG.md << 'EOF'
# Changelog

All notable changes to Canopy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-07

### Added
- Worktree lifecycle: create, open, merge, delete from the UI
- Session resume: reopen a worktree and continue the previous Claude conversation
- Auto-start Claude: configurable globally and per-project
- Tab sorting: manual, by name, project, creation date, or directory (Cmd+Shift+S)
- Drag-and-drop: reorder tabs and sidebar sessions
- Context menus: Open in Terminal, Finder, or IDE; copy paths and branch names
- Merge & Finish: merge branch, clean up worktree and branch in one step
- Split terminal: secondary shell pane below the main terminal (Cmd+Shift+D)
- Session persistence: sessions restored across app restarts with Claude resume
- Tab switching: Cmd+1–9 to jump to any tab instantly
- Finish notifications: macOS notification when a session finishes in background
- Command palette: Cmd+K fuzzy-match sessions, projects, branches, actions
- Terminal search: Cmd+F search through terminal output with match navigation
- Token and cost tracking: per-session and per-project from Claude JSONL files
- Welcome screen: onboarding for new users, quick-launch for returning users
- App icon: tropical rainforest canopy at sunrise
EOF
```

- [ ] **Step 2: Verify the awk extraction command works**

This is the exact command CI will use to extract release notes:

```bash
VERSION=$(cat VERSION)
awk "/^## \[${VERSION}\]/{found=1; next} /^## \[/{if(found) exit} found{print}" CHANGELOG.md
```

Expected output: the `### Added` block for 0.1.0 (everything between `## [0.1.0]` and `## [Unreleased]`).

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG.md with v0.1.0 release notes"
```

---

## Task 3: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflows directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create ci.yml**

```bash
cat > .github/workflows/ci.yml << 'EOF'
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  build-test:
    runs-on: macos-15

    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: swift build -c release

      - name: Test
        run: swift test
EOF
```

- [ ] **Step 3: Commit and push to trigger CI**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add CI workflow — build and test on every push and PR"
git push
```

- [ ] **Step 4: Verify CI passes**

Go to github.com/juliensimon/canopy → Actions → CI workflow.
Expected: green checkmark on the latest push.

---

## Task 4: ExportOptions.plist

**Files:**
- Create: `ExportOptions.plist`

This file tells `xcodebuild -exportArchive` to sign with Developer ID (not App Store).

- [ ] **Step 1: Create ExportOptions.plist**

```bash
cat > ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF
```

- [ ] **Step 2: Commit**

```bash
git add ExportOptions.plist
git commit -m "build: add ExportOptions.plist for Developer ID export"
```

---

## Task 5: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`

This is the main pipeline. It runs when you push a tag like `v0.1.0`.

- [ ] **Step 1: Create release.yml**

```bash
cat > .github/workflows/release.yml << 'EOF'
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    runs-on: macos-15

    steps:
      - uses: actions/checkout@v4

      # Gate: tag must match VERSION file
      - name: Validate tag matches VERSION
        run: |
          TAG_VERSION="${GITHUB_REF_NAME#v}"
          FILE_VERSION=$(cat VERSION)
          if [ "$TAG_VERSION" != "$FILE_VERSION" ]; then
            echo "ERROR: tag $GITHUB_REF_NAME does not match VERSION file ($FILE_VERSION)"
            exit 1
          fi
          echo "Version: $FILE_VERSION"

      # Import Developer ID certificate into a temporary keychain
      - name: Import signing certificate
        env:
          APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain"
          CERTIFICATE_PATH="$RUNNER_TEMP/cert.p12"

          echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode -o "$CERTIFICATE_PATH"

          security create-keychain -p "" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "" "$KEYCHAIN_PATH"
          security import "$CERTIFICATE_PATH" \
            -P "$APPLE_CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN_PATH"
          security list-keychains -d user -s "$KEYCHAIN_PATH"

      # Run tests before building the release artifact
      - name: Run tests
        run: swift test

      # Build and archive using xcodebuild (handles icons, assets, entitlements)
      - name: Build archive
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          VERSION=$(cat VERSION)
          xcodebuild archive \
            -project Canopy.xcodeproj \
            -scheme Canopy \
            -configuration Release \
            -archivePath "build/Canopy.xcarchive" \
            MARKETING_VERSION="$VERSION" \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

      # Export signed .app from the archive
      - name: Export .app
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          # Inject team ID into ExportOptions.plist
          sed "s|</dict>|<key>teamID</key><string>${APPLE_TEAM_ID}</string></dict>|" \
            ExportOptions.plist > /tmp/ExportOptions.plist
          xcodebuild -exportArchive \
            -archivePath "build/Canopy.xcarchive" \
            -exportOptionsPlist /tmp/ExportOptions.plist \
            -exportPath "build/export"

      # Verify signature before spending time on notarization
      - name: Verify signature
        run: |
          codesign --verify --deep --strict "build/export/Canopy.app"
          spctl --assess --type execute "build/export/Canopy.app"
          echo "Signature OK"

      # Create a professional DMG with background and Applications shortcut
      - name: Install create-dmg
        run: brew install create-dmg

      - name: Create DMG
        run: |
          VERSION=$(cat VERSION)
          create-dmg \
            --volname "Canopy" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "Canopy.app" 175 190 \
            --hide-extension "Canopy.app" \
            --app-drop-link 425 190 \
            "build/Canopy-${VERSION}.dmg" \
            "build/export/"

      # Sign the DMG itself (required for notarization)
      - name: Sign DMG
        run: |
          VERSION=$(cat VERSION)
          codesign --sign "Developer ID Application" "build/Canopy-${VERSION}.dmg"

      # Submit to Apple for notarization — blocks until Apple responds (2–10 min)
      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          VERSION=$(cat VERSION)
          xcrun notarytool submit "build/Canopy-${VERSION}.dmg" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

      # Attach the notarization ticket to the DMG so it passes Gatekeeper offline
      - name: Staple notarization ticket
        run: |
          VERSION=$(cat VERSION)
          xcrun stapler staple "build/Canopy-${VERSION}.dmg"

      # Upload notarized DMG as artifact — recovery point if later steps fail
      - name: Upload notarized DMG as artifact
        uses: actions/upload-artifact@v4
        with:
          name: Canopy-notarized
          path: build/Canopy-*.dmg
          retention-days: 30

      # Extract release notes from CHANGELOG.md for this version
      - name: Extract release notes
        run: |
          VERSION=$(cat VERSION)
          awk "/^## \[${VERSION}\]/{found=1; next} /^## \[/{if(found) exit} found{print}" \
            CHANGELOG.md > RELEASE_NOTES.md
          echo "--- Release notes ---"
          cat RELEASE_NOTES.md

      # Create the GitHub Release and attach the DMG
      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          VERSION=$(cat VERSION)
          gh release create "v${VERSION}" \
            --title "Canopy v${VERSION}" \
            --notes-file RELEASE_NOTES.md \
            "build/Canopy-${VERSION}.dmg"
EOF
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow — build, sign, notarize, publish on tag push"
```

---

## Task 6: Homebrew tap repo

This is a separate GitHub repository. Create it before wiring the automation.

- [ ] **Step 1: Create the tap repo on GitHub**

```bash
gh repo create juliensimon/homebrew-canopy --public --description "Homebrew tap for Canopy"
```

- [ ] **Step 2: Clone it and create the cask formula**

```bash
cd /tmp
git clone https://github.com/juliensimon/homebrew-canopy.git
cd homebrew-canopy
mkdir -p Casks

cat > Casks/canopy.rb << 'EOF'
cask "canopy" do
  version "0.1.0"
  sha256 :no_check  # placeholder — replaced by homebrew.yml on each release

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
EOF

cat > README.md << 'EOF'
# homebrew-canopy

Homebrew tap for [Canopy](https://github.com/juliensimon/canopy) — parallel Claude Code sessions with git worktrees.

## Install

```bash
brew install --cask juliensimon/canopy/canopy
```

## Update

```bash
brew upgrade --cask canopy
```
EOF

git add .
git commit -m "feat: initial Homebrew cask for Canopy"
git push
cd -
```

- [ ] **Step 3: Verify the tap is accessible**

```bash
brew tap juliensimon/canopy
brew info --cask juliensimon/canopy/canopy
```

Expected: shows Canopy cask info without errors.

```bash
brew untap juliensimon/canopy  # clean up
```

---

## Task 7: Homebrew update workflow

**Files:**
- Create: `.github/workflows/homebrew.yml`

Fires when a GitHub Release is published. Downloads the DMG, computes SHA256, opens a PR on the tap repo with the updated formula.

- [ ] **Step 1: Create homebrew.yml**

```bash
cat > .github/workflows/homebrew.yml << 'EOF'
name: Update Homebrew Tap

on:
  release:
    types: [published]

jobs:
  update-tap:
    runs-on: ubuntu-latest

    steps:
      - name: Compute version and DMG URL
        id: info
        run: |
          TAG="${{ github.event.release.tag_name }}"
          VERSION="${TAG#v}"
          DMG_URL="https://github.com/${{ github.repository }}/releases/download/${TAG}/Canopy-${VERSION}.dmg"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "dmg_url=$DMG_URL" >> "$GITHUB_OUTPUT"

      - name: Download DMG and compute SHA256
        id: sha
        run: |
          curl -L -o canopy.dmg "${{ steps.info.outputs.dmg_url }}"
          SHA256=$(sha256sum canopy.dmg | awk '{print $1}')
          echo "sha256=$SHA256" >> "$GITHUB_OUTPUT"

      - name: Checkout tap repo
        uses: actions/checkout@v4
        with:
          repository: juliensimon/homebrew-canopy
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          path: homebrew-canopy

      - name: Update cask formula
        working-directory: homebrew-canopy
        run: |
          VERSION="${{ steps.info.outputs.version }}"
          SHA256="${{ steps.sha.outputs.sha256 }}"
          sed -i "s/version \".*\"/version \"${VERSION}\"/" Casks/canopy.rb
          sed -i "s/sha256 .*/sha256 \"${SHA256}\"/" Casks/canopy.rb

      - name: Open PR on tap repo
        working-directory: homebrew-canopy
        env:
          GH_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        run: |
          VERSION="${{ steps.info.outputs.version }}"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git checkout -b "release/v${VERSION}"
          git add Casks/canopy.rb
          git commit -m "chore: bump Canopy to v${VERSION}"
          git push origin "release/v${VERSION}"
          gh pr create \
            --repo juliensimon/homebrew-canopy \
            --title "chore: bump Canopy to v${VERSION}" \
            --body "Automated update from canopy release v${VERSION}. Review and merge to make it available via \`brew upgrade\`." \
            --base main \
            --head "release/v${VERSION}"
EOF
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/homebrew.yml
git commit -m "ci: add Homebrew tap update workflow — opens PR on tap repo when release is published"
git push
```

---

## Task 8: First release — end-to-end smoke test

Do this only after completing pre-flight P1–P6.

- [ ] **Step 1: Confirm VERSION and CHANGELOG are in sync**

```bash
cat VERSION   # should print 0.1.0
grep "## \[0.1.0\]" CHANGELOG.md  # should print the header line
```

- [ ] **Step 2: Tag and push**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 3: Watch the release workflow**

Go to github.com/juliensimon/canopy → Actions → Release.

Watch each step. Expected timeline:
- Validate tag: < 5 seconds
- Import certificate: < 10 seconds
- Tests: ~1–2 minutes
- xcodebuild archive: ~2–3 minutes
- Notarize: 2–10 minutes (this is Apple's servers, not yours)
- Create GitHub Release: < 10 seconds

If any step fails, check the step logs. The most common issues:
- Certificate import: wrong base64 encoding or wrong password secret
- xcodebuild: scheme name — verify with `xcodebuild -list -project Canopy.xcodeproj`
- Notarize: wrong APPLE_ID, expired app-specific password, or wrong TEAM_ID

- [ ] **Step 4: Verify the release**

```bash
# Check the release exists
gh release view v0.1.0

# Download and verify the DMG
gh release download v0.1.0 --pattern "*.dmg" --dir /tmp/canopy-test
spctl --assess --type execute /tmp/canopy-test/Canopy-0.1.0.dmg
# Expected: accepted (source=Notarized Developer ID)
```

- [ ] **Step 5: Verify Homebrew workflow opened a PR**

Go to github.com/juliensimon/homebrew-canopy → Pull Requests.
Expected: a PR titled "chore: bump Canopy to v0.1.0" with updated version and sha256.

Review the diff, then merge it.

- [ ] **Step 6: Verify Homebrew install works**

```bash
brew tap juliensimon/canopy
brew install --cask juliensimon/canopy/canopy
open /Applications/Canopy.app
```

Expected: Canopy opens without any Gatekeeper warning.

---

## Rollback Plan

If a critical bug ships after release:

1. **Pull the download:** Go to github.com/juliensimon/canopy → Releases → Edit release → Convert to draft. Stops new downloads.
2. **Block Homebrew:** Close or revert the Homebrew tap PR. If already merged, push a revert commit to the tap.
3. **Ship hotfix:** Fix the bug, bump `VERSION` to `0.1.1`, update `CHANGELOG.md`, commit, push tag `v0.1.1`. Pipeline runs automatically.
4. **Re-publish:** Convert the v0.1.1 release from draft to published once you're satisfied.

---

## What's Not in This Plan (Plan B)

Sparkle in-app update notifications are intentionally excluded. They require adding the Sparkle Swift Package, wiring `SPUStandardUpdaterController` in the app, generating an EdDSA key pair, and extending `release.yml` to sign and generate `appcast.xml`. This is clean work for v0.2.0 after v0.1.0 ships.
