# macOS System Data Research Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the research plan in `docs/superpowers/specs/2026-05-10-system-data-research-design.md` — dispatch 10 hypothesis-driven Sonnet subagents, run the adaptive review gate with the user, synthesize findings into a discovery doc, and conditionally produce a gap-categories spec.

**Architecture:** Hypothesis-partitioned, adaptive, four-source. Round 1 dispatches 10 agents in parallel (one Bash/Agent message with 10 Agent calls). Review gate is a main-thread conversation with the user, gated on a 5-step automated checklist. Round 2 dispatches 0–4 deep-dives based on user decision. Main-thread synthesis (no subagents) reads all reports, buckets by verdict, writes the discovery doc, and conditionally writes a gap spec.

**Tech Stack:** Claude Code Agent tool (Sonnet subagents), markdown deliverables, git for committing.

---

## File Structure

**Created in this plan:**
- `docs/superpowers/discovery/2026-05-10-system-data-research.md` — discovery doc backfilling the 19 implemented categories + new findings.
- `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md` — **conditional**, only if the Gap bucket is non-empty.

**Read by tasks (already exists):**
- `docs/superpowers/specs/2026-05-10-system-data-research-design.md` — the plan-of-record (this implementation follows it).
- `docs/superpowers/specs/2026-05-10-system-data-categories-design.md` — defines the 19 implemented categories; backfill maps to it.
- `CLAUDE.md` (project root) — three documented safety-rule exception shapes; new category proposals must fit one.

**Not modified in this plan:**
- `mac-cleaner.sh`, `README.md`, `CLAUDE.md`. These land in a future implementation cycle if the gap spec is approved.

---

## Task 1: Pre-flight check

**Files:**
- Read: `docs/superpowers/specs/2026-05-10-system-data-research-design.md`
- Read: `docs/superpowers/specs/2026-05-10-system-data-categories-design.md`
- Read: `CLAUDE.md`

- [ ] **Step 1: Verify the research design spec is committed and on main**

Run:
```bash
git log --oneline -3 && git status --short
```
Expected: most recent commit is `docs: research plan for May 2026 macOS System Data growth`; status clean.

- [ ] **Step 2: Confirm discovery directory does not yet exist**

Run:
```bash
ls -la docs/superpowers/discovery/ 2>/dev/null || echo "no discovery dir (expected)"
```
Expected: "no discovery dir (expected)" — Round 1 dispatch creates content for it; the directory is created by the Write tool when the discovery doc is written in Task 6.

- [ ] **Step 3: Capture this Mac's current System Data ballpark for downstream synthesis**

Run:
```bash
df -h / && echo --- && du -sh /System/Volumes/Data/private/var 2>/dev/null; du -sh ~/Library 2>/dev/null
```
Note the totals — they're the rough denominators that finding sizes get expressed against.

---

## Task 2: Dispatch Round 1 — 10 hypothesis agents in parallel

**Files:**
- No file changes. Single tool message with 10 Agent calls.

**Critical:** all 10 Agent calls go in **one tool message** so they run concurrently. Sequential dispatch wastes wall-clock time and burns the prompt cache between calls.

- [ ] **Step 1: Compose the dispatch message**

Each Agent call uses:
- `subagent_type: "general-purpose"` (default — has Bash/Read/WebFetch/WebSearch)
- `model: "sonnet"`
- `description`: short like `"H1 Xcode tooling research"` (3–5 words)
- `prompt`: the full skeleton below with the hypothesis-specific values filled in.

**Prompt skeleton (identical across all 10 except the three filled slots — `<HYPOTHESIS_ID>`, `<HYPOTHESIS_CLAIM>`, `<SUGGESTED_PROBE_PATHS>`):**

