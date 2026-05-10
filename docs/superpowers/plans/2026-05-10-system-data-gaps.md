# System Data Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the gap categories defined in `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md` — 3 new Tier 1 categories, 3 extensions to `category_browser_caches`, 1 pnpm v3 guard rail, and 2 latent spec-bug fixes — into `mac-cleaner.sh`, with README updates.

**Architecture:** Single-file zsh script edits following the established patterns. Each new category is a `cleanup_*` function plus a `category_*` wrapper that calls `run_category` (Tier 1) or implements its own size/prompt/clean/measure loop (Tier 2). Existing `category_browser_caches` is extended in place (sub-functions). Verification per the project's own rules: `zsh -n` syntax check + `--dry-run` inspection + a real run on this Mac. **No TDD because the project has no test harness — this is intentional per `CLAUDE.md`.**

**Tech Stack:** zsh, macOS-native CLIs (`du`, `pgrep`, `rm`, `pkill`), `git` for commits.

---

## File Structure

**Modified:**
- `mac-cleaner.sh` (~1779 lines now → ~+250 lines after this plan)
- `README.md` (gain "What mac-cleaner cannot reclaim" section + 3 new categories listed)

**Not created:** No new files. The script is a single self-contained file by design.

**Read for context (already exists):**
- `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md` — the spec this plan implements.
- `docs/superpowers/discovery/2026-05-10-system-data-research.md` — evidence backing each category.

---

## Task 1: Pre-flight — confirm baseline and read existing code

**Files:**
- Read: `mac-cleaner.sh` (relevant sections only — see below)
- Read: `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md`

- [ ] **Step 1: Confirm working tree is clean and on main**

Run:
```bash
git status --short && git log --oneline -3
```
Expected: clean tree; most recent commit is `b64566b docs: system data research + gap categories spec`.

- [ ] **Step 2: Verify the baseline `--dry-run` works before any changes**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | tail -40
```
Expected: completes without error; shows existing categories ending with `── Summary ──`. Save the trailing summary as a baseline.

- [ ] **Step 3: Confirm spec bug S1 (DeviceLogs path) on this Mac**

Run:
```bash
ls -la ~/Library/Developer/Xcode/DeviceLogs 2>&1 | head -2
ls -la "$HOME/Library/Developer/Xcode/iOS Device Logs" 2>&1 | head -2
```
Expected: `DeviceLogs` exists; `iOS Device Logs` (with space) does NOT exist. Confirms the spec bug.

- [ ] **Step 4: Confirm spec bug S2 (DiagnosticReports `Retired/` subfolder) on this Mac**

Run:
```bash
ls -la ~/Library/Logs/DiagnosticReports/ 2>&1
```
Expected: contains a `Retired/` subdirectory with files inside. Confirms the spec bug.

- [ ] **Step 5: Confirm `~/Library/IntelligencePlatform/`, `~/Library/Application Support/com.apple.wallpaper/aerials/`, `~/Library/Logs/Google/`, and `~/Library/pnpm/store/v3` exist and have non-zero size**

Run:
```bash
for p in ~/Library/IntelligencePlatform "$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos" ~/Library/Logs/Google ~/Library/pnpm/store/v3; do
  if [[ -e "$p" ]]; then printf 'OK %s — ' "$p"; du -sh "$p" 2>/dev/null | awk '{print $1}'
  else printf 'ABSNT %s\n' "$p"
  fi
done
```
Expected: all four print `OK <path> — <size>` with sizes matching the discovery doc (~108 MB IntelligencePlatform, 1.7 GB aerials/videos, 781 MB Google logs, 1.2 GB pnpm v3).

---

## Task 2: Spec bug fix S1 — `category_xcode_device_logs` path

**Files:**
- Modify: `mac-cleaner.sh:977-985`

- [ ] **Step 1: Read the current implementation**

The current code (lines 977-985):
```zsh
cleanup_xcode_device_logs() {
  run_cmd "rm -rf ~/Library/Developer/Xcode/iOS Device Logs/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/Xcode/iOS Device Logs/"*'
}
category_xcode_device_logs() {
  run_category "Xcode iOS device logs" \
    "historical crash logs from attached devices, re-collected on next attach" \
    "$HOME/Library/Developer/Xcode/iOS Device Logs" cleanup_xcode_device_logs
}
```

The path `iOS Device Logs` (with space, plural) does not exist on Tahoe. Actual path: `DeviceLogs` (no space, singular).

- [ ] **Step 2: Replace both occurrences using Edit tool with `replace_all: true`**

Use Edit on `mac-cleaner.sh`:
- old_string: `iOS Device Logs`
- new_string: `DeviceLogs`
- replace_all: true

Verify the new function bodies look like:
```zsh
cleanup_xcode_device_logs() {
  run_cmd "rm -rf ~/Library/Developer/Xcode/DeviceLogs/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/Xcode/DeviceLogs/"*'
}
category_xcode_device_logs() {
  run_category "Xcode iOS device logs" \
    "historical crash logs from attached devices, re-collected on next attach" \
    "$HOME/Library/Developer/Xcode/DeviceLogs" cleanup_xcode_device_logs
}
```

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -A2 'Xcode iOS device logs'
```
Expected: section header appears, size is non-zero (matches the actual `DeviceLogs` directory size, e.g. `1.1M`), reclaim command lists `DeviceLogs` (no space).

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
fix(xcode): use DeviceLogs path (Tahoe rename)

The spec used "iOS Device Logs" (with space, plural) but the actual
Tahoe path is DeviceLogs (no space, singular). Category was silently
firing SKIP reason=empty regardless of contents. Both cleanup function
and category wrapper updated to use the correct path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Spec bug fix S2 — `category_diagnostic_reports` Retired/ recursion

**Files:**
- Modify: `mac-cleaner.sh:1496-1505`

