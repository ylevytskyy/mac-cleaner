# System Data Categories — Design

Status: draft 2026-05-10
Supersedes: nothing — extends `2026-04-22-mac-cleaner-design.md` and `2026-05-07-app-cache-cleanup-design.md`

## Goal

Add new interactive categories to `mac-cleaner.sh` that reclaim disk space from the buckets macOS reports as **"System Data"** (System Settings → General → Storage). On Sequoia 15.x and Tahoe 16.x in May 2026, this bucket routinely grows to 50–150 GB on dev machines and is invisible to the existing dev-cache categories.

Research informing this spec lives in 10 parallel agent reports summarized in `docs/superpowers/discovery/2026-05-10-system-data-research.md` (separate file). Each new category below is justified by one of those reports.

## Scope

Two tiers of additions, all gated by the existing safety rules in `2026-04-22-mac-cleaner-design.md`.

**Tier 1 — `run_category`-shaped (13 categories).** Each fits the `run_category <name> <desc> <size_path> <cleanup_fn>` pattern with a single hardcoded path, a known reclaim command (raw `rm -rf` of a hardcoded subtree, or a tool's `--clean`-style command), and a regenerable target.

**Tier 2 — bespoke wrappers (6 categories).** Each needs custom shape that `run_category` cannot model: multi-path sizing, no pre-flight size, per-instance iteration, or running-process choreography. Each follows the precedent set by `category_xcode_archives`, `category_npm_yarn_all_nvm`, and `cleanup_gradle`.

## Out of scope

The following were researched and **explicitly rejected**. Documented here so future contributors don't re-litigate.

- **iCloud Drive / CloudKit / `bird` / FileProvider caches.** Wrong domain (user documents, not dev cache). The only supported tool, `brctl evict`, requires user-document path arguments — violates the no-dynamic-path rule. Risk: permanent loss of unsynced files. README will point users at System Settings → Apple Account → iCloud → Optimize Mac Storage.
- **Photos library internals** (`derivatives`, `private`, `Caches` inside `~/Pictures/Photos Library.photoslibrary`). Undocumented internals adjacent to originals; Apple's Option-Cmd "Repair Library" is the supported alternative. README mention only.
- **Messages attachments + `chat.db`.** Risk of irreversible loss if iCloud Messages is off; scriptable detection of that setting is unreliable across macOS versions.
- **iOS device backups** (`~/Library/Application Support/MobileSync/Backup`). Irreplaceable user data; safer to delegate to Finder → Manage Backups. README mention only.
- **Unified log** (`/private/var/db/diagnostics`). Requires sudo; `logd` self-attrites to ~520 MB anyway. May revisit later as opt-in `--unified-log`.
- **`/private/var/folders/*/{T,C}`.** Dynamic path construction violates the safety rule; macOS self-cleans on reboot.
- **`/Library/Updates`, `/Library/Apple/Application Support`, `softwareupdate --clear-catalog`.** Sudo + SIP-adjacent.
- **`~/.m2/repository`.** Not a true cache (locally-installed SNAPSHOTs may be unrecoverable from any remote).
- **Buck2.** No global cache path; per-workspace only.
- **Per-user clang ModuleCache under `DARWIN_USER_CACHE_DIR`.** Dynamic path; covered passively when DerivedData is cleaned.
- **FaceTime Live Photos.** Stored inside the Photos library; nothing to sweep separately.
- **Xcode `*DeviceSupport`** (`iOS DeviceSupport`, `watchOS DeviceSupport`, etc.). User explicitly opted out — needs them for old iPhones/Watches.
- **Stale Xcode simulator runtimes** (`xcrun simctl runtime delete --notUsedSinceDays N`). User explicitly opted out — needs old simulators.

## Reconciliation with existing categories

Cross-referenced against every category in `mac-cleaner.sh` (npm, yarn, pnpm, brew, nvm/brew Node sweeps, Xcode DerivedData/Archives, simctl unavailable, CocoaPods, Gradle, Android build cache, Expo/Metro, pip, Trash, app_caches, temp, dev_dotcaches).

- **`~/Library/Caches/com.apple.Music`** (Tier 1 #11) — `category_app_caches`'s denylist already excludes the broad `com.apple.*` prefix. We carve out this single literal subdir as an explicit category so it gets sized, prompted, and cleaned independently. The `app_caches` denylist must continue to skip `com.apple.Music` to avoid double-deletion.
- **`~/Library/Caches/ccache`** (Tier 1 #7) — `app_caches` would otherwise sweep this on its own, but using the `ccache --clear` command is safer (respects user-configured `CCACHE_DIR` override). Add `ccache` to `app_caches` denylist.
- **`~/Library/Caches/composer`** (Tier 1 #11 → wait, #11 is composer per renumber below) — same rationale as ccache; use `composer clear-cache`. Add `composer` to `app_caches` denylist.
- **`~/Library/Caches/org.swift.swiftpm`** (Tier 1 #4) — same; use `swift package purge-cache`. Add `org.swift.swiftpm` to `app_caches` denylist.
- **`~/.cache/clangd`** (Tier 1 #6) — sits under `~/.cache`, which `dev_dotcaches` deletes wholesale. Either drop `~/.cache` from `dev_dotcaches` entirely (preferred — too broad) or add a clangd-specific carve. Decision: **drop `~/.cache` from `dev_dotcaches`**; clangd becomes an explicit category, and other `~/.cache` subdirs are too heterogeneous to sweep blindly.
- **`~/.cargo/registry/cache`** (Tier 1 #8 — already in `dev_dotcaches`) — promote out of `dev_dotcaches` into its own category so it can also clean `~/.cargo/registry/src` (research confirms safe, regen on next build). Remove from `dev_dotcaches`.
- **All other Tier 1/2 paths** — net-new, no overlap.

## Tier 1 categories (run_category-shaped)

Numbering is local to this spec, not the script.

| # | Category fn | Path (hardcoded) | Reclaim command | Notes |
|---|---|---|---|---|
| 1 | `category_coresimulator_caches` | `~/Library/Developer/CoreSimulator/Caches` | `xcrun simctl shutdown all && rm -rf "$path"/*` | Skip if Simulator.app running |
| 2 | `category_xctest_xcpg_devices` | `~/Library/Developer/XCTestDevices` and `~/Library/Developer/XCPGDevices` | `rm -rf "$path"/*` for each | Two siblings sized together |
| 3 | `category_xcode_dt_cache` | `~/Library/Caches/com.apple.dt.Xcode` | `rm -rf "$path"/*` | Skip if Xcode running (`pgrep -x Xcode`) |
| 4 | `category_xcode_device_logs` | `~/Library/Developer/Xcode/iOS Device Logs` | `rm -rf "$path"/*` | Re-collected on next device attach |
| 5 | `category_swiftpm` | `~/Library/Caches/org.swift.swiftpm` | `swift package purge-cache` (fallback `rm -rf`) | `have swift` |
| 6 | `category_clangd_index` | `~/.cache/clangd` | `rm -rf "$path"` | Re-indexed on next open |
| 7 | `category_ccache` | `~/Library/Caches/ccache` | `ccache --clear` | `have ccache` |
| 8 | `category_cargo_registry` | `~/.cargo/registry/cache` and `~/.cargo/registry/src` | `rm -rf` of those two subdirs only | `have cargo`; never touch `~/.cargo/{git,bin}` |
| 9 | `category_go_caches` | `$(go env GOMODCACHE)` and `$(go env GOCACHE)` | `go clean -modcache && go clean -cache` | `have go`. Tool-derived paths but read from a trusted tool — same precedent as `brew cleanup` etc. If `go env` exits non-zero or returns empty for either var, `SKIP reason=tool_error key=<var>` and continue (no fallback to hardcoded defaults — a broken Go install should not become a `rm` target) |
| 10 | `category_composer` | `~/Library/Caches/composer` | `composer clear-cache` | `have composer` |
| 11 | `category_apple_music_stream_cache` | `~/Library/Caches/com.apple.Music` | `rm -rf "$path"/*` | Skip if Music running (`pgrep -x Music`) → `SKIP reason=app_running app=Music`. Safe — does NOT contain downloaded songs (those live in `~/Music/Music/Media`) |
| 12 | `category_mail_downloads` | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | `rm -rf "$path"/*` | Originals stay in `.emlx` files in `~/Library/Mail`; re-extracted on attachment open |
| 13 | `category_diagnostic_reports` | `~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports` | `rm -f "$path"/*` for each | System path requires user to be in `_analyticsusers` group (typical for admin users); group-check via `id -Gn`, log `SKIP reason=insufficient_perms` if not |

**Tool-derived path note (#9 only).** `go env GOMODCACHE` returns either `$HOME/go/pkg/mod` or a `GOMODCACHE`-overridden value. We treat `go env` as a trusted tool command per the existing rule that allows `brew cleanup`'s output as a deletion target. The `go clean -modcache` invocation is preferred so we never have to `rm` ourselves; the `go env` output is used for sizing (`du_safe`), not for deletion.

## Tier 2 categories (bespoke wrappers)

### B1. `category_tm_local_snapshots` — APFS Time Machine local snapshots

**Why bespoke:** no useful pre-flight `du` (snapshots are block-deltas, not files). UX needs a count + age range, not a size header.

**Shape:**
```
have tmutil → SKIP if missing
count = tmutil listlocalsnapshots / | grep -c '^com.apple.TimeMachine'
[ count -eq 0 ] → "no local snapshots", SKIP reason=empty
print "Found N Time Machine local snapshot(s). Removing them deletes the local 24h restore window."
print "(Network/external Time Machine backups are NOT affected.)"
prompt y/N (skipped under --yes)
optional: tmutil stopbackup (no-op if idle)
before = df -k / | awk 'NR==2{print $4}'
run_cmd "thin all local snapshots" tmutil thinlocalsnapshots / 999999999999 4
after = df -k / | awk 'NR==2{print $4}'
print freed = (after - before) KB
```

**No sudo.** No reboot. No DELETE-typed prompt (snapshots are not irreplaceable user data — they regenerate on next backup).

### B2. `category_macos_installers` — stale `Install macOS *.app` stubs

**Why bespoke:** iterates a hardcoded glob and prompts per-installer with the version name. Same exception-shape as `category_app_caches` (hardcoded parent + immediate-children iteration + literal pattern match), narrower because we use a literal prefix/suffix rather than a denylist.

**Shape:**
```
setopt nullglob; installers=(/Applications/Install\ macOS\ *.app)
[ ${#installers} -eq 0 ] → "no stale installers", SKIP reason=empty
for app in "${installers[@]}":
  # paranoid re-check — guard against parameter mishaps
  [[ "$app" == /Applications/Install\ macOS\ *.app ]] || continue
  size = du_safe "$app"
  prompt "Delete <name> (<size>)? [y/N]"
  run_cmd "remove $app" rm -rf "$app"
```

**No sudo.** Each `.app` is 12–15 GB; users routinely have two stuck (e.g. Sequoia + Tahoe).

**Safety exception note:** parent `/Applications` is hardcoded; iteration is immediate-children only matching a literal prefix `Install macOS ` and suffix `.app`; deletion target is the resolved match path with a re-check guard before `rm`. Same constraints that bound the `category_app_caches` exception. Cannot widen further.

### B3. `category_sccache` — Mozilla sccache

**Why bespoke:** no built-in clear command; must stop the daemon first.

**Shape:**
```
have sccache → SKIP
run_cmd "stop sccache server" sccache --stop-server || true   # ok if not running
size = du_safe ~/Library/Caches/Mozilla.sccache
... standard size/prompt ...
run_cmd "remove sccache cache" rm -rf ~/Library/Caches/Mozilla.sccache
```

### B4. `category_bazel` — Bazel disk cache + outputBase

**Why bespoke:** mirrors `cleanup_gradle` (daemon-stop + rm + surface failures). Bazel 8 stores at `/private/var/tmp/_bazel_$USER`; Bazel 9+ at `~/Library/Caches/bazel`. Both literal paths are hardcoded; we try both and skip the missing one.

**Shape:**
```
have bazel → SKIP
run_cmd "shutdown bazel" bazel shutdown || true
for path in /private/var/tmp/_bazel_$USER ~/Library/Caches/bazel:
  [ -d "$path" ] || continue
  size = du_safe "$path"
  ... size/prompt ...
  run_cmd "remove bazel disk cache at $path" rm -rf "$path"
  if rm partially failed (locks held): surface loudly, suggest rerun after closing IDE
```

`$USER` in the Bazel 8 path is a Darwin-system var, equivalent to the existing `$NVM_DIR` and `$HOME` usage — not user-influenced.

### B5. `category_container_vms` — Docker / OrbStack / Colima / Lima / Podman

**Why bespoke:** five sub-tools, each with a different binary, prune command, and disk-image path. **NEVER `rm` a disk image file** — corrupts the VM permanently. Always invoke the tool's CLI.

**Umbrella shape:**
```
for tool in docker orb colima limactl podman:
  have <tool> || continue
  call cleanup_vm_<tool>
```

**Per-tool sub-functions:**

| Tool | Detect | Disk image (sized for header) | Prune | Notes |
|---|---|---|---|---|
| Docker Desktop | `have docker && docker info >/dev/null 2>&1` | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | `docker system prune -a -f` then `docker run --privileged --pid=host docker/desktop-reclaim-space` | Default OMITS `--volumes`; gate behind separate explicit `--include-volumes` flag |
| OrbStack | `have orb` | `~/.orbstack/data/data.img` | `docker builder prune -a -f` | Auto-shrinks sparse file; no helper container needed |
| Colima | `have colima` | `~/.colima/_lima/colima/diffdisk` | `colima prune` then `colima ssh -- sudo fstrim -a` | Restart needed for full reclaim; we skip the restart, log a hint |
| Lima | `have limactl` | `~/.lima/_cache` | `limactl prune` | Only prunes template cache; per-instance diffdisk reclaim skipped (too disruptive) |
| Podman | `have podman` | `~/.local/share/containers/podman/machine/applehv/<machine>-arm64.raw` | `podman system prune -a -f` | Default OMITS `--volumes`; same flag-gate as Docker |

**New flag — `--include-volumes`:** off by default. When on, Docker's and Podman's prune commands gain `--volumes`. Documented separately in `--help` with a "this can delete container data" warning. `--yes` does NOT imply `--include-volumes`.

**Sizing:** `du -h` on the host-visible disk image file (whatever exists). Gracefully report 0 if the image isn't present (tool installed but never run).

### B6. `category_browser_caches` — Safari, Chrome, Arc, Edge, Firefox, Brave

**Why bespoke:** matrix of fixed top-level dirs × variable profile children × hardcoded leaf cache subdirs. `run_category` cannot model this. **Requires a safety-rule amendment** — see "Safety rule exception" below.

**Per-browser hardcoded structure:**

| Browser | Top-level (hardcoded) | Profile iteration | Leaf cache subpaths (hardcoded under each profile) |
|---|---|---|---|
| Safari | `~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari` | n/a (single dir) | `.` (the whole dir) and `Webpage Previews` |
| Chrome | `~/Library/Application Support/Google/Chrome` | `Default`, `Profile <N>` only (skip `System Profile`, `Guest Profile`, `Snapshots`, `Crashpad`) | `Cache/Cache_Data`, `Code Cache`, `GPUCache`, `Service Worker/CacheStorage`, `Service Worker/ScriptCache`, `DawnGraphiteCache`, `DawnWebGPUCache` |
| Arc | `~/Library/Application Support/Arc/User Data` | same allowlist as Chrome | same leaf list as Chrome |
| Edge | `~/Library/Application Support/Microsoft Edge` | same | same |
| Brave | `~/Library/Application Support/BraveSoftware/Brave-Browser` | same | same |
| Firefox | `~/Library/Caches/Firefox/Profiles` | iterate immediate children ending in `.default-release`, `.default`, `.dev-edition-default` (literal suffix allowlist) | `cache2` only |

**Profile iteration safety:** for Chromium browsers, the iteration is `setopt nullglob; for prof in "$top"/Default "$top"/Profile\ *; do ...`. The pattern `Profile *` is a literal prefix glob limited to immediate children; same shape as Tier 2 #B2 (installers).

**Per-browser cleanup:**
```
have open || skip   # macOS guarantee, just defensive
[[ -d "$top" ]] || skip reason=tool_not_installed
pgrep -f "/Applications/<App>.app" >/dev/null && skip reason=browser_running   # CRITICAL — deleting cache mid-run can corrupt disk_cache index
for prof in <iteration>:
  for leaf in <hardcoded leaf list>:
    target="$prof/$leaf"
    [[ -d "$target" ]] || continue
    run_cmd "remove $target" rm -rf "$target"
```

**Sizing:** sum across all (profile × leaf) targets that exist.

**Hard exclusions** (never deleted): `Cookies`, `Login Data`, `History`, `Bookmarks`, `Preferences`, `Local State`, `Network/Cookies`, anything ending in `.db` outside the listed leaves, and any Safari `Databases` / `LocalStorage` / `WebsiteData` directories (those are site storage, not pure cache, and deletion logs users out of PWAs).

## Integration with existing patterns

All Tier 1 categories use `run_category`. All Tier 2 categories use bespoke wrappers that still call `run_cmd` for every destructive invocation (so `--dry-run` works) and emit the standard log events.

Each new category function lives next to its kind in the script (group Xcode-family near the existing Xcode categories, Swift/Rust/Go/PHP near the language-toolchain block, browsers/VMs/snapshots/installers/Music/Mail/diagnostics in a new "system data" block at the end).

**Run order in `main()`** (final):

1. Existing dev-cache categories (unchanged, in current order). Familiar wins first.
2. New Xcode-family additions: `category_coresimulator_caches`, `category_xctest_xcpg_devices`, `category_xcode_dt_cache`, `category_xcode_device_logs`.
3. New language-toolchain additions: `category_swiftpm`, `category_clangd_index`, `category_ccache`, `category_sccache` (Tier 2), `category_cargo_registry`, `category_go_caches`, `category_composer`, `category_bazel` (Tier 2).
4. New container-VM block: `category_container_vms`.
5. New browser block: `category_browser_caches`.
6. New user-app block: `category_apple_music_stream_cache`, `category_mail_downloads`, `category_diagnostic_reports`.
7. New system-state block: `category_tm_local_snapshots`, `category_macos_installers`.

Rationale: dev-cache categories first because users already trust them and the wins are routine. New categories ordered by familiarity — Xcode/language toolchains feel like more dev-cache; VMs and browsers introduce new running-process behavior; user-app and system-state categories (snapshots, installers) require the most novel judgment, so they come last when the user is already in the rhythm of accepting/declining prompts.

`--dry-run`, `--yes`, the `run=<id>` log key, and the `START`/`SKIP`/`CLEAN`/`DECLINE`/`ERROR`/`END` event vocabulary all carry over unchanged.

## New flag — `--include-volumes`

Default: off. Affects only `category_container_vms` (Docker and Podman sub-tools). When on, adds `--volumes` to those tools' `prune` invocations. `--yes` does NOT imply `--include-volumes` — they must be passed independently.

`--help` output gains a one-line note: `--include-volumes  also prune Docker/Podman named volumes (DESTROYS DATA)`.

## Safety rule exception (browser_caches only)

The current rule from `2026-04-22-mac-cleaner-design.md` § Safety guarantees:

> No dynamic path construction for `rm -rf`. Every deletion target is either a hardcoded absolute path or the output of a known tool command.

The first amendment (`2026-05-07-app-cache-cleanup-design.md` § Safety rule exception) carved out one parent: `$HOME/Library/Caches`, immediate-children iteration, denylist filter.

This spec adds a **second carve-out for `category_browser_caches` only**, structurally bounded as follows:

- **Per-browser top-level path is hardcoded** (six literal paths total).
- **Profile-name iteration is restricted to a hardcoded allowlist of literal patterns** per browser:
  - Chromium family: `Default` (literal) and `Profile *` (prefix-glob, immediate children only).
  - Firefox: literal-suffix allowlist (`*.default-release`, `*.default`, `*.dev-edition-default`).
- **Leaf cache subpath inside each profile is hardcoded** (Chrome's leaf list is 7 entries; Firefox is 1).
- **No `**` recursion; no env-derived paths beyond `$HOME`; no user-supplied paths.**
- **The deletion target is `<profile_match>/<hardcoded_leaf>`** — the only string concatenation involves a profile path matched against a literal allowlist and a hardcoded leaf name.

The pattern used for app_caches (denylist) and macos_installers (literal prefix/suffix) is generalized once, here, to "literal allowlist of profile-name patterns + hardcoded leaf list". `CLAUDE.md` will be updated to record this exception with the same "future categories cannot widen this" clause.

If a future category cannot fit any of the three documented exception shapes (denylisted-children, literal-prefix-iteration, allowlist-profile + hardcoded-leaf), it does **not** get an exception — it gets rejected.

## Logging additions

Same event vocabulary; new key/values for transparency:

- `SKIP category=<x> reason=tool_not_installed`
- `SKIP category=<x> reason=empty`
- `SKIP category=<x> reason=app_running app=Xcode|Music|Safari|Chrome|...`
- `SKIP category=diagnostic_reports reason=insufficient_perms group=_analyticsusers`
- `SKIP category=tm_local_snapshots reason=empty count=0`
- `CLEAN category=tm_local_snapshots freed_bytes=<df-delta>` (note: source is `df` delta, not `du`)
- `CLEAN category=container_vms tool=docker freed_bytes=...` (one CLEAN per sub-tool)
- `CLEAN category=browser_caches browser=chrome freed_bytes=...` (one CLEAN per browser)
- `CLEAN category=macos_installers app="Install macOS Sequoia.app" freed_bytes=...` (one CLEAN per installer)

## Verification

Same approach as the existing spec. No unit tests.

1. `zsh -n mac-cleaner.sh` — syntax check.
2. `./mac-cleaner.sh --dry-run` and confirm:
   - Each new Tier 1 category prints its size header and the exact reclaim command.
   - `category_tm_local_snapshots` prints the snapshot count + warning + the `tmutil thinlocalsnapshots` invocation.
   - `category_macos_installers` enumerates each `.app` with size + per-installer prompt.
   - `category_container_vms` only attempts sub-tools whose binary `have`s; for each, it prints the disk-image size (or 0) and the prune command (without `--volumes` unless `--include-volumes` was passed).
   - `category_browser_caches` skips browsers that aren't installed and skips browsers whose process is running, with the right `SKIP reason=` log line.
   - `category_diagnostic_reports` skips the `/Library` path (with the right log key) when the user isn't in `_analyticsusers`.
3. `./mac-cleaner.sh --dry-run --include-volumes` — confirm `--volumes` is appended to docker/podman prune commands.
4. Read `~/.mac-cleaner.log` and confirm event lines for the dry-run carry the right `category=`, `reason=`, and per-sub-tool / per-browser / per-installer keys.
5. Real run on the user's machine — the acceptance test.

## Implementation notes

- **Chromium profile dir glob `Profile *` portability:** a profile named `Profile X` (literal X, not number) would still match. Acceptable since the leaf cache is still a hardcoded subdir of that profile — worst case is we clean an extra profile's cache, which is the same operation we'd do anyway. No tightening needed.
- **Browser `pgrep -f` accuracy:** `/Applications/<App>.app` substring match. False positive only if another path coincidentally contains that string — acceptable.
- **Uniform "GUI app running" rule:** any category whose target is governed by a user-facing GUI app (Xcode, Music, Mail, the six browsers) skips with `SKIP reason=app_running app=<name>` rather than auto-quitting the app. Background daemons that the user does not interact with directly (Gradle daemon, sccache server, Bazel server, Docker engine) are stopped/shut down by their respective `cleanup_*` function before deletion. This split mirrors `cleanup_gradle`'s precedent and avoids surprising the user by closing playback / open windows.

## Files to touch at implementation time

- `mac-cleaner.sh` — add 13 + 6 = 19 new functions, add `--include-volumes` parsing, extend `app_caches` denylist with the four new entries (`com.apple.Music`, `ccache`, `composer`, `org.swift.swiftpm`), drop `~/.cache` from `dev_dotcaches`'s subpath list, drop `~/.cargo/registry/cache` from `dev_dotcaches`.
- `README.md` — add "System Data cleanup" section listing the new categories; mention the four out-of-scope user-data buckets (iCloud, Photos rebuild, Messages history, iOS device backups) with the supported manual alternative for each.
- `CLAUDE.md` (project) — add the second documented safety-rule exception for `category_browser_caches`.
- `~/.mac-cleaner.log` — gains the new event keys above; format unchanged.
