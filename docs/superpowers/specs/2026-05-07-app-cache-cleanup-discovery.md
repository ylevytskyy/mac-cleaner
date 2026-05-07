# App Cache Cleanup — Discovery Report

Generated: 2026-05-07  
Consumed by: implementation agent working from `2026-05-07-app-cache-cleanup-design.md`  
Machine: darwin 25.4.0, user `lion`

---

## Step 1 — Existing-Category Target Inventory (Collision-Avoidance Ground Truth)

Every filesystem path that an existing category in `mac-cleaner.sh` already deletes or sweeps. These paths are **OFF-LIMITS** for Appendices A, B, and C unless the spec's Reconciliation section explicitly says otherwise.

| Category function | Paths owned |
|---|---|
| `category_npm_cache` | `~/.npm` |
| `category_yarn_cache` | `~/Library/Caches/Yarn` |
| `category_pnpm_store` | `~/Library/pnpm/store`, `~/.pnpm-store` |
| `category_brew` | `$(brew --cache)` — resolves to `~/Library/Caches/Homebrew` |
| `category_npm_yarn_all_nvm` | invokes `npm cache clean` + `yarn cache clean` per nvm version; default paths same as npm/yarn categories above |
| `category_npm_yarn_all_brew` | invokes `npm cache clean` + `yarn cache clean` per brew Node formula; default paths same as above |
| `category_xcode_derived` | `~/Library/Developer/Xcode/DerivedData/*` |
| `category_xcode_archives` | `~/Library/Developer/Xcode/Archives/*` |
| `category_ios_sim` | `xcrun simctl delete unavailable` — managed by simctl, not a fixed path |
| `category_cocoapods` | `~/Library/Caches/CocoaPods` |
| `category_gradle` | `~/.gradle/caches` |
| `category_android_build` | `~/.android/build-cache` |
| `category_expo_metro` | `~/.expo/cache`, `/tmp/metro-*`, `/tmp/haste-map-*`, `/tmp/react-*` |
| `category_pip_cache` | `$(pip3 cache dir)` — resolves to `~/Library/Caches/pip` |
| `category_trash` | `~/.Trash` |

**Note on `/tmp` overlap with expo_metro:** `category_expo_metro` deletes `/tmp/metro-*`, `/tmp/haste-map-*`, and `/tmp/react-*` without an mtime gate. Category B's sweep is mtime-gated at `+7` days and scoped to user-owned entries, so it will catch any orphaned expo/metro temp files older than 7 days that expo_metro missed. Because the patterns are different (Category B sweeps all user-owned entries, not just those three globs), no exclusion is needed — but the implementation agent should be aware that fresh expo/metro files will be caught by `category_expo_metro` first and will already be gone before Category B runs.

---

## Step 2 — Appendix A: `~/Library/Caches` Classification

### Summary statistics

Total `~/Library/Caches` size on this machine: ~16.2 GB (dominated by `Google/` Android Studio caches at 13.1 GB).

### Classification table

Classes: **ALLOW** = safe `rm -rf` of entire child; **PARTIAL** = only named subfolders inside are safe; **DENY** = do not touch.

Sizes are `du -sk` in KB unless noted as MB.

