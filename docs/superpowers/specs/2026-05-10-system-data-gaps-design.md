# System Data Gap Categories — Design

Status: draft 2026-05-10
Supersedes: nothing — extends `2026-05-10-system-data-categories-design.md` with novel sources surfaced by `docs/superpowers/discovery/2026-05-10-system-data-research.md`.

## Goal

Add 3 new categories and 3 extensions to existing categories in `mac-cleaner.sh`, plus 1 guard rail in the existing pnpm sweep, plus 2 spec-bug fixes for currently-implemented categories. All additions are evidence-backed by the May 2026 research cycle and pass the no-dynamic-path safety audit using only existing exception shapes (no new exceptions required).

## Scope

Three new Tier 1 categories (no Tier 2 needed — all proposals fit `run_category` shape):

1. `category_wallpaper_aerials` — Tahoe per-user aerial videos + thumbnails (1.7 GB on the probe machine; up to 50+ GB community-reported).
2. `category_android_studio_logs` — Android Studio + JetBrains IDE log accumulation across versions (781 MB on the probe machine).
3. `category_intelligence_platform` — Apple Intelligence knowledge graph + entity index + per-locale inference artifacts (108 MB on the probe machine; growing per Tahoe minor release).

Three extensions to existing `category_browser_caches` (Tier 2 B6):

- Chromium top-level shader caches (3 hardcoded leaf names per browser).
- Firefox `startupCache` leaf addition.
- Slack as a 7th browser-class app.

One guard rail folded into the existing pnpm category (NOT a new category):

- pnpm v3 legacy store orphan (`~/Library/pnpm/store/v3`, 1.2 GB on the probe machine).

Two spec-bug fixes:

- `category_xcode_device_logs` path: `iOS Device Logs` → `DeviceLogs` (Tahoe rename).
- `category_diagnostic_reports` reclaim command: add recursive removal of the `Retired/` subfolder (Sequoia/Tahoe addition).

One README addition (no script change):

- Honest "what mac-cleaner cannot reclaim" section explaining APFS purgeable / sealed / Preboot / Recovery / VM-swap / FileVault.
- Chrome's silent ~4 GB Gemini Nano `OptGuideOnDeviceModel` weights — recommend the user toggle the Chrome setting themselves.

## Out of scope (re-affirms discovery-doc rejections so future contributors don't re-litigate)

All items in the discovery doc's "Out of scope" section. The most consequential ones to call out here, where they directly compete with proposals in this spec:

- **`com.apple.mediaanalysisd` container cache** (DEFERRED, not rejected). Proposing it would require a NEW 4th safety-rule exception shape ("hardcoded parent + immediate children + dynamically-computed exclusion via trusted tool like `sw_vers -buildVersion`"). Not allowed without a CLAUDE.md amendment; not warranted now since 0 stale build dirs exist on the probe machine. Re-evaluate when field reports of stale `e5bundlecache/` accumulation appear.
- **Wallpaper Path C** (`~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Caches/`): contains user iPhone photos (10 of 41 files have iPhone 13 Pro EXIF data on the probe machine). Excluded permanently from `category_wallpaper_aerials`.
- **Wallpaper Path B** (`~/Library/Containers/com.apple.wallpaper.agent/.../extension-com.apple.wallpaper.extension.image/`, 523 MB BMP render cache): all Apple-stock content but path stability across Tahoe minor versions not yet confirmed. Deferred — not included in this spec; revisit after observation across two Tahoe minor releases.
- **Microsoft Teams 2.x sandbox cache**: cache leaves and persistent IndexedDB/WebStorage are interleaved in the same WebView2 profile; pure-cache leaves are only ~50–80 MB; deletion of storage signs the user out. Risk-to-reward poor; not added to B6.
- **Apple Intelligence cryptex weights** (8–13 GB): SIP-sealed read-only volumes; reclaim requires Settings toggle + Apple-controlled removal. Out of scope.
- **APFS purgeable / sealed system volume / Preboot / Recovery / VM swap**: README addition only, no category.

