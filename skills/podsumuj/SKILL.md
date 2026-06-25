---
name: podsumuj
description: Gives a 2–3 sentence readout of "where I am + next step", picking its source: live context → ./tmp/STATUS.md → last session transcript. Invoked only explicitly via /podsumuj.
disable-model-invocation: true
---

# /podsumuj — where I stopped + next step

Give **2–3 sentences in Polish**: where the work stands and what the next step is. Not a full
recap — orient on **position**. End with a light offer to start ("Ruszamy?"). See `CONTEXT.md`.

## Source selection (in order — first match wins)

### 1. Warm — live context present
You have an earlier conversation from this session in context (beyond the bare `/podsumuj`
invocation) → **summarize it**. Don't touch any files.

### 2. Cold — no context, STATUS exists
Empty context but `./tmp/STATUS.md` exists → summarize from it.

**Freshness guard** — before trusting STATUS, check whether a newer session exists:
```bash
SID="$CLAUDE_CODE_SESSION_ID"
DIR=$(dirname "$(find ~/.claude/projects -name "$SID.jsonl" 2>/dev/null | head -1)")
PREV=$(ls -t "$DIR"/*.jsonl 2>/dev/null | grep -v "/$SID.jsonl" | head -1)
[ -n "$PREV" ] && find "$PREV" -newer ./tmp/STATUS.md 2>/dev/null
```
If the last line printed anything (a session newer than STATUS's `mtime` exists) → **don't
guess**: say in Polish „STATUS jest z <Zapisano>, ale jest nowsza sesja — wziąć z niej zamiast
ze STATUS-u?" and wait for the decision. Otherwise summarize from STATUS.

### 3. Cold — no context and no STATUS
First **ask for consent** before going to disk, in Polish: „Brak STATUS-u i czysty kontekst —
zajrzeć do ostatniej sesji?". On consent, find it and read **only the tail** (sessions can be
>1 MB — don't load the whole file):
```bash
SID="$CLAUDE_CODE_SESSION_ID"
DIR=$(dirname "$(find ~/.claude/projects -name "$SID.jsonl" 2>/dev/null | head -1)")
PREV=$(ls -t "$DIR"/*.jsonl 2>/dev/null | grep -v "/$SID.jsonl" | head -1)
[ -n "$PREV" ] && tail -c 60000 "$PREV"
```
Skip the noise (tool results), pick out the last exchanges, and summarize.

If there is **no prior session at all** (`PREV` empty) → say plainly, in Polish: „Nie ma czego
streszczać — brak STATUS-u i brak wcześniejszej sesji w tym repo." Don't make things up.

## Output

- Polish, 2–3 sentences, **position + next step** (not a recap).
- Prefer naming the next step as a **command** — if the repo pipeline (prose in `CLAUDE.md`)
  names one; otherwise free text.
- When cold, **tag the source**: „(ze STATUS-u / z poprzedniej sesji; bieżąca sesja jest czysta)".
- End with a light „Ruszamy?".
