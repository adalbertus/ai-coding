#!/bin/bash

# ralph-epic [claude|codex] [nr]: carries one epic from start to acceptance by repeating
# `ralph-once <epic>` (one sub-issue per run, fresh context) — ADR 0013. It decides only from
# once.sh's exit-code contract (see the header of once.sh); the decision is the pure function
# ralph_epic_decision in lib.sh.
#
# Without a number it takes the epic the selector would (started first, then lowest number) and
# honours the `needs-human-test` gate; with a number the gate is skipped, like ralph-once.
#
# Test seams: RALPH_ONCE_CMD replaces once.sh (called with: [runtime] <epic>; it may write the
# issue number it worked on to $RALPH_ISSUE_FILE).
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

ralph_parse_args ralph-epic "$@" || exit "$RALPH_EXIT_ERROR"
runtime="$RALPH_RUNTIME"
epic="$RALPH_ISSUE_ARG"
once_cmd="${RALPH_ONCE_CMD:-$SCRIPT_DIR/once.sh}"

# Print a stop message and notify.
finish() {
  local code="$1" title="$2" body="$3"
  echo
  echo "$body"
  ralph_notify "$title" "$(printf '%s' "$body" | head -1)"
  exit "$code"
}

if [ -z "$epic" ]; then
  # Gate: an epic awaiting acceptance blocks new work (skipped when a number is given).
  pending=$(gh issue list --label needs-human-test --state open \
    --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null)
  if [ -n "$pending" ]; then
    finish "$RALPH_EXIT_NOTHING" "Ralph: czeka odbiór" \
"⏳ Coś czeka na weryfikację przez człowieka (needs-human-test). Sprawdź i zamknij, zanim ruszę po nową pracę:
$pending"
  fi
fi

epics=$(ralph_epics_json)
if [ -z "$epic" ]; then
  epic=$(ralph_pick_epic <<<"$epics")
  if [ -z "$epic" ]; then
    finish "$RALPH_EXIT_NOTHING" "Ralph: brak epicu" "Brak epicu z otwartymi sub-issues. Nie ma nic do zrobienia."
  fi
fi

open_count=$(jq -r --argjson e "$epic" '[.[] | select(.number == $e) | .open[]] | length' <<<"$epics")
limit=$(ralph_epic_iteration_limit "${open_count:-0}")
echo "ralph-epic: epic #${epic}, otwartych sub-issues: ${open_count:-0}, limit iteracji: ${limit} (runtime ${runtime})."

# Open sub-issues of the epic as "  #n: title (HITL)" lines.
open_list() {
  gh api --paginate "repos/{owner}/{repo}/issues/${epic}/sub_issues" 2>/dev/null | jq -s -r 'add // []
    | .[] | select(.state == "open")
    | "  #\(.number): \(.title)" + (if any(.labels[]?; .name == "ready-for-agent") then "" else " (HITL)" end)'
}

issue_file=$(mktemp)
trap 'rm -f "$issue_file"' EXIT
runs=0
while :; do
  runs=$((runs + 1))
  : > "$issue_file"
  echo
  echo "── ralph-epic: iteracja ${runs}/${limit} ──"
  RALPH_ISSUE_FILE="$issue_file" RALPH_NOTIFY_HITL=1 "$once_cmd" "$runtime" "$epic"
  code=$?
  issue=$(head -1 "$issue_file")
  ready=$(gh issue view "$epic" --json labels --jq 'any(.labels[]; .name == "needs-human-test")' 2>/dev/null)
  [ "$ready" = true ] || ready=false

  case "$(ralph_epic_decision "$code" "$runs" "$limit" "$ready")" in
    continue) ;;
    stop-ready)
      finish "$RALPH_EXIT_DONE" "Ralph: epic #${epic} gotowy" "Epic #${epic} gotowy do odbioru." ;;
    stop-afk-failed)
      finish "$RALPH_EXIT_AFK_FAILED" "Ralph: porażka AFK" \
"Issue #${issue:-?} (epic #${epic}) nie zostało domknięte i nadal ma ready-for-agent — porażka, bez pomijania. Zobacz komentarz workera w tym issue (gh issue view ${issue:-?} --comments) i log w .git/ralph-logs/." ;;
    stop-hitl)
      finish "$RALPH_EXIT_HITL_OPEN" "Ralph: HITL nierozwiązane" \
"Sesja HITL dla issue #${issue:-?} (epic #${epic}) skończyła się bez rozwiązania. Rozstrzygnij je (domknij albo przywróć ready-for-agent) i uruchom ralph-epic ponownie." ;;
    stop-nothing)
      finish "$RALPH_EXIT_NOTHING" "Ralph: nic do zrobienia" \
"Epic #${epic} ma otwarte sub-issues, ale żadne nie jest wolne — każde ma otwarty bloker w „Blocked by”:
$(open_list)" ;;
    stop-error)
      finish "$RALPH_EXIT_ERROR" "Ralph: błąd" \
"once.sh zakończył się błędem lub odmową (kod ${code}) przy epicu #${epic}${issue:+, issue #${issue}}. Przyczyna jest w komunikatach powyżej." ;;
    stop-limit)
      finish "$RALPH_EXIT_NOTHING" "Ralph: limit iteracji" \
"Limit iteracji (${limit}) wyczerpany, a epic #${epic} nie jest gotowy do odbioru. Otwarte sub-issues:
$(open_list)" ;;
  esac
done