## Reconciliation with existing categories

Cross-referenced against every category in `2026-05-10-system-data-categories-design.md`:

- **`category_browser_caches`** — extended in three ways (Chromium top-level shader caches, Firefox `startupCache`, Slack). All extensions fit the existing third documented exception shape (allowlist-profile + hardcoded-leaf). No new exception shape required.
- **`category_xcode_device_logs`** — path correction: spec uses `~/Library/Developer/Xcode/iOS Device Logs` (with space, plural); actual Tahoe path is `~/Library/Developer/Xcode/DeviceLogs` (no space, singular). Update path constant; no shape change.
- **`category_diagnostic_reports`** — reclaim command adjustment: current `rm -f "$path"/*` does not recurse into the `Retired/` subfolder. Update to delete `Retired/` recursively in addition to top-level `.ips` files.
- **pnpm sweep** (existing `--prepare-for-pnpm` block) — guard rail addition: detect `~/Library/pnpm/store/v3` and offer to delete if active store is something else.
- All other existing categories (CoreSimulator, swiftpm, ccache, sccache, clangd, cargo, go, composer, bazel, gradle, npm, nvm, brew, container_vms, tm_local_snapshots, macos_installers, apple_music_stream_cache, mail_downloads, app_caches, temp, dev_dotcaches): no overlap with new categories.

## Tier 1 categories

Numbering is local to this spec, not the script.

| # | Category fn | Path (hardcoded) | Reclaim command | Notes |
|---|---|---|---|---|
| G1 | `category_intelligence_platform` | `~/Library/IntelligencePlatform` | `pkill -x intelligenceplatformd; rm -rf "$path"/*` | macOS relaunches daemon automatically; recreated within hours |
| G2 | `category_wallpaper_aerials` | `~/Library/Application Support/com.apple.wallpaper/aerials/videos` and `aerials/thumbnails` | `rm -rf` of each subdir individually | Skip if `pgrep -x ScreenSaverEngine`; preserve `aerials/manifest/` (the re-download index) |
| G3 | `category_android_studio_logs` | `~/Library/Logs/Google` and `~/Library/Logs/JetBrains` | `rm -rf` of each | Skip if `pgrep -f "Android Studio.app"` |

### G1. `category_intelligence_platform` — Apple Intelligence knowledge graph + artifacts

**Why:** New in macOS Tahoe 26.x. On the probe machine: 108 MB total (`globalKnowledge.db` 49 MB; `Artifacts/` 43 MB with siri 9.3 MB / visualIdentifier 6.7 MB / internal 11 MB / entityRelevance 2.6 MB). Growth correlates with Apple Intelligence usage and 26.1's 15-language expansion.

**Shape:**
```
have_path "$HOME/Library/IntelligencePlatform" || SKIP reason=empty
size = du_safe "$HOME/Library/IntelligencePlatform"
[ size -eq 0 ] → SKIP reason=empty
print warning: "Apple Intelligence knowledge graph + per-locale inference artifacts.
  Daemon re-creates from on-device content within hours.
  Siri / Spotlight suggestions / Apple Intelligence routing continue working;
  may be slightly less personalized for the first few hours."
prompt y/N (skipped under --yes)
run_cmd "stop intelligence platform daemon" pkill -x intelligenceplatformd  # || true; macOS relaunches
run_cmd "remove intelligence platform" rm -rf "$HOME/Library/IntelligencePlatform"/*
```

**Tool detection:** none. Path-existence check only.

**Running-process gate:** `pkill -x intelligenceplatformd` (release WAL files; macOS auto-relaunches the daemon). **Same precedent as `cleanup_gradle`'s daemon-stop pattern** for daemons the user does not interact with directly.

**Safety-rule fit:** Single hardcoded absolute path. No iteration, no dynamic construction. Baseline rule — no exception shape needed.

