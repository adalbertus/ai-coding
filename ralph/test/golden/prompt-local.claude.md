# ISSUES

A LIST of the local issue files in `issues/` is provided at the start of context — one line per
file: its path and its first heading. The bodies are NOT included, deliberately: loading the whole
backlog would spend context you need for the implementation.

Pick ONE file by its title (see TASK SELECTION below), then read THAT file and no other. You will
work on the AFK issues only, not the HITL ones — the title usually says which it is; if it does
not, read the file to find out and move on to the next candidate if it turns out to be HITL.

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

**Search before you read.** A full `Read` of a large reference file (a glossary, a big module)
can cost tens of thousands of tokens, and every one of them stays in context for the rest of the
run — degrading your own reasoning exactly when the implementation needs it. So:

- **If you can name what you are looking for** — a term, a symbol, a function, a path — use
  `Grep`/`Glob`, then `Read` only the matching range (`offset`/`limit`). This is the default, and
  it is not a compromise: it returns the exact source text, just less of it.
- **Only if you cannot formulate a search pattern**, because you need an overview rather than a
  specific fact, delegate to the `Explore` subagent. It reads in its own context and returns
  conclusions. It costs a full extra model run and gives you a paraphrase instead of the source,
  so it earns its keep for open-ended reconnaissance and nothing else.

This is how to read an instruction like "read `CONTEXT.md` before introducing a new term" in a
repo's CLAUDE.md: **consult** that file for what you need. Do not pull all of it into context.

# IMPLEMENTATION

Use /tdd to complete the task. Keep risky logic (parsing, the data layer, business rules,
date math) in isolated, unit-testable modules, following this repo's conventions. Some work
cannot be proven by the automated gate (e.g. UI, or device/native behaviour); for that, write
the thin layer over the tested modules and rely on human verification — the `## Ralph`
done-criteria say when that applies (see THE ISSUE).

# FEEDBACK LOOPS

Before committing, run the feedback loops declared in the `## Ralph` section of CLAUDE.md and
make them all green. Do not invent commands — use exactly the ones declared there.

# DOC-SYNC (only when you will move the issue to issues/done/)

If — and ONLY if — this issue's done-criteria are fully met by the automated gate and you are
about to move it to `issues/done/` yourself (no human verification needed), reconcile this
repo's durable docs with what you actually shipped, and include those edits in the commit below.
The `## Ralph` section lists the docs and their class:

- **status-class** docs (e.g. known-gaps, backlog) — update them to match reality.
- **glossary/design-class** docs (e.g. CONTEXT.md, ADRs) — do NOT rewrite; at most note the
  needed change in the issue file. They belong to the design phase, not this loop.

If `## Ralph` declares no durable docs, this step is inert — skip it. If the issue instead needs
human verification (see THE ISSUE), do NOT sync docs now — doc-sync for that path is deferred to
the human's close-out.

# COMMIT

Make a git commit, following any commit conventions declared in `## Ralph` (e.g. message
language, committing to `main` vs a branch/PR, where to put the detail). If `## Ralph` says
nothing about commits, default to a message that records: (1) key decisions made, (2) files
changed, (3) blockers or notes for the next iteration.

# THE ISSUE

Apply the done-criteria from `## Ralph` to decide how to close out:

- **Done and fully verified by the automated gate** — move the issue file to `issues/done/`.

- **Implemented but the gate cannot prove it works** (the `## Ralph` done-criteria call for
  human verification) — do NOT move it to `issues/done/`. Leave it in `issues/` and add a clear
  "NEEDS HUMAN TEST" note:

  - **If the issue body already has a manual-verification section** (e.g. `## Jak sprawdzić
    ręcznie`), it was written when the issue was created, by a stronger model with the whole
    plan in view — do NOT rewrite it. Point the human at it and add ONLY the deviations the
    implementation introduced: steps that no longer match, extra checks the work turned out to
    need, actual UI labels that differ from the ones assumed there. If nothing deviates, say
    exactly that.
  - **Only if the issue has no such section**, write the instructions from scratch: concrete,
    step-by-step, in the language/format the `## Ralph` section specifies (reference the actual
    UI labels where it applies).

  A human verifies, then moves it to done.

- **Not complete** (gate not green, or work unfinished) — leave the file in `issues/` and add
  a note with what was done, what remains, and blockers for the next iteration.

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
