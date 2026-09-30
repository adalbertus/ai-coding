#!/bin/bash

# Ralph loop, GitHub-backed. Two stages so the model can be chosen per issue:
#   1. a cheap selector picks the single next issue number;
#   2. its `complexity:*` label is mapped to a model, and that model implements it.
#
# `ralph-once <n>` runs issue <n> directly, skipping stage 1 (and the selector's token cost).
# An issue without `ready-for-agent` (HITL) opens an interactive session; without a number only AFK is taken.
# `ralph-once <epic>` ([PRD] prefix) works one of that epic's open sub-issues, picked by the selector.
# In loop mode a started epic (>=1 closed sub-issue) is finished before others are touched (ADR 0012).
# Inside an epic, free AFK sub-issues go first; only when none is left does the same selector pick a
# free HITL one (no `ready-for-agent`) and a HITL session opens (ADR 0013).
#
# Exit codes (the run's result, for callers such as ralph-epic):
#   0  issue closed
#   1  error or refusal (bad args, missing issue, busy lock, guard halt, dirty tree, merge conflict)
#   2  nothing to do (gate `needs-human-test`, epic awaiting acceptance, no/blocked candidates, NO_TASK)
#   3  AFK run left the issue open and it still has `ready-for-agent` (failure, unfinished work)
#   4  AFK run left the issue open without `ready-for-agent` (discovered HITL)
#   5  HITL session ended, issue open without `ready-for-agent` (unresolved)
#   6  HITL session ended, issue open with `ready-for-agent` restored (handed back to AFK)

# Self-locate: this script + its sibling prompts/guard live together (in the shared ralph/
# dir, reached via a symlink on PATH). `realpath` resolves that symlink so prompts are read
# from here, while gh/git below operate on the current repo (cwd).
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

ralph_parse_args ralph-once "$@" || exit "$RALPH_EXIT_ERROR"
ralph_require_runtime "$RALPH_RUNTIME" || exit "$RALPH_EXIT_ERROR"
ISSUE_ARG="$RALPH_ISSUE_ARG"

ralph_acquire_lock "${ISSUE_ARG:-selector}" || exit "$RALPH_EXIT_ERROR"
ralph_trap_release_lock

# Epics whose sub-issues are all closed get `needs-human-test` from here, not from the worker —
# so it works whoever closed the last one. Done before the gate so it sees the fresh label.
[ -z "$ISSUE_ARG" ] && ralph_mark_ready_epics

# 0. HARD GATE: never pile up unverified work. If any issue is already implemented and is
#    waiting for a human to verify it (label `needs-human-test`), stop here and list them —
#    do NOT pick up new work until they are verified and closed. Inert in repos that do not
#    use the label (the query comes back empty). What counts as "done" per repo lives in the
#    `## Ralph` section of the selected runtime's native contract file. Skipped in explicit mode: naming an issue is a
#    deliberate override, so the loop-safety gate does not apply.
if [ -z "$ISSUE_ARG" ]; then
  echo "Ralph: sprawdzam zadania czekające na weryfikację (needs-human-test)..."
  pending=$(gh issue list --label needs-human-test --state open \
    --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null)

  if [ -n "$pending" ]; then
    echo "⏳ Zaimplementowane, czekają na weryfikację przez człowieka (needs-human-test)."
    echo "   Sprawdź i zamknij, zanim ruszę po nową pracę:"
    echo "$pending"
    exit "$RALPH_EXIT_NOTHING"
  fi
fi

# Strażnik (fail-closed): refuse to run unless this repo declares a usable "## Ralph" section
# in the selected runtime's native contract file. On halt it prints the reason + how to fix and
# exits non-zero, so the refusal code stops the loop (the message is already on screen).
"$SCRIPT_DIR/preflight.sh" "$RALPH_RUNTIME" || exit "$RALPH_EXIT_ERROR"

