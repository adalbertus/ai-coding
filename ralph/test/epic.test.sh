#!/usr/bin/env bash
# Tests for ralph/epic.sh (ralph-epic). once.sh is replaced by a dummy (RALPH_ONCE_CMD) that plays
# back a sequence of exit codes; gh and osascript are fakes on PATH — no network, no runtime.
#
# Run: bash ralph/test/epic.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
EPIC="$SCRIPT_DIR/../epic.sh"
pass=0; fail=0
LAST_OUT=""; LAST_RC=0

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT
# No run log by default: the tests run inside this repo and must not write to its .git. The run
# log has its own test below, in a throwaway repo. Plain output, so substrings match.
export RALPH_RUN_LOG=off RALPH_COLOR=0
# The worker and the bramka run these tests under ralph-epic, which exports its own launch command.
unset RALPH_LAUNCH_CMD_OUTER RALPH_ISSUE_FILE RALPH_NOTIFY_HITL RALPH_TERM_FDS
mkdir -p "$FAKE/bin"

cat > "$FAKE/bin/gh" <<'GH'
#!/usr/bin/env bash
# Fake gh: state lives in $FAKE_DIR.
args="$*"
case "$args" in
  *"--label needs-human-test"*) cat "$FAKE_DIR/pending" 2>/dev/null ;;
  "issue list --state open"*) cat "$FAKE_DIR/epics" 2>/dev/null ;;
  "api --paginate repos/{owner}/{repo}/issues/"*"/sub_issues")
    n="${args#api --paginate repos/\{owner\}/\{repo\}/issues/}"; n="${n%/sub_issues}"
    cat "$FAKE_DIR/subs-$n.json" 2>/dev/null || cat "$FAKE_DIR/subs.json" 2>/dev/null ;;
  "api --paginate repos/{owner}/{repo}/issues/13/dependencies/blocked_by") echo '[{"number":12,"state":"open"}]' ;;
  "api --paginate repos/{owner}/{repo}/issues/"*"/dependencies/blocked_by") echo '[]' ;;
  "issue view"*"--json labels"*) [ -f "$FAKE_DIR/ready" ] && echo true || echo false ;;
esac
GH
cat > "$FAKE/bin/osascript" <<'OSA'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DIR/notifications"
OSA
# Dummy once.sh: each call pops the first line of $FAKE_DIR/seq: "<code> [issue] [ready]".
cat > "$FAKE/once" <<'ONCE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/once-args"
read -r code issue ready < <(head -1 "$FAKE_DIR/seq"; )
sed -i.bak 1d "$FAKE_DIR/seq"
[ -n "$issue" ] && [ -n "${RALPH_ISSUE_FILE:-}" ] && echo "$issue" > "$RALPH_ISSUE_FILE"
[ "$ready" = ready ] && touch "$FAKE_DIR/ready"
[ "${RALPH_NOTIFY_HITL:-}" = 1 ] && echo hitl-flag >> "$FAKE_DIR/once-args"
echo "runlog:${RALPH_RUN_LOG:-}" >> "$FAKE_DIR/once-args"
exit "${code:-1}"
ONCE
chmod +x "$FAKE/bin/gh" "$FAKE/bin/osascript" "$FAKE/once"

# Two epics: #10 (started, 2 open sub-issues) and #20 (not started). Sub-issues of every epic are
# answered with the same array — enough for open_list and epic detection.
SUBS='[{"number":11,"title":"Zrobione","state":"closed","labels":[]},{"number":12,"title":"Afk","state":"open","labels":[{"name":"ready-for-agent"}]},{"number":13,"title":"Decyzja","state":"open","labels":[]}]'

# run <seq lines, \n-separated> [args...]; env: PENDING (gate listing)
run() {
  local seq="$1"; shift
  rm -f "$FAKE"/{ready,notifications,once-args} "$FAKE"/subs-*.json
  printf '%s\n' "$seq" > "$FAKE/seq"
  printf '%s' "${PENDING:-}" > "$FAKE/pending"
  printf '10\n20\n' > "$FAKE/epics"
  printf '%s' "$SUBS" > "$FAKE/subs.json"
  LAST_OUT=$(FAKE_DIR="$FAKE" PATH="$FAKE/bin:$PATH" RALPH_ONCE_CMD="$FAKE/once" bash "$EPIC" "$@" 2>&1)
  LAST_RC=$?
}

