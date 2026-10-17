---
name: to-issues-ralph
description: Turn a finished grill into a Ralph-loop epic in two non-interactive invocations. Without an argument (`/to-issues-ralph`) it fills the PRD with grill findings missing from it, publishes it as a parent `[PRD]` issue with an acceptance scenario (`## Jak odebrać`), and ends the turn with the epic number and the next command (`/clear`, then `/to-issues-ralph <nr>`) — no breakdown. With an issue number (`/to-issues-ralph <nr>`), in a fresh session, it reads the PRD from the epic's body, breaks it into vertical slices published as native sub-issues of that epic, then adds complexity triage per sub-issue — and, for each heavy one, the list of cases its tests must cover. Asks no questions. Every piece of work is an epic, even a one-line change. Use after a grill session to convert a plan/PRD into issues the Ralph autonomous loop (ralph/once.sh) will implement, or when the user mentions Ralph, epic, complexity triage, or per-issue model selection.
---

# To Issues (Ralph)

Runs the post-grill chain **non-interactively** in two invocations. Without an argument: fill
the PRD gaps → publish the PRD as an epic (parent issue) → stop. With an epic number, in a
fresh session: break it into vertical slices published as sub-issues of that epic → complexity
triage → report. It asks no questions. Every piece of work is an epic, even a one-line change:
an epic with a single sub-issue (ADR 0012).

It does not reimplement PRD synthesis or breakdown — it **delegates** to `to-prd` and
`to-issues`, wrapping each call with an override that suppresses their interactive
checkpoints. Delegating (not copying) means upstream changes keep working here.

## Invocation with an epic number

`/to-issues-ralph <nr>` breaks down an **existing** epic in a fresh session; with no argument,
run step 1 only and stop (see "Invocation without an argument").

1. Fetch the issue: `gh issue view <nr> --json number,title,body`.
2. Check the preconditions. If either fails, print one message saying which and why, create
   nothing, and stop:
   - the title starts with `[PRD]` — otherwise it is not an epic;
   - it has no sub-issues yet — `gh api "repos/{owner}/{repo}/issues/<nr>/sub_issues" --jq length`
     must be `0`; otherwise the epic is already broken down.
3. The PRD is **only** the epic's body. Do not read a file or rely on the conversation. Do not
   run step 1 (the epic exists); use that PRD as the input to step 2 with epic number `<nr>`,
   then continue with steps 3–5 and the report unchanged.

## Invocation without an argument

Run step 1 of the workflow and **stop there**. Do not run steps 2–5 and do not break down.
Before publishing, review the grill context for findings that are in neither the PRD nor the
repo's documents (`CONTEXT.md`, `docs/adr/`): decisions, rejected options, constraints, edge
cases. Add each to the matching PRD section without asking. A finding already recorded in an
ADR or `CONTEXT.md` is only referenced, not copied. After publishing, end the turn with the
epic number and this line: `/clear`, then `/to-issues-ralph <nr>`.

## Workflow

1. **Publish the epic.** Invoke the `to-prd` skill with this override:
   > Run `to-prd` **non-interactively**: skip its step-2 human check on modules/tests —
   > make the module and test-target calls yourself from the grill context. Publish the PRD
   > as the epic: title `[PRD] <name>`, label `ready-for-agent`, and do NOT add any
   > `complexity:*` label. Before publishing, append exactly one section, `## Jak odebrać`:
   > the acceptance scenario for the whole epic — 3–7 concrete steps a human follows to judge
   > whether the result is what they want, using real UI labels where that makes sense. Do
   > not keep the PRD in your response as breakdown input and do not continue to a breakdown:
   > publishing the epic is the end of this run.

   Why: the PRD denoises a long grill session into a clean one-page breakdown input and
   supplies the exhaustive user-story list the breakdown uses as a coverage checklist. The
   breakdown runs later, in a fresh session, from the epic's body. It lands in the epic because that parent issue exists anyway for odbiór (ADR 0012), so storing
   it costs nothing; `ralph/once.sh` filters `[PRD]` issues out, so the epic is never picked
   up as work. The epic is published before its sub-issues so they can point at it.

2. **Run the breakdown non-interactively** (only with an epic number). Invoke the `to-issues` skill with this override:
   > Run `to-issues` **non-interactively** from the PRD in the epic's body (do not look
   > for a file). Do NOT perform its step 4 (Quiz the user) and do NOT
   > wait for approval — treat the breakdown as approved and proceed straight to publishing.
   > This countermands `to-issues`' "Iterate until the user approves." Publish every slice as
   > a native sub-issue of the epic from step 1: set the parent with
   > `gh issue create --parent <epic number>`. Do NOT add a `## Jak sprawdzić ręcznie`
   > section to any slice — manual acceptance belongs to the epic. After publishing, in
   > the same turn, continue with steps 3–5 of `to-issues-ralph`.

   It applies the AFK triage label itself. Prefix every issue title with `[ISSUE]`
   (e.g. `[ISSUE] Add user login`).