- [ ] **Step 1: Read the current implementation**

Current `cleanup_diagnostic_reports` (lines 1496-1505):
```zsh
cleanup_diagnostic_reports() {
  run_cmd "rm -f ~/Library/Logs/DiagnosticReports/*" \
    zsh -c 'rm -f "$HOME/Library/Logs/DiagnosticReports/"*'
  if id -Gn | tr ' ' '\n' | grep -qx _analyticsusers; then
    run_cmd "rm -f /Library/Logs/DiagnosticReports/*" \
      zsh -c 'rm -f /Library/Logs/DiagnosticReports/*'
  else
    log SKIP "category=diagnostic_reports reason=insufficient_perms group=_analyticsusers path=/Library/Logs/DiagnosticReports"
  fi
}
```

Bug: `rm -f "$path"/*` does not recurse into `Retired/` subdirectory. The directory entry is matched by `*` but `rm -f` without `-r` does not descend into it; `Retired/` and its contents persist.

- [ ] **Step 2: Replace the two reclaim commands**

Use Edit on `mac-cleaner.sh` to replace the function body:

old_string:
```zsh
cleanup_diagnostic_reports() {
  run_cmd "rm -f ~/Library/Logs/DiagnosticReports/*" \
    zsh -c 'rm -f "$HOME/Library/Logs/DiagnosticReports/"*'
  if id -Gn | tr ' ' '\n' | grep -qx _analyticsusers; then
    run_cmd "rm -f /Library/Logs/DiagnosticReports/*" \
      zsh -c 'rm -f /Library/Logs/DiagnosticReports/*'
  else
    log SKIP "category=diagnostic_reports reason=insufficient_perms group=_analyticsusers path=/Library/Logs/DiagnosticReports"
  fi
}
```

new_string:
```zsh
cleanup_diagnostic_reports() {
  run_cmd "rm -rf ~/Library/Logs/DiagnosticReports/Retired" \
    zsh -c 'rm -rf "$HOME/Library/Logs/DiagnosticReports/Retired"'
  run_cmd "rm -f ~/Library/Logs/DiagnosticReports/*.ips ~/Library/Logs/DiagnosticReports/*.diag" \
    zsh -c 'rm -f "$HOME/Library/Logs/DiagnosticReports/"*.ips "$HOME/Library/Logs/DiagnosticReports/"*.diag(N)'
  if id -Gn | tr ' ' '\n' | grep -qx _analyticsusers; then
    run_cmd "rm -rf /Library/Logs/DiagnosticReports/Retired" \
      zsh -c 'rm -rf /Library/Logs/DiagnosticReports/Retired'
    run_cmd "rm -f /Library/Logs/DiagnosticReports/*.ips /Library/Logs/DiagnosticReports/*.diag" \
      zsh -c 'rm -f /Library/Logs/DiagnosticReports/*.ips /Library/Logs/DiagnosticReports/*.diag(N)'
  else
    log SKIP "category=diagnostic_reports reason=insufficient_perms group=_analyticsusers path=/Library/Logs/DiagnosticReports"
  fi
}
```

The `(N)` zsh glob qualifier makes the pattern null-glob (no error if there are no matching `.diag` files). The `*.ips` glob is bare because `Retired/` is removed first by `rm -rf`, and `.ips` files at the top level are then targeted explicitly.

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -A6 'Diagnostic reports'
```
Expected: section appears; reclaim commands now show `Retired` deletion AND `*.ips`/`*.diag` deletion separately for each path.

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
fix(diagnostic-reports): recursively remove Retired/ subfolder

The previous reclaim command rm -f "$path"/* did not recurse into the
Retired/ subdirectory (a Sequoia/Tahoe addition that archives older
.ips files). The dir entry was matched by * but rm -f without -r left
its contents intact. Now Retired/ is removed via rm -rf; top-level
.ips and .diag files are removed separately.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Implement `category_intelligence_platform` (G1)

**Files:**
- Modify: `mac-cleaner.sh` — add new functions in the user-app block (after `cleanup_diagnostic_reports`/`category_diagnostic_reports` ending around line 1535, before `# ── System-state additions (Tier 2) ──` on line 1536). Also add to `main()` run order.

- [ ] **Step 1: Add the cleanup and category functions**

Find the line `# ── System-state additions (Tier 2) ──` (line 1536 in the original; may shift after Task 3). Use Edit to insert immediately BEFORE that comment. Use the exact existing comment as the anchor.

old_string:
```zsh
# ── System-state additions (Tier 2) ──
```

new_string:
```zsh
# ── Apple Intelligence + on-device ML (G1, spec 2026-05-10-gaps) ──

cleanup_intelligence_platform() {
  pkill -x intelligenceplatformd 2>/dev/null || true
  run_cmd "rm -rf ~/Library/IntelligencePlatform/*" \
    zsh -c 'rm -rf "$HOME/Library/IntelligencePlatform/"*'
}

category_intelligence_platform() {
  run_category "Apple Intelligence platform cache" \
    "knowledge graph + per-locale inference artifacts; daemon rebuilds within hours" \
    "$HOME/Library/IntelligencePlatform" cleanup_intelligence_platform
}

# ── System-state additions (Tier 2) ──
```

- [ ] **Step 2: Add to main() run order**

Find the `category_diagnostic_reports` line in `main()` (around line 1760). Use Edit:

old_string:
```zsh
    category_apple_music_stream_cache
    category_mail_downloads
    category_diagnostic_reports

    category_tm_local_snapshots
```

