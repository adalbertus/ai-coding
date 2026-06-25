# THE TASK

A single GitHub issue has already been selected for you (by priority and eligibility) and
is provided at the start of context as `## Issue #<number>: <title>` followed by its body.
Work ONLY this issue — do not list or switch to a different one.

You've also been passed a file containing the last few commits. Review these to understand
what work has been done.

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

Explore the repo.

# IMPLEMENTATION

Use /tdd to complete the task.

# FEEDBACK LOOPS

Before committing, run the feedback loops:

- `composer test` to run the test suites (Pest, parallel, against MySQL)
- `./vendor/bin/pint` to fix code style

# COMMIT

Make a git commit. The commit message must:

1. Include key decisions made
2. Include files changed
3. Blockers or notes for next iteration

# THE ISSUE

If the task is complete, close the issue: `gh issue close <number> --comment "<summary of what shipped + the commit SHA>"`.

If the task is not complete, leave the issue open and record progress: `gh issue comment <number> --body "<what was done, what remains, blockers for next iteration>"`.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.