3. **Link blockers.** The loop takes blockers only from GitHub's native "blocked by"
   relation, never from body text. For every sub-issue whose `## Blocked by` section names
   other issues, add each one as a native blocker (`issue_id` is the blocker's internal `id`,
   not its number):
   ```bash
   gh api -X POST "repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by" \
     -F issue_id="$(gh api "repos/{owner}/{repo}/issues/<blocker>" --jq .id)"
   ```
   Leave the `## Blocked by` text as written. A sub-issue without blockers needs nothing.

4. **Triage complexity.** Add **exactly one** `complexity:*` label to each **sub-issue**
   (never to the epic), using the rubric below. Create the label first if the repo lacks it:
   ```bash
   gh label create complexity:heavy   --color B60205 --description "Case list + review by the strongest model" 2>/dev/null
   gh label create complexity:normal  --color FBCA04 --description "Default model" 2>/dev/null
   gh label create complexity:trivial --color 0E8A16 --description "Cheapest model — mechanical only" 2>/dev/null
   gh issue edit <n> --add-label complexity:<tier>
   ```

5. **Write the case list (heavy only).** For each `complexity:heavy` sub-issue, first read the
   code the slice will touch — where the check, rule or calculation lives today and every entry
   point that reaches it — then insert a `## Przypadki do przetestowania` section directly
   before `## Blocked by`. Open it with one line stating why the slice is heavy (e.g. "heavy —
   touches tenant-isolation logic"), then list the cases, one bullet each, as
   `situation → expected outcome`, concrete enough to become a test with no further judgment:
   ```markdown
   ## Przypadki do przetestowania

   heavy — touches tenant-isolation logic.

   - user of tenant A, `GET /orders/{id of tenant B}` → 404, not 403 (no existence leak)
   - user of tenant A, `GET /orders` → only tenant A's orders, also when B has more
   - order id that does not exist → 404, same body as the cross-tenant case
   ```
   Cover what makes the slice heavy: the boundaries, the second path around the check, the
   error path. Describe behaviour, never file names or test code — the worker writes the
   tests, and a stronger model reviews them against this list after the worker closes the
   issue. Always write the list; when the code leaves a case uncertain, write your best case
   and say what is uncertain.

End the turn only here (invocation with an epic number), with the epic (number, title) followed by one line per sub-issue:
number, title, tier, blockers.

## Complexity rubric

The label encodes intrinsic complexity, NOT a model name. Complexity here means one precise
thing: **would a stronger model materially change the outcome?** — the difficulty of getting
the implementation *right*, not the blast radius of getting it *wrong*. Those axes are
orthogonal, and only the first justifies spending a stronger model (as reviewer — see `heavy`). The complexity→model mapping lives
only in `ralph/once.sh`; never put a model name in the label.

**Blast radius is not complexity.** A wide-but-mechanical change (e.g. `ADD COLUMN … DEFAULT 0`
on a shared table) can break a lot if wrong, yet a stronger model implements it no better. The
safety net for blast radius is the automated gate plus `needs-human-test`, not a more expensive
model — so route such a slice by its substance, which is usually `normal`.

**Design judgment is front-loaded.** By the time a slice reaches this loop it has been through
`grill-with-docs` → PRD → breakdown on a strong model with a human, so "the design isn't
settled" should almost never appear here. If a slice still looks under-specified, that is a gap
in the grill or breakdown: **sharpen its acceptance criteria until a mid-tier model can finish
it — do not escalate the model to paper over a vague issue.** Sharpen before you escalate.

- **`complexity:trivial`** — ONLY truly mechanical, zero-logic changes: a documentation typo, a
  config/constant bump, a pure rename, a dependency version bump. If a human reviewer would not
  need to think, it is trivial. **Anything that touches behaviour or logic — however small — is
  NOT trivial.** When in doubt, it is `normal`. This tier runs on the weakest model unattended,
  so be strict.

- **`complexity:normal`** — the default, and the target for almost everything. A well-scoped
  tracer-bullet slice with clear acceptance criteria: an additive field, an isolated service
  with tests, ordinary CRUD — and also wide-but-mechanical changes whose risk is covered by the
  gate plus human test. If a settled spec and the worker's own tests can close it, it is normal.
  Use this whenever you hesitate.

- **`complexity:heavy`** — reserved for the one case where a green gate is not enough:
  **implementation correctness that a green gate would not prove.** Concretely, work where a
  plausible-but-wrong implementation would pass the tests the worker writes for itself —
  tenant-isolation / authorization / other security enforcement, or subtle logic (financial,
  date/time, algorithmic) with easy-to-miss cases. The tell: what matters is enumerating *what
  to test*, not merely passing the obvious test. Nothing else — not size, not blast radius, not
  a "run code-review before merging" note — is enough on its own. A heavy slice is answered
  with a case list (step 5) and a review by a stronger model, not by a stronger implementer.

## Notes

- Apply exactly one tier per issue. An untagged issue is treated as `normal` by the loop,
  so tagging is a safe-by-default refinement, not a hard requirement.
- This skill only triages; it does not run the loop or choose models. `ralph/once.sh` owns
  the `complexity:* → model` mapping.