new_string:
```zsh
    category_apple_music_stream_cache
    category_mail_downloads
    category_diagnostic_reports
    category_intelligence_platform

    category_tm_local_snapshots
```

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -B1 -A4 'Apple Intelligence platform'
```
Expected: section header, size ~104 MB on this Mac, reclaim command shows `pkill -x intelligenceplatformd` (or its log line under DRY_RUN) followed by the rm command.

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(cleanup): add category_intelligence_platform (G1)

New Tier 1 category for Apple Intelligence knowledge graph + per-locale
inference artifacts at ~/Library/IntelligencePlatform/. Daemon rebuilds
within hours. ~108 MB on the probe machine; growing per Tahoe minor
release. Spec: docs/superpowers/specs/2026-05-10-system-data-gaps-design.md
section G1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Implement `category_wallpaper_aerials` (G2)

**Files:**
- Modify: `mac-cleaner.sh` — add immediately after `category_intelligence_platform` from Task 4.

- [ ] **Step 1: Add the category function**

This category is bespoke (sums size of two paths together; needs `pgrep -x ScreenSaverEngine` gate). It does NOT use `run_category` because `run_category` sizes a single path. Instead, follow the same self-contained pattern as `category_diagnostic_reports`.

Find the line `# ── System-state additions (Tier 2) ──` (now shifted by Task 4). Use Edit to insert the new block IMMEDIATELY BEFORE that comment.

old_string (anchored on the just-inserted G1 comment + system-state comment):
```zsh
category_intelligence_platform() {
  run_category "Apple Intelligence platform cache" \
    "knowledge graph + per-locale inference artifacts; daemon rebuilds within hours" \
    "$HOME/Library/IntelligencePlatform" cleanup_intelligence_platform
}

# ── System-state additions (Tier 2) ──
```

new_string:
```zsh
category_intelligence_platform() {
  run_category "Apple Intelligence platform cache" \
    "knowledge graph + per-locale inference artifacts; daemon rebuilds within hours" \
    "$HOME/Library/IntelligencePlatform" cleanup_intelligence_platform
}

# ── Wallpaper aerials (G2, spec 2026-05-10-gaps) ──
#
# Two hardcoded subdirs under a hardcoded parent. Manifest is preserved
# (the re-download index). User-photo wallpaper cache (Path C in the spec)
# is permanently excluded — it contains user iPhone photos with EXIF.

category_wallpaper_aerials() {
  if pgrep -x ScreenSaverEngine >/dev/null 2>&1; then
    section "Wallpaper aerials (videos + thumbnails)"
    printf '  %sScreensaver is running, skipping (file handles in use).%s\n' \
      "$C_YELLOW" "$C_RESET"
    log SKIP "category=wallpaper_aerials reason=screensaver_running"
    return 0
  fi
  local videos="$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos"
  local thumbs="$HOME/Library/Application Support/com.apple.wallpaper/aerials/thumbnails"
  local total=0
  [[ -e "$videos" ]] && total=$(( total + $(du_safe "$videos") ))
  [[ -e "$thumbs" ]] && total=$(( total + $(du_safe "$thumbs") ))
  section "Wallpaper aerials (videos + thumbnails)"
  printf '  ~/Library/Application Support/com.apple.wallpaper/aerials/{videos,thumbnails}\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=wallpaper_aerials reason=empty"
    return 0
  fi
  printf '  Re-downloads automatically on next screensaver activation (requires internet).\n'
  printf '  Manifest index is preserved; only video and thumbnail files are removed.\n'
  if ! confirm "Clean wallpaper aerials?"; then
    log DECLINE "category=wallpaper_aerials size_bytes=$total"
    return 0
  fi
  run_cmd "rm -rf <aerials>/videos" zsh -c "rm -rf ${(q)videos}"
  run_cmd "rm -rf <aerials>/thumbnails" zsh -c "rm -rf ${(q)thumbs}"
  local after=0
  [[ -e "$videos" ]] && after=$(( after + $(du_safe "$videos") ))
  [[ -e "$thumbs" ]] && after=$(( after + $(du_safe "$thumbs") ))
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=wallpaper_aerials freed_bytes=$freed"
}

# ── System-state additions (Tier 2) ──
```

- [ ] **Step 2: Add to main() run order**

Find the just-added `category_intelligence_platform` line and add the new category right after it.

old_string:
```zsh
    category_diagnostic_reports
    category_intelligence_platform

    category_tm_local_snapshots
```

new_string:
```zsh
    category_diagnostic_reports
    category_intelligence_platform
    category_wallpaper_aerials

    category_tm_local_snapshots
```

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -B1 -A8 'Wallpaper aerials'
```
Expected: section header, size ~1.7 GB on this Mac, reclaim commands list both `videos` and `thumbnails` rm operations; manifest is NOT mentioned in any rm.

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(cleanup): add category_wallpaper_aerials (G2)

New Tier 1-shaped category for Tahoe per-user aerial wallpaper videos +
thumbnails at ~/Library/Application Support/com.apple.wallpaper/aerials/.
Manifest is preserved (re-download index). User-photo wallpaper cache
permanently excluded (Path C, contains iPhone EXIF data per discovery).
Skip if ScreenSaverEngine running. ~1.7 GB on probe machine; up to
50+ GB community-reported. Spec: G2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Implement `category_android_studio_logs` (G3)

**Files:**
- Modify: `mac-cleaner.sh` — add immediately after `category_diagnostic_reports`. The plan moves `category_android_studio_logs` AFTER `category_diagnostic_reports` per the gap spec's run-order recommendation (both are log-domain).

Wait — the gap spec says `category_android_studio_logs` goes after `category_diagnostic_reports`. We're adding it in the user-app block, ordered: diagnostic_reports → android_studio_logs → intelligence_platform → wallpaper_aerials.

- [ ] **Step 1: Add the cleanup and category functions**

Insert immediately AFTER `category_diagnostic_reports` (the closing `}` of that function, around line 1534) and BEFORE the G1 (`# ── Apple Intelligence + on-device ML`) block added in Task 4.

Find the closing of `category_diagnostic_reports` followed by the G1 block. Use Edit:

