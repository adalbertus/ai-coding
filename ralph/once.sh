#!/bin/bash

# Ralph loop, GitHub-backed. Two stages so the model can be chosen per issue:
#   1. a cheap selector picks the single next issue number;
#   2. its `complexity:*` label is mapped to a model, and that model implements it.
#
# `ralph-once <n>` runs issue <n> directly, skipping stage 1 (and the selector's token cost).
# A PRD/epic ([PRD] prefix) is refused in that mode — only implementable slices are run.

# Self-locate: this script + its sibling prompts/guard live together (in the shared ralph/
# dir, reached via a symlink on PATH). `realpath` resolves that symlink so prompts are read
# from here, while gh/git below operate on the current repo (cwd).
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# Explicit-issue mode: `ralph-once <n>` runs issue <n> directly, skipping the selector
# (and its token cost). The argument must be a bare issue number.
ISSUE_ARG="${1:-}"
if [ -n "$ISSUE_ARG" ] && ! printf '%s' "$ISSUE_ARG" | grep -qE '^[0-9]+$'; then
  echo "Argument '${ISSUE_ARG}' nie jest numerem issue. Użycie: ralph-once [numer-issue]"
  exit 1
fi

# 0. HARD GATE: never pile up unverified work. If any issue is already implemented and is
#    waiting for a human to verify it (label `needs-human-test`), stop here and list them —
#    do NOT pick up new work until they are verified and closed. Inert in repos that do not
#    use the label (the query comes back empty). What counts as "done" per repo lives in the
#    `## Ralph` section of CLAUDE.md. Skipped in explicit mode: naming an issue is a
#    deliberate override, so the loop-safety gate does not apply.
if [ -z "$ISSUE_ARG" ]; then
  echo "Ralph: sprawdzam zadania czekające na weryfikację (needs-human-test)..."
  pending=$(gh issue list --label needs-human-test --state open \
    --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null)

  if [ -n "$pending" ]; then
    echo "⏳ Zaimplementowane, czekają na weryfikację przez człowieka (needs-human-test)."
    echo "   Sprawdź i zamknij, zanim ruszę po nową pracę:"
    echo "$pending"
    exit 0
  fi
fi

# Strażnik (fail-closed): refuse to run unless this repo declares a usable "## Ralph"
# section in CLAUDE.md. On halt it prints the reason + how to fix and exits non-zero, so
# `|| exit 0` stops the loop cleanly (the message is already on screen).
"$SCRIPT_DIR/preflight.sh" || exit 0

# 1. Recent history, for both the selector and the worker.
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")

# 2. Decide which issue to work on: the one named on the command line, or — in loop mode —
#    whatever the cheap selector picks from the agent-ready queue.
if [ -n "$ISSUE_ARG" ]; then
  # Explicit mode. Verify the issue exists, and refuse PRDs/epics ([PRD] prefix): those are
  # not implementable slices, so running one would feed a whole epic to the worker.
  num="$ISSUE_ARG"
  title=$(gh issue view "$num" --json title --jq .title 2>/dev/null) || true
  if [ -z "$title" ]; then
    echo "Nie znalazłem issue #${num} w tym repo."
    exit 1
  fi
  case "$title" in
    "[PRD]"*)
      echo "Issue #${num} to PRD/epik ([PRD]), nie implementowalny slice."
      echo "Podaj numer child-issue ([ISSUE]) zamiast PRD."
      exit 1
      ;;
  esac
  echo "Tryb bezpośredni: pomijam selektor, odpalam issue #${num}; ustalam etykietę complexity..."
