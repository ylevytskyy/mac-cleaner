# LLM Caches & Additional App Caches — Design

Status: draft 2026-05-13
Supersedes: nothing — extends `2026-04-22-mac-cleaner-design.md`, `2026-05-07-app-cache-cleanup-design.md`, and `2026-05-10-system-data-categories-design.md`.

## Goal

Add interactive categories for two new bucket classes that the existing script does not reach:

1. **AI / LLM model caches.** A weekend of experimenting with Pinokio, Ollama, LM Studio, or Hugging Face can deposit 20–200 GB of model blobs. None of the existing dev-cache categories touch them and `app_caches` skips them (they live outside `~/Library/Caches`).
2. **Electron desktop-app Chromium caches.** The recent Slack addition (commit `b52ada` — Slack as 7th browser-class app) demonstrated the pattern works for non-browser Chromium apps. VS Code / Cursor / Windsurf / Discord / Teams / Notion all use the same Chromium cache layout under `~/Library/Application Support/<App>/` and routinely accumulate 1–10 GB each.

Plus a small set of single-leaf and multi-leaf additions in adjacent ecosystems (JetBrains IDE caches, Python/Node toolchain extras, Apple Maps tiles, per-user `SoftwareUpdate` cache).

Justification source: review of https://dou.ua/forums/topic/59423/ (Nektony CTO on macOS app uninstallation), cross-referenced against gaps in the existing script. The article's only concrete datapoint — a commenter losing 80+ GB to Pinokio LLM models that no uninstaller caught — directly motivates category #A1 below. The rest of the article is methodological and reinforces existing safety rules rather than introducing new categories.

## Scope

All additions remain inside the **three documented safety-rule exceptions**. No new exception shape is introduced.

**Tier 1 — `run_category`-shaped (4 categories).**
| # | fn | Path | Notes |
|---|---|---|---|
| T1 | `category_jetbrains_caches` | `~/Library/Caches/JetBrains` | Entire dir is documented cache; re-built on next IDE launch. |
| T2 | `category_macos_software_update` | `~/Library/Caches/com.apple.SoftwareUpdate` | Per-user only. `app_caches` denylists `com.apple.*`, so this needs an explicit category — same precedent as `category_apple_music_stream_cache`. |
| T3 | `category_apple_maps_tiles` | `~/Library/Containers/com.apple.Maps/Data/Library/Caches/com.apple.Maps/MapTiles` | Single hardcoded leaf inside a known Container. The existing safety rule prohibits *enumerating* Containers, not deleting a known leaf inside one. Maps refetches tiles on next view. |
| T4 | `category_node_extras` | `~/Library/Caches/node-gyp` + `~/.npm/_logs` | Multi-path sum; same shape as `category_expo_metro`. |

**Tier 2 — multi-path categories (2).**

### A1. `category_llm_caches` — AI / LLM model caches

Hardcoded leaf list, summed for the size header, single prompt for the whole category.

| Path | Tool | Typical size |
|---|---|---|
| `~/.ollama/models` | Ollama | 5–200 GB |
| `~/.cache/huggingface/hub` | HF transformers/diffusers (current path) | 1–100 GB |
| `~/.cache/huggingface/datasets` | HF datasets | 1–50 GB |
| `~/.cache/huggingface/transformers` | HF legacy path | varies |
| `~/.cache/torch/hub` | `torch.hub.load()` | 1–20 GB |
| `~/.cache/torch/kernels` | PyTorch JIT cache | <1 GB |
| `~/.cache/whisper` | OpenAI Whisper | 1–10 GB |
| `~/.lmstudio/models` | LM Studio | 5–100 GB |
| `~/Library/Application Support/nomic.ai/GPT4All` | GPT4All | 5–50 GB |
| `~/pinokio/cache` | Pinokio download cache only | 1–80 GB |

**Pre-flight hint, no auto-stop.** If `~/.ollama/models` is non-empty, the category prints a one-line `Ollama daemon is running — quit Ollama.app or run \`launchctl stop com.ollama.Ollama\` for a clean delete` *informational* line before the prompt and continues. We do **not** auto-stop the daemon — same precedent as the browser_caches "app_running → skip" posture: GUI apps are surfaced to the user; only background-daemons-with-no-UI (Gradle, sccache, Bazel server) get auto-stopped. Ollama has a menu-bar UI and counts as user-facing.

