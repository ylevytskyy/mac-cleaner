# macOS System Data Research — Discovery

Status: complete 2026-05-10
Plan-of-record: `docs/superpowers/specs/2026-05-10-system-data-research-design.md`
Implements: backfill for `docs/superpowers/specs/2026-05-10-system-data-categories-design.md`
Output spec: `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md`
Host probed: macOS 26.4.1 (Tahoe), build 25E253; ~/Library = 149 GB; /private/var = 11 GB; root volume 462 GiB free of 926 GiB.

## Methodology

10 hypothesis-driven Sonnet subagents dispatched in parallel (Round 1, six backfill + four extend), with adaptive 5-step review gate, then 4 Round 2 deep-dive agents (mediaanalysisd, wallpaper aerials, JetBrains/Studio logs, pnpm legacy stores). Four evidence sources per agent: local read-only probe of this Mac, Apple official documentation, community sources (Apple Developer Forums, r/MacOS, Eclectic Light, MacRumors, Apple Discussions), and source/tool inspection (man pages, plist payloads, codesign, launchd plists).

Total: 14 Sonnet calls. Synthesis performed in main thread.

---

## Backfill — justifying the 19 implemented categories

### category_coresimulator_caches (H1)
~/Library/Developer/CoreSimulator/Caches — 0 B on this Mac (correctly fires SKIP reason=empty). Apple Developer Forums thread/758703 confirms safe to delete when Simulator not running. Spec design correct.

### category_xctest_xcpg_devices (H1)
~/Library/Developer/XCTestDevices and XCPGDevices — both 0 B on this Mac. Spec Tier 1 #2 sizes both together; design correct.

### category_xcode_dt_cache (H1)
~/Library/Caches/com.apple.dt.Xcode — TCC-denied during read-only probe. du_safe silences stderr → category functionally no-ops on this Mac until TCC granted. Acceptable; xcodebuild sibling cache (com.apple.dt.xcodebuild) is 80 KB.

### category_xcode_device_logs (H1) — **SPEC BUG identified**
**The spec uses path `~/Library/Developer/Xcode/iOS Device Logs` (with space, plural). The actual directory on Tahoe is `~/Library/Developer/Xcode/DeviceLogs` (no space, singular).** The spec path does not exist on this Mac. The category will always SKIP reason=empty silently regardless of actual contents. On this Mac the correct path holds 1.1 MB. **Recommended fix**: update spec Tier 1 #4 path to `DeviceLogs`, or attempt both paths.

### category_swiftpm (H1, H2)
~/Library/Caches/org.swift.swiftpm — 8.5 MB on this Mac. Swift Forums confirms `swift package purge-cache` is the official clear command. Fallback to rm -rf is safe.

