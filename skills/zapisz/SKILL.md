---
name: zapisz
description: Writes a minimal work-position pointer to ./tmp/STATUS.md at a phase boundary (where I stopped + next step). Invoked only explicitly via /zapisz.
disable-model-invocation: true
---

# /zapisz — position pointer for the next session

At a calm phase boundary, record **where the work stopped and what the next step is** to
`./tmp/STATUS.md`. This is not a recap or a log — the work lives in artifacts (PRD, issues);
the file only **points at the position**. See `CONTEXT.md`.

## Steps

1. From **live context**, determine:
   - **Last step** — what was closed off, or where work was interrupted mid-flight.
   - **Next step** — one concrete action. If the repo's pipeline (prose in `CLAUDE.md`)
     names a command (`/to-prd`, `/to-issues`…), use it; otherwise free text.
   - **Open question** — *only if* interrupted mid-thought; one sentence. Omit when the step
     closed cleanly.
   - **Title** — short, generated from the session, recognizable at a glance.

2. Get the current date and time:
   ```bash
   date '+%Y-%m-%d %H:%M'
   ```

3. Overwrite the **single** `./tmp/STATUS.md` (one thread per repo — don't pile up files):
   ```bash
   mkdir -p ./tmp
   ```
   Use exactly this format; include the `Otwarta kwestia` line **only** when it applies.
   The field labels are Polish on purpose — this is the on-disk contract `/podsumuj` reads:
   ```markdown
   # <title generated from the session>
   Zapisano: <date time>

   **Ostatni etap:** <what was closed off, or where interrupted>
   **Następny krok:** <command or action>
   **Otwarta kwestia:** <one sentence — only if interrupted mid-flight>
   ```

4. Confirm to the user in one short Polish sentence: zapisałem STATUS „<title>",
   następny krok: <…>.
