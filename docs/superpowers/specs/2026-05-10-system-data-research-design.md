# System Data Research Plan — Design

Status: draft 2026-05-10
Supersedes: nothing — research input for `2026-05-10-system-data-categories-design.md` (which references but does not contain its source research) and a forthcoming gap-categories spec.

## Goal

Produce a research artifact that explains why macOS System Data has grown to 50–150 GB on developer machines as of May 2026, with evidence strong enough to (a) backfill the missing `docs/superpowers/discovery/2026-05-10-system-data-research.md` discovery doc that the existing categories spec depends on, and (b) identify category gaps not yet covered by the 19 implemented categories.

## Deliverables

Written at the synthesis step in the main thread (not by individual agents):

1. `docs/superpowers/discovery/2026-05-10-system-data-research.md` — the discovery doc. One section per hypothesis tested, with: hypothesis, evidence found (local size + sources cited), verdict (in-scope-existing / in-scope-new / out-of-scope-rejected), and tie-back to the existing 19 categories or to a proposed new one.
2. `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md` — design spec for any **new** categories the research surfaces, written in the same shape as the existing system-data spec (Tier 1 / Tier 2, hard safety rules, run-order placement). Created **only if** the research surfaces gaps worth implementing — otherwise the discovery doc notes "no novel sources found beyond current 19" and this file is not created.
3. (Optional) A "personal findings" subsection appended to the discovery doc, separated from general findings, only if Round 2 surfaces machine-specific bloat unique to this Mac that's not generalizable.

## Non-deliverables

- No code changes in this cycle. The discovery doc and any gap spec are inputs to a future implementation cycle.
- No `mac-cleaner.sh` invocations. No deletions, modifications, or sudo. Read-only research only.

## Approach

Hypothesis-partitioned, adaptive, four-source. Round 1 dispatches one Sonnet subagent per hypothesis in parallel; Round 2 dispatches 0–4 deep-dives based on a review gate; main-thread synthesis produces the deliverables.

## Round 1 hypotheses

Ten hypotheses. Six **backfill** (mapping to the 19 implemented categories so each gets evidence in the discovery doc) and four **extend** (looking for novel sources not yet covered).

### Backfill hypotheses

- **H1. Xcode + Apple developer tooling.** CoreSimulator caches, XCTestDevices/XCPGDevices, com.apple.dt.Xcode caches, iOS Device Logs. Also document why DeviceSupport directories and unused simulator runtimes were rejected (user explicitly opted out — reaffirm with current evidence).
- **H2. Native compilation toolchain caches.** ccache, sccache, swiftpm, clangd index, bazel, cargo registry, go (mod + build), composer.
- **H3. Container / VM disk images.** Docker.raw, OrbStack data.img, Colima diffdisk, Lima cache, Podman raw images. Why they grow without bound, why prune doesn't reclaim host space without `--volumes` / `fstrim`.
- **H4. Browser cache + service-worker storage.** Why Safari/Chrome/Arc/Edge/Brave/Firefox caches grow into multi-GB on developer machines (DevTools, ServiceWorker, GPU shader caches), why Apple's "manage storage" doesn't surface them.
- **H5. macOS housekeeping artifacts.** Time Machine local APFS snapshots (24h restore window), stale `Install macOS *.app` stubs, DiagnosticReports.
- **H6. User-app bundled caches.** Apple Music streaming cache, Mail Downloads attachment extracts. Why they aren't reachable from the app's settings UI.

### Extend hypotheses

- **H7. Apple Intelligence + on-device ML growth (NEW IN 2026).** Tahoe 16.x ships expanded on-device models, Siri context cache, Genmoji / Image Playground generation cache, Writing Tools draft history. Where do these live? Are they unbounded? User-clearable? Strongest candidate for "why it's growing right now."
- **H8. Third-party app sandbox container caches.** `~/Library/Containers/<bundle>/Data/Library/Caches/*` and `~/Library/Group Containers/*`. These fall **outside** `category_app_caches`'s `~/Library/Caches` denylist iteration, so any third-party app with a runaway sandbox cache is invisible to the current tool. Identify top offenders empirically.
- **H9. System-volume opaque growth.** APFS purgeable space, FileVault recovery artifacts, snapshot accounting that shows up as System Data but isn't user-deletable (or requires a different mechanism than `tmutil thinlocalsnapshots`). Goal: explain the part the tool **cannot** reclaim, so README can guide users honestly.
- **H10. Background daemon write-amplification.** Long-lived state under `/private/var/db`, `/Library/Application Support/`, `/Library/Logs/`, `/private/var/folders/*` written by daemons (Spotlight `mds_stores`, `bird` / CloudKit, `assistantd`, `analyticsd`, `corespeechd`, etc.). Which of these grow unboundedly in May 2026, and which are user-clearable without sudo / SIP risk.

## Per-agent prompt contract