**Distinguishes from rejected**: `~/Library/LanguageModeling/` (USER DATA: keyboard learning), `~/Library/Application Support/Knowledge/knowledgeC.db` (USER DATA: Siri/Screen Time/AI personalization), AI cryptex weights at `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*` (SIP-sealed, out of scope per the discovery doc).

### G2. `category_wallpaper_aerials` — Tahoe per-user aerial videos + thumbnails

**Why:** Tahoe migrated aerial storage from `/Library/Application Support/com.apple.idleassetsd/Customer/` (Sequoia/Sonoma system-wide, sudo-required and now empty post-migration) to `~/Library/Application Support/com.apple.wallpaper/aerials/` (per-user, user-clearable). On the probe machine: 1.7 GB videos (5 × .mov, all Apple-stock UUID-named) + 7.9 MB thumbnails. Community reports up to 50+ GB orphans across Tahoe minor-version manifest refreshes.

**Shape:**
```
pgrep -x ScreenSaverEngine >/dev/null && SKIP reason=screensaver_running
videos="$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos"
thumbs="$HOME/Library/Application Support/com.apple.wallpaper/aerials/thumbnails"
size = du_safe "$videos" + du_safe "$thumbs"
[ size -eq 0 ] → SKIP reason=empty
print warning: "Removes downloaded aerial wallpaper videos and thumbnails.
  Re-downloads automatically on next screensaver activation (requires internet).
  The manifest index is preserved — only video and thumbnail files are removed."
prompt y/N (skipped under --yes)
run_cmd "remove aerial videos" rm -rf "$videos"
run_cmd "remove aerial thumbnails" rm -rf "$thumbs"
```

**Tool detection:** none. Path existence handled inline.

**Running-process gate:** `pgrep -x ScreenSaverEngine` (skip if screensaver is actively playing — file handle on a video would be held open). WallpaperAgent itself does NOT need stopping; KeepAlive auto-restarts and the daemon does not hold video files open while idle.

**CRITICAL — preserve manifest:** Do NOT delete `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/`. The `manifest.tar` and `entries.json` are the index WallpaperAgent uses to re-download. Removing them would leave the daemon confused.

**Safety-rule fit:** Two hardcoded absolute paths. No iteration of children. Baseline rule — no exception shape needed.

**User warning text** is intentionally specific about the re-download behavior so the user is not surprised when the screensaver later pulls over the network.

### G3. `category_android_studio_logs` — Android Studio + JetBrains IDE logs (all versions)

**Why:** Android Studio creates a per-version log directory under `~/Library/Logs/Google/` at every minor version and never prunes old ones. On the probe machine: 781 MB across 8 version subdirs (1 active, 7 stale spanning 2025-11 to 2026-05). JetBrains companion path (`~/Library/Logs/JetBrains/`) on the probe machine holds a 208 KB AppCode 2023.1 relic from an uninstalled product (auto-cleanup failed because the product was uninstalled before the next-version upgrade triggered cleanup).

**Shape:**
```
pgrep -f "Android Studio.app" >/dev/null && SKIP reason=app_running app=AndroidStudio
google="$HOME/Library/Logs/Google"
jetbrains="$HOME/Library/Logs/JetBrains"
size = du_safe "$google"   # JetBrains is rounding error; size header reflects Google only
[ size -eq 0 ] && [ ! -d "$jetbrains" ] → SKIP reason=empty
print warning: "Android Studio and JetBrains IDE log directories.
  All versions, including stale ones from older IDE versions.
  Each IDE recreates its log dir on next launch."
prompt y/N (skipped under --yes)
run_cmd "remove Android Studio log history" rm -rf "$google"
run_cmd "remove JetBrains log history" rm -rf "$jetbrains"
```

**Tool detection:** none.

**Running-process gate:** `pgrep -f "Android Studio.app"` (NOT `pgrep -x studio` — the launcher binary `studio` exits after spawning the JVM; the JVM has the app path in its classpath, so `-f` is required). **Same gate pattern as `category_browser_caches`'s app-running gate.**

