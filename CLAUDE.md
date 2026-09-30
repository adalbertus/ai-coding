# ai-coding — agent notes

Personal AI coding tooling: skills (`/zapisz`, `/podsumuj`, `/sesja`, `/sesja-konfiguracja`,
`/ralph-konfiguracja`, `/to-issues-ralph`; Codex uses `$...`) plus the shared Ralph loop.
Distributed as symlinks by `install.sh`.

- **Glossary / domain model:** `CONTEXT.md` — consult it (grep for the term) before introducing a
  new term, and add it there. It is a glossary: look terms up, don't read it end to end.
- **Design decisions:** `docs/adr/` — document any significant architecture change with a new ADR.
- **User-facing overview:** `README.md`.

## Conventions

- **Language:** human-facing text — `README.md`, ADRs, `CONTEXT.md`, commit messages, script output
  (`echo` printed to the user) — in Polish. Agent-facing text — `SKILL.md` bodies and their
  `description`, model prompts, strings fed to a model (e.g. the `No commits found` fallbacks), and
  this file — in English. Code comments stay English.
- **Editing = production.** `~/.claude/skills/*`, `~/.codex/skills/*`, and
  `~/.local/bin/ralph-*` are symlinks INTO this repo. Edit a file here → the change is live
  immediately after the relevant agent reloads. `install.sh` only creates links (idempotent,
  never overwrites others' files); it does not copy content.
- **Don't hand-write the `## Ralph` / `## Sesja` sections** in another repo's `CLAUDE.md` or
  `AGENTS.md` — `/ralph-konfiguracja` / `$ralph-konfiguracja` and
  `/sesja-konfiguracja` / `$sesja-konfiguracja` do that.
- **Native agent contract files carry instructions only** — no rationale, no `docs/adr/`
  pointers, no references to files outside that repo. Every line is re-read on every message
  there, so anything a reader could look up elsewhere is a permanent tax; and a cross-repo
  pointer breaks the moment the other repo is not cloned. Applies to what the skills here
  *write* into other repos as much as to this file.
- **Never put a repo's rules in global agent files** such as `~/.claude/CLAUDE.md` or
  `~/.codex/AGENTS.md`. They are not distributed by `install.sh`, so the behaviour vanishes on
  another machine and cannot be versioned with the work it governs.

## Sesja

Dotyczy rozmów, w których ważymy projekt, plan albo decyzję — z grillem lub bez. Nie dotyczy
przebiegów implementacyjnych: tam kontekst to dosłowne odczyty plików, więc jego czyszczenie
jest stratą, nie zyskiem.

- Gdy zauważysz w widocznym kontekście, że wracamy do sprawy uznanej wyżej za ustaloną albo
  odrzuconą — albo że pytasz drugi raz o to samo — przerwij i zaproponuj `/sesja`.
- To ma być obserwacja tego, co widać w rozmowie, nigdy szacowanie własnego zużycia kontekstu
  ani odległości do limitu. Nie masz do tego wglądu.
- Nie proponuj `/compact` dla takiej rozmowy: gubi to, co odrzucone, więc napędza powtórzone
  pytania. Zamiast tego `/sesja`, potem `/clear`.

## Tests

```bash
bash ralph/test/preflight.test.sh
bash ralph/test/lib.test.sh
bash ralph/test/epic.test.sh
```

Run these after changing `ralph/*.sh` **or `ralph/prompt*.md`**. The model branch is stubbed via
`RALPH_GATE_CMD`, so preflight tests are deterministic — no network, no installed agent runtime.

`lib.test.sh` compares the rendered prompts against `ralph/test/golden/*` for both runtimes.
After a deliberate prompt change, regenerate them and commit the diff:

```bash
UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh
```

## Ralph

Configuration for the shared Ralph loop (`ralph-once`).

Run the loop only from a separate worktree on branch `ralph` (e.g. `../ai-coding-ralph`), never
from this checkout.

### Feedback loops (run before every commit — all must be green)

- `bash ralph/test/preflight.test.sh` — preflight strażnik tests (model gate stubbed).
- `bash ralph/test/epic.test.sh` — `ralph-epic` loop against a dummy `once.sh` and a fake `gh`.
- `bash ralph/test/lib.test.sh` — lib functions and rendered prompts vs `ralph/test/golden/*`.
  After a deliberate prompt change, regenerate with `UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh`
  and commit the golden diff.

### Done-criteria

A task is done when both feedback loops are green and the issue's acceptance criteria are met.

Work runs in epics: an epic is a `[PRD]` issue with sub-issues. Close a sub-issue yourself once
the gate is green — including changes to prompts and skills. The gate does not prove how prompts
and skills behave on a live model, how `ralph/once.sh` behaves against real GitHub, or whether
`README.md` reads well; the human checks that when accepting the epic, not per sub-issue. Never
label a sub-issue `needs-human-test` and write no manual test steps for it. Describe deviations
from the plan in a comment on the epic (no deviations = no comment). After closing the last
sub-issue, label the epic `needs-human-test` and comment that it awaits acceptance.

Issue with no parent: close it yourself once the gate is green; in the closing comment, list any
deviations from its `## Jak sprawdzić ręcznie` section, or say there are none.

### Doc-sync (durable docs — sync on issue close)

- `README.md` — **status-class** → update it to match what shipped, in the same commit.
- `CONTEXT.md`, `docs/adr/` — **glossary/design-class** → only flag the needed change in an issue
  comment; never rewrite them.

### Commit

- Message in Polish, a short subject in the style of `git log`; add a body only when a decision
  needs explaining.
- Commit to the current branch (`ralph`); never switch branches, never commit to `main`, no PR.

### Closing an epic

When I say "zamykaj" / "potwierdzam" / "zrobione, zamykaj" about an epic labelled
`needs-human-test`:

1. If `README.md` does not match what the epic shipped (derive it from the epic, its sub-issues
   and commits), fix it in the `ralph` worktree and commit there.
2. Close the epic.

Merging `ralph` into `main` is mine — never do it.

### Acceptance feedback

When I point out fixes while accepting an epic:

- Small: fix it right away in this session, in the `ralph` worktree, and commit there.
- Larger: open a new sub-issue `[ISSUE] Poprawka: …` under the epic, labelled `ready-for-agent`,
  and remove `needs-human-test` from the epic — the loop does the fix and puts the epic up for
  acceptance again.
