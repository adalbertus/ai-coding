# THE TASK

A single GitHub issue has already been selected for you (by priority and eligibility) and
is provided at the start of context as `## Issue #<number>: <title>` followed by its body.
Work ONLY this issue — do not list or switch to a different one.

You've also been passed a file containing the last few commits. Review these to understand
what work has been done.

# REPO CONTRACT (## Ralph in AGENTS.md)

This loop is stack-agnostic. Everything specific to THIS repo — the feedback-loop commands
to run, what "done" means (done-criteria), and any commit conventions — lives in the
`## Ralph` section of this repo's AGENTS.md. Read it now and follow it. A preflight guard has
already confirmed the section exists and is usable, so it is safe to rely on.

# SANITY CHECK BEFORE STARTING

The `ready-for-agent` label is the contract for AFK-ready work, but that separation is by
convention, not guaranteed — an issue can be mislabelled, and the blocked check upstream
is best-effort. So before implementing, verify two things with `gh`:

- **Still AFK?** If the issue actually requires a human decision or a human action — an
  architectural choice, a design review, an ambiguous trade-off the body does not settle, or a
  destructive/irreversible step — do NOT guess. The issue is HITL, not AFK: remove its
  `ready-for-agent` label (`gh issue edit <number> --remove-label ready-for-agent`) so the loop
  does not pick it up again, comment exactly what is needed, with your recommendation
  (`gh issue comment <number>`), and output <promise>NO MORE TASKS</promise>. It returns to the
  loop only when the human restores the label.
- **Still unblocked?** If its "Blocked by" section references an issue that is still open
  (`gh issue view <blocker>`), do the same: comment that it is blocked and output
  <promise>NO MORE TASKS</promise>.

# EXPLORATION

Explore the repo. Note its structure and conventions (AGENTS.md), and the existing tests that
the `## Ralph` feedback loops run.

**Search before you read.** `cat`-ing a large reference file (a glossary, a big module) into
context can cost tens of thousands of tokens, and every one of them stays in context for the rest
of the run — degrading your own reasoning exactly when the implementation needs it. Reading a file
whole is the easiest way to run this loop out of context. So read in two steps:

1. **Locate the lines** — `rg -n '<pattern>' <path>` (or `grep -rn '<pattern>' <path>` where `rg`
   is not installed). This gives you the file and the line numbers, not the file.
2. **Read only that range** — `sed -n '<start>,<end>p' <file>`, with a window of a few dozen lines
   around the hit. If the range turns out to be too narrow, widen it or search again. Two targeted
   reads still cost a fraction of the whole file.

Use `cat` only on a file you already know is short — `wc -l <file>` when unsure. Never `cat` a
glossary, a contract file, or a directory-wide glob.

This is how to read an instruction like "read `CONTEXT.md` before introducing a new term" in a
repo's AGENTS.md: **consult** that file for what you need. Do not pull all of it into context.

# IMPLEMENTATION

Use $tdd to complete the task. Keep risky logic (parsing, the data layer, business rules,
date math) in isolated, unit-testable modules, following this repo's conventions. Some work
cannot be proven by the automated gate (e.g. UI, or device/native behaviour); for that, write
the thin layer over the tested modules and rely on human verification — the `## Ralph`
done-criteria say when that applies (see THE ISSUE).

Where $tdd asks you to confirm seams with the user, nobody is there to answer: derive the
seams from the issue's acceptance criteria, list them in your closing issue comment, and proceed.

# FEEDBACK LOOPS

Before committing, run the feedback loops declared in the `## Ralph` section of AGENTS.md and
make them all green. Do not invent commands — use exactly the ones declared there.
A loop that failed to start is not green. If all that is missing is the repo's declared
dependencies, install them with its own package manager and lockfile; otherwise treat the issue
as not complete (see THE ISSUE).

# DOC-SYNC (only when you will self-close)

If — and ONLY if — this issue's done-criteria are fully met by the automated gate and you are
about to close it yourself (no human verification needed), reconcile this repo's durable docs
with what you actually shipped, and include those edits in the commit below. The `## Ralph`
section lists the docs and their class:

- **status-class** docs (e.g. known-gaps, backlog) — update them to match reality.
- **glossary/design-class** docs (e.g. CONTEXT.md, ADRs) — do NOT rewrite; at most note the
  needed change in the issue thread. They belong to the design phase, not this loop.

