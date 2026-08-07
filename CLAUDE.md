# ai-coding — agent notes

Personal Claude Code tooling: skills (`/zapisz`, `/podsumuj`, `/sesja`, `/sesja-konfiguracja`,
`/ralph-konfiguracja`, `/to-issues-ralph`) plus the shared Ralph loop. Distributed as symlinks
by `install.sh`.

- **Glossary / domain model:** `CONTEXT.md` — consult it (grep for the term) before introducing a
  new term, and add it there. It is a glossary: look terms up, don't read it end to end.
- **Design decisions:** `docs/adr/` — document any significant architecture change with a new ADR.
- **User-facing overview:** `README.md`.

## Conventions

- **Language:** human-facing text — `README.md`, ADRs, `CONTEXT.md`, commit messages, script output
  (`echo` printed to the user) — in Polish. Agent-facing text — `SKILL.md` bodies and their
  `description`, model prompts, strings fed to a model (e.g. the `No commits found` fallbacks), and
  this file — in English. Code comments stay English.
- **Editing = production.** `~/.claude/skills/*` and `~/.local/bin/ralph-*` are symlinks INTO this
  repo. Edit a file here → the change is live immediately, no reinstall. `install.sh` only creates
  the links (idempotent, never overwrites others' files); it does not copy content.
- **Don't hand-write the `## Ralph` / `## Sesja` sections** in another repo's CLAUDE.md —
  `/ralph-konfiguracja` and `/sesja-konfiguracja` do that.
- **A `CLAUDE.md` carries instructions only** — no rationale, no `docs/adr/` pointers, no
  references to files outside that repo. Every line is re-read on every message there, so
  anything a reader could look up elsewhere is a permanent tax; and a cross-repo pointer breaks
  the moment the other repo is not cloned. Applies to what the skills here *write* into other
  repos as much as to this file.
- **Never put a repo's rules in the global `~/.claude/CLAUDE.md`.** It is not distributed by
  `install.sh`, so the behaviour vanishes on another machine and cannot be versioned with the
  work it governs.

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
```

The only test suite; run it after changing `ralph/*.sh` (especially `preflight.sh`). The model
branch is stubbed via `RALPH_GATE_CMD`, so the test is deterministic — no network, no `claude`.
