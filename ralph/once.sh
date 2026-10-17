#!/bin/bash

# Ralph loop, GitHub-backed. Two stages so the model can be chosen per issue:
#   1. a cheap selector picks the single next issue number;
#   2. its `complexity:*` label is mapped to a model, and that model implements it.
#
# `ralph-once <n>` runs issue <n> directly, skipping stage 1 (and the selector's token cost).
# An issue without `ready-for-agent` (HITL) opens an interactive session; without a number only AFK is taken.
# `ralph-once <epic>` ([PRD] prefix) works one of that epic's open sub-issues: the lowest-numbered free one.
# In loop mode a started epic (>=1 closed sub-issue) is finished before others are touched (ADR 0012).
# Inside an epic, free AFK sub-issues go first; only when none is left is a free HITL one (no
# `ready-for-agent`) taken and a HITL session opens (ADR 0013). The model selector runs only outside
# an epic, and only with more than one candidate: blockers and order are the script's job.
#
# Exit codes (the run's result, for callers such as ralph-epic):
#   0  issue closed
#   1  error or refusal (bad args, missing issue, busy lock, guard halt, dirty tree, merge conflict)
#   2  nothing to do (gate `needs-human-test`, epic awaiting acceptance, no/blocked candidates, NO_TASK)
#   3  AFK run left the issue open and it still has `ready-for-agent` (failure, unfinished work)
#   4  AFK run left the issue open without `ready-for-agent` (discovered HITL)
#   5  HITL session ended, issue open without `ready-for-agent` (unresolved)
#   6  HITL session ended, issue open with `ready-for-agent` restored (handed back to AFK)
#   7  przegląd heavy or the bramka failed once: the issue is reopened with its notes for one fix
#      (ADR 0016, ADR 0018); a second failure of either gives 3 (AFK failed, a human is needed)
#   8  a usage limit stopped the run and its reset is too far to wait for; the ślad is left so the
#      next run resumes the same session (ADR 0017)
#
# Wznowienie po limicie (ADR 0017): a Claude worker or przegląd heavy cut off by a usage limit
# waits for the reset (up to 6 h) and resumes its session. A later run finds the ślad and resumes
# before anything else — the gate, the strażnik and the clean-tree check do not apply to it.
# A resumed worker that closed the issue goes through the bramka like any run; a resumed przegląd
# heavy does not run it again (the bramka was green before the przegląd began).

# Self-locate: this script + its sibling prompts/guard live together (in the shared ralph/
# dir, reached via a symlink on PATH). `realpath` resolves that symlink so prompts are read
# from here, while gh/git below operate on the current repo (cwd).
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

ralph_parse_args ralph-once "$@" || exit "$RALPH_EXIT_ERROR"
ralph_start_run_log "once${RALPH_ISSUE_ARG:+-$RALPH_ISSUE_ARG}" "$@"
ralph_require_claude || exit "$RALPH_EXIT_ERROR"
ISSUE_ARG="$RALPH_ISSUE_ARG"

ralph_acquire_lock "${ISSUE_ARG:-selector}" || exit "$RALPH_EXIT_ERROR"
ralph_trap_release_lock

# A run stopped by a usage limit it could not wait out, or whose runtime would not take the
# session up: the ślad stays and nothing below may count the issue as done.
exit_on_limit_stop() {
  case "${RALPH_LIMIT_STOP:-}" in
    limit) exit "$RALPH_EXIT_USAGE_LIMIT" ;;
    resume-failed) exit "$RALPH_EXIT_ERROR" ;;
  esac
}

# Everything after the worker, shared by a fresh run and one resumed from the ślad. Reads the
# globals num, mode, complexity, pre_head and issue. Never returns.
after_worker() {
  local cost
  exit_on_limit_stop
  if [ -n "$RALPH_LAST_LOG" ]; then
    cost=$(ralph_run_cost "$RALPH_LAST_LOG")
    [ -n "$cost" ] && ralph_say dim "Koszt workera: $cost"
  fi

  # The bramka (ADR 0018) and, after a green one, the przegląd heavy (ADR 0016): both before the
  # epic can be marked for acceptance or anything counts the issue as done.
  ralph_verify_closed "$num" "$mode" "$complexity" "$pre_head" "$issue"
  finish_run
}

