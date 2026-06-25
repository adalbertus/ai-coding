# Wznawianie pracy — /zapisz & /podsumuj

The domain of two skills that help resume a project's single work thread. `/zapisz` writes
a tiny position pointer to disk at a phase boundary; `/podsumuj` gives a 2–3 sentence
readout of *where the work stands and the next step*, picking its source via a layered
fallback (live context → STATUS → last session transcript). See `docs/adr/0001`.

## Language

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
to the last session transcript. In scope (unlike the earlier design).

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

## Example dialogues

**Ciepło** (po `claude -r`, tydzień przerwy, długa skompaktowana sesja):
— `/podsumuj`
— Wznawiamy grill modelu danych dla importu wyciągów; ustaliliśmy encje i nazwy, otwarta
  została kwestia walut. Przerwane w trakcie `/grill-with-docs`. Następny krok: dokończyć
  grill (waluty), potem `/to-prd`. Ruszamy?

**Zimno** (świeży `claude`, jest STATUS najświeższy):
— `/podsumuj`
— (z `./tmp/STATUS.md`) Domknięte: grill + PRD + issues #1–5 dla importu wyciągów. Bieżąca
  sesja jest czysta. Następny krok: implementacja, zacznij od #1. Ruszamy?