expect() {
  local desc="$1" want_rc="$2" want_sub="${3:-}"
  if [ "$LAST_RC" = "$want_rc" ] && { [ -z "$want_sub" ] || grep -qF -- "$want_sub" <<<"$LAST_OUT"; }; then
    echo "✓ $desc"; pass=$((pass+1))
  else
    echo "✗ $desc (rc=$LAST_RC, want $want_rc; substring: ${want_sub:-—})"
    printf '%s\n' "$LAST_OUT" | sed 's/^/   /'
    fail=$((fail+1))
  fi
}
runs() { grep -c '^claude\|^codex' "$FAKE/once-args" 2>/dev/null || echo 0; }
expect_eq() {
  if [ "$2" = "$3" ]; then echo "✓ $1"; pass=$((pass+1)); else echo "✗ $1"; printf '   got : %s\n   want: %s\n' "$2" "$3"; fail=$((fail+1)); fi
}

# Closed, closed, then the epic goes to acceptance.
run $'0 12\n0 13 ready' 10
expect "closed, closed+ready -> stop with 'gotowy do odbioru', rc 0" 0 "Epic #10 gotowy do odbioru"
expect_eq "  two runs" "$(runs)" "2"
expect_eq "  runtime and epic passed to once" "$(head -1 "$FAKE/once-args")" "claude 10"
expect_eq "  notification sent at the stop" "$(grep -c 'display notification' "$FAKE/notifications")" "1"

run $'0 12\n0 13 ready' codex 10
expect "codex is rejected with a message" 1 "Codex nie uruchamia już Ralpha"
expect_eq "  and once is never called" "$(runs)" "0"

run $'0 12\n0 13 ready' 10 --force-model=opus
expect_eq "--force-model is passed on to every run" "$(grep -c -- '--force-model=opus' "$FAKE/once-args")" "2"
expect "  and named in the start line" 0 "model wymuszony: opus/high"

# HITL solved (0) and handed back (6) both go on.
run $'6 13\n0 13 ready' 10
expect "HITL handed back -> next run, then ready" 0 "gotowy do odbioru"
expect_eq "  two runs" "$(runs)" "2"
expect_eq "  HITL notification flag is set for once" "$(grep -c hitl-flag "$FAKE/once-args")" "2"

run $'4 12\n0 12 ready' 10
expect "discovered HITL (4) -> next run" 0 "gotowy do odbioru"

# Stops.
run $'0 12\n3 13' 10
expect "AFK failure -> stop naming the issue and the comment" 3 "Issue #13"
expect "  points at the worker's comment" 3 "komentarz"
expect_eq "  no run after the failure" "$(runs)" "2"

run $'5 13' 10
expect "HITL unresolved -> stop naming the issue" 5 "Sesja HITL dla issue #13"

run $'2' 10
expect "nothing to do -> stop listing open sub-issues" 2 "#13: Decyzja (HITL)"
expect "  lists AFK ones too" 2 "#12: Afk"
expect "  names the open blocker of a blocked one" 2 "#13: Decyzja (HITL) ← #12"
expect_eq "  a free one gets no arrow" "$(grep -c '#12: Afk ←' <<<"$LAST_OUT")" "0"

run $'0 12\n8 13' 10
expect "usage limit too far to wait (8) -> stop with its own code, naming the issue and the restart" 8 "Po resecie wklej: ralph-epic 10"
expect "  names the issue" 8 "(issue #13)"
expect_eq "  the command to paste is ralph-epic, not ralph-once" "$(grep -c 'ralph-once' <<<"$LAST_OUT")" "0"
expect_eq "  no run after it" "$(runs)" "2"
expect_eq "  notified" "$(grep -c 'limit użycia' "$FAKE/notifications")" "1"

run $'1 12' 10
expect "error -> stop with the cause" 1 "kod 1"

run $'2 12 ready' 10
expect "ready epic beats 'nothing to do' (once refused because it awaits acceptance)" 0 "gotowy do odbioru"

# Limit: 2 open sub-issues -> at most 4 runs.
run $'0 12\n0 12\n0 12\n0 12\n0 12' 10
expect "limit -> stop after 4 runs" 2 "Limit iteracji (4)"
expect_eq "  exactly 4 runs" "$(runs)" "4"

