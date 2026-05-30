# Tier-1 Cache Additions + Opt-in User-Data / Maintenance — Design

Status: implemented 2026-05-30
Extends: `2026-04-22-mac-cleaner-design.md`, `2026-05-10-system-data-categories-design.md`
Supersedes: three "Out of scope" bullets in `2026-05-10-system-data-categories-design.md`
(see **Reversed prior decisions** below).

## Goal

A four-domain parallel research sweep (Apple/Xcode, cross-language toolchains,
creative/media apps, macOS system) surfaced safe-to-delete buckets the existing
45 categories miss. This spec adds the verified, safety-model-compliant subset
the user approved, plus two deliberate policy additions the user explicitly
opted into.

## A. New categories (no new safety-exception shape)

Every target below is either a **hardcoded absolute path** (safety rule 1, base
case) or the action of a **trusted tool** (rule 1, allowed). None introduces a
new glob-exception shape, so the three ratified exceptions
(`app_caches` / `macos_installers` / `browser_caches`) are untouched.

A new helper `run_paths_category <name> <log_cat> <desc> <path>...` factors the
multi-path size→prompt→delete→measure body already duplicated in
`dev_dotcaches` / `python_extras` / `node_extras` / `llm_caches`. It is additive
— existing categories are not refactored onto it.

| Category | Target | Pattern | Regenerates |
|---|---|---|---|
| `xcode_devicesupport` | `~/Library/Developer/Xcode/{iOS,watchOS,tvOS,visionOS} DeviceSupport` | hardcoded multi-path | re-copied from device on next debug session |
| `xcode_docs` | `~/Library/Developer/Xcode/{DocumentationCache,DocumentationIndex}`, `~/Library/Developer/Shared/Documentation/DocSets` | hardcoded multi-path | re-downloaded on demand |
| `xcode_previews` | `xcrun simctl --set previews delete all` (sized via `~/Library/Developer/Xcode/UserData/Previews`) | trusted tool | recreated on next preview render |
| `instruments_cache` | `~/Library/Caches/com.apple.dt.Instruments` | hardcoded single path (run_category) | regenerated on launch |
| `adobe_media_cache` | `~/Library/Application Support/Adobe/Common/Media Cache{, Files}` | hardcoded multi-path | rebuilt on project open |
| `desktop_app_caches` | `~/Library/Application Support/Figma/{Desktop,DesktopProfile}`, `Steam/{appcache,steamapps/shadercache}` | hardcoded multi-path | re-synced from cloud / recompiled |
| `user_logs` | `~/Library/Logs`, `~/Library/Application Support/CrashReporter` | hardcoded multi-path | written on next event |
| `quicklook_cache` | `qlmanage -r cache` (sized via `$(getconf DARWIN_USER_CACHE_DIR)com.apple.QuickLook.thumbnailcache`) | trusted tool | rebuilt on next preview |
| `font_cache` | `atsutil databases -removeUser` (no size path) | trusted tool | rebuilt by fontd |

`dev_dotcaches` array also extended with hardcoded `~/.nuget/packages`,
`~/.ivy2/cache`, `~/.sbt/boot`, `~/.gradle/wrapper/dists`, `~/.gradle/daemon`,
`~/.terraform.d/plugin-cache`, `~/.cache/zig` (all `~/.*` cache subpaths, same
shape as the existing entries).

Notes:
- `quicklook_cache` / `font_cache` / `xcode_previews` **delete via a trusted
  tool, never `rm`** — the dynamic path is only ever read (for sizing), never a
  deletion target, so the no-dynamic-`rm` rule holds.
- `instruments_cache` and `quicklook_cache` are Apple `com.apple.*` paths that
  the generic `app_caches` denylist sweep deliberately skips; they get explicit
  hardcoded categories instead.

## B. Policy addition 1 — first user-data category (`ios_backups`)

`~/Library/Application Support/MobileSync/Backup` holds Finder/iTunes device
backups. These are **irreplaceable user data, not cache** — for anyone not using
iCloud Backup, the only copy of their device. This is the script's first and
only user-data deletion.

Guard (mirrors `category_xcode_archives`, hardened):
1. Red WARNING banner stating it is permanent, non-cache data.
2. Per-backup listing for informed consent: device name + last-backup date (best-
   effort from each backup's `Info.plist` via `PlistBuddy`, fallback to UDID) +
   size, plus a total.
3. Standard y/N, then a **second prompt requiring the literal string `DELETE`**.
   `--yes` does **not** bypass this second prompt (same load-bearing rule as
   Xcode Archives).
4. `rm` target is the hardcoded `MobileSync/Backup/` parent + `*` glob (identical
   shape to `DerivedData/*` — hardcoded parent, immediate children) — no dynamic
   path construction.

## C. Policy addition 2 — first sudo path (`system_maintenance`)

Opt-in final step offering `sudo purge` (frees inactive RAM) and
`sudo mdutil -E /` (rebuilds the Spotlight index). Properties:
- **The only `sudo` in the script.** Fully opt-in behind its own y/N; declining
  is the default path and touches nothing.
- **Reclaims no disk** (`mdutil` temporarily uses *more*). Therefore it does
  **not** increment `TOTAL_FREED` / `CATEGORIES_CLEANED` — the freed-bytes
  accounting stays honest.
- Under `--dry-run`, `run_cmd` prints but never executes, so `sudo` is never
  invoked during a preview.

## Reversed prior decisions

`2026-05-10-system-data-categories-design.md` "Out of scope" listed these as
rejected. The user explicitly opted **in** on 2026-05-30; this spec supersedes
those bullets:

- **Xcode `*DeviceSupport`** — previously "user explicitly opted out — needs
  them for old iPhones/Watches." Now opted in (`xcode_devicesupport`); safe
  because Xcode re-copies symbols on the next debug session.
- **iOS device backups** — previously "irreplaceable user data; README mention
  only." Now opted in (`ios_backups`) with the typed-`DELETE` + per-backup-
  listing guard above. The irreplaceability is unchanged; the decision changed.

Still out of scope (unchanged): **stale Xcode simulator runtimes**
(`xcrun simctl runtime delete`) — must be re-downloaded, user has not opted in;
iCloud/CloudKit/`bird` caches; Photos internals; Messages/`chat.db`;
`~/Library/Containers/*/Caches` and `Group Containers` (would require a new,
unratified glob-exception shape).

## Testing

`zsh -n` clean; `./mac-cleaner.sh --dry-run` exits 0 with all 11 new sections
present, empties auto-skipping, non-empty targets printing the correct
hardcoded-path / trusted-tool commands. On the author's machine the dry run
surfaced `Xcode DeviceSupport` 10.57 GB, `desktop_app_caches` 861 MB,
`user_logs` 111 MB.
