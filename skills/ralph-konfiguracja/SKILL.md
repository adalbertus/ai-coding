---
name: ralph-konfiguracja
description: One-time HITL setup that makes a repo runnable by the shared Ralph loop. Detects the stack, writes a usable "## Ralph" section (feedback loops + done-criteria + commit conventions) into the repo's CLAUDE.md, and creates the GitHub labels the loop relies on. Run it in a Claude session on Sonnet or better. Invoked only explicitly via /ralph-konfiguracja (the preflight strażnik points the user here when the section is missing).
disable-model-invocation: true
---

# /ralph-konfiguracja — make this repo runnable by Ralph

The shared loop (`ralph-once` / `ralph-once-local`) is stack-agnostic. Before it will run in a
repo, a **preflight strażnik** (`ralph/preflight.sh`) requires that repo's `CLAUDE.md` to carry
a usable `## Ralph` section declaring **how to test** and **what "done" means**. This skill
writes that section, once, per repo.

This is deliberately a **human-in-the-loop** task on a capable model — the test commands and
done-criteria are repo-judgment, not something to autogenerate blindly. Confirm each piece with
the user before writing.

## What it produces

1. A `## Ralph` section in the repo's `CLAUDE.md` (created if the file is absent), with three
   parts the strażnik checks for: **feedback loops** + **done-criteria** (required), and
   **commit conventions** (recommended).
2. The GitHub labels the loop relies on — **only** for GitHub-backed repos.

## Workflow

### 1. Detect the stack and the real feedback-loop commands

Do not guess. Inspect the repo and confirm the commands actually exist:

- **PHP / Laravel** — `composer.json`. Typical: `composer test` (Pest/PHPUnit),
  `./vendor/bin/pint` (style). Check the `scripts` block for the real script names.
- **JS / TS (incl. React Native / Expo)** — `package.json` `scripts`. Typical:
  `npm run typecheck` (`tsc --noEmit`), `npm run lint`, `npm test`. Use only scripts that
  are actually defined.
- **Anything else** — read the build/test config and ask the user for the canonical
  "run before commit" commands.

Propose the exact command list and have the user confirm. These must be **runnable as-is** —
the strażnik's Haiku gate marks the section MISSING if the loops are vague or placeholder.

### 2. Decide the done-criteria

The key question: **can the automated gate fully prove correctness, or does some work need a
human?** This drives how the worker closes issues (see `ralph/prompt.md` → THE ISSUE).

- **Backend / library / pure-logic repo** (e.g. Laravel API, a TS package) — gate-green is
  enough; the worker may close issues itself.
- **App with UI / device / native surface** (e.g. RN + Expo) — logic fully covered by the
  gate may be closed; anything touching UI or native modules **cannot** be proven by the gate
  and must be handed to a human via `needs-human-test`. If so, also state the convention for
  the manual test steps (language, and that they must reference real UI labels).

Write the criteria as concrete sentences, not "when it works".

### 3. Decide commit conventions (recommended)

Capture anything non-default so the worker matches the repo: message **language**, commit to
**`main`** vs a **branch/PR**, and where the detail goes (commit body vs issue thread). If the
repo has no special convention, you may omit this part — the prompt has a sensible fallback.

### 4. Write the `## Ralph` section

Create `CLAUDE.md` if missing. If a `## Ralph` section already exists, **replace it in place**
(don't append a duplicate). Use a level-2 heading exactly `## Ralph` — the strażnik greps for
it. Sub-sections use `###` (they stay inside the section). Template:

```markdown
## Ralph

Konfiguracja dla współdzielonej pętli Ralpha (`ralph-once` / `ralph-once-local`).

### Feedback loops (uruchom przed każdym commitem — wszystkie muszą być zielone)

- `<komenda>` — <co robi>
- `<komenda>` — <co robi>

### Done-criteria

Zadanie jest skończone, gdy wszystkie feedback loops są zielone <oraz …>.
<Jeśli dotyczy: Zmiany w UI / na urządzeniu / w modułach natywnych NIE są weryfikowalne
automatycznie — nie zamykaj takich issue. Oznacz `needs-human-test` i zostaw człowiekowi
z konkretnymi krokami testowymi po polsku, odwołującymi się do realnych etykiet UI.>

### Commit

<np. wiadomość po polsku, krótka; commit prosto na `main`, bez brancha/PR; detal w wątku issue.>
```

Fill every placeholder. The section the strażnik accepts has **concrete, executable**
instructions for both feedback loops and done-criteria.

### 5. Create the loop's GitHub labels (GitHub-backed repos only)

If the repo has a GitHub remote (`gh repo view` succeeds), create the labels the loop and the
triage skill rely on. Skip this entirely for local-files repos (those driven by
`ralph-once-local` with an `issues/` directory).

```bash
gh label create ready-for-agent  --color 0E8A16 --description "AFK-ready: safe for the autonomous loop to pick up" 2>/dev/null
gh label create needs-human-test --color 5319E7 --description "Implemented; awaiting human verification" 2>/dev/null
gh label create complexity:heavy   --color B60205 --description "Highest-capability model" 2>/dev/null
gh label create complexity:normal  --color FBCA04 --description "Default model" 2>/dev/null
gh label create complexity:trivial --color 0E8A16 --description "Cheapest model — mechanical only" 2>/dev/null
```

(`2>/dev/null` keeps it idempotent — re-running is harmless when a label already exists.)

### 6. Hand back

Tell the user in one or two Polish sentences what was written and what is next: that
`ralph-once` (or `ralph-once-local`) will now pass the strażnik in this repo, and that issues
get triaged with `/to-issues-ralph`.

## Notes

- The strażnik is fail-closed: a missing file, a missing/empty `## Ralph` section, or vague
  loops/criteria all halt the run. This skill's job is to produce a section that passes it.
- Run on **Sonnet or better** — stack detection and done-criteria need real judgment.
- One `## Ralph` section per repo; re-running this skill should update it in place.
