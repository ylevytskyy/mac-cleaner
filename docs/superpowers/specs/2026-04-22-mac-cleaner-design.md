# mac-cleaner — Design

**Date:** 2026-04-22
**Target:** macOS (Darwin 25+, zsh default shell)
**Location:** `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

## Purpose

A personal, interactive macOS disk-space reclaimer focused on developer caches. Walks the user through each cleanup category, shows the current size, and asks y/N before touching anything. Also audits outdated global npm packages and core tool versions (node/npm/yarn), prompting to update.

## Non-goals

- Not a general-purpose system cleaner (no `~/Library/Caches/*` sweep, no Spotlight/font/keychain repair).
- Not a Docker pruner, node_modules sweeper, or cross-machine sync tool.
- Not a scheduled job — runs on demand only.

## User interaction model

Interactive, category-by-category. Each category:

```
── npm cache ──────────────────────
  Location: ~/.npm
  Size:     1.4 GB
  Clean this? [y/N] _
  → cleaned, freed 1.4 GB
```

Flags:

- `--dry-run` — print every destructive command without executing; still prompts so you see the flow.
- `--yes` / `-y` — skip prompts (for repeat runs after you trust it). Xcode Archives still double-prompts.
- `--help` — usage.

No other flags in v1.

## Categories (in run order)

### Package manager caches (safe)

| Category | Path / command | Notes |
|---|---|---|
| npm cache | `npm cache clean --force` (path: `~/.npm`) | Size reported from `~/.npm` |
| yarn classic cache | `yarn cache clean` | Only if `yarn` v1 detected |
| yarn berry cache | `yarn cache clean --all` | If `yarn` v2+ |
| pnpm store | `pnpm store prune` | If `pnpm` present |
| Homebrew | `brew cleanup -s && brew autoremove` | Old versions + downloads |

### Dev-tool caches (bigger wins)

| Category | Path | Notes |
|---|---|---|
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | Safe; regenerated on next build |
| Xcode Archives | `~/Library/Developer/Xcode/Archives/*` | **Double-prompted.** These are App Store submission archives. |
| iOS Simulator unavailable | `xcrun simctl delete unavailable` | Removes sim devices for uninstalled runtimes |
| CocoaPods cache | `~/Library/Caches/CocoaPods` | Tool-specific subdir only |
| Gradle cache | `~/.gradle/caches` | Regenerated on next build |
| Android build cache | `~/.android/build-cache` | Regenerated |
| Expo / Metro | `~/.expo`, `/tmp/metro-*`, `/tmp/haste-map-*`, `/tmp/react-*` | Safe, ephemeral |
| pip cache | `pip cache purge` | Only if `pip` present |
| Trash | `~/.Trash/*` | Safe |

### Version audit (report + optional update)

| Check | How |
|---|---|
| Outdated global npm packages | `npm outdated -g --parseable --depth=0` |
| node version vs latest LTS | Compare `node -v` to `https://nodejs.org/dist/index.json` latest LTS |
| npm version vs latest | Compare `npm -v` to `npm view npm version` |
| yarn version vs latest (v1) | Compare `yarn -v` to `npm view yarn version` |
| pnpm version vs latest | Compare `pnpm -v` to `npm view pnpm version` |

For each outdated item the script prints the current vs latest and prompts y/N to run the update. Node updates are **report-only** (no automatic replacement — user decides if they use nvm, brew, installer, etc.). npm/yarn/pnpm/global packages can be updated in place via `npm i -g <pkg>@latest`.

## Script structure

Single zsh file, ~300–400 lines, sections in this order:

1. **Shebang + strict mode**
   `#!/usr/bin/env zsh` + `set -euo pipefail` + `setopt nullglob` so unmatched globs don't error.
2. **Globals** — log path, colors, flags parsed from `$@`, totals accumulator.
3. **Helpers**
   - `log(msg)` — append to `~/.mac-cleaner.log` with ISO timestamp, also stdout.
   - `human_size(bytes)` — pretty-print B/KB/MB/GB.
   - `du_safe(path)` — `du -sk` returning 0 if path missing, output in bytes.
   - `confirm(prompt)` — y/N, returns 0/1, auto-yes under `--yes`.
   - `run_cmd(desc, cmd...)` — under `--dry-run` just prints, otherwise executes and captures status.
   - `have(cmd)` — `command -v` wrapper, returns 0/1.
4. **Category functions** — one per row above. Each:
   - Prints a header line.
   - Computes size before.
   - Prompts (skip in `--yes`).
   - Runs cleanup.
   - Computes freed bytes, adds to total, logs.
5. **Version audit functions** — `check_outdated_globals`, `check_tool_versions`.
6. **Main** — banner, run categories in order, print summary:
   ```
   ── Summary ────────────────────────
     Freed 4.7 GB across 8 categories
     Log: ~/.mac-cleaner.log
   ```

## Safety guarantees

- `set -euo pipefail` — fail fast on any command error, undefined var, or failed pipe stage.
- **No dynamic path construction.** Every deletion target is either (a) a hardcoded absolute path, (b) the output of a known tool command (`brew cleanup`, `npm cache clean`). No `rm -rf "$foo/$bar"` where either var is user-influenced.
- **Xcode Archives** — double-prompted: standard y/N, then a second explicit "⚠ These are your App Store submissions. Type 'DELETE' to confirm:" requiring the literal string `DELETE` (case-sensitive). Anything else aborts this category.
- **Currently-running apps** — not a concern here because we dropped the generic `~/Library/Caches` sweep. Tool caches like CocoaPods/Gradle are regenerated; if a build is in flight the worst case is that build restarts.
- **Dry-run** — `run_cmd` prints the command prefixed with `[dry-run]` and skips execution. Size-before is still computed so user sees the potential savings.
- **Tool detection** — if a tool is missing, category is silently skipped with a one-line note. Prevents `command not found` failures.

## Log format

`~/.mac-cleaner.log`, append-only, one line per event:

```
2026-04-22T14:32:10-0700  START  run=abc123  dry_run=false  yes=false
2026-04-22T14:32:11-0700  SKIP   category=pnpm            reason=tool_not_installed
2026-04-22T14:32:14-0700  CLEAN  category=npm_cache       freed_bytes=1503238553
2026-04-22T14:32:14-0700  DECLINE category=xcode_archives  size_bytes=8321000000
2026-04-22T14:32:45-0700  END    run=abc123  freed_total=5021938100  categories_cleaned=7
```

`run` is a short random id so multiple runs in the log can be separated.

## Error handling

- A failing cleanup command (e.g., `brew cleanup` errors because a formula is pinned) logs `ERROR category=<x> rc=<n>` and continues to the next category. It does not abort the whole run — one bad category shouldn't block the rest.
- Strict mode (`set -e`) is temporarily relaxed around `run_cmd` so we can capture the exit code and decide; it stays strict for the script's own logic.

## Testing approach

Since this is a personal utility and destructive-by-design, testing is pragmatic:

1. **Dry-run smoke test** — `./mac-cleaner.sh --dry-run` on the real machine, verify every category prints a plausible command and size. No writes.
2. **Help/flag parsing** — `--help`, `-y`, `--dry-run --yes` combinations.
3. **Missing-tool handling** — manually rename `yarn` on PATH (or test on a machine without it) to confirm the skip path.
4. **Empty category** — if a cache is already empty, script should print `0 B` and skip the prompt (auto-skip when size is 0).
5. **Real run** — the user runs it interactively on their actual machine. This is the acceptance test.

No unit tests. The script is small, the commands are well-known, and the cost of a test harness would exceed the value for a personal tool.

## Out of scope for v1 (documented for later)

- Docker prune integration.
- `node_modules` sweeper across a projects root.
- Scheduled runs / launchd plist.
- JSON output mode.
- Per-category size threshold (only prompt if > N MB).