**JetBrains companion gate:** None added by default — no JetBrains IDEs are installed on the probe machine. If the user installs IntelliJ IDEA / WebStorm / PyCharm / GoLand / CLion / Rider / DataGrip / RubyMine / etc. in the future, extend the gate with additional `pgrep -f "<App>.app"` checks before touching `~/Library/Logs/JetBrains`. Defer that work until at least one is installed.

**Safety-rule fit:** Two hardcoded absolute paths. No iteration of children. Baseline rule — no exception shape needed.

**Run-order placement:** Insert after `category_diagnostic_reports` (existing Tier 1 #13) — both are log-domain categories; belongs in the user-app block (position 6 in the parent spec's run order).

## Extensions to `category_browser_caches` (Tier 2 B6)

Three additive changes. None require a new exception shape.

### E1. Chromium top-level shader caches

After the per-profile loop completes for each Chromium browser (Chrome, Arc, Edge, Brave), also delete (per browser):

- `$top/GrShaderCache` — Skia GPU shader cache
- `$top/GraphiteDawnCache` — Skia Graphite GPU cache
- `$top/ShaderCache` — WebGL shader cache

Where `$top` is the existing hardcoded per-browser top-level path (e.g., `~/Library/Application Support/Google/Chrome` for Chrome). Three hardcoded leaf names at the top level, NOT per-profile. On the probe machine: ~20 MB total in Chrome. Hundreds of MB on heavy WebGL/WebGPU dev machines per Chromium issue tracker.

**Source:** Chromium `gr_shader_cache.cc` confirms top-level (not per-profile) location and full regenerability.

**Safety-rule fit:** Hardcoded leaf names under hardcoded top-level path. Same exception shape as B6's existing per-profile leaf list, simpler (no profile iteration). No widening.

### E2. Firefox `startupCache` leaf

Add `startupCache` to the Firefox leaf list alongside `cache2`. Same profile iteration already in place; one additional hardcoded leaf name. On the probe machine: 19 MB. Regen risk: zero — regenerated on every Firefox launch.

### E3. Slack as a 7th browser-class app

Slack 5.x stores its Chromium cache under `~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/`. Same Chromium leaf list as existing Chromium browsers in B6 (`Cache`, `Code Cache`, `GPUCache`, `Service Worker/CacheStorage`, `Service Worker/ScriptCache`, `DawnGraphiteCache`, `DawnWebGPUCache`). On the probe machine: 597 MB combined (Cache 170 MB + Service Worker 427 MB).

```
top="$HOME/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack"
[[ -d "$top" ]] || skip reason=tool_not_installed
pgrep -f "/Applications/Slack.app" >/dev/null && skip reason=app_running app=Slack
for leaf in Cache "Code Cache" GPUCache "Service Worker" DawnGraphiteCache DawnWebGPUCache; do
  target="$top/$leaf"
  [[ -d "$target" ]] || continue
  run_cmd "remove $target" rm -rf "$target"
done
```

(The `Service Worker` leaf is treated as a single sub-tree; deletion sweeps both `CacheStorage` and `ScriptCache` together. Same pattern Slack itself recommends.)

**Source:** Slack's official help page recommends quitting Slack and deleting `~/Library/Application Support/Slack/Cache` to clear cache.

**Safety-rule fit:** Hardcoded full top-level path; single profile (no iteration); same hardcoded leaf list as existing B6 entries. **Fits B6's third documented exception shape (allowlist-profile + hardcoded-leaf)** — it is structurally a single-profile case of that shape. No widening.

## Guard rails (NOT new categories)

### pnpm v3 orphan store

Add to the existing pnpm category function (the one tied to the `--prepare-for-pnpm` flag and the nvm/brew sweep). On the probe machine: 1.2 GB orphan at `~/Library/pnpm/store/v3` (last touched 2024-07-28; 72,762 content-addressable files). pnpm 10 (October 2025) introduced the v11 format; pnpm ≥9 cannot read v3.

```
v3="$HOME/Library/pnpm/store/v3"
if [[ -d "$v3" ]]; then
  active=$(pnpm store path 2>/dev/null || true)
  if [[ "$active" != "$v3" ]]; then
    size=$(du_safe "$v3")
    if (( size > 0 )); then
      print_size "pnpm legacy v3 store (orphaned)" "$size"
      prompt_or_yes "Remove orphaned pnpm v3 store?" || { log DECLINE; return 0; }
      run_cmd "remove pnpm v3 store" rm -rf "$v3"
    fi
  fi
fi
```

Three safety guards:
1. Path is hardcoded (`$HOME/Library/pnpm/store/v3`).
2. The `active != v3` check protects against accidentally deleting an active v3 store on a hypothetical machine still running pnpm 5–8.
3. Size check skips if the dir is somehow already empty.

**Generalization rejected.** R2-4 confirmed pnpm is structurally unique among investigated tools (yarn, npm, deno, bun, pip, uv, poetry, rubygems, go, rustup, homebrew downloads): no other tool creates multi-version top-level orphan store directories. Folding into existing pnpm category, not a new category.

## Spec-bug fixes (existing categories)

### S1. `category_xcode_device_logs` path

Current path constant: `~/Library/Developer/Xcode/iOS Device Logs` (with space, plural).
Actual Tahoe path: `~/Library/Developer/Xcode/DeviceLogs` (no space, singular).

Effect of bug: `du_safe` returns 0 on the wrong path → category fires `SKIP reason=empty` silently regardless of actual contents. On the probe machine the correct path holds 1.1 MB.

**Fix:** Update Tier 1 #4 path in the parent spec to `DeviceLogs`. Optionally also probe the legacy path (`iOS Device Logs`) to handle Sequoia/older systems gracefully — but for current macOS 26.x, `DeviceLogs` is the only correct path.

### S2. `category_diagnostic_reports` reclaim command

Current command: `rm -f "$path"/*`.
Bug: this deletes top-level files but does NOT recurse into the `Retired/` subfolder (a Sequoia/Tahoe addition that archives older `.ips` files). The `Retired/` directory entry is matched by `*` but `rm -f` without `-r` does not descend into it; the directory and its contents are left behind.

**Fix:** Replace with `rm -rf "$path"/Retired` followed by `rm -f "$path"/*.ips`. Or equivalently `rm -rf "$path"/Retired "$path"/*.ips` (zsh handles the glob and the literal subdir together; if `Retired/` is absent the `-rf` is a no-op).

Both system path (`/Library/Logs/DiagnosticReports`) and user path (`~/Library/Logs/DiagnosticReports`) need the same fix. Group-check guard for the system path remains unchanged.

## README additions (no script change)

Two paragraphs to add to `README.md` under a new "What mac-cleaner cannot reclaim" section:

1. **APFS purgeable / sealed / Preboot / Recovery / VM-swap / FileVault.** Verbatim text drafted in H9 of the discovery doc:
   > **APFS purgeable space (~10–80 GB on heavy iCloud/Photos machines):** macOS marks iCloud-synced local copies and Photos derivatives as "purgeable." These appear in `diskutil info` CapacityInUse but not `df` "used." macOS reclaims them automatically under storage pressure. No user CLI can force this without sudo.
   >
   > **System volume (~12–15 GB), Preboot (~9 GB), Recovery (~1–2 GB):** macOS's sealed read-only OS partition and firmware support volumes. SIP-protected.
   >
   > **VM/swap (varies):** Root-owned swap files in `/System/Volumes/VM`. Only a reboot reduces them.
   >
   > **FileVault:** Adds no storage overhead — encryption is in-place at the block level.
   >
   > **APFS local snapshots:** Covered by the "Time Machine snapshots" category if you have TM configured.

2. **Chrome's Gemini Nano AI weights** (~4 GB):
   > Chrome silently downloads a ~4 GB Gemini Nano AI model to `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/`. mac-cleaner does not touch this because it re-downloads unless the Chrome setting is disabled. To remove permanently: open Chrome → Settings → System → On-device AI → Off, then delete the directory once.

3. **Apple Intelligence cryptex weights** (~8–13 GB):
   > Apple Intelligence model weights live in SIP-sealed system cryptex volumes (`/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*`). Reclaim requires disabling Apple Intelligence in System Settings; mac-cleaner does not modify this.

## Integration with existing patterns

All three new categories use `run_category` (Tier 1 shape). All extensions to `category_browser_caches` integrate with its existing per-browser sub-functions and the existing leaf-list iteration. The pnpm guard rail is a four-line in-line addition to the existing pnpm function. The two spec-bug fixes are one-line path/command changes.

Each new category function lives next to its kind in the script:
- `category_intelligence_platform` and `category_wallpaper_aerials` join the user-app block at the end (alongside `category_apple_music_stream_cache` / `category_mail_downloads`).
- `category_android_studio_logs` joins the user-app block immediately after `category_diagnostic_reports`.
- E1/E2/E3 modify `category_browser_caches`'s sub-functions inline.
- pnpm guard rail modifies the existing pnpm function inline.
- S1/S2 are one-line path/command fixes in their respective categories.

**Run order in `main()`** (delta from parent spec — only listing the new and moved entries):

After the existing user-app block (`category_apple_music_stream_cache`, `category_mail_downloads`, `category_diagnostic_reports` [bug-fixed]):

- `category_android_studio_logs` (new)
- `category_intelligence_platform` (new)
- `category_wallpaper_aerials` (new)

Rationale: `android_studio_logs` immediately after `diagnostic_reports` because both are log-domain. `intelligence_platform` and `wallpaper_aerials` placed in the user-app block because they prompt for clearly user-visible data (Apple Intelligence personalization, screensaver content). All retain prompt-based execution; `--yes` accepts but the warning text remains visible.

`--dry-run`, `--yes`, the `run=<id>` log key, and the `START`/`SKIP`/`CLEAN`/`DECLINE`/`ERROR`/`END` event vocabulary all carry over unchanged.

## Logging additions

Same event vocabulary; new key/values for transparency:

- `SKIP category=intelligence_platform reason=empty`
- `SKIP category=wallpaper_aerials reason=screensaver_running`
- `SKIP category=wallpaper_aerials reason=empty`
- `SKIP category=android_studio_logs reason=app_running app=AndroidStudio`
- `SKIP category=android_studio_logs reason=empty`
- `CLEAN category=intelligence_platform freed_bytes=<n>`
- `CLEAN category=wallpaper_aerials freed_bytes=<n>`
- `CLEAN category=android_studio_logs freed_bytes=<n>`
- `CLEAN category=browser_caches browser=slack freed_bytes=<n>` (one CLEAN per browser, including the new Slack entry)

For E1 (top-level Chromium shader caches) and E2 (Firefox startupCache), the existing `CLEAN category=browser_caches browser=<name>` event already aggregates all leaves under that browser. No new event per leaf.

For the pnpm v3 guard rail, an additional event under the existing pnpm category:
- `CLEAN category=pnpm action=remove_v3_orphan freed_bytes=<n>` (or whatever logging convention the existing pnpm function uses; consistent with it).

## Verification

Same approach as the parent spec. No unit tests.

1. `zsh -n mac-cleaner.sh` — syntax check after all changes land.
2. `./mac-cleaner.sh --dry-run` and confirm:
   - Each new Tier 1 category prints its size header and the exact reclaim commands.
   - `category_wallpaper_aerials` skips when `pgrep -x ScreenSaverEngine` matches; otherwise prints both `videos` and `thumbnails` rm commands and does NOT print a `manifest` rm command.
   - `category_android_studio_logs` skips when `pgrep -f "Android Studio.app"` matches; otherwise prints both Google and JetBrains rm commands.
   - `category_intelligence_platform` prints `pkill -x intelligenceplatformd` followed by the rm command.
   - `category_browser_caches` now also prints the three Chromium top-level shader cache rm commands per Chromium browser, the Firefox `startupCache` leaf, and the full Slack sub-function.
   - The pnpm category prints the v3 detection logic and the rm command (when v3 exists and active store differs).
3. `./mac-cleaner.sh --dry-run` after S1/S2 fixes — confirm `category_xcode_device_logs` now references `DeviceLogs` (no space) and `category_diagnostic_reports` prints both the `Retired/` rm and the top-level `*.ips` rm.
4. Read `~/.mac-cleaner.log` after the dry-run and confirm event lines for the new entries match the format above.
5. Real run on the probe machine — the acceptance test. Expected reclaim on this machine: 781 MB (android_studio_logs) + 1.7 GB (wallpaper_aerials) + 108 MB (intelligence_platform) + 597 MB (Slack via B6 extension) + 1.2 GB (pnpm v3 guard) = **~4.4 GB** plus a small additional amount from the Chromium top-level shader caches and Firefox `startupCache` leaf.

## Implementation notes

- **`pgrep -f "Android Studio.app"` accuracy**: substring match on the JVM's classpath. False positive only if another path coincidentally contains the literal string `Android Studio.app` — acceptable.
- **Wallpaper screensaver gate**: `pgrep -x ScreenSaverEngine` is correct; the daemon `WallpaperAgent` itself does NOT need stopping (it doesn't hold video files open while idle, and KeepAlive auto-restarts it harmlessly even if killed).
- **`intelligenceplatformd` relaunch latency**: macOS auto-relaunches via `bg.system.task` triggers, not immediately. The category does not wait — the category exits after deletion; the user observes no Apple Intelligence regression because the daemon restarts before any Siri / Spotlight call needs it.
- **Slack `Service Worker` leaf**: includes both `CacheStorage` and `ScriptCache` sub-trees. The B6 leaf list explicitly enumerates both for the existing browsers, but for Slack the parent `Service Worker` deletion is equivalent and simpler. Both treatments are safe.
- **Spec-bug fix S1** ("iOS Device Logs" → "DeviceLogs"): backwards-compatibility is unnecessary — only macOS 26.x is in scope per the parent spec; the legacy path no longer exists on supported systems.
- **Spec-bug fix S2** (Retired/ recursion): the `rm -rf "$path"/Retired` is safe because the parent path is already hardcoded in the existing category; we are not introducing dynamic-path construction.

## Files to touch at implementation time

- `mac-cleaner.sh`:
  - Add `category_intelligence_platform`, `category_wallpaper_aerials`, `category_android_studio_logs` (3 new functions).
  - Extend `category_browser_caches` with E1 (Chromium top-level shader caches × 4 browsers), E2 (Firefox `startupCache` leaf), E3 (Slack as a 7th browser-class app).
  - Add pnpm v3 guard rail to existing pnpm function.
  - Fix `category_xcode_device_logs` path constant.
  - Fix `category_diagnostic_reports` reclaim command.
  - Add three new category invocations to `main()` run order.
- `README.md`:
  - Add three new categories to the "System Data cleanup" section.
  - Add the "What mac-cleaner cannot reclaim" section with three paragraphs (APFS internals, Chrome Gemini Nano, Apple Intelligence cryptexes).
- `CLAUDE.md` (project): no changes — every gap proposal fits an existing exception shape or the baseline rule.
- `~/.mac-cleaner.log`: gains the new event keys above; format unchanged.

## Cost / size summary

Aggregate reclaim potential on the probe machine: **~4.4 GB** across the three new categories + the pnpm v3 guard + Slack via B6. Community evidence supports up to **50–60 GB** on heavily-affected machines (large wallpaper aerial orphans + many Android Studio versions + multi-GB Slack workspace cache). Plus the spec bug fixes restore reclaim to the existing `category_xcode_device_logs` (was 0 due to bug) and `category_diagnostic_reports` (`Retired/` archive contents).
