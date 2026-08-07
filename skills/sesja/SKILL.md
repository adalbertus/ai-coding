---
name: sesja
description: Entry point for deliberative sessions — starts a topic, checkpoints the session to ./tmp/SESJA.md so the context can be cleared, and resumes it afterwards. Never compacts. Scope is any deliberation, with or without a grill; a fresh topic is opened by calling the grill-with-docs skill. Use when the user starts stress-testing a design, says a long design conversation is getting heavy or leaving the smart zone, wants to checkpoint or resume such a session, or invokes /sesja.
disable-model-invocation: true
---

# /sesja — one deliberative session across many context windows

Deliberation sessions grow past the point where they work well. **Never `/compact` them**: a
compact loses what was *rejected*, so the session re-opens settled branches and re-asks answered
questions. Instead put the settled part on disk, the open part in `./tmp/SESJA.md`, and `/clear`.

Scope is the **deliberation vs implementation** axis, nothing narrower: any conversation whose
context is mostly proposals, counter-arguments and killed variants qualifies, whether or not
`grill-with-docs` is driving it. Implementation runs are out — their context is verbatim file
reads, so clearing them is a loss. When this skill does open a grill it **calls**
`grill-with-docs`, never copies its prompt (same pattern as `to-issues-ralph` over `to-issues`).
See `docs/adr/0006`, `CONTEXT.md`.

## Pick the mode

Decide from **what is in the current context**, not from whether the file exists:

| current context | `./tmp/SESJA.md` | mode |
|---|---|---|
| holds a deliberation dialogue | either way | **checkpoint** (or **close**, if the user declares it done) |
| fresh | exists | **resume** |
| fresh | missing | **start** (need a topic — ask if none was given) |

Judging "is there a deliberation above me" is direct observation of visible context. Do **not**
try to judge your own token usage — you cannot see it, and you will confabulate.

## Start

A **new** topic opens as a grill: call `grill-with-docs` with the topic and the framing below
(settled/rejected/glossary empty; the proactivity rule is not). This is the default entry, not
the definition of the skill — the other three modes serve any deliberation. Starting here rather
than calling `grill-with-docs` directly is the point: the first session on a topic is the
longest, so it needs that rule most. A plain design conversation needs no start mode — the user
just talks, and reaches for `/sesja` at the first checkpoint.

## Checkpoint

1. Split the session: rulings → `CONTEXT.md` / `docs/adr/` (only if `grill-with-docs` has not
   filed them already); everything else → `./tmp/SESJA.md`.
2. Overwrite `./tmp/SESJA.md` in the format below. `mkdir -p ./tmp` first.
3. Before writing any **pointer** (`→ ADR 0006`), `grep` that the target exists. If it does not,
   write the decision **inline** instead. That is the only check: do **not** audit whether the
   session did its job, and do **not** file ADRs on its behalf (that would copy the three-part
   test `grill-with-docs` owns). You may *flag* an obvious missing ADR in one sentence.
4. Never write `./tmp/STATUS.md` — separate skill, separate role (`/zapisz` writes for the
   human; this file is written for the next model).
   If `git check-ignore -q tmp/SESJA.md` fails, say so in Polish in one line and point at
   `/sesja-konfiguracja` — then carry on. Do **not** offer to edit `.gitignore` here: setup
   questions belong to setup, and a checkpoint runs when the user is deep in a session and
   least able to entertain one.
5. End by telling the user, in Polish, what was saved and to run **`/clear` now** — the
   checkpoint alone does not shrink the window; only clearing does.

## Resume

1. Read `./tmp/SESJA.md`.
2. **Read the ADR / `CONTEXT.md` sections it points at yourself**, by range — before delegating.
   Left to `grill-with-docs` it would be a request; done here it is a certainty.
3. Print one header line in Polish — „wznawiam sesję »X« z 12 czerwca, otwarte: 3 gałęzie" — and
   **do not wait for confirmation**: a dead topic is recognisable by its name, and a wrong resume
   costs one message. Never apply a staleness threshold in days — that is guesswork.
4. Per the `Wznowić` field: `grill-with-docs` → call it with the framing; `rozmowa` → just carry
   on the conversation, no delegation and no framing (there is nobody to frame).
5. Then stay out of the way until the user invokes `/sesja` again.

## Close

Triggered by the user saying so ("domknięte", "idę do PRD") — the main path, because a session
ends when the user has enough for a PRD, not when the open list empties (an empty list is only a
*prompt* to close). Show what is left open, confirm it is immaterial, delete `./tmp/SESJA.md`,
point at `/to-prd`. `/to-prd` itself deletes nothing — someone else's skill.

## Framing (goes in the **arguments** of the call, never in this file's prose)

Only for the `grill-with-docs` branch — start, and a resume whose `Wznowić` says so.

Arguments land last, below the called skill's body, so they win by recency over its "interview me
relentlessly about **every** aspect… walk down **each** branch" — which, unframed, marches
through settled ground. Include:

- the topic, and **"start at branch N"**;
- **settled** — do not re-open without a counter-argument;
- **rejected + reasons** — do not propose these again;
- the **glossary** agreed so far;
- the proactivity rule, phrased as an *observation*, not a measurement: „jeśli zauważysz, że
  pytasz o coś już wymienionego jako ustalone albo odrzucone — przerwij i zaproponuj `/sesja`".

## `./tmp/SESJA.md` format

One per repo, gitignored, ~30 lines — a list, not prose; Polish labels, as it is the on-disk
contract. **Ustalone** holds pointers **and one-line decisions** passing neither the ADR test nor
the glossary — the largest class, dead at `/clear` without it, and exactly what `/to-prd` later
consumes. Half-settled things go under **Otwarte** with the known part attached: what matters is
whether a decision is still owed, not how much is already known (a false "open" costs one
question; a false "settled" costs a design built on an unexamined assumption).

```markdown
# Sesja: <temat>
Zapisano: <data godzina> · Wznowić: grill-with-docs | rozmowa

## Ustalone
- <decyzja w jednej linii> (<powód w kilku słowach>)
- <termin albo decyzja> → ADR 0006 · CONTEXT: ramka

## Otwarte
1. <gałąź> — <część już ustalona, jeśli połowicznie rozstrzygnięta>
2. <gałąź>

## Odrzucone
- <wariant> — <powód>

## Słownik
- <termin> — <znaczenie ustalone w tej sesji>
```
