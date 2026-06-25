# ISSUES

Local issue files from `issues/` are provided at start of context. Parse them to understand
the open issues.

You will work on the AFK issues only, not the HITL ones.

You've also been passed a file containing the last few commits. Review these to understand
what work has been done.

If all AFK tasks are complete, output <promise>NO MORE TASKS</promise>.

# REPO CONTRACT (## Ralph in CLAUDE.md)

This loop is stack-agnostic. Everything specific to THIS repo — the feedback-loop commands
to run, what "done" means (done-criteria), and any commit conventions — lives in the
`## Ralph` section of this repo's CLAUDE.md. Read it now and follow it. A preflight guard has
already confirmed the section exists and is usable, so it is safe to rely on.

# TASK SELECTION

Pick the next task. Prioritize tasks in this order:

1. Critical bugfixes
2. Development infrastructure (tests, migrations, factories, dev scripts) — getting this ready
   is an important precursor to building features.
3. Tracer bullets for new features — build a tiny, end-to-end slice of the feature first, then
   expand it out. A slice that goes through all layers validates the approach and surfaces
   architectural problems early, before significant time is invested.
4. Polish and quick wins
5. Refactors

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

- **Done and fully verified by the automated gate** — move the issue file to `issues/done/`.

- **Implemented but the gate cannot prove it works** (the `## Ralph` done-criteria call for
  human verification) — do NOT move it to `issues/done/`. Leave it in `issues/`, add a clear
  "NEEDS HUMAN TEST" note with concrete, step-by-step manual test instructions in the
  language/format the `## Ralph` section specifies. A human verifies, then moves it to done.

- **Not complete** (gate not green, or work unfinished) — leave the file in `issues/` and add
  a note with what was done, what remains, and blockers for the next iteration.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