### category_clangd_index (H2)
~/.cache/clangd — absent on this Mac (clangd not installed). On dev machines that use clangd it grows into multi-GB. Spec design correct (drop ~/.cache from dev_dotcaches because it's too heterogeneous; clangd gets its own category).

### category_ccache (H2)
~/Library/Caches/ccache — absent on this Mac. mozilla/sccache README confirms 10 GB default cap; same pattern for ccache. Spec design correct.

### category_sccache (H2 — Tier 2 B3)
~/Library/Caches/Mozilla.sccache — absent on this Mac. Bespoke wrapper correct: must `sccache --stop-server` before rm because no built-in clear command exists.

### category_cargo_registry (H2)
~/.cargo/registry — absent on this Mac (cargo not installed). Community sources (thisDaveJ, cargo-cache crate) confirm 4–50 GB sizes on active Rust shops. Cargo 1.84 (Feb 2026) added auto-GC for unreferenced crate sources after 3 months; reduces but does not eliminate growth. Spec design correct (clean both `registry/cache` and `registry/src`; never touch `registry/git` or `bin`).

### category_go_caches (H2)
$(go env GOMODCACHE) and $(go env GOCACHE) — absent on this Mac (go not installed). Tool-derived path approach correct; preferred command `go clean -modcache` avoids raw rm. Spec correctly handles `go env` non-zero exit (SKIP reason=tool_error, no fallback to hardcoded defaults).

### category_composer (H2)
~/Library/Caches/composer — absent on this Mac. `composer clear-cache` is the official clear command.

### category_bazel (H2 — Tier 2 B4)
/private/var/tmp/_bazel_$USER and ~/Library/Caches/bazel — both absent on this Mac. Bespoke wrapper correct (mirrors cleanup_gradle pattern: bazel shutdown + rm + surface partial-failure). Both Bazel 8 and Bazel 9+ paths handled.

### category_container_vms (H3 — Tier 2 B5)
**Confirmed with hard local numbers.** Docker.raw on this Mac: 9.2 GB actual / 60 GB apparent (6.5x sparse ratio, post-prune state). OrbStack/Colima/Lima/Podman not installed. Docker Desktop docs confirm `docker system prune -a` does NOT reclaim host bytes without `docker run --privileged --pid=host docker/desktop-reclaim-space` (fstrim proxy). OrbStack auto-fstrims continuously (key differentiator). Apple Virtualization framework migration in macOS 26 changes VM bootstrap, NOT disk-reclaim semantics. Spec design correct including the `--include-volumes` flag gate.

### category_browser_caches (H4 — Tier 2 B6)
**Confirmed with three identified gap extensions** (see Gap bucket below). Chrome on this Mac: 7.2 GB total. Service Worker CacheStorage 1.3 GB, ScriptCache 47 MB, GPUCache + DawnWebGPUCache + DawnGraphiteCache (per-profile) confirmed in spec leaf list. Firefox cache2: 1.1 GB. Safari container Caches: 0 B (Safari self-managing well on Tahoe per WebKit blog 7-day auto-eviction policy). Arc/Edge/Brave: installed but empty/unused. Arc-specific: maintenance mode since May 2025; Atlassian acquired The Browser Company Sep 2025 ($610M); Chromium security patches continue, no new features. Spec design correct.

### category_apple_music_stream_cache (H6)
~/Library/Caches/com.apple.Music — absent on this Mac (Music never used). Community sources confirm 1–43 GB on active Music users; safe to delete (downloaded songs live in ~/Music/Music/Media, not here). Spec Tier 1 #11 design correct.

### category_mail_downloads (H6)
~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads — absent on this Mac (Mail unused). Setapp guide confirms safe to delete (originals stay in .emlx in ~/Library/Mail; re-extracted on attachment open). Spec Tier 1 #12 design correct.

### category_diagnostic_reports (H5, H10) — **SPEC BUG identified**
~/Library/Logs/DiagnosticReports holds 9 .ips files in `Retired/` (680 KB on this Mac); /Library/Logs/DiagnosticReports holds 5.5 MB. **The spec's reclaim command `rm -f "$path"/*` does NOT recurse into the `Retired/` subfolder** (a Sequoia/Tahoe addition that archives older .ips files). `rm -f` without `-r` removes only top-level files. Recommended fix: change to `rm -rf "$path"/Retired && rm -f "$path"/*.ips` or equivalent. Group-check guard (user `lion` confirmed in `_analyticsusers`) works correctly.

### category_tm_local_snapshots (H5 — Tier 2 B1)
**0 snapshots on this Mac** (TM not configured to a backup destination). Category correctly fires SKIP reason=empty count=0. The SSV seal snapshot (com.apple.os.update-…) visible in `diskutil apfs list` is a sealed-system mechanism, not a TM snapshot, immutable, sudo+SIP to delete. Apple HT102154 confirms 24h retention rule unchanged officially in Tahoe. Eclectic Light "snapshots, the elephant in APFS" (May 10, 2026) confirms no new Tahoe-specific retention changes. Spec design correct.

### category_macos_installers (H5 — Tier 2 B2)
0 stale installers on this Mac. nullglob correctly produces empty array → SKIP reason=empty. Spec design correct (paranoid re-check before rm; literal prefix/suffix exception shape).

---

## Novel sources (Gap bucket)

Five actionable findings, two with full Tier 1 categories proposed, two as extensions to existing categories, one as a guard rail folded into the existing pnpm sweep.

### Proposed category_wallpaper_aerials (H6 + R2-2) — Tier 1
**Why now:** Tahoe migrated aerial storage from /Library/Application Support/com.apple.idleassetsd/Customer/ (Sequoia/Sonoma system-wide) to ~/Library/Application Support/com.apple.wallpaper/aerials/ (per-user). On this Mac: 1.7 GB videos + 7.9 MB thumbnails. Community reports up to 50+ GB orphans across Tahoe minor-version manifest refreshes (Apple Community thread/256139061, MacRumors thread 2465906). Manifest URL confirmed: `https://sylvan.apple.com/itunes-assets/Aerials126/v4/.../resources-26-4-1.tar`.

**Path inclusion (refined in R2-2):**
- INCLUDE: `~/Library/Application Support/com.apple.wallpaper/aerials/videos/` and `aerials/thumbnails/` (1.7 GB local; all Apple-stock UUID-named .mov + .png; manifest preserved as the re-download index).
- DEFER: `~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.image/` (523 MB BMP render cache; all Apple-stock; safe but path-stability across Tahoe minor versions to be confirmed before shipping).
- **PERMANENTLY EXCLUDE: `~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Caches/`** — 100 MB on this Mac, **10 of 41 files contain iPhone 13 Pro EXIF data** (manufacturer=Apple, GPS, datetime=2024:09:28). This caches the user's CUSTOM photo wallpapers; mixed user/stock with no reliable filter.

**Process gate:** `pgrep -x ScreenSaverEngine` only. WallpaperAgent does not hold video files open while idle; KeepAlive auto-restarts it harmlessly.

**Re-download trigger** (from `strings WallpaperAgent`): ChoiceDownloadCoordinator fires on next aerial selection or screensaver activation; manifest re-fetches via AerialActivityScheduler.

### Proposed category_android_studio_logs (H10 + R2-3) — Tier 1
**Why now:** Android Studio creates a per-version log dir under ~/Library/Logs/Google/ at every minor version and never prunes old ones. On this Mac: 781 MB across 8 version subdirs (one active, seven stale).

**Paths (both hardcoded):**
- `~/Library/Logs/Google/` (781 MB primary; all Android Studio — confirmed no other Google product writes here on this Mac)
- `~/Library/Logs/JetBrains/` (208 KB AppCode 2023.1 relic from uninstalled product; auto-cleanup failed because product was uninstalled before next-version upgrade)

**Process gate:** `pgrep -f "Android Studio.app"` (NOT `pgrep -x studio` — launcher exits after spawning JVM; JVM has app path in classpath, so `-f` is required).

**Regen safety:** JetBrains official docs endorse log dirs as fully ephemeral; IDE does not read idea.log on startup (crash recovery uses restarter.log + JVM dumps in /private/var/folders/, not idea.log parsing).

**Other ~/Library/Logs/ candidates rejected** (R2-3): CoreSimulator (57 MB, UUID-by-device, needs simctl context), GitHubCopilot (30 MB, active write handle, below threshold), Claude (22 MB, below threshold). No vendor dir matches the multi-version-stale pattern except Google.

### Proposed category_intelligence_platform (H7) — Tier 1
**Why now:** New in macOS Tahoe 26.0; expanded across point releases. The directory contains the Apple Intelligence knowledge graph (`globalKnowledge.db` 49 MB), entity relevance index, and per-locale inference artifacts (siri 9.3 MB, visualIdentifier 6.7 MB, internal 11 MB, entityRelevance 2.6 MB). On this Mac: 108 MB total. Community/Nektony reports indicate growth correlates with Apple Intelligence usage and 26.1's 15-language expansion.

**Path:** `~/Library/IntelligencePlatform/` (single hardcoded absolute path).

**Reclaim:** `rm -rf "$HOME/Library/IntelligencePlatform"/*`. Daemon `intelligenceplatformd` recreates it within hours from on-device content.

**Process gate:** `pkill -x intelligenceplatformd || true` to release WAL files; macOS relaunches the daemon automatically.

**Distinguishes from rejected**: ~/Library/LanguageModeling/ (1.2 MB, keyboard/autocorrect personalization — USER DATA), ~/Library/Application Support/Knowledge/knowledgeC.db (USER DATA — Siri/Screen Time/AI personalization), AI cryptex weights at /System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_* (8–13 GB, SIP-sealed read-only volumes).

### Browser cache extensions (H4 + H8) — extend existing category_browser_caches (B6)

Three additive changes to the existing browser_caches Tier 2 B6:

**a. Chromium top-level shader caches.** After the per-profile loop, also delete (per Chromium browser): `$top/GrShaderCache`, `$top/GraphiteDawnCache`, `$top/ShaderCache`. Three hardcoded leaf names at the top level (not per-profile). On this Mac: ~20 MB total in Chrome's `~/Library/Application Support/Google/Chrome/`. Chromium gr_shader_cache.cc source confirms top-level location and full regenerability. Hundreds of MB on heavy WebGL/WebGPU dev machines. Same exception shape (literal-allowlist of leaf names under hardcoded top-level path) as existing B6; simpler than the existing per-profile leaves.

**b. Firefox `startupCache`.** Add `startupCache` to the Firefox leaf list alongside `cache2`. Compiled XUL/JS startup bytecode; regenerates every Firefox launch. 19 MB on this Mac.

**c. Slack as a 7th browser-class app.** Slack 5.x stores its Chromium cache under `~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/`. Same Chromium leaf list as existing B6 entries (`Cache`, `Code Cache`, `GPUCache`, `Service Worker/CacheStorage`, `Service Worker/ScriptCache`, `DawnGraphiteCache`, `DawnWebGPUCache`). On this Mac: 597 MB combined. Slack itself officially recommends the Cache and Service Worker dirs as safe to clear when Slack is closed. Single profile (no profile iteration). Process gate: `pgrep -f "/Applications/Slack.app"`. **Fits B6's third documented exception shape** (allowlist-profile + hardcoded-leaf) without inventing anything new.

### pnpm v3 orphan guard (H2 + R2-4) — fold into existing pnpm sweep, NOT a new category
**Why now:** pnpm 10 (October 2025) introduced the v11 store format. On machines that previously used pnpm 5–8 (which stored at `~/Library/pnpm/store/v3`), the v3 directory becomes permanently orphaned: pnpm ≥9 cannot read it; `pnpm store prune` does not touch it. On this Mac: **1.2 GB orphaned v3 store**, last touched 2024-07-28, 72,762 content-addressable files.

**Generalization rejected** (R2-4): No other tool investigated has the same multi-version top-level orphan pattern. Yarn Classic v6 stable since 1.0; Yarn Berry doesn't share Classic's cache; npm `_cacache` format-stable since npm 5; deno/bun/pip/uv all use single-top-level cache; cargo registry already covered; rustup toolchains are runtime targets, not caches. pnpm is structurally unique.

**Implementation:** add a guard rail to the existing pnpm category function (not a new category). Hardcoded `$HOME/Library/pnpm/store/v3` path with `active_store != v3_path` safety check via `pnpm store path`. The v10 empty skeleton (0 bytes) can be left alone or cleaned by extending the same guard.

### Spec extension that IS NOT a category: README note for Chrome OptGuideOnDeviceModel (H4)
Chrome silently downloads ~4 GB Gemini Nano AI weights to `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/` (filename `weights.bin`). Confirmed 4.0 GB on this Mac in path `OptGuideOnDeviceModel/2025.8.11.1/weights.bin`. Documented widely in May 2026 (PCWorld, Android Authority). **Not a category candidate** because deletion forces immediate re-download unless the Chrome flag `chrome://flags/#optimization-guide-on-device-model` or Settings → System → On-device AI is disabled. mac-cleaner does not modify browser application settings. README addition only — recommend telling users to toggle the setting in Chrome themselves if they want to reclaim this 4 GB.

---

## May 2026: why now

Ranked by impact on dev-machine System Data growth:

1. **Apple Intelligence + AI cryptexes** (8–13 GB, growing per release). 23 Revival cryptexes in 26.0; 28 in 26.2 (+10 new, −5 removed); growing further through 26.3–26.4.1. macOS 15.4 added an explicit "Apple Intelligence" row in Storage Settings — before that, this 8–13 GB was silently in System Data, explaining the post-15.1 mysterious growth users noticed. **Out of scope** (SIP-sealed read-only cryptex volumes; reclaim requires disabling Apple Intelligence in Settings).
2. **`com.apple.mediaanalysisd` Photos re-analysis bug** (15–140 GB on affected machines). Originated Sequoia 15.1 with the Apple Intelligence Photos analysis revamp; persists into Tahoe 26.x and was NOT fully fixed as of May 2026. The runaway growth lives primarily inside `~/Pictures/Photos Library.photoslibrary/private/com.apple.mediaanalysisd/` — already correctly out-of-scope per existing spec rejection of Photos library internals. **In-scope-deferred** for the container path alone, blocked on (a) field reports of stale e5bundlecache build-dir growth, (b) a 4th safety-rule exception shape for "hardcoded parent + dynamic-build-version-exclusion", and (c) evidence that the daemon does not re-acquire PFScene index file locks within the 5-second `launchctl kill TERM` window. On this Mac: 285 MB (well-behaved).
3. **Wallpaper aerial path migration** (Sequoia/Sonoma → Tahoe; up to 50+ GB community-reported orphans). Tahoe moved aerial storage from system-wide `/Library/Application Support/com.apple.idleassetsd/Customer/` to per-user `~/Library/Application Support/com.apple.wallpaper/aerials/`. Some upgraded machines retain both paths; the system-wide legacy path is empty on this Mac (post-migration GC succeeded) but root-owned (sudo-required, out-of-scope regardless). **The new per-user path becomes a Gap-bucket category.**
4. **Apple Intelligence language pack expansion (Tahoe 26.1, late 2025)**. 15 NEW languages added (Da, Nl, Fr, De, It, No, Pt, Es, Sv, Tr, zh-CN/TW, Ja, Ko, Vi). Per-language UAF model adapters and ANE bundle caches. First major post-launch storage expansion. Contributes to both cryptex growth (out-of-scope) and IntelligencePlatform Artifacts/ growth (in-scope-new).
5. **Chrome's Gemini Nano silent download** (Chrome 127+, present on most Chrome 130+ installs by May 2026; ~4 GB). Out of scope for the tool but README-documented.
6. **pnpm 10 release (October 2025)**. Introduced v11 store format, permanently orphaning machines' v3 stores from prior pnpm 5–8 use. **In-scope-new** as a guard rail folded into the existing pnpm sweep.
7. **Tahoe diagnostic format additions**. The `Retired/` subfolder for `.ips` crash reports (Sequoia/Tahoe addition) is currently NOT cleaned by the existing `category_diagnostic_reports` reclaim command — **spec bug identified**.
8. **Tahoe Xcode path rename**. `iOS Device Logs` → `DeviceLogs` (no space, singular). The existing `category_xcode_device_logs` silently no-ops on Tahoe — **spec bug identified**.
9. **APFS purgeable space** (31.8 GB on this Mac; up to 80–100 GB on heavy iCloud/Photos machines). Out of scope (macOS auto-reclaims; no user CLI without sudo) but the README needs to honestly explain this gap so users stop chasing phantom System Data.

---

## Out of scope (with reasons; mirrors existing spec's "Out of scope" pattern so future contributors don't re-litigate)

- **Apple Intelligence cryptex model weights** (`/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*`, 8–13 GB): SIP-sealed read-only cryptex volumes. Reclaim requires disabling Apple Intelligence in System Settings + Apple-controlled removal — not scriptable.
- **`com.apple.mediaanalysisd` container cache** (in-scope-deferred): the only theoretically reclaimable piece (stale e5bundlecache directories whose name ≠ current `sw_vers -buildVersion`) requires a NEW 4th safety-rule exception shape ("hardcoded parent + immediate children + dynamically-computed exclusion via trusted tool"). Not allowed without a CLAUDE.md amendment. On this Mac: 0 stale build dirs (nothing to reclaim today).
- **Photos library internals** including `~/Pictures/Photos Library.photoslibrary/private/com.apple.mediaanalysisd/`: already rejected by existing spec; reaffirmed by R2-1 evidence.
- **Apple Intelligence behavioral state stores** (~/Library/Biome 296 MB, ~/Library/DuetExpertCenter 336 MB, ~/Library/Application Support/Knowledge/knowledgeC.db 14 MB, ~/Library/LanguageModeling 1.2 MB, ~/Library/Assistant 3.4 MB): USER DATA, not regenerable caches. Deletion loses Siri/Screen Time/AI personalization with no recovery.
- **Group Containers** (~/Library/Group Containers/*): all top-5-by-size on this Mac (WhatsApp 2.8 GB, Telegram 248 MB, Notes 238 MB, UserNotifications 228 MB, Teams group 217 MB) have **0 bytes in their `Library/Caches` subdir** — bulk is irreplaceable user data (message DBs, account data, media). No safe reclaim found.
- **Microsoft Teams 2.x sandbox cache** (~/Library/Containers/com.microsoft.teams2/, 1.4 GB on this Mac): Cache leaves and persistent state (WebStorage 551 MB IndexedDB 193 MB Cookies/Login Data) interleaved in same WebView2 profile. Pure-cache leaves only ~50–80 MB; deletion of the storage leaves signs the user out of Teams. Risk-to-reward poor. Out of scope.
- **Apple TV+, Podcasts, News+ download caches**: all containers + group containers tiny on this Mac (32 KB to 668 KB). Mac apps don't support offline downloads at scale. Not material.
- **iWork app caches** (Pages/Numbers/Keynote): containers absent or tiny on this Mac. No AI-generated content cache found persistent in user-clearable location on Tahoe 26.4.1.
- **Wallpaper image cache Path C** (~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Caches/, 100 MB on this Mac): contains user iPhone photos (10 of 41 files have iPhone 13 Pro EXIF). Mixed user/stock with no reliable filter — would risk deleting cached versions of user's chosen photo wallpapers.
- **Wallpaper agent BMP render cache Path B** (~/Library/Containers/com.apple.wallpaper.agent/.../extension-com.apple.wallpaper.extension.image, 523 MB): Apple stock only, fully regenerable, no user contamination — but **deferred** until path stability across Tahoe minor versions is confirmed.
- **Legacy aerial path** (/Library/Application Support/com.apple.idleassetsd/Customer/): root:admin owned, sudo-required to delete. Empty on this Mac (post-Tahoe migration GC succeeded). Out of scope on the no-sudo rule and moot here.
- **APFS purgeable space** (31.8 GB on this Mac; up to 80–100 GB on heavy iCloud/Photos): macOS auto-reclaims under storage pressure. No unprivileged CLI to force purge without `brctl evict` per-file (violates no-dynamic-path).
- **Sealed system volume** (12.6 GB), **Preboot** (9.0 GB), **Recovery** (1.3 GB), **VM/swap** (9.7 GB on this Mac): SIP-protected and/or root-owned. macOS-managed; no user-action reclaim path.
- **FileVault overhead**: zero (in-place block-level encryption). Preboot 9 GB holds the FV unlock mechanism — only FV-specific cost, already counted in Preboot bucket.
- **Spotlight index** (~/Library/Metadata/CoreSpotlight, 563 MB on this Mac): `mdutil -E /` is user-clearable but triggers immediate full rebuild → same space, plus search broken during rebuild. Disruptive, not durable, not a cache (it IS the index).
- **Unified Log + symbolication** (/private/var/db/diagnostics 2.4 GB, /private/var/db/uuidtext 618 MB, /private/var/db/systemstats 126 MB, /private/var/db/powerlog 99 MB on this Mac): all root-owned, sudo-required. logd self-manages diagnostics ~520 MB typical; `log erase --all` requires root.
- **Background daemon state caches** (callintelligenced, geoanalyticsd, corespeechd, etc.): tiny on this Mac (KB–MB range). Most are user-personalized inference state (not cache); the rest are sudo-gated. Speech models live under /private/var/MobileAsset/AssetsV2 (sudo + SIP).
- **`bird` / CloudKit caches**: already rejected in existing spec; confirmed by H10 (~/Library/Application Support/CloudDocs only 11 MB on this Mac).
- **Maccy clipboard history DB, Photos `photolibraryd` Library data**: USER DATA, not cache.
- **iOS DeviceSupport, unused simulator runtimes, Xcode `*DeviceSupport` directories**: already rejected per user preference (needs them for old iPhones/Watches). Reaffirmed by H1 (27.9 GB simulator runtimes + 19 GB iOS DeviceSupport on this Mac).
- **AppleIntelligenceReporting / siri.inference / DiagnosticPipeline state**: tiny (KB to a few MB) and either sudo-gated or user data.

---

## Open questions (carried forward for future research)

1. **mediaanalysisd stale-build-dir cleanup** — would require a 4th safety-rule exception shape ("hardcoded parent + dynamically-computed exclusion via trusted tool like `sw_vers -buildVersion`"). Field reports needed to confirm whether this growth pattern is material in the wild. If so, propose the shape amendment as a separate spec change.
2. **Wallpaper Path B (BMP render cache, 523 MB)** — confirm path stability across Tahoe minor versions (26.0 → 26.5+) before shipping as part of category_wallpaper_aerials.
3. **JetBrains companion gate** — if the user installs IntelliJ/WebStorm/PyCharm/etc., the category_android_studio_logs gate needs extension to add their per-app `pgrep -f` checks. Defer until at least one is installed.
4. **Wallpaper aerial within-Tahoe orphan accumulation** — manifest tar is versioned per OS minor (26.0, 26.1, 26.4.1...). Old downloaded videos whose UUIDs no longer appear in the new manifest may become orphans. Frequency depends on Apple CDN's manifest rotation cadence; could be checked by comparing successive manifest.source URLs over time.
5. **Citation conflict** — Apple HT102154 says 24-hour TM snapshot retention rule unchanged in Tahoe; Apple Discussions thread/256077943 reports more aggressive snapshot creation under low-free-space. Both can be true (creation rate vs. retention ceiling are different metrics). No action needed; documented as informational.

---

## Personal findings (this Mac)

Round 2 surfaced one machine-specific discrepancy worth noting separately from general findings:

- **Wallpaper Path C contains iPhone 13 Pro photos** (10 of 41 files, GPS-tagged, datetime 2024-09-28). This is the user's CUSTOM photo wallpapers cached at display resolution. It demonstrates concretely that ~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Caches/ is NOT a pure cache and would risk user-data deletion on any machine where the user has set a custom photo wallpaper. Excluded permanently from category_wallpaper_aerials regardless of size.

No other machine-specific findings warrant separation from general findings.