# Weryfikacja epica (ADR 0018): an epic with every sub-issue closed and no needs-human-test is work.
# once.sh's exit 9 = "do odbioru", 7 = a "Poprawka" opened (go on). Epic #10 below: all closed.
ALL_CLOSED='[{"number":11,"title":"A","state":"closed","labels":[]},{"number":12,"title":"B","state":"closed","labels":[]}]'
ONE_OPEN='[{"number":11,"title":"A","state":"closed","labels":[]},{"number":12,"title":"B","state":"open","labels":[{"name":"ready-for-agent"}]}]'
epic_run() { # <seq> <epics file content> <subs file for #10 ('' = default)> [args...]
  local seq="$1" epics="$2" subs10="$3"; shift 3
  rm -f "$FAKE"/{ready,notifications,once-args} "$FAKE"/subs-*.json
  printf '%s\n' "$seq" > "$FAKE/seq"; printf '%b' "$epics" > "$FAKE/epics"; printf '%s' "${PENDING:-}" > "$FAKE/pending"
  printf '%s' "$SUBS" > "$FAKE/subs.json"
  [ -z "$subs10" ] || printf '%s' "$subs10" > "$FAKE/subs-10.json"
  [ -z "${SUBS7:-}" ] || printf '%s' "$SUBS7" > "$FAKE/subs-7.json"
  LAST_OUT=$(FAKE_DIR="$FAKE" PATH="$FAKE/bin:$PATH" RALPH_ONCE_CMD="$FAKE/once" bash "$EPIC" "$@" 2>&1)
  LAST_RC=$?
}

epic_run $'9' '10\n' "$ALL_CLOSED" 10
expect "all sub-issues closed, no label -> the weryfikacja runs instead of 'nothing to do'; code 9 -> ready" 0 "Epic #10 gotowy do odbioru"
expect_eq "  exactly one run, of the epic" "$(runs)|$(head -1 "$FAKE/once-args")" "1|claude 10"
expect "  the acceptance command ends the output" 0 'claude "/odbior 10"'
expect_eq "  last line of the output is that command" "$(tail -1 <<<"$LAST_OUT" | grep -c 'claude "/odbior 10"')" "1"
expect "  the start line gives the room for a weryfikacja" 0 "limit iteracji: 3"

epic_run $'7\n9' '10\n' "$ALL_CLOSED" 10
expect "round 1 red (7: Poprawka opened) -> the loop goes on, then the next weryfikacja hands over (9)" 0 "gotowy do odbioru"
expect_eq "  two runs" "$(runs)" "2"

epic_run $'0 12\n9' '10\n' "$ONE_OPEN" 10
expect "closing the last sub-issue in iteration N -> iteration N+1 is the weryfikacja, no human in between" 0 "gotowy do odbioru"
expect_eq "  two runs, both of epic #10" "$(runs)|$(grep -c '^claude 10$' "$FAKE/once-args")" "2|2"

epic_run $'0 12\n7' '10\n' "$ONE_OPEN" 10
expect "the weryfikacja counts as an iteration: limit reached on it -> stop as at the limit" 2 "Limit iteracji (2)"
expect_eq "  the epic is not labelled by ralph-epic" "$([ -f "$FAKE/ready" ] && echo yes || echo no)" "no"

SUBS7="$ALL_CLOSED" epic_run $'9' '7\n10\n' '' 
expect "no number: a started epic waiting for weryfikacja goes before another with open sub-issues" 0 "epic #7"
expect_eq "  takes #7" "$(head -1 "$FAKE/once-args")" "claude 7"

epic_run $'9' '10\n' "$ONE_OPEN"
expect_eq "no number: an epic with open sub-issues is taken as before" "$(head -1 "$FAKE/once-args")" "claude 10"

PENDING=$'  #99: [PRD] Czeka' SUBS7="$ALL_CLOSED" epic_run $'9' '7\n' '' 
expect "no number: an epic awaiting acceptance elsewhere still refuses to start, even with another to verify" 2 "#99: [PRD] Czeka"
expect_eq "  no run" "$(runs)" "0"
SUBS7=""

epic_run $'2 - ready' '10\n' "$ALL_CLOSED" 10
expect "an epic already labelled (once.sh: nothing to do, label present) -> ready, no second weryfikacja" 0 "gotowy do odbioru"
expect_eq "  one run only" "$(runs)" "1"

# Without a number: the gate, then the epic pick (started #10 over #20).
PENDING=$'  #99: [PRD] Czeka' run $'0' 
expect "no number, awaiting epic -> refuses and names it" 2 "#99: [PRD] Czeka"
expect_eq "  no run at all" "$(runs)" "0"

PENDING=$'  #99: [PRD] Czeka' run $'0 12 ready' 10
expect "with a number the gate is skipped" 0 "gotowy do odbioru"

run $'0 12 ready'
expect "no number -> picks an epic" 0 "epic #"
expect_eq "  takes #10 (first with open sub-issues)" "$(head -1 "$FAKE/once-args")" "claude 10"

