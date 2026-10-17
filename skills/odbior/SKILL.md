---
name: odbior
description: Publish an epic's acceptance as a claude.ai artifact with persistent state. Given an epic number (`/odbior <nr>`), reads the newest acceptance list from the epic's comments, creates (once per epic) or reuses an artifact with the `db` and `assets` capabilities, writes the list's steps into the artifact's database and gives the user the link. The page (template in this skill) shows each step with OK / needs-fix buttons, a comment and a screenshot paste, plus a general-notes field; state survives between browser sessions, per round and step. Re-running for the same round neither creates a new artifact nor wipes state; a new round adds a section above the older ones. On the next run for a round that already has verdicts it reads them and acts: small fixes in the session (gate before every commit), bigger matters as "Poprawka" sub-issues plus a round marker, all OK and no notes closes the epic per the repo's `## Ralph`, "do it differently" becomes a proposal for a separate grill; an incomplete acceptance is reported and nothing is closed. Invoked explicitly via /odbior <nr>; the loop prints this command when it hands an epic over.
model: opus
disable-model-invocation: true
---

# /odbior <nr> — publish the epic's acceptance as an artifact

Argument: the epic number. Without it, stop and ask for it. Claude only (artifacts do not exist
in Codex). Work in the epic's worktree (the loop prints `cd <worktree> && claude "/odbior <nr>"`).

One command, two modes, chosen in step 4 by what the round's artifact holds: **publish** (no
verdicts yet: steps 5–7) or **act** (verdicts exist: the "Act on the verdicts" section).

## Markers (HTML comments in the epic's comments)

- `<!-- ralph-lista-odbioru -->` — the acceptance list comment; the newest one is the current round.
- `<!-- ralph-odbior-artefakt: <url> -->` — the epic's artifact URL, written by this skill.
- `<!-- ralph-odbior: runda -->` — the acceptance-round marker, written by this skill when it opens
  "Poprawka" sub-issues (act mode). The loop's round counter recognises exactly this string, so
  write it verbatim.

## Steps

1. **Read the epic's comments:** `gh issue view <nr> --json comments --jq '.comments'` (id, body).
   Take the newest comment containing the list marker. None → say the epic has no acceptance list
   (verification has not handed it over) and stop.
2. **Round id** = the id of that list comment. It identifies the round for good: the same list is
   the same round, a new verification comment is a new round.
3. **Parse the list** into the steps to show. Sections of the list, in order: `Nierozwiązane`
   (unresolved findings; each bullet is a step), `Kroki (## Jak odebrać)` (each numbered/bulleted
   step), then the report sections (`not-proven`, `before-after`, proposals — each bullet is a
   step; a proposal is a step to *decide*, say so in its text). Skip the `Odbiór` section and the
   `claude --resume` line. For each step write: `id` (`s1`, `s2`, …), `title` (short), `do` (what
   to do, concrete, in Polish), `expect` (what the user should see), `kind`
   (`unresolved` | `step` | `not-proven` | `before-after` | `proposal`).
4. **Choose the mode.** Look for the artifact marker in the epic's comments. If there is one,
   read the artifact's `db`: if round `<round id>` is in `rounds` and at least one of its steps
   has a `state:<roundId>:<stepId>` with a non-null `status`, go to **Act on the verdicts**.
   Otherwise (no artifact, round not written, or nothing marked yet) continue with 5–7.
5. **Find or create the artifact.** Look for the artifact marker in the epic's comments.
   - **Marker found** → reuse that artifact. Do not create another one.
   - **No marker** → create an artifact from `template.html` (next to this file), with the `db`
     and `assets` capabilities. Then post the marker:
     `gh issue comment <nr> --body "<!-- ralph-odbior-artefakt: <url> -->\nArtefakt odbioru epicu #<nr>: <url>"`.
6. **Write the round into the artifact's database** (data model below).
   - If a round with this round id already exists, **do not touch it** and do not touch any
     `state:*` / `notes:*` key. Re-running only reprints the link.
   - Otherwise **prepend** the new round to `rounds` (newest first); never rewrite older rounds.