```
Ultrathink and investigate hypothesis <HYPOTHESIS_ID>: <HYPOTHESIS_CLAIM>.

Context: macOS System Data on developer machines is routinely 50-150 GB
in May 2026. The mac-cleaner.sh tool covers 19 categories; the goal of
your investigation is to produce evidence about this hypothesis.

You have read-only access to this Mac (paths under $HOME and
read-permitted system paths). DO NOT modify, delete, or write anything
outside scratch files in /tmp. DO NOT run sudo. DO NOT invoke the
mac-cleaner script. Probing tools allowed: du, find, ls, stat, file,
strings, codesign, defaults read, plutil, pgrep, launchctl list, df,
xcrun simctl list, brew list, tmutil listlocalsnapshots, go env,
sqlite3 (read-only), grep.

Suggested starting probe paths:
<SUGGESTED_PROBE_PATHS>

Evidence sources required:
  1. Local probe — measure on this Mac. Start with the paths above and
     follow the evidence wherever it leads (within the read-only scope).
  2. Apple official docs — developer.apple.com, support.apple.com,
     WWDC session notes, Apple tech notes. Cite URL + section.
  3. Community sources — Apple Developer Forums, r/MacOS, Stack
     Overflow, blog posts, dated 2025-2026 preferred. Cite URL.
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
    - Safety-rule fit: which of the three documented exception shapes
      it fits (or "no exception needed").
  ## May-2026 specifics
    - Anything that's NEW or has GROWN since 2025: new daemon, new
      Tahoe 16.x behavior, recent Xcode/SDK release, etc. This is the
      part that explains "why now".

Hard rules:
  - Cite every claim. No verdict without evidence.
  - If you cannot probe a path (perms denied), say so explicitly.
  - Do NOT propose categories that violate the no-dynamic-path rule.
    Read /Users/lion/Documents/Projects/mine/mac-cleaner/CLAUDE.md
    section "Hard safety rules" before proposing - there are exactly
    three documented exception shapes; a new category must fit one of
    them or be rejected.
  - Read the existing system-data spec at
    /Users/lion/Documents/Projects/mine/mac-cleaner/docs/superpowers/specs/2026-05-10-system-data-categories-design.md
    so you know what's already covered and don't duplicate work.

Report cap: under 600 words.
```

**The 10 hypothesis fillings:**

| ID | Claim | Suggested probe paths |
|----|-------|----------------------|
| H1 | Xcode + Apple developer tooling caches grow without bound and contribute materially to System Data on dev machines. | `~/Library/Developer/CoreSimulator/Caches`, `~/Library/Developer/XCTestDevices`, `~/Library/Developer/XCPGDevices`, `~/Library/Caches/com.apple.dt.Xcode`, `~/Library/Developer/Xcode/iOS Device Logs`, `~/Library/Developer/Xcode/iOS DeviceSupport`, `~/Library/Developer/CoreSimulator/Devices` |
| H2 | Native compilation toolchain caches (ccache, sccache, swiftpm, clangd, bazel, cargo, go, composer) grow into multi-GB on dev machines. | `~/Library/Caches/ccache`, `~/Library/Caches/Mozilla.sccache`, `~/Library/Caches/org.swift.swiftpm`, `~/.cache/clangd`, `/private/var/tmp/_bazel_$USER`, `~/Library/Caches/bazel`, `~/.cargo/registry`, `$(go env GOMODCACHE 2>/dev/null)`, `$(go env GOCACHE 2>/dev/null)`, `~/Library/Caches/composer` |
| H3 | Container/VM disk images (Docker, OrbStack, Colima, Lima, Podman) grow without bound and don't shrink without explicit prune + fstrim. | `~/Library/Containers/com.docker.docker/Data/vms`, `~/.orbstack/data`, `~/.colima/_lima`, `~/.lima`, `~/.local/share/containers/podman/machine` |
| H4 | Browser caches (Safari, Chrome, Arc, Edge, Brave, Firefox) grow into multi-GB via DevTools, ServiceWorker, GPU shader caches, and aren't surfaced by Apple's storage UI. | `~/Library/Containers/com.apple.Safari/Data/Library/Caches`, `~/Library/Application Support/Google/Chrome`, `~/Library/Application Support/Arc/User Data`, `~/Library/Application Support/Microsoft Edge`, `~/Library/Application Support/BraveSoftware/Brave-Browser`, `~/Library/Caches/Firefox/Profiles` |
| H5 | macOS housekeeping artifacts — Time Machine local APFS snapshots, stale `Install macOS *.app` stubs, DiagnosticReports — accumulate silently. | `tmutil listlocalsnapshots /`, `/Applications` (glob `Install macOS *.app`), `~/Library/Logs/DiagnosticReports`, `/Library/Logs/DiagnosticReports` |
| H6 | User-app bundled caches (Apple Music streaming, Mail Downloads) grow into GB and are unreachable from the apps' settings UI. | `~/Library/Caches/com.apple.Music`, `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`, `~/Library/Mail` (for context only — not deletion target) |
| H7 | Apple Intelligence + on-device ML caches (Tahoe 16.x) — Genmoji, Image Playground, Writing Tools, Siri context, on-device LLM models — are a NEW major source of System Data growth in 2026. | `~/Library/Caches/com.apple.assistantd`, `~/Library/Caches/com.apple.intelligenceplatform`, `~/Library/Containers/com.apple.imagineintents`, `~/Library/Caches/com.apple.WritingTools`, `/System/Library/AssetsV2` (read-only inspect), `/private/var/db/com.apple.intelligenceplatform`, `~/Library/Caches/com.apple.GenerativePlayground`, `~/Library/Application Support/com.apple.intelligenceplatform`, `launchctl list | grep -i intelligence`, `launchctl list | grep -i assistant` |
| H8 | Third-party app sandbox container caches (`~/Library/Containers/<bundle>/Data/Library/Caches`, `~/Library/Group Containers/<group>`) fall outside the existing tool's `~/Library/Caches` denylist iteration and are invisible to mac-cleaner. | `~/Library/Containers` (sum sizes per bundle, find top 20 by size), `~/Library/Group Containers` (same — top 20 by size). For top 5 of each: identify owning app, examine cache subpaths, check for tool-provided clear commands |
| H9 | Part of System Data is opaque growth that mac-cleaner CANNOT reclaim — APFS purgeable space, FileVault recovery artifacts, snapshot accounting beyond `tmutil thinlocalsnapshots`. The README needs to honestly tell users about this gap. | `df -hi /System/Volumes/Data`, `diskutil apfs list`, `diskutil info /`, `mount | grep apfs`, `tmutil listbackups`, `tmutil listlocalsnapshotdates`, `tmutil status`. Compare `df` "available" vs "purgeable" |
| H10 | Background daemon write-amplification — services like `mds_stores`, `bird`/CloudKit, `analyticsd`, `corespeechd`, etc. — accumulate state under `/private/var/db`, `/Library/Application Support`, `/Library/Logs` and grow unboundedly. Identify which are user-clearable without sudo or SIP risk. | `/private/var/db` (top-level subdirs by size, where readable), `/Library/Application Support` (top by size), `/Library/Logs`, `/private/var/folders` (purgeable summary, not deletion target), `launchctl list` (filter by io stats / large state), `~/Library/Application Support` (top by size, exclude user docs) |

