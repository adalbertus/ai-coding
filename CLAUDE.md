# ai-coding — agent notes

Personal Claude Code tooling: skills (`/zapisz`, `/podsumuj`, `/ralph-konfiguracja`,
`/to-issues-ralph`) plus the shared Ralph loop. Distributed as symlinks by `install.sh`.

- **Glossary / domain model:** `CONTEXT.md` — read before introducing a new term, and add it there.
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
- **Don't hand-write the `## Ralph` section** in another repo's CLAUDE.md — `/ralph-konfiguracja`
  does that.

## Tests

```bash
bash ralph/test/preflight.test.sh
```

The only test suite; run it after changing `ralph/*.sh` (especially `preflight.sh`). The model
branch is stubbed via `RALPH_GATE_CMD`, so the test is deterministic — no network, no `claude`.
