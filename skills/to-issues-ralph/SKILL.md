---
name: to-issues-ralph
description: Break a plan into Ralph-loop issues — runs the standard to-issues breakdown, then triages each published issue's complexity so the loop can pick a model. Use when converting a plan/PRD into issues that the Ralph autonomous loop (ralph/once.sh) will implement, or when the user mentions Ralph, complexity triage, or per-issue model selection.
---

# To Issues (Ralph)

Thin wrapper over the `to-issues` skill. It does not reimplement the breakdown — it
**delegates** to `to-issues`, then adds one step: tagging each published issue with a
`complexity:*` label so `ralph/once.sh` can choose the model to run it on.

Delegating (not copying) means upstream changes to `to-issues` keep working here.

## Workflow

0. **Prefix the parent PRD issue.** If the source is an existing GitHub issue (the PRD),
   rename it to add a `[PRD]` prefix — unless the title already starts with `[PRD]`:
   ```bash
   gh issue edit <prd-n> --title "[PRD] $(gh issue view <prd-n> --json title -q .title)"
   ```

1. **Run the standard breakdown.** Invoke the `to-issues` skill and let it draft, quiz,
   and publish the vertical-slice issues exactly as usual (it applies the AFK triage
   label itself). Do not duplicate or alter that process.
   Prefix every issue title with `[ISSUE]` (e.g. `[ISSUE] Add user login`).

2. **Add manual verification steps.** For each published issue, edit its body to append
   a `## Jak sprawdzić ręcznie` section — a brief, concrete list (3–5 bullets) showing
   the golden path a human can follow to confirm the slice works. Skip only for pure
   documentation/config changes with nothing observable.

   ```bash
   gh issue edit <n> --body "$(gh issue view <n> --json body -q .body)

   ## Jak sprawdzić ręcznie

   - krok 1
   - krok 2"
   ```

3. **Triage complexity.** After adding verification steps, add **exactly one**
   `complexity:*` label to each issue, using the rubric below. Create the label first if
   the repo lacks it:
   ```bash
   gh label create complexity:heavy   --color B60205 --description "Highest-capability model" 2>/dev/null
   gh label create complexity:normal  --color FBCA04 --description "Default model" 2>/dev/null
   gh label create complexity:trivial --color 0E8A16 --description "Cheapest model — mechanical only" 2>/dev/null
   gh issue edit <n> --add-label complexity:<tier>
   ```

4. **Record why (heavy only).** For a `complexity:heavy` issue, add one line to its body
   stating why (e.g. "heavy — touches tenant-isolation logic"), for the human reader who
   picks it up weeks later.

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
`/grill-with-docs` → PRD → breakdown on a strong model with a human, so "the design isn't
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
