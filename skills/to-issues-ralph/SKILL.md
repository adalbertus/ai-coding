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

The label encodes intrinsic complexity, NOT a model name. The complexity of a slice does
not change over time; which model is best for each tier does — that mapping lives only in
`ralph/once.sh`. Never put a model name in the label.

- **`complexity:trivial`** — ONLY truly mechanical, zero-logic changes: a documentation
  typo, a config/constant bump, a pure rename, a dependency version bump. If a human
  reviewer would not need to think, it is trivial. **Anything that touches behaviour or
  logic — however small — is NOT trivial.** When in doubt, it is `normal`. This tier runs
  on the weakest model unattended, so be strict.

- **`complexity:normal`** — the default. A well-scoped tracer-bullet slice with clear
  acceptance criteria: an additive field, an isolated service with tests, ordinary CRUD.
  Most slices are normal. Use this whenever you hesitate.

- **`complexity:heavy`** — high blast radius or genuine judgment required: a schema
  migration on shared/widely-used tables, tenant-isolation or other security/authorization
  logic, anything the source marks "run code-review before merging", or a slice whose
  design is not fully settled by the acceptance criteria.

## Notes

- Apply exactly one tier per issue. An untagged issue is treated as `normal` by the loop,
  so tagging is a safe-by-default refinement, not a hard requirement.
- This skill only triages; it does not run the loop or choose models. `ralph/once.sh` owns
  the `complexity:* → model` mapping.