# The run's verdict. Never returns.
finish_run() {
  local state has_label outcome
  exit_on_limit_stop

  # The worker may have closed the last sub-issue of an epic: mark it for acceptance. Not when the
  # bramka could not even run (no gate line): that issue is not verified.
  [ "${RALPH_GATE_EXIT:-}" = "$RALPH_EXIT_ERROR" ] || ralph_mark_ready_epics

  # Auto mode denies without prompting, so a run that could not finish (e.g. the commit was
  # blocked) now ends quietly. Uncommitted leftovers would poison the NEXT run — say it out loud.
  ralph_warn_dirty_tree

  # The result of the run is the state of the issue afterwards, not the worker's own exit status.
  state=$(gh issue view "$num" --json state --jq '.state | ascii_downcase' 2>/dev/null)
  has_label=$(gh issue view "$num" --json labels --jq 'any(.labels[]; .name == "ready-for-agent")' 2>/dev/null)
  outcome=$(ralph_run_outcome "$mode" "$state" "$has_label")
  [ -n "${RALPH_REVIEW_EXIT:-}" ] && outcome="$RALPH_REVIEW_EXIT"
  if [ -n "${RALPH_GATE_EXIT:-}" ]; then
    # The bramka already said what happened on screen; the generic line would blame a przegląd.
    outcome="$RALPH_GATE_EXIT"
  else
    ralph_outcome_message "$outcome" "$num"
  fi
  exit "$outcome"
}

issue_text() {
  gh issue view "$1" --json number,title,body \
    --jq '"## Issue #\(.number): \(.title)\n\n\(.body)\n"' 2>/dev/null
}

# Wznowienie po limicie: a valid ślad is resumed before anything else. Its dirty tree is the
# interrupted worker's work, on the branch it was working on.
if ralph_limit_trace_applies "$ISSUE_ARG"; then
  num=$(ralph_limit_trace_get issue)
  phase=$(ralph_limit_trace_get phase)
  session=$(ralph_limit_trace_get session)
  pre_head=$(ralph_limit_trace_get pre_head)
  complexity=$(ralph_limit_trace_get complexity)
  mode=afk
  RALPH_LIMIT_CONTEXT=$(printf 'issue=%s\npre_head=%s\ncomplexity=%s' "$num" "$pre_head" "$complexity")
  [ -n "${RALPH_ISSUE_FILE:-}" ] && printf '%s\n' "$num" > "$RALPH_ISSUE_FILE"
  ralph_say warn "Wznowienie po limicie: issue #${num} — $([ "$phase" = review ] && echo "przegląd heavy" || echo worker) przerwany przez limit użycia (sesja $session)."
  issue=$(issue_text "$num")
  if [ "$phase" = review ]; then
    ralph_heavy_review "$num" "$pre_head" "$issue" "$session"
    finish_run
  fi
  RALPH_LAST_LOG=""
  ralph_run_worker_through_limit "$(ralph_limit_trace_get model)" "$(ralph_limit_trace_get effort)" \
    "" "$(ralph_limit_trace_get label)" afk worker "$session"
  after_worker
fi

# Epics whose sub-issues are all closed get `needs-human-test` from here, not from the worker —
# so it works whoever closed the last one. Done before the gate so it sees the fresh label.
[ -z "$ISSUE_ARG" ] && ralph_mark_ready_epics

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
    ralph_say warn "⏳ Zaimplementowane, czekają na weryfikację przez człowieka (needs-human-test).
   Sprawdź i zamknij, zanim ruszę po nową pracę:
$pending"
    exit "$RALPH_EXIT_NOTHING"
  fi
fi

# Strażnik (fail-closed): refuse to run unless this repo declares a usable "## Ralph" section
# in CLAUDE.md. On halt it prints the reason + how to fix and
# exits non-zero, so the refusal code stops the loop (the message is already on screen).
"$SCRIPT_DIR/preflight.sh" claude
guard_rc=$?
[ "$guard_rc" = "$RALPH_EXIT_USAGE_LIMIT" ] && exit "$RALPH_EXIT_USAGE_LIMIT"
[ "$guard_rc" = 0 ] || exit "$RALPH_EXIT_ERROR"