**Pinokio scope:** `~/pinokio/cache` ONLY. Never `~/pinokio/api` (installed apps) or `~/pinokio/drive` (virtual-env disk image). Same shape as the Adobe-shared-folder trap the article calls out.

### A2. `category_python_extras` — Python toolchain caches

Hardcoded leaf list, summed for the header, single prompt.

| Path | Tool |
|---|---|
| `~/.cache/pre-commit` | pre-commit framework hook venvs |
| `~/Library/Caches/pypoetry` | Poetry (macOS default) |
| `~/.cache/pypoetry` | Poetry (XDG override) |
| `~/Library/Caches/pip` | pip (macOS XDG path; sibling of `~/.cache/pip` already in `category_pip_cache`) |

Decision: add as a sibling category rather than renaming `category_pip_cache`. The existing one stays narrow (`pip cache purge`); the new one sweeps tool-specific paths Poetry and pre-commit own.

### Electron desktop-app extension to `category_browser_caches`

Not a new category — adds new entries to the existing dispatcher, exactly mirroring the Slack addition (`_browser_clean_slack` at mac-cleaner.sh:1492).

Each entry uses the same shape: hardcoded top path × hardcoded leaf list × `pgrep -f` running-app skip.

New apps:
| Slug | Display | Top path | pgrep pattern |
|---|---|---|---|
| `vscode` | VS Code | `~/Library/Application Support/Code` | `/Applications/Visual Studio Code.app` |
| `vscode_insiders` | VS Code Insiders | `~/Library/Application Support/Code - Insiders` | `/Applications/Visual Studio Code - Insiders.app` |
| `cursor` | Cursor | `~/Library/Application Support/Cursor` | `/Applications/Cursor.app` |
| `windsurf` | Windsurf | `~/Library/Application Support/Windsurf` | `/Applications/Windsurf.app` |
| `discord` | Discord | `~/Library/Application Support/discord` | `/Applications/Discord.app` |
| `teams` | Microsoft Teams | `~/Library/Application Support/Microsoft/Teams` | `/Applications/Microsoft Teams.app` |
| `notion` | Notion | `~/Library/Application Support/Notion` | `/Applications/Notion.app` |