old_string:
```zsh
  log CLEAN "category=diagnostic_reports freed_bytes=$freed"
}

# ── Apple Intelligence + on-device ML (G1, spec 2026-05-10-gaps) ──
```

new_string:
```zsh
  log CLEAN "category=diagnostic_reports freed_bytes=$freed"
}

# ── IDE log accumulation (G3, spec 2026-05-10-gaps) ──
#
# Android Studio creates a per-version log dir under ~/Library/Logs/Google/
# at every minor version and never prunes old ones. JetBrains companion
# path is included for completeness (auto-cleanup-180-day policy can
# fail when products are uninstalled before next-version upgrade).

cleanup_android_studio_logs() {
  run_cmd "rm -rf ~/Library/Logs/Google" \
    zsh -c 'rm -rf "$HOME/Library/Logs/Google"'
  run_cmd "rm -rf ~/Library/Logs/JetBrains" \
    zsh -c 'rm -rf "$HOME/Library/Logs/JetBrains"'
}

category_android_studio_logs() {
  if pgrep -f "Android Studio.app" >/dev/null 2>&1; then
    section "Android Studio + JetBrains IDE logs"
    printf '  %sAndroid Studio is running. Close it and re-run.%s\n' \
      "$C_YELLOW" "$C_RESET"
    log SKIP "category=android_studio_logs reason=app_running app=AndroidStudio"
    return 0
  fi
  local total=0 p
  for p in "$HOME/Library/Logs/Google" "$HOME/Library/Logs/JetBrains"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  section "Android Studio + JetBrains IDE logs"
  printf '  ~/Library/Logs/Google + ~/Library/Logs/JetBrains (all IDE versions)\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=android_studio_logs reason=empty"
    return 0
  fi
  printf '  Each IDE recreates its log dir on next launch.\n'
  if ! confirm "Clean this?"; then
    log DECLINE "category=android_studio_logs size_bytes=$total"
    return 0
  fi
  cleanup_android_studio_logs || { log ERROR "category=android_studio_logs rc=$?"; return 0; }
  local after=0
  for p in "$HOME/Library/Logs/Google" "$HOME/Library/Logs/JetBrains"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=android_studio_logs freed_bytes=$freed"
}

# ── Apple Intelligence + on-device ML (G1, spec 2026-05-10-gaps) ──
```

- [ ] **Step 2: Add to main() run order**

The `category_android_studio_logs` runs AFTER `category_diagnostic_reports` per spec. Use Edit:

old_string:
```zsh
    category_diagnostic_reports
    category_intelligence_platform
    category_wallpaper_aerials

    category_tm_local_snapshots
```