- [ ] **Step 2: Send the dispatch message**

Single message with 10 Agent tool calls, one per row above. Use `subagent_type: "general-purpose"`, `model: "sonnet"`, with the prompt = skeleton + filled slots from the row. Set `run_in_background: false` (we want all 10 results back before proceeding).

- [ ] **Step 3: Wait for all 10 to return**

Each agent returns a single message. The tool results are visible to the assistant only — relay nothing to the user yet. Capture all 10 reports for the review gate in Task 3. Save each report's content to a scratch file under `/tmp/round1-H<N>.md` so a long-running session doesn't lose them when context compresses:

```bash
# Run for each report after the agent returns; substitute REPORT_TEXT with the agent's report:
cat > /tmp/round1-H1.md <<'REPORT_EOF'
<paste agent H1's full report here>
REPORT_EOF
```
Repeat for H2..H10.

- [ ] **Step 4: Sanity check the reports**

Run:
```bash
ls -la /tmp/round1-H*.md && wc -w /tmp/round1-H*.md
```
Expected: 10 files, each under ~600 words (the cap). Any agent that returned an empty/short report or didn't follow the structure → re-dispatch that single agent in Task 3 review-gate step 1.

---

## Task 3: Review gate

**Files:**
- Read: `/tmp/round1-H*.md` (10 files written in Task 2).
- No file changes; this task is conversation + AskUserQuestion.

- [ ] **Step 1: Run the 5-step automated checklist**

Build the gate summary by reading each report and applying these 5 filters (in order):