# Optional epic branch (ADR 0012): a `ralph-base-branch: <base>` line in ## Ralph. Absent ->
# trunk, the loop never switches branches. When set, a dirty tree is refused here already, so
# no selector tokens are spent on a run that could not switch branches anyway.
base_branch=$(ralph_contract_section "$(ralph_contract_file)" | ralph_base_branch) || exit "$RALPH_EXIT_ERROR"
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
    ralph_say err "Nie znalazłem issue #${num} w tym repo."
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

  epics=$(ralph_epics_json)

  if [ -n "$EPIC_ARG" ]; then
    open_count=$(jq -r --argjson e "$EPIC_ARG" '[.[] | select(.number == $e) | .open[]] | length' <<<"$epics")
    if [ "${open_count:-0}" = 0 ]; then
      ralph_mark_epic_if_ready "$EPIC_ARG" || true
      ralph_say warn "Epic #${EPIC_ARG} nie ma otwartych sub-issues — czeka na odbiór albo jest skończony. Nie uruchamiam workera."
      exit "$RALPH_EXIT_NOTHING"
    fi
  fi

  # Epic mode also needs the HITL sub-issues (no `ready-for-agent`), so fetch labels too and
  # narrow to AFK here for the loop; ralph_epic_stage does the AFK-then-HITL choice for an epic.
  # Fail-closed: without an answer from GitHub there are no blockers to trust, so no run.
  if ! issues_json=$(ralph_open_issues); then
    ralph_say err "Nie udało się pobrać otwartych zadań z GitHuba (gh api) — bez blokerów nie wybieram zadania."
    exit "$RALPH_EXIT_ERROR"
  fi
  issues_json=$(jq -c 'map(select(.title | startswith("[PRD]") | not))' <<<"$issues_json")
  if [ -z "$EPIC_ARG" ]; then
    issues_json=$(jq -c 'map(select(any(.labels[]?; .name == "ready-for-agent")))' <<<"${issues_json:-[]}")
  fi
  issues_json=$(ralph_annotate_parents "$epics" <<<"${issues_json:-[]}")
  if [ -n "$EPIC_ARG" ]; then
    issues_json=$(ralph_epic_issues "$EPIC_ARG" <<<"$issues_json")
  else
    issues_json=$(ralph_filter_started_epic "$epics" <<<"$issues_json")
  fi
  # Blockers are settled here, deterministically, from GitHub's native "blocked by" relation:
  # the selector only ever sees free issues and decides order alone.
  candidates_json="$issues_json"
  issues_json=$(ralph_filter_unblocked <<<"$issues_json")
  if [ "$(jq -r 'length' <<<"$candidates_json")" -gt 0 ] && [ "$(jq -r 'length' <<<"$issues_json")" = 0 ]; then
    ralph_say warn "Wszystkie kandydaty są zablokowane (otwarty bloker w relacji „blocked by”). Nie wywołuję selektora.
$(ralph_blocked_report <<<"$candidates_json")"
    exit "$RALPH_EXIT_NOTHING"
  fi
  if [ -n "$EPIC_ARG" ]; then
    issues_json=$(ralph_epic_stage <<<"$issues_json")
    if ! jq -e 'any(.[]; any(.labels[]?; .name == "ready-for-agent"))' <<<"$issues_json" >/dev/null 2>&1 \
        && [ "$(jq -r 'length' <<<"$issues_json")" -gt 0 ]; then
      ralph_say warn "Epic #${EPIC_ARG}: nie ma wolnych issues AFK — wybieram sesję HITL."
    fi
  fi
  issues=$(jq -r '.[] | "## Issue #\(.number): \(.title)\n\n\(.body)\n"' <<<"$issues_json")

  if [ -z "$issues" ]; then
    ralph_say warn "Brak otwartych zadań (ready-for-agent). Nie ma nic do zrobienia."
    exit "$RALPH_EXIT_NOTHING"
  fi

  if [ -n "$EPIC_ARG" ]; then
    # Inside an epic the order is deterministic: a model adds nothing the numbering does not,
    # and a spurious NO_TASK would stop an unattended ralph-epic.
    num=$(ralph_pick_first <<<"$issues_json")
    echo "Epic #${EPIC_ARG}: biorę pierwsze wolne sub-issue #${num} (bez selektora); ustalam etykietę complexity..."
  elif [ "$(jq -r 'length' <<<"$issues_json")" = 1 ]; then
    num=$(ralph_pick_first <<<"$issues_json")
    echo "Jedyne wolne issue: #${num} (bez selektora); ustalam etykietę complexity..."
  else
    # Stage 1 — cheap selector. Picks ONE issue number (or NO_TASK) among free issues. Tool-free,
    #   so it reasons over the issue bodies provided above; runs through the cheap
    #   Haiku call.
    select_prompt=$(cat "$SCRIPT_DIR/select.md")
    echo "Selektor ($(ralph_selector_model_label)) wybiera następne zadanie... (chwilę trwa)"
    selection=$(ralph_run_model_capture selector \
      "Previous commits: $commits Issues: $issues $select_prompt")
    [ "$?" = "$RALPH_EXIT_USAGE_LIMIT" ] && exit "$RALPH_EXIT_USAGE_LIMIT"
    num=$(printf '%s' "$selection" | grep -Eo 'NO_TASK|[0-9]+' | head -1)

    if [ -z "$num" ] || [ "$num" = "NO_TASK" ]; then
      ralph_say warn "Selektor nie wskazał żadnego zadania (odpowiedź: '${selection}'). Nie ma nic do zrobienia."
      exit "$RALPH_EXIT_NOTHING"
    fi

    echo "Selektor wybrał issue #${num}; ustalam etykietę complexity..."
  fi