# Optional epic branch (ADR 0012): a `ralph-base-branch: <base>` line in ## Ralph. Absent ->
# trunk, the loop never switches branches. When set, a dirty tree is refused here already, so
# no selector tokens are spent on a run that could not switch branches anyway.
base_branch=$(ralph_contract_section "$(ralph_contract_file "$RALPH_RUNTIME")" | ralph_base_branch) || exit "$RALPH_EXIT_ERROR"
if [ -n "$base_branch" ]; then
  ralph_require_clean_tree || exit "$RALPH_EXIT_ERROR"
fi

# 1. Recent history, for both the selector and the worker.
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")

# 2. Decide which issue to work on: the one named on the command line, or whatever the cheap
#    selector picks from the agent-ready queue (narrowed to an epic, see below).
EPIC_ARG=""
if [ -n "$ISSUE_ARG" ]; then
  # Explicit mode. Verify the issue exists. A [PRD] (epic) is not implementable itself: it
  # switches to epic mode, where the selector chooses among that epic's open sub-issues.
  num="$ISSUE_ARG"
  title=$(gh issue view "$num" --json title --jq .title 2>/dev/null) || true
  if [ -z "$title" ]; then
    echo "Nie znalazłem issue #${num} w tym repo."
    exit "$RALPH_EXIT_ERROR"
  fi
  case "$title" in
    "[PRD]"*) EPIC_ARG="$num" ;;
  esac
  if [ -z "$EPIC_ARG" ]; then
    echo "Tryb bezpośredni: pomijam selektor, odpalam issue #${num}; ustalam etykietę complexity..."
  fi
fi