1. **Coverage check.** Each of H1–H10 must have a verdict (`in-scope-existing` / `in-scope-new` / `out-of-scope-rejected`). Any report that didn't return a verdict, or returned "couldn't probe" / "ambiguous" → flag for re-dispatch with a tightened prompt before continuing. If any flagged, re-dispatch via a single Agent call (sequential, not parallel — only 1 agent), wait for return, update `/tmp/round1-H<N>.md`, then re-run this step.
2. **Evidence quality check.** Every `in-scope-new` verdict cites at least one local-probe number AND one external source. Missing either → mark for Round 2 deep-dive.
3. **Cross-cut check.** Any path two agents independently flagged → auto-promote to Round 2 candidate.
4. **Surprise filter.** Sort `in-scope-new` findings by claimed local size (this Mac), descending. Top 3 by size → Round 2 candidates.
5. **"Why now" filter.** Any finding tagged in May-2026-specifics as new-in-Tahoe-16 → Round 2 candidate even if size is small.

The output of this step is an internal table: `{candidate_id, source_finding, recommended_priority, reason}`.

- [ ] **Step 2: Present the summary to the user**

Write a single message to the user containing:
1. **One-line summary per Round 1 agent (10 lines):** `H<N>: <verdict> | <headline-size-on-this-Mac> | <top-citation>`.
2. **Ranked Round 2 candidate list (0–N entries):** for each, the candidate question, the source filter that surfaced it, the assistant's recommended priority.
3. **"Remaining unknowns" list:** open questions Round 1 raised but didn't answer (citation conflicts, unprobed paths due to perms, etc.).
4. **An explicit ask via AskUserQuestion:** "Which Round 2 deep-dives to dispatch (pick 0–4)?" Options: top 4 ranked candidates as a multi-select, plus an "all of the above" and "skip Round 2 — synthesize directly" option.

- [ ] **Step 3: Capture the user's Round 2 selection**

Record the user's selection (which 0–4 candidates) into `/tmp/round2-dispatch.md` as a numbered list. If user says "skip Round 2," skip Task 4 and go to Task 5.

---

## Task 4: Dispatch Round 2 — 0–4 deep-dive agents (CONDITIONAL)

**Files:**
- Read: `/tmp/round2-dispatch.md` (written in Task 3).
- No file changes. Single tool message with 0–4 Agent calls.

**Skip this task entirely if `/tmp/round2-dispatch.md` is empty or says "skip Round 2."**

- [ ] **Step 1: Compose Round 2 prompts**

Each Round 2 prompt uses the same skeleton as Round 1, with two changes:
- Replace `<HYPOTHESIS_ID>` with `R2-<N>` and `<HYPOTHESIS_CLAIM>` with the specific candidate question (e.g., `"~/Library/Containers/com.example/Data/Library/Caches is 47 GB on this Mac. Explain growth mechanism, identify owning app's tool-provided clear command if any, and propose a safe reclaim path that fits one of the three documented exception shapes."`).
- Replace the report-cap line with `Report cap: under 1000 words.`

- [ ] **Step 2: Send the dispatch message**

Single message with 0–4 Agent tool calls (`subagent_type: "general-purpose"`, `model: "sonnet"`).

- [ ] **Step 3: Wait for return and save reports**

For each Round 2 agent that returns:
```bash
cat > /tmp/round2-R2-1.md <<'REPORT_EOF'
<paste report>
REPORT_EOF
```
Repeat for R2-2..R2-4.

---

## Task 5: Synthesis — bucket findings

**Files:**
- Read: all `/tmp/round1-H*.md` and `/tmp/round2-R2-*.md`.
- No file changes; this is in-context bucketing.

- [ ] **Step 1: Build the flat findings table**

Read each report and build a list of finding objects. Each finding:
```
{
  hypothesis_id: "H1" | ... | "R2-N",
  path: "/absolute/path",
  size_on_this_mac: "<du -sh output>",
  verdict: "in-scope-existing" | "in-scope-new" | "out-of-scope-rejected",
  owning_app_or_daemon: "<name>",
  regen_risk: "<low/medium/high + one-line reason>",
  may_2026_specific: true | false,
  citations: ["url1", "url2", ...],
}
```
Hold this table inline in the conversation; no file write needed.

- [ ] **Step 2: De-duplicate**

Findings naming the same path collapse to one row; merge citations and pick the strongest verdict (`in-scope-new` > `in-scope-existing` > `out-of-scope-rejected` if disagreement, with a "reconciliation note" added to the row).

- [ ] **Step 3: Bucket by verdict**

Three buckets:
- **Backfill bucket** = all `in-scope-existing` findings → justify the 19 categories.
- **Gap bucket** = all `in-scope-new` findings → become the gap design spec (if non-empty).
- **Out-of-scope bucket** = all `out-of-scope-rejected` findings → populate discovery doc's rejection section.