fi

# 3. Map the selected issue's complexity label to a model AND a reasoning-effort level.
#    Update ONLY this map as the best model/effort per tier changes — the issue labels stay
#    stable (complexity is intrinsic, the model/effort du jour is not). Cheap tiers run at
#    lower effort so trivial work stops burning high-effort thinking tokens; heavy keeps the
#    top effort. An untagged issue is treated as 'normal' (safe default).
labels=$(gh issue view "$num" --json labels --jq '.labels[].name' 2>/dev/null)
complexity=$(printf '%s\n' "$labels" | sed -n 's/^complexity://p' | head -1)
complexity="${complexity:-normal}"

ralph_model_for_complexity "$complexity"
model="$RALPH_MODEL"
effort="$RALPH_EFFORT"

[ -n "${RALPH_ISSUE_FILE:-}" ] && printf '%s\n' "$num" > "$RALPH_ISSUE_FILE"
echo "Wybrane issue #${num} (complexity:${complexity}) -> $(ralph_model_display "$model" "$effort")${RALPH_FORCE_MODEL:+, wymuszone --force-model}"

# 4. Epic branch: put the repo on epic/<parent> (merging the base in) or on the base for an
#    issue without a parent. The run ends on that branch, ready for local acceptance.
if [ -n "$base_branch" ]; then
  # Loop/epic mode already knows the parent from the annotated list; explicit mode (or a
  # selector answer outside that list) asks GitHub. A failed lookup stops the run rather than
  # silently putting sub-issue work on the base.
  if jq -e --argjson n "$num" 'any(.[]; .number == $n)' <<<"${issues_json:-[]}" >/dev/null 2>&1; then
    parent=$(jq -r --argjson n "$num" 'first(.[] | select(.number == $n) | .parent) // empty' <<<"$issues_json")
  elif ! parent=$(ralph_issue_parent "$num"); then
    ralph_say err "Nie udało się ustalić epicu issue #${num} (gh api); nie przełączam gałęzi, nie uruchamiam workera."
    exit "$RALPH_EXIT_ERROR"
  fi
  ralph_prepare_branch "$base_branch" "$parent" || exit "$RALPH_EXIT_ERROR"
  # The worker should see the history of the branch it will commit to.
  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
fi

# 5. Stage 2 — implement ONLY the selected issue, on the chosen model.
issue=$(issue_text "$num")
# A przegląd heavy that sent the issue back left its notes in a comment; the body does not
# carry them, so hand the latest ones to the worker explicitly.
review_notes=$(ralph_review_notes "$num")
if [ -n "$review_notes" ]; then
  issue="$issue
### Notes from the failed przegląd heavy (fix these)

$review_notes
"
fi
# The mode follows from the issue: ready-for-agent -> unattended, otherwise an interactive HITL
# session with its own prompt. Loop mode only ever selects ready-for-agent issues.
mode=$(ralph_worker_mode <<<"$labels")
if [ "$mode" = "hitl" ]; then
  ralph_say warn "Issue #${num} nie ma ready-for-agent — to HITL: otwieram sesję interaktywną z człowiekiem."
  [ -n "${RALPH_NOTIFY_HITL:-}" ] && ralph_notify "Ralph: sesja HITL" "Issue #${num} czeka na Ciebie."
  prompt=$(ralph_render_prompt "$SCRIPT_DIR/prompt-hitl.md")
else
  prompt=$(ralph_render_prompt "$SCRIPT_DIR/prompt.md")
fi

echo "Zaczynam implementację issue #${num} przez Claude na $(ralph_model_display "$model" "$effort")..."
# Claude runs unattended via `claude -p` (stream-json; see ralph_run_claude_worker) and ends on
# its own once the issue is closed out. It uses `auto` (not `acceptEdits`): acceptEdits auto-approves file edits ONLY, so every
# Bash call outside the user's allowlist — `git commit`, `gh issue close`, the ## Ralph feedback
# loops — still stops for approval, and an AFK loop hangs. Auto mode is Claude Code's default:
# a classifier vets each tool call for risk and prompt injection. HITL issues (no ready-for-agent)
# get the interactive CLI instead.
pre_head=$(git rev-parse HEAD 2>/dev/null)
RALPH_LAST_LOG=""
# What a ślad needs beyond the session, should a usage limit cut this run off (ADR 0017).
RALPH_LIMIT_CONTEXT=$(printf 'issue=%s\npre_head=%s\ncomplexity=%s' "$num" "$pre_head" "$complexity")
ralph_run_worker_through_limit "$model" "$effort" \
  "Previous commits: $commits Issue to work (work ONLY this one): $issue $prompt" "issue-${num}" "$mode" worker
after_worker
