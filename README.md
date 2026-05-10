# mac-cleaner

Interactive macOS developer-cache cleaner. One zsh script that walks every common dev cache on your Mac, shows you its size, and asks `y/N` before deleting anything.

No daemons, no config, no dependencies beyond the tools whose caches it cleans.

## What it cleans

| Category | Path / command |
|---|---|
| npm cache | `~/.npm` (also swept across **every nvm-installed Node**, catching per-version `.npmrc` overrides) |
| yarn cache | `~/Library/Caches/Yarn` (handles both classic v1 and modern Yarn) |
| pnpm store | `~/Library/pnpm/store` or `~/.pnpm-store` (also offers to remove the orphaned `~/Library/pnpm/store/v3` legacy store left by pnpm 5–8 if pnpm has migrated) |
| Homebrew | `brew cleanup -s` + `brew autoremove` |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` *(double-prompted: requires typing `DELETE`)* |
| iOS Simulators | `xcrun simctl delete unavailable` |
| CocoaPods | `~/Library/Caches/CocoaPods` |
| Gradle | `~/.gradle/caches` *(stops the Gradle/Kotlin daemons first to avoid lock-induced partial deletes)* |
| Android build cache | `~/.android/build-cache` |
| Expo / Metro | `~/.expo/cache`, `/tmp/metro-*`, `/tmp/haste-map-*`, `/tmp/react-*` |
| pip cache | `pip3 cache purge` (or `pip cache purge`) |
| Trash | `~/.Trash` |
| App caches | `~/Library/Caches/*` immediate children, denylist-filtered (Apple system, sync state, login-bearing apps preserved) |
| Temp dirs | `/tmp` and `$TMPDIR` — user-owned entries older than 7 days |
| Dev dotcaches | hardcoded `~/.cache/uv`, `~/.bun/install/cache`, `~/.m2/repository`, etc. |

### System Data categories

Targets the buckets macOS reports as **"System Data"** (System Settings → General → Storage).

| Category | Path / command |
|---|---|
| CoreSimulator caches | `~/Library/Developer/CoreSimulator/Caches` *(skip if Simulator running)* |
| Xcode test/playground devices | `~/Library/Developer/{XCTestDevices,XCPGDevices}` *(skip if Xcode running)* |
| Xcode app cache | `~/Library/Caches/com.apple.dt.Xcode` *(skip if Xcode running)* |
| Xcode iOS device logs | `~/Library/Developer/Xcode/iOS Device Logs` |
| SwiftPM cache | `swift package purge-cache` (fallback `~/Library/Caches/org.swift.swiftpm`) |
| clangd index | `~/.cache/clangd` |
| ccache | `ccache --clear` |
| sccache | `sccache --stop-server` then `~/Library/Caches/Mozilla.sccache` |
| Cargo registry | `~/.cargo/registry/{cache,src}` |
| Go caches | `go clean -modcache && go clean -cache` |
| Composer cache | `composer clear-cache` |
| Bazel cache | `bazel shutdown` then `/private/var/tmp/_bazel_$USER` and `~/Library/Caches/bazel` |
| Container VMs | per-tool prune for Docker / OrbStack / Colima / Lima / Podman *(volumes preserved unless `--include-volumes`)* |
| Browser caches | Safari, Chrome, Arc, Edge, Brave, Firefox, Slack — cache subdirs only (Chromium top-level shader caches + Firefox `startupCache` included); cookies/history/logins preserved *(skip if browser/app running)* |
| Apple Music stream cache | `~/Library/Caches/com.apple.Music` *(skip if Music running; does NOT contain downloaded songs)* |
| Mail Downloads | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` *(skip if Mail running)* |
| Diagnostic reports | `~/Library/Logs/DiagnosticReports` + `/Library/Logs/DiagnosticReports` |
| Time Machine local snapshots | `tmutil thinlocalsnapshots / 999999999999 4` *(removes local 24h restore window; network/external TM unaffected)* |
| Stale macOS installers | `/Applications/Install macOS *.app` *(per-installer prompt; 12-15 GB each)* |
| Apple Intelligence platform cache | `~/Library/IntelligencePlatform/` — knowledge graph + per-locale inference artifacts; daemon rebuilds within hours; new in Tahoe 26.x |
| Wallpaper aerials | `~/Library/Application Support/com.apple.wallpaper/aerials/{videos,thumbnails}` — aerial wallpaper videos and thumbnails; re-downloads on next screensaver activation; manifest preserved |
| Android Studio + JetBrains IDE logs | `~/Library/Logs/{Google,JetBrains}` — multi-version log accumulation; each IDE recreates its log dir on next launch |

After cleanup it also runs a **version audit** — checks `npm` / `yarn` / `pnpm` against the registry and lists outdated global npm packages, prompting before any update.

### Manual-only buckets (intentionally NOT scripted)

These are real System Data contributors but the safety/value tradeoff doesn't fit a cleanup script. The supported alternative is listed for each:

- **iCloud Drive cache / "Optimize Mac Storage"** → System Settings → Apple Account → iCloud → Drive → Optimize Mac Storage. Risk of permanent loss of unsynced documents prevents scripting.
- **Photos library derivatives / thumbnails** → quit Photos, then hold ⌥⌘ while opening Photos → Repair Library / Rebuild Thumbnails. Apple's supported rebuild path.
- **Messages attachments / `chat.db`** → Messages → Settings → General → Keep Messages: 30 Days. Risk of irreversible loss if iCloud Messages is off.
- **iOS device backups (`~/Library/Application Support/MobileSync/Backup`)** → Finder → connect device → Manage Backups. Uses Apple's index to identify each backup safely.

## Usage

```bash
./mac-cleaner.sh                  # interactive run
./mac-cleaner.sh --dry-run        # preview only — nothing is deleted
./mac-cleaner.sh --yes            # auto-accept y/N prompts (Xcode Archives still double-prompts)
./mac-cleaner.sh --include-volumes # also prune Docker/Podman named volumes (DESTROYS DATA)
./mac-cleaner.sh --help
```

For each category the script:

1. Reports the cache size (skips silently if already empty / tool not installed).
2. Asks `y/N`. Anything other than `y` skips.
3. Deletes, then reports the bytes actually freed.
4. Logs the event to `~/.mac-cleaner.log` (one line per action, with a per-run id).

At the end you get a summary: total bytes freed and number of categories cleaned.

## Safety

- **Nothing is deleted without an explicit prompt.** `--yes` skips the y/N, but the Xcode Archives prompt always requires typing the literal string `DELETE`.
- `--dry-run` prints every command it *would* run, deletes nothing.
- Gradle: the script stops `gradle --stop` (or kills `GradleDaemon` / `KotlinCompileDaemon`) before deleting, because a half-deleted Gradle cache produces broken Android builds. If a delete partially fails, the script tells you loudly and gives you the recovery command.
- Categories never abort the run — a per-category failure logs `ERROR` and the script continues to the next one.
- All actions are logged to `~/.mac-cleaner.log` with a 4-byte run id so you can correlate runs.

## Requirements

- macOS, zsh (default since Catalina).
- The cleaner only touches caches for tools you have installed; missing tools are skipped silently.

## What mac-cleaner cannot reclaim

Some buckets show up in macOS Storage Settings as "System Data" but cannot be safely freed by an unprivileged tool. mac-cleaner deliberately does not touch them.

**APFS purgeable space (~10–80 GB on heavy iCloud/Photos machines).** macOS marks iCloud-synced local copies and Photos derivatives as "purgeable." These appear in `diskutil info` `CapacityInUse` but not in `df` "used". macOS reclaims them automatically under storage pressure; no user CLI can force this without sudo.

**System volume (~12–15 GB), Preboot (~9 GB), Recovery (~1–2 GB).** The sealed read-only OS partition and firmware support volumes. SIP-protected.

**VM/swap (varies).** Root-owned swap files in `/System/Volumes/VM`. Only a reboot reduces them.

**FileVault.** Adds no storage overhead — encryption is in-place at the block level.

**APFS local snapshots.** Covered by the "Time Machine snapshots" category if you have TM configured. If not, no snapshots accumulate.

**Apple Intelligence cryptex weights (~8–13 GB).** Live in SIP-sealed system cryptex volumes (`/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*`). Reclaim requires disabling Apple Intelligence in System Settings; mac-cleaner does not modify this.

**Chrome's Gemini Nano AI weights (~4 GB).** Chrome silently downloads to `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/`. mac-cleaner does not touch this because deletion forces immediate re-download unless the Chrome setting is changed. To remove permanently: open Chrome → Settings → System → On-device AI → Off, then delete the directory once.

## Files

- `mac-cleaner.sh` — the script.
- `~/.mac-cleaner.log` — append-only log of every run.
- `docs/superpowers/` — design spec and implementation plan.