if [ -z "$ISSUE_ARG" ] || [ -n "$EPIC_ARG" ]; then
  # Loop mode (or epic mode). Pull open, agent-ready (AFK) issues from GitHub as the task list.
  #   The `ready-for-agent` label is the AFK filter (HITL issues won't carry it).
  #   PRDs/epics also carry `ready-for-agent` but are excluded here by title prefix,
  #   so the loop only ever picks implementable tracer-bullet slices.
  echo "Pobieram otwarte zadania (ready-for-agent) z GitHuba..."

  # Epic structure: one sub_issues call per open epic -> {number, started, open:[...]}.
  epics="[]"
  for e in $(gh issue list --state open --limit 200 --json number,title \
      --jq '.[] | select(.title | startswith("[PRD]")) | .number' 2>/dev/null); do
    subs=$(gh api --paginate "repos/{owner}/{repo}/issues/${e}/sub_issues" 2>/dev/null | jq -s -c 'add // []')
    [ -n "$subs" ] || subs="[]"
    epics=$(jq -c --argjson e "$e" --argjson subs "$subs" \
      '. + [{number: $e, started: any($subs[]; .state == "closed"), open: [$subs[] | select(.state == "open") | .number]}]' \
      <<<"$epics")
  done

  if [ -n "$EPIC_ARG" ]; then
    open_count=$(jq -r --argjson e "$EPIC_ARG" '[.[] | select(.number == $e) | .open[]] | length' <<<"$epics")
    if [ "${open_count:-0}" = 0 ]; then
      ralph_mark_epic_if_ready "$EPIC_ARG" || true
      echo "Epic #${EPIC_ARG} nie ma otwartych sub-issues — czeka na odbiór albo jest skończony. Nie uruchamiam workera."
      exit "$RALPH_EXIT_NOTHING"
    fi
  fi

  # Epic mode also needs the HITL sub-issues (no `ready-for-agent`), so fetch labels too and
  # narrow to AFK here for the loop; ralph_epic_stage does the AFK-then-HITL choice for an epic.
  issues_json=$(gh issue list --state open --limit 200 \
    --json number,title,body,labels 2>/dev/null | jq -c 'map(select(.title | startswith("[PRD]") | not))')
  if [ -z "$EPIC_ARG" ]; then
    issues_json=$(jq -c 'map(select(any(.labels[]?; .name == "ready-for-agent")))' <<<"${issues_json:-[]}")
  fi
  issues_json=$(ralph_annotate_parents "$epics" <<<"${issues_json:-[]}")
  if [ -n "$EPIC_ARG" ]; then
    issues_json=$(ralph_epic_issues "$EPIC_ARG" <<<"$issues_json")
  else
    issues_json=$(ralph_filter_started_epic "$epics" <<<"$issues_json")
  fi
  # Blockers are settled here, deterministically (all open issues, not just ready-for-agent
  # ones): the selector only ever sees free issues and decides order alone.
  open_numbers=$(gh issue list --state open --limit 500 --json number --jq '[.[].number]' 2>/dev/null)
  candidates=$(jq -r 'length' <<<"$issues_json")
  issues_json=$(ralph_filter_unblocked "${open_numbers:-[]}" <<<"$issues_json")
  if [ "$candidates" -gt 0 ] && [ "$(jq -r 'length' <<<"$issues_json")" = 0 ]; then
    echo "Wszystkie kandydaty są zablokowane (otwarty bloker w sekcji „Blocked by”). Nie wywołuję selektora."
    exit "$RALPH_EXIT_NOTHING"
  fi
  if [ -n "$EPIC_ARG" ]; then
    issues_json=$(ralph_epic_stage <<<"$issues_json")
    if ! jq -e 'any(.[]; any(.labels[]?; .name == "ready-for-agent"))' <<<"$issues_json" >/dev/null 2>&1 \
        && [ "$(jq -r 'length' <<<"$issues_json")" -gt 0 ]; then
      echo "Epic #${EPIC_ARG}: nie ma wolnych issues AFK — wybieram sesję HITL."
    fi
  fi
  issues=$(jq -r '.[] | "## Issue #\(.number): \(.title)\n\n\(.body)\n"' <<<"$issues_json")

  if [ -z "$issues" ]; then
    echo "Brak otwartych zadań (ready-for-agent). Nie ma nic do zrobienia."
    exit "$RALPH_EXIT_NOTHING"
  fi

  # Stage 1 — cheap selector. Picks ONE issue number (or NO_TASK). Tool-free, so it
  #   reasons over the issue bodies provided above; runs through the selected runtime's
  #   cheap/read-only adapter.
  select_prompt=$(cat "$SCRIPT_DIR/select.md")
  echo "Selektor ($(ralph_selector_model_label "$RALPH_RUNTIME")) wybiera następne zadanie... (chwilę trwa)"
  selection=$(ralph_run_model_capture "$RALPH_RUNTIME" selector \
    "Previous commits: $commits Issues: $issues $select_prompt" 2>/dev/null)
  num=$(printf '%s' "$selection" | grep -Eo 'NO_TASK|[0-9]+' | head -1)

  if [ -z "$num" ] || [ "$num" = "NO_TASK" ]; then
    echo "Selektor nie wskazał żadnego zadania (odpowiedź: '${selection}'). Nie ma nic do zrobienia."
    exit "$RALPH_EXIT_NOTHING"
  fi

  echo "Selektor wybrał issue #${num}; ustalam etykietę complexity..."
fi

# 3. Map the selected issue's complexity label to a model AND a reasoning-effort level.
#    Update ONLY this map as the best model/effort per tier changes — the issue labels stay
#    stable (complexity is intrinsic, the model/effort du jour is not). Cheap tiers run at
#    lower effort so trivial work stops burning high-effort thinking tokens; heavy keeps the
#    top effort. An untagged issue is treated as 'normal' (safe default).
labels=$(gh issue view "$num" --json labels --jq '.labels[].name' 2>/dev/null)
complexity=$(printf '%s\n' "$labels" | sed -n 's/^complexity://p' | head -1)
complexity="${complexity:-normal}"

ralph_model_for_complexity "$RALPH_RUNTIME" "$complexity"
model="$RALPH_MODEL"
effort="$RALPH_EFFORT"