: > "$FAKE/epics"
LAST_OUT=$(FAKE_DIR="$FAKE" PATH="$FAKE/bin:$PATH" RALPH_ONCE_CMD="$FAKE/once" bash "$EPIC" 2>&1); LAST_RC=$?
expect "no epics at all -> nothing to do" 2 "Brak epicu"

# Without osascript the loop works the same (no notification, no error).
NOOSA=$(mktemp -d)
for t in bash jq sed head cat mktemp rm realpath dirname grep touch printf tr; do ln -s "$(command -v $t)" "$NOOSA/$t" 2>/dev/null; done
cp "$FAKE/bin/gh" "$NOOSA/gh"
rm -f "$FAKE"/{ready,notifications,once-args}
printf '0 12 ready\n' > "$FAKE/seq"; printf '10\n' > "$FAKE/epics"; printf '%s' "$SUBS" > "$FAKE/subs.json"
LAST_OUT=$(FAKE_DIR="$FAKE" PATH="$NOOSA" RALPH_ONCE_CMD="$FAKE/once" bash "$EPIC" 10 2>&1); LAST_RC=$?
expect "no osascript -> same behaviour, no notifications" 0 "gotowy do odbioru"
expect_eq "  nothing notified" "$(ls "$FAKE/notifications" 2>/dev/null | wc -l | tr -d ' ')" "0"
rm -rf "$NOOSA"

# Run log: the whole output lands in <git dir>/ralph-logs/<stamp>-epic-<n>.log, colour stripped,
# framed by start/end lines with the exit code; the screen keeps the colour; the rc is kept.
LOGREPO=$(mktemp -d)
git -C "$LOGREPO" init -q
rm -f "$FAKE"/{ready,notifications,once-args}
printf '0 12\n0 13 ready\n' > "$FAKE/seq"; printf '10\n' > "$FAKE/epics"; printf '%s' "$SUBS" > "$FAKE/subs.json"
LAST_OUT=$(cd "$LOGREPO" && env -u RALPH_RUN_LOG FAKE_DIR="$FAKE" PATH="$FAKE/bin:$PATH" RALPH_ONCE_CMD="$FAKE/once" \
  RALPH_COLOR=1 bash "$EPIC" 10 2>&1); LAST_RC=$?
logs=$(ls "$LOGREPO/.git/ralph-logs" 2>/dev/null)
expect "run log: rc of the loop is kept" 0 "Log przebiegu:"
expect_eq "  one log named after the epic" "$(sed -E 's/[0-9]{8}-[0-9]{6}/STAMP/' <<<"$logs")" "STAMP-epic-10.log"
log="$LOGREPO/.git/ralph-logs/$logs"
expect_eq "  log holds the loop's output" "$(grep -c 'gotowy do odbioru' "$log" 2>/dev/null)" "1"
expect_eq "  log has no colour codes" "$(grep -c $'\x1b' "$log" 2>/dev/null)" "0"
expect_eq "  log ends with the exit code" "$(tail -1 "$log" | sed 's/.*kod wyjścia: //')" "0"
case "$LAST_OUT" in *$'\x1b[32m'*) r=yes ;; *) r=no ;; esac
expect_eq "  screen keeps colour (green ready)" "$r" "yes"
expect_eq "  once.sh inherits the log (so it opens none of its own)" \
  "$(grep -c "^runlog:.git/ralph-logs/$logs\$" "$FAKE/once-args")" "2"
rm -rf "$LOGREPO"

# once.sh itself against a fake gh and claude, in a throwaway repo: `ralph-once <epic>` verifies an
# epic whose sub-issues are all closed; the loop never labels an epic on its own any more.
ONCE_SH="$SCRIPT_DIR/../once.sh"
OFAKE=$(mktemp -d); mkdir -p "$OFAKE/bin"
cat > "$OFAKE/bin/claude" <<'CL'
#!/usr/bin/env bash
echo "claude $*" >> "$ONCE_CALLS"
CL
cat > "$OFAKE/bin/gh" <<'GH'
#!/usr/bin/env bash
# Fake gh for once.sh: epic #50; sub-issues, label and comments come from $OFAKE_DIR; every write lands in $ONCE_CALLS.
args="$*"
case "$args" in
  "issue view 50 --json title"*) echo "[PRD] Epic" ;;
  "issue view 50 --json labels"*) cat "$OFAKE_DIR/label" ;;
  "issue view 50 --json body"*) printf '## Jak odebrać\n\n1. Zrób krok\n' ;;
  "issue list --label needs-human-test"*) ;;
  "issue list --state open"*) echo 50 ;;
  "api --paginate repos/{owner}/{repo}/issues/50/sub_issues") cat "$OFAKE_DIR/subs.json" ;;
  "api --paginate repos/{owner}/{repo}/issues/50/comments") cat "$OFAKE_DIR/comments.json" ;;
  "api --paginate repos/{owner}/{repo}/issues?state=open"*) echo '[]' ;;
  "issue comment 50 --body "*) echo "comment-epic" >> "$ONCE_CALLS" ;;
  "issue edit 50 --add-label needs-human-test") echo "label-epic" >> "$ONCE_CALLS" ;;
  "issue create "*) echo "create: $args" >> "$ONCE_CALLS" ;;
