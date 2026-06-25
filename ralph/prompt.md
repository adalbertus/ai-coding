# THE TASK

A single GitHub issue has already been selected for you (by priority and eligibility) and
is provided at the start of context as `## Issue #<number>: <title>` followed by its body.
Work ONLY this issue — do not list or switch to a different one.

You've also been passed a file containing the last few commits. Review these to understand
what work has been done.

# REPO CONTRACT (## Ralph in CLAUDE.md)

This loop is stack-agnostic. Everything specific to THIS repo — the feedback-loop commands
to run, what "done" means (done-criteria), and any commit conventions — lives in the
`## Ralph` section of this repo's CLAUDE.md. Read it now and follow it. A preflight guard has
already confirmed the section exists and is usable, so it is safe to rely on.

# SANITY CHECK BEFORE STARTING

The `ready-for-agent` label is the contract for AFK-ready work, but that separation is by
convention, not guaranteed — an issue can be mislabelled, and the blocked check upstream
is best-effort. So before implementing, verify two things with `gh`:

- **Still AFK?** If the issue actually requires a human decision — an architectural choice,
  a design review, an ambiguous trade-off the body does not settle, or a destructive/
  irreversible step — do NOT guess. Leave it open, add a comment explaining what decision
  is needed (`gh issue comment <number>`), and output <promise>NO MORE TASKS</promise>.
- **Still unblocked?** If its "Blocked by" section references an issue that is still open
  (`gh issue view <blocker>`), do the same: comment that it is blocked and output
  <promise>NO MORE TASKS</promise>.

# EXPLORATION

Explore the repo. Note its structure and conventions (CLAUDE.md), and the existing tests that
the `## Ralph` feedback loops run.

# IMPLEMENTATION

Use /tdd to complete the task. Keep risky logic (parsing, the data layer, business rules,
date math) in isolated, unit-testable modules, following this repo's conventions. Some work
cannot be proven by the automated gate (e.g. UI, or device/native behaviour); for that, write
the thin layer over the tested modules and rely on human verification — the `## Ralph`
done-criteria say when that applies (see THE ISSUE).

# FEEDBACK LOOPS

Before committing, run the feedback loops declared in the `## Ralph` section of CLAUDE.md and
make them all green. Do not invent commands — use exactly the ones declared there.

# COMMIT

Make a git commit, following any commit conventions declared in `## Ralph` (e.g. message
language, committing to `main` vs a branch/PR, where to put the detail). If `## Ralph` says
nothing about commits, default to a message that records: (1) key decisions made, (2) files
changed, (3) blockers or notes for the next iteration.

# THE ISSUE

Apply the done-criteria from `## Ralph` to decide how to close out:

- **Done and fully verified by the automated gate** — close the issue:
  `gh issue close <number> --comment "<summary of what shipped + the commit SHA>"`.

- **Implemented but the gate cannot prove it works** (the `## Ralph` done-criteria call for
  human verification — e.g. UI, a device, or other manual checks) — do NOT close it. Leave it
  open, mark it for a human, and post concrete, step-by-step manual test instructions in the
  language/format the `## Ralph` section specifies (reference the actual UI labels where it
  applies):
  ```bash
  gh label create needs-human-test --color 5319E7 --description "Implemented; awaiting human verification" 2>/dev/null
  gh issue edit <number> --add-label needs-human-test
  gh issue comment <number> --body "<what to verify, step by step>"
  ```
  After the human verifies, THEY close the issue.

- **Not complete** (gate not green, or work unfinished) — leave the issue open WITHOUT the
  `needs-human-test` label and record progress:
  `gh issue comment <number> --body "<what was done, what remains, blockers for next iteration>"`.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