new_string:
```zsh
    category_diagnostic_reports
    category_android_studio_logs
    category_intelligence_platform
    category_wallpaper_aerials

    category_tm_local_snapshots
```

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -B1 -A8 'Android Studio + JetBrains'
```
Expected: section header, size ~781 MB on this Mac, reclaim commands show both `~/Library/Logs/Google` and `~/Library/Logs/JetBrains` rm.

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(cleanup): add category_android_studio_logs (G3)

New Tier 1-shaped category for Android Studio + JetBrains IDE log dirs
at ~/Library/Logs/{Google,JetBrains}. Skip if Android Studio running
(pgrep -f matches JVM with app path in classpath). ~781 MB on probe
machine. Spec: G3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Extend `_browser_clean_chromium` with top-level shader caches (E1)

**Files:**
- Modify: `mac-cleaner.sh:1308-1365` — `_browser_clean_chromium` function.

- [ ] **Step 1: Read current function**

The function currently iterates per-profile leaves. We add a top-level (NOT per-profile) leaf list.

- [ ] **Step 2: Add top-level leaves to size pre-flight, deletion, and post-size**

Use Edit to replace the function body. The change adds a `top_leaves` array and applies it to all three loops (size before, delete, size after).

old_string:
```zsh
_browser_clean_chromium() {
  # _browser_clean_chromium <browser-key> <pgrep-path-pattern> <user-data-dir>
  local key="$1" pgpat="$2" udir="$3"
  if [[ ! -d "$udir" ]]; then
    log SKIP "category=browser_caches browser=$key reason=tool_not_installed"
    return 0
  fi
  if pgrep -f "$pgpat" >/dev/null 2>&1; then
    printf '  %s%s is running, skipping its caches.%s\n' "$C_YELLOW" "$key" "$C_RESET"
    log SKIP "category=browser_caches browser=$key reason=app_running"
    return 0
  fi
  local -a leaves=(
    "Cache/Cache_Data"
    "Code Cache"
    "GPUCache"
    "Service Worker/CacheStorage"
    "Service Worker/ScriptCache"
    "DawnGraphiteCache"
    "DawnWebGPUCache"
  )
  local before=0 after=0 prof leaf target
  # Compute size across (Default + Profile *) × leaves
  for prof in "$udir"/Default(N/) "$udir"/Profile\ *(N/); do
    for leaf in "${leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] && before=$(( before + $(du_safe "$target") ))
    done
  done
  if (( before == 0 )); then
    log SKIP "category=browser_caches browser=$key reason=empty"
    return 0
  fi
  printf '  %s%s%s — size: %s%s%s\n' "$C_BOLD" "$key" "$C_RESET" \
    "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Clean $key caches?"; then
    log DECLINE "category=browser_caches browser=$key size_bytes=$before"
    return 0
  fi
  for prof in "$udir"/Default(N/) "$udir"/Profile\ *(N/); do
    for leaf in "${leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] || continue
      run_cmd "rm -rf <profile>/$leaf" zsh -c "rm -rf ${(q)target}"
    done
  done
  for prof in "$udir"/Default(N/) "$udir"/Profile\ *(N/); do
    for leaf in "${leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] && after=$(( after + $(du_safe "$target") ))
    done
  done
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ %s freed %s%s\n' "$C_GREEN" "$key" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=browser_caches browser=$key freed_bytes=$freed"
}
```

new_string:
```zsh
_browser_clean_chromium() {
  # _browser_clean_chromium <browser-key> <pgrep-path-pattern> <user-data-dir>
  local key="$1" pgpat="$2" udir="$3"
  if [[ ! -d "$udir" ]]; then
    log SKIP "category=browser_caches browser=$key reason=tool_not_installed"
    return 0
  fi
  if pgrep -f "$pgpat" >/dev/null 2>&1; then
    printf '  %s%s is running, skipping its caches.%s\n' "$C_YELLOW" "$key" "$C_RESET"
    log SKIP "category=browser_caches browser=$key reason=app_running"
    return 0
  fi
  local -a leaves=(
    "Cache/Cache_Data"
    "Code Cache"
    "GPUCache"
    "Service Worker/CacheStorage"
    "Service Worker/ScriptCache"
    "DawnGraphiteCache"
    "DawnWebGPUCache"
  )
  # Top-level (not per-profile) shader caches — Chromium gpu/graphite/skia.
  local -a top_leaves=(
    "GrShaderCache"
    "GraphiteDawnCache"
    "ShaderCache"
  )
  local before=0 after=0 prof leaf target
  # Compute size across (Default + Profile *) × per-profile leaves
  for prof in "$udir"/Default(N/) "$udir"/Profile\ *(N/); do
    for leaf in "${leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] && before=$(( before + $(du_safe "$target") ))
    done
  done
  # Add top-level shader cache sizes
  for leaf in "${top_leaves[@]}"; do
    target="$udir/$leaf"
    [[ -e "$target" ]] && before=$(( before + $(du_safe "$target") ))
  done
  if (( before == 0 )); then
    log SKIP "category=browser_caches browser=$key reason=empty"
    return 0
  fi
  printf '  %s%s%s — size: %s%s%s\n' "$C_BOLD" "$key" "$C_RESET" \
    "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Clean $key caches?"; then
    log DECLINE "category=browser_caches browser=$key size_bytes=$before"
    return 0
  fi
  for prof in "$udir"/Default(N/) "$udir"/Profile\ *(N/); do
    for leaf in "${leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] || continue
      run_cmd "rm -rf <profile>/$leaf" zsh -c "rm -rf ${(q)target}"
    done
  done
  for leaf in "${top_leaves[@]}"; do
    target="$udir/$leaf"
    [[ -e "$target" ]] || continue
    run_cmd "rm -rf <browser>/$leaf" zsh -c "rm -rf ${(q)target}"
  done
  for prof in "$udir"/Default(N/) "$udir"/Profile\ *(N/); do
    for leaf in "${leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] && after=$(( after + $(du_safe "$target") ))
    done
  done
  for leaf in "${top_leaves[@]}"; do
    target="$udir/$leaf"
    [[ -e "$target" ]] && after=$(( after + $(du_safe "$target") ))
  done
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ %s freed %s%s\n' "$C_GREEN" "$key" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=browser_caches browser=$key freed_bytes=$freed"
}
```

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -A20 'Browser caches' | head -40
```
Expected: Chrome size now reflects the additional top-level shader caches; reclaim list mentions `GrShaderCache`, `GraphiteDawnCache`, `ShaderCache` as `<browser>/...` (the new code path).

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(browser-caches): add Chromium top-level shader caches (E1)

GrShaderCache, GraphiteDawnCache, and ShaderCache live at the top
level of each Chromium browser's user data dir (NOT per-profile).
Adds them to all four Chromium sub-functions (Chrome, Arc, Edge, Brave)
via _browser_clean_chromium. Hardcoded leaf names under hardcoded
top-level path; same exception shape as existing per-profile leaves.
Spec: E1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Extend `_browser_clean_firefox` with `startupCache` leaf (E2)

**Files:**
- Modify: `mac-cleaner.sh:1398-1438` — `_browser_clean_firefox` function.

- [ ] **Step 1: Replace the single-leaf logic with a leaf list**

The current function uses a hardcoded `cache2` leaf. We replace with a list of two leaves: `cache2` and `startupCache`.

Use Edit:

old_string:
```zsh
_browser_clean_firefox() {
  local root="$HOME/Library/Caches/Firefox/Profiles"
  if [[ ! -d "$root" ]]; then
    log SKIP "category=browser_caches browser=firefox reason=tool_not_installed"
    return 0
  fi
  if pgrep -x firefox >/dev/null 2>&1 || pgrep -f '/Applications/Firefox.app' >/dev/null 2>&1; then
    printf '  %sFirefox is running, skipping its caches.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=browser_caches browser=firefox reason=app_running"
    return 0
  fi
  local before=0 after=0 prof target
  for prof in "$root"/*.default-release(N/) "$root"/*.default(N/) "$root"/*.dev-edition-default(N/); do
    target="$prof/cache2"
    [[ -e "$target" ]] && before=$(( before + $(du_safe "$target") ))
  done
  if (( before == 0 )); then
    log SKIP "category=browser_caches browser=firefox reason=empty"
    return 0
  fi
  printf '  %sFirefox%s — size: %s%s%s\n' "$C_BOLD" "$C_RESET" \
    "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Clean Firefox caches?"; then
    log DECLINE "category=browser_caches browser=firefox size_bytes=$before"
    return 0
  fi
  for prof in "$root"/*.default-release(N/) "$root"/*.default(N/) "$root"/*.dev-edition-default(N/); do
    target="$prof/cache2"
    [[ -e "$target" ]] || continue
    run_cmd "rm -rf <profile>/cache2" zsh -c "rm -rf ${(q)target}"
  done
  for prof in "$root"/*.default-release(N/) "$root"/*.default(N/) "$root"/*.dev-edition-default(N/); do
    target="$prof/cache2"
    [[ -e "$target" ]] && after=$(( after + $(du_safe "$target") ))
  done
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ Firefox freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=browser_caches browser=firefox freed_bytes=$freed"
}
```