esac
GH
chmod +x "$OFAKE/bin/claude" "$OFAKE/bin/gh"
# once_case <subs json> <label true|false> <comments json> <gate command> [ralph-once args...]
once_case() {
  local subs="$1" label="$2" comments="$3" gate="$4" repo; shift 4
  repo=$(mktemp -d); git -C "$repo" init -q
  printf '# T\n\n## Ralph\n\nBramka zielona = gotowe.\n\nralph-gate: %s\n' "$gate" > "$repo/CLAUDE.md"
  printf '%s' "$subs" > "$OFAKE/subs.json"; printf '%s' "$label" > "$OFAKE/label"; printf '%s' "$comments" > "$OFAKE/comments.json"
  : > "$OFAKE/calls"
  LAST_OUT=$(cd "$repo" && ONCE_CALLS="$OFAKE/calls" OFAKE_DIR="$OFAKE" PATH="$OFAKE/bin:$PATH" RALPH_GATE_CMD="echo READY" \
    bash "$ONCE_SH" "$@" 2>&1)
  LAST_RC=$?
  rm -rf "$repo"
}
calls() { paste -sd, "$OFAKE/calls"; }
GATE_Y='echo gate >> "$ONCE_CALLS"'
GATE_N='echo gate >> "$ONCE_CALLS"; exit 1'

once_case "$ALL_CLOSED" false '[]' "$GATE_Y" 50
expect "ralph-once <epic>, all sub-issues closed, gate green -> exit 9 (do odbioru)" 9 'claude "/odbior 50"'
expect_eq "  gate, round marker, label, acceptance list" "$(calls)" "gate,comment-epic,label-epic,comment-epic"

once_case "$ALL_CLOSED" false '[]' "$GATE_N" 50
expect "ralph-once <epic>, gate red in round 1 -> exit 7, a Poprawka under the epic" 7 "Poprawka"
expect_eq "  gate, round marker, create — and no label" "$(calls | sed 's/create: .*/create/')" "gate,comment-epic,create"

once_case "$ALL_CLOSED" false '[{"body":"<!-- ralph-weryfikacja: runda -->\nrunda 1"}]' "$GATE_N" 50
expect "ralph-once <epic>, gate red in round 2 -> exit 9, labelled, no new Poprawka" 9 "oznaczony needs-human-test"
expect_eq "  gate, round marker, label, list" "$(calls)" "gate,comment-epic,label-epic,comment-epic"

once_case "$ALL_CLOSED" true '[]' "$GATE_Y" 50
expect "ralph-once <epic> already labelled needs-human-test -> exit 2, not verified again" 2 "czeka na odbiór"
expect_eq "  nothing run, nothing written" "$(calls)" ""

once_case '[]' false '[]' "$GATE_Y" 50
expect "ralph-once <epic> without sub-issues -> exit 2, neither verified nor labelled" 2 "nie jest zaplanowany"
expect_eq "  nothing run, nothing written" "$(calls)" ""

once_case "$ONE_OPEN" false '[]' "$GATE_Y" 50
expect_eq "ralph-once <epic> with an open sub-issue works as before: no weryfikacja, no label" "$(calls)" ""

once_case "$ALL_CLOSED" false '[]' "$GATE_Y"
expect_eq "ralph-once without a number no longer labels an epic whose sub-issues are all closed" "$(calls)" ""

once_case "$ALL_CLOSED" false '[]' "" 50
expect "ralph-once <epic> without a gate line -> refused (the strażnik), nothing verified" 1 "ralph-gate"
rm -rf "$OFAKE"

# Argument errors.
run $'0' foo
expect "bad argument -> error" 1 "Użycie: ralph-epic"

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
