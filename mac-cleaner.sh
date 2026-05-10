#!/usr/bin/env zsh
# mac-cleaner — interactive macOS developer-cache cleaner
# Usage: ./mac-cleaner.sh [--dry-run] [--yes|-y] [--help|-h]

set -euo pipefail
setopt nullglob

# ── globals ──────────────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
PREPARE_PNPM=0
INCLUDE_VOLUMES=0
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
  ${SCRIPT_NAME} [--dry-run] [--yes|-y] [--prepare-for-pnpm] [--include-volumes] [--help|-h]

Flags:
  --dry-run   Show what would be deleted without deleting. Still prompts.
  --yes, -y   Skip y/N prompts (Xcode Archives still double-prompts).
  --prepare-for-pnpm  Clean only npm/yarn caches across nvm + brew Node versions; skip everything else.
  --include-volumes   Also prune Docker/Podman named volumes (DESTROYS DATA). Off by default.
  --help, -h  This message.

Log: ${LOG_FILE}
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --prepare-for-pnpm) PREPARE_PNPM=1 ;;
    --include-volumes) INCLUDE_VOLUMES=1 ;;
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

cleanup_npm_yarn_all_nvm() {
  # Each nvm-installed Node ships its own npm (and optionally yarn) with
  # potentially a different `cache` setting via per-version .npmrc.
  # Invoke each version's binaries so custom cache paths also get purged.
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local versions_dir="$nvm_dir/versions/node"
  local vpath vname vbin yarn_v
  for vpath in "$versions_dir"/*; do
    [[ -d "$vpath" ]] || continue
    vname="${vpath:t}"
    vbin="$vpath/bin"
    if [[ -x "$vbin/npm" ]]; then
      run_cmd "($vname) npm cache clean --force" "$vbin/npm" cache clean --force
    fi
    if [[ -x "$vbin/yarn" ]]; then
      yarn_v="$("$vbin/yarn" --version 2>/dev/null || echo 0)"
      if [[ "${yarn_v%%.*}" == "1" ]]; then
        run_cmd "($vname) yarn cache clean" "$vbin/yarn" cache clean
      else
        run_cmd "($vname) yarn cache clean --all" "$vbin/yarn" cache clean --all
      fi
    fi
  done
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

category_npm_yarn_all_nvm() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local versions_dir="$nvm_dir/versions/node"
  section "npm/yarn (all nvm Node versions)"
  if [[ ! -d "$versions_dir" ]]; then
    printf '  %snvm not found at %s, skipping%s\n' "$C_DIM" "$nvm_dir" "$C_RESET"
    log SKIP "category=npm_yarn_all_nvm reason=nvm_not_installed"
    return 0
  fi
  local count=0 vpath
  for vpath in "$versions_dir"/*; do
    [[ -d "$vpath" ]] && count=$(( count + 1 ))
  done
  if (( count == 0 )); then
    printf '  %sno Node versions installed under nvm, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=npm_yarn_all_nvm reason=no_versions"
    return 0
  fi
  printf '  Found %d nvm Node version(s); invokes each bundled npm/yarn.\n' "$count"
  printf '  Catches per-version .npmrc cache overrides the default categories miss.\n'

  # Shared default cache paths — sized to report freed bytes. Per-version
  # custom caches still get `cache clean`'d but are not summed here.
  local npm_path="$HOME/.npm" yarn_path="$HOME/Library/Caches/Yarn"
  local before=0
  [[ -d "$npm_path" ]]  && before=$(( before + $(du_safe "$npm_path") ))
  [[ -d "$yarn_path" ]] && before=$(( before + $(du_safe "$yarn_path") ))
  printf '  Size (shared caches): %s%s%s\n' "$C_YELLOW" "$(human_size "$before")" "$C_RESET"

  if ! confirm "Clean across all $count nvm version(s)?"; then
    log DECLINE "category=npm_yarn_all_nvm size_bytes=$before"
    return 0
  fi
  cleanup_npm_yarn_all_nvm || { log ERROR "category=npm_yarn_all_nvm rc=$?"; return 0; }

  local after=0
  [[ -d "$npm_path" ]]  && after=$(( after + $(du_safe "$npm_path") ))
  [[ -d "$yarn_path" ]] && after=$(( after + $(du_safe "$yarn_path") ))
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ swept %d version(s), freed %s%s\n' "$C_GREEN" "$count" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=npm_yarn_all_nvm freed_bytes=$freed versions=$count"
}

cleanup_npm_yarn_all_brew() {
  # Each brew-installed Node formula ships its own npm; corepack-shimmed yarn
  # may also live under that prefix's bin. Per-formula .npmrc may set a custom
  # cache path, so invoke each binary explicitly.
  have brew || return 0
  local formulas formula prefix vbin yarn_v
  formulas="$(brew list --formula 2>/dev/null | grep -E '^node(@[0-9.]+)?$' || true)"
  [[ -n "$formulas" ]] || return 0
  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    prefix="$(brew --prefix "$formula" 2>/dev/null)"
    [[ -n "$prefix" && -d "$prefix" ]] || continue
    vbin="$prefix/bin"
    if [[ -x "$vbin/npm" ]]; then
      run_cmd "($formula) npm cache clean --force" "$vbin/npm" cache clean --force
    fi
    if [[ -x "$vbin/yarn" ]]; then
      yarn_v="$("$vbin/yarn" --version 2>/dev/null || echo 0)"
      if [[ "${yarn_v%%.*}" == "1" ]]; then
        run_cmd "($formula) yarn cache clean" "$vbin/yarn" cache clean
      else
        run_cmd "($formula) yarn cache clean --all" "$vbin/yarn" cache clean --all
      fi
    fi
  done <<< "$formulas"
}

category_npm_yarn_all_brew() {
  section "npm/yarn (all brew Node formulas)"
  if ! have brew; then
    printf '  %sbrew not installed, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=npm_yarn_all_brew reason=tool_not_installed"
    return 0
  fi
  local formulas
  formulas="$(brew list --formula 2>/dev/null | grep -E '^node(@[0-9.]+)?$' || true)"
  if [[ -z "$formulas" ]]; then
    printf '  %sno brew Node formulas installed, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=npm_yarn_all_brew reason=no_versions"
    return 0
  fi
  local count
  count="$(printf '%s\n' "$formulas" | wc -l | tr -d ' ')"
  printf '  Found %d brew Node formula(s); invokes each bundled npm/yarn.\n' "$count"
  printf '  Catches per-formula .npmrc cache overrides the default categories miss.\n'

  # Shared default cache paths — sized to report freed bytes. Per-formula
  # custom caches still get `cache clean`'d but are not summed here.
  local npm_path="$HOME/.npm" yarn_path="$HOME/Library/Caches/Yarn"
  local before=0
  [[ -d "$npm_path" ]]  && before=$(( before + $(du_safe "$npm_path") ))
  [[ -d "$yarn_path" ]] && before=$(( before + $(du_safe "$yarn_path") ))
  printf '  Size (shared caches): %s%s%s\n' "$C_YELLOW" "$(human_size "$before")" "$C_RESET"

  if ! confirm "Clean across all $count brew Node formula(s)?"; then
    log DECLINE "category=npm_yarn_all_brew size_bytes=$before"
    return 0
  fi
  cleanup_npm_yarn_all_brew || { log ERROR "category=npm_yarn_all_brew rc=$?"; return 0; }

  local after=0
  [[ -d "$npm_path" ]]  && after=$(( after + $(du_safe "$npm_path") ))
  [[ -d "$yarn_path" ]] && after=$(( after + $(du_safe "$yarn_path") ))
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ swept %d formula(s), freed %s%s\n' "$C_GREEN" "$count" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=npm_yarn_all_brew freed_bytes=$freed formulas=$count"
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
  # Gradle daemon & Kotlin LSP hold file locks in ~/.gradle/caches; rm -rf
  # bails on the first locked file, leaving the cache half-deleted with the
  # metadata journal out of sync with jars-9/transforms-*. That is the shape
  # of "Android builds mysteriously fail after cleanup". Stop daemons first.
  if have gradle; then
    run_cmd "gradle --stop" gradle --stop || true
  else
    run_cmd "pkill -f GradleDaemon|KotlinCompileDaemon (best-effort)" \
      zsh -c 'pkill -f "GradleDaemon|KotlinCompileDaemon" 2>/dev/null; true'
  fi

  local rc=0
  run_cmd "rm -rf ~/.gradle/caches" \
    zsh -c 'rm -rf "$HOME/.gradle/caches"' || rc=$?

  if (( rc != 0 )); then
    printf '  %sWARNING:%s Gradle cache partially deleted — an IDE or daemon held file locks.\n' "$C_RED" "$C_RESET"
    printf '           Android builds will fail until this completes. Close Android Studio,\n'
    printf '           then re-run: %sgradle --stop && rm -rf ~/.gradle/caches%s\n' "$C_BOLD" "$C_RESET"
    log WARN "category=gradle partial_delete=true"
  fi
  return $rc
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

# ── cleanup functions: app caches, temp, dev dotcaches ───

# category_app_caches — iterates ~/Library/Caches immediate children,
# applies literal-name denylist + prefix-pattern denylist, and special-cases
# Google/ with an Android Studio running-process check.
# This is the single allowed exception to the "no dynamic rm -rf" rule:
#   - Parent is hardcoded ($HOME/Library/Caches)
#   - Iteration is over immediate children only (no ** recursion)
#   - Every candidate is checked against a hardcoded denylist first
#   - The deletion target is the matched child's resolved absolute path
category_app_caches() {
  local CACHES_DIR="$HOME/Library/Caches"

  # Literal names to deny (exact match on child basename)
  local -a DENY_NAMES=(
    askpermissiond
    ccache
    chrome_crashpad_handler
    CloudKit
    "com.anthropic.claudefordesktop"
    "com.apple.Music"
    composer
    "Docker Desktop"
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
    org.swift.swiftpm
    PassKit
    pip
    pnpm
    SentryCrash
    ssu
    TemporaryItems
    Trae
    "Viber Media S.à r.l"
    Yarn
    com.microsoft.autoupdate.fba
    com.raycast.macos
    com.google.GoogleUpdater
    com.plausiblelabs.crashreporter.data
    com.github.CopilotForXcode
  )

  # Returns 0 (denied) if the child name matches a literal deny entry or a
  # prefix pattern; returns 1 (allowed) otherwise.
  # Special sentinel "Google" is NOT in this list — handled separately below.
  _app_caches_is_denied() {
    local name="$1"
    # Literal match
    local d
    for d in "${DENY_NAMES[@]}"; do
      [[ "$name" == "$d" ]] && return 0
    done
    # Prefix patterns: com.apple.* and *.ShipIt
    [[ "$name" == com.apple.* ]] && return 0
    [[ "$name" == *.ShipIt    ]] && return 0
    return 1
  }

  # ── size: sum du_safe across allowed children (post-denylist) ──────────
  # Glob qualifier (N/) restricts matches to directories only. Top-level files
  # in ~/Library/Caches (profile pictures, INSTALLATION marker, etc.) are user
  # content / app state, not caches — caches are always directories by Apple
  # convention.
  local total=0
  local child name
  for child in "$CACHES_DIR"/*(N/); do
    name="${child:t}"
    # Google/ is special-cased: always count its safe subfolders toward size
    if [[ "$name" == "Google" ]]; then
      local gsub
      for gsub in "$child"/AndroidStudio*(N) "$child/Chrome"; do
        [[ -e "$gsub" ]] && total=$(( total + $(du_safe "$gsub") ))
      done
      continue
    fi
    _app_caches_is_denied "$name" && continue
    total=$(( total + $(du_safe "$child") ))
  done

  section "macOS app caches"
  printf '  ~/Library/Caches — immediate children (denylist-filtered)\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=app_caches reason=empty"
    return 0
  fi

  if ! confirm "Clean this?"; then
    log DECLINE "category=app_caches size_bytes=$total"
    return 0
  fi

  # ── cleanup ────────────────────────────────────────────────────────────
  local before="$total"
  for child in "$CACHES_DIR"/*(N/); do
    name="${child:t}"

    # Special case: Google/ — sub-iterate with Android Studio check
    if [[ "$name" == "Google" ]]; then
      # Check if Android Studio is running
      if pgrep -f '/Applications/Android Studio.app' >/dev/null 2>&1; then
        printf '  %sWARNING:%s Android Studio is running. Close it before clearing its caches; skipping Google/AndroidStudio*/\n' \
          "$C_YELLOW" "$C_RESET"
        log SKIP "category=app_caches reason=android_studio_running entry=Google/AndroidStudio*"
      else
        # Delete each AndroidStudio* child
        local as_sub
        for as_sub in "$child"/AndroidStudio*(N); do
          [[ -e "$as_sub" ]] || continue
          local as_name="${as_sub:t}"
          run_cmd "rm -rf ~/Library/Caches/Google/$as_name" \
            zsh -c "rm -rf ${(q)as_sub}"
        done
      fi
      # Always attempt Google/Chrome (browser HTTP cache, no IDE-lock concern)
      if [[ -e "$child/Chrome" ]]; then
        run_cmd "rm -rf ~/Library/Caches/Google/Chrome" \
          zsh -c "rm -rf ${(q)child}/Chrome"
      fi
      # Any other Google/ child defaults to DENY — do nothing
      continue
    fi

    if _app_caches_is_denied "$name"; then
      log SKIP "category=app_caches reason=denylist entry=$name"
      continue
    fi

    run_cmd "rm -rf ~/Library/Caches/$name" \
      zsh -c "rm -rf ${(q)child}"
  done

  # ── measure freed ─────────────────────────────────────────────────────
  local after=0
  for child in "$CACHES_DIR"/*(N/); do
    name="${child:t}"
    if [[ "$name" == "Google" ]]; then
      local gsub2
      for gsub2 in "$child"/AndroidStudio*(N) "$child/Chrome"; do
        [[ -e "$gsub2" ]] && after=$(( after + $(du_safe "$gsub2") ))
      done
      continue
    fi
    _app_caches_is_denied "$name" && continue
    after=$(( after + $(du_safe "$child") ))
  done

  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=app_caches freed_bytes=$freed"
}

cleanup_temp_parent() {
  # cleanup_temp_parent <parent-dir>
  # Deletes user-owned entries older than 7 days via find; never removes parent.
  local parent="$1"
  local me
  me="$(id -un)"
  run_cmd "find $parent -mindepth 1 -maxdepth 1 -user $me -mtime +7 -exec rm -rf {} +" \
    zsh -c "find ${(q)parent} -mindepth 1 -maxdepth 1 -user ${(q)me} -mtime +7 -exec rm -rf {} +"
}

_temp_size_parent() {
  # echo bytes of user-owned entries older than 7 days in parent dir
  local parent="$1"
  [[ -d "$parent" ]] || { echo 0; return; }
  local me
  me="$(id -un)"
  local kb
  kb="$(find "$parent" -mindepth 1 -maxdepth 1 -user "$me" -mtime +7 -print0 2>/dev/null \
        | xargs -0 /usr/bin/du -sk 2>/dev/null \
        | /usr/bin/awk '{s+=$1} END{print s+0}')"
  echo "$(( ${kb:-0} * 1024 ))"
}

category_temp() {
  local tmp_dir="/tmp"
  local user_tmp="${TMPDIR%/}"
  # Resolve /tmp -> /private/tmp on macOS for consistent comparison.
  # readlink returns a relative path ("private/tmp") on macOS, so prepend / if needed.
  if [[ -L "$tmp_dir" ]]; then
    local resolved
    resolved="$(readlink "$tmp_dir")"
    [[ "$resolved" != /* ]] && resolved="/$resolved"
    tmp_dir="$resolved"
  fi

  # Size: sum >7-day user-owned entries across both parents
  local total=0 sz
  sz="$(_temp_size_parent "$tmp_dir")"
  total=$(( total + sz ))
  if [[ -n "$user_tmp" && "$user_tmp" != "$tmp_dir" ]]; then
    sz="$(_temp_size_parent "$user_tmp")"
    total=$(( total + sz ))
  fi

  section "Temp directories"
  printf '  /tmp and $TMPDIR — user-owned entries older than 7 days\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=temp reason=empty"
    return 0
  fi

  if ! confirm "Clean this?"; then
    log DECLINE "category=temp size_bytes=$total"
    return 0
  fi

  local rc=0
  cleanup_temp_parent "$tmp_dir" || rc=$?
  if [[ -n "$user_tmp" && "$user_tmp" != "$tmp_dir" ]]; then
    cleanup_temp_parent "$user_tmp" || rc=$?
  fi

  if (( rc != 0 )); then
    printf '  %sERROR%s cleanup returned rc=%d (continuing)\n' "$C_RED" "$C_RESET" "$rc"
    log ERROR "category=temp rc=$rc"
    return 0
  fi

  local after=0
  sz="$(_temp_size_parent "$tmp_dir")"
  after=$(( after + sz ))
  if [[ -n "$user_tmp" && "$user_tmp" != "$tmp_dir" ]]; then
    sz="$(_temp_size_parent "$user_tmp")"
    after=$(( after + sz ))
  fi

  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=temp freed_bytes=$freed"
}

category_dev_dotcaches() {
  # Hardcoded list of known-safe cache subpaths under $HOME.
  # Each entry is a full subpath; no globbing of $HOME.
  local -a DEV_DOTCACHE_PATHS=(
    "$HOME/.cache/uv"
    "$HOME/.cache/puppeteer"
    "$HOME/.cache/chrome-devtools-mcp"
    "$HOME/.cache/node"
    "$HOME/.cache/prisma"
    "$HOME/.cache/mesa_shader_cache"
    "$HOME/.cache/pkg"
    "$HOME/.cache/vscode-ripgrep"
    "$HOME/.cache/gitstatus"
    "$HOME/.cache/tooling"
    "$HOME/.cache/zed"
    "$HOME/.cache/github-copilot"
    "$HOME/.cache/phpactor"
    "$HOME/.bun/install/cache"
    "$HOME/.bundle/cache"
    "$HOME/.gem/specs"
    "$HOME/.gluestack/cache"
    "$HOME/.javacpp/cache"
    "$HOME/.lldb/module_cache"
    "$HOME/.m2/repository"
    "$HOME/.openjfx/cache"
    "$HOME/.pub-cache/hosted"
    "$HOME/.skiko"
    "$HOME/.yarn/berry/cache"
    "$HOME/.hawtjni"
    "$HOME/.android/cache"
    "$HOME/.expo/android-apk-cache"
    "$HOME/.expo/ios-simulator-app-cache"
    "$HOME/.net/Updates"
  )

  # Size: sum du_safe across all extant entries
  local total=0 p
  for p in "${DEV_DOTCACHE_PATHS[@]}"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done

  section "Dev dotfolder caches"
  printf '  Hardcoded cache subpaths under ~/ (uv, puppeteer, bun, lldb, m2, pub, etc.)\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=dev_dotcaches reason=empty"
    return 0
  fi

  if ! confirm "Clean this?"; then
    log DECLINE "category=dev_dotcaches size_bytes=$total"
    return 0
  fi

  local before="$total"
  for p in "${DEV_DOTCACHE_PATHS[@]}"; do
    if [[ ! -e "$p" ]]; then
      # Strip $HOME prefix for a readable relative path in the log
      local rel="${p#$HOME/}"
      log SKIP "category=dev_dotcaches reason=missing entry=~/$rel"
      continue
    fi
    local rel="${p#$HOME/}"
    run_cmd "rm -rf ~/$rel" zsh -c "rm -rf ${(q)p}"
  done

  local after=0
  for p in "${DEV_DOTCACHE_PATHS[@]}"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done

  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=dev_dotcaches freed_bytes=$freed"
}

# ── cleanup functions: System Data categories ───────────
#
# These categories target buckets macOS reports as "System Data"
# (System Settings → General → Storage). Spec:
#   docs/superpowers/specs/2026-05-10-system-data-categories-design.md
#
# Convention: GUI apps the user interacts with (Xcode, Music, Mail,
# browsers) → skip-if-running. Background daemons (sccache, Bazel,
# Docker engine) → stop-then-clean inside the cleanup_* function.

# ── Xcode-family additions ──

cleanup_coresimulator_caches() {
  have xcrun && run_cmd "xcrun simctl shutdown all (best-effort)" \
    xcrun simctl shutdown all || true
  run_cmd "rm -rf ~/Library/Developer/CoreSimulator/Caches/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/CoreSimulator/Caches/"*'
}
category_coresimulator_caches() {
  if pgrep -x Simulator >/dev/null 2>&1; then
    section "CoreSimulator caches"
    printf '  %sSimulator.app is running. Close it and re-run.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=coresimulator_caches reason=app_running app=Simulator"
    return 0
  fi
  run_category "CoreSimulator caches" \
    "iOS Simulator dyld closures, regenerated on next sim boot" \
    "$HOME/Library/Developer/CoreSimulator/Caches" cleanup_coresimulator_caches
}

cleanup_xctest_xcpg_devices() {
  run_cmd "rm -rf ~/Library/Developer/XCTestDevices/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/XCTestDevices/"*'
  run_cmd "rm -rf ~/Library/Developer/XCPGDevices/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/XCPGDevices/"*'
}
category_xctest_xcpg_devices() {
  if pgrep -x Xcode >/dev/null 2>&1; then
    section "Xcode test/playground devices"
    printf '  %sXcode is running. Close it and re-run.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=xctest_xcpg_devices reason=app_running app=Xcode"
    return 0
  fi
  local total=0 p
  for p in "$HOME/Library/Developer/XCTestDevices" "$HOME/Library/Developer/XCPGDevices"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  section "Xcode test/playground devices"
  printf '  ~/Library/Developer/{XCTestDevices,XCPGDevices} — recreated on next test/preview run\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=xctest_xcpg_devices reason=empty"
    return 0
  fi
  if ! confirm "Clean this?"; then
    log DECLINE "category=xctest_xcpg_devices size_bytes=$total"
    return 0
  fi
  cleanup_xctest_xcpg_devices || { log ERROR "category=xctest_xcpg_devices rc=$?"; return 0; }
  local after=0
  for p in "$HOME/Library/Developer/XCTestDevices" "$HOME/Library/Developer/XCPGDevices"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=xctest_xcpg_devices freed_bytes=$freed"
}

cleanup_xcode_dt_cache() {
  run_cmd "rm -rf ~/Library/Caches/com.apple.dt.Xcode/*" \
    zsh -c 'rm -rf "$HOME/Library/Caches/com.apple.dt.Xcode/"*'
}
category_xcode_dt_cache() {
  if pgrep -x Xcode >/dev/null 2>&1; then
    section "Xcode app cache"
    printf '  %sXcode is running. Close it and re-run.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=xcode_dt_cache reason=app_running app=Xcode"
    return 0
  fi
  run_category "Xcode app cache" \
    "~/Library/Caches/com.apple.dt.Xcode (separate from DerivedData)" \
    "$HOME/Library/Caches/com.apple.dt.Xcode" cleanup_xcode_dt_cache
}

cleanup_xcode_device_logs() {
  run_cmd "rm -rf ~/Library/Developer/Xcode/DeviceLogs/*" \
    zsh -c 'rm -rf "$HOME/Library/Developer/Xcode/DeviceLogs/"*'
}
category_xcode_device_logs() {
  run_category "Xcode iOS device logs" \
    "historical crash logs from attached devices, re-collected on next attach" \
    "$HOME/Library/Developer/Xcode/DeviceLogs" cleanup_xcode_device_logs
}

# ── Language-toolchain additions ──

cleanup_swiftpm() {
  if have swift; then
    run_cmd "swift package purge-cache" swift package purge-cache
  else
    run_cmd "rm -rf ~/Library/Caches/org.swift.swiftpm" \
      zsh -c 'rm -rf "$HOME/Library/Caches/org.swift.swiftpm"'
  fi
}
category_swiftpm() {
  run_category "SwiftPM cache" "~/Library/Caches/org.swift.swiftpm" \
    "$HOME/Library/Caches/org.swift.swiftpm" cleanup_swiftpm
}

cleanup_clangd_index() {
  run_cmd "rm -rf ~/.cache/clangd" \
    zsh -c 'rm -rf "$HOME/.cache/clangd"'
}
category_clangd_index() {
  run_category "clangd index" "~/.cache/clangd, re-indexed on next open" \
    "$HOME/.cache/clangd" cleanup_clangd_index
}

cleanup_ccache() {
  have ccache || { log SKIP "category=ccache reason=tool_not_installed"; return 0; }
  run_cmd "ccache --clear" ccache --clear
}
category_ccache() {
  run_category "ccache" "compiler cache, refilled on miss" \
    "$HOME/Library/Caches/ccache" cleanup_ccache
}

cleanup_cargo_registry() {
  run_cmd "rm -rf ~/.cargo/registry/cache" \
    zsh -c 'rm -rf "$HOME/.cargo/registry/cache"'
  run_cmd "rm -rf ~/.cargo/registry/src" \
    zsh -c 'rm -rf "$HOME/.cargo/registry/src"'
}
category_cargo_registry() {
  local total=0 p
  for p in "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  section "Cargo registry"
  printf '  ~/.cargo/registry/{cache,src} — re-downloaded on next build\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=cargo_registry reason=empty"
    return 0
  fi
  if ! confirm "Clean this?"; then
    log DECLINE "category=cargo_registry size_bytes=$total"
    return 0
  fi
  cleanup_cargo_registry || { log ERROR "category=cargo_registry rc=$?"; return 0; }
  local after=0
  for p in "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=cargo_registry freed_bytes=$freed"
}

cleanup_go_caches() {
  have go || { log SKIP "category=go_caches reason=tool_not_installed"; return 0; }
  run_cmd "go clean -modcache" go clean -modcache
  run_cmd "go clean -cache"    go clean -cache
}
category_go_caches() {
  if ! have go; then
    section "Go caches"
    printf '  %sgo not installed, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=go_caches reason=tool_not_installed"
    return 0
  fi
  local mod_path build_path total=0 p
  mod_path="$(go env GOMODCACHE 2>/dev/null || true)"
  build_path="$(go env GOCACHE 2>/dev/null || true)"
  if [[ -z "$mod_path" ]]; then
    section "Go caches"
    printf '  %sgo env GOMODCACHE returned empty, skipping%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=go_caches reason=tool_error key=GOMODCACHE"
    return 0
  fi
  if [[ -z "$build_path" ]]; then
    section "Go caches"
    printf '  %sgo env GOCACHE returned empty, skipping%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=go_caches reason=tool_error key=GOCACHE"
    return 0
  fi
  for p in "$mod_path" "$build_path"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  section "Go caches"
  printf '  GOMODCACHE=%s\n' "$mod_path"
  printf '  GOCACHE=%s\n' "$build_path"
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=go_caches reason=empty"
    return 0
  fi
  if ! confirm "Clean this?"; then
    log DECLINE "category=go_caches size_bytes=$total"
    return 0
  fi
  cleanup_go_caches || { log ERROR "category=go_caches rc=$?"; return 0; }
  local after=0
  for p in "$mod_path" "$build_path"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=go_caches freed_bytes=$freed"
}

cleanup_composer() {
  have composer || { log SKIP "category=composer reason=tool_not_installed"; return 0; }
  run_cmd "composer clear-cache" composer clear-cache
}
category_composer() {
  run_category "Composer cache" "PHP Composer package cache" \
    "$HOME/Library/Caches/composer" cleanup_composer
}

cleanup_sccache() {
  have sccache || { log SKIP "category=sccache reason=tool_not_installed"; return 0; }
  run_cmd "sccache --stop-server (best-effort)" sccache --stop-server || true
  run_cmd "rm -rf ~/Library/Caches/Mozilla.sccache" \
    zsh -c 'rm -rf "$HOME/Library/Caches/Mozilla.sccache"'
}
category_sccache() {
  run_category "sccache" "Mozilla sccache disk cache (server stopped first)" \
    "$HOME/Library/Caches/Mozilla.sccache" cleanup_sccache
}

cleanup_bazel() {
  if have bazel; then
    run_cmd "bazel shutdown (best-effort)" bazel shutdown || true
  fi
  local rc=0 p partial=0
  for p in "/private/var/tmp/_bazel_$USER" "$HOME/Library/Caches/bazel"; do
    [[ -d "$p" ]] || continue
    local rel
    case "$p" in
      "$HOME"/*) rel="~/${p#$HOME/}" ;;
      *) rel="$p" ;;
    esac
    run_cmd "rm -rf $rel" zsh -c "rm -rf ${(q)p}" || { rc=$?; partial=1; }
  done
  if (( partial )); then
    printf '  %sWARNING:%s Bazel cache partially deleted — daemon or IDE held file locks.\n' "$C_RED" "$C_RESET"
    printf '           Close your IDE, then re-run: %sbazel shutdown && rm -rf /private/var/tmp/_bazel_%s%s\n' \
      "$C_BOLD" "$USER" "$C_RESET"
    log WARN "category=bazel partial_delete=true"
  fi
  return $rc
}
category_bazel() {
  if ! have bazel; then
    section "Bazel cache"
    printf '  %sbazel not installed, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=bazel reason=tool_not_installed"
    return 0
  fi
  local total=0 p
  for p in "/private/var/tmp/_bazel_$USER" "$HOME/Library/Caches/bazel"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  section "Bazel cache"
  printf '  /private/var/tmp/_bazel_%s and ~/Library/Caches/bazel\n' "$USER"
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=bazel reason=empty"
    return 0
  fi
  if ! confirm "Clean this?"; then
    log DECLINE "category=bazel size_bytes=$total"
    return 0
  fi
  cleanup_bazel || { log ERROR "category=bazel rc=$?"; }
  local after=0
  for p in "/private/var/tmp/_bazel_$USER" "$HOME/Library/Caches/bazel"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=bazel freed_bytes=$freed"
}

# ── Container VMs (Tier 2 umbrella) ──
#
# NEVER rm a VM disk image file — corrupts the VM. Always use the tool's CLI.
# --include-volumes flag (off by default) gates Docker/Podman volume pruning.

_vm_cleanup_one() {
  # _vm_cleanup_one <tool-name> <disk-image-path> <prune-cmd...>
  local tool="$1" disk="$2"; shift 2
  local before=0 after=0
  [[ -e "$disk" ]] && before=$(du_safe "$disk")
  printf '  %s%s%s — disk: %s, image size: %s%s%s\n' \
    "$C_BOLD" "$tool" "$C_RESET" "$disk" "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Prune $tool?"; then
    log DECLINE "category=container_vms tool=$tool size_bytes=$before"
    return 0
  fi
  local rc=0
  run_cmd "$tool prune: $*" "$@" || rc=$?
  [[ -e "$disk" ]] && after=$(du_safe "$disk")
  if (( rc != 0 )); then
    printf '  %sERROR%s %s prune returned rc=%d\n' "$C_RED" "$C_RESET" "$tool" "$rc"
    log ERROR "category=container_vms tool=$tool rc=$rc"
    return 0
  fi
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ %s pruned, freed %s%s\n' "$C_GREEN" "$tool" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=container_vms tool=$tool freed_bytes=$freed"
}

category_container_vms() {
  section "Container VM disk images"
  printf '  Docker / OrbStack / Colima / Lima / Podman — uses each tool'\''s prune command.\n'
  if (( INCLUDE_VOLUMES )); then
    printf '  %s--include-volumes ON: Docker/Podman will also prune named volumes.%s\n' \
      "$C_RED" "$C_RESET"
  else
    printf '  %s(volumes preserved; pass --include-volumes to also prune them)%s\n' \
      "$C_DIM" "$C_RESET"
  fi
  local any=0

  if have docker && docker info >/dev/null 2>&1; then
    any=1
    if (( INCLUDE_VOLUMES )); then
      _vm_cleanup_one docker \
        "$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw" \
        docker system prune -a -f --volumes
    else
      _vm_cleanup_one docker \
        "$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw" \
        docker system prune -a -f
    fi
    # Reclaim helper container actually shrinks Docker.raw on host.
    run_cmd "docker reclaim-space helper" \
      docker run --rm --privileged --pid=host docker/desktop-reclaim-space || true
  else
    log SKIP "category=container_vms tool=docker reason=tool_not_installed"
  fi

  if have orb; then
    any=1
    _vm_cleanup_one orbstack "$HOME/.orbstack/data/data.img" \
      docker builder prune -a -f
  else
    log SKIP "category=container_vms tool=orbstack reason=tool_not_installed"
  fi

  if have colima; then
    any=1
    _vm_cleanup_one colima "$HOME/.colima/_lima/colima/diffdisk" \
      colima prune
    # fstrim inside the VM releases blocks; restart needed for full reclaim.
    run_cmd "colima ssh fstrim" colima ssh -- sudo fstrim -a || true
    printf '  %s(restart Colima with `colima stop && colima start` for full reclaim)%s\n' \
      "$C_DIM" "$C_RESET"
  else
    log SKIP "category=container_vms tool=colima reason=tool_not_installed"
  fi

  if have limactl; then
    any=1
    _vm_cleanup_one lima "$HOME/.lima/_cache" limactl prune
  else
    log SKIP "category=container_vms tool=lima reason=tool_not_installed"
  fi

  if have podman; then
    any=1
    local podman_disk=""
    local cand
    for cand in "$HOME/.local/share/containers/podman/machine/applehv"/*-arm64.raw(N) \
                "$HOME/.local/share/containers/podman/machine/applehv"/*.raw(N); do
      [[ -e "$cand" ]] && { podman_disk="$cand"; break; }
    done
    [[ -z "$podman_disk" ]] && podman_disk="$HOME/.local/share/containers/podman"
    if (( INCLUDE_VOLUMES )); then
      _vm_cleanup_one podman "$podman_disk" podman system prune -a -f --volumes
    else
      _vm_cleanup_one podman "$podman_disk" podman system prune -a -f
    fi
  else
    log SKIP "category=container_vms tool=podman reason=tool_not_installed"
  fi

  if (( any == 0 )); then
    printf '  %sno container tools installed, skipping%s\n' "$C_DIM" "$C_RESET"
  fi
}

# ── Browser caches (Tier 2) ──
#
# Per-browser hardcoded top-level + literal-allowlist profile glob + hardcoded
# leaf cache subpaths. Cookies, history, login data, and other site storage
# are explicitly NOT touched. Skip-if-running per browser to avoid disk_cache
# index corruption.

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

_browser_clean_safari() {
  local cdir="$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari"
  if [[ ! -d "$cdir" ]]; then
    log SKIP "category=browser_caches browser=safari reason=tool_not_installed"
    return 0
  fi
  if pgrep -x Safari >/dev/null 2>&1; then
    printf '  %sSafari is running, skipping its caches.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=browser_caches browser=safari reason=app_running"
    return 0
  fi
  local before; before=$(du_safe "$cdir")
  if (( before == 0 )); then
    log SKIP "category=browser_caches browser=safari reason=empty"
    return 0
  fi
  printf '  %sSafari%s — size: %s%s%s\n' "$C_BOLD" "$C_RESET" \
    "$C_YELLOW" "$(human_size "$before")" "$C_RESET"
  if ! confirm "Clean Safari caches?"; then
    log DECLINE "category=browser_caches browser=safari size_bytes=$before"
    return 0
  fi
  run_cmd "rm -rf <safari cache>/*" zsh -c "rm -rf ${(q)cdir}/*"
  local after; after=$(du_safe "$cdir")
  local freed=$(( before - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  printf '  %s→ Safari freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=browser_caches browser=safari freed_bytes=$freed"
}

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

category_browser_caches() {
  section "Browser caches"
  printf '  Safari, Chrome, Arc, Edge, Brave, Firefox — cache subdirs only.\n'
  printf '  Cookies, history, logins, and site storage are NOT touched.\n'
  local before_cleaned=$CATEGORIES_CLEANED
  local before_freed=$TOTAL_FREED
  _browser_clean_safari
  _browser_clean_chromium chrome '/Applications/Google Chrome.app' \
    "$HOME/Library/Application Support/Google/Chrome"
  _browser_clean_chromium arc '/Applications/Arc.app' \
    "$HOME/Library/Application Support/Arc/User Data"
  _browser_clean_chromium edge '/Applications/Microsoft Edge.app' \
    "$HOME/Library/Application Support/Microsoft Edge"
  _browser_clean_chromium brave '/Applications/Brave Browser.app' \
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
  _browser_clean_firefox
  # Count this category as cleaned if any sub-browser produced freed bytes.
  if (( TOTAL_FREED > before_freed )); then
    CATEGORIES_CLEANED=$(( before_cleaned + 1 ))
  fi
}

# ── User-app additions ──

cleanup_apple_music_stream_cache() {
  run_cmd "rm -rf ~/Library/Caches/com.apple.Music/*" \
    zsh -c 'rm -rf "$HOME/Library/Caches/com.apple.Music/"*'
}
category_apple_music_stream_cache() {
  if pgrep -x Music >/dev/null 2>&1; then
    section "Apple Music stream cache"
    printf '  %sMusic.app is running. Close it and re-run.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=apple_music_stream_cache reason=app_running app=Music"
    return 0
  fi
  run_category "Apple Music stream cache" \
    "~/Library/Caches/com.apple.Music — does NOT contain downloaded songs" \
    "$HOME/Library/Caches/com.apple.Music" cleanup_apple_music_stream_cache
}

cleanup_mail_downloads() {
  run_cmd "rm -rf <Mail Downloads>/*" \
    zsh -c 'rm -rf "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/"*'
}
category_mail_downloads() {
  if pgrep -x Mail >/dev/null 2>&1; then
    section "Mail Downloads"
    printf '  %sMail.app is running. Close it and re-run.%s\n' "$C_YELLOW" "$C_RESET"
    log SKIP "category=mail_downloads reason=app_running app=Mail"
    return 0
  fi
  run_category "Mail Downloads" \
    "extracted attachment copies; originals stay in mailbox .emlx files" \
    "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" cleanup_mail_downloads
}

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
category_diagnostic_reports() {
  local total=0 p
  for p in "$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports"; do
    [[ -e "$p" ]] && total=$(( total + $(du_safe "$p") ))
  done
  section "Diagnostic reports"
  printf '  ~/Library/Logs/DiagnosticReports + /Library/Logs/DiagnosticReports (.ips/.diag files)\n'
  printf '  Size: %s%s%s\n' "$C_YELLOW" "$(human_size "$total")" "$C_RESET"
  if (( total == 0 )); then
    printf '  %salready empty, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=diagnostic_reports reason=empty"
    return 0
  fi
  if ! confirm "Clean this?"; then
    log DECLINE "category=diagnostic_reports size_bytes=$total"
    return 0
  fi
  cleanup_diagnostic_reports || { log ERROR "category=diagnostic_reports rc=$?"; return 0; }
  local after=0
  for p in "$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports"; do
    [[ -e "$p" ]] && after=$(( after + $(du_safe "$p") ))
  done
  local freed=$(( total - after ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ cleaned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=diagnostic_reports freed_bytes=$freed"
}

# ── Apple Intelligence + on-device ML (G1, spec 2026-05-10-gaps) ──

cleanup_intelligence_platform() {
  run_cmd "pkill -x intelligenceplatformd (best-effort)" \
    zsh -c 'pkill -x intelligenceplatformd 2>/dev/null; true'
  run_cmd "rm -rf ~/Library/IntelligencePlatform/*" \
    zsh -c 'rm -rf "$HOME/Library/IntelligencePlatform/"*'
}

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

category_tm_local_snapshots() {
  section "Time Machine local snapshots"
  if ! have tmutil; then
    printf '  %stmutil not found, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=tm_local_snapshots reason=tool_not_installed"
    return 0
  fi
  local count
  count="$(tmutil listlocalsnapshots / 2>/dev/null \
           | grep -c '^com.apple.TimeMachine' || true)"
  if (( count == 0 )); then
    printf '  %sno local snapshots, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=tm_local_snapshots reason=empty count=0"
    return 0
  fi
  printf '  Found %s%d%s Time Machine local snapshot(s).\n' \
    "$C_YELLOW" "$count" "$C_RESET"
  printf '  %sThis removes the local 24h restore window.%s\n' "$C_RED" "$C_RESET"
  printf '  Network/external Time Machine backups are NOT affected.\n'
  if ! confirm "Thin all local snapshots?"; then
    log DECLINE "category=tm_local_snapshots count=$count"
    return 0
  fi
  run_cmd "tmutil stopbackup (best-effort)" tmutil stopbackup || true
  local before after freed
  before="$(df -k / 2>/dev/null | awk 'NR==2{print $4}')"
  before=${before:-0}
  run_cmd "tmutil thinlocalsnapshots / 999999999999 4" \
    tmutil thinlocalsnapshots / 999999999999 4 \
    || { log ERROR "category=tm_local_snapshots rc=$?"; return 0; }
  after="$(df -k / 2>/dev/null | awk 'NR==2{print $4}')"
  after=${after:-0}
  freed=$(( (after - before) * 1024 ))
  (( freed < 0 )) && freed=0
  TOTAL_FREED=$(( TOTAL_FREED + freed ))
  CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
  printf '  %s→ thinned, freed %s%s\n' "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
  log CLEAN "category=tm_local_snapshots freed_bytes=$freed"
}

category_macos_installers() {
  section "Stale macOS installers"
  printf '  /Applications/Install macOS *.app — 12-15 GB stub installers\n'
  local -a installers=(/Applications/Install\ macOS\ *.app(N))
  if (( ${#installers} == 0 )); then
    printf '  %snone present, skipping%s\n' "$C_DIM" "$C_RESET"
    log SKIP "category=macos_installers reason=empty"
    return 0
  fi
  local app name size before=0 after_total=0 cat_freed=0 any=0
  for app in "${installers[@]}"; do
    # Paranoid re-check that the path matches the literal pattern
    [[ "$app" == /Applications/Install\ macOS\ *.app ]] || continue
    name="${app:t}"
    size="$(du_safe "$app")"
    before=$(( before + size ))
    printf '  %s%s%s — %s%s%s\n' "$C_BOLD" "$name" "$C_RESET" \
      "$C_YELLOW" "$(human_size "$size")" "$C_RESET"
    if confirm "Delete \"$name\"?"; then
      run_cmd "rm -rf /Applications/$name" zsh -c "rm -rf ${(q)app}"
      local after_one=0
      [[ -e "$app" ]] && after_one=$(du_safe "$app")
      local one_freed=$(( size - after_one ))
      (( one_freed < 0 )) && one_freed=0
      cat_freed=$(( cat_freed + one_freed ))
      any=1
      log CLEAN "category=macos_installers app=\"$name\" freed_bytes=$one_freed"
    else
      log DECLINE "category=macos_installers app=\"$name\" size_bytes=$size"
    fi
  done
  if (( any )); then
    TOTAL_FREED=$(( TOTAL_FREED + cat_freed ))
    CATEGORIES_CLEANED=$(( CATEGORIES_CLEANED + 1 ))
    printf '  %s→ removed installers, freed %s%s\n' "$C_GREEN" "$(human_size "$cat_freed")" "$C_RESET"
  fi
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
  log START "dry_run=$DRY_RUN yes=$ASSUME_YES prepare_pnpm=$PREPARE_PNPM"

  printf '%smac-cleaner%s — interactive macOS developer-cache cleaner   run %s\n' \
    "$C_BOLD" "$C_RESET" "$RUN_ID"
  printf '  %sHow it works:%s walks each cache, shows its size, asks y/N — %sy%s cleans, anything else skips.\n' \
    "$C_BOLD" "$C_RESET" "$C_GREEN" "$C_RESET"
  printf '  %sFlags:%s --dry-run | --yes | --prepare-for-pnpm | --help\n' \
    "$C_BOLD" "$C_RESET"
  printf '  %sLog:%s   %s\n' "$C_BOLD" "$C_RESET" "$LOG_FILE"
  printf '  %sAbort:%s Ctrl-C at any prompt. Xcode Archives has a second DELETE confirm.\n' \
    "$C_BOLD" "$C_RESET"
  if (( DRY_RUN )); then
    printf '  %s(dry-run: nothing will be deleted)%s\n' "$C_YELLOW" "$C_RESET"
  fi
  if (( ASSUME_YES )); then
    printf '  %s(--yes: prompts auto-accepted; Xcode Archives still double-prompts)%s\n' "$C_YELLOW" "$C_RESET"
  fi
  if (( PREPARE_PNPM )); then
    printf '  %s(--prepare-for-pnpm: only npm/yarn caches across all Node versions will be touched)%s\n' "$C_YELLOW" "$C_RESET"
  fi

  # Order: smaller/safer first → bigger dev-tool wins → version audit last.
  category_npm_yarn_all_nvm
  category_npm_yarn_all_brew
  category_npm_cache
  category_yarn_cache
  if (( ! PREPARE_PNPM )); then
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

    # Generic app caches, temp dirs, and dev dotfolder caches.
    # These run after all tool-specific categories to avoid double-deletion.
    category_app_caches
    category_temp
    category_dev_dotcaches

    # ── System Data categories (spec 2026-05-10) ──
    # Familiar wins above; novel-judgment categories below.
    category_coresimulator_caches
    category_xctest_xcpg_devices
    category_xcode_dt_cache
    category_xcode_device_logs

    category_swiftpm
    category_clangd_index
    category_ccache
    category_sccache
    category_cargo_registry
    category_go_caches
    category_composer
    category_bazel

    category_container_vms
    category_browser_caches

    category_apple_music_stream_cache
    category_mail_downloads
    category_diagnostic_reports
    category_intelligence_platform
    category_wallpaper_aerials

    category_tm_local_snapshots
    category_macos_installers

    category_trash

    check_tool_versions
    check_outdated_globals
  fi

  printf '\n%s── Summary ────────────────────%s\n' "$C_BOLD" "$C_RESET"
  printf '  Freed %s%s%s across %d categories\n' \
    "$C_GREEN" "$(human_size "$TOTAL_FREED")" "$C_RESET" "$CATEGORIES_CLEANED"
  printf '  Log:  %s\n' "$LOG_FILE"
  log END "freed_total=$TOTAL_FREED categories_cleaned=$CATEGORIES_CLEANED"
}

main