else
  # Loop mode. Pull open, agent-ready (AFK) issues from GitHub as the task list.
  #   The `ready-for-agent` label is the AFK filter (HITL issues won't carry it).
  #   PRDs/epics also carry `ready-for-agent` but are excluded here by title prefix,
  #   so the loop only ever picks implementable tracer-bullet slices.
  echo "Pobieram otwarte zadania (ready-for-agent) z GitHuba..."
  issues=$(gh issue list --label ready-for-agent --state open \
    --json number,title,body \
    --jq '.[] | select(.title | startswith("[PRD]") | not) | "## Issue #\(.number): \(.title)\n\n\(.body)\n"' \
    2>/dev/null)

  if [ -z "$issues" ]; then
    echo "Brak otwartych zadań (ready-for-agent). Nie ma nic do zrobienia."
    exit 0
  fi

  # Stage 1 — cheap selector. Picks ONE issue number (or NO_TASK). Tool-free, so it
  #   reasons over the issue bodies provided above; runs on the cheapest capable model.
  select_prompt=$(cat "$SCRIPT_DIR/select.md")
  echo "Selektor (claude-haiku-4-5) wybiera następne zadanie... (chwilę trwa)"
  selection=$(claude -p --model claude-haiku-4-5-20251001 --effort low \
    "Previous commits: $commits Issues: $issues $select_prompt" 2>/dev/null)
  num=$(printf '%s' "$selection" | grep -Eo 'NO_TASK|[0-9]+' | head -1)

  if [ -z "$num" ] || [ "$num" = "NO_TASK" ]; then
    echo "Selektor nie wskazał żadnego zadania (odpowiedź: '${selection}'). Nie ma nic do zrobienia."
    exit 0
  fi

  echo "Selektor wybrał issue #${num}; ustalam etykietę complexity..."
fi

# 3. Map the selected issue's complexity label to a model AND a reasoning-effort level.
#    Update ONLY this map as the best model/effort per tier changes — the issue labels stay
#    stable (complexity is intrinsic, the model/effort du jour is not). Cheap tiers run at
#    lower effort so trivial work stops burning high-effort thinking tokens; heavy keeps the
#    top effort. An untagged issue is treated as 'normal' (safe default).
complexity=$(gh issue view "$num" --json labels \
  --jq '[.labels[].name | select(startswith("complexity:"))][0] // "complexity:normal" | sub("complexity:"; "")' \
  2>/dev/null)
complexity="${complexity:-normal}"

case "$complexity" in
  heavy)   model="claude-opus-4-8"; effort="high"   ;;
  trivial) model="haiku";  effort="medium" ;;
  *)       model="sonnet"; effort="medium" ;; # 'normal' + anything unexpected
esac

echo "Wybrane issue #${num} (complexity:${complexity}) -> ${model} (effort:${effort})"

# 4. Stage 2 — implement ONLY the selected issue, on the chosen model.
issue=$(gh issue view "$num" --json number,title,body \
  --jq '"## Issue #\(.number): \(.title)\n\n\(.body)\n"' 2>/dev/null)
prompt=$(cat "$SCRIPT_DIR/prompt.md")

echo "Zaczynam implementację issue #${num} na ${model}..."
# `auto` (not `acceptEdits`): acceptEdits auto-approves file edits ONLY, so every Bash call
# outside the user's allowlist — `git commit`, `gh issue close`, the ## Ralph feedback loops —
# still stops for approval, and an AFK loop hangs. Auto mode is Claude Code's default: a
# classifier vets each tool call for risk and prompt injection, approves the low-risk ones and
# denies the rest to the model, never to a human. Not `bypassPermissions`: that skips the
# injection check too, and this loop feeds GitHub issue bodies into an agent running in real
# repos. See docs/adr/0007-*.
claude --permission-mode auto --model "$model" --effort "$effort" \
  "Previous commits: $commits Issue to work (work ONLY this one): $issue $prompt"

# Auto mode denies without prompting, so a run that could not finish (e.g. the commit was
# blocked) now ends quietly. Uncommitted leftovers would poison the NEXT run — say it out loud.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "⚠️  Ralph zostawił niezacommitowane zmiany w drzewie roboczym."
  echo "   Sprawdź (git status) i domknij je, zanim odpalisz kolejny przebieg."
fi