If `## Ralph` declares no durable docs, this step is inert — skip it. If the issue instead needs
human verification (see THE ISSUE), do NOT sync docs now — doc-sync for that path is deferred to
the human's close-out.

# COMMIT

Make a git commit, following any commit conventions declared in `## Ralph` (e.g. message
language, committing to `main` vs a branch/PR, where to put the detail). If `## Ralph` says
nothing about commits, default to a message that records: (1) key decisions made, (2) files
changed, (3) blockers or notes for the next iteration.

If the loop put you on an epic branch (`epic/<number>`), commit there, on the current branch —
even if the `## Ralph` commit conventions name a different branch — and do not switch branches,
merge, or push.

# THE ISSUE

First find out whether the issue has a parent (it is then a sub-issue of an epic):
`gh api repos/{owner}/{repo}/issues/<number>/parent --jq .number` (a 404 / no output means no
parent; `gh issue view <number> --json parent` is fine if your `gh` supports it). Then pick the path:

- **Issue with no parent** — apply the done-criteria from `## Ralph` as described below.
- **Sub-issue of an epic** — follow SUB-ISSUE OF AN EPIC below instead. The epic is the unit of
  human acceptance, so this issue is closed on the automated gate alone, whatever the `## Ralph`
  done-criteria say about manual verification (that human part moves to the epic).

## Issue with no parent

Apply the done-criteria from `## Ralph` to decide how to close out:

- **Done and fully verified by the automated gate** — close the issue:
  `gh issue close <number> --comment "<summary of what shipped + the commit SHA>"`.

- **Implemented but the gate cannot prove it works** (the `## Ralph` done-criteria call for
  human verification — e.g. UI, a device, or other manual checks) — do NOT close it. Leave it
  open, mark it for a human, and post the manual test instructions as a comment:

  - **If the issue body already has a manual-verification section** (e.g. `## Jak sprawdzić
    ręcznie`), it was written when the issue was created, by a stronger model with the whole
    plan in view — do NOT rewrite it. Point the human at it and add ONLY the deviations the
    implementation introduced: steps that no longer match, extra checks the work turned out to
    need, actual UI labels that differ from the ones assumed there. If nothing deviates, say
    exactly that.
  - **Only if the issue has no such section**, write the instructions from scratch: concrete,
    step-by-step, in the language/format the `## Ralph` section specifies (reference the actual
    UI labels where it applies).

  ```bash
  gh label create needs-human-test --color 5319E7 --description "Implemented; awaiting human verification" 2>/dev/null
  gh issue edit <number> --add-label needs-human-test
  gh issue comment <number> --body "<what to verify, step by step>"
  ```
  After the human verifies, THEY close the issue.

- **Not complete** (gate not green, or work unfinished) — leave the issue open WITHOUT the
  `needs-human-test` label and record progress:
  `gh issue comment <number> --body "<what was done, what remains, blockers for next iteration>"`.

## SUB-ISSUE OF AN EPIC

- **Gate green** — do DOC-SYNC (edits go into the same commit), commit, then close the sub-issue
  with `gh issue close <number> --comment "<summary of what shipped + the commit SHA>"`. Do not add
  `needs-human-test` to the sub-issue and do not write manual test instructions for it.
  - **Deviations go to the epic, not the sub-issue.** If the implementation deviated from the plan
    — steps in the epic's acceptance scenario that no longer match, extra checks the work turned
    out to need, actual UI labels that differ from the ones assumed — post them with
    `gh issue comment <epic> --body "<deviations>"`. If nothing deviates, write nothing in the epic.
  - **Marking the epic for acceptance is not yours.** The loop script labels the epic
    `needs-human-test` once its last sub-issue is closed; do not label or comment on it for that.
- **Gate not green or work unfinished** — same as the "Not complete" path above: leave the
  sub-issue open without `needs-human-test` and comment on it with progress.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.

This run is unattended: nobody reads your messages until it ends, and a message without a tool
call stalls the run. Keep working until you have closed the issue out in one of the three ways
under THE ISSUE. Do not end a turn with a summary that announces the next step, an offer to
continue, or a question you can answer from the repo yourself. The only early stops are the two
in SANITY CHECK BEFORE STARTING, and a blocker you have recorded with `gh issue comment`.

Do only what this issue asks. Tests the feedback loops need are part of the work; features,
files, docs beyond the DOC-SYNC step, or refactors are not — if one would help, name it in your
closing issue comment instead of doing it.
