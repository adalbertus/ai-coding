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
mkdir -p "$FAKE/bin"

cat > "$FAKE/bin/gh" <<'GH'
#!/usr/bin/env bash
# Fake gh: state lives in $FAKE_DIR.
args="$*"
case "$args" in
  *"--label needs-human-test"*) cat "$FAKE_DIR/pending" 2>/dev/null ;;
  "issue list --state open"*) cat "$FAKE_DIR/epics" 2>/dev/null ;;
  "api --paginate repos/{owner}/{repo}/issues/"*"/sub_issues") cat "$FAKE_DIR/subs.json" 2>/dev/null ;;
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
  rm -f "$FAKE"/{ready,notifications,once-args}
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
expect_eq "codex runtime is passed on" "$(head -1 "$FAKE/once-args")" "codex 10"

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

run $'1 12' 10
expect "error -> stop with the cause" 1 "kod 1"

run $'2 12 ready' 10
expect "ready epic beats 'nothing to do' (once refused because it awaits acceptance)" 0 "gotowy do odbioru"

# Limit: 2 open sub-issues -> at most 4 runs.
run $'0 12\n0 12\n0 12\n0 12\n0 12' 10
expect "limit -> stop after 4 runs" 2 "Limit iteracji (4)"
expect_eq "  exactly 4 runs" "$(runs)" "4"

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

# Argument errors.
run $'0' foo
expect "bad argument -> error" 1 "Użycie: ralph-epic"

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
