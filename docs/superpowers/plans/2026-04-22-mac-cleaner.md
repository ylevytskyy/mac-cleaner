# mac-cleaner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-file interactive zsh script that walks the user through cleaning developer caches on macOS, auditing outdated tool/global-package versions, and logging actions — with a dry-run mode and per-category y/N prompts.

**Architecture:** Single zsh file organized into: (1) flag parser + globals, (2) small reusable helpers, (3) one function per cleanup category, (4) version-audit functions, (5) main dispatcher. Each cleanup function follows the same shape: print header → compute size → prompt → run → log → update running total.

**Tech Stack:** zsh (5.x, shipped with macOS), POSIX `du`, macOS built-ins (`xcrun`, `open`), native package-manager CLIs (`npm`, `yarn`, `pnpm`, `brew`, `pip`). No external script dependencies.

**Note on git/TDD:** The target directory is NOT a git repo and the spec explicitly opts out of unit tests. Plan therefore uses `--dry-run` smoke checks as the verification step after each task, and skips git-commit steps. If the user later runs `git init`, they can `git add -A && git commit -m "initial"` at the end.

**Note on file size:** The whole script is one file (`mac-cleaner.sh`) at ~400 lines. That's fine for a personal utility — splitting into sourced helpers (option B in the design) was explicitly rejected as over-engineering.

---

## File Structure

| File | Role |
|---|---|
| `mac-cleaner.sh` | Executable entry point and only source file. Sections built up task by task. |
| `docs/superpowers/specs/2026-04-22-mac-cleaner-design.md` | Design spec (already written). |
| `docs/superpowers/plans/2026-04-22-mac-cleaner.md` | This plan. |

No test files. Verification is interactive via `--dry-run`.

---

## Task 1: Scaffold — shebang, strict mode, flag parsing, help

**Files:**
- Create: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

- [ ] **Step 1: Create the file with scaffold**

```bash
#!/usr/bin/env zsh
# mac-cleaner — interactive macOS developer-cache cleaner
# Usage: ./mac-cleaner.sh [--dry-run] [--yes|-y] [--help|-h]

set -euo pipefail
setopt nullglob

# ── globals ──────────────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
LOG_FILE="${HOME}/.mac-cleaner.log"
RUN_ID="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
TOTAL_FREED=0
CATEGORIES_CLEANED=0

# ── colors ───────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

usage() {
  cat <<EOF
mac-cleaner — interactive macOS developer-cache cleaner

Usage:
  $(basename "$0") [--dry-run] [--yes|-y] [--help|-h]

Flags:
  --dry-run   Show what would be deleted without deleting. Still prompts.
  --yes, -y   Skip y/N prompts (Xcode Archives still double-prompts).
  --help, -h  This message.

Log: ${LOG_FILE}
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown flag: $arg" >&2; usage; exit 2 ;;
  esac
done

# main will be defined later; for now just prove scaffold runs
echo "mac-cleaner scaffold OK (dry_run=${DRY_RUN} yes=${ASSUME_YES})"
```

- [ ] **Step 2: Make executable and smoke-test**

Run:
```bash
chmod +x /Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --help
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --bogus; echo "rc=$?"
```

Expected:
- `--help` prints usage, exits 0.
- `--dry-run` prints `mac-cleaner scaffold OK (dry_run=1 yes=0)`.
- `--bogus` prints "Unknown flag", usage, and `rc=2`.

---

## Task 2: Core helpers

**Files:**
- Modify: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh` — insert after the globals, before the `# main will be defined later` line.

- [ ] **Step 1: Add helper functions**

Insert this block immediately after the argument-parser `for arg in "$@"` loop and before the temporary `echo "mac-cleaner scaffold OK ..."` line:

