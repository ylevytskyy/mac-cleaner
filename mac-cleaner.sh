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
SCRIPT_NAME="${${ZSH_ARGZERO:-$0}:t}"
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
  ${SCRIPT_NAME} [--dry-run] [--yes|-y] [--help|-h]

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
  if   (( b >= 1073741824 )); then printf '%.2f GB' "$(( b * 1.0 / 1073741824 ))"
  elif (( b >= 1048576 ));    then printf '%.2f MB' "$(( b * 1.0 / 1048576 ))"
  elif (( b >= 1024 ));       then printf '%.2f KB' "$(( b * 1.0 / 1024 ))"
  else                              printf '%d B'    "$b"
  fi
}

du_safe() {
  # echo size-in-bytes of path, 0 if missing
  local path="$1"
  if [[ ! -e "$path" ]]; then echo 0; return; fi
  # du -sk gives KB; multiply by 1024. Use BSD du (macOS default).
  local kb
  kb="$(/usr/bin/du -sk "$path" 2>/dev/null | /usr/bin/awk '{print $1}')"
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
category_npm_cache() {
  run_category "npm cache" "npm package download & tarball cache" \
    "$HOME/.npm" cleanup_npm_cache
}

category_yarn_cache() {
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
  local total=0 p
  for p in "$HOME/.expo/cache" /tmp/metro-* /tmp/haste-map-* /tmp/react-*; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
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
  # --parseable format: path:pkg@wanted:pkg@current:pkg@latest:global
  local line pkg current latest f3 f4
  while IFS= read -r line; do
    f3="$(echo "$line" | awk -F: '{print $3}')"
    f4="$(echo "$line" | awk -F: '{print $4}')"
    pkg="${f3%@*}"
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
