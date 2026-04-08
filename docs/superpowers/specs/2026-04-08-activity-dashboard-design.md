# Activity Dashboard — Design Spec

## Overview

A global activity dashboard showing aggregated Claude Code token usage over time, displayed as a GitHub-style contribution heatmap with summary statistics. Accessed via a dedicated "Activity" sidebar item.

## Data Source

Scan all JSONL files in `~/.claude/projects/*/*.jsonl`. These are Claude Code session transcripts containing assistant message entries with token usage data.

From each `assistant` message entry, extract:
- `message.usage.input_tokens`
- `message.usage.cache_creation_input_tokens`
- `message.usage.cache_read_input_tokens`
- `message.usage.output_tokens`
- `message.model`
- `timestamp` (ISO 8601)

Input tokens = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

Session count is derived from the number of distinct JSONL files that contain at least one assistant entry.

## Caching

Cache file: `~/.config/canopy/activity-cache.json`

### Cache Schema

```json
{
  "version": 1,
  "lastScanTimestamp": "2026-04-08T10:00:00Z",
  "scannedFiles": {
    "/path/to/session.jsonl": {
      "lastModified": "2026-04-07T15:30:00Z",
      "byteSize": 1048576
    }
  },
  "dailyBuckets": {
    "2026-04-07": {
      "inputTokens": 250000,
      "outputTokens": 80000,
      "sessionCount": 3,
      "models": { "claude-opus-4-6": 200000, "claude-sonnet-4-6": 130000 }
    }
  }
}
```

### Cache Behavior

- **First load**: Full scan of all JSONL files. Parse every line, bucket by date, write cache.
- **Subsequent loads**: Compare each JSONL file's modification time and byte size against `scannedFiles`. Only re-parse files that changed or are new. Merge results into existing `dailyBuckets`.
- **Deleted files**: Files in `scannedFiles` that no longer exist on disk are ignored (their historical data remains in `dailyBuckets` — we can't subtract individual file contributions without a full rescan).
- **Cache invalidation**: If `version` doesn't match the expected version, discard and rescan.

### Performance

Scanning runs on a background thread (`Task.detached`). The view shows a spinner during initial load. For incremental updates, the view renders cached data immediately and updates when the scan completes.

## Navigation

- **Sidebar item**: "Activity" entry at the top of the sidebar, above the projects list. Uses a chart/graph SF Symbol icon.
- **Keyboard shortcut**: Cmd+Shift+A.
- Clicking "Activity" sets `activeSessionId = nil` and `selectedProjectId = nil`, and sets a new `showActivity` flag on `AppState`.
- The main content area renders `ActivityView` when `showActivity` is true, instead of a terminal or project detail.

## Layout

Single screen, no scrolling. Two sections stacked vertically:

### 1. Stats Cards Row

Five compact cards in a horizontal row:

| Card | Title | Value | Sub-line |
|------|-------|-------|----------|
| All-Time Tokens | `ALL-TIME TOKENS` | Total tokens (purple accent) | `In: X · Out: Y` |
| Period Tokens | `LAST 12 WEEKS` (varies by granularity) | Total for period | `In: X · Out: Y` |
| Sessions | `SESSIONS` | Count for period | Period label |
| Busiest Day | `BUSIEST DAY` | Peak day token count | Date of peak |
| Models | `MODELS` | Top model + % | Other models + % |

The "All-Time Tokens" card always shows lifetime totals regardless of granularity. The other four cards reflect the selected time range.

### 2. Heatmap (Hero Element)

GitHub-style contribution grid filling the remaining vertical space. Squares stretch to fill available width.

**Components:**
- Month labels along the top
- Day-of-week labels on the left (Mon, Wed, Fri, Sun)
- Less/More legend in the top-right corner
- Squares colored on a 4-level scale using the app's purple palette

**Color scale** (total tokens per bucket):
- Level 0: `#1e1e3a` (no/minimal activity)
- Level 1: `#2d1b69` (low)
- Level 2: `#5b21b6` (medium)
- Level 3: `#7c3aed` (high)

Levels are computed relative to the maximum bucket value in the displayed range (quantile-based: 0%, 25%, 50%, 75%+).

### Granularity Picker

Segmented control in the title bar: **Day | Week | Month**

| Granularity | Time Range | Grid Shape | Bucket |
|-------------|-----------|------------|--------|
| Day | Last 7 days | 24 rows (hours) × 7 columns (days) | Hour |
| Week | Last 12 weeks | 7 rows (days) × 12 columns (weeks) | Day |
| Month | Last 12 months | ~5 rows (weeks) × 12 columns (months) | Week |

The "Day" granularity requires sub-day bucketing from timestamps. The cache stores daily buckets; hourly bucketing is computed on-the-fly from the raw JSONL data of the last 7 days (small enough to scan live).

## Architecture

### New Files

- `Canopy/Services/ActivityDataService.swift` — scans JSONL files, manages cache, produces `ActivityData` model
- `Canopy/Models/ActivityData.swift` — data model: `DailyBucket`, `ActivitySummary`, `ActivityData`
- `Canopy/Views/ActivityView.swift` — main dashboard view (stats cards + heatmap)
- `Canopy/Views/ActivityHeatmap.swift` — the heatmap grid component

### Modified Files

- `Canopy/App/AppState.swift` — add `showActivity: Bool`, navigation logic
- `Canopy/Views/Sidebar.swift` — add "Activity" entry at top
- `Canopy/Views/MainWindow.swift` — route to `ActivityView` when `showActivity` is true

### Data Flow

1. User clicks "Activity" in sidebar (or Cmd+Shift+A)
2. `AppState.showActivity = true`, clears session/project selection
3. `MainWindow` renders `ActivityView`
4. `ActivityView.task` calls `ActivityDataService.loadData()` on a background thread
5. Service reads cache, scans new/modified JSONL files, merges, saves cache
6. Returns `ActivityData` to the view
7. View renders stats cards from `ActivityData.summary` and heatmap from `ActivityData.buckets`

## Token Formatting

Use the existing `TokenUsage.formatCount` approach (NumberFormatter with `.decimal` style). For large numbers, use abbreviated format: `142.3M`, `24.7M`, `1.8M`, `312K`, `4.2K`.

## What's NOT Included

- No per-project breakdown — purely aggregated
- No cost estimation
- No real-time polling — data loads when the view opens
- No tooltip on hover (can be added later)
- No export functionality