Note the size of the Gap bucket: `0` means no gap spec is written (Task 7 is skipped).

---

## Task 6: Write the discovery doc

**Files:**
- Create: `docs/superpowers/discovery/2026-05-10-system-data-research.md`

- [ ] **Step 1: Write the discovery doc**

Use the Write tool with this structure:

```markdown
# macOS System Data Research — Discovery

Status: complete YYYY-MM-DD
Plan-of-record: `docs/superpowers/specs/2026-05-10-system-data-research-design.md`
Implements: backfill for `docs/superpowers/specs/2026-05-10-system-data-categories-design.md`

## Methodology

10 hypothesis-driven Sonnet subagents dispatched in parallel (Round 1).
Adaptive review gate. Round 2 deep-dives: <N> dispatched (or "none — Round 1 sufficient").
Four evidence sources: local probe, Apple official docs, community sources, source/tool inspection.

## Backfill — justifying the 19 implemented categories

### category_coresimulator_caches (H1)
[paragraph: claim, top local-probe number, top citation, regen risk, why this category exists]

[... one section per existing category ...]

## Novel sources (Gap bucket)

### Proposed category_<name> (H<N> [+ R2-<M>])
[paragraph: same structure as backfill, plus the proposed category shape]

[... one section per gap finding, OR a single line "no novel sources found beyond current 19" ...]

## May 2026: why now

[ranked list of every finding tagged may_2026_specific=true, by impact, with one-paragraph explanation each]

## Out of scope

[bullet per rejected source with concrete reason, mirroring the existing system-data spec's "Out of scope" pattern]

## Personal findings (this-Mac-specific)

[only if Round 2 surfaced bloat unique to this Mac that's not generalizable]
[else: omit this section entirely]

## Open questions

[citation conflicts and unprobed paths, for future research]
```

- [ ] **Step 2: Run completeness check**

Run:
```bash
for cat in coresimulator_caches xctest_xcpg_devices xcode_dt_cache xcode_device_logs swiftpm clangd_index ccache cargo_registry go_caches composer apple_music_stream_cache mail_downloads diagnostic_reports tm_local_snapshots macos_installers sccache bazel container_vms browser_caches; do
  if grep -q "category_$cat" docs/superpowers/discovery/2026-05-10-system-data-research.md; then
    echo "OK   $cat"
  else
    echo "MISS $cat"
  fi
done
```
Expected: all 19 categories print "OK". Any "MISS" → add a paragraph for that category, then re-run.

- [ ] **Step 3: Run citation integrity sample-check**

Pick 5 random external URLs from the doc:
```bash
grep -oE 'https?://[^ )]+' docs/superpowers/discovery/2026-05-10-system-data-research.md | sort -u | shuf -n 5
```
For each, use WebFetch with a 1-line prompt ("Is this URL resolvable? Return YES/NO + page title.") to verify it resolves. If any fail → fix or replace the citation, then continue.

Pick 5 random local paths from the doc and verify with `du -sh`:
```bash
grep -oE '(~|/[A-Za-z][A-Za-z0-9._/-]+)' docs/superpowers/discovery/2026-05-10-system-data-research.md | grep -E '^(~|/Library|/System|/private|/Applications)' | sort -u | shuf -n 5 | while read p; do
  expanded="${p/#\~/$HOME}"
  echo "$p -> $(du -sh "$expanded" 2>&1 | head -1)"
done
```
Expected: paths exist. If a path doesn't exist on this Mac, the doc must say "not present on this Mac" rather than imply a size.

---

## Task 7: Write the gap-categories spec (CONDITIONAL)

**Files:**
- Create: `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md`

**Skip this task if the Gap bucket from Task 5 is empty.** In that case, the discovery doc's "Novel sources" section already says "no novel sources found beyond current 19" and no gap spec is written.

- [ ] **Step 1: Run the no-dynamic-path audit on every gap finding**

For each finding in the Gap bucket, check it against CLAUDE.md's three documented exception shapes:
1. `category_app_caches` shape: hardcoded parent under `$HOME/Library/Caches`, immediate-children iteration, denylist filter.
2. `category_macos_installers` shape: hardcoded parent, immediate-children iteration, literal-pattern allowlist (prefix or suffix).
3. `category_browser_caches` shape: hardcoded top-level + literal-allowlist profile glob + hardcoded leaf-cache subdir list.