Every Round 1 agent uses Sonnet (`model: "sonnet"`) and is instructed to ultrathink. Every prompt is self-contained: goal, context, scope of allowed probes, evidence sources, structured report shape, hard rules, word cap.

### Prompt skeleton

```
Ultrathink and investigate hypothesis <ID>: <one-sentence claim>.

Context: macOS System Data on developer machines is routinely 50–150 GB
in May 2026. The mac-cleaner.sh tool covers 19 categories; the goal of
your investigation is to produce evidence about <hypothesis>.

You have read-only access to this Mac (paths under $HOME and
read-permitted system paths). DO NOT modify, delete, or write anything
outside scratch files in /tmp. DO NOT run sudo. DO NOT invoke the
mac-cleaner script. Probing tools allowed: du, find, ls, stat, file,
strings, codesign, defaults read, plutil, pgrep, launchctl list, df,
xcrun simctl list, brew list, tmutil listlocalsnapshots, go env,
sqlite3 (read-only), grep.

Evidence sources required:
  1. Local probe — measure on this Mac. Suggested starting paths: <list>
  2. Apple official docs — developer.apple.com, support.apple.com,
     WWDC session notes, Apple tech notes. Cite URL + section.
  3. Community sources — Apple Developer Forums, r/MacOS, Stack
     Overflow, blog posts, dated 2025–2026 preferred. Cite URL.
  4. Source/tool inspection — when relevant: man pages, plist payloads,
     launchd plists, formula sources. Cite path or URL.

Return a structured report with these EXACT sections:
  ## Hypothesis
  ## Local evidence
    - For each path investigated: absolute path, current size (du -sh),
      regen risk on deletion, owning daemon/app (if known), running-app
      gate needed (yes/no + which app).
  ## External evidence
    - Bullet list of cited sources with one-line takeaway each.
  ## Verdict
    One of:
      - in-scope-existing: maps to category_<X> in current spec
      - in-scope-new: should become a new category
      - out-of-scope-rejected: with concrete reason fitting one of the
        existing rejection patterns (user-data risk, dynamic-path
        violation, sudo-required, regen impossible, etc.)
  ## Proposed category shape (only if in-scope-new)
    - Tier 1 (run_category) or Tier 2 (bespoke)
    - Hardcoded path(s)
    - Reclaim command
    - Tool detection (have <cmd>)
    - Running-process gate (if any)
    - Safety-rule fit: which of the three documented exception
      shapes it fits (or "no exception needed").
  ## May-2026 specifics
    - Anything that's NEW or has GROWN since 2025: new daemon, new
      Tahoe 16.x behavior, recent Xcode/SDK release, etc. This is the
      part that explains "why now".

Hard rules:
  - Cite every claim. No verdict without evidence.
  - If you cannot probe a path (perms denied), say so explicitly.
  - Do NOT propose categories that violate the no-dynamic-path rule.
    Read CLAUDE.md (project root) §"Hard safety rules" before
    proposing — there are exactly three documented exception shapes
    and a new category must fit one of them or be rejected.
  - Read the existing system-data spec
    (docs/superpowers/specs/2026-05-10-system-data-categories-design.md)
    so you know what's already covered and don't duplicate work.

Report cap: under 600 words.
```

### Round 2 prompt variation

Same skeleton, with two changes:
- The hypothesis is a **specific finding** from Round 1 (e.g., `"~/Library/Caches/<X> on this Mac is 47 GB; explain growth mechanism + safe reclaim path"`).
- Word cap raised to 1000 since fewer agents.

## Round 1 → Round 2 review gate

Adaptive checkpoint between rounds. After Round 1 returns, the main thread (user + assistant) reviews findings together before any Round 2 dispatch.

### Review checklist (assistant runs before showing summary to user)

1. **Coverage check.** Every hypothesis returned a verdict. Any agent that returned "couldn't probe" or "ambiguous" is a blocker — re-dispatch that single agent with a tightened prompt before proceeding.
2. **Evidence quality check.** Every "in-scope-new" verdict cites at least one local-probe number AND one external source. Missing either → mark for Round 2 deep-dive.
3. **Cross-cut check.** Any path two agents independently flagged is a strong signal of a real gap; auto-promote to Round 2.
4. **Surprise filter.** Sort all "in-scope-new" findings by claimed local size on this Mac, descending. Top 3 by size are Round 2 candidates regardless of confidence.
5. **"Why now" filter.** Any finding tagged in May-2026-specifics as new-in-Tahoe-16 is promoted to Round 2 even if size is small.

### Gate output to user (in main-thread chat, not a file)

- One-line summary per Round 1 agent: hypothesis ID, verdict, headline number from local probe, top external citation.
- Ranked list of Round 2 candidates with assistant's recommended priority, drawn from the four filters.
- Short list of "remaining unknowns" — questions Round 1 raised but didn't answer.
- Explicit ask: which Round 2 deep-dives to dispatch (user picks 0–4).

