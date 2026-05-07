# App Cache Cleanup — Design

Status: approved 2026-05-07
Supersedes: nothing — extends `2026-04-22-mac-cleaner-design.md`

## Goal

Add three new interactive categories to `mac-cleaner.sh` that reclaim disk space from generic application caches and user temp directories, beyond the developer-tool-specific categories already covered.

## Scope

The script today targets named developer tools (npm, yarn, brew, gradle, expo, xcode, simulators, etc.). It does not touch:

- `~/Library/Caches/*` — the macOS app-cache directory used by every GUI app
- `/tmp` and `/private/var/folders/.../T/` — system + user temp dirs
- Generic `~/.cache`-style dotfolder caches that don't belong to a specific tool we wrap

This spec adds three new categories — A, B, C below — to cover those, with a moderate aggression posture (most app caches + temp; not "everything cache-shaped").

## Out of scope

- Running-app detection (no `lsof` check before deletion). Apps that lose login state when their cache is wiped are explicitly denylisted instead.
- `~/Library/Logs` and `~/Library/Application Support` (not caches).
- `/private/var/folders/.../C/` (system-owned cache trees).
- Anything not owned by the current user.

## Reconciliation with existing categories

Several targets in the new categories overlap with categories already wrapped by the script. To avoid double-deletion (and to keep each cache governed by exactly one prompt), the new categories MUST exclude paths owned by an existing category:

- `~/Library/Caches/Yarn` — owned by `category_yarn_cache` → **must be in category A's denylist**.
- `~/Library/Caches/CocoaPods` — owned by `category_cocoapods` → **must be in category A's denylist**.
- `~/Library/Caches/Homebrew` — covered by `brew cleanup` in `category_brew` (Homebrew manages its own cache invalidation) → **must be in category A's denylist**.
- `~/.expo/cache`, `/tmp/metro-*`, `/tmp/haste-map-*`, `/tmp/react-*` — owned by `category_expo_metro` (deletes regardless of age) → category B's `/tmp` sweep is mtime-gated at 7 days, so it will *not* race expo_metro on fresh files; older orphans are fair game. No exclusion needed but discovery agent must confirm.
- `~/.gradle/caches` — owned by `category_gradle` (which also stops the daemon) → **must NOT appear in category C**.
- `~/.android/build-cache` — owned by `category_android_build` → **must NOT appear in category C**.
- `~/.npm`, pip's resolved cache dir — owned by `category_npm_cache` and `category_pip_cache` → **must NOT appear in category C**.
- `~/.Trash` — owned by `category_trash` → not in scope for any of the new three.

The discovery agent's first task is to enumerate every path the existing categories already touch, then ensure its appendices A and B do not collide.

## Categories

### A. macOS app caches — `~/Library/Caches`

**Sizing:** Sum of `du -sk` across the *allowed* immediate children (post-denylist filter).

**Cleanup:** For each immediate child of `~/Library/Caches`:

1. If the child name appears in the **denylist** → skip silently.
2. If the child name matches a **denylist prefix** (e.g. `com.apple.AMP*`, `com.apple.assistantd*`) → skip.
3. Else → `rm -rf` the entire child directory.

The denylist is split into four buckets and lives as a hardcoded zsh array in the script. The discovery agent populates the concrete entries (see Appendix A); the buckets themselves are part of this design:

- **Apple system & sync state** — anything Apple uses for iCloud sync, search indexes, Safari/Mail/Messages/Calendar/Photos state.
- **Container scaffolding** — `Containers`, `Group Containers`, `GroupContainers`, `KSCrashReports`, etc.
- **Apps with login/session state inside the cache dir** — Spotify, Slack, Discord, Teams, Zoom, Telegram, WhatsApp, 1Password, Claude Desktop, Firefox profiles.
- **Caches that hold user content** — Apple Music/TV library indexes, etc.

Any subdir not matched by the denylist is allowed by default.

### B. User temp & system temp

Two hardcoded parent dirs:

- `/tmp`
- `${TMPDIR:-/private/var/folders/$(id -un)/.../T}` — the per-user temp tree under `/private/var/folders`. Resolved once at script start via the `TMPDIR` env var (which macOS guarantees points at the right per-user dir).

**Cleanup rules** (apply to both parents):

- Iterate immediate children of the parent dir.
- Delete only entries owned by the current user (`-user $(id -un)`).
- Delete only entries with mtime ≥ 7 days old (`-mtime +7`).
- Never remove the parent dir itself.

Implemented via a single `find <parent> -mindepth 1 -maxdepth 1 -user <user> -mtime +7 -exec rm -rf {} +` per parent. `find` itself acts as the filter so we never construct child paths in shell.

