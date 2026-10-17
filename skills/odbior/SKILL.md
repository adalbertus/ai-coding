---
name: odbior
description: Publish an epic's acceptance as a claude.ai artifact with persistent state. Given an epic number (`/odbior <nr>`), reads the newest acceptance list from the epic's comments, creates (once per epic) or reuses an artifact with the `db` and `assets` capabilities, writes the list's steps into the artifact's database and gives the user the link. The page (template in this skill) shows each step with OK / needs-fix buttons, a comment and a screenshot paste, plus a general-notes field; state survives between browser sessions, per round and step. Re-running for the same round neither creates a new artifact nor wipes state; a new round adds a section above the older ones. Invoked explicitly via /odbior <nr>; the loop prints this command when it hands an epic over.
model: opus
disable-model-invocation: true
---

# /odbior <nr> — publish the epic's acceptance as an artifact

Argument: the epic number. Without it, stop and ask for it. Claude only (artifacts do not exist
in Codex). Work in the epic's worktree (the loop prints `cd <worktree> && claude "/odbior <nr>"`).

This skill only **publishes** the acceptance page and hands over the link. Reading the results,
fixing, opening "Poprawka" sub-issues and closing the epic happen on the next `/odbior <nr>`
(not in this skill's scope here).

## Markers (HTML comments in the epic's comments)

- `<!-- ralph-lista-odbioru -->` — the acceptance list comment; the newest one is the current round.
- `<!-- ralph-odbior-artefakt: <url> -->` — the epic's artifact URL, written by this skill.

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
4. **Find or create the artifact.** Look for the artifact marker in the epic's comments.
   - **Marker found** → reuse that artifact. Do not create another one.
   - **No marker** → create an artifact from `template.html` (next to this file), with the `db`
     and `assets` capabilities. Then post the marker:
     `gh issue comment <nr> --body "<!-- ralph-odbior-artefakt: <url> -->\nArtefakt odbioru epicu #<nr>: <url>"`.
5. **Write the round into the artifact's database** (data model below).
   - If a round with this round id already exists, **do not touch it** and do not touch any
     `state:*` / `notes:*` key. Re-running only reprints the link.
   - Otherwise **prepend** the new round to `rounds` (newest first); never rewrite older rounds.
6. **Reply** with the link and one sentence: after going through it (it can be done in pieces, over
   days), type `/odbior <nr>` again.

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