### Round 2 dispatch shape

- 0–4 agents max (capped to keep cost bounded).
- Each gets a sharper, narrower prompt as described above.
- Same 4-source evidence rule, 1000-word cap.
- Run in parallel (single message, multiple Agent calls).

### No Round 3

If Round 2 surfaces yet more unknowns, those are noted in the discovery doc as "open questions for future research" rather than chasing infinitely. The user's time is the binding constraint, not subagent budget.

### Termination signal

Either: (a) Round 2 returns clean verdicts on all candidates, or (b) the user decides Round 1 is sufficient and skips Round 2 entirely.

## Synthesis

Performed in the main thread, not delegated. Synthesis is judgment work; delegating loses context and dilutes calls between findings.

### Synthesis steps (sequential)

1. **Read every report once.** Build a flat list: `{hypothesis_id, path, size_on_this_mac, verdict, owning_app/daemon, regen_risk, may_2026_specific?, citations[]}`.
2. **De-duplicate.** Findings naming the same path collapse to one row; citations merge.
3. **Bucket by verdict:**
   - **Backfill bucket** (`in-scope-existing`) — justifies the 19 implemented categories.
   - **Gap bucket** (`in-scope-new`) — becomes the gap design spec.
   - **Out-of-scope bucket** (`out-of-scope-rejected`) — populates the discovery doc's rejection section so future contributors don't re-litigate (mirrors the existing spec's "Out of scope" pattern).
4. **Write `docs/superpowers/discovery/2026-05-10-system-data-research.md`** with this structure:
   - Header: status, date, scope, "supersedes nothing" framing.
   - Methodology: brief — 10 hypothesis-agents, adaptive Round 2, four evidence sources, this spec referenced as the plan-of-record.
   - Section per hypothesis (H1–H10, plus any Round 2 entries): claim, evidence, verdict, tie-back to existing category number or new-category placeholder ID.
   - "May 2026: why now" subsection: every finding tagged 2026-specific, ranked by impact. The existing categories spec's one-line "Sequoia 15.x and Tahoe 16.x in May 2026..." claim is silently leaning on this — write it down.
   - "Out of scope" subsection: same shape as the existing system-data spec — bullet per rejected source with concrete reason.
   - "Personal findings" (only if Round 2 surfaced this-Mac-specific bloat): separated, clearly labeled.
5. **Write `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md`** ONLY if the Gap bucket is non-empty. Same shape as the existing system-data spec (Tier 1 / Tier 2 tables, safety-rule fit, run-order placement, logging additions). If Gap bucket is empty, the discovery doc explicitly notes "no novel sources found beyond current 19" and this file is not created.
6. **Commit** both files in one commit: `docs: system data research + gap categories spec` (or `docs: system data research (no novel gaps)` if no gap spec).

### Synthesis stop conditions

- A finding can't be classified into any bucket → ask the user, don't guess.
- Citations conflict (Apple docs vs. community claim) → note both in the discovery doc, mark "open question," don't pretend resolution.
- A proposed gap category doesn't fit any of the three documented safety-rule exception shapes → goes into out-of-scope with that specific reason, NOT into the gap spec.

## Verification

Light but not absent. No code is run during this research; the only writes are the two markdown files and one git commit.

1. **Discovery-doc completeness pass.** Every existing category from the implemented 19 has at least one paragraph of justification. Cross-reference by grepping for `category_<name>` mentions; no category should be unmentioned.
2. **Citation integrity pass.** Every external URL is resolvable (sample-check 5 random citations). Local-probe numbers reference paths that exist on this Mac (sample-check 5 with `du -sh`).
3. **Gap-spec self-review.** If written, run the same self-review the brainstorming skill mandates: placeholders, contradictions, ambiguity, scope.
4. **No-dynamic-path audit.** Every proposed new category checked against CLAUDE.md's three exception shapes. Any violator is moved to out-of-scope before commit.
5. **User review gate.** Both files presented to the user for review before any implementation cycle is discussed.

## Files to touch at execution time

- `docs/superpowers/discovery/2026-05-10-system-data-research.md` (new) — discovery doc.
- `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md` (new, conditional) — gap categories spec.
- One git commit covering both files.

No changes to `mac-cleaner.sh`, `README.md`, or `CLAUDE.md` in this cycle. Those land in a future implementation cycle if the gap spec is written and approved.

## Cost considerations

- 10 Round 1 agents × ~600 words output × Sonnet → bounded by per-agent context budget; agents are independent so total wall-clock is single-agent latency.
- Up to 4 Round 2 agents × ~1000 words output → optional and gated.
- Main-thread synthesis: reads ~10–14 reports + writes 2 files. Well under main-thread budget.
- Total worst case: ~14 Sonnet calls. Best case (no Round 2): 10 calls.
