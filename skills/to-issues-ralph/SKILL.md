---
name: to-issues-ralph
description: Turn a finished grill into a published Ralph-loop epic in one non-interactive run — publishes the PRD as a parent `[PRD]` issue with an acceptance scenario (`## Jak odebrać`), breaks it into vertical slices published as native sub-issues of that epic, then adds complexity triage per sub-issue. Asks no questions. Every piece of work is an epic, even a one-line change. Use after a grill session to convert a plan/PRD into issues the Ralph autonomous loop (ralph/once.sh) will implement, or when the user mentions Ralph, epic, complexity triage, or per-issue model selection.
---

# To Issues (Ralph)

Runs the whole post-grill chain **non-interactively**: publish the PRD as an epic (parent
issue) → break it into vertical slices published as sub-issues of that epic → complexity
triage → report. It asks no questions. Every piece of work is an epic, even a one-line change:
an epic with a single sub-issue (ADR 0012).

It does not reimplement PRD synthesis or breakdown — it **delegates** to `to-prd` and
`to-issues`, wrapping each call with an override that suppresses their interactive
checkpoints. Delegating (not copying) means upstream changes keep working here.

## Workflow

1. **Publish the epic.** Invoke the `to-prd` skill with this override:
   > Run `to-prd` **non-interactively**: skip its step-2 human check on modules/tests —
   > make the module and test-target calls yourself from the grill context. Publish the PRD
   > as the epic: title `[PRD] <name>`, label `ready-for-agent`, and do NOT add any
   > `complexity:*` label. Before publishing, append exactly one section, `## Jak odebrać`:
   > the acceptance scenario for the whole epic — 3–7 concrete steps a human follows to judge
   > whether the result is what they want, using real UI labels where that makes sense. Also
   > keep the full PRD in your response as breakdown input. The PRD is not a stopping point:
   > in the same turn, continue with step 2 of `to-issues-ralph`.

   Why: the PRD denoises a long grill session into a clean one-page breakdown input and
   supplies the exhaustive user-story list the breakdown uses as a coverage checklist. It
   lands in the epic because that parent issue exists anyway for odbiór (ADR 0012), so storing
   it costs nothing; `ralph/once.sh` filters `[PRD]` issues out, so the epic is never picked
   up as work. The epic is published before its sub-issues so they can point at it.

2. **Run the breakdown non-interactively.** Invoke the `to-issues` skill with this override:
   > Run `to-issues` **non-interactively** from the PRD synthesized in step 1 (already in
   > context — do not look for a file). Do NOT perform its step 4 (Quiz the user) and do NOT
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
   gh label create complexity:heavy   --color B60205 --description "Highest-capability model" 2>/dev/null
   gh label create complexity:normal  --color FBCA04 --description "Default model" 2>/dev/null
   gh label create complexity:trivial --color 0E8A16 --description "Cheapest model — mechanical only" 2>/dev/null
   gh issue edit <n> --add-label complexity:<tier>
   ```

5. **Record why (heavy only).** For a `complexity:heavy` sub-issue, insert a `## Complexity`
   section directly before `## Blocked by`, holding one line that states why (e.g. "heavy —
   touches tenant-isolation logic").

End the turn only here, with the epic (number, title) followed by one line per sub-issue:
number, title, tier, blockers.

## Complexity rubric

The label encodes intrinsic complexity, NOT a model name. Complexity here means one precise
thing: **would a stronger model materially change the outcome?** — the difficulty of getting
the implementation *right*, not the blast radius of getting it *wrong*. Those axes are
orthogonal, and only the first justifies a pricier model. The complexity→model mapping lives
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

- **`complexity:heavy`** — reserved for the one case where a stronger model genuinely pays back:
  **implementation correctness that a green gate would not prove.** Concretely, work where a
  plausible-but-wrong implementation would pass the tests the worker writes for itself —
  tenant-isolation / authorization / other security enforcement, or subtle logic (financial,
  date/time, algorithmic) with easy-to-miss cases. The tell: a stronger model is more likely to
  enumerate *what to test*, not merely to pass the obvious test. Nothing else — not size, not
  blast radius, not a "run code-review before merging" note — is enough on its own.

## Notes

- Apply exactly one tier per issue. An untagged issue is treated as `normal` by the loop,
  so tagging is a safe-by-default refinement, not a hard requirement.
- This skill only triages; it does not run the loop or choose models. `ralph/once.sh` owns
  the `complexity:* → model` mapping.