**Universal leaf list** (same as the Slack helper's 6, plus `CachedData` for VS Code-family extension caches):
```
Cache, Code Cache, GPUCache, Service Worker, DawnGraphiteCache, DawnWebGPUCache, CachedData
```
Leaves are filtered by existence — apps that don't ship a given leaf are silently no-ops for that leaf. No dynamic enumeration; no `**` recursion.

**Hard exclusions** (per app, never touched): `Local Storage`, `IndexedDB`, `Session Storage`, `Cookies`, `Preferences`, `User`, `History`, `databases`, `Local State`, any `*.db`/`*.sqlite`/`*.log` outside the listed leaves. Same posture as the existing browser-caches "site storage stays" rule.

**Implementation note.** Rather than 7 near-identical copies of `_browser_clean_slack`, introduce one helper `_browser_clean_electron <slug> <display> <pgrep_pattern> <base_path>` that takes the leaf list from a function-local hardcoded array. Slack is then either left as-is (it has the same shape) or migrated to call the helper — leaving it as-is is fine; this is a project that values surgical changes over DRY.

## Out of scope

Documented so future contributors don't re-litigate:

- **Xcode `iOS DeviceSupport` / `watchOS DeviceSupport` / `tvOS DeviceSupport`.** User explicitly opted out for the third time (see prior spec §Out of scope, plus the 2026-05-13 conversation).
- **`/Library/Updates` (system-wide SoftwareUpdate cache).** Sudo + SIP-adjacent; rejected by `2026-05-10-system-data-categories-design.md` §Out of scope and not reintroduced here. Per-user `~/Library/Caches/com.apple.SoftwareUpdate` is fine because it stays inside `$HOME` and needs no elevation.
- **iOS device backups** (`~/Library/Application Support/MobileSync/Backup`). Irreplaceable user data; already rejected upstream.
- **Figma Desktop caches.** `~/Library/Application Support/Figma/Desktop/` mixes the Chromium cache leaves with offline draft documents at peer paths. Cannot guarantee safety without per-leaf knowledge of Figma's offline schema. Rejected — user can clear in-app.
- **Zed caches.** Zed manages its own cache; the safe leaves are entangled with extension state in ways that aren't stable across versions. Rejected.
- **Spotify** (`~/Library/Application Support/Spotify/PersistentCache`). `~/Library/Caches/com.spotify.client` is already swept by `category_app_caches`. The PersistentCache under Application Support also holds offline-saved tracks for premium users; cannot delete safely without per-user-account state knowledge. Rejected for now; rely on the existing `app_caches` coverage.
- **VS Code/Cursor user settings, `User/` directory, MCP server caches, AI provider response caches.** Settings + workspace state, not pure runtime cache. Out of scope.
- **`~/Library/Logs/Code`, `~/Library/Logs/Cursor`.** Could be added to `category_android_studio_logs` later (the misleadingly named "IDE logs" category); deferred — current logs sweep is intentionally vendor-allowlisted.
- **Hugging Face `~/.cache/huggingface/token` and `~/.cache/huggingface/accelerate`.** Auth + config; excluded from the LLM caches sweep.
- **`~/pinokio/api`, `~/pinokio/drive`, `~/pinokio/bin`.** Installed apps, venvs, and binaries respectively. Article failure mode #2 ("shared vendor folder") applies — touching these breaks installs. Only `~/pinokio/cache` is in scope.
- **Generalised orphan-detection** in `~/Library/Application Support`, `~/Library/Containers`, `~/Library/Group Containers`, `~/Library/LaunchAgents`, `~/Library/LaunchDaemons`. Article failure modes #1, #3, #4, #7. Rejected at the methodology level; this is the kind of feature the article argues *cannot* be automated safely.

## Reconciliation with existing categories

Cross-referenced against `dev_dotcaches`, `app_caches`, `pip_cache`, `browser_caches`, `apple_music_stream_cache`, and `mail_downloads`:

- **`~/.cache/huggingface/*`, `~/.cache/torch/*`, `~/.cache/whisper`** — not in `dev_dotcaches`. No overlap.
- **`~/.cache/pre-commit`** — not in `dev_dotcaches`. No overlap.
- **`~/Library/Caches/JetBrains`** — `category_app_caches` denylist did not exclude it, which means it's currently being deleted by the bulk `~/Library/Caches/*` sweep. Promoting it to an explicit category means **adding `JetBrains` to the `app_caches` denylist** so it isn't double-handled. Same precedent as `com.apple.Music`, `ccache`, `composer`, `org.swift.swiftpm` from the 2026-05-10 spec.
- **`~/Library/Caches/com.apple.SoftwareUpdate`** — already excluded by the `com.apple.*` denylist in `app_caches`; explicit category carves it out for separate prompting. No denylist change needed.
- **`~/Library/Caches/node-gyp`** — currently being swept by `app_caches`. Add `node-gyp` to the `app_caches` denylist when promoting it to `category_node_extras`.
- **`~/Library/Caches/pypoetry`** — same; add `pypoetry` to the `app_caches` denylist.
- **`~/Library/Caches/pip`** — **already** in the `app_caches` denylist (line 617). No denylist change needed. The existing `category_pip_cache` calls `pip cache purge` which respects `PIP_CACHE_DIR`; `category_python_extras` adds a literal `rm -rf` on the macOS XDG path as a sibling — both safe because the path is already denylisted from the bulk sweep.
- **`~/Library/Application Support/nomic.ai/GPT4All`, `~/.ollama/models`, `~/.lmstudio/models`, `~/pinokio/cache`** — outside both `~/Library/Caches` and `dev_dotcaches`'s hardcoded list. Net new.
- **`~/Library/Containers/com.apple.Maps/.../MapTiles`** — inside Containers, never enumerated by any existing category. Net new.
- **`~/.npm/_logs`** — currently untouched. `~/.npm/_cacache` is handled by `cleanup_npm_cache`; the logs sibling is not. Net new.

## Run order in `main()` (incremental, only the new positions)

The 2026-05-10 spec defined seven blocks (1 = legacy dev-cache, 2 = Xcode family, 3 = language toolchains, 4 = container/VM, 5 = browsers, 6 = user apps, 7 = system state). Slot the additions:

- **Block 1 (dev-cache):** append `category_python_extras`, `category_node_extras` after the existing `category_pip_cache`. Append `category_jetbrains_caches` after `category_dev_dotcaches`. These feel like dev-cache; they go up front.
- **Block 5 (browsers):** no run-order change — additions ride inside the existing `category_browser_caches` function call.
- **Block 6 (user-app):** append `category_apple_maps_tiles` after `category_mail_downloads`.
- **New block 8 (LLM):** `category_llm_caches` at the end (before `category_macos_installers`). Reason: the largest single reclaim category — but also the one most likely to make a user say "wait, I want to keep that". Goes after the user has already been prompted through everything else, when they're in the rhythm of accepting/declining; matches the "less familiar last" reasoning from the prior spec.
- **`category_macos_software_update`** slots into block 7 (system state) right before `category_tm_local_snapshots`.

## Logging additions

Same event vocabulary; new keys:

- `CLEAN category=llm_caches freed_bytes=<sum> entries=<count>` (one CLEAN per category, summed across leaves — same pattern as `dev_dotcaches`)
- `SKIP category=llm_caches reason=empty`
- `CLEAN category=jetbrains_caches freed_bytes=<n>`
- `CLEAN category=macos_software_update freed_bytes=<n>`
- `CLEAN category=apple_maps_tiles freed_bytes=<n>`
- `CLEAN category=python_extras freed_bytes=<sum>` / `CLEAN category=node_extras freed_bytes=<sum>`
- `CLEAN category=browser_caches browser=vscode|cursor|... freed_bytes=<n>` (one per added Electron app — same per-app log key Slack already uses)
- Informational (not a SKIP/CLEAN event): when `~/.ollama/models` non-empty, print to stderr only — no log line, since we proceed regardless.

## Verification

Same testing approach as prior specs. No unit tests.

1. `zsh -n mac-cleaner.sh` — syntax check.
2. `./mac-cleaner.sh --dry-run` and confirm:
   - `category_llm_caches` prints each present leaf with its size and the exact `rm -rf` command, summed to a single header.
   - The Ollama informational line appears only when `~/.ollama/models` exists and is non-empty.
   - `category_jetbrains_caches` prints `~/Library/Caches/JetBrains` size + delete command (or `SKIP empty`).
   - `category_macos_software_update` prints the per-user path; no sudo invocation appears anywhere.
   - `category_apple_maps_tiles` only the MapTiles leaf — not the parent Caches dir, not the Container root.
   - `category_python_extras` / `category_node_extras` print every present leaf.
   - `category_browser_caches` runs through Safari → Chrome → Arc → Edge → Brave → Firefox → Slack → VS Code → VS Code Insiders → Cursor → Windsurf → Discord → Teams → Notion. Each non-installed app emits `SKIP reason=tool_not_installed`; each running app emits `SKIP reason=app_running`.
3. Tail `~/.mac-cleaner.log` and confirm one CLEAN line per added Electron app (or SKIP), plus the new top-level category CLEAN events.
4. Real run on the user's machine — acceptance.

## Files to touch at implementation time

- `mac-cleaner.sh`
  - Add `category_llm_caches` (multi-path, dev_dotcaches-style summing + Ollama daemon hint).
  - Add `category_jetbrains_caches`, `category_macos_software_update`, `category_apple_maps_tiles` (each `run_category`-shaped).
  - Add `category_python_extras`, `category_node_extras` (multi-path).
  - Add `_browser_clean_electron` helper; add 7 calls to it from `category_browser_caches`.
  - Extend `app_caches` denylist with: `JetBrains`, `node-gyp`, `pypoetry`. (`pip` is already in the denylist. `com.apple.SoftwareUpdate` is already excluded by the `com.apple.*` prefix.)
  - Splice the new categories into `main()` per run-order plan above.
- `README.md` — append the new categories to the existing inventory + add a short "AI/LLM model caches" subsection naming Ollama / HF / LM Studio / GPT4All / Pinokio explicitly.
- `~/.mac-cleaner.log` — new event keys above; format unchanged.

No changes to `CLAUDE.md`; no new safety-rule exception is introduced.
