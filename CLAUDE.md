# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project shape

A single-file zsh utility (`mac-cleaner.sh`, ~600 lines) that interactively reclaims disk space from developer caches on macOS. There is **no build system, no package manager, no test harness, and no CI** — this is intentional. The design spec at `docs/superpowers/specs/2026-04-22-mac-cleaner-design.md` is the source of truth for scope and safety invariants; read it before changing behavior.

## Common commands

```bash
./mac-cleaner.sh --dry-run        # canonical smoke test — prints every command, deletes nothing
./mac-cleaner.sh --yes            # auto-accept y/N (Xcode Archives still requires typing DELETE)
./mac-cleaner.sh --prepare-for-pnpm  # only npm/yarn caches (across nvm + brew Node versions); skip everything else
./mac-cleaner.sh --help
zsh -n mac-cleaner.sh             # syntax check (no execution)
tail -f ~/.mac-cleaner.log        # event log; one line per START/SKIP/CLEAN/DECLINE/ERROR/END
```

`--dry-run` is the testing strategy. There are no unit tests by design (documented in the spec under "Testing approach"). When you change a category, run `--dry-run` and confirm the printed commands are correct.

## Architecture

### The `run_category` pattern

Every cache category follows a fixed shape: show size → prompt → run cleanup → measure freed bytes → log. That shape is encoded in `run_category <name> <desc> <size_path> <cleanup_fn>` (mac-cleaner.sh:116). Adding a typical new category means:

1. Write `cleanup_<x>()` that calls `run_cmd "<desc>" <command...>` (so it respects `--dry-run`).
2. Write `category_<x>()` that calls `run_category` with the path used for sizing.
3. Add `category_<x>` to the run order in `main()` (mac-cleaner.sh:560).

### Categories that bypass `run_category`

Five categories need bespoke wrappers and **must not** be folded back into `run_category`:

- **`category_xcode_archives`** — requires a second confirmation where the user types the literal string `DELETE` (case-sensitive). `--yes` does **not** bypass this.
- **`category_npm_yarn_all_nvm`** — iterates `$NVM_DIR/versions/node/*` and invokes each version's bundled `npm`/`yarn`. This catches per-version `.npmrc` cache overrides that the single-path categories miss.
- **`category_npm_yarn_all_brew`** — Homebrew sibling of the nvm sweep. Iterates `brew list --formula` matches for `node` / `node@*` and invokes each formula's bundled `npm`/`yarn` to catch per-formula `.npmrc` cache overrides.
- **`category_expo_metro`** — sums size across multiple paths (`~/.expo/cache`, `/tmp/metro-*`, `/tmp/haste-map-*`, `/tmp/react-*`).
- **`cleanup_gradle`** — stops the Gradle/Kotlin daemons (`gradle --stop` or `pkill -f`) before `rm -rf ~/.gradle/caches`, because a half-deleted cache (locks held by IDE/daemon) leaves Android builds permanently broken. If the delete partially fails, surface it loudly with the recovery command — do not swallow.

### Strict mode and `run_cmd`

The script uses `set -euo pipefail`, but `run_cmd` (mac-cleaner.sh:95) temporarily relaxes `-e` so a failing cleanup command logs `ERROR category=<x> rc=<n>` and continues to the next category. **One bad category must not abort the run.** Keep this contract intact when editing.

### Per-run log id

Every run generates a 4-byte hex `RUN_ID`; every log line includes `run=<id>`. This is how concurrent or sequential runs are disambiguated in `~/.mac-cleaner.log`. Don't change the log format casually — it's append-only and the structure is part of the spec.

## Hard safety rules (non-negotiable)

These come from the spec's "Safety guarantees" section and must be preserved on any edit:

1. **No dynamic path construction for `rm -rf`.** Every deletion target is either a hardcoded absolute path or the output of a trusted tool command (`brew cleanup`, `npm cache clean`, `xcrun simctl`). Never `rm -rf "$foo/$bar"` where either side is user-influenced.
2. **Tool detection before invocation.** Use `have <cmd>`; if missing, log `SKIP reason=tool_not_installed` and return 0. Never let `command not found` reach the user.
3. **Auto-skip empty caches.** When `du_safe` returns 0, print "already empty, skipping", log `SKIP reason=empty`, and do not prompt.
4. **`--yes` does not bypass the Xcode Archives DELETE prompt.** Treat that double-prompt as load-bearing.

## Repository layout

- `mac-cleaner.sh` — the script.
- `README.md` — user-facing documentation.
- `docs/superpowers/specs/2026-04-22-mac-cleaner-design.md` — design spec; read before non-trivial changes.
- `docs/superpowers/plans/2026-04-22-mac-cleaner.md` — original implementation plan (historical).
- `~/.mac-cleaner.log` — runtime log (not in repo).
