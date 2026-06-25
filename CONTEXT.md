# ai-coding — słownik projektu

Repo z osobistym toolingiem do Claude Code, dystrybuowanym symlinkami przez `install.sh`.
Dwa obszary: **wznawianie pracy** (`/zapisz`, `/podsumuj`) i **pętla Ralpha** (autonomiczna,
jednozadaniowa implementacja). Decyzje projektowe: `docs/adr/`.

## Wznawianie pracy (`/zapisz`, `/podsumuj`)

Dwa skille, które pomagają wrócić do **jednego wątku pracy na repo**. `/zapisz` zapisuje na
granicy fazy mały wskaźnik pozycji; `/podsumuj` daje 2–3 zdaniowy readout „gdzie jestem +
następny krok", dobierając źródło warstwowo (żywy kontekst → STATUS → ostatni transkrypt).
Zob. `docs/adr/0001`.

**Podsumowanie** (summary):
A 2–3 sentence, position-focused readout — where the work stands and the next step. Ends
with a light offer to start the next step ("Ruszamy?"). Source per the layered fallback.
Not a full recap of everything said.
_Avoid_: snapshot, dump, recap, dziennik, log.

**STATUS** (`./tmp/STATUS.md`):
The minimal *position pointer* `/zapisz` writes: a generated title, date+time, last step,
next step, and optionally one "open question" line. Points at the work; does not re-describe
it (the work lives in artifacts — PRD, issues). One file per repo, overwritten each save.
_Avoid_: dziennik, log, snapshot (it is not a running record).

**Ciepłe wznowienie** (warm resume):
Returning via `claude -r`, which reloads the transcript into context. `/podsumuj` then
summarizes the live context directly — no file involved.

**Zimny start** (cold start):
A fresh `claude` (no `-r`), empty context — deliberately opened for the next phase
(implementation, `/improve-codebase-architecture`). `/podsumuj` falls back to STATUS, then
to the last session transcript.

**Straż świeżości** (freshness guard):
On a cold start where STATUS exists *but* a session file is newer than STATUS's `mtime`,
`/podsumuj` flags it ("STATUS z X, jest nowsza sesja — wziąć z niej?") instead of trusting
a possibly stale pointer. Guards the case where `/zapisz` was forgotten after later work.

**Następny krok** (next step):
The single concrete action that resumes the work — ideally a command name (`/to-prd`) or a
manual step ("test na telefonie"). The thing `/podsumuj` ends on; the thing `/zapisz` records.
_Avoid_: TODO, plan, zadania.

**Pipeline**:
The ordered workflow stages for a repo, documented as plain prose in `CLAUDE.md` (no special
config block), e.g. `/grill-with-docs → /to-prd → /to-issues → implementacja → test manualny`.
`/podsumuj` reads it to name the next step; absent, the next step is free text.
_Avoid_: workflow (as a synonym), proces.

## Pętla Ralpha

Autonomiczny, jednozadaniowy loop implementacyjny odpalany z terminala (AFK). Jeden komplet
skryptów i promptów wspólny dla wszystkich repo; to, co per-stack (jak testować, kiedy
„done"), żyje w sekcji `## Ralph` w CLAUDE.md repo. Zob. `docs/adr/0002`.

**Pętla Ralpha** (Ralph loop):
An autonomous run that takes exactly ONE task end-to-end — pick → implement → test → commit —
launched from the terminal without supervision (AFK). Two flavours: GitHub-backed (issues) and
local (`issues/*.md`, single fixed model).
_Avoid_: agent, automat, bot.

**Worker**:
The model run that actually implements the selected task (explores, `/tdd`, commits). Distinct
from the **selektor** (only picks the next task) and the **strażnik** (only gates).

**Selektor** (selector):
A cheap-model run that, from the open tasks, picks the single next one — it implements nothing.
GitHub flavour only; the local flavour has no selector.

**Strażnik** (preflight guard):
A fail-closed gate run before any work (in `ralph/preflight.sh`): `grep` for the `## Ralph`
section, then a cheap Haiku check that it actually holds runnable instructions. Missing → the
loop refuses to start and points to `/ralph-konfiguracja`. Never guesses how to test.
_Avoid_: walidacja, check.

**Sekcja `## Ralph`** (repo contract):
The place in a repo's `CLAUDE.md` where it declares its own way of working: the feedback loops
to run before a commit (required) and the done-criteria. The ONLY place stack-specific
differences live; the shared prompts stay stack-agnostic and delegate to it.

**Done-criteria** (kryteria ukończenia):
The condition under which a task counts as finished: whether the automated gate can prove it
(→ the worker closes it) or an un-gateable surface remains (→ `needs-human-test`). Declared
per repo in the `## Ralph` section.
_Avoid_: definition of done / DoD.

**complexity** (złożoność):
A task's intrinsic difficulty — `trivial` / `normal` / `heavy` — independent of any model. The
complexity→model mapping lives only in the loop script, so labels stay stable as models change.
_Avoid_: putting a model name in the label.

**needs-human-test**:
A task already implemented but awaiting a human to verify it (e.g. on a real device). While one
is open, the GitHub loop refuses to start new work. Applied by the worker after implementation,
never at triage.

**AFK / HITL**:
AFK = a task fit to run unsupervised (label `ready-for-agent`); HITL = one needing a human
decision (won't carry the label). The selektor and worker only touch AFK tasks.

## Przykłady rozmów

**Wznawianie — ciepło** (po `claude -r`, tydzień przerwy, długa skompaktowana sesja):
— `/podsumuj`
— Wznawiamy grill modelu danych dla importu wyciągów; ustaliliśmy encje i nazwy, otwarta
  została kwestia walut. Przerwane w trakcie `/grill-with-docs`. Następny krok: dokończyć
  grill (waluty), potem `/to-prd`. Ruszamy?

**Wznawianie — zimno** (świeży `claude`, jest STATUS najświeższy):
— `/podsumuj`
— (z `./tmp/STATUS.md`) Domknięte: grill + PRD + issues #1–5 dla importu wyciągów. Bieżąca
  sesja jest czysta. Następny krok: implementacja, zacznij od #1. Ruszamy?

**Ralph — strażnik blokuje** (terminal, repo bez kontraktu):
— `ralph-once`
— ✋ Brak sekcji „## Ralph" z instrukcjami testowania. Odpal w sesji Claude: `/ralph-konfiguracja`
— (w nowej sesji, Sonnet) `/ralph-konfiguracja` wykrywa stack, dopisuje `## Ralph`, zakłada
  labelki. Potem `ralph-once` rusza: selektor wybiera issue (wg complexity → model), worker
  implementuje, testuje, commituje.
