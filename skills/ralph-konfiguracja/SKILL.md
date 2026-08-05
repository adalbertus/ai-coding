---
name: ralph-konfiguracja
description: One-time HITL setup that makes a repo runnable by the shared Ralph loop. Detects the stack, writes a usable "## Ralph" section (feedback loops + done-criteria + commit conventions) into the repo's CLAUDE.md, creates the GitHub labels the loop relies on, and proposes rewording any CLAUDE.md instruction that makes agents read a large reference file wholesale. Run it in a Claude session on Sonnet or better. Invoked only explicitly via /ralph-konfiguracja (the preflight strażnik points the user here when the section is missing).
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

1. A `## Ralph` section in the repo's `CLAUDE.md` (created if the file is absent), with the
   parts the strażnik checks for — **feedback loops** + **done-criteria** (required) — plus
   **commit conventions** and **doc-sync** (both recommended; doc-sync only if the repo keeps
   durable docs it can invalidate).
2. The GitHub labels the loop relies on — **only** for GitHub-backed repos.
3. Where it applies: a **reworded** instruction elsewhere in that CLAUDE.md, so agents consult
   large reference files instead of reading them whole (proposed to the user, never silent).

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

### 3. Detect the durable docs (doc-sync)

Find the repo's **durable documentation** — the long-lived files whose content a shipped change
can invalidate. Look for things like `known-gaps.md`, a `backlog`/`ROADMAP`, `CONTEXT.md`,
`docs/adr/`. This set is per-repo: some repos have only `CONTEXT.md`, some several docs, some
none. Do not guess — list what actually exists and confirm the list with the user.

Classify each doc into one of two classes (this drives what the closer is allowed to do):

- **status-class** (e.g. `known-gaps`, `backlog`) — factual "what's done / what's left". The
  closer **rewrites** these to match reality.
- **glossary/design-class** (`CONTEXT.md`, `docs/adr/`) — the shared language and settled
  decisions. The closer only **flags** a needed change (a comment/note); it never rewrites them.
  The glossary belongs to the design phase (`/grill-with-docs`), not the implementation loop.

If the repo keeps no durable docs, skip this — omit the doc-sync subsection and the loop's
trigger stays inert. Otherwise you write the list + classes into the `## Ralph` section (next
step); that is what makes doc-sync fire on close. See `docs/adr/0004` for the rationale.

### 4. Decide commit conventions (recommended)

Capture anything non-default so the worker matches the repo: message **language**, commit to
**`main`** vs a **branch/PR**, and where the detail goes (commit body vs issue thread). If the
repo has no special convention, you may omit this part — the prompt has a sensible fallback.

### 5. Write the `## Ralph` section

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

### Doc-sync (trwała dokumentacja — synchronizuj przy zamknięciu issue)

<Wypełnij tylko, jeśli repo trzyma trwałe dokumenty; inaczej pomiń całą podsekcję.>
Zamykając issue (sam albo po potwierdzeniu człowieka), najpierw pogódź poniższe dokumenty
z tym, co realnie weszło:

- `<ścieżka>` — **statusowy** → aktualizuj treść i wrzuć do commita.
- `CONTEXT.md`, `docs/adr/` — **słownikowe/projektowe** → tylko zgłoś potrzebę zmiany
  (komentarz w issue), NIE przepisuj; słownikiem rządzi grill, nie pętla.

Gdy zamykam ręcznie issue z `needs-human-test` („potwierdzam" / „zamykaj" / „zrobione,
zamykaj"): potraktuj to jako sygnał — najpierw zsynchronizuj dokumenty statusowe (zmianę
wyprowadź z treści issue i jego commitów), dopiero potem zamknij.

### Commit

<np. wiadomość po polsku, krótka; commit prosto na `main`, bez brancha/PR; detal w wątku issue.>
```

Fill every placeholder. The section the strażnik accepts has **concrete, executable**
instructions for both feedback loops and done-criteria.

### 6. Create the loop's GitHub labels (GitHub-backed repos only)

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

### 7. Reword instructions that force whole-file reads (outside `## Ralph`)

The rest of this repo's CLAUDE.md often carries a line like *"`CONTEXT.md` — read before
introducing a new term"*. A worker obeys it literally: a full `Read` of a 68 KB glossary is
~25k tokens, spent before it writes a line of code, and it stays in context for the whole run.
`ralph/prompt.md` tells the worker to search rather than read, but an instruction in CLAUDE.md
saying "read" outranks it in the worker's eyes — so fix the source instead of arguing with it.

Only worth doing where the pointed-at file is genuinely large (rule of thumb: **>20 KB**). Below
that the exploration protocol handles it anyway and the reword is noise.

1. Find the repo's large reference files: `find . -size +20k -name '*.md' -not -path './node_modules/*'`
   plus any oversized single-purpose source file the docs point at.
2. Grep CLAUDE.md for instructions that point at them with a read verb (`read`, `przeczytaj`,
   `zapoznaj się`).
3. **Propose** the reword to the user — show the old line and the new one, and let them accept.
   Never rewrite parts of CLAUDE.md outside `## Ralph` without confirmation; this is the one
   step where this skill touches somebody else's prose. Pattern:

   > `CONTEXT.md` — ~~read~~ **consult it (grep for the term)** before introducing a new term.
   > It is a glossary: look terms up, don't read it end to end.

Skip the step entirely when the repo has no large reference file. See `docs/adr/0005`.

### 8. Hand back

Tell the user in one or two Polish sentences what was written and what is next: that
`ralph-once` (or `ralph-once-local`) will now pass the strażnik in this repo, and that issues
get triaged with `/to-issues-ralph`. Mention the reword from step 7 only if one was made.

## Notes

- The strażnik is fail-closed: a missing file, a missing/empty `## Ralph` section, or vague
  loops/criteria all halt the run. This skill's job is to produce a section that passes it.
- Run on **Sonnet or better** — stack detection and done-criteria need real judgment.
- One `## Ralph` section per repo; re-running this skill should update it in place.