new_string:
```zsh
_browser_clean_firefox() {
  local root="$HOME/Library/Caches/Firefox/Profiles"
  if [[ ! -d "$root" ]]; then
    log SKIP "category=browser_caches browser=firefox reason=tool_not_installed"
    return 0
  fi
  if pgrep -x firefox >/dev/null 2>&1 || pgrep -f '/Applications/Firefox.app' >/dev/null 2>&1; then
    printf '  %sFirefox is running, skipping its caches.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=browser_caches browser=firefox reason=app_running"
    return 0
  fi
  local -a ff_leaves=("cache2" "startupCache")
  local before=0 after=0 prof leaf target
  for prof in "$root"/*.default-release(N/) "$root"/*.default(N/) "$root"/*.dev-edition-default(N/); do
    for leaf in "${ff_leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] && before=$(( before + $(du_safe "$target") ))
    done
  done
  if (( before == 0 )); then
    log SKIP "category=browser_caches browser=firefox reason=empty"
    return 0
  fi
  printf '  %sFirefox%s — size: %s%s%s\n' "$C_BOLD" "$C_RESET" \
    "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Clean Firefox caches?"; then
    log DECLINE "category=browser_caches browser=firefox size_bytes=$before"
    return 0
  fi
  for prof in "$root"/*.default-release(N/) "$root"/*.default(N/) "$root"/*.dev-edition-default(N/); do
    for leaf in "${ff_leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] || continue
      run_cmd "rm -rf <profile>/$leaf" zsh -c "rm -rf ${(q)target}"
    done
  done
  for prof in "$root"/*.default-release(N/) "$root"/*.default(N/) "$root"/*.dev-edition-default(N/); do
    for leaf in "${ff_leaves[@]}"; do
      target="$prof/$leaf"
      [[ -e "$target" ]] && after=$(( after + $(du_safe "$target") ))
    done
  done
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ Firefox freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=browser_caches browser=firefox freed_bytes=$freed"
}
```

- [ ] **Step 2: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -A2 Firefox
```
Expected: Firefox size now includes `startupCache` (~+19 MB on this Mac); reclaim list shows both `cache2` and `startupCache` paths.

- [ ] **Step 4: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(browser-caches): add Firefox startupCache leaf (E2)

startupCache holds compiled XUL/JS startup bytecode; regenerates on
every Firefox launch. ~19 MB on probe machine. One-line addition to
the Firefox leaf list. Spec: E2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Add Slack as a 7th browser-class app (E3)

**Files:**
- Modify: `mac-cleaner.sh` — add new `_browser_clean_slack` sub-function (model after `_browser_clean_safari` since Slack has a single profile, no per-profile iteration). Wire into `category_browser_caches`.

- [ ] **Step 1: Add the `_browser_clean_slack` sub-function**

Insert immediately after `_browser_clean_firefox` (line 1438) and before `category_browser_caches` (line 1440).

Find the closing of `_browser_clean_firefox` (`log CLEAN ... browser=firefox ...`) followed by `category_browser_caches() {`. Use Edit:

old_string:
```zsh
  log CLEAN "category=browser_caches browser=firefox freed_bytes=$freed"
}

category_browser_caches() {
```

new_string:
```zsh
  log CLEAN "category=browser_caches browser=firefox freed_bytes=$freed"
}

# Slack 5.x stores Chromium-style caches under its sandbox container.
# Same Chromium leaf list as the other browsers (single profile, no iteration).
_browser_clean_slack() {
  local base="$HOME/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack"
  if [[ ! -d "$base" ]]; then
    log SKIP "category=browser_caches browser=slack reason=tool_not_installed"
    return 0
  fi
  if pgrep -f '/Applications/Slack.app' >/dev/null 2>&1; then
    printf '  %sSlack is running, skipping its caches.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=browser_caches browser=slack reason=app_running"
    return 0
  fi
  local -a leaves=(
    "Cache"
    "Code Cache"
    "GPUCache"
    "Service Worker"
    "DawnGraphiteCache"
    "DawnWebGPUCache"
  )
  local before=0 after=0 leaf target
  for leaf in "${leaves[@]}"; do
    target="$base/$leaf"
    [[ -e "$target" ]] && before=$(( before + $(du_safe "$target") ))
  done
  if (( before == 0 )); then
    log SKIP "category=browser_caches browser=slack reason=empty"
    return 0
  fi
  printf '  %sSlack%s — size: %s%s%s\n' "$C_BOLD" "$C_RESET" \
    "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Clean Slack caches?"; then
    log DECLINE "category=browser_caches browser=slack size_bytes=$before"
    return 0
  fi
  for leaf in "${leaves[@]}"; do
    target="$base/$leaf"
    [[ -e "$target" ]] || continue
    run_cmd "rm -rf <slack>/$leaf" zsh -c "rm -rf ${(q)target}"
  done
  for leaf in "${leaves[@]}"; do
    target="$base/$leaf"
    [[ -e "$target" ]] && after=$(( after + $(du_safe "$target") ))
  done
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ Slack freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=browser_caches browser=slack freed_bytes=$freed"
}

