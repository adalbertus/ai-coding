# THE TASK

A single GitHub issue has been selected for you and is provided at the start of context as
`## Issue #<number>: <title>` followed by its body. Work ONLY this issue.

This issue is HITL: it does not carry `ready-for-agent`, because it needs a human decision or a
human action. A human is present in this session and can answer you. Do not stop on the
"needs a human" question the way an unattended run would — asking is the point of this session.

You've also been passed the last few commits. Review them to understand what work has been done.

# START WITH THE OPEN QUESTION

Before writing any code, read the issue (and its comments: `gh issue view <number> --comments`)
and tell the human, in your first message, what decision or action is needed from them — with your
recommendation and the reasoning behind it. Then wait for their answer. If the issue turns out to
need nothing from them after all, say so and go on.

# REPO CONTRACT (## Ralph in AGENTS.md)

Everything specific to THIS repo — the feedback-loop commands to run, what "done" means
(done-criteria), and any commit conventions — lives in the `## Ralph` section of this repo's
AGENTS.md. Read it now and follow it.

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
date math) in isolated, unit-testable modules, following this repo's conventions. Where
$tdd asks you to confirm seams, ask the human.

# FEEDBACK LOOPS, DOC-SYNC, COMMIT

Same rules as an unattended run. Before committing, run the feedback loops declared in `## Ralph`
and make them all green; use exactly those commands. If — and only if — you are about to close the
issue on the automated gate, reconcile the durable docs the `## Ralph` section lists: status-class
docs get updated in the same commit, glossary/design-class docs (CONTEXT.md, ADRs) only get a note
in the issue thread. Commit following the `## Ralph` conventions. On an epic branch
(`epic/<number>`), commit on the current branch and do not switch branches, merge, or push.
If you change the `## Ralph` section itself, make the identical change in both `CLAUDE.md` and
`AGENTS.md` (whichever exist) in the same commit — the preflight guard halts the next run when
the two differ.

# CLOSING THE ISSUE

First find out whether the issue has a parent (it is then a sub-issue of an epic):
`gh api repos/{owner}/{repo}/issues/<number>/parent --jq .number` (404 / no output = no parent).

- **Issue with no parent** — apply the done-criteria from `## Ralph`. Done and verified by the
  gate: `gh issue close <number> --comment "<summary + commit SHA>"`. Needs human verification:
  leave it open, add `needs-human-test` (`gh label create needs-human-test --color 5319E7
  --description "Implemented; awaiting human verification" 2>/dev/null`, then
  `gh issue edit <number> --add-label needs-human-test`), and comment what to verify — pointing at
  the issue's own manual-verification section if it has one and adding only deviations. Not
  complete: leave it open and comment on progress.
- **Sub-issue of an epic** — the epic is the unit of human acceptance, so close the sub-issue on
  the automated gate alone (`gh issue close`, with summary + commit SHA); no `needs-human-test`
  and no manual test steps on the sub-issue. Deviations from the plan go to the epic
  (`gh issue comment <epic>`); no deviations, no comment. Do not mark the epic for acceptance
  yourself: the loop script does it once its last sub-issue is closed.
  Gate not green or work unfinished: leave the sub-issue open and comment on progress.

The issue does not get `ready-for-agent` back from you: only the human returns an issue to the
unattended loop.

# FINAL RULES

ONLY WORK ON A SINGLE TASK. Do only what this issue asks; features, files, docs beyond
DOC-SYNC, or refactors are not part of it — name them in your closing comment instead.