echo "Wybrane issue #${num} (complexity:${complexity}) -> $(ralph_model_display "$RALPH_RUNTIME" "$model" "$effort")"

# 4. Epic branch: put the repo on epic/<parent> (merging the base in) or on the base for an
#    issue without a parent. The run ends on that branch, ready for local acceptance.
if [ -n "$base_branch" ]; then
  # Loop/epic mode already knows the parent from the annotated list; explicit mode (or a
  # selector answer outside that list) asks GitHub. A failed lookup stops the run rather than
  # silently putting sub-issue work on the base.
  if jq -e --argjson n "$num" 'any(.[]; .number == $n)' <<<"${issues_json:-[]}" >/dev/null 2>&1; then
    parent=$(jq -r --argjson n "$num" 'first(.[] | select(.number == $n) | .parent) // empty' <<<"$issues_json")
  elif ! parent=$(ralph_issue_parent "$num"); then
    echo "Nie udało się ustalić epicu issue #${num} (gh api); nie przełączam gałęzi, nie uruchamiam workera."
    exit "$RALPH_EXIT_ERROR"
  fi
  ralph_prepare_branch "$base_branch" "$parent" || exit "$RALPH_EXIT_ERROR"
  # The worker should see the history of the branch it will commit to.
  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
fi

# 5. Stage 2 — implement ONLY the selected issue, on the chosen model.
issue=$(gh issue view "$num" --json number,title,body \
  --jq '"## Issue #\(.number): \(.title)\n\n\(.body)\n"' 2>/dev/null)
# The mode follows from the issue: ready-for-agent -> unattended, otherwise an interactive HITL
# session with its own prompt. Loop mode only ever selects ready-for-agent issues.
mode=$(ralph_worker_mode <<<"$labels")
if [ "$mode" = "hitl" ]; then
  echo "Issue #${num} nie ma ready-for-agent — to HITL: otwieram sesję interaktywną z człowiekiem."
  prompt=$(ralph_render_prompt "$RALPH_RUNTIME" "$SCRIPT_DIR/prompt-hitl.md")
else
  prompt=$(ralph_render_prompt "$RALPH_RUNTIME" "$SCRIPT_DIR/prompt.md")
fi

echo "Zaczynam implementację issue #${num} przez runtime ${RALPH_RUNTIME} na $(ralph_model_display "$RALPH_RUNTIME" "$model" "$effort")..."
# Claude runs unattended via `claude -p` (stream-json; see ralph_run_claude_worker) and ends on
# its own once the issue is closed out. It uses `auto` (not `acceptEdits`): acceptEdits auto-approves file edits ONLY, so every
# Bash call outside the user's allowlist — `git commit`, `gh issue close`, the ## Ralph feedback
# loops — still stops for approval, and an AFK loop hangs. Auto mode is Claude Code's default:
# a classifier vets each tool call for risk and prompt injection. Codex runs unattended too, via
# `codex exec --json --approve-for-me` (see ralph_run_codex_worker). HITL issues (no ready-for-agent)
# get the interactive CLI of either runtime instead.
ralph_run_worker "$RALPH_RUNTIME" "$model" "$effort" \
  "Previous commits: $commits Issue to work (work ONLY this one): $issue $prompt" "issue-${num}" "$mode"

# The worker may have closed the last sub-issue of an epic: mark it for acceptance.
ralph_mark_ready_epics

# Auto mode denies without prompting, so a run that could not finish (e.g. the commit was
# blocked) now ends quietly. Uncommitted leftovers would poison the NEXT run — say it out loud.
ralph_warn_dirty_tree

# The result of the run is the state of the issue afterwards, not the worker's own exit status.
state=$(gh issue view "$num" --json state --jq '.state | ascii_downcase' 2>/dev/null)
has_label=$(gh issue view "$num" --json labels --jq 'any(.labels[]; .name == "ready-for-agent")' 2>/dev/null)
exit "$(ralph_run_outcome "$mode" "$state" "$has_label")"