category_browser_caches() {
```

- [ ] **Step 2: Wire `_browser_clean_slack` into `category_browser_caches`**

Inside `category_browser_caches`, add the Slack call after Firefox.

Find:

old_string:
```zsh
  _browser_clean_firefox
  # Count this category as cleaned if any sub-browser produced freed bytes.
```

new_string:
```zsh
  _browser_clean_firefox
  _browser_clean_slack
  # Count this category as cleaned if any sub-browser produced freed bytes.
```

Also update the section header text. Find:

old_string:
```zsh
category_browser_caches() {
  section "Browser caches"
  printf '  Safari, Chrome, Arc, Edge, Brave, Firefox — cache subdirs only.\n'
  printf '  Cookies, history, logins, and site storage are NOT touched.\n'
```

new_string:
```zsh
category_browser_caches() {
  section "Browser caches"
  printf '  Safari, Chrome, Arc, Edge, Brave, Firefox, Slack — cache subdirs only.\n'
  printf '  Cookies, history, logins, and site storage are NOT touched.\n'
```

- [ ] **Step 3: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -A1 'Slack'
```
Expected: Slack size shown (~597 MB on this Mac); reclaim list includes the Chromium leaf names under Slack's container path.

- [ ] **Step 5: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(browser-caches): add Slack as 7th browser-class app (E3)

Slack 5.x stores Chromium-style caches under its sandbox container at
~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application
Support/Slack. Single profile, same Chromium leaf list. Officially
endorsed by Slack help docs as safe to clear when Slack is closed.
~597 MB on probe machine. Spec: E3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: pnpm v3 orphan guard rail

**Files:**
- Modify: `mac-cleaner.sh:190-193, 237-241` — `cleanup_pnpm_store` function.

The spec says fold the v3 guard into the existing pnpm function, NOT a new category. The existing `cleanup_pnpm_store` runs `pnpm store prune`. We add a v3 detection step before that.

- [ ] **Step 1: Replace `cleanup_pnpm_store`**

Use Edit:

old_string:
```zsh
cleanup_pnpm_store() {
  have pnpm || { log SKIP "category=pnpm_store reason=tool_not_installed"; return 0; }
  run_cmd "pnpm store prune" pnpm store prune
}
```

new_string:
```zsh
cleanup_pnpm_store() {
  # v3 legacy store: pnpm 5-8 stored at ~/Library/pnpm/store/v3.
  # pnpm 9+ migrated to v10/v11; v3 is permanently unreachable.
  # Guard rail: if v3 dir exists and is NOT the active store, offer to delete it.
  local v3="$HOME/Library/pnpm/store/v3"
  if [[ -d "$v3" ]]; then
    local active=""
    if have pnpm; then
      active="$(pnpm store path 2>/dev/null || true)"
    fi
    if [[ "$active" != "$v3" ]]; then
      local v3_size; v3_size=$(du_safe "$v3")
      if (( v3_size > 0 )); then
        printf '  %spnpm legacy v3 store found (orphaned by pnpm 9+):%s %s\n' \
          "$C_YELLOW" "$C_RESET" "$(human_size "$v3_size")"
        if confirm "  Remove orphaned pnpm v3 store?"; then
          run_cmd "rm -rf ~/Library/pnpm/store/v3" zsh -c "rm -rf ${(q)v3}"
          log CLEAN "category=pnpm_store action=remove_v3_orphan freed_bytes=$v3_size"
        else
          log DECLINE "category=pnpm_store action=remove_v3_orphan size_bytes=$v3_size"
        fi
      fi
    fi
  fi
  have pnpm || { log SKIP "category=pnpm_store reason=tool_not_installed"; return 0; }
  run_cmd "pnpm store prune" pnpm store prune
}
```

- [ ] **Step 2: Syntax check**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Dry-run inspection**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | grep -B2 -A4 'pnpm.*legacy v3\|pnpm store'
```
Expected: pnpm category prints the `legacy v3 store found` line with ~1.2 GB size, lists the rm command, then the standard `pnpm store prune`.

- [ ] **Step 4: Commit**

```bash
git add mac-cleaner.sh
git commit -m "$(cat <<'EOF'
feat(pnpm): add v3 orphan store guard rail

pnpm 5-8 stored at ~/Library/pnpm/store/v3; pnpm 9+ migrated to v10/v11
and pnpm store prune does NOT touch v3. The guard checks if v3 exists
AND the active store is something else, then offers to delete v3.
~1.2 GB on probe machine. Folded into existing cleanup_pnpm_store
rather than a new category (R2-4 confirmed no other tool has the same
multi-version orphan pattern).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Update README.md

**Files:**
- Modify: `README.md` — add 3 new categories to the cleanup list, add "What mac-cleaner cannot reclaim" section.

- [ ] **Step 1: Read current README**

Run:
```bash
wc -l README.md && grep -n '^##' README.md
```
Note the current section structure.

- [ ] **Step 2: Add the 3 new categories to the cleanup list**

Find the existing System Data cleanup section (where category descriptions live). Add three entries describing G1, G2, G3 — match the existing format. Use Edit; the exact insertion point depends on the current README structure (the agent should locate the corresponding existing-categories list first by reading the file).

The new bullets to add:
- "Apple Intelligence platform cache (~/Library/IntelligencePlatform) — knowledge graph + per-locale inference artifacts; daemon rebuilds within hours; new in Tahoe 26.x"
- "Wallpaper aerials (~/Library/Application Support/com.apple.wallpaper/aerials/{videos,thumbnails}) — aerial wallpaper videos and thumbnails; re-downloads on next screensaver activation; manifest preserved"
- "Android Studio + JetBrains IDE logs (~/Library/Logs/{Google,JetBrains}) — multi-version log accumulation; each IDE recreates its log dir on next launch"

- [ ] **Step 3: Add a "What mac-cleaner cannot reclaim" section**

Append to the README a new section with the text drafted in the gap spec § "README additions":

```markdown
## What mac-cleaner cannot reclaim

Some buckets show up in macOS Storage Settings as "System Data" but cannot be safely freed by an unprivileged tool. mac-cleaner deliberately does not touch them.

**APFS purgeable space (~10–80 GB on heavy iCloud/Photos machines).** macOS marks iCloud-synced local copies and Photos derivatives as "purgeable." These appear in `diskutil info` `CapacityInUse` but not in `df` "used". macOS reclaims them automatically under storage pressure; no user CLI can force this without sudo.

**System volume (~12–15 GB), Preboot (~9 GB), Recovery (~1–2 GB).** The sealed read-only OS partition and firmware support volumes. SIP-protected.

**VM/swap (varies).** Root-owned swap files in `/System/Volumes/VM`. Only a reboot reduces them.

**FileVault.** Adds no storage overhead — encryption is in-place at the block level.

**APFS local snapshots.** Covered by the "Time Machine snapshots" category if you have TM configured. If not, no snapshots accumulate.

**Apple Intelligence cryptex weights (~8–13 GB).** Live in SIP-sealed system cryptex volumes (`/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*`). Reclaim requires disabling Apple Intelligence in System Settings; mac-cleaner does not modify this.

**Chrome's Gemini Nano AI weights (~4 GB).** Chrome silently downloads to `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/`. mac-cleaner does not touch this because deletion forces immediate re-download unless the Chrome setting is changed. To remove permanently: open Chrome → Settings → System → On-device AI → Off, then delete the directory once.
```

Insert this section before the existing "Logs" or final section (whatever the README structure has).

- [ ] **Step 4: Verify README parses as Markdown (no syntax errors)**

Run:
```bash
head -60 README.md && echo --- && tail -60 README.md
```
Skim for any obvious issues (broken headings, unclosed code fences).

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): add 3 new categories + 'cannot reclaim' section

Documents category_intelligence_platform, category_wallpaper_aerials,
and category_android_studio_logs. Adds a 'What mac-cleaner cannot
reclaim' section explaining APFS purgeable / sealed / Preboot /
Recovery / VM-swap / FileVault, Apple Intelligence cryptexes (8-13 GB),
and Chrome's Gemini Nano (4 GB) — all out of scope per the gap spec.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Final verification — full dry-run + real run on this Mac

**Files:** none modified; verification only.

- [ ] **Step 1: Full `--dry-run` end-to-end**

Run:
```bash
./mac-cleaner.sh --dry-run --yes 2>&1 | tee /tmp/dry-run-after.log
```
Expected: no errors, no `command not found`, no `bad substitution`. The trailing summary should show all new categories ran (or printed SKIP for valid reasons like `app_running`).

- [ ] **Step 2: Inspect the new event lines in the log**

Run:
```bash
tail -100 ~/.mac-cleaner.log | grep -E 'category=(intelligence_platform|wallpaper_aerials|android_studio_logs|browser_caches.*slack|pnpm_store.*v3)'
```
Expected: at least one event per new category/extension, with appropriate `START`/`SKIP`/`CLEAN`/`DECLINE`/`ERROR` level.

- [ ] **Step 3: Check the script's syntax one final time**

Run:
```bash
zsh -n mac-cleaner.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Confirm with the user before doing a REAL run**

This step is a HUMAN-IN-LOOP gate. The agent presents the summary of `/tmp/dry-run-after.log` to the user and asks: "The dry-run looks clean. Want me to do a real run on this Mac now to verify reclaim numbers? You can also do this yourself with `./mac-cleaner.sh` (without `--dry-run`)."

If the user says yes:
```bash
./mac-cleaner.sh --yes 2>&1 | tee /tmp/real-run.log
```
Expected: real reclaim numbers match (within rounding) the dry-run sizes — ~108 MB intelligence_platform + ~1.7 GB wallpaper_aerials + ~781 MB android_studio_logs + ~597 MB Slack + ~1.2 GB pnpm v3 + small browser shader caches = ~4.4 GB total.

If the user says no, skip the real run. The dry-run is sufficient verification per the project's own convention.

- [ ] **Step 5: Confirm git is clean and all commits are present**

Run:
```bash
git status --short && git log --oneline -15
```
Expected: clean tree; the commit history shows Task 2 → Task 11 commits in order plus the prior `b64566b` research commit.

---

## Self-review checklist (run after writing this plan)

1. **Spec coverage:**
   - G1 (intelligence_platform) → Task 4 ✓
   - G2 (wallpaper_aerials) → Task 5 ✓
   - G3 (android_studio_logs) → Task 6 ✓
   - E1 (Chromium top-level shaders) → Task 7 ✓
   - E2 (Firefox startupCache) → Task 8 ✓
   - E3 (Slack) → Task 9 ✓
   - pnpm v3 guard → Task 10 ✓
   - S1 (DeviceLogs path) → Task 2 ✓
   - S2 (Retired/ recursion) → Task 3 ✓
   - README → Task 11 ✓
   - Final verification → Task 12 ✓
2. **Placeholder scan:** No "TBD"/"TODO"/"fill in details". Every code block is complete and shows actual code to insert. Task 11 step 2 says "the agent should locate the corresponding existing-categories list first by reading the file" — this is necessary because README structure is conditional on its current state, but the bullet text to insert is given verbatim.
3. **Type/identifier consistency:** Function names (`cleanup_intelligence_platform`, `category_intelligence_platform`, `cleanup_android_studio_logs`, `category_android_studio_logs`, `category_wallpaper_aerials`, `_browser_clean_slack`, `cleanup_pnpm_store`) consistent throughout. Path strings (`~/Library/IntelligencePlatform`, `~/Library/Application Support/com.apple.wallpaper/aerials/{videos,thumbnails}`, `~/Library/Logs/{Google,JetBrains}`, `~/Library/pnpm/store/v3`, Slack container path) consistent with the gap spec.
4. **Run-order consistency:** Plan has `category_diagnostic_reports → category_android_studio_logs → category_intelligence_platform → category_wallpaper_aerials`, matching the gap spec's recommended placement (android_studio_logs after diagnostic_reports because both log-domain; the AI/wallpaper categories grouped at the end of the user-app block).