```bash
# ── helpers ──────────────────────────────────────────────

log() {
  # log <EVENT> <key=value>...
  local event="$1"; shift
  local ts
  ts="$(date "+%Y-%m-%dT%H:%M:%S%z")"
  printf '%s  %-7s run=%s %s\n' "$ts" "$event" "$RUN_ID" "$*" >> "$LOG_FILE"
}

have() { command -v "$1" >/dev/null 2>&1; }

human_size() {
  # human_size <bytes>
  local b=$1
  if   (( b >= 1073741824 )); then printf '%.2f GB' "$(( b ))e-9"
  elif (( b >= 1048576 ));    then printf '%.2f MB' "$(( b ))e-6"
  elif (( b >= 1024 ));       then printf '%.2f KB' "$(( b ))e-3"
  else                              printf '%d B'    "$b"
  fi
}

du_safe() {
  # echo size-in-bytes of path, 0 if missing
  local path="$1"
  if [[ ! -e "$path" ]]; then echo 0; return; fi
  # du -sk gives KB; multiply by 1024. Use BSD du (macOS default).
  local kb
  kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
  echo "$(( ${kb:-0} * 1024 ))"
}

confirm() {
  # confirm "<prompt>" — returns 0 if yes, 1 if no
  local prompt="$1"
  if (( ASSUME_YES )); then
    printf '  %s [y/N] %sy (auto)%s\n' "$prompt" "$C_DIM" "$C_RESET"
    return 0
  fi
  printf '  %s [y/N] ' "$prompt"
  local ans
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

run_cmd() {
  # run_cmd <desc> <cmd...>  — respects DRY_RUN, returns cmd's rc
  local desc="$1"; shift
  if (( DRY_RUN )); then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  # Relax -e briefly so we can keep going on per-category failures.
  set +e
  "$@"
  local rc=$?
  set -e
  return $rc
}

section() {
  printf '\n%s── %s %s%s\n' "$C_BOLD" "$1" "$(printf -- '─%.0s' {1..30})" "$C_RESET"
}

# category runner: handles the size-show / prompt / delete-and-measure loop.
# Usage: run_category <name> <description> <path-for-sizing-or-"-"> <cleanup-fn>
run_category() {
  local name="$1" desc="$2" size_path="$3" cleanup_fn="$4"

  if ! typeset -f "$cleanup_fn" >/dev/null; then
    echo "  internal error: cleanup fn '$cleanup_fn' not defined" >&2
    return 1
  fi

  section "$name"
  printf '  %s\n' "$desc"

  local before=0
  if [[ "$size_path" != "-" ]]; then
    before="$(du_safe "$size_path")"
    printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
    if (( before == 0 )); then
      printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
      log SKIP "category=$name reason=empty"
      return 0
    fi
  fi

  if ! confirm "Clean this?"; then
    log DECLINE "category=$name size_bytes=$before"
    return 0
  fi

  local rc=0
  "$cleanup_fn" || rc=$?

  local after=0
  if [[ "$size_path" != "-" ]]; then
    after="$(du_safe "$size_path")"
  fi

  if (( rc != 0 )); then
    printf '  %sERROR%s cleanup returned rc=%d (continuing)\n' "$C_RED" "$C_RESET" "$rc"
    log ERROR "category=$name rc=$rc"
    return 0
  fi

  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=$name freed_bytes=$freed"
}
```

- [ ] **Step 2: Replace temporary echo with a quick helper self-test**

Replace the existing line `echo "mac-cleaner scaffold OK (dry_run=${DRY_RUN} yes=${ASSUME_YES}"` with:

```bash
# Quick helpers self-test (removed in Task 3)
log START "dry_run=$DRY_RUN yes=$ASSUME_YES"
echo "human_size(0)          = $(human_size 0)"
echo "human_size(2048)       = $(human_size 2048)"
echo "human_size(3221225472) = $(human_size 3221225472)"
echo "du_safe(~/.zshrc)      = $(du_safe "$HOME/.zshrc") bytes"
echo "du_safe(/does/not)     = $(du_safe /does/not/exist) bytes"
have npm && echo "have npm: yes" || echo "have npm: no"
log END "helpers_selftest=ok"
```

- [ ] **Step 3: Run self-test**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh
tail -n 4 ~/.mac-cleaner.log
```

Expected:
- `human_size(0) = 0 B`
- `human_size(2048) = 2.00 KB`
- `human_size(3221225472) = 3.00 GB`
- `du_safe(~/.zshrc)` shows a non-zero byte count.
- `du_safe(/does/not)` shows `0 bytes`.
- Log file has two fresh lines (START and END) with matching `run=<hex>`.

---

## Task 3: Cleanup category functions — package managers

**Files:**
- Modify: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

- [ ] **Step 1: Delete the helpers self-test block**

Remove the entire block starting with `# Quick helpers self-test (removed in Task 3)` and ending with `log END "helpers_selftest=ok"` from Task 2 Step 2. We'll replace it with the real `main` in Task 7.