### C. Misc dev caches in $HOME

Hardcoded list of known-safe cache subpaths under `$HOME`. Each entry is a *full subpath*, not a glob. Initial set (discovery agent will refine in Appendix B):

- `~/.cache` (XDG-style; many tools dump here)
- `~/.cocoapods/repos.cache` (the *cache subdir only*, not the repos themselves)
- `~/.dart-tool`
- `~/.bun/install/cache`
- `~/.deno/dep_analysis_cache_v2`, `~/.deno/gen`
- `~/.cargo/registry/cache` (NOT `~/.cargo/registry/src` — that contains source for offline builds)
- `~/.electron`, `~/.electron-gyp`

Explicitly excluded (handled elsewhere or not pure cache): `~/.npm`, `~/.gradle/caches`, `~/.android/build-cache`, `~/.pnpm-store`, pip's cache dir, anything in the "Reconciliation" section above.

Cleanup: `rm -rf <subpath>` for each. Each subpath is hardcoded; no globbing of `$HOME`.

## Integration with existing patterns

All three new categories are added as separate top-level functions:

- `category_app_caches`     → calls `run_category "macOS app caches" ...` with custom cleanup fn
- `category_temp`           → custom wrapper (sums two parents) on top of `run_category`
- `category_dev_dotcaches`  → custom wrapper (sums many subpaths) on top of `run_category`

Each is added to `main()` *after* the existing developer-tool categories, *before* the final summary.

`--dry-run`, `--yes`, and the existing logging contract (`START`, `SKIP`, `CLEAN`, `DECLINE`, `ERROR`, `END` with `run=<id>`) all carry over unchanged.

## Safety rule exception (load-bearing)

The current spec at `2026-04-22-mac-cleaner-design.md` says:

> No dynamic path construction for `rm -rf`. Every deletion target is either a hardcoded absolute path or the output of a trusted tool command.

Category A breaks this minimally and explicitly. The exception terms:

- **Parent path is hardcoded** (`$HOME/Library/Caches`).
- **Iteration is over immediate children only.** No `**` recursion of names. No user-supplied paths. No env-derived paths beyond `$HOME`.
- **Every candidate is checked against a hardcoded denylist** (literal names + a small set of prefix patterns) before deletion.
- **The deletion target is the matched child's full absolute path**, never a string-concatenation result like `"$parent/$user_input"`.

Categories B and C remain inside the original safety rule:

- B uses `find` with hardcoded parents; `find` does the filtering and the path construction.
- C uses a hardcoded list of full subpaths; no globbing.

`CLAUDE.md` will be updated to record this exception. Future categories cannot widen it.

## Logging additions

Same event vocabulary as today; new key/values for transparency:

- Category A — when a child is skipped by denylist: `SKIP category=app_caches reason=denylist entry=com.spotify.client`
- Category B — `CLEAN category=temp parent=/tmp removed=42 freed=...`
- Category C — `SKIP category=dev_dotcaches reason=missing entry=~/.cargo/registry/cache`

## Verification

Same as the rest of the script: there are no unit tests by design. Verification is:

1. `zsh -n mac-cleaner.sh` — syntax check.
2. `./mac-cleaner.sh --dry-run` — confirm:
   - Each new category prints its size header.
   - Category A prints the exact `rm -rf` command for each *allowed* child and *no command at all* for any denylisted child (denylisted children should generate `SKIP` log lines visible in `~/.mac-cleaner.log`).
   - Category B prints the exact `find ... -exec rm -rf {} +` invocation for each parent.
   - Category C prints `rm -rf` for each existing subpath and "already empty, skipping" for missing ones.
3. Read `~/.mac-cleaner.log` and confirm event lines for the dry-run carry the right `category=` and `reason=` keys.

## Appendices (filled in by discovery agent)

### Appendix A — Library/Caches denylist

To be populated by the discovery Sonnet agent. Format: each entry on its own line, with a one-line rationale.

```
com.apple.* — Apple system daemons; mixed cache + sync state
CloudKit — iCloud sync state
com.spotify.client — clearing logs out the user; auth tokens stored here
…
```

The agent must also flag any *prefix patterns* (e.g. `com.apple.AMP*`) that need wildcard handling.

### Appendix B — Dev dotfolder cache subpaths

To be populated by the discovery Sonnet agent. Format: full subpath under `$HOME`, with a one-line rationale plus a "currently exists on this machine: yes/no" flag.

### Appendix C — Temp staleness threshold

The 7-day mtime threshold is a default. Discovery agent reports actual age distribution of `/tmp` and the user's `$TMPDIR` and recommends a threshold (default stays 7 unless evidence says otherwise).