| Child | Class | Size (KB) | Rationale |
|---|---|---|---|
| `Animoji` | ALLOW | 436 | Animoji model textures; purely regenerable asset cache |
| `askpermissiond` | DENY | 404 | Apple permission daemon state; mixed Cache.db + system state |
| `chrome_crashpad_handler` | DENY | 80 | Chrome crash reporter state (Cache.db pattern but holds crash metadata) |
| `claude-cli-nodejs` | ALLOW | 123,144 | MCP log files per project; purely regenerable logs, no auth state |
| `CloudKit` | DENY | 25,340 | iCloud sync state; wiping disrupts CloudKit sync across apps |
| `com.anthropic.claudefordesktop` | DENY | 2,132 | Claude Desktop app cache; Cache.db only, safe structurally — but conservative DENY since session/auth data may be co-located with Cache.db on the claudefordesktop prefix |
| `com.anthropic.claudefordesktop.ShipIt` | DENY | 76 | Sparkle updater state for Claude Desktop; contains ShipItState.plist |
| `com.apple.accountsd` | DENY | 172 | Apple account daemon; holds account state |
| `com.apple.akd` | DENY | 2,176 | Apple authentication key daemon; security-adjacent |
| `com.apple.AMPDevicesAgent` | DENY | 216 | Apple Media Products device state |
| `com.apple.AMPLibraryAgent` | DENY | 3,648 | Apple Music library agent; music library index |
| `com.apple.amsaccountsd` | DENY | 3,304 | Apple Media Services account daemon; auth state |
| `com.apple.amsengagementd` | DENY | 4,196 | Apple Media engagement daemon |
| `com.apple.ap.adprivacyd` | DENY | 3,156 | Apple privacy ad daemon |
| `com.apple.ap.PromotedContentJetService` | DENY | 236 | Apple promoted content (ads); system daemon state |
| `com.apple.appleaccountd` | DENY | 2,132 | Apple account daemon; contains account/auth state |
| `com.apple.AppleMediaServices` | DENY | 9,444 | Apple Music/TV purchase records and DRM keys |
| `com.apple.appstore` | DENY | 340 | App Store session/purchase cache |
| `com.apple.appstoreagent` | DENY | 3,204 | App Store agent; contains purchase and download state |
| `com.apple.AssistantServices` | DENY | 0 | Siri assistant service state |
| `com.apple.assistantd` | DENY | 0 | Siri daemon state |
| `com.apple.AvatarKit` | DENY | 0 | Memoji avatar data |
| `com.apple.betaenrollmentagent` | DENY | 276 | Beta enrollment state; system enrollment records |
| `com.apple.bird` | DENY | 0 | iCloud Drive daemon (bird = iCloud file sync) |
| `com.apple.businessservicesd` | DENY | 0 | Business services daemon state |
| `com.apple.cache_delete` | DENY | 24 | System cache manager; do not touch |
| `com.apple.callintelligenced` | DENY | 0 | On-device call transcription state |
| `com.apple.cds` | DENY | 0 | Core Data sync daemon |
| `com.apple.cds.vbtx` | DENY | 0 | Core Data sync (transactions) |
| `com.apple.chrono` | DENY | 0 | App Store download scheduling state |
| `com.apple.CloudTelemetry` | DENY | 7,400 | Apple telemetry upload queue; system-managed |
| `com.apple.commerce` | DENY | 0 | In-app purchase commerce state |
| `com.apple.containermanagerd` | DENY | 0 | App container management daemon |
| `com.apple.controlcenter` | DENY | 80 | Control Center state |
| `com.apple.ctcategories.service` | DENY | 4,540 | Communications transcription categories |
| `com.apple.dataaccess.dataaccessd` | DENY | 168 | Contacts/Calendar data access daemon state |
| `com.apple.dt.Xcode` | DENY | 6,724 | Xcode IDE caches — managed by Xcode, not ours to touch |
| `com.apple.dt.Xcode.ITunesSoftwareService` | DENY | 724 | iTunes/Xcode device software service state |
| `com.apple.dt.xcodebuild` | DENY | 80 | Xcode build system state |
| `com.apple.duetexpertd` | DENY | 192 | Siri Suggestions ML model state |
| `com.apple.e5rt.e5bundlecache` | DENY | 0 | System bundle cache |
| `com.apple.Family-Settings.extension` | DENY | 2,144 | Family Sharing settings extension state |
| `com.apple.FeatureAccessAgent` | DENY | 4,180 | Feature availability/flag state |
| `com.apple.feedbacklogger` | DENY | 208 | Feedback Assistant logs |
| `com.apple.gamed` | DENY | 0 | Game Center daemon state |
| `com.apple.geoanalyticsd` | DENY | 3,112 | Location analytics state |
| `com.apple.helpd` | DENY | 17,940 | Help viewer cache with indexed help content |
| `com.apple.homed` | DENY | 0 | HomeKit daemon state |
| `com.apple.HomeKit` | DENY | 0 | HomeKit state |
| `com.apple.iCloudNotificationAgent` | DENY | 2,132 | iCloud notification state |
| `com.apple.icloudwebd` | DENY | 144 | iCloud web daemon state |
| `com.apple.iTunes` | DENY | 2,152 | iTunes library/purchase index |
| `com.apple.itunes.swinfo` | DENY | 340 | iTunes software info state |
| `com.apple.iTunesCloud` | DENY | 0 | iTunes Cloud sync state |
| `com.apple.itunescloudd` | DENY | 968 | iTunes Cloud daemon state |
| `com.apple.managedappdistributionagent` | DENY | 3,144 | MDM-managed app distribution state |
| `com.apple.Music` | DENY | 2,388 | Apple Music library index and cached artwork |
| `com.apple.nbagent` | DENY | 2,152 | Notification banner agent state |
| `com.apple.nsurlsessiond` | DENY | 0 | NSURLSession background transfer state |
| `com.apple.parsecd` | DENY | 0 | Spotlight/CoreSpotlight parse daemon state |
| `com.apple.passd` | DENY | 5,416 | Wallet/Passbook daemon; holds pass data |
| `com.apple.proactive.eventtracker` | DENY | 260 | Siri Suggestions event tracking state |
| `com.apple.python` | DENY | 8,856 | System Python extension modules; system-managed |
| `com.apple.remindd` | DENY | 172 | Reminders daemon state |
| `com.apple.Safari` | DENY | 884 | Safari RemoteNotifications + WebKitCache — Safari manages its own cache |
| `com.apple.Safari.SafeBrowsing` | DENY | 276 | Safari Safe Browsing state (security-adjacent) |
| `com.apple.shazamd` | DENY | 512 | Shazam audio recognition state |
| `com.apple.sirittsd` | DENY | 0 | Siri text-to-speech state |
| `com.apple.SoftwareUpdateNotificationManager` | DENY | 212 | Software update check state |
| `com.apple.storekitagent` | DENY | 3,300 | StoreKit in-app purchase agent state |
| `com.apple.tipsd` | DENY | 3,720 | Tips app content |
| `com.apple.tiswitcher.cache` | DENY | 0 | Text input switcher cache (file, not dir) |
| `com.apple.translationd` | DENY | 1,036 | Translation daemon state |
| `com.apple.VideoConference` | DENY | 20 | FaceTime/video conferencing state |
| `com.apple.weatherd` | DENY | 356 | Weather daemon location state |
| `com.exafunction.windsurf` | ALLOW | 404 | Windsurf IDE (Electron): only Cache.db + fsCachedData — pure HTTP/asset cache |
| `com.exafunction.windsurf.ShipIt` | DENY | 28 | Sparkle updater state for Windsurf |
| `com.exafunction.windsurfNext` | ALLOW | 724 | Windsurf Next IDE: only Cache.db + fsCachedData — pure HTTP/asset cache |
| `com.exafunction.windsurfNext.ShipIt` | DENY | 48 | Sparkle updater state for Windsurf Next |
| `com.figma.agent` | ALLOW | 724 | Figma desktop agent: only Cache.db + fsCachedData — pure HTTP cache |
| `com.figma.Desktop` | ALLOW | 276 | Figma Desktop: only Cache.db + fsCachedData — pure HTTP cache (no User profile dir here) |
| `com.figma.Desktop.ShipIt` | DENY | 16 | Sparkle updater state for Figma |
| `com.github.CopilotForXcode` | DENY | 0 | Contains org.sparkle-project.Sparkle — updater state only |
| `com.github.CopilotForXcode.ExtensionService` | ALLOW | 884 | GitHub Copilot Xcode extension: only Cache.db + fsCachedData |
| `com.google.antigravity` | ALLOW | 404 | Google Antigravity (Chrome remote desktop helper): only Cache.db + fsCachedData |
| `com.google.antigravity.ShipIt` | DENY | 28 | Sparkle updater state for Antigravity |
| `com.google.GoogleUpdater` | DENY | 80 | Google Updater state; contains update scheduling state |
| `com.googlecode.iterm2` | ALLOW | 176 | iTerm2: Cache.db + fsCachedData + org.sparkle-project.Sparkle + parsers — parsers are regenerable |
| `com.knollsoft.Rectangle` | ALLOW | 9,516 | Rectangle window manager: only Cache.db + fsCachedData |
| `com.lwouis.alt-tab-macos` | ALLOW | 80 | AltTab: only Cache.db + fsCachedData |
| `com.macpaw.site.Gemini2` | ALLOW | 80 | Gemini 2 duplicate finder: only Cache.db/shm/wal |
| `com.microsoft.autoupdate.fba` | DENY | 420 | Microsoft AutoUpdate state; removing disrupts Office update checks |
| `com.microsoft.VSCode` | ALLOW | 468 | VS Code: only Cache.db + fsCachedData — pure HTTP/asset cache |
| `com.microsoft.VSCode.ShipIt` | DENY | 36 | Sparkle updater state for VS Code |
| `com.mitchellh.ghostty` | PARTIAL | 348 | Ghostty terminal: Cache.db + fsCachedData are safe; `sentry/` is crash reporter state |
| `com.plausiblelabs.crashreporter.data` | DENY | 0 | Crash reporter data (holds crash reports per-app) |
| `com.raycast.macos` | DENY | 9,656 | Raycast: contains Clipboard history and urlcache — user content |
| `com.trae.app` | ALLOW | 276 | Trae AI IDE: only Cache.db + fsCachedData |
| `com.trae.app.ShipIt` | DENY | 28,800 | REVIEW: ShipIt normally small; 28MB is large — may contain pending update binary |
| `docker-secrets-engine` | DENY | 0 | Docker secrets state |
| `Docker Desktop` | DENY | 8 | Docker Desktop state (bugsnag crash reporter) |
| `dotslash` | ALLOW | 368,532 | DotSlash binary cache (Meta's tool runner); `bc/` = cached binaries, `locks/` = lock files — purely regenerable |
| `eas-cli` | DENY | 16 | EAS CLI version + error log; state, not cache |
| `FamilyCircle` | DENY | 32 | Family Sharing state |
| `familycircled` | DENY | 2,132 | Family Sharing daemon state |
| `Firefox` | DENY | 391,068 | Firefox profiles cache; `Profiles/` dir contains user data and session state |
| `flutter_engine` | ALLOW | 84 | Flutter engine download cache; purely regenerable |
| `GameKit` | DENY | 48 | Game Center state |
| `Gemini 2` | ALLOW | 512 | Gemini 2 scan results cache; regenerable |
| `GeoServices` | DENY | 74,712 | Maps/Location offline tile cache and regional resource data; system-managed |
| `Google` | PARTIAL | 13,090,124 | Android Studio IDE caches and Chrome; see safe subfolders below |
| `Homebrew` | DENY | 695,696 | **Covered by `category_brew`** — Homebrew manages its own cache lifecycle |
| `io.sentry` | DENY | 0 | Sentry crash reporter upload queue; async.log + pending crash reports |
| `Jedi` | ALLOW | 2,796 | Python Jedi language server cache; regenerable |
| `JNA` | ALLOW | 0 | Java Native Access temp cache; regenerable |
| `main.kts.compiled.cache` | ALLOW | 0 | Kotlin script compiled cache; regenerable |
| `Mozilla` | DENY | 28 | Mozilla update state |
| `ms-playwright` | ALLOW | 540,264 | Playwright browser binaries (Chromium, Firefox, ffmpeg); large but regenerable via `playwright install` |
| `ms-playwright-go` | ALLOW | 256,656 | Playwright Go browser binaries; regenerable |
| `node-gyp` | ALLOW | 127,676 | node-gyp Node.js header cache; regenerable via `node-gyp` |
| `org.graalvm.polyglot` | ALLOW | 52 | GraalVM polyglot engine cache; regenerable |
| `org.m0k.transmission` | PARTIAL | 176 | Transmission BitTorrent: Cache.db + fsCachedData + WebKit are safe; `org.sparkle-project.Sparkle` is updater state |
| `org.swift.swiftpm` | ALLOW | 168,764 | Swift Package Manager: repositories checkouts, manifests, artifacts — all regenerable on next build |
| `org.videolan.vlc` | ALLOW | 8,664 | VLC: only Cache.db + fsCachedData |
| `PassKit` | DENY | 2,268 | Wallet pass data — user content |
| `pip` | DENY | 12 | **Covered by `category_pip_cache`** (`pip3 cache dir` resolves here) |
| `pnpm` | DENY | 0 | pnpm dlx cache (currently empty); **covered by `category_pnpm_store`** scope — REVIEW: spec says `~/Library/pnpm/store` is pnpm's store; `~/Library/Caches/pnpm` is a separate dlx cache; consider whether to own this under Category A or the existing pnpm category |
| `qemu-system-aarch64` | ALLOW | 0 | QEMU VM emulator: only Cache.db + fsCachedData |
| `SentryCrash` | DENY | 12 | Sentry crash reports per-app (Gemini 2, Logi, Raycast) — pending upload queue |
| `ssu` | DENY | 0 | Software Update state |
| `SwiftLint` | ALLOW | 168 | SwiftLint cache; regenerable |
| `TemporaryItems` | DENY | 0 | macOS temp items (`.DS_Store` staging); system-managed |
| `Trae` | DENY | 611,012 | Trae AI IDE updater staging: `pending/` + `update.zip` — in-progress update binary |
| `typescript` | ALLOW | 387,600 | TypeScript language server compiler cache (v5.9, v6.0 node_modules); regenerable |
| `Viber Media S.à r.l` | DENY | 4 | Viber state |
| `Yarn` | DENY | 0 | **Covered by `category_yarn_cache`** |
| `Zed` | ALLOW | 0 | Zed editor cache; currently empty but safe to include |

### PARTIAL entries — safe subfolders

**`com.mitchellh.ghostty`**: safe to delete `Cache.db`, `Cache.db-shm`, `Cache.db-wal`, `fsCachedData`. Do **not** delete `sentry/` (crash reporter state) or `WebKit/` if present.  
Recommended implementation: since the safe subfolders are the standard Cache.db set, treat as ALLOW and note the `sentry/` exception. On this machine `sentry/` is present.

**`org.m0k.transmission`**: safe to delete `Cache.db`, `Cache.db-shm`, `Cache.db-wal`, `fsCachedData`, `WebKit/`. Do **not** delete `org.sparkle-project.Sparkle/` (updater state).  
On this machine the directory is only 176 KB total so low-priority.

**`Google`**: safe subfolders are `AndroidStudio*/` and `Chrome/`. See detailed breakdown:

| Safe subfolder | Size (KB) | Notes |
|---|---|---|
| `Google/AndroidStudio2025.3.1` | 3,615,344 | IDE build/index caches; regenerable |
| `Google/AndroidStudio2025.3.2` | 2,527,332 | IDE build/index caches; regenerable |
| `Google/AndroidStudio2025.3.3` | 3,654,024 | IDE build/index caches; regenerable |
| `Google/AndroidStudio2025.3.4` | 2,422,604 | IDE build/index caches; regenerable |
| `Google/Chrome` | 403,208 | Chrome browser HTTP cache; regenerable |

**Implementation note for `Google/`**: rather than deleting `Google/` as a whole, iterate its immediate children. `AndroidStudio*/` (glob) and `Chrome/` are safe. Any future child of `Google/` that doesn't match those patterns should default to DENY. This is a case where a denylist-by-default approach inside this subdirectory is safer than an allowlist.

REVIEW for implementation agent: the spec's Category A cleanup iterates `~/Library/Caches` immediate children. `Google/` is one child — deleting it as a whole is ALLOW but only because all known children are safe. Consider treating `Google/` as a special-cased PARTIAL with explicit safe-subfolder logic, to avoid future `Google/SomeNewApp` being accidentally deleted.

### Denylist prefix patterns

The following prefixes cover large families of children that are all DENY. Use these as wildcard patterns in the denylist array:

| Prefix | Covers | Rationale |
|---|---|---|
| `com.apple.*` | All Apple daemon/app caches | Mixed cache + sync + auth state; Apple manages its own eviction |
| `*.ShipIt` | All Sparkle updater dirs | Contains `ShipItState.plist` and pending update binaries — never delete |
| `com.plausiblelabs.*` | Crash reporter data | Pending crash upload queues |

Additional single-name denies that don't fit a prefix:
- `CloudKit` — iCloud sync state
- `Firefox` — user profile data inside cache dir
- `GeoServices` — large offline map tile cache; system-managed
- `Homebrew` — covered by `category_brew`
- `Yarn` — covered by `category_yarn_cache`
- `pip` — covered by `category_pip_cache`
- `TemporaryItems` — system-managed
- `SentryCrash` — crash report upload queues
- `io.sentry` — crash report upload queues
- `PassKit` — Wallet user data
- `com.raycast.macos` — clipboard history (user content)
- `FamilyCircle`, `familycircled` — Family Sharing state
- `Docker Desktop`, `docker-secrets-engine` — Docker state
- `ssu` — Software Update state
- `Trae` — contains in-progress 611 MB update.zip (REVIEW: may be safe to delete if Trae is not updating; conservative DENY for now)
- `Viber Media S.à r.l` — messaging app state

### Estimated ALLOW reclaim from Category A (this machine)

| Entry | Size (KB) |
|---|---|
| `Google/` (AndroidStudio * 4 + Chrome) | 12,622,312 |
| `dotslash` | 368,532 |
| `ms-playwright` | 540,264 |
| `ms-playwright-go` | 256,656 |
| `org.swift.swiftpm` | 168,764 |
| `typescript` | 387,600 |
| `claude-cli-nodejs` | 123,144 |
| `node-gyp` | 127,676 |
| `Jedi` | 2,796 |
| `com.knollsoft.Rectangle` | 9,516 |
| `com.figma.agent` + `com.figma.Desktop` | 1,000 |
| `com.microsoft.VSCode` | 468 |
| `org.videolan.vlc` | 8,664 |
| `com.exafunction.windsurf*` | 1,128 |
| `com.trae.app` | 276 |
| `com.github.CopilotForXcode.ExtensionService` | 884 |
| `flutter_engine`, `org.graalvm.polyglot`, `SwiftLint`, others | ~1,200 |
| **Total estimate** | **~14.5 GB** |

---

## Step 3 — Appendix B: `$HOME` Dotfolder Cache Subpaths (Category C)

### Classification table

Classes: **CACHE-SAFE** = full subpath safe; **PARTIAL** = only named subpath inside is cache; **NOT-CACHE** = skip entirely.

| Dotfolder / subpath | Class | Size of safe subpath (KB) | Rationale |
|---|---|---|---|
| `.agents` | NOT-CACHE | — | Claude Code skills store; config state |
| `.ai_completion` | NOT-CACHE | — | AI completion config |
| `.android` (whole) | NOT-CACHE | — | Mixed state+credentials (adbkey, debug.keystore, avd); **not** safe to wipe |
| `.android/cache` | PARTIAL → CACHE-SAFE subpath | 8,676 | Only `~/.android/cache` is safe; build-cache covered by `category_android_build` |
| `.app-store` | NOT-CACHE | — | Contains `auth/` credentials for fastlane/deliver |
| `.aws` | NOT-CACHE | — | AWS credentials and SSO tokens |
| `.bun/install/cache` | CACHE-SAFE | 115,020 | Bun package download cache; regenerable via `bun install` |
| `.bundle/cache` | CACHE-SAFE | 22,640 | Bundler gem download cache (`compact_index` format); regenerable |
| `.cagent` | NOT-CACHE | — | AI agent store state |
| `.cargo` | NOT-CACHE (absent) | 0 | Not present on this machine; if added, `~/.cargo/registry/cache` is safe, NOT `src/` |
| `.cache` (whole) | NOT-CACHE | — | XDG cache; contains mixed safe and unsafe entries; see safe subpaths below |
| `.cache/uv` | CACHE-SAFE | 29,538,344 | uv Python package manager cache; regenerable |
| `.cache/puppeteer` | CACHE-SAFE | 1,025,460 | Puppeteer browser binaries; regenerable via `npx puppeteer browsers install` |
| `.cache/node` | CACHE-SAFE | 52,148 | Node corepack cache; regenerable |
| `.cache/prisma` | CACHE-SAFE | 35,816 | Prisma query engine binary cache; regenerable |
| `.cache/mesa_shader_cache` | CACHE-SAFE | 2,704 | Mesa GPU shader cache; regenerable |
| `.cache/pkg` | CACHE-SAFE | 5,744 | `pkg` Node.js packager binary cache; regenerable |
| `.cache/vscode-ripgrep` | CACHE-SAFE | 1,428 | VS Code ripgrep binary cache; regenerable |
| `.cache/gitstatus` | CACHE-SAFE | 2,080 | gitstatus binary cache; regenerable |
| `.cache/tooling` | CACHE-SAFE | 268 | tooling gradle cache; regenerable |
| `.cache/github-copilot` | NOT-CACHE | — | REVIEW: contains `project-context` and `project-index` — may hold auth-adjacent context; 1.2 GB is significant; classify conservatively as NOT-CACHE |
| `.cache/opencode` | NOT-CACHE | — | opencode: contains `node_modules` + `models.json` — application state, not pure cache |
| `.cache/claude` | NOT-CACHE | — | Claude cache dir; may contain staging/auth state |
| `.cache/devin` | NOT-CACHE | — | Devin AI CLI/next binaries and telemetry state |
| `.cache/icedtea-web` | NOT-CACHE | — | REVIEW: icedtea-web Java Web Start; 690 MB — regenerable in theory but conservative DENY since it may hold browser-trusted state |
| `.cache/phpactor` | NOT-CACHE | — | REVIEW: phpactor PHP language server cache; 130 MB — safe to delete but not common enough to include without confirmation |
| `.cache/chrome-devtools-mcp` | CACHE-SAFE | 208,576 | Chrome DevTools MCP server resource cache; regenerable |
| `.cache/zed` | CACHE-SAFE | 0 | Zed editor XDG cache; currently empty |
| `.cache/kilo`, `.cache/p10k-*` | NOT-CACHE | — | Shell tool state/compiled cache; tiny, do not bother |
| `.claude` | NOT-CACHE | — | Claude Code config, credentials, session state |
| `.cmake` | NOT-CACHE | — | CMake config; small, not cache |
| `.cocoapods` | NOT-CACHE | — | CocoaPods repo checkouts — NOT the Lib/Caches version; these are the actual cloned specs repos |
| `.codex` | NOT-CACHE | — | OpenAI Codex CLI: auth.json + sessions + history — credentials + state |
| `.codeium` | NOT-CACHE | — | Codeium/Windsurf AI: memories, database, user_settings — state + credentials |
| `.codestream` | NOT-CACHE | — | CodeStream VS Code extension state |
| `.codeverse` | NOT-CACHE | — | AI coding tool trace; state |
| `.composer` | NOT-CACHE | — | PHP Composer: only `latest.phar` (tool binary), no cache dir present |
| `.composio` | NOT-CACHE | — | Composio AI tooling state |
| `.config` | NOT-CACHE | — | XDG config dir: mixed configs and credentials across many tools |
| `.context7` | NOT-CACHE | — | Contains `credentials.json` — auth credentials |
| `.copilot` | NOT-CACHE | — | GitHub Copilot state |
| `.cursor` | NOT-CACHE | — | Cursor IDE: `argv.json` + extensions + skills — config state, not cache |
| `.dart-tool` | NOT-CACHE | — | Dart Flutter tool: CLIENT_ID + telemetry config + session — state, not regenerable cache |
| `.docker` | NOT-CACHE | — | Docker Desktop: config.json + contexts + credentials — credentials + state |
| `.electron` | NOT-CACHE (absent) | 0 | Not present on this machine |
| `.electron-gyp` | NOT-CACHE (absent) | 0 | Not present on this machine |
| `.expo` | NOT-CACHE | — | Mixed state; `~/.expo/cache` covered by `category_expo_metro`; other subdirs hold simulator app installs (1.4 GB) — REVIEW: `android-apk-cache` (583 MB) and `ios-simulator-app-cache` (1.4 GB) are likely safe to delete; codesigning and state.json are not |
| `.gem/specs` | CACHE-SAFE | 33,500 | RubyGems spec index; regenerable via `gem update --system` |
| `.gemini` | NOT-CACHE | — | Google Gemini CLI: `oauth_creds.json` + `mcp-oauth-tokens-v2.json` — credentials |
| `.Genymobile` | NOT-CACHE | — | Genymotion Android emulator state + logs |
| `.ghcp-appmod`, `.ghcp-appmod-java` | NOT-CACHE | — | GitHub Copilot app modernization state |
| `.gk` | NOT-CACHE | — | GitKraken workspace state |
| `.gluestack/cache` | CACHE-SAFE | 327,364 | Gluestack UI CLI package download cache; regenerable |
| `.gradle` | NOT-CACHE (whole) | — | **Covered by `category_gradle`** for `~/.gradle/caches`; other subdirs (daemon, jdks, wrapper) are not safe to wipe |
| `.hawtjni` | CACHE-SAFE | 0 | HawtJNI native library extraction cache; currently empty, regenerable |
| `.icube-remote-ssh` | NOT-CACHE | — | Remote SSH state |
| `.javacpp/cache` | CACHE-SAFE | 57,212 | JavaCPP precompiled native library JARs; regenerable |
| `.kiro` | NOT-CACHE | — | Kiro AI IDE: extensions + settings + skills — state, not cache |
| `.livekit` | NOT-CACHE | — | LiveKit credentials/state |
| `.lldb/module_cache` | CACHE-SAFE | 2,138,040 | LLDB debugger module cache; regenerable on next debug session |
| `.lldbinit_commands` | NOT-CACHE | — | LLDB init scripts |
| `.local` | NOT-CACHE | — | XDG local: bin + share + state — mixed app data, not cache |
| `.m2/repository` | CACHE-SAFE | 354,256 | Maven local repository (downloaded JARs); regenerable via Maven rebuild |
| `.maestro` | NOT-CACHE | — | Maestro mobile testing tool: sessions + tests + deps — state + tool installation |
| `.marscode` | NOT-CACHE | — | MarsCode IDE state |
| `.mcp-auth` | NOT-CACHE | — | MCP OAuth tokens per protocol version — credentials |
| `.mongodb` | NOT-CACHE | — | MongoDB shell state |
| `.net` | NOT-CACHE | — | .NET SDK: `Updates/` contains downloaded update packages; REVIEW: 140 MB in `Updates/` is likely safe but conservative DENY |
| `.npm` | NOT-CACHE | — | **Covered by `category_npm_cache`** |
| `.nvm` | NOT-CACHE | — | nvm Node version manager: installed versions + scripts — tool installation, not cache |
| `.oh-my-zsh` | NOT-CACHE | — | Oh My Zsh framework installation |
| `.openjfx/cache` | CACHE-SAFE | 560 | OpenJFX native library cache; regenerable |
| `.pub-cache/hosted` | CACHE-SAFE | 901,164 | Dart/Flutter pub package download cache; regenerable via `flutter pub get` |
| `.pymobiledevice3` | NOT-CACHE | — | pymobiledevice3 state (currently empty) |
| `.qodo` | NOT-CACHE | — | Qodo AI coding tool: history + workflows — state |
| `.rbenv` | NOT-CACHE (whole) | — | rbenv: installed Ruby versions + shims — tool installation |
| `.redhat` | NOT-CACHE | — | Red Hat tools state |
| `.rest-client` | NOT-CACHE | — | REST Client VS Code extension: history + cookies + environment — state |
| `.skiko` | CACHE-SAFE | 40,760 | Skiko (Kotlin Multiplatform graphics) native library cache; regenerable |
| `.ssh` | NOT-CACHE | — | SSH keys and config — credentials |
| `.supermaven` | NOT-CACHE | — | Supermaven AI config |
| `.swiftpm` | NOT-CACHE | — | Swift PM configuration + security fingerprints — state, not cache |
| `.trae` | NOT-CACHE | — | Trae AI IDE: extensions + skills + worktrees — state |
| `.trae-aicc` | NOT-CACHE | — | Trae AICC state |
| `.Trash` | NOT-CACHE | — | **Covered by `category_trash`** |
| `.vscode` | NOT-CACHE | — | VS Code: argv.json + extensions (installed) + cli — config + installed extensions |
| `.vscode-react-native` | NOT-CACHE | — | React Native Debugger state |
| `.vscode-shared` | NOT-CACHE | — | VS Code shared state |
| `.windsurf` | NOT-CACHE | — | Windsurf IDE: extensions + plans + worktrees — state |
| `.windsurf-next` | NOT-CACHE | — | Windsurf Next IDE: extensions — installed extension state |
| `.yarn` | NOT-CACHE (whole) | — | Mixed: `berry/cache` is safe, `berry/index` is state |
| `.yarn/berry/cache` | CACHE-SAFE | 1,118,964 | Yarn Berry (v2+) package download cache; regenerable via `yarn install` |
| `.zsh_sessions` | NOT-CACHE | — | Zsh terminal session logs |

### Recommended Category C hardcoded subpath list

Based on the classification above, these subpaths are safe to include in Category C (all exist on this machine unless marked):

```
~/.cache/uv                    # 28.8 GB — uv Python cache
~/.cache/puppeteer             # 1.0 GB — Puppeteer browser binaries
~/.cache/chrome-devtools-mcp   # 204 MB — Chrome DevTools MCP cache
~/.cache/node                  # 51 MB — corepack cache
~/.cache/prisma                # 35 MB — Prisma engine cache
~/.cache/mesa_shader_cache     # 2.6 MB — GPU shader cache
~/.cache/pkg                   # 5.6 MB — pkg binary cache
~/.cache/vscode-ripgrep        # 1.4 MB — ripgrep binary cache
~/.cache/gitstatus             # 2.0 MB — gitstatus binary cache
~/.cache/tooling               # 0.3 MB — tooling gradle cache
~/.cache/zed                   # 0 MB — Zed editor cache
~/.bun/install/cache           # 112 MB — Bun package cache
~/.bundle/cache                # 22 MB — Bundler gem cache
~/.gem/specs                   # 33 MB — RubyGems spec index
~/.gluestack/cache             # 320 MB — Gluestack UI package cache
~/.javacpp/cache               # 56 MB — JavaCPP native library cache
~/.lldb/module_cache           # 2.1 GB — LLDB debugger module cache
~/.m2/repository               # 346 MB — Maven local repository
~/.openjfx/cache               # 0.5 MB — OpenJFX native cache
~/.pub-cache/hosted            # 880 MB — Dart/Flutter pub cache
~/.skiko                       # 40 MB — Skiko graphics native cache
~/.yarn/berry/cache            # 1.1 GB — Yarn Berry package cache
~/.hawtjni                     # 0 MB — HawtJNI native cache
~/.android/cache               # 8.5 MB — Android SDK cache (NOT build-cache)
```

**Not included (handled by existing categories):**  
`~/.npm`, `~/.gradle/caches`, `~/.android/build-cache`, `~/.expo/cache`, `~/Library/Caches/pip`

### Estimated ALLOW reclaim from Category C (this machine)

| Subpath | Size (KB) |
|---|---|
| `~/.cache/uv` | 29,538,344 |
| `~/.lldb/module_cache` | 2,138,040 |
| `~/.yarn/berry/cache` | 1,118,964 |
| `~/.pub-cache/hosted` | 901,164 |
| `~/.cache/puppeteer` | 1,025,460 |
| `~/.m2/repository` | 354,256 |
| `~/.gluestack/cache` | 327,364 |
| `~/.bun/install/cache` | 115,020 |
| `~/.cache/chrome-devtools-mcp` | 208,576 |
| `~/.bundle/cache` | 22,640 |
| `~/.gem/specs` | 33,500 |
| `~/.skiko` | 40,760 |
| `~/.javacpp/cache` | 57,212 |
| Others | ~10,000 |
| **Total estimate** | **~35.9 GB** |

---

## Step 4 — Appendix C: Temp Dir Age Distribution (Category B)

### `/tmp`

On this machine, `/tmp` is a symlink to `/private/tmp`. The directory appears to contain no user-owned entries (all entries are owned by root or other system users). Total size is 0 KB for user-owned entries.

```
/tmp total size: 0 KB (user-owned entries: 0)
```

**Interpretation:** `/tmp` is not useful to include for user-targeted cleanup on this machine. The sweep rule (user-owned, `mtime +7`) would find nothing.

### `$TMPDIR` = `/var/folders/8_/qgpj39hn05n838sps0zc9f3m0000gp/T/`

Total size: ~30.9 GB (`du -sk` returns 31,591,040 KB).  
Total user-owned entries at depth 1: 91,787.

**Age distribution (user-owned entries, `find -mindepth 1 -maxdepth 1 -user lion`):**

| Age bucket | Entry count |
|---|---|
| < 1 day | 591 |
| 1–7 days | 6,242 |
| 7–30 days | 4,393 |
| 30–90 days | 6,427 |
| > 90 days | 74,134 |

**Entries older than 7 days:** 84,618 entries, **~25.3 GB**.  
**Entries older than 90 days:** 74,134 entries, **~17.9 GB**.

### Top 10 largest user-owned TMPDIR entries

| Size (KB) | Last modified | Entry name |
|---|---|---|
| 2,794,428 | 2026-05-05 | `B1583171-DA9A-4413-9E42-C94509F53DE3..mov` (screen recording) |
| 2,490,924 | 2026-03-11 | `com.docker.install` (Docker installer artifacts; 57 days old) |
| 278,200 | 2025-06-12 | `jcef-bundle` (JetBrains JCEF browser bundle; ~330 days old) |
| 236,048 | 2026-04-30 | `XcodeDistPipeline.~~~IzATOt` (Xcode distribution pipeline; 7 days old) |
| 236,044 | 2026-04-23 | `XcodeDistPipeline.~~~a9pnHm` (Xcode distribution pipeline; 14 days old) |
| 223,388 | (7d+ ago) | `XcodeDistPipeline.~~~oodBQ4` |
| 222,908 | (7d+ ago) | `XcodeDistPipeline.~~~BcBsnl` |
| 221,812 | (7d+ ago) | `XcodeDistPipeline.~~~uyv3y8` |
| 221,792 | (7d+ ago) | `XcodeDistPipeline.~~~ZCJgZR` |
| 218,780 | (7d+ ago) | `XcodeDistPipeline.~~~mWRAcj` |

**Notable findings:**
- The `.mov` file (2.7 GB) is 2 days old — within the 7-day window, so it would be preserved by the default threshold.
- `com.docker.install` (2.4 GB, 57 days old) would be deleted at 7d threshold.
- `jcef-bundle` (272 MB, ~330 days old) would be deleted at 7d threshold.
- Multiple `XcodeDistPipeline` entries accumulate after App Store submission runs. Most are >7 days old, totaling several GB each submission cycle.

### Threshold recommendation

**Keep the 7-day default.** The data strongly supports it:

1. The age cliff is dramatic: 80,954 entries (88%) are older than 7 days vs. 6,833 (7%) active (< 1 day). There is no natural cliff at a higher threshold that would argue for changing it.
2. The >7d size is ~25.3 GB, nearly the entire TMPDIR. Even at >90d it is ~17.9 GB. Either threshold reclaims substantial space.
3. The 7-day window preserves all genuinely active temp files (< 1 day = 591 entries; 1-7 days = 6,242 entries) while eliminating abandoned artifacts.
4. The `XcodeDistPipeline` entries are the main bulk producer — they accumulate one-per-submission and are never cleaned up automatically.

A 30-day threshold is an acceptable more-conservative alternative (leaves ~7.4 GB behind vs. 7-day). The spec's 7-day default is well-justified.

---

## Summary for Implementation Agent

### Total estimated reclaim (this machine)

| Category | Estimate |
|---|---|
| A — `~/Library/Caches` ALLOW entries | ~14.5 GB |
| B — `$TMPDIR` entries >7 days | ~25.3 GB |
| C — `$HOME` dotfolder cache subpaths | ~35.9 GB |
| **Grand total** | **~75.7 GB** |

Note: Category C total is dominated by `~/.cache/uv` (28.8 GB) and `~/.lldb/module_cache` (2.1 GB). These are safe but large.

### Top 3 items for human review before implementation

1. **`~/.cache/github-copilot` (1.2 GB) — classified NOT-CACHE.** Contains `project-context` and `project-index` directories. These may hold AI-indexed code context that GitHub Copilot rebuilds automatically, making them safe to delete — but this agent conservatively denied them because they could also hold auth-adjacent session state. Human should verify whether GitHub Copilot re-indexes on first use without error.

2. **`Google/` in `~/Library/Caches` — 13.1 GB of Android Studio caches.** Classified as PARTIAL/ALLOW because all known subfolders are IDE build caches. However, the current script design iterates `~/Library/Caches` immediate children, so `Google/` as a single entry would be entirely deleted. Android Studio may have open file locks on these caches if the IDE is running. Consider adding a daemon-check (similar to Gradle's `--stop` pattern) or documenting "close Android Studio before running."

3. **`~/.expo/android-apk-cache` (583 MB) and `~/.expo/ios-simulator-app-cache` (1.4 GB) — classified REVIEW.** These are simulator/device build artifacts under `~/.expo` that are *not* covered by `category_expo_metro` (which only wipes `~/.expo/cache`, not the apk/ipa caches). They are almost certainly safe to delete (EAS/Expo Prebuild regenerates them). But `~/.expo/codesigning` and `~/.expo/state.json` within the same parent must not be touched. If the implementation agent wants to add these as Category C entries, they need explicit approval here.

### REVIEW-tagged paths

| Path | Concern |
|---|---|
| `~/Library/Caches/pnpm` (`dlx/`) | Currently empty; covered by Category A sweep anyway; but should the `pnpm` category in future own this, not Category A? |
| `~/Library/Caches/com.trae.app.ShipIt` | 28 MB is unusually large for a ShipIt dir (normally <1 MB); may contain a staged update binary; conservative DENY is correct but worth verifying |
| `~/Library/Caches/Trae` | 611 MB `update.zip` — this is the pending Trae update binary; deleting would require re-downloading the update. Conservative DENY. |
| `~/.cache/icedtea-web` | 690 MB; Java Web Start cache; likely safe but not common enough to add without owner confirmation |
| `~/.cache/phpactor` | 130 MB; PHP language server cache; safe but tool is niche |
| `~/.net/Updates` | 140 MB; .NET SDK update packages; safe but conservative DENY for now |
| `~/.expo/android-apk-cache`, `~/.expo/ios-simulator-app-cache` | 2 GB combined; likely safe; needs human confirmation |

---

## Final Decisions (authoritative — implementation agent obeys this section)

These resolve the open questions surfaced above. Where this section conflicts with anything earlier in the doc, this section wins.

### A. `~/Library/Caches/Google/` — special-case PARTIAL with running-IDE check

Do NOT delete `Google/` as a whole. Instead, in Category A's iteration, when the child name is exactly `Google` apply a sub-iteration with these rules:

1. Before any deletion under `Google/`, check if Android Studio is running:  
   `pgrep -f '/Applications/Android Studio.app' >/dev/null 2>&1` (or equivalent).
2. If Android Studio is running:
   - Print a loud yellow warning: "Android Studio is running. Close it before clearing its caches; skipping `Google/AndroidStudio*/`."
   - Do **not** touch any `Google/AndroidStudio*` subdir.
   - Still proceed with `Google/Chrome` (Chrome is browser HTTP cache, no IDE-lock concern).
   - Log: `SKIP category=app_caches reason=android_studio_running entry=Google/AndroidStudio*`.
3. If Android Studio is not running:
   - Delete each immediate child of `Google/` whose name matches `AndroidStudio*` (glob).
   - Delete `Google/Chrome`.
   - **Do not** touch any other immediate child of `Google/` — those default to DENY (future-proofing against `Google/Drive`, `Google/Meet`, etc., that may appear later).

This mirrors the gradle daemon pattern (detect-then-warn) and bounds blast radius if Google adds a new app under that prefix later.

### B. Category B (`/tmp` + `$TMPDIR`) — keep 7-day default

No change from spec. Implementation uses `find <parent> -mindepth 1 -maxdepth 1 -user $(id -un) -mtime +7 -exec rm -rf {} +` per parent. `/tmp` will be effectively a no-op on this machine (zero user-owned entries) but include it anyway for portability.

### C. Category C — final hardcoded subpath list

Use this exact list. Each is a hardcoded full subpath; no globbing of `$HOME`.

```
~/.cache/uv
~/.cache/puppeteer
~/.cache/chrome-devtools-mcp
~/.cache/node
~/.cache/prisma
~/.cache/mesa_shader_cache
~/.cache/pkg
~/.cache/vscode-ripgrep
~/.cache/gitstatus
~/.cache/tooling
~/.cache/zed
~/.cache/github-copilot      # INCLUDED per user decision
~/.cache/phpactor            # INCLUDED per user decision (REVIEW item)
~/.bun/install/cache
~/.bundle/cache
~/.gem/specs
~/.gluestack/cache
~/.javacpp/cache
~/.lldb/module_cache
~/.m2/repository
~/.openjfx/cache
~/.pub-cache/hosted
~/.skiko
~/.yarn/berry/cache
~/.hawtjni
~/.android/cache
~/.expo/android-apk-cache    # INCLUDED per user decision (REVIEW item)
~/.expo/ios-simulator-app-cache  # INCLUDED per user decision (REVIEW item)
~/.net/Updates               # INCLUDED per user decision (REVIEW item)
```

**Excluded by user decision:** `~/.cache/icedtea-web` (690 MB; niche tool).

**Excluded by overlap with existing categories:** `~/.npm`, `~/.gradle/caches`, `~/.android/build-cache`, `~/.expo/cache`, `~/Library/Caches/pip`.

### A — final denylist for `~/Library/Caches`

Use this list (literal names). Plus prefix patterns. Anything else is ALLOW by default. Implementation must match Step 2's classifications exactly.

**Literal names to deny:**
```
askpermissiond
chrome_crashpad_handler
CloudKit
com.anthropic.claudefordesktop
Docker Desktop
docker-secrets-engine
eas-cli
FamilyCircle
familycircled
Firefox
GameKit
GeoServices
Homebrew
io.sentry
Mozilla
PassKit
pip
pnpm
SentryCrash
ssu
TemporaryItems
Trae
Viber Media S.à r.l
Yarn
com.microsoft.autoupdate.fba
com.raycast.macos
com.google.GoogleUpdater
com.plausiblelabs.crashreporter.data
com.github.CopilotForXcode
```

**Prefix patterns to deny (glob match on child name):**
```
com.apple.*
*.ShipIt
```

**Special-cased:** `Google` (handled per the rules in section A above).

Everything not matching the above is **ALLOW**. The script trusts the discovery classification and deletes the entire child directory.