7. **Reply** with the link and one sentence: after going through it (it can be done in pieces, over
   days), type `/odbior <nr>` again.

## Act on the verdicts

Read from the artifact's `db`: for the current round every step's `state:<roundId>:<stepId>`
(`status`, `comment`, `shots`) and `notes:<roundId>`. Fetch each screenshot (`shots` URLs) and look
at it — it is part of the verdict. Work in the epic's worktree (branch `epic/<nr>`), following the
repo's `## Ralph` section in `CLAUDE.md` / `AGENTS.md` (gate command `ralph-gate:`, commit
conventions, closing procedure).

**Incomplete acceptance first.** Steps of the round whose `status` is null (or missing) = not
decided. Then do **nothing** that changes the epic (no commit, no sub-issue, no marker, no label
change, no close). Say in Polish which steps are left (id + title) and that the user can continue
in the artifact, then run `/odbior <nr>` again. Verdicts already given are kept in the db.

**Complete acceptance.** Classify each `fix` step and each general note (a note that asks for a
change counts as one) into one of three kinds, then run the paths that apply:

1. **Small matter** (a quick, local fix, no design judgement) → fix it in this session:
   edit, run the `ralph-gate:` command from `## Ralph`, and commit **only when it is green**
   (commit conventions from `## Ralph`). **Red gate → no commit**: revert that edit
   (`git checkout -- <files>` / `git restore`) and treat the matter as a larger one (path 2).
   The gate runs before every single commit, never once for a batch.
2. **Larger matter** (more than a quick fix, or a small fix that went red) → open a sub-issue of
   the epic: `gh issue create --parent <nr> --title "[ISSUE] Poprawka: <what>" --label ready-for-agent --label complexity:<tier> --body "<body>"`.
   Body: what is wrong, the user's comment and screenshot links, how to check it. Tier from the
   `to-issues-ralph` rubric (`trivial` mechanical only, `normal` default, `heavy` only when a green
   gate is not enough); for `heavy` add a `## Przypadki do przetestowania` section (one bullet per
   case, `situation → expected outcome`, behaviour not file names). Create the label if missing
   (`gh label create complexity:<tier> ... 2>/dev/null`).
   After all such sub-issues are created: post the round marker
   `gh issue comment <nr> --body "<!-- ralph-odbior: runda -->\nOdbiór: założono sub-issues „Poprawka”, epic wraca do weryfikacji."`
   and `gh issue edit <nr> --remove-label needs-human-test`. The loop then does the fixes and
   verifies the epic again. Post the marker once per run, only if at least one sub-issue was opened.
3. **"Let's do it differently"** (the user questions the approach, not a detail) → no fix and no
   sub-issue. Propose a separate grill (`grilling`) on that point and say what it would settle.

**All OK and no notes** (every step `ok`, `notes:<roundId>` empty, no `fix`) → run the epic-closing
procedure from the repo's `## Ralph` section ("Zamknięcie epicu"), as if the user had said
"zamykaj". Close only on this condition. If fixes were just committed in this run (path 1 only,
no sub-issue), do not close: the user has not yet seen the result — say so and let them confirm
with `/odbior <nr>` or "zamykaj".

Finish with a short Polish summary: what was fixed (commits), which sub-issues were opened, what
awaits a grill, whether the epic was closed.

## Artifact data model

All keys live in the artifact's `db`:

- `epic` → `{ "number": <nr>, "title": "<epic title>" }`
- `rounds` → array, newest first: `{ "id": "<comment id>", "label": "Runda <k>", "steps": [ { "id", "title", "do", "expect", "kind" } ] }`
  (`k` = count of rounds already in `rounds` + 1)
- `state:<roundId>:<stepId>` → `{ "status": "ok" | "fix" | null, "comment": "<text>", "shots": ["<asset url>", …] }` — written by the page only
- `notes:<roundId>` → general-notes text — written by the page only

The template is the page: it renders whatever `rounds` holds, so step content never goes into the
HTML. If the artifact runtime's `db` / `assets` calls differ from the thin adapter at the top of
`template.html` (`store` and `uploadAsset`), fix the adapter there — nowhere else.
