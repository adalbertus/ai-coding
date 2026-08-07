---
name: sesja-konfiguracja
description: One-time per-repo setup for the /sesja skill. Writes a "## Sesja" section into the repo's CLAUDE.md so a long deliberation gets interrupted before it leaves the smart zone, and makes sure ./tmp/ stays out of git. Invoked only explicitly via /sesja-konfiguracja.
disable-model-invocation: true
---

# /sesja-konfiguracja — arm this repo for `/sesja`

`/sesja` works in any repo without setup, but nothing will **remind** the user to use it: the
skill is explicit-invocation only, so a deliberation drifts out of the smart zone unnoticed
until they think of it themselves — at the worst possible moment for remembering anything. The
reminder has to sit in the repo's `CLAUDE.md`, which is in context from the first message.

This skill puts it there, once, per repo. The section is near-identical everywhere: this is
**distribution**, not configuration, and that is fine — the point is that the rule is opt-in per
repo and versioned with it, rather than smuggled in through a global file that only works on one
machine.

Two things happen here rather than at checkpoint time, deliberately: checkpoint runs when the
user is deep in a session and tired of it, so any question that can be asked earlier should be.

## 1. Keep `./tmp/` out of git

`/sesja` writes `./tmp/SESJA.md`, which must never be committed. Check:

```bash
git check-ignore -q tmp/SESJA.md
```

Non-zero → tell the user in Polish, in one line, and **offer** to append `tmp/` to `.gitignore`.
Never edit `.gitignore` unasked — it is a tracked file and may be somebody else's.

## 2. Write the `## Sesja` section

Into the repo's `CLAUDE.md` (create the file if absent). Level-2 heading exactly `## Sesja`. If
one already exists, **replace it in place** — never append a duplicate. Verbatim template; it is
short on purpose, because everything in `CLAUDE.md` is paid for on every single message:

```markdown
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
```

Do **not** enrich it — no rationale, no pointers into `docs/adr/`, no cross-repo references.
`CLAUDE.md` carries instructions only; anything a reader could look up elsewhere is a permanent
tax on every message in that repo.

## 3. Hand back

One or two Polish sentences: that this repo will now propose a checkpoint on its own, and that
`/sesja <temat>` starts a topic. Mention the `.gitignore` change only if one was made.
