# mac-cleaner

Interactive macOS developer-cache cleaner. One zsh script that walks every common dev cache on your Mac, shows you its size, and asks `y/N` before deleting anything.

No daemons, no config, no dependencies beyond the tools whose caches it cleans.

## What it cleans

| Category | Path / command |
|---|---|
| npm cache | `~/.npm` (also swept across **every nvm-installed Node**, catching per-version `.npmrc` overrides) |
| yarn cache | `~/Library/Caches/Yarn` (handles both classic v1 and modern Yarn) |
| pnpm store | `~/Library/pnpm/store` or `~/.pnpm-store` |
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

After cleanup it also runs a **version audit** — checks `npm` / `yarn` / `pnpm` against the registry and lists outdated global npm packages, prompting before any update.

## Usage

```bash
./mac-cleaner.sh                 # interactive run
./mac-cleaner.sh --dry-run       # preview only — nothing is deleted
./mac-cleaner.sh --yes           # auto-accept y/N prompts (Xcode Archives still double-prompts)
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

## Files

- `mac-cleaner.sh` — the script.
- `~/.mac-cleaner.log` — append-only log of every run.
- `docs/superpowers/` — design spec and implementation plan.