- [ ] **Step 2: Add package-manager cleanup functions**

Append before the (now-deleted) self-test block's former position:

```bash
# ── cleanup functions: package managers ──────────────────

cleanup_npm_cache() {
  have npm || { log SKIP "category=npm_cache reason=tool_not_installed"; return 0; }
  run_cmd "npm cache clean --force" npm cache clean --force
}

cleanup_yarn_cache() {
  have yarn || { log SKIP "category=yarn_cache reason=tool_not_installed"; return 0; }
  local v major
  v="$(yarn --version 2>/dev/null || echo 0)"
  major="${v%%.*}"
  if [[ "$major" == "1" ]]; then
    run_cmd "yarn cache clean" yarn cache clean
  else
    run_cmd "yarn cache clean --all" yarn cache clean --all
  fi
}

cleanup_pnpm_store() {
  have pnpm || { log SKIP "category=pnpm_store reason=tool_not_installed"; return 0; }
  run_cmd "pnpm store prune" pnpm store prune
}

cleanup_brew() {
  have brew || { log SKIP "category=brew reason=tool_not_installed"; return 0; }
  run_cmd "brew cleanup -s"   brew cleanup -s
  run_cmd "brew autoremove"   brew autoremove
}

# Wrappers that call run_category with the right sizing path.
# For npm/yarn/pnpm we size the on-disk cache dir; for brew we use brew --cache.
category_npm_cache() {
  run_category "npm cache" "npm package download & tarball cache" \
    "$HOME/.npm" cleanup_npm_cache
}

category_yarn_cache() {
  # yarn v1: ~/Library/Caches/Yarn; yarn v2+: project-local, no global by default.
  # Use v1 path; yarn v2 cache clean is a no-op if nothing cached globally.
  local p="$HOME/Library/Caches/Yarn"
  run_category "yarn cache" "yarn (classic) global cache" "$p" cleanup_yarn_cache
}

category_pnpm_store() {
  local p="$HOME/Library/pnpm/store"
  [[ -d "$p" ]] || p="$HOME/.pnpm-store"
  run_category "pnpm store" "pnpm content-addressable store" "$p" cleanup_pnpm_store
}

category_brew() {
  local p
  if have brew; then p="$(brew --cache 2>/dev/null || echo /tmp/does-not-exist)"; else p="-"; fi
  run_category "Homebrew" "old versions, downloads, autoremove unused" "$p" cleanup_brew
}
```

- [ ] **Step 3: Add a temporary main to smoke-test these categories**

At the bottom of the file (where the self-test used to be), add:

```bash
main() {
  log START "dry_run=$DRY_RUN yes=$ASSUME_YES"
  printf '%smac-cleaner%s — run %s\n' "$C_BOLD" "$C_RESET" "$RUN_ID"
  (( DRY_RUN )) && printf '%s(dry-run: nothing will be deleted)%s\n' "$C_YELLOW" "$C_RESET"

  category_npm_cache
  category_yarn_cache
  category_pnpm_store
  category_brew

  printf '\n%s── Summary ────────────────────%s\n' "$C_BOLD" "$C_RESET"
  printf '  Freed %s across %d categories\n' "$(human_size "$TOTAL_FREED")" "$CATEGORIES_CLEANED"
  printf '  Log: %s\n' "$LOG_FILE"
  log END "freed_total=$TOTAL_FREED categories_cleaned=$CATEGORIES_CLEANED"
}

main
```

- [ ] **Step 4: Dry-run smoke test**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run --yes
```

Expected output structure:
- Banner `mac-cleaner — run <hex>` followed by `(dry-run: ...)`.
- Four sections: `npm cache`, `yarn cache`, `pnpm store`, `Homebrew`.
- Each section prints its size and either `[dry-run] <cmd>` or `already empty, skipping` or `tool_not_installed` skip.
- Summary shows `Freed 0 B` (because dry-run doesn't delete) across N categories.
- Log file has START, the per-category events, and END.

---

## Task 4: Cleanup category functions — Xcode & iOS

**Files:**
- Modify: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

- [ ] **Step 1: Add Xcode / iOS cleanup functions**

Append after the package-manager category wrappers:

```bash
# ── cleanup functions: Xcode & iOS ───────────────────────