Or "no exception needed" — single hardcoded path.

If a gap finding fits NONE of the four (three exceptions + no-exception-needed), move it from the Gap bucket to the Out-of-scope bucket with reason `does not fit any documented exception shape — would require widening the rule`. Update the discovery doc accordingly.

- [ ] **Step 2: Write the gap spec**

Use the same shape as `2026-05-10-system-data-categories-design.md`. Sections: Goal, Scope (Tier 1 vs Tier 2 split), Out of scope (just the gap-bucket items moved out by step 1), Reconciliation with existing categories, Tier 1 categories table, Tier 2 categories (one section each), Integration with existing patterns, Run order in `main()`, Logging additions, Verification, Implementation notes, Files to touch at implementation time.

Reference the discovery doc as the source of evidence for every category.

- [ ] **Step 3: Self-review the gap spec**

Apply the brainstorming skill's 4-point self-review (placeholders, consistency, scope, ambiguity). Fix inline.

---

## Task 8: Verification + commit

**Files:**
- Modified: none beyond Tasks 6–7.

- [ ] **Step 1: Final completeness pass**

Run:
```bash
ls -la docs/superpowers/discovery/2026-05-10-system-data-research.md && \
ls -la docs/superpowers/specs/2026-05-10-system-data-gaps-design.md 2>/dev/null || echo "(no gap spec — Gap bucket was empty)"
```

- [ ] **Step 2: Stage and inspect the diff**

Run:
```bash
git add docs/superpowers/discovery/2026-05-10-system-data-research.md
[ -f docs/superpowers/specs/2026-05-10-system-data-gaps-design.md ] && git add docs/superpowers/specs/2026-05-10-system-data-gaps-design.md
git diff --cached --stat
```
Expected: 1 or 2 new files staged. No other changes.

- [ ] **Step 3: Present to user for review BEFORE commit**

Show the user:
- Path of the discovery doc.
- Path of the gap spec (or "no gap spec — no novel sources found").
- Top 3 findings by impact (one line each).
- Number of in-scope-new categories proposed (or 0).
- An explicit ask: "Ready to commit?"

Wait for user approval. If they request changes, make them inline, re-run completeness + citation checks (Task 6 steps 2–3), then re-ask.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs: system data research + gap categories spec

Output of the May 2026 macOS System Data research cycle defined in
docs/superpowers/specs/2026-05-10-system-data-research-design.md.
Discovery doc backfills the 19 implemented categories and documents
novel sources found by the 10 Round 1 agents (+ N Round 2 deep-dives).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If the gap bucket was empty, the commit subject becomes `docs: system data research (no novel gaps)` and the body line about the gap spec is dropped.

- [ ] **Step 5: Confirm**

Run:
```bash
git log --oneline -5
```
Expected: most recent commit reflects the doc(s) added.

---

## Self-review checklist (run after writing this plan)

1. **Spec coverage:** Every section of the research design spec maps to a task here. ✓
   - Goal/deliverables → Tasks 6–7.
   - Round 1 hypotheses (10) → Task 2 dispatch table.
   - Per-agent prompt contract → Task 2 prompt skeleton.
   - Review gate → Task 3.
   - Round 2 → Task 4 (conditional).
   - Synthesis → Task 5.
   - Verification → Task 6 step 2/3, Task 8.
   - Cost considerations → not a task; it's a constraint reflected in the agent count.
2. **Placeholder scan:** No "TBD", "TODO", "fill in details". The `<HYPOTHESIS_ID>` etc. inside the prompt skeleton are intentional template slots filled by the dispatch table immediately below.
3. **Type/identifier consistency:** `Backfill bucket` / `Gap bucket` / `Out-of-scope bucket` used consistently in Tasks 5, 6, 7. Hypothesis IDs `H1..H10` and `R2-1..R2-4` used consistently throughout.
4. **Path consistency:** Discovery doc path is `docs/superpowers/discovery/2026-05-10-system-data-research.md` everywhere. Gap spec path is `docs/superpowers/specs/2026-05-10-system-data-gaps-design.md` everywhere. Scratch files are `/tmp/round1-H<N>.md` and `/tmp/round2-R2-<N>.md` everywhere.
