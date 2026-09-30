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

Check that it is unblocked: if its "Blocked by" section references an issue that is still open
(`gh issue view <blocker>`), tell the human and let them decide whether to go on.

# REPO CONTRACT (## Ralph in {AGENT_CONTRACT_FILE})

Everything specific to THIS repo — the feedback-loop commands to run, what "done" means
(done-criteria), and any commit conventions — lives in the `## Ralph` section of this repo's
{AGENT_CONTRACT_FILE}. Read it now and follow it.

# EXPLORATION

{EXPLORE_GUIDANCE}

# IMPLEMENTATION

Use {SKILL_TDD} to complete the task. Keep risky logic (parsing, the data layer, business rules,
date math) in isolated, unit-testable modules, following this repo's conventions. Where
{SKILL_TDD} asks you to confirm seams, ask the human.

# FEEDBACK LOOPS, DOC-SYNC, COMMIT

Same rules as an unattended run. Before committing, run the feedback loops declared in `## Ralph`
and make them all green; use exactly those commands. If — and only if — you are about to close the
issue on the automated gate, reconcile the durable docs the `## Ralph` section lists: status-class
docs get updated in the same commit, glossary/design-class docs (CONTEXT.md, ADRs) only get a note
in the issue thread. Commit following the `## Ralph` conventions. On an epic branch
(`epic/<number>`), commit on the current branch and do not switch branches, merge, or push.

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