cleanup_xcode_derived() {
  run_cmd "rm -rf ~/Library/Developer/Xcode/DerivedData/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"*'
}

cleanup_xcode_archives() {
  run_cmd "rm -rf ~/Library/Developer/Xcode/Archives/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/Xcode/Archives/"*'
}

cleanup_ios_sim() {
  have xcrun || { log SKIP "category=ios_sim reason=tool_not_installed"; return 0; }
  run_cmd "xcrun simctl delete unavailable" xcrun simctl delete unavailable
}

cleanup_cocoapods() {
  run_cmd "rm -rf ~/Library/Caches/CocoaPods" \
    zsh -c 'rm -rf "$HOME/Library/Caches/CocoaPods"'
}

category_xcode_derived() {
  run_category "Xcode DerivedData" "build intermediates, regenerated on next build" \
    "$HOME/Library/Developer/Xcode/DerivedData" cleanup_xcode_derived
}

# Archives needs a bespoke wrapper (double-prompt), not run_category.
category_xcode_archives() {
  local name="Xcode Archives"
  local p="$HOME/Library/Developer/Xcode/Archives"
  section "$name"
  printf '  %sWARNING: archives are your App Store submission records.%s\n' "$C_RED" "$C_RESET"
  printf '  Location: %s\n' "$p"
  local before
  before="$(du_safe "$p")"
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if (( before == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=xcode_archives reason=empty"
    return 0
  fi

  if ! confirm "Delete Xcode Archives?"; then
    log DECLINE "category=xcode_archives size_bytes=$before"
    return 0
  fi

  # Second prompt: require the literal string DELETE even under --yes.
  printf '  %sType DELETE (all caps) to confirm:%s ' "$C_RED" "$C_RESET"
  local confirm_text
  read -r confirm_text
  if [[ "$confirm_text" != "DELETE" ]]; then
    printf '  aborted (did not type DELETE)\n'
    log DECLINE "category=xcode_archives stage=double_prompt"
    return 0
  fi

  cleanup_xcode_archives || {
    log ERROR "category=xcode_archives rc=$?"
    return 0
  }

  local after freed
  after="$(du_safe "$p")"
  freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=xcode_archives freed_bytes=$freed"
}

category_ios_sim() {
  # No meaningful size metric here — xcrun decides what to delete.
  run_category "iOS Simulators" "unavailable simulator devices (runtimes you uninstalled)" \
    "-" cleanup_ios_sim
}

category_cocoapods() {
  run_category "CocoaPods cache" "downloaded pod specs & sources" \
    "$HOME/Library/Caches/CocoaPods" cleanup_cocoapods
}
```

- [ ] **Step 2: Wire into main**

Change the `main` function to add these categories after `category_brew`:

```bash
  category_brew
  category_xcode_derived
  category_xcode_archives
  category_ios_sim
  category_cocoapods
```

- [ ] **Step 3: Dry-run smoke test**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run
```

When prompted for Xcode Archives, answer `y`, then when asked for `DELETE` type `DELETE`. Expected:
- Archives section prints the red warning, size, and both prompts.
- Under `--dry-run`, after typing `DELETE`, the `rm -rf` command is shown as `[dry-run]` not executed.
- Archives section exits without deleting even though you confirmed.

Also run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run
```
and decline Archives (answer `n`). Confirm log has `DECLINE category=xcode_archives`.

Also test the DELETE-mismatch path: answer `y`, then type `delete` (lowercase). Confirm it aborts and logs `DECLINE stage=double_prompt`.

---

## Task 5: Cleanup category functions — Gradle, Android, Expo, pip, Trash

**Files:**
- Modify: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

- [ ] **Step 1: Add the remaining cleanup functions**

Append after the Xcode section:

```bash
# ── cleanup functions: JVM / Android / JS tooling / misc ─

cleanup_gradle() {
  run_cmd "rm -rf ~/.gradle/caches" \
    zsh -c 'rm -rf "$HOME/.gradle/caches"'
}

cleanup_android_build() {
  run_cmd "rm -rf ~/.android/build-cache" \
    zsh -c 'rm -rf "$HOME/.android/build-cache"'
}

cleanup_expo_metro() {
  # ~/.expo is user-level state; some of it is caches, some is auth.
  # Safer: wipe the cache subdir only, not the whole ~/.expo.
  run_cmd "rm -rf ~/.expo/cache" \
    zsh -c 'rm -rf "$HOME/.expo/cache"'
  run_cmd "rm -rf /tmp/metro-*"      zsh -c 'rm -rf /tmp/metro-*'
  run_cmd "rm -rf /tmp/haste-map-*"  zsh -c 'rm -rf /tmp/haste-map-*'
  run_cmd "rm -rf /tmp/react-*"      zsh -c 'rm -rf /tmp/react-*'
}

cleanup_pip_cache() {
  have pip3 || have pip || { log SKIP "category=pip_cache reason=tool_not_installed"; return 0; }
  if have pip3; then
    run_cmd "pip3 cache purge" pip3 cache purge
  else
    run_cmd "pip cache purge"  pip cache purge
  fi
}

cleanup_trash() {
  run_cmd "rm -rf ~/.Trash/*" \
    zsh -c 'rm -rf "$HOME/.Trash/"*'
}

category_gradle() {
  run_category "Gradle caches" "~/.gradle/caches (regenerated on next build)" \
    "$HOME/.gradle/caches" cleanup_gradle
}

category_android_build() {
  run_category "Android build cache" "~/.android/build-cache" \
    "$HOME/.android/build-cache" cleanup_android_build
}

category_expo_metro() {
  # Sum the ephemeral paths; use a temp file since du won't take multiple missing paths cleanly.
  local total=0 p
  for p in "$HOME/.expo/cache" /tmp/metro-* /tmp/haste-map-* /tmp/react-*; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  # Inline the flow rather than going through run_category, since sizing is multi-path.
  section "Expo / Metro"
  printf '  ~/.expo/cache, /tmp/metro-*, /tmp/haste-map-*, /tmp/react-*\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=expo_metro reason=empty"
    return 0
  fi
  if ! confirm "Clean this?"; then
    log DECLINE "category=expo_metro size_bytes=$total"
    return 0
  fi
  cleanup_expo_metro || { log ERROR "category=expo_metro rc=$?"; return 0; }
  # Re-measure (best-effort).
  local after=0
  for p in "$HOME/.expo/cache" /tmp/metro-* /tmp/haste-map-* /tmp/react-*; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=expo_metro freed_bytes=$freed"
}

category_pip_cache() {
  # pip cache dir is managed by pip itself; size via `pip cache dir`.
  local p=""
  if have pip3; then p="$(pip3 cache dir 2>/dev/null || true)"
  elif have pip; then p="$(pip cache dir 2>/dev/null || true)"
  fi
  [[ -z "$p" ]] && p="-"
  run_category "pip cache" "$(have pip3 && echo pip3 || echo pip) cache" "$p" cleanup_pip_cache
}

category_trash() {
  run_category "Trash" "~/.Trash" "$HOME/.Trash" cleanup_trash
}
```

- [ ] **Step 2: Wire into main**

Change `main` to append:

```bash
  category_cocoapods
  category_gradle
  category_android_build
  category_expo_metro
  category_pip_cache
  category_trash
```

- [ ] **Step 3: Dry-run smoke test**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run --yes
```

Expected: every new section shows a size line and a `[dry-run] rm -rf ...` or `[dry-run] pip cache purge`. No errors. Log has CLEAN/SKIP lines for each.

---

## Task 6: Version audit — outdated global npm packages and tool versions

**Files:**
- Modify: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

- [ ] **Step 1: Add version-audit helpers**

Append after the category functions:

```bash
# ── version audit ────────────────────────────────────────

# Semver compare — echo -1/0/1 for a<b/a==b/a>b. Strips leading 'v'.
semver_cmp() {
  local a="${1#v}" b="${2#v}"
  if [[ "$a" == "$b" ]]; then echo 0; return; fi
  local winner
  winner="$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)"
  if [[ "$winner" == "$a" ]]; then echo 1; else echo -1; fi
}

npm_latest() {
  # echo latest version of an npm-registry package, empty on failure
  have npm || { echo ""; return; }
  npm view "$1" version 2>/dev/null || echo ""
}

check_tool_versions() {
  section "Tool versions"
  local tool current latest cmp
  for tool in npm yarn pnpm; do
    have "$tool" || { printf '  %-6s %s(not installed)%s\n' "$tool" "$C_DIM" "$C_RESET"; continue; }
    current="$("$tool" --version 2>/dev/null | head -1)"
    latest="$(npm_latest "$tool")"
    if [[ -z "$latest" ]]; then
      printf '  %-6s %s  (latest: unknown)\n' "$tool" "$current"
      continue
    fi
    cmp="$(semver_cmp "$current" "$latest")"
    if [[ "$cmp" == "-1" ]]; then
      printf '  %-6s %s%s%s → latest %s%s%s\n' "$tool" "$C_YELLOW" "$current" "$C_RESET" "$C_GREEN" "$latest" "$C_RESET"
      if confirm "Update $tool to $latest?"; then
        run_cmd "npm i -g $tool@latest" npm i -g "$tool@latest"
        log UPDATE "tool=$tool from=$current to=$latest"
      else
        log DECLINE "tool=$tool stage=update current=$current latest=$latest"
      fi
    else
      printf '  %-6s %s %s(up-to-date)%s\n' "$tool" "$current" "$C_DIM" "$C_RESET"
    fi
  done

  # Node: report-only
  if have node; then
    current="$(node --version)"
    printf '  %-6s %s %s(report-only; upgrade via nvm/brew/installer)%s\n' "node" "$current" "$C_DIM" "$C_RESET"
    log INFO "tool=node current=$current"
  fi
}

check_outdated_globals() {
  have npm || { log SKIP "category=npm_globals reason=tool_not_installed"; return 0; }
  section "Outdated global npm packages"
  # --parseable output: path:pkg@wanted:pkg@current:pkg@latest
  local out
  out="$(npm outdated -g --parseable --depth=0 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    printf '  %snone%s\n' "$C_GREEN" "$C_RESET"
    return 0
  fi
  local line pkg current latest
  while IFS= read -r line; do
    # parseable fields separated by ':' — split manually
    # Fourth field is pkg@latest, third is pkg@current
    local f3 f4
    f3="$(echo "$line" | awk -F: '{print $(NF-1)}')"
    f4="$(echo "$line" | awk -F: '{print $NF}')"
    pkg="${f4%@*}"
    current="${f3##*@}"
    latest="${f4##*@}"
    printf '  %-30s %s%s%s → %s%s%s\n' "$pkg" "$C_YELLOW" "$current" "$C_RESET" "$C_GREEN" "$latest" "$C_RESET"
    if confirm "Update $pkg to $latest?"; then
      run_cmd "npm i -g ${pkg}@latest" npm i -g "${pkg}@latest"
      log UPDATE "pkg=$pkg from=$current to=$latest"
    else
      log DECLINE "pkg=$pkg stage=update current=$current latest=$latest"
    fi
  done <<< "$out"
}
```

- [ ] **Step 2: Wire into main before the summary**

Modify `main` so the order is:

```bash
  category_trash
  check_tool_versions
  check_outdated_globals

  printf '\n%s── Summary ────────────────────%s\n' "$C_BOLD" "$C_RESET"
```

- [ ] **Step 3: Dry-run smoke test**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run
```

When the tool-versions section fires, answer `n` to any update prompts. Expected:
- `Tool versions` section lists npm, yarn, pnpm with a version each; those at latest show `(up-to-date)`, others show current → latest and a prompt.
- `Outdated global npm packages` shows either `none` or a list of packages with prompts.
- Declining leaves the log with `DECLINE tool=...` lines.
- Dry-run prints `[dry-run] npm i -g ...` when you answer `y` (try it at least once).

---

## Task 7: Final main, banner, and summary polish

**Files:**
- Modify: `/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh`

- [ ] **Step 1: Replace `main` with the final version**

Replace the entire current `main` function at the bottom of the file with:

```bash
main() {
  log START "dry_run=$DRY_RUN yes=$ASSUME_YES"

  printf '%smac-cleaner%s — run %s\n' "$C_BOLD" "$C_RESET" "$RUN_ID"
  printf '  log: %s\n' "$LOG_FILE"
  if (( DRY_RUN )); then
    printf '  %s(dry-run: nothing will be deleted)%s\n' "$C_YELLOW" "$C_RESET"
  fi
  if (( ASSUME_YES )); then
    printf '  %s(--yes: prompts auto-accepted; Xcode Archives still double-prompts)%s\n' "$C_YELLOW" "$C_RESET"
  fi

  # Order: smaller/safer first → bigger dev-tool wins → version audit last.
  category_npm_cache
  category_yarn_cache
  category_pnpm_store
  category_brew
  category_xcode_derived
  category_xcode_archives
  category_ios_sim
  category_cocoapods
  category_gradle
  category_android_build
  category_expo_metro
  category_pip_cache
  category_trash

  check_tool_versions
  check_outdated_globals

  printf '\n%s── Summary ────────────────────%s\n' "$C_BOLD" "$C_RESET"
  printf '  Freed %s%s%s across %d categories\n' \
    "$C_GREEN" "$(human_size "$TOTAL_FREED")" "$C_RESET" "$CATEGORIES_CLEANED"
  printf '  Log:  %s\n' "$LOG_FILE"
  log END "freed_total=$TOTAL_FREED categories_cleaned=$CATEGORIES_CLEANED"
}

main
```

- [ ] **Step 2: Full dry-run walkthrough**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run
```

Walk through every prompt. Expected:
- Banner at top with `(dry-run: ...)`.
- 13 cleanup sections in the documented order.
- 2 audit sections.
- Summary at bottom reporting `Freed 0 B` (dry run) across 0 categories (no DECLINE counts).
- Log has matching START/END with a single RUN_ID.

- [ ] **Step 3: `--yes` dry-run**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --dry-run --yes
```

When Xcode Archives double-prompts, type `DELETE`. Expected:
- Every other section auto-accepts (no prompts).
- Archives prints the warning, still asks for `DELETE` (because `--yes` doesn't skip the second stage per design).
- Every destructive command appears as `[dry-run] <command>`.

- [ ] **Step 4: Help output**

Run:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh --help
```

Expected: usage block, exit 0.

---

## Task 8: Real-run acceptance (manual)

**Files:** (none — user-run verification)

- [ ] **Step 1: User runs for real**

User runs:
```bash
/Users/lion/Documents/Projects/mine/mac-cleaner/mac-cleaner.sh
```

Walk through interactively, accepting categories that feel safe and declining anything that doesn't. Decline Xcode Archives unless the user has a specific reason to clear them.

- [ ] **Step 2: Inspect log**

```bash
tail -n 50 ~/.mac-cleaner.log
```

Expected: one START, a mix of CLEAN/SKIP/DECLINE/INFO lines, one END, with consistent `run=<hex>`. `freed_total` should be > 0.

- [ ] **Step 3: Verify df before/after (optional)**

```bash
df -h / | awk 'NR==2 {print $4 " available"}'
```

Compare with a snapshot taken before the run.

---

## Self-Review

**Spec coverage:**

| Spec section | Covered by |
|---|---|
| Flags: `--dry-run`, `--yes`, `--help` | Task 1 |
| Strict mode, `nullglob` | Task 1 |
| `log`, `have`, `human_size`, `du_safe`, `confirm`, `run_cmd`, `section` helpers | Task 2 |
| `run_category` dispatcher | Task 2 |
| npm / yarn / pnpm / brew categories | Task 3 |
| Xcode DerivedData, Archives (double-prompt), iOS sim, CocoaPods | Task 4 |
| Gradle, Android build, Expo/Metro, pip, Trash | Task 5 |
| Outdated globals + tool version audit with update prompts | Task 6 |
| Banner, summary, order of operations | Task 7 |
| Log format (START/SKIP/CLEAN/DECLINE/ERROR/UPDATE/INFO/END with run id) | Tasks 2–7 |
| No generic `~/Library/Caches/*` sweep | By omission (intentionally not in any task) |
| Real-run acceptance test | Task 8 |

All spec requirements mapped. No gaps.

**Placeholder scan:** No TBDs, no "add appropriate error handling", every code step contains runnable code.

**Type/name consistency:**
- `run_category <name> <desc> <path> <cleanup_fn>` signature is used consistently in Task 3/4/5.
- `cleanup_<x>` / `category_<x>` naming consistent across all categories.
- Log event names consistent: `START`, `SKIP`, `CLEAN`, `DECLINE`, `ERROR`, `UPDATE`, `INFO`, `END`.
- Global variables (`DRY_RUN`, `ASSUME_YES`, `LOG_FILE`, `RUN_ID`, `TOTAL_FREED`, `CATEGORIES_CLEANED`) used with the same spelling throughout.
- `semver_cmp` signature `semver_cmp a b` matches how `check_tool_versions` calls it.

No inconsistencies found.
