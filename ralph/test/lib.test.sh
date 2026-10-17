#!/usr/bin/env bash
# Tests for ralph/lib.sh. Pure shell helpers only; no model, network, or GitHub calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
# Plain, unclipped output whatever terminal the tests run in; colour and clipping are tested
# explicitly.
export RALPH_COLOR=0 RALPH_COLS=0
# A worker or przegląd running these tests under ralph-epic inherits the run's variables; without
# this, the tests would write test issue numbers into the real run's issue file, expect fds 3/4
# that are not open, render reports under the reviewer's title, and name the epic's launch command.
unset RALPH_ISSUE_FILE RALPH_NOTIFY_HITL RALPH_TERM_FDS RALPH_REPORT_TITLE RALPH_LAUNCH_CMD_OUTER
. "$SCRIPT_DIR/../lib.sh"

pass=0; fail=0

expect_eq() {
  local desc="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "✓ $desc"
    pass=$((pass+1))
  else
    echo "✗ $desc"
    printf '   got : %s\n' "$got"
    printf '   want: %s\n' "$want"
    fail=$((fail+1))
  fi
}

expect_ok() {
  local desc="$1"
  shift
  if "$@"; then
    echo "✓ $desc"
    pass=$((pass+1))
  else
    echo "✗ $desc"
    fail=$((fail+1))
  fi
}

expect_fail() {
  local desc="$1"
  shift
  if "$@"; then
    echo "✗ $desc"
    fail=$((fail+1))
  else
    echo "✓ $desc"
    pass=$((pass+1))
  fi
}

expect_ok "ralph-once 224 parses as default Claude explicit issue" ralph_parse_args ralph-once 224
expect_eq "default runtime is claude" "$RALPH_RUNTIME" "claude"
expect_eq "issue parsed" "$RALPH_ISSUE_ARG" "224"

ralph_parse_args ralph-once 17; expect_eq "launch command: ralph-once 17" "$RALPH_LAUNCH_CMD" "ralph-once 17"
ralph_parse_args ralph-once claude; expect_eq "launch command: ralph-once without a number" "$RALPH_LAUNCH_CMD" "ralph-once"
ralph_parse_args ralph-epic claude 42 --force-model=opus; expect_eq "launch command: ralph-epic 42" "$RALPH_LAUNCH_CMD" "ralph-epic 42"
RALPH_LAUNCH_CMD_OUTER="ralph-epic 42" ralph_parse_args ralph-once 43; expect_eq "launch command: outer ralph-epic wins over the child once" "$RALPH_LAUNCH_CMD" "ralph-epic 42"
expect_ok "ralph-once claude 224 parses as an explicit issue" ralph_parse_args ralph-once claude 224
expect_eq "  claude is skipped, issue parsed" "$RALPH_RUNTIME/$RALPH_ISSUE_ARG" "claude/224"
expect_ok "ralph-once claude parses as selector mode" ralph_parse_args ralph-once claude
expect_eq "  selector has no issue" "$RALPH_ISSUE_ARG" ""
expect_fail "ralph-once codex 224 is rejected" ralph_parse_args ralph-once codex 224
expect_fail "ralph-once codex is rejected" ralph_parse_args ralph-once codex
expect_fail "ralph-epic codex is rejected" ralph_parse_args ralph-epic codex 12
expect_fail "ralph-once-local codex is rejected" ralph_parse_args ralph-once-local codex
expect_eq "  the rejection says Codex no longer runs Ralph" \
  "$(ralph_parse_args ralph-once codex 2>&1 | grep -c 'Codex nie uruchamia już Ralpha')" "1"
expect_eq "  usage does not mention codex" \
  "$(for l in ralph-once ralph-epic ralph-once-local; do ralph_usage $l; done | grep -ci codex)" "0"

expect_fail "unknown runtime/issue is rejected" ralph_parse_args ralph-once gpt 224
expect_fail "ralph-once-local rejects issue arg" ralph_parse_args ralph-once-local 224

expect_ok "--force-model before the issue number" ralph_parse_args ralph-once --force-model=opus 224
expect_eq "  forced model parsed" "$RALPH_FORCE_MODEL" "opus"
expect_eq "  issue still parsed" "$RALPH_ISSUE_ARG" "224"
expect_ok "--force-model after runtime and epic" ralph_parse_args ralph-epic claude 12 --force-model=sonnet
expect_eq "  forced model parsed" "$RALPH_FORCE_MODEL/$RALPH_RUNTIME/$RALPH_ISSUE_ARG" "sonnet/claude/12"
expect_ok "ralph-once-local accepts --force-model" ralph_parse_args ralph-once-local --force-model=sonnet
expect_ok "no flag -> no forced model (reset between calls)" ralph_parse_args ralph-once 224
expect_eq "  forced model empty" "$RALPH_FORCE_MODEL" ""
expect_fail "--force-model rejects an unknown model" ralph_parse_args ralph-once --force-model=haiku 224

expect_eq "contract file is CLAUDE.md" "$(ralph_contract_file)" "CLAUDE.md"

tmp_prompt=$(mktemp)
printf 'Read CLAUDE.md; use /tdd.\n' > "$tmp_prompt"
expect_eq "render prompt returns the file as is" "$(ralph_render_prompt "$tmp_prompt")" "Read CLAUDE.md; use /tdd."
rm -f "$tmp_prompt"
expect_fail "no prompt carries a runtime placeholder" \
  grep -qE '\{(AGENT_CONTRACT_FILE|SKILL_TDD|EXPLORE_GUIDANCE)\}' "$SCRIPT_DIR"/../prompt*.md

tmp_contract=$(mktemp)
printf '# Repo\n\n## Ralph\n\nRun `npm test`.\n\n### Done\ngreen\n\n## Inne\nnieistotne\n' > "$tmp_contract"
expect_eq "contract section stops at the next level-2 heading" \
  "$(ralph_contract_section "$tmp_contract")" \
  $'## Ralph\n\nRun `npm test`.\n\n### Done\ngreen'
rm -f "$tmp_contract"

# Worker mode follows from the issue's labels: ready-for-agent -> unattended, otherwise interactive.
expect_eq "mode: ready-for-agent -> afk" \
  "$(printf '%s\n' ready-for-agent complexity:normal | ralph_worker_mode)" "afk"
expect_eq "mode: no ready-for-agent -> hitl" \
  "$(printf '%s\n' complexity:normal bug | ralph_worker_mode)" "hitl"
expect_eq "mode: no labels -> hitl" "$(ralph_worker_mode </dev/null)" "hitl"
expect_eq "mode: similar label is not ready-for-agent" \
  "$(printf '%s\n' not-ready-for-agent | ralph_worker_mode)" "hitl"

# Golden files: the prompts as the worker gets them. A deliberate change means regenerating them:
# UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh
GOLDEN_DIR="$SCRIPT_DIR/golden"
for prompt_file in prompt prompt-hitl prompt-local prompt-review prompt-verify; do
  golden="$GOLDEN_DIR/$prompt_file.md"
  rendered=$(ralph_render_prompt "$SCRIPT_DIR/../$prompt_file.md")
  if [ -n "${UPDATE_GOLDEN:-}" ]; then
    printf '%s\n' "$rendered" > "$golden"
    echo "· zregenerowano $prompt_file.md"
    continue
  fi
  if [ ! -f "$golden" ]; then
    echo "✗ brak golden file $prompt_file.md (UPDATE_GOLDEN=1 żeby wygenerować)"
    fail=$((fail+1))
    continue
  fi
  if diff_out=$(diff -u "$golden" <(printf '%s\n' "$rendered")); then
    echo "✓ golden render: $prompt_file.md"
    pass=$((pass+1))
  else
    echo "✗ golden render: $prompt_file.md"
    printf '%s\n' "$diff_out" | sed 's/^/   /'
    echo "   Zmiana celowa? UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh"
    fail=$((fail+1))
  fi
done

ralph_model_for_complexity heavy
expect_eq "Claude heavy: the normal-tier model at high effort (ADR 0016)" "$RALPH_MODEL/$RALPH_EFFORT" "sonnet/high"

ralph_review_model
expect_eq "Claude przegląd heavy model" "$RALPH_REVIEW_MODEL/$RALPH_REVIEW_EFFORT" "opus/high"
RALPH_FORCE_MODEL=sonnet ralph_review_model
expect_eq "--force-model does not touch the przegląd model" "$RALPH_REVIEW_MODEL" "opus"
RALPH_FORCE_MODEL=""

ralph_model_for_complexity trivial
expect_eq "Claude trivial stays on a model with auto mode (not Haiku)" "$RALPH_MODEL/$RALPH_EFFORT" "sonnet/low"

RALPH_FORCE_MODEL=sonnet ralph_model_for_complexity heavy
expect_eq "--force-model=sonnet overrides heavy, at high effort" "$RALPH_MODEL/$RALPH_EFFORT" "sonnet/high"
RALPH_FORCE_MODEL=opus ralph_model_for_complexity trivial
expect_eq "--force-model=opus overrides trivial, at high effort" "$RALPH_MODEL/$RALPH_EFFORT" "opus/high"
RALPH_FORCE_MODEL=""

fake_hc_dir=$(mktemp -d)
mkdir "$fake_hc_dir/bin"
cat > "$fake_hc_dir/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CLAUDE_ARGV_CAPTURE"
FAKE_CLAUDE
chmod +x "$fake_hc_dir/bin/claude"
(
  PATH="$fake_hc_dir/bin:$PATH"
  CLAUDE_ARGV_CAPTURE="$fake_hc_dir/worker.argv"
  export CLAUDE_ARGV_CAPTURE
  ralph_run_worker sonnet low "PROMPT" issue-13 hitl >/dev/null
)
expect_eq "Claude HITL worker starts interactive session (no -p) in auto mode" \
  "$(cat "$fake_hc_dir/worker.argv")" \
  $'--permission-mode\nauto\n--model\nsonnet\n--effort\nlow\nPROMPT'
rm -rf "$fake_hc_dir"

# --- Claude worker: stream renderer + unattended adapter ---
stream_fixture=$(cat <<STREAM
{"type":"system","subtype":"init","session_id":"sess-123"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Zaczynam."},{"type":"tool_use","name":"Bash","input":{"command":"bash test.sh\\necho second line"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$PWD/greet.sh","old_string":"a","new_string":"b"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/elsewhere/x.md","content":"hi"}}]}}
{"type":"rate_limit_event","foo":1}
not json at all
{"type":"result","subtype":"success","result":"Gotowe: issue zamknięte.","session_id":"sess-123"}
STREAM
)
expect_eq "renderer: narration, Bash call, Edit/Write paths, final result; unknown/garbage skipped" \
  "$(ralph_render_stream <<<"$stream_fixture")" \
  $'› Zaczynam.\n  ▸ Bash: bash test.sh\n  ▸ Edit: greet.sh\n  ▸ Write: /elsewhere/x.md\n\n── Raport workera ──\nGotowe: issue zamknięte.'
expect_eq "renderer: a stream without a result says so" \
  "$(ralph_render_stream <<<'{"type":"system","subtype":"init"}')" \
  $'\n── Worker zakończył się bez raportu ──'

# Background work: a command moved to the background after the time limit, the turn ending while
# it runs (first line of the text + waiting), the CLI waking the worker when it is done, a
# stopped monitor. A foreground task's notification is not shown. The report is the last turn
# that did work, not the reply to a stale wake-up.
bg_fixture=$(cat <<'STREAM'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"composer test"}}]}}
{"type":"system","subtype":"task_started","task_id":"t1","description":"composer test","is_backgrounded":false}
{"type":"system","subtype":"task_updated","task_id":"t1","patch":{"is_backgrounded":true}}
{"type":"system","subtype":"background_tasks_changed","tasks":[{"task_id":"t1"}]}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Monitor","input":{"command":"until …","description":"Czekaj na testy"}}]}}
{"type":"system","subtype":"task_started","task_id":"m1","description":"Czekaj na testy","is_backgrounded":true}
{"type":"system","subtype":"background_tasks_changed","tasks":[{"task_id":"t1"},{"task_id":"m1"}]}
{"type":"assistant","message":{"content":[{"type":"text","text":"Testy w tle.\nDrugi akapit."}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":3,"result":"Testy w tle.\nDrugi akapit."}
{"type":"system","subtype":"task_notification","task_id":"t1","status":"completed"}
{"type":"system","subtype":"background_tasks_changed","tasks":[{"task_id":"m1"}]}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m x"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Zamknięte."}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":2,"result":"Zamknięte."}
{"type":"system","subtype":"task_notification","task_id":"m1","status":"stopped"}
{"type":"system","subtype":"background_tasks_changed","tasks":[]}
{"type":"system","subtype":"task_started","task_id":"f1","description":"krótka","is_backgrounded":false}
{"type":"system","subtype":"task_notification","task_id":"f1","status":"completed"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Monitor wygasł, nic nie zmienia."}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"Monitor wygasł, nic nie zmienia."}
STREAM
)
expect_eq "renderer: background work is spelled out; report = last turn that did work" \
  "$(ralph_render_stream <<<"$bg_fixture")" \
  "$(cat <<'WANT'
  ▸ Bash: composer test
  ⧗ Przeniesione w tle (przekroczony limit czasu komendy): composer test
  ▸ Monitor: Czekaj na testy
  ⧗ W tle: Czekaj na testy
› Testy w tle.
  … Czekam na zadania w tle (2); CLI wznowi workera, gdy się skończą.
  ↻ Zadanie w tle zakończone: composer test
  ▸ Bash: git commit -m x
› Zamknięte.
  … Czekam na zadania w tle (1); CLI wznowi workera, gdy się skończą.
  ↻ Zadanie w tle przerwane (stopped): Czekaj na testy

── Raport workera ──
Zamknięte.
WANT
)"

# Failures: a rejected tool call, a usage-limit warning then exhaustion (one line per change of
# status, not per event), and a last result with is_error printed as an interruption.
err_fixture=$(cat <<'STREAM'
{"type":"assistant","message":{"content":[{"type":"text","text":"  Sprawdzam.\nDruga linia.  "},{"type":"tool_use","name":"Grep","input":{"pattern":"foo"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"<tool_use_error>Error: No such tool available: Grep.\nmore</tool_use_error>"}]}}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","rateLimitType":"five_hour","utilization":0.9}}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","rateLimitType":"five_hour","utilization":0.91}}
{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"five_hour"}}
{"type":"result","subtype":"success","is_error":true,"num_turns":2,"result":"You've hit your session limit"}
STREAM
)
expect_eq "renderer: rejected tool call, limit status changes, interrupted worker" \
  "$(ralph_render_stream <<<"$err_fixture")" \
  "$(cat <<'WANT'
› Sprawdzam.
  Druga linia.
  ▸ Grep: foo
  ✗ Error: No such tool available: Grep.
  ⚠ Limit użycia blisko (five_hour: 90%)
  ✗ Limit użycia wyczerpany (five_hour)

── Worker przerwany ──
You've hit your session limit
WANT
)"

clip_fixture='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo 0123456789abcdefghij"}}]}}'
expect_eq "renderer: steps clipped to RALPH_COLS" \
  "$(RALPH_COLS=20 ralph_render_stream <<<"$clip_fixture" | head -1)" "  ▸ Bash: echo 0123…"
colored=$(RALPH_COLOR=1 ralph_render_stream <<<"$err_fixture")
case "$colored" in *$'\e[2m  ▸ Grep: foo\e[0m'*) r=yes ;; *) r=no ;; esac
expect_eq "renderer: colour on -> steps dimmed" "$r" "yes"
case "$colored" in *$'\e[31m  ✗ Error: No such tool'*) r=yes ;; *) r=no ;; esac
expect_eq "renderer: colour on -> rejected tool call red" "$r" "yes"
case "$colored" in *$'\e[38;5;208m  ⚠ Limit'*) r=yes ;; *) r=no ;; esac
expect_eq "renderer: colour on -> limit warning orange" "$r" "yes"
case "$(ralph_render_stream <<<"$err_fixture")" in *$'\e'*) r=yes ;; *) r=no ;; esac
expect_eq "renderer: colour off -> no escape codes" "$r" "no"

fake_claude_dir=$(mktemp -d)
mkdir "$fake_claude_dir/bin"
cat > "$fake_claude_dir/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CLAUDE_ARGV_CAPTURE"
cat "$CLAUDE_STREAM_FIXTURE"
FAKE_CLAUDE
chmod +x "$fake_claude_dir/bin/claude"
printf '%s\n' "$stream_fixture" > "$fake_claude_dir/stream.jsonl"

claude_repo=$(mktemp -d)
worker_out=$(
  cd "$claude_repo" || exit 1
  git init -q
  PATH="$fake_claude_dir/bin:$PATH"
  CLAUDE_ARGV_CAPTURE="$fake_claude_dir/worker.argv"
  CLAUDE_STREAM_FIXTURE="$fake_claude_dir/stream.jsonl"
  export CLAUDE_ARGV_CAPTURE CLAUDE_STREAM_FIXTURE
  ralph_run_worker sonnet low "PROMPT" issue-12
  echo "status:[$(git status --porcelain)]"
  echo "logs:$(ls "$(git rev-parse --git-path ralph-logs)")"
)
expect_eq "Claude worker runs unattended: -p, auto mode, stream-json" \
  "$(cat "$fake_claude_dir/worker.argv")" \
  $'-p\n--permission-mode\nauto\n--output-format\nstream-json\n--verbose\n--model\nsonnet\n--effort\nlow\nPROMPT'
case "$worker_out" in *"claude --resume sess-123"*) r=yes ;; *) r=no ;; esac
expect_eq "Claude worker prints --resume line with the session id" "$r" "yes"
case "$worker_out" in *"▸ Bash: bash test.sh"*) r=yes ;; *) r=no ;; esac
expect_eq "Claude worker shows progress lines on screen" "$r" "yes"
expect_eq "Claude worker log is written under ralph-logs, git status stays clean" \
  "$(grep -E '^(status|logs):' <<<"$worker_out" | sed -E 's/[0-9]{8}-[0-9]{6}/STAMP/')" \
  $'status:[]\nlogs:STAMP-issue-12.jsonl'
rm -rf "$fake_claude_dir" "$claude_repo"

lock_repo=$(mktemp -d)
(
  cd "$lock_repo" || exit 1
  git init -q
  ralph_acquire_lock 224
  [ -d "$(git rev-parse --git-path ralph.lock.d)" ] || exit 1
  grep -q '^runtime=claude$' "$(git rev-parse --git-path ralph.lock.d)/meta" || exit 1
  grep -q '^issue=224$' "$(git rev-parse --git-path ralph.lock.d)/meta" || exit 1
  ralph_release_lock
  [ ! -e "$(git rev-parse --git-path ralph.lock.d)" ] || exit 1
)
lock_rc=$?
rm -rf "$lock_repo"
if [ "$lock_rc" = 0 ]; then
  echo "✓ lock acquire/release writes metadata and cleans up"
  pass=$((pass+1))
else
  echo "✗ lock acquire/release writes metadata and cleans up"
  fail=$((fail+1))
fi

ralph_trap_release_lock
trap_hup=$(trap -p HUP)
trap_term=$(trap -p TERM)
trap_int=$(trap -p INT)
trap EXIT INT TERM HUP
if printf '%s\n' "$trap_hup" | grep -q 'ralph_release_lock; exit 129' &&
  printf '%s\n' "$trap_term" | grep -q 'ralph_release_lock; exit 143' &&
  printf '%s\n' "$trap_int" | grep -q 'ralph_release_lock; exit 130'; then
  echo "✓ signal traps release lock and exit"
  pass=$((pass+1))
else
  echo "✗ signal traps release lock and exit"
  fail=$((fail+1))
fi

stale_repo=$(mktemp -d)
(
  cd "$stale_repo" || exit 1
  git init -q
  stale_lock="$(git rev-parse --git-path ralph.lock.d)"
  mkdir "$stale_lock"
  printf 'pid=999999\nruntime=claude\nissue=235\n' > "$stale_lock/meta"
  output=$(ralph_acquire_lock 236 2>&1 </dev/null)
  printf '%s\n' "$output" | grep -q 'Stary lock bez żywego PID; usuwam i kontynuuję.' || exit 1
  [ -d "$stale_lock" ] || exit 1
  grep -q '^issue=236$' "$stale_lock/meta" || exit 1
  ralph_release_lock
)
stale_rc=$?
rm -rf "$stale_repo"
if [ "$stale_rc" = 0 ]; then
  echo "✓ stale lock cleanup is explicit in non-interactive mode"
  pass=$((pass+1))
else
  echo "✗ stale lock cleanup is explicit in non-interactive mode"
  fail=$((fail+1))
fi

# --- Epic filter (pure JSON) ---
iss() { jq -c -n "$1"; }
nums() { jq -r 'map(.number) | join(",")'; }
E_NONE='[]'
I_FLAT='[{"number":1,"parent":null},{"number":2,"parent":null}]'
expect_eq "filter: no epics -> unchanged" "$(ralph_filter_started_epic "$E_NONE" <<<"$I_FLAT" | nums)" "1,2"
E_ONE='[{"number":10,"started":true,"open":[11,12]},{"number":20,"started":false,"open":[21]}]'
I_ONE='[{"number":11,"parent":10},{"number":12,"parent":10},{"number":21,"parent":20},{"number":5,"parent":null}]'
expect_eq "filter: one started epic -> only its sub-issues" "$(ralph_filter_started_epic "$E_ONE" <<<"$I_ONE" | nums)" "11,12"
E_TWO='[{"number":30,"started":true,"open":[31]},{"number":10,"started":true,"open":[11]}]'
I_TWO='[{"number":31,"parent":30},{"number":11,"parent":10},{"number":5,"parent":null}]'
expect_eq "filter: two started epics -> oldest" "$(ralph_filter_started_epic "$E_TWO" <<<"$I_TWO" | nums)" "11"
E_EMPTY='[{"number":10,"started":true,"open":[]},{"number":20,"started":false,"open":[21]}]'
I_EMPTY='[{"number":21,"parent":20},{"number":5,"parent":null}]'
expect_eq "filter: started epic without open sub-issues is ignored" "$(ralph_filter_started_epic "$E_EMPTY" <<<"$I_EMPTY" | nums)" "21,5"
E_MIX='[{"number":20,"started":false,"open":[21]}]'
expect_eq "filter: parentless issues next to unstarted epics unchanged" "$(ralph_filter_started_epic "$E_MIX" <<<"$I_EMPTY" | nums)" "21,5"
expect_eq "annotate: parent filled from epics' open lists" \
  "$(ralph_annotate_parents "$E_ONE" <<<'[{"number":11},{"number":5}]' | jq -c 'map(.parent)')" "[10,null]"
expect_eq "epic issues: only the named epic's sub-issues" "$(ralph_epic_issues 20 <<<"$I_ONE" | nums)" "21"
expect_eq "epic issues: epic without open sub-issues -> empty" "$(ralph_epic_issues 99 <<<"$I_ONE" | nums)" ""

# --- Epic stage (ADR 0013): AFK first, then HITL ---
L_AFK='[{"name":"ready-for-agent"}]'
L_HITL='[{"name":"bug"}]'
S_BOTH="[{\"number\":1,\"labels\":$L_HITL},{\"number\":2,\"labels\":$L_AFK},{\"number\":3,\"labels\":$L_AFK}]"
expect_eq "stage: free AFK present -> only AFK" "$(ralph_epic_stage <<<"$S_BOTH" | nums)" "2,3"
S_HITL="[{\"number\":1,\"labels\":$L_HITL},{\"number\":4,\"labels\":[]}]"
expect_eq "stage: no AFK, free HITL -> HITL" "$(ralph_epic_stage <<<"$S_HITL" | nums)" "1,4"
S_BLK="[{\"number\":1,\"labels\":$L_HITL,\"issue_dependencies_summary\":{\"blocked_by\":1}}]"
expect_eq "stage: blocked HITL dropped by filter -> nothing" \
  "$(ralph_filter_unblocked <<<"$S_BLK" | ralph_epic_stage | nums)" ""
expect_eq "pick first: lowest number, whatever the order" \
  "$(ralph_pick_first <<<'[{"number":9},{"number":7},{"number":8}]')" "7"
expect_eq "pick first: empty list -> nothing" "$(ralph_pick_first <<<'[]')" ""
expect_eq "stage: blocked AFK, free HITL -> HITL" \
  "$(jq -c '[.[0] + {labels: [{"name":"ready-for-agent"}]}] + [{"number":7,"labels":[],"issue_dependencies_summary":{"blocked_by":0}}]' <<<"$S_BLK" \
    | ralph_filter_unblocked | ralph_epic_stage | nums)" "7"
expect_eq "stage: empty -> empty" "$(ralph_epic_stage <<<'[]' | nums)" ""

# --- Exit code of a finished run ---
expect_eq "outcome: closed (afk) -> 0" "$(ralph_run_outcome afk closed false)" "0"
expect_eq "outcome: closed (hitl) -> 0" "$(ralph_run_outcome hitl closed false)" "0"
expect_eq "outcome: afk open, still labelled -> 3" "$(ralph_run_outcome afk open true)" "3"
expect_eq "outcome: afk open, label removed -> 4" "$(ralph_run_outcome afk open false)" "4"
expect_eq "outcome: hitl open, no label -> 5" "$(ralph_run_outcome hitl open false)" "5"
expect_eq "outcome: hitl open, label restored -> 6" "$(ralph_run_outcome hitl open true)" "6"
expect_eq "outcome: unreadable state -> 1" "$(ralph_run_outcome afk '' false)" "1"

# --- Colour and verdict lines ---
expect_eq "say: colour off -> plain text" "$(ralph_say err "błąd")" "błąd"
expect_eq "say: ok green" "$(RALPH_COLOR=1 ralph_say ok "x" | cat -v)" "^[[32mx^[[0m"
expect_eq "say: warn orange" "$(RALPH_COLOR=1 ralph_say warn "x" | cat -v)" "^[[38;5;208mx^[[0m"
expect_eq "say: err red" "$(RALPH_COLOR=1 ralph_say err "x" | cat -v)" "^[[31mx^[[0m"
expect_eq "say: unknown tone -> plain" "$(RALPH_COLOR=1 ralph_say foo "x")" "x"
expect_eq "colour init: inherited RALPH_COLOR wins" "$(RALPH_COLOR=1 bash -c '. "$0"; echo $RALPH_COLOR' "$SCRIPT_DIR/../lib.sh" | cat)" "1"
expect_eq "colour init: stdout not a TTY -> off" "$(env -u RALPH_COLOR bash -c '. "$0"; echo $RALPH_COLOR' "$SCRIPT_DIR/../lib.sh" | cat)" "0"
expect_eq "term cols: RALPH_COLS wins" "$(RALPH_COLS=77 ralph_term_cols)" "77"
expect_eq "term cols: garbage -> 0 (no clipping)" "$(RALPH_COLS=abc ralph_term_cols)" "0"
expect_eq "verdict: closed" "$(ralph_outcome_message 0 7)" "✓ Issue #7 zamknięte."
expect_eq "verdict: AFK failed" "$(ralph_outcome_message 3 7)" "✗ Issue #7 nie zostało domknięte (nadal ma ready-for-agent)."
expect_eq "verdict: discovered HITL" "$(ralph_outcome_message 4 7)" "⚠ Issue #7 wymaga człowieka: worker zdjął ready-for-agent (odkryty HITL)."
expect_eq "verdict: HITL unresolved" "$(ralph_outcome_message 5 7)" "⚠ Sesja HITL skończona, issue #7 nadal otwarte bez ready-for-agent."
expect_eq "verdict: HITL handed back" "$(ralph_outcome_message 6 7)" "✓ Issue #7 oddane pętli (przywrócone ready-for-agent)."
expect_eq "verdict: unreadable state" "$(ralph_outcome_message 1 7)" "✗ Nie udało się odczytać stanu issue #7 po runie."
case "$(RALPH_COLOR=1 ralph_outcome_message 0 7)$(RALPH_COLOR=1 ralph_outcome_message 3 7)$(RALPH_COLOR=1 ralph_outcome_message 4 7)" in
  $'\e[32m✓'*$'\e[31m✗'*$'\e[38;5;208m⚠'*) r=yes ;;
  *) r=no ;;
esac
expect_eq "verdict: green done, red failure, orange waiting for a human" "$r" "yes"
expect_eq "outcome: codes are distinct" \
  "$(printf '%s\n' "$RALPH_EXIT_DONE" "$RALPH_EXIT_ERROR" "$RALPH_EXIT_NOTHING" "$RALPH_EXIT_AFK_FAILED" "$RALPH_EXIT_DISCOVERED" "$RALPH_EXIT_HITL_OPEN" "$RALPH_EXIT_HITL_TO_AFK" | sort -u | wc -l | tr -d ' ')" "7"

# --- Gate command (ralph-gate:) ---
expect_eq "gate: line present -> command" \
  "$(ralph_gate_command <<<$'## Ralph\nralph-gate: bash a.sh && bash b.sh')" "bash a.sh && bash b.sh"
expect_eq "gate: list marker and backticks tolerated" \
  "$(ralph_gate_command <<<$'## Ralph\n- ralph-gate: `bash a.sh && bash b.sh`')" "bash a.sh && bash b.sh"
expect_fail "gate: line absent -> no gate" ralph_gate_command <<<$'## Ralph\nFeedback: make test'
expect_fail "gate: empty command -> no gate" ralph_gate_command <<<$'## Ralph\nralph-gate:   '
gate_file=$(mktemp)
printf '# T\nralph-gate: outside\n\n## Ralph\nx\n\n## Other\nralph-gate: also outside\n' > "$gate_file"
expect_fail "gate: line outside ## Ralph does not count" \
  bash -c ". '$SCRIPT_DIR/../lib.sh'; ralph_contract_section '$gate_file' | ralph_gate_command"
rm -f "$gate_file"

# --- Epic branch (ADR 0012) ---
SECTION_WITH=$'## Ralph\n\n### Commit\n\nralph-base-branch: dev\n\n- Polish message.'
expect_eq "base branch: line present -> branch name" "$(ralph_base_branch <<<"$SECTION_WITH")" "dev"
SECTION_WITHOUT=$'## Ralph\n\n### Commit\n\n- Polish message.'
expect_eq "base branch: line absent -> nothing (trunk)" "$(ralph_base_branch <<<"$SECTION_WITHOUT")" ""
expect_ok "base branch: line absent -> success" ralph_base_branch <<<"$SECTION_WITHOUT"
expect_eq "base branch: list marker and backticks tolerated" \
  "$(ralph_base_branch <<<$'## Ralph\n- ralph-base-branch: `release/2.x`')" "release/2.x"
expect_fail "base branch: empty value rejected" ralph_base_branch <<<$'ralph-base-branch:' 2>/dev/null
expect_fail "base branch: extra words rejected" ralph_base_branch <<<$'ralph-base-branch: dev (produkcja)' 2>/dev/null
expect_fail "base branch: bad ref name rejected" ralph_base_branch <<<$'ralph-base-branch: ../dev' 2>/dev/null
expect_fail "base branch: key inside prose rejected" ralph_base_branch <<<$'Use `ralph-base-branch: dev` here.' 2>/dev/null
expect_fail "base branch: two declarations rejected" ralph_base_branch <<<$'ralph-base-branch: dev\nralph-base-branch: main' 2>/dev/null
expect_ok "base branch: bad syntax explains the expected line" \
  grep -qF 'ralph-base-branch: <gałąź>' <<<"$(ralph_base_branch <<<'ralph-base-branch:' 2>&1)"

# The ralph-konfiguracja template is what writes that line into other repos: it must name the key
# exactly once (any other mention makes the parser fail closed), and the line must parse.
TEMPLATE=$(awk '/^```markdown$/{f=1;next} /^```$/{f=0} f' "$SCRIPT_DIR/../../skills/ralph-konfiguracja/SKILL.md")
expect_eq "template: key named exactly once" "$(grep -cF 'ralph-base-branch' <<<"$TEMPLATE")" "1"
expect_eq "template: base-branch line parses once <baza> is filled" \
  "$(sed 's/<baza>/dev/' <<<"$TEMPLATE" | ralph_base_branch)" "dev"
expect_eq "template: without the epic-branch line the section stays trunk" \
  "$(grep -vF 'ralph-base-branch' <<<"$TEMPLATE" | ralph_base_branch)" ""

# ralph_prepare_branch works on the git repo in cwd: each case gets a fresh temp repo whose
# base branch `dev` holds one commit, and runs in a subshell (exit 0 = pass).
branch_case() {
  local desc="$1" fn="$2" repo rc
  repo=$(mktemp -d)
  (
    cd "$repo" || exit 1
    git init -q -b dev
    git config user.name ralph-test
    git config user.email ralph-test@example.invalid
    printf 'a\n' > f
    git add f
    git commit -qm init
    "$fn"
  ) >/dev/null 2>"$repo.err"
  rc=$?
  if [ "$rc" = 0 ]; then
    echo "✓ $desc"
    pass=$((pass+1))
  else
    echo "✗ $desc"
    sed 's/^/   /' "$repo.err"
    fail=$((fail+1))
  fi
  rm -rf "$repo" "$repo.err"
}
on_branch() { [ "$(git branch --show-current)" = "$1" ]; }
commit_file() { printf '%s\n' "$2" > "$1"; git add "$1"; git commit -qm "$1: $2"; }

case_create() {
  ralph_prepare_branch dev 7 || exit 1
  on_branch epic/7 || exit 1
  [ "$(git rev-parse epic/7)" = "$(git rev-parse dev)" ]
}
branch_case "prepare: first run on an epic creates epic/<n> from base" case_create

case_reuse() {
  git checkout -q -b epic/7
  commit_file g epic-work
  local epic_head; epic_head=$(git rev-parse HEAD)
  git checkout -q dev
  ralph_prepare_branch dev 7 || exit 1
  on_branch epic/7 || exit 1
  # Base did not move: no merge, the epic's own history is untouched.
  [ "$(git rev-parse HEAD)" = "$epic_head" ]
}
branch_case "prepare: later runs switch to the existing epic/<n>" case_reuse

case_merge_base() {
  git checkout -q -b epic/7
  commit_file g epic-work
  git checkout -q dev
  commit_file h hotfix
  ralph_prepare_branch dev 7 || exit 1
  on_branch epic/7 || exit 1
  git merge-base --is-ancestor dev epic/7 || exit 1
  [ -f g ] && [ -f h ] || exit 1
  [ -z "$(git status --porcelain)" ]
}
branch_case "prepare: base moved on -> merged into epic/<n>" case_merge_base

case_conflict() {
  git checkout -q -b epic/7
  commit_file f epic-side
  local epic_head; epic_head=$(git rev-parse HEAD)
  git checkout -q dev
  commit_file f base-side
  local out
  if out=$(ralph_prepare_branch dev 7 2>&1); then exit 1; fi
  grep -q 'Konflikt' <<<"$out" || exit 1
  [ -z "$(git status --porcelain)" ] || exit 1
  [ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ] || exit 1
  [ "$(git rev-parse epic/7)" = "$epic_head" ] || exit 1
  [ "$(cat f)" = "epic-side" ]
}
branch_case "prepare: merge conflict -> aborted, clean tree, non-zero, epic untouched" case_conflict

case_dirty_tracked() {
  printf 'edit\n' > f
  local head; head=$(git rev-parse HEAD)
  if ralph_prepare_branch dev 7 2>/dev/null; then exit 1; fi
  on_branch dev || exit 1
  ! git rev-parse --verify --quiet refs/heads/epic/7 >/dev/null || exit 1
  [ "$(cat f)" = "edit" ] && [ "$(git rev-parse HEAD)" = "$head" ]
}
branch_case "prepare: modified tracked file -> refused before any git operation" case_dirty_tracked

case_dirty_untracked() {
  git checkout -q -b epic/7
  git checkout -q dev
  commit_file h hotfix
  printf 'x\n' > stray
  if ralph_prepare_branch dev 7 2>/dev/null; then exit 1; fi
  # Still on dev, epic/7 not merged, the stray file left alone.
  on_branch dev || exit 1
  ! git merge-base --is-ancestor dev epic/7 || exit 1
  [ -f stray ]
}
branch_case "prepare: untracked file -> refused, nothing switched or merged" case_dirty_untracked

case_no_parent() {
  git checkout -q -b epic/7
  commit_file g epic-work
  ralph_prepare_branch dev "" || exit 1
  on_branch dev || exit 1
  [ ! -f g ]
}
branch_case "prepare: issue without a parent -> work on the base" case_no_parent

case_missing_base() {
  local out
  if out=$(ralph_prepare_branch nope 7 2>&1); then exit 1; fi
  grep -q "nope" <<<"$out" || exit 1
  on_branch dev || exit 1
  ! git rev-parse --verify --quiet refs/heads/epic/7 >/dev/null
}
branch_case "prepare: missing local base -> refused, no epic branch created" case_missing_base

fake_gh_dir=$(mktemp -d)
cat > "$fake_gh_dir/gh" <<'FAKE_GH'
#!/usr/bin/env bash
case "$FAKE_GH_MODE" in
  parent) echo 12 ;;
  none) echo '{"message":"No parent issue found","status":"404"}'; echo 'gh: No parent issue found (HTTP 404)' >&2; exit 1 ;;
  *) echo 'error connecting to api.github.com' >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$fake_gh_dir/gh"
expect_eq "issue parent: sub-issue -> epic number" "$(PATH="$fake_gh_dir:$PATH" FAKE_GH_MODE=parent ralph_issue_parent 13)" "12"
expect_eq "issue parent: 404 -> nothing" "$(PATH="$fake_gh_dir:$PATH" FAKE_GH_MODE=none ralph_issue_parent 13)" ""
expect_ok "issue parent: 404 -> success" env PATH="$fake_gh_dir:$PATH" FAKE_GH_MODE=none bash -c ". '$SCRIPT_DIR/../lib.sh'; ralph_issue_parent 13"
expect_fail "issue parent: other gh failure -> error, not 'no parent'" \
  env PATH="$fake_gh_dir:$PATH" FAKE_GH_MODE=down bash -c ". '$SCRIPT_DIR/../lib.sh'; ralph_issue_parent 13"
rm -rf "$fake_gh_dir"

# --- ralph_filter_unblocked: issues with an open blocker (native "blocked by") are dropped ---
# $1: number, $2: open blockers, $3: all blockers (default = $2), $4: body (default empty).
mk() { jq -cn --argjson n "$1" --argjson o "$2" --argjson t "${3:-$2}" --arg b "${4:-}" \
  '{number: $n, title: "t", body: $b, issue_dependencies_summary: {blocked_by: $o, total_blocked_by: $t}}'; }
unblocked() { printf '%s\n' "$@" | jq -cs '.' | ralph_filter_unblocked | nums; }
expect_eq "unblocked: open blocker -> rejected" "$(unblocked "$(mk 1 1)")" ""
expect_eq "unblocked: only closed blockers -> passes" "$(unblocked "$(mk 1 0 2)")" "1"
expect_eq "unblocked: no blockers -> passes" "$(unblocked "$(mk 1 0)")" "1"
expect_eq "unblocked: no dependency summary -> rejected (fail-closed)" "$(unblocked '{"number":1,"title":"t","body":""}')" ""
expect_eq "unblocked: numbers in the body text are ignored" \
  "$(unblocked "$(mk 1 0 0 $'## Blocked by\n\n- #12\n\nheavy: przesuwne 7 dni')")" "1"
expect_eq "unblocked: keeps order of the free ones" "$(unblocked "$(mk 3 0)" "$(mk 1 1)" "$(mk 2 0)")" "3,2"

# --- gh layer for blockers: candidates fetch (fail-closed) and the open-blocker report ---
fake_gh_dir=$(mktemp -d)
cat > "$fake_gh_dir/gh" <<'FAKE_GH'
#!/usr/bin/env bash
[ "$FAKE_GH_MODE" = down ] && { echo 'error connecting to api.github.com' >&2; exit 1; }
case "$*" in
  "api --paginate repos/{owner}/{repo}/issues?state=open&per_page=100")
    echo '[{"number":5,"title":"a","body":null,"labels":[],"issue_dependencies_summary":{"blocked_by":0}},{"number":6,"title":"pr","pull_request":{}}]'
    echo '[{"number":7,"title":"b","body":"x","labels":[{"name":"ready-for-agent"}],"issue_dependencies_summary":{"blocked_by":1}}]' ;;
  "api --paginate repos/{owner}/{repo}/issues/3/dependencies/blocked_by")
    echo '[{"number":7,"state":"open"},{"number":2,"state":"closed"}]' ;;
  "api --paginate repos/{owner}/{repo}/issues/9/dependencies/blocked_by")
    echo '[{"number":3,"state":"open"}]'; echo '[{"number":6,"state":"open"}]' ;;
  "api --paginate repos/{owner}/{repo}/issues/"*"/dependencies/blocked_by") echo '[]' ;;
  *) exit 1 ;;
esac
FAKE_GH
chmod +x "$fake_gh_dir/gh"
expect_eq "open issues: all pages, pull requests dropped" \
  "$(PATH="$fake_gh_dir:$PATH" ralph_open_issues | nums)" "5,7"
expect_eq "open issues: keeps labels and the dependency summary" \
  "$(PATH="$fake_gh_dir:$PATH" ralph_open_issues | jq -c '.[1] | [.labels[0].name, .issue_dependencies_summary.blocked_by]')" '["ready-for-agent",1]'
expect_fail "open issues: gh failure -> error, not an empty list" \
  env PATH="$fake_gh_dir:$PATH" FAKE_GH_MODE=down bash -c ". '$SCRIPT_DIR/../lib.sh'; ralph_open_issues"
expect_eq "open blockers: only open ones" "$(PATH="$fake_gh_dir:$PATH" ralph_open_blockers 3)" "#7"
expect_eq "open blockers: all pages" "$(PATH="$fake_gh_dir:$PATH" ralph_open_blockers 9)" "#3, #6"
expect_eq "open blockers: none -> nothing" "$(PATH="$fake_gh_dir:$PATH" ralph_open_blockers 4)" ""
expect_eq "open blockers: gh failure -> '?'" "$(PATH="$fake_gh_dir:$PATH" FAKE_GH_MODE=down ralph_open_blockers 3)" "?"
expect_eq "blocked report: one line per issue with its open blockers" \
  "$(printf '[{"number":3},{"number":9}]' | PATH="$fake_gh_dir:$PATH" ralph_blocked_report)" "  #3 ← #7
  #9 ← #3, #6"
rm -rf "$fake_gh_dir"

# --- Weryfikacja epica (ADR 0018): the epic's state, the round, the decision (pure) ---
# ralph_epic_state: total sub-issues, open sub-issues, has needs-human-test.
expect_eq "state: 3 sub-issues, all closed, no label -> to-verify" "$(ralph_epic_state 3 0 false)" "to-verify"
expect_eq "state: open sub-issues -> in-progress" "$(ralph_epic_state 3 1 false)" "in-progress"
expect_eq "state: no sub-issues -> unplanned (neither verified nor labelled)" "$(ralph_epic_state 0 0 false)" "unplanned"
expect_eq "state: label present -> awaiting, not verified again" "$(ralph_epic_state 3 0 true)" "awaiting"
expect_eq "state: an epic labelled before the change (no markers) stays awaiting" "$(ralph_epic_state 2 0 true)" "awaiting"
expect_eq "state: label wins over open sub-issues (a Poprawka added while awaiting)" "$(ralph_epic_state 3 1 true)" "awaiting"

VM="$RALPH_VERIFY_MARKER"; OM="$RALPH_ODBIOR_MARKER"
round_of() { jq -c -n '$ARGS.positional | map({body: .})' --args "$@" | ralph_verify_round; }
expect_eq "round: no comments -> 1" "$(round_of)" "1"
expect_eq "round: unrelated comments only -> 1" "$(round_of 'odchylenie' 'inny komentarz')" "1"
expect_eq "round: one verification marker -> 2" "$(round_of "$VM
runda 1")" "2"
expect_eq "round: two verification markers -> 3" "$(round_of "$VM" 'x' "$VM")" "3"
expect_eq "round: acceptance marker after two rounds, then a Poprawka -> next verification is round 1" \
  "$(round_of "$VM" "$VM" "$OM" 'inny')" "1"
expect_eq "round: one round after the acceptance marker -> 2" "$(round_of "$VM" "$VM" "$OM" "$VM")" "2"
expect_eq "round: the acceptance marker alone -> 1" "$(round_of "$OM")" "1"

expect_eq "verify decision: green in round 1 -> accept" "$(ralph_verify_decision 0 1)" "accept"
expect_eq "verify decision: green in round 2 -> accept" "$(ralph_verify_decision 0 2)" "accept"
expect_eq "verify decision: red in round 1 -> fix" "$(ralph_verify_decision 1 1)" "fix"
expect_eq "verify decision: red in round 2 -> accept-red (no new Poprawka)" "$(ralph_verify_decision 1 2)" "accept-red"
expect_eq "verify decision: red in round 3 -> accept-red" "$(ralph_verify_decision 5 3)" "accept-red"
expect_eq "verify decision: green gate, blocking findings, round 1 -> fix" "$(ralph_verify_decision 0 1 2)" "fix"
expect_eq "verify decision: green gate, blocking findings, round 2 -> accept-red" "$(ralph_verify_decision 0 2 1)" "accept-red"
expect_eq "verify decision: green gate, no blocking findings -> accept" "$(ralph_verify_decision 0 2 0)" "accept"

# --- Raport weryfikatora (ADR 0018): parsing, blocking, issue bodies, the list's parts (pure) ---
R_FENCE='```'
V_REPORT_EMPTY=$'Nic nie znalazłem.\n\n```json\n{"findings": [], "items": []}\n```'
mk_reply() { printf 'Podsumowanie dla człowieka.\n\n%sjson\n%s\n%s\n' "$R_FENCE" "$1" "$R_FENCE"; }
R_BLOCK_N='{"category":"blocking","area":"security","title":"Zamknij wyciek tenantów","rationale":"Orders::show (app/Orders.php:12) nie sprawdza tenanta.","complexity":"normal","acceptance":["GET cudzego zamówienia -> 404"]}'
R_BLOCK_H='{"category":"blocking","area":"prd","title":"Napraw naliczanie","rationale":"Naliczanie ignoruje rok przestępny.","complexity":"heavy","acceptance":["luty 2028 liczy 29 dni"],"cases":["1 marca 2028 -> 29 dni lutego","1 marca 2027 -> 28 dni lutego"]}'
R_PROP='{"category":"proposal","area":"ux","title":"Większy przycisk","rationale":"Przycisk Zapisz jest mały."}'
R_REF='{"category":"refactor","area":"architecture","title":"Wydziel serwis cen","rationale":"Logika cen w trzech kontrolerach."}'
R_ITEMS='{"kind":"not-proven","text":"Czy mail dochodzi na prawdziwą skrzynkę"},{"kind":"before-after","text":"Ekran listy. Przed: tabela. Po: karty."}'
R_ALL=$(mk_reply "{\"findings\":[$R_BLOCK_N,$R_BLOCK_H,$R_PROP,$R_REF],\"items\":[$R_ITEMS]}")
parsed_all=$(ralph_report_parse <<<"$R_ALL")
expect_eq "report: a valid reply parses; findings by category" \
  "$(jq -r '[.findings[].category] | join(",")' <<<"$parsed_all")" "blocking,blocking,proposal,refactor"
expect_eq "report: blocking count" "$(ralph_report_blocking_count "$parsed_all")" "2"
expect_eq "report: defaults are filled (complexity normal, no cases, no area)" \
  "$(ralph_report_parse <<<"$(mk_reply '{"findings":[{"category":"proposal","title":"t","rationale":"r"}]}')" | jq -c '.findings[0] | [.complexity, .cases, .area]')" '["normal",[],""]'
expect_eq "report: no findings is a valid report" "$(ralph_report_parse <<<"$V_REPORT_EMPTY" | jq -c .)" '{"findings":[],"items":[]}'
expect_eq "report: only the last json block counts" \
  "$(ralph_report_parse <<<"$(mk_reply '{"findings":[],"items":[]}')"$'\n'"$(mk_reply "{\"findings\":[$R_PROP]}")" | jq -r '.findings[0].title')" "Większy przycisk"
bad() { ralph_report_parse <<<"$1" >/dev/null 2>&1; echo "rc=$?"; }
expect_eq "report: no json block -> unreadable" "$(bad 'Wszystko dobrze, nic nie znalazłem.')" "rc=1"
expect_eq "report: not JSON -> unreadable" "$(bad "$(mk_reply '{nie json')")" "rc=1"
expect_eq "report: empty block -> unreadable" "$(bad "$(mk_reply '')")" "rc=1"
expect_eq "report: findings missing -> unreadable" "$(bad "$(mk_reply '{"items":[]}')")" "rc=1"
expect_eq "report: unknown category -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[{"category":"opinia","title":"t","rationale":"r"}]}')")" "rc=1"
expect_eq "report: finding without a rationale -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[{"category":"proposal","title":"t"}]}')")" "rc=1"
expect_eq "report: blocking without acceptance criteria -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[{"category":"blocking","title":"t","rationale":"r","complexity":"normal","acceptance":[]}]}')")" "rc=1"
expect_eq "report: blocking without a complexity -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[{"category":"blocking","title":"t","rationale":"r","acceptance":["a"]}]}')")" "rc=1"
expect_eq "report: blocking with an unknown complexity -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[{"category":"blocking","title":"t","rationale":"r","complexity":"huge","acceptance":["a"]}]}')")" "rc=1"
expect_eq "report: heavy without cases -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[{"category":"blocking","title":"t","rationale":"r","complexity":"heavy","acceptance":["a"]}]}')")" "rc=1"
expect_eq "report: an item of an unknown kind -> unreadable" \
  "$(bad "$(mk_reply '{"findings":[],"items":[{"kind":"opinia","text":"x"}]}')")" "rc=1"

body_n=$(ralph_report_issue_body "$(ralph_report_findings "$parsed_all" blocking | head -1)" 45 1)
expect_eq "fix body: the rationale, the epic and round, criteria as a checklist, no case list for a normal one" \
  "$(grep -c 'Orders::show' <<<"$body_n")|$(grep -c 'epicu #45, runda 1, obszar: security' <<<"$body_n")|$(grep -c -- '- \[ \] GET cudzego zamówienia -> 404' <<<"$body_n")|$(grep -c 'Przypadki do przetestowania' <<<"$body_n")" "1|1|1|0"
body_h=$(ralph_report_issue_body "$(ralph_report_findings "$parsed_all" blocking | tail -1)" 45 1)
expect_eq "fix body (heavy): the case list for the przegląd, one bullet per case" \
  "$(grep -c '^## Przypadki do przetestowania' <<<"$body_h")|$(grep -c -- '^- 1 marca 2028 -> 29 dni lutego' <<<"$body_h")|$(grep -c -- '^- 1 marca 2027 -> 28 dni lutego' <<<"$body_h")" "1|1|1"
expect_eq "unresolved: blocking findings as bullets, nothing else" \
  "$(ralph_report_unresolved "$parsed_all" | grep -c '^- \*\*')|$(ralph_report_unresolved "$parsed_all" | grep -c 'Większy przycisk')" "2|0"
sections=$(ralph_report_sections "$parsed_all")
expect_eq "list parts: not-proven, before/after and proposals, in that order; refactors are not there" \
  "$(grep '^### ' <<<"$sections" | paste -sd, -)|$(grep -c 'Wydziel serwis cen' <<<"$sections")" \
  "### Czego bramka nie udowadnia,### Przed / po (wygląd zapowiedziany w PRD),### Propozycje do decyzji|0"
expect_eq "list parts: nothing to say -> nothing" "$(ralph_report_sections "$(ralph_report_parse <<<"$V_REPORT_EMPTY")")" ""
list_full=$(ralph_acceptance_list 45 "1. Krok" 'cd /w && claude "/odbior 45"' '' '' '' '' "$(ralph_report_unresolved "$parsed_all")" "$sections" v-sess-1)
expect_eq "acceptance list: unresolved findings first, then the steps, the report's parts, the command" \
  "$(grep -E '^### ' <<<"$list_full" | paste -sd, -)" \
  "### Nierozwiązane,### Kroki (## Jak odebrać),### Czego bramka nie udowadnia,### Przed / po (wygląd zapowiedziany w PRD),### Propozycje do decyzji,### Odbiór"
expect_eq "acceptance list: the weryfikator's session id with the resume command" \
  "$(grep -c 'claude --resume v-sess-1' <<<"$list_full")" "1"
list_green=$(ralph_acceptance_list 45 "1. Krok" 'cd /w && claude "/odbior 45"')
expect_eq "acceptance list: no session -> no resume line" "$(grep -c 'resume' <<<"$list_green")" "0"
expect_eq "stale ślad: verify, epic open and not handed over -> fits" "$(ralph_limit_trace_stale verify open false epic/45 epic/45)" ""
expect_eq "stale ślad: verify, epic closed" "$(ralph_limit_trace_stale verify closed false epic/45 epic/45)" "epic jest już zamknięty"
expect_eq "stale ślad: verify, epic already has needs-human-test" "$(ralph_limit_trace_stale verify open true epic/45 epic/45)" "epic ma już needs-human-test"

expect_eq "steps: the Jak odebrać section of an epic body, without the heading and the next section" \
  "$(printf '## Solution\nx\n\n## Jak odebrać\n\n1. Pierwszy\n2. Drugi\n\n## Inne\nnie to\n' | ralph_epic_acceptance_steps)" $'1. Pierwszy\n2. Drugi'
expect_eq "steps: no section -> nothing" "$(printf '## Solution\nx\n' | ralph_epic_acceptance_steps)" ""
expect_eq "acceptance command: cd <worktree> && claude \"/odbior <nr>\"" \
  "$(ralph_acceptance_command 45 /tmp/wt)" 'cd /tmp/wt && claude "/odbior 45"'
wt_dir="$(mktemp -d)/my wt"; mkdir "$wt_dir"
expect_eq "acceptance command: a worktree path with a space still cd's into it" \
  "$(bash -c "$(ralph_acceptance_command 45 "$wt_dir" | sed 's/ && claude.*//') && pwd")" "$wt_dir"
rm -rf "${wt_dir%/my wt}"
expect_eq "acceptance list: steps and the command, the marker first, no unresolved section" \
  "$(head -1 <<<"$list_green")|$(grep -c '1. Krok' <<<"$list_green")|$(grep -c 'odbior 45' <<<"$list_green")|$(grep -c 'Nierozwiązane' <<<"$list_green")" \
  "$RALPH_ACCEPT_LIST_MARKER|1|1|0"
list_red=$(ralph_acceptance_list 45 "1. Krok" 'cd /w && claude "/odbior 45"' 'make test' 3 'FAIL: x' /tmp/g.log)
expect_eq "acceptance list: a red gate goes before the steps" \
  "$(grep -nE 'Nierozwiązane|Kroki' <<<"$list_red" | cut -d: -f2 | paste -sd, -)" "### Nierozwiązane,### Kroki (## Jak odebrać)"
expect_eq "acceptance list: the red gate names its command, code, output and log" \
  "$(grep -c 'make test' <<<"$list_red")|$(grep -c 'kod 3' <<<"$list_red")|$(grep -c 'FAIL: x' <<<"$list_red")|$(grep -c '/tmp/g.log' <<<"$list_red")" "1|1|1|1"
expect_eq "acceptance list: the lists carry no round marker (they would reset or advance the count)" \
  "$(grep -cE 'ralph-weryfikacja|ralph-odbior' <<<"$list_red$list_green")" "0"

# --- ralph-epic: pure decisions (args: exit code, iterations done, limit, epic ready "true"/"false") ---
dec() { ralph_epic_decision "$@"; }
expect_eq "decision: 0 (closed) -> continue" "$(dec 0 1 5 false)" "continue"
expect_eq "decision: 6 (HITL handed to AFK) -> continue" "$(dec 6 1 5 false)" "continue"
expect_eq "decision: 4 (discovered HITL) -> continue" "$(dec 4 1 5 false)" "continue"
expect_eq "decision: 3 (AFK failed) -> stop-afk-failed" "$(dec 3 1 5 false)" "stop-afk-failed"
expect_eq "decision: 5 (HITL unresolved) -> stop-hitl" "$(dec 5 1 5 false)" "stop-hitl"
expect_eq "decision: 2 (nothing to do) -> stop-nothing" "$(dec 2 1 5 false)" "stop-nothing"
expect_eq "decision: 1 (error) -> stop-error" "$(dec 1 1 5 false)" "stop-error"
expect_eq "decision: unknown code -> stop-error" "$(dec 42 1 5 false)" "stop-error"
expect_eq "decision: epic ready wins over closed" "$(dec 0 1 5 true)" "stop-ready"
expect_eq "decision: epic ready wins over nothing to do" "$(dec 2 1 5 true)" "stop-ready"
expect_eq "decision: epic ready does not hide an error" "$(dec 1 1 5 true)" "stop-error"
expect_eq "decision: limit reached after a closed issue -> stop-limit" "$(dec 0 5 5 false)" "stop-limit"
expect_eq "decision: limit exceeded after HITL handed back -> stop-limit" "$(dec 6 6 5 false)" "stop-limit"
expect_eq "decision: limit does not mask AFK failure" "$(dec 3 5 5 false)" "stop-afk-failed"
expect_eq "decision: below limit -> continue" "$(dec 0 4 5 false)" "continue"
expect_eq "limit: twice the open sub-issues" "$(ralph_epic_iteration_limit 3)" "6"

# --- ralph-epic: which epic (same rule as the selector: started first, then lowest number) ---
E_PICK='[{"number":5,"started":false,"open":[50]},{"number":9,"started":true,"open":[90]},{"number":7,"started":true,"open":[70]},{"number":3,"started":true,"open":[]},{"number":2,"started":false,"open":[]}]'
expect_eq "pick epic: lowest started with open sub-issues" "$(ralph_pick_epic <<<"$E_PICK")" "7"
expect_eq "pick epic: none started -> lowest with open sub-issues" \
  "$(ralph_pick_epic <<<'[{"number":5,"started":false,"open":[50]},{"number":4,"started":false,"open":[40]}]')" "4"
expect_eq "pick epic: nothing open -> empty" "$(ralph_pick_epic <<<'[{"number":3,"started":true,"open":[]}]')" ""
expect_eq "pick epic: no epics -> empty" "$(ralph_pick_epic <<<'[]')" ""

expect_eq "decision: 7 (przegląd sent the issue back once) -> continue" "$(dec 7 1 5 false)" "continue"
expect_eq "decision: 7 at the limit -> stop-limit" "$(dec 7 5 5 false)" "stop-limit"

# --- Przegląd heavy (ADR 0016): verdict, action, report and cost from a stream log ---
expect_eq "verdict: OK line" "$(printf 'REVIEW: OK\n- case 1: test_x\n' | ralph_review_verdict)" "OK"
expect_eq "verdict: preamble, then a bolded FAIL" "$(printf 'Checked.\n**REVIEW: FAIL**\n- gap\n' | ralph_review_verdict)" "FAIL"
expect_eq "verdict: first verdict line wins" "$(printf 'REVIEW: FAIL\nREVIEW: OK\n' | ralph_review_verdict)" "FAIL"
expect_eq "verdict: OKAY is not OK" "$(printf 'REVIEW: OKAY\n' | ralph_review_verdict)" ""
expect_eq "verdict: mid-line mention is not a verdict" "$(printf 'I would say REVIEW: OK\n' | ralph_review_verdict)" ""
expect_eq "verdict: none" "$(printf 'no verdict here\n' | ralph_review_verdict)" ""
expect_eq "review action: OK -> ok" "$(ralph_review_action OK 0)" "ok"
expect_eq "review action: first FAIL -> retry" "$(ralph_review_action FAIL 0)" "retry"
expect_eq "review action: second FAIL -> stop" "$(ralph_review_action FAIL 1)" "stop"
expect_eq "review action: OK after a FAIL -> ok" "$(ralph_review_action OK 1)" "ok"
expect_eq "review action: no verdict -> error" "$(ralph_review_action '' 0)" "error"

review_log=$(mktemp)
cat > "$review_log" <<'JSONL'
{"type":"system","subtype":"init","session_id":"s1"}
{"type":"result","is_error":false,"num_turns":3,"result":"first\nREVIEW: FAIL","total_cost_usd":0.1234}
not json
{"type":"result","is_error":false,"num_turns":1,"result":"REVIEW: OK\n- case: test_a","total_cost_usd":0.4567}
{"type":"result","is_error":true,"num_turns":1,"result":"limit","total_cost_usd":0.4567}
JSONL
expect_eq "last report (Claude): last non-error result" "$(ralph_last_report "$review_log")" "REVIEW: OK
- case: test_a"
expect_eq "run cost (Claude): max total_cost_usd, rounded" "$(ralph_run_cost "$review_log")" '$0.46'
printf '%s\n' '{"type":"result","result":"x"}' > "$review_log"
expect_eq "run cost (Claude): no cost data -> empty" "$(ralph_run_cost "$review_log")" ""
rm -f "$review_log"

# ralph_heavy_review end to end, with the worker and gh stubbed in this shell: what it does on
# GitHub for each verdict, and the exit code it hands back to once.sh.
review_case() {
  # Not `local report`: ralph_heavy_review has locals of that name, which the stubs would see.
  local rc_report="$1" rc_prior="$2"
  (
    SCRIPT_DIR="$SCRIPT_DIR/.."
    gh_calls=$(mktemp)
    ralph_run_worker() {
      RALPH_LAST_LOG=$(mktemp)
      jq -c -n --arg r "$rc_report" '{type:"result",is_error:false,num_turns:2,result:$r,total_cost_usd:0.2}' > "$RALPH_LAST_LOG"
    }
    gh() {
      if [ "$1" = api ]; then
        if [ "$rc_prior" -gt 0 ]; then jq -c -n --arg m "$RALPH_REVIEW_FAIL_MARKER" '[{body: ($m + "\nold")}]'; else echo '[]'; fi
      else
        echo "$1 $2 $3" >> "$gh_calls"; printf '%s\n' "$*" >> "$gh_calls.full"
      fi
    }
    ralph_heavy_review 12 abc123 "## Issue #12: t" >/dev/null
    printf '%s|' "${RALPH_REVIEW_EXIT:-none}"
    tr '\n' ';' < "$gh_calls"
    grep -q -F "$RALPH_REVIEW_FAIL_MARKER" "$gh_calls.full" && printf 'marker'
    rm -f "$gh_calls" "$gh_calls.full"
  )
}
notes_case() {
  (
    gh() { jq -c -n --arg m "$RALPH_REVIEW_FAIL_MARKER" '[{body: ($m + "\nfirst")}, {body: "other"}, {body: ($m + "\nsecond\n- a")}]'; }
    printf '%s|%s' "$(ralph_review_notes 5)" "$(ralph_review_fail_count 5)"
  )
}
expect_eq "review notes: the latest failed przegląd, marker stripped; count of failures" "$(notes_case)" "second
- a|2"
expect_eq "heavy review: OK -> accepted, one comment" "$(review_case 'REVIEW: OK' 0)" "none|issue comment 12;"
expect_eq "heavy review: first FAIL -> reopen + label + marked comment, retry code" \
  "$(review_case $'REVIEW: FAIL\n- gap' 0)" "7|issue reopen 12;issue edit 12;issue comment 12;marker"
expect_eq "heavy review: second FAIL -> reopen, AFK-failed code" \
  "$(review_case $'REVIEW: FAIL\n- gap' 1)" "3|issue reopen 12;issue edit 12;issue comment 12;marker"
expect_eq "heavy review: no verdict -> reopen without the marker, error code" \
  "$(review_case 'I could not decide' 0)" "1|issue reopen 12;issue edit 12;issue comment 12;"

# --- Bramka uruchamiana przez pętlę po zamkniętym issue (ADR 0018) ---
expect_eq "gate action: green -> ok" "$(ralph_gate_action 0 0)" "ok"
expect_eq "gate action: green after an earlier red -> ok" "$(ralph_gate_action 0 1)" "ok"
expect_eq "gate action: first red -> retry" "$(ralph_gate_action 1 0)" "retry"
expect_eq "gate action: second red -> stop" "$(ralph_gate_action 2 1)" "stop"

# --- Niestabilny test: nazwa i rodzic (czyste funkcje) ---
expect_eq "flaky name: TAP not ok" "$(ralph_flaky_test_name <<<$'ok 1 - a\nnot ok 2 - zapis pliku')" "zapis pliku"
expect_eq "flaky name: ✗ line (this repo's expect_eq)" "$(ralph_flaky_test_name <<<$'✓ a\n✗ gate: red')" "gate: red"
expect_eq "flaky name: go --- FAIL" "$(ralph_flaky_test_name <<<$'--- FAIL: TestFoo (0.01s)')" "TestFoo"
expect_eq "flaky name: FAILED pytest id" "$(ralph_flaky_test_name <<<$'FAILED tests/a.py::test_x - boom')" "tests/a.py::test_x - boom"
expect_eq "flaky name: first match wins" "$(ralph_flaky_test_name <<<$'not ok 1 - one\nnot ok 2 - two')" "one"
expect_eq "flaky name: unreadable output -> nothing" "$(ralph_flaky_test_name <<<$'boom\nexit 1' || true)" ""
expect_eq "flaky parent: test file changed in the epic -> epic" \
  "$(ralph_flaky_parent 45 $'README.md\nralph/test/lib.test.sh' <<<'FAIL in ralph/test/lib.test.sh line 3')" "45"
expect_eq "flaky parent: ./ and absolute prefixes still match" \
  "$(ralph_flaky_parent 45 $'ralph/test/lib.test.sh' <<<'/work/repo/ralph/test/lib.test.sh: failed')" "45"
expect_eq "flaky parent: test file not changed in the epic -> no parent" \
  "$(ralph_flaky_parent 45 $'README.md' <<<'FAIL ralph/test/lib.test.sh')" ""
expect_eq "flaky parent: output names no test file -> no parent" \
  "$(ralph_flaky_parent 45 $'ralph/test/lib.test.sh' <<<'boom')" ""
expect_eq "flaky parent: issue without an epic -> no parent" \
  "$(ralph_flaky_parent '' $'ralph/test/lib.test.sh' <<<'ralph/test/lib.test.sh')" ""
expect_eq "flaky parent: no changed files -> no parent" \
  "$(ralph_flaky_parent 45 '' <<<'ralph/test/lib.test.sh')" ""

gate_tail_file=$(mktemp)
seq 1 100000 > "$gate_tail_file"
gate_tail_out=$(ralph_gate_tail "$gate_tail_file")
expect_eq "gate tail: bounded in size, ends with the last line" \
  "$([ "${#gate_tail_out}" -le 8000 ] && tail -1 <<<"$gate_tail_out")" "100000"
expect_eq "gate tail: short output kept whole" "$(printf 'a\nb\n' > "$gate_tail_file"; ralph_gate_tail "$gate_tail_file")" "a
b"
rm -f "$gate_tail_file"

gate_comments_case() {
  (
    gh() { jq -c -n --arg g "$RALPH_GATE_FAIL_MARKER" --arg r "$RALPH_REVIEW_FAIL_MARKER" \
      '[{body: ($g + "\nbramka")}, {body: ($r + "\nprzegląd")}, {body: "other"}, {body: ($g + "\nbramka 2")}]'; }
    printf '%s|%s' "$(ralph_gate_fail_count 5)" "$(ralph_review_fail_count 5)"
  )
}
expect_eq "gate failure markers and przegląd markers are counted apart" "$(gate_comments_case)" "2|1"

# ralph_verify_closed end to end in a throwaway repo whose CLAUDE.md declares the gate; gh and
# the heavy review are stubs. $1: gate command (empty = section without the line), $2: earlier
# gate failures on the issue ("keep" = the comments the previous call left: a second run on the
# same GitHub state), $3: issue state, $4: mode, $5: complexity, $6: earlier przegląd failures.
# Prints "<RALPH_GATE_EXIT or none>|<review run?>|<gh calls>|<marker>"; the gate's own runs are
# appended to $GATE_RAN, the full gh arguments land in $GATE_FULL. The stub keeps comments like
# GitHub: `gh issue comment` appends to $GATE_COMMENTS, `gh api .../comments` lists them — so a
# count taken after the run's own comment would see it.
export GATE_RAN; GATE_RAN=$(mktemp)
GATE_FULL=$(mktemp)
GATE_COMMENTS=$(mktemp)
gate_case() {
  local g_cmd="$1" g_prior="$2" g_state="${3:-closed}" g_mode="${4:-afk}" g_cx="${5:-normal}" g_review_prior="${6:-0}" i
  : > "$GATE_RAN"; : > "$GATE_FULL"
  if [ "$g_prior" != keep ]; then
    : > "$GATE_COMMENTS"
    for ((i = 0; i < g_prior; i++)); do jq -c -n --arg b "$RALPH_GATE_FAIL_MARKER"$'\nold' '{body: $b}' >> "$GATE_COMMENTS"; done
    for ((i = 0; i < g_review_prior; i++)); do jq -c -n --arg b "$RALPH_REVIEW_FAIL_MARKER"$'\nold' '{body: $b}' >> "$GATE_COMMENTS"; done
  fi
  (
    # once.sh runs without pipefail; a gate exit code lost in a pipe must fail here as it would there.
    set +o pipefail
    repo=$(mktemp -d); cd "$repo" && git init -q
    if [ -n "$g_cmd" ]; then printf '# T\n\n## Ralph\n\nralph-gate: %s\n' "$g_cmd" > CLAUDE.md
    else printf '# T\n\n## Ralph\n\nbez linii bramki\n' > CLAUDE.md; fi
    if [ -n "${GATE_EPIC_FILE:-}" ]; then
      printf 'ralph-base-branch: main\n' >> CLAUDE.md
      git add -A && git -c user.email=t@t -c user.name=t commit -q -m base && git branch -M main
      git checkout -q -b epic/45 && mkdir -p t && echo x > "$GATE_EPIC_FILE" && git add -A \
        && git -c user.email=t@t -c user.name=t commit -q -m epic && git checkout -q main
    fi
    gh_calls=$(mktemp); reviewed=no
    gh() {
      if [ "$1 $2" = "issue view" ]; then echo "$g_state"
      elif [ "$1" = api ] && [[ "$2" == */parent ]]; then
        if [ -n "${GATE_PARENT:-}" ]; then echo "$GATE_PARENT"; else echo '{"status":"404"}'; return 1; fi
      elif [ "$1" = api ]; then jq -s -c . "$GATE_COMMENTS"
      else
        echo "$1 $2 $3" >> "$gh_calls"; printf '%s\n' "$*" >> "$GATE_FULL"
        case "$1 $2" in
          "issue reopen") g_state=open ;;
          "issue comment")
            local body=""
            while [ $# -gt 0 ]; do if [ "$1" = --body ]; then body="${2:-}"; fi; shift; done
            jq -c -n --arg b "$body" '{body: $b}' >> "$GATE_COMMENTS" ;;
        esac
      fi
    }
    ralph_heavy_review() { reviewed=yes; }
    ralph_verify_closed 12 "$g_mode" "$g_cx" abc123 "## Issue #12: t" >/dev/null
    printf '%s|%s|' "${RALPH_GATE_EXIT:-none}" "$reviewed"
    tr '\n' ';' < "$gh_calls"
    grep -q -F "$RALPH_GATE_FAIL_MARKER" "$GATE_FULL" && printf '|marker'
    rm -rf "$repo" "$gh_calls"
  )
}
ran() { grep -c ran "$GATE_RAN" | tr -d ' '; }

expect_eq "gate: AFK closes a plain issue, gate green -> nothing changes, gate ran once" \
  "$(gate_case 'echo ran >> "$GATE_RAN"' 0)|$(ran)" "none|no||1"
expect_eq "gate: red -> reopen + label + marked comment, retry code (7)" \
  "$(gate_case 'echo ran >> "$GATE_RAN"; exit 1' 0)" "7|no|issue reopen 12;issue edit 12;issue comment 12;|marker"
expect_eq "gate: red label is ready-for-agent" "$(grep -c 'issue edit 12 --add-label ready-for-agent' "$GATE_FULL")" "1"
expect_eq "gate: second red on the same issue -> reopen, AFK-failed code (3)" \
  "$(gate_case 'exit 1' 1)" "3|no|issue reopen 12;issue edit 12;issue comment 12;|marker"
expect_eq "gate: przegląd heavy markers are not gate failures (first red is still a retry)" \
  "$(gate_case 'exit 1' 0 closed afk heavy 1 | cut -d'|' -f1)" "7"
expect_eq "gate: the issue was left open by the run -> gate not run" \
  "$(gate_case 'echo ran >> "$GATE_RAN"' 0 open)|$(ran)" "none|no||0"
expect_eq "gate: heavy issue, gate red -> przegląd heavy never runs" \
  "$(gate_case 'exit 1' 0 closed afk heavy | cut -d'|' -f1-2)" "7|no"
expect_eq "gate: heavy issue, gate green -> przegląd heavy runs" \
  "$(gate_case 'true' 0 closed afk heavy | cut -d'|' -f1-2)" "none|yes"
expect_eq "gate: HITL session closed a plain issue -> gate runs the same" \
  "$(gate_case 'echo ran >> "$GATE_RAN"' 0 closed hitl)|$(ran)" "none|no||1"
expect_eq "gate: HITL session, red -> reopened like after AFK" \
  "$(gate_case 'exit 1' 0 closed hitl | cut -d'|' -f1)" "7"
expect_eq "gate: HITL closed a heavy issue, gate green -> no przegląd (a human was there)" \
  "$(gate_case 'true' 0 closed hitl heavy | cut -d'|' -f1-2)" "none|no"
expect_eq "gate: nonzero code survives the output going to a log (exit 3 after output)" \
  "$(gate_case 'echo some output; exit 3' 0 | cut -d'|' -f1)" "7"
expect_eq "gate: multi-step a && b, the second fails -> red" \
  "$(gate_case 'true && false' 0 | cut -d'|' -f1)" "7"
expect_eq "gate: multi-step a && b, the first fails -> b never runs, red" \
  "$(gate_case 'false && echo ran >> "$GATE_RAN"' 0 | cut -d'|' -f1)|$(ran)" "7|0"
expect_eq "gate: no ralph-gate: line -> error code (1), no reopen, no przegląd, not green" \
  "$(gate_case '' 0 closed afk heavy)" "1|no|"
expect_eq "gate: red comment carries the output tail and the log path" \
  "$(gate_case 'echo ogon-$((6*7)); exit 1' 0 >/dev/null; grep -c 'ogon-42' "$GATE_FULL")|$(grep -c 'ralph-logs/.*-gate-12.log' "$GATE_FULL")" "1|1"
gate_case 'seq 1 200000; exit 1' 0 >/dev/null
expect_eq "gate: very long output -> the comment fits GitHub's limit and ends with the last line" \
  "$([ "$(wc -c < "$GATE_FULL")" -lt 60000 ] && grep -c '^200000$' "$GATE_FULL")" "1"
# The count is taken before the run's own comment: the first red sees no marker (7), and the next
# one, on the GitHub state the first left behind, sees exactly one (3).
expect_eq "gate: first red -> 7, the next red on the state it left behind -> 3" \
  "$(gate_case 'exit 1' 0 | cut -d'|' -f1)|$(gate_case 'exit 1' keep | cut -d'|' -f1)|$(gate_case 'exit 1' keep | cut -d'|' -f1)" "7|3|3"
expect_eq "gate: the first red's comment is on the issue, so a green run afterwards stays green" \
  "$(gate_case 'exit 1' 0 >/dev/null; gate_case 'true' keep | cut -d'|' -f1)" "none"

# Niestabilny test: czerwona → (jedno powtórzenie) → zielona. Stateful gate command: red on its
# first run, green after (the state file is per case).
flaky_cmd() { echo "f=$1; if [ -f \$f ]; then exit 0; else touch \$f; echo 'not ok 3 - flaky thing' ; echo t/x.test.sh; exit 1; fi"; }
flaky_case() { local st; st=$(mktemp -u); gate_case "$(flaky_cmd "$st")" "${1:-0}" "${@:2}"; rm -f "$st"; }
expect_eq "flaky: red then green -> run passes (no exit code), no reopen, issue created" \
  "$(flaky_case 0 | cut -d'|' -f1)|$(grep -c '^issue create' "$GATE_FULL")|$(grep -c 'issue reopen' "$GATE_FULL")" "none|1|0"
expect_eq "flaky: the issue carries complexity:normal and ready-for-agent" \
  "$(grep -c -- '--label complexity:normal --label ready-for-agent' "$GATE_FULL")" "1"
expect_eq "flaky: title names the test, body has the red output and the log path" \
  "$(grep -c '\[ISSUE\] Niestabilny test: flaky thing' "$GATE_FULL")|$(grep -c 'ralph-logs/.*-gate-12.log' "$GATE_FULL")|$(grep -c '^not ok 3' "$GATE_FULL")" "1|1|1"
expect_eq "flaky: no epic -> no parent" "$(grep -c -- '--parent' "$GATE_FULL")" "0"
expect_eq "flaky: the gate is not red-commented (no gate marker)" "$(grep -c -F "$RALPH_GATE_FAIL_MARKER" "$GATE_FULL")" "0"
expect_eq "flaky: heavy issue, flaky gate -> run counts as green, przegląd runs" \
  "$(flaky_case 0 closed afk heavy | cut -d'|' -f1-2)" "none|yes"
expect_eq "flaky: red then red -> as before (first red = 7, reopened, no flaky issue)" \
  "$(gate_case 'exit 1' 0 | cut -d'|' -f1)|$(grep -c '^issue create' "$GATE_FULL")" "7|0"
expect_eq "flaky: red then red on the second failure -> 3" \
  "$(gate_case 'exit 1' 1 | cut -d'|' -f1)" "3"
expect_eq "flaky: the gate is repeated exactly once, never until green" \
  "$(gate_case 'echo ran >> "$GATE_RAN"; exit 1' 0 >/dev/null; ran)" "2"
expect_eq "flaky: a green gate is not repeated" \
  "$(gate_case 'echo ran >> "$GATE_RAN"' 0 >/dev/null; ran)" "1"
expect_eq "flaky: epic changed the test file named in the output -> --parent epic" \
  "$(GATE_PARENT=45 GATE_EPIC_FILE=t/x.test.sh flaky_case 0 >/dev/null; grep -c -- '--parent 45' "$GATE_FULL")" "1"
expect_eq "flaky: epic did not change that file -> no parent" \
  "$(GATE_PARENT=45 GATE_EPIC_FILE=t/other.sh flaky_case 0 >/dev/null; grep -c -- '--parent' "$GATE_FULL")" "0"
rm -f "$GATE_RAN" "$GATE_FULL" "$GATE_COMMENTS"

# The sequence once.sh runs after the worker (ralph_after_worker): bramka -> przegląd heavy ->
# marking epics -> verdict. Issue 12 is the only sub-issue of epic 45. gh is a stub with state:
# reopen reopens, issue edit/comment are recorded; every call that matters lands in $SEQ_CALLS
# in order (gate, review, reopen, ready, comment, label-epic, comment-epic, worker).
seq_gh() {
  case "$*" in
    "issue view 12 --json state"*) echo "$st12" ;;
    "issue view 12 --json labels"*) echo "$ready12" ;;
    "issue view 45 --json labels"*) echo false ;;
    "issue list --state open"*) echo 45 ;;
    "api --paginate repos/{owner}/{repo}/issues/45/sub_issues") printf '[{"number":12,"state":"%s"}]\n' "$st12" ;;
    "api --paginate repos/{owner}/{repo}/issues/12/comments") jq -s -c . "$SEQ_COMMENTS" ;;
    "issue reopen 12") st12=open; echo reopen >> "$SEQ_CALLS" ;;
    "issue edit 12 --add-label ready-for-agent") ready12=true; echo ready >> "$SEQ_CALLS" ;;
    "issue edit 45 --add-label needs-human-test") echo label-epic >> "$SEQ_CALLS" ;;
    "issue comment 45 "*) echo comment-epic >> "$SEQ_CALLS" ;;
    "issue comment 12 --body "*)
      echo comment >> "$SEQ_CALLS"
      jq -c -n --arg b "${*#issue comment 12 --body }" '{body: $b}' >> "$SEQ_COMMENTS" ;;
  esac
}
# $1: gate command (empty = section without the line); the command records itself as "gate".
seq_repo() {
  repo=$(mktemp -d); cd "$repo" && git init -q
  if [ -n "$1" ]; then printf '# T\n\n## Ralph\n\nralph-gate: %s\n' "$1" > CLAUDE.md
  else printf '# T\n\n## Ralph\n\nbez linii bramki\n' > CLAUDE.md; fi
  export SEQ_CALLS SEQ_COMMENTS; SEQ_CALLS=$(mktemp); SEQ_COMMENTS=$(mktemp)
  gh() { seq_gh "$@"; }
}
GATE_OK='echo gate >> "$SEQ_CALLS"'
GATE_RED='echo gate >> "$SEQ_CALLS"; exit 1'
# $1: gate command, $2: complexity, $3: review stub (ok|fail), $4: earlier red bramki.
# Prints "<exit code>|<calls>".
after_worker_case() {
  local a_cmd="$1" a_cx="${2:-normal}" a_review="${3:-ok}" a_prior="${4:-0}" i rc
  (
    seq_repo "$a_cmd"
    st12=closed; ready12=false
    for ((i = 0; i < a_prior; i++)); do jq -c -n --arg b "$RALPH_GATE_FAIL_MARKER" '{body: $b}' >> "$SEQ_COMMENTS"; done
    ralph_heavy_review() {
      echo review >> "$SEQ_CALLS"
      if [ "$a_review" = fail ]; then st12=open; RALPH_REVIEW_EXIT=$RALPH_EXIT_REVIEW_RETRY; fi
    }
    ( ralph_after_worker 12 afk "$a_cx" abc123 "## Issue #12: t" ) >/dev/null 2>&1
    rc=$?
    printf '%s|%s' "$rc" "$(paste -sd, "$SEQ_CALLS")"
    rm -rf "$repo" "$SEQ_CALLS" "$SEQ_COMMENTS"
  )
}
expect_eq "after worker: last sub-issue closed, gate green -> exit 0, the epic is NOT labelled (only the weryfikacja does)" \
  "$(after_worker_case "$GATE_OK")" "0|gate"
expect_eq "after worker: last sub-issue closed, gate red -> exit 7, issue reopened, epic NOT marked" \
  "$(after_worker_case "$GATE_RED")" "7|gate,gate,reopen,ready,comment"
expect_eq "after worker: second red on the same issue -> exit 3, epic NOT marked" \
  "$(after_worker_case "$GATE_RED" normal ok 1)" "3|gate,gate,reopen,ready,comment"
expect_eq "after worker: no ralph-gate: line -> exit 1, no gate, epic NOT marked" \
  "$(after_worker_case '')" "1|"
expect_eq "after worker: no ralph-gate: line on a heavy issue -> exit 1, no review, epic NOT marked" \
  "$(after_worker_case '' heavy)" "1|"
expect_eq "after worker: heavy, gate red -> no przegląd, exit 7, epic NOT marked" \
  "$(after_worker_case "$GATE_RED" heavy)" "7|gate,gate,reopen,ready,comment"
expect_eq "after worker: heavy, gate green, przegląd OK -> gate, then przegląd, epic NOT labelled" \
  "$(after_worker_case "$GATE_OK" heavy)" "0|gate,review"
expect_eq "after worker: heavy, gate green, przegląd FAIL -> exit 7, epic NOT marked" \
  "$(after_worker_case "$GATE_OK" heavy fail)" "7|gate,review"

# --- ralph-epic: decision for the weryfikacja's exit codes, the pick and the limit ---
expect_eq "decision: 9 (weryfikacja handed the epic to acceptance) -> stop-ready, even without the label read yet" \
  "$(dec 9 1 5 false)" "stop-ready"
expect_eq "decision: 9 at the limit -> still stop-ready (not stop-limit)" "$(dec 9 5 5 false)" "stop-ready"
expect_eq "decision: 7 from the weryfikacja (Poprawka opened) -> continue" "$(dec 7 3 5 false)" "continue"
expect_eq "decision: weryfikacja counted as an iteration -> 7 at the limit -> stop-limit, no label" "$(dec 7 5 5 false)" "stop-limit"
expect_eq "limit: an epic with nothing open still has room for weryfikacja, Poprawka and weryfikacja" "$(ralph_epic_iteration_limit 0)" "3"
E_VER='[{"number":10,"started":true,"open":[12],"state":"in-progress"},{"number":20,"started":false,"open":[21],"state":"in-progress"},{"number":30,"started":true,"open":[],"state":"to-verify"},{"number":40,"started":true,"open":[],"state":"awaiting"},{"number":50,"started":false,"open":[],"state":"unplanned"}]'
expect_eq "pick epic: a started epic waiting for weryfikacja goes before another with open sub-issues" \
  "$(ralph_pick_epic <<<"$E_VER")" "30"
expect_eq "pick epic: only to-verify -> that one" \
  "$(ralph_pick_epic <<<'[{"number":30,"started":true,"open":[],"state":"to-verify"}]')" "30"
expect_eq "pick epic: awaiting acceptance and unplanned epics are never picked" \
  "$(ralph_pick_epic <<<'[{"number":40,"started":true,"open":[],"state":"awaiting"},{"number":50,"started":false,"open":[],"state":"unplanned"}]')" ""
expect_eq "pick epic: lowest of several to-verify" \
  "$(ralph_pick_epic <<<'[{"number":9,"started":true,"open":[],"state":"to-verify"},{"number":4,"started":true,"open":[],"state":"to-verify"}]')" "4"

# ralph_epics_json: the state of every open [PRD] from its sub-issues and its label.
epics_gh() {
  case "$*" in
    "issue list --state open"*) printf '10\n20\n30\n40\n' ;;
    "api --paginate repos/{owner}/{repo}/issues/10/sub_issues") echo '[{"number":11,"state":"closed"},{"number":12,"state":"open"}]' ;;
    "api --paginate repos/{owner}/{repo}/issues/20/sub_issues") echo '[{"number":21,"state":"closed"},{"number":22,"state":"closed"}]' ;;
    "api --paginate repos/{owner}/{repo}/issues/30/sub_issues") echo '[]' ;;
    "api --paginate repos/{owner}/{repo}/issues/40/sub_issues") echo '[{"number":41,"state":"closed"}]' ;;
    "issue view 40 --json labels"*) echo true ;;
    "issue view "*" --json labels"*) echo false ;;
  esac
}
epics_state=$( gh() { epics_gh "$@"; }; ralph_epics_json | jq -r 'map("\(.number)=\(.state)") | join(",")' )
expect_eq "epics json: in-progress, to-verify, unplanned (no sub-issues), awaiting (label)" \
  "$epics_state" "10=in-progress,20=to-verify,30=unplanned,40=awaiting"
expect_eq "epics json: started and open lists kept" \
  "$( gh() { epics_gh "$@"; }; ralph_epics_json | jq -c '.[0] | [.started, .open]')" '[true,[12]]'
expect_eq "epics json: a label GitHub cannot answer about -> awaiting, never to-verify" \
  "$( gh() { case "$*" in "issue list --state open"*) echo 20 ;; "issue view"*) return 1 ;; *) epics_gh "$@" ;; esac; }; ralph_epics_json | jq -r '.[0].state')" "awaiting"

# ralph_verify_epic end to end in a throwaway repo whose CLAUDE.md declares the gate; gh is a stub
# that keeps the epic's comments like GitHub. $1: gate command (empty = section without the line),
# $2: the epic's earlier comments (one body per line, \n for newlines), $3: failing gh call
# (comments|marker|create|label, or none). Prints "<RALPH_VERIFY_EXIT>|<calls>"; the full text of
# the comments written lands in $VERIFY_OUT, the issue created in $VERIFY_CREATE.
VERIFY_BODY=$'## Solution\nx\n\n## Jak odebrać\n\n1. Otwórz stronę\n2. Kliknij OK\n\n## Out of Scope\nnic'
verify_gh() {
  case "$*" in
    "api --paginate repos/{owner}/{repo}/issues/45/comments")
      [ "$v_fail" = comments ] && return 1
      jq -s -c . "$V_COMMENTS" ;;
    "issue comment 45 --body "*)
      case "${*#issue comment 45 --body }" in
        *"$RALPH_VERIFY_MARKER"*) [ "$v_fail" = marker ] && return 1; echo marker >> "$V_CALLS" ;;
        *) echo list >> "$V_CALLS" ;;
      esac
      jq -c -n --arg b "${*#issue comment 45 --body }" '{body: $b}' >> "$V_COMMENTS"
      printf '%s\n----\n' "${*#issue comment 45 --body }" >> "$VERIFY_OUT" ;;
    "issue edit 45 --add-label needs-human-test") [ "$v_fail" = label ] && return 1; echo label >> "$V_CALLS" ;;
    "issue view 45 --json body"*) printf '%s\n' "$VERIFY_BODY" ;;
    "issue view 45 --json number,title,body"*) printf '## Epic #45: [PRD] Testowy\n\n%s\n' "$VERIFY_BODY" ;;
    "issue view 45 --json state"*) echo open ;;
    "issue view 45 --json labels"*) echo false ;;
    "issue list "*) printf '%s\n' "${V_EXISTING:-}" ;;
    "label create"*) ;;
    "issue create "*)
      [ "$v_fail" = create ] && return 1
      echo create >> "$V_CALLS"; printf '%s\n====\n' "$*" >> "$VERIFY_CREATE" ;;
  esac
}
# The weryfikator, stubbed where the real one would run through the usage limit: plays the reply in
# $V_REPORT_TEXT as a finished run with session v-sess-1 and a cost; records its prompt (arg 3) and
# the session it was asked to resume (arg 7). V_STOP=limit|resume-failed plays a stopped run.
V_REPORT_EMPTY=$'Nic nie znalazłem.\n\n```json\n{"findings": [], "items": []}\n```'
V_REPORT_TEXT="$V_REPORT_EMPTY"
verify_stub_worker() {
  echo verifier >> "$V_CALLS"
  printf '%s\n' "$3" > "$VERIFY_PROMPT"
  printf '%s\n' "${7:-}" > "$VERIFY_RESUMED"
  RALPH_LIMIT_STOP="${V_STOP:-}"
  [ -z "${V_STOP:-}" ] || return 1
  RALPH_LAST_LOG=$(mktemp)
  {
    echo '{"type":"system","subtype":"init","session_id":"v-sess-1"}'
    jq -c -n --arg r "$V_REPORT_TEXT" '{type:"result",is_error:false,num_turns:4,result:$r,total_cost_usd:1.234,session_id:"v-sess-1"}'
  } > "$RALPH_LAST_LOG"
}
verify_case() {
  local v_cmd="$1" v_prior="${2:-}" v_fail="${3:-none}" line
  (
    repo=$(mktemp -d); cd "$repo" && git init -q
    if [ -n "$v_cmd" ]; then printf '# T\n\n## Ralph\n\nralph-gate: %s\n' "$v_cmd" > CLAUDE.md
    else printf '# T\n\n## Ralph\n\nbez linii bramki\n' > CLAUDE.md; fi
    export V_CALLS V_COMMENTS VERIFY_OUT VERIFY_CREATE VERIFY_PROMPT VERIFY_RESUMED
    V_CALLS=$(mktemp); V_COMMENTS=$(mktemp); VERIFY_OUT=$(mktemp); VERIFY_CREATE=$(mktemp)
    VERIFY_PROMPT=$(mktemp); VERIFY_RESUMED=$(mktemp)
    SCRIPT_DIR="$SCRIPT_DIR/.."
    while IFS= read -r line; do
      [ -n "$line" ] && jq -c -n --arg b "$(printf '%b' "$line")" '{body: $b}' >> "$V_COMMENTS"
    done <<<"$v_prior"
    gh() { verify_gh "$@"; }
    ralph_run_worker_through_limit() { verify_stub_worker "$@"; }
    ralph_verify_epic 45 >"$repo/stdout" 2>&1
    printf '%s|%s' "$RALPH_VERIFY_EXIT" "$(paste -sd, "$V_CALLS")"
    cp "$VERIFY_OUT" /tmp/ralph-verify-out.$$; cp "$VERIFY_CREATE" /tmp/ralph-verify-create.$$; cp "$repo/stdout" /tmp/ralph-verify-stdout.$$
    cp "$VERIFY_PROMPT" /tmp/ralph-verify-prompt.$$
    rm -rf "$repo" "$V_CALLS" "$V_COMMENTS" "$VERIFY_OUT" "$VERIFY_CREATE" "$VERIFY_PROMPT" "$VERIFY_RESUMED"
  )
}
V_GATE_OK='echo gate >> "$V_CALLS"; echo "wszystko zielone"'
V_GATE_RED='echo gate >> "$V_CALLS"; echo "FAIL: test d""ziwny"; exit 3'
verify_artifacts() { # reads the files verify_case left (named by the subshell's pid) -> sets v_out, v_create, v_stdout
  v_out=$(cat /tmp/ralph-verify-out.* 2>/dev/null); v_create=$(cat /tmp/ralph-verify-create.* 2>/dev/null); v_stdout=$(cat /tmp/ralph-verify-stdout.* 2>/dev/null)
  v_prompt=$(cat /tmp/ralph-verify-prompt.* 2>/dev/null)
  rm -f /tmp/ralph-verify-out.* /tmp/ralph-verify-create.* /tmp/ralph-verify-stdout.* /tmp/ralph-verify-prompt.*
}

expect_eq "verify: gate green, round 1 -> marker, label, acceptance list; exit 9 (do odbioru)" \
  "$(verify_case "$V_GATE_OK")" "9|gate,verifier,marker,label,list"
verify_artifacts
expect_eq "  the list holds the Jak odebrać steps, not the rest of the epic body" \
  "$(grep -c '1. Otwórz stronę' <<<"$v_out")|$(grep -c 'Out of Scope' <<<"$v_out")" "1|0"
expect_eq "  the list holds the command with /odbior <nr>, and so does the screen" \
  "$(grep -c 'claude "/odbior 45"' <<<"$v_out")|$(grep -c 'claude "/odbior 45"' <<<"$v_stdout")" "1|1"
expect_eq "  the command ends the screen output" "$(tail -1 <<<"$v_stdout" | grep -c 'claude "/odbior 45"')" "1"
expect_eq "  the round marker comment says round 1" "$(grep -c 'runda 1' <<<"$v_out")" "1"

expect_eq "verify: gate red, round 1 -> marker, one Poprawka sub-issue, NO label; exit 7 (ralph-epic goes on)" \
  "$(verify_case "$V_GATE_RED")" "7|gate,verifier,marker,create"
verify_artifacts
expect_eq "  Poprawka: title, ready-for-agent, complexity:normal, parent = the epic" \
  "$(grep -c -e '--title \[ISSUE\] Poprawka: czerwona bramka' <<<"$v_create")|$(grep -c -e '--label ready-for-agent' <<<"$v_create")|$(grep -c -e '--label complexity:normal' <<<"$v_create")|$(grep -c -e '--parent 45' <<<"$v_create")" "1|1|1|1"
expect_eq "  Poprawka: the tail of the output and the log path" \
  "$(grep -c 'FAIL: test dziwny' <<<"$v_create")|$(grep -c 'weryfikacja-45.log' <<<"$v_create")" "1|1"
expect_eq "  the epic gets no acceptance list" "$(grep -c 'Lista odbioru' <<<"$v_out")" "0"

expect_eq "verify: gate red, round 2 (one earlier round) -> label with the red gate on top of the list; exit 9; no new Poprawka" \
  "$(verify_case "$V_GATE_RED" "$RALPH_VERIFY_MARKER runda 1")" "9|gate,verifier,marker,label,list"
verify_artifacts
expect_eq "  the red gate is listed before the steps" \
  "$(grep -nE 'Nierozwiązane|Kroki' <<<"$v_out" | cut -d: -f2 | paste -sd, -)" "### Nierozwiązane,### Kroki (## Jak odebrać)"
expect_eq "  and names the failing output" "$(grep -c 'FAIL: test dziwny' <<<"$v_out")" "1"
expect_eq "  the round marker comment says round 2" "$(grep -c 'runda 2' <<<"$v_out")" "1"

expect_eq "verify: acceptance marker after two rounds, then a Poprawka -> red again is round 1: Poprawka again, no label" \
  "$(verify_case "$V_GATE_RED" "$RALPH_VERIFY_MARKER 1\n$RALPH_VERIFY_MARKER 2\n$RALPH_ODBIOR_MARKER\nzamknięta Poprawka")" "7|gate,verifier,marker,create"
verify_artifacts
expect_eq "verify: gate green after a fresh acceptance marker -> round 1 marker" \
  "$(verify_case "$V_GATE_OK" "$RALPH_VERIFY_MARKER 1\n$RALPH_VERIFY_MARKER 2\n$RALPH_ODBIOR_MARKER")" "9|gate,verifier,marker,label,list"
verify_artifacts
expect_eq "  and says so" "$(grep -c 'runda 1' <<<"$v_out")" "1"

expect_eq "verify: no ralph-gate: line -> error, nothing run, nothing written" "$(verify_case '')" "1|"
verify_artifacts
expect_eq "verify: comments unreadable -> error before the gate (the round number is unknown)" \
  "$(verify_case "$V_GATE_OK" '' comments)" "1|"
verify_artifacts
expect_eq "verify: the round marker cannot be written -> error, no label and no Poprawka (it would verify forever)" \
  "$(verify_case "$V_GATE_RED" '' marker)" "1|gate,verifier"
verify_artifacts
expect_eq "verify: green, label cannot be set -> error, no acceptance list" \
  "$(verify_case "$V_GATE_OK" '' label)" "1|gate,verifier,marker"
verify_artifacts
expect_eq "verify: red, Poprawka cannot be created -> error" \
  "$(verify_case "$V_GATE_RED" '' create)" "1|gate,verifier,marker"
verify_artifacts

# --- ralph_verify_epic with the weryfikator's report (stubbed): what lands on GitHub per decision ---
V_BODY_DEV='Odchylenie: zamiast przycisku OK jest link'
expect_eq "verify (report): green gate, no findings -> exit 9; the weryfikator ran once, after the gate" \
  "$(verify_case "$V_GATE_OK")" "9|gate,verifier,marker,label,list"
verify_artifacts
expect_eq "  the list names the weryfikator's session and the epic stays free of Poprawka" \
  "$(grep -c 'claude --resume v-sess-1' <<<"$v_out")|$(grep -c 'Poprawka' <<<"$v_create")" "1|0"
expect_eq "  the round marker says who verified" "$(grep -c 'Sesja weryfikatora: v-sess-1' <<<"$v_out")" "1"
expect_eq "  the cost is on screen" "$(grep -c 'Koszt weryfikacji: \$1.23' <<<"$v_stdout")" "1"
expect_eq "  the prompt carries the epic body, the gate state and the repo's Ralph section" \
  "$(grep -c '1. Otwórz stronę' <<<"$v_prompt")|$(grep -c 'zielona' <<<"$v_prompt")|$(grep -c 'ralph-gate:' <<<"$v_prompt")" "1|1|1"
expect_eq "  the prompt carries the weryfikator's own instructions" "$(grep -c 'You are the weryfikator' <<<"$v_prompt")" "1"

V_REPORT_TEXT=$(mk_reply "{\"findings\":[$R_BLOCK_N,$R_BLOCK_H,$R_PROP,$R_REF],\"items\":[$R_ITEMS]}")
expect_eq "verify (report): round 1, green gate, two blocking + refactor + proposal -> 2 Poprawki + 1 Refaktor, no label; exit 7" \
  "$(verify_case "$V_GATE_OK")" "7|gate,verifier,marker,create,create,create"
verify_artifacts
expect_eq "  Poprawka titles carry the prefix; each is a sub-issue of the epic and ready-for-agent" \
  "$(grep -c -e '--title \[ISSUE\] Poprawka: Zamknij wyciek tenantów' <<<"$v_create")|$(grep -c -e '--title \[ISSUE\] Poprawka: Napraw naliczanie' <<<"$v_create")|$(grep -c -e '--parent 45' <<<"$v_create")" "1|1|2"
expect_eq "  complexity labels follow the report" \
  "$(grep -c -e '--label complexity:normal' <<<"$v_create")|$(grep -c -e '--label complexity:heavy' <<<"$v_create")" "2|1"
expect_eq "  the heavy one carries its case list" "$(grep -c 'Przypadki do przetestowania' <<<"$v_create")" "1"
expect_eq "  the Refaktor has no parent and does not block" \
  "$(grep -c -e '--title \[ISSUE\] Refaktor: Wydziel serwis cen' <<<"$v_create")|$(grep -v -e '--parent 45' <<<"$v_create" | grep -c -e '--title \[ISSUE\] Refaktor')" "1|1"
expect_eq "  the proposal makes no issue" "$(grep -c 'Większy przycisk' <<<"$v_create")" "0"
expect_eq "  no acceptance list yet" "$(grep -c 'Lista odbioru' <<<"$v_out")" "0"

V_EXISTING='[ISSUE] Refaktor: Wydziel serwis cen'
expect_eq "verify (report): a Refaktor already opened by an earlier round is not opened again" \
  "$(verify_case "$V_GATE_OK")" "7|gate,verifier,marker,create,create"
V_EXISTING=''
verify_artifacts

expect_eq "verify (report): red gate AND blocking findings, round 1 -> the gate's Poprawka plus the findings'" \
  "$(verify_case "$V_GATE_RED")" "7|gate,verifier,marker,create,create,create,create"
verify_artifacts
expect_eq "  both kinds of Poprawka are there" \
  "$(grep -c -e 'Poprawka: czerwona bramka' <<<"$v_create")|$(grep -c -e 'Poprawka: Zamknij wyciek' <<<"$v_create")" "1|1"

expect_eq "verify (report): round 2, blocking findings remain -> label, unresolved first on the list, no new Poprawka; exit 9" \
  "$(verify_case "$V_GATE_OK" "$RALPH_VERIFY_MARKER runda 1")" "9|gate,verifier,marker,create,label,list"
verify_artifacts
expect_eq "  the only issue opened is the Refaktor" "$(grep -c -e '--title \[ISSUE\] Poprawka' <<<"$v_create")|$(grep -c -e '--title \[ISSUE\] Refaktor' <<<"$v_create")" "0|1"
expect_eq "  the list: unresolved, steps, report parts, command" \
  "$(grep -E '^### ' <<<"$v_out" | paste -sd, -)" \
  "### Nierozwiązane,### Kroki (## Jak odebrać),### Czego bramka nie udowadnia,### Przed / po (wygląd zapowiedziany w PRD),### Propozycje do decyzji,### Odbiór"
expect_eq "  the unresolved section names both blocking findings" \
  "$(sed -n '/### Nierozwiązane/,/### Kroki/p' <<<"$v_out" | grep -c -e 'Zamknij wyciek tenantów\|Napraw naliczanie')" "2"
expect_eq "  the round marker says round 2" "$(grep -c 'runda 2' <<<"$v_out")" "1"

V_REPORT_TEXT=$(mk_reply "{\"findings\":[$R_PROP,$R_REF],\"items\":[$R_ITEMS]}")
expect_eq "verify (report): only a proposal and a refactor, round 1 -> hand over; the Refaktor is opened, the proposal only listed" \
  "$(verify_case "$V_GATE_OK")" "9|gate,verifier,marker,create,label,list"
verify_artifacts
expect_eq "  the proposal is on the list, under the decision heading" \
  "$(sed -n '/### Propozycje do decyzji/,/### Odbiór/p' <<<"$v_out" | grep -c 'Większy przycisk')" "1"
expect_eq "  nothing unresolved" "$(grep -c 'Nierozwiązane' <<<"$v_out")" "0"

V_REPORT_TEXT=$'Chyba jest dobrze, ale nie podam raportu.'
expect_eq "verify (report): unreadable report -> error; no marker, no label, no issue" \
  "$(verify_case "$V_GATE_OK")" "1|gate,verifier"
verify_artifacts
expect_eq "  says so on screen" "$(grep -c 'nieczytelny' <<<"$v_stdout")" "1"
V_REPORT_TEXT=$(mk_reply '{"findings":[{"category":"blocking","title":"t","rationale":"r"}]}')
expect_eq "verify (report): a blocking finding without complexity or criteria -> error, nothing written" \
  "$(verify_case "$V_GATE_RED")" "1|gate,verifier"
verify_artifacts

V_REPORT_TEXT="$V_REPORT_EMPTY"
V_STOP=limit
expect_eq "verify (report): a usage limit in the weryfikator -> exit 8, nothing written" \
  "$(verify_case "$V_GATE_OK")" "8|gate,verifier"
verify_artifacts
V_STOP=resume-failed
expect_eq "verify (report): the session cannot be resumed -> error" "$(verify_case "$V_GATE_OK")" "1|gate,verifier"
verify_artifacts
V_STOP=

verify_case "$V_GATE_OK" "$V_BODY_DEV"$'\n'"$RALPH_VERIFY_MARKER runda 1" >/dev/null
verify_artifacts
expect_eq "verify (report): the deviation comments of the epic reach the weryfikator, the loop's markers do not" \
  "$(grep -c 'zamiast przycisku OK' <<<"$v_prompt")|$(grep -c 'ralph-weryfikacja' <<<"$v_prompt")" "1|0"

# Wznowienie weryfikatora po limicie (ADR 0017): the ślad of phase `verify` through ralph_resume_from_trace
verify_resume_case() { # $1: report reply, $2: gate exit code in the ślad
  V_REPORT_TEXT="$1"
  (
    repo=$(mktemp -d); cd "$repo" && git init -q && git checkout -q -b epic/45
    printf '# T\n\n## Ralph\n\nralph-gate: true\n' > CLAUDE.md
    export V_CALLS V_COMMENTS VERIFY_OUT VERIFY_CREATE VERIFY_PROMPT VERIFY_RESUMED
    V_CALLS=$(mktemp); V_COMMENTS=$(mktemp); VERIFY_OUT=$(mktemp); VERIFY_CREATE=$(mktemp)
    VERIFY_PROMPT=$(mktemp); VERIFY_RESUMED=$(mktemp)
    SCRIPT_DIR="$SCRIPT_DIR/.."
    glog="$repo/gate.log"; echo "wyjście bramki" > "$glog"
    ralph_limit_trace_write runtime=claude phase=verify session=v-sess-1 model=opus effort=high label=verify-45 \
      resets_at=$(($(date +%s) - 100)) limit=five_hour branch=epic/45 issue=45 epic_gate_rc="$2" epic_round=1 epic_gate_log="$glog"
    gh() { verify_gh "$@"; }
    ralph_run_worker_through_limit() { verify_stub_worker "$@"; }
    v_fail=none
    ( ralph_resume_from_trace '' ) >"$repo/stdout" 2>&1
    printf '%s|%s|resumed=%s' "$?" "$(paste -sd, "$V_CALLS")" "$(tr -d '\n' < "$VERIFY_RESUMED")"
    cp "$VERIFY_OUT" /tmp/ralph-verify-out.$$
    rm -rf "$repo" "$V_CALLS" "$V_COMMENTS" "$VERIFY_OUT" "$VERIFY_CREATE" "$VERIFY_PROMPT" "$VERIFY_RESUMED"
  )
}
expect_eq "resume: verify phase -> the weryfikator's session is resumed, the gate is not rerun, the epic is handed over; exit 9" \
  "$(verify_resume_case "$V_REPORT_EMPTY" 0)" "9|verifier,marker,label,list|resumed=v-sess-1"
verify_artifacts
expect_eq "  the round marker keeps the ślad's round and the list names the session" \
  "$(grep -c 'runda 1' <<<"$v_out")|$(grep -c 'claude --resume v-sess-1' <<<"$v_out")" "1|1"
expect_eq "resume: verify phase, red gate in the ślad, blocking findings (round 1) -> Poprawki, exit 7" \
  "$(verify_resume_case "$(mk_reply "{\"findings\":[$R_BLOCK_N]}")" 3)" "7|verifier,marker,create,create|resumed=v-sess-1"
verify_artifacts
expect_eq "resume: verify phase with an incomplete ślad -> error, the weryfikator is not started" \
  "$(
    verify_resume_case "$V_REPORT_EMPTY" '' 
  )" "1||resumed="
verify_artifacts

# --- Limit użycia (ADR 0017) ---
LIMIT_FIXTURE="$SCRIPT_DIR/fixtures/usage-limit.jsonl"
SID=92d20c8c-b0e0-4fbc-9256-3fde3852c1e6
expect_eq "usage limit: a real stopped run -> reset and type" "$(ralph_stream_usage_limit "$LIMIT_FIXTURE")" "1791596400 five_hour"
expect_eq "usage limit: read from stdin too" "$(ralph_stream_usage_limit < "$LIMIT_FIXTURE")" "1791596400 five_hour"
expect_eq "usage limit: a normal run -> nothing" "$(ralph_stream_usage_limit <<<"$stream_fixture")" ""
expect_eq "usage limit: warnings only, run ended on another error -> nothing" \
  "$(grep -v 'usage_limit_reached\|"status":"rejected"' "$LIMIT_FIXTURE" | ralph_stream_usage_limit)" ""
expect_eq "usage limit: no runtime message, but a failed result after a rejected event -> limit" \
  "$(grep -v 'usage_limit_reached' "$LIMIT_FIXTURE" | ralph_stream_usage_limit)" "1791596400 five_hour"
expect_eq "usage limit: a rejected event followed by a successful result -> nothing" \
  "$(grep -v 'usage_limit_reached' "$LIMIT_FIXTURE" | sed 's/"is_error":true/"is_error":false/' | ralph_stream_usage_limit)" ""

expect_eq "stale ślad: worker, issue open + AFK, same branch -> fits" "$(ralph_limit_trace_stale worker open true epic/45 epic/45)" ""
expect_eq "stale ślad: worker, issue closed" "$(ralph_limit_trace_stale worker closed false epic/45 epic/45)" "issue jest już zamknięte"
expect_eq "stale ślad: worker, ready-for-agent removed" "$(ralph_limit_trace_stale worker open false epic/45 epic/45)" "issue nie ma już ready-for-agent"
expect_eq "stale ślad: another branch" "$(ralph_limit_trace_stale worker open true epic/45 dev)" "run przerwano na gałęzi epic/45, a bieżąca to dev"
expect_eq "stale ślad: review, issue closed -> fits" "$(ralph_limit_trace_stale review closed false epic/45 epic/45)" ""
expect_eq "stale ślad: review, issue reopened" "$(ralph_limit_trace_stale review open true epic/45 epic/45)" "przerwany był przegląd heavy, a issue nie jest już zamknięte"

now=$(date +%s)
expect_ok "wait for reset: a reset in the past -> go on at once" ralph_wait_for_reset $((now - 100)) five_hour
expect_fail "wait for reset: more than 6 h away -> no wait" ralph_wait_for_reset $((now + 30000)) seven_day
expect_fail "wait for reset: unknown reset -> no wait" ralph_wait_for_reset 0 five_hour
# Not `now` inside the stubs: ralph_wait_for_reset has a local of that name, which they would see.
wait_out=$(t0=$now; RALPH_LIMIT_MARGIN=0; date() { echo "$t0"; }; sleep() { echo "sleep $1"; date() { echo $((t0 + 10)); }; }; ralph_notify() { :; }; ralph_wait_for_reset $((now + 5)) five_hour)
expect_eq "wait for reset: announces the time, sleeps until the wall clock passes it" \
  "$(sed 's/do [0-9:. ]*,/do T,/' <<<"$wait_out")" "⏸ Limit użycia (five_hour) — czekam na reset do T, potem wznawiam.
sleep 5"

# A fake claude that plays one stream per call: <Q>/<n>.jsonl, exit <Q>/<n>.rc; argv -> <Q>/argv.<n>.
fake_lim=$(mktemp -d)
mkdir "$fake_lim/bin" "$fake_lim/q"
cat > "$fake_lim/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_Q/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_Q/count"
printf '%s\n' "$@" > "$FAKE_Q/argv.$n"
cat "$FAKE_Q/$n.jsonl" 2>/dev/null
exit "$(cat "$FAKE_Q/$n.rc" 2>/dev/null || echo 0)"
FAKE_CLAUDE
chmod +x "$fake_lim/bin/claude"
# limit_stream <resetsAt> -> the real fixture with the reset moved.
limit_stream() { sed "s/1791596400/$1/g" "$LIMIT_FIXTURE"; }
DONE_STREAM='{"type":"system","subtype":"init","session_id":"92d20c8c-b0e0-4fbc-9256-3fde3852c1e6"}
{"type":"result","is_error":false,"num_turns":3,"result":"Gotowe.","session_id":"92d20c8c-b0e0-4fbc-9256-3fde3852c1e6"}'
# limit_case <setup> <fn call...>: runs in a fresh git repo with the fake claude; prints
# "<RALPH_LIMIT_STOP>|<calls>|<ślad keys or 'brak'>".
limit_case() {
  local setup="$1"; shift
  (
    repo=$(mktemp -d); cd "$repo" || exit 1
    git init -q; git checkout -q -b epic/45
    rm -rf "$fake_lim/q"; mkdir "$fake_lim/q"
    export FAKE_Q="$fake_lim/q" RALPH_LIMIT_MARGIN=0
    PATH="$fake_lim/bin:$PATH"
    ralph_notify() { :; }
    : > "$fake_lim/out"
    eval "$setup" >>"$fake_lim/out" 2>&1
    "$@" >>"$fake_lim/out" 2>&1
    f=$(ralph_limit_trace_path)
    printf '%s|%s|%s' "${RALPH_LIMIT_STOP:-none}" "$(cat "$FAKE_Q/count" 2>/dev/null || echo 0)" \
      "$([ -f "$f" ] && sed 's/=.*//' "$f" | tr '\n' ',' || echo brak)"
    rm -rf "$repo"
  )
}

past=$((now - 100)); far=$((now + 30000))
expect_eq "worker hits a limit with the reset passed -> resumes the session, run ends, ślad gone" \
  "$(limit_case "limit_stream $past > \$FAKE_Q/1.jsonl; printf '%s\n' \"\$DONE_STREAM\" > \$FAKE_Q/2.jsonl" \
     ralph_run_worker_through_limit sonnet high PROMPT issue-12 afk worker)" "none|2|brak"
expect_eq "  the second call resumes that session with the follow-up message, same model" \
  "$(head -10 "$fake_lim/q/argv.2" | tr '\n' ' ')" "-p --resume $SID --permission-mode auto --output-format stream-json --verbose --model sonnet "
expect_eq "  and is told to continue" "$(tail -1 "$fake_lim/q/argv.2")" "$RALPH_RESUME_PROMPT"
expect_eq "  the first call is a fresh run" "$(grep -c -- '--resume' "$fake_lim/q/argv.1")" "0"

expect_eq "worker hits a limit too far away -> stops, ślad left with the caller's context" \
  "$(limit_case "RALPH_LAUNCH_CMD='ralph-once 12'; limit_stream $far > \$FAKE_Q/1.jsonl; RALPH_LIMIT_CONTEXT=\$'issue=12\npre_head=abc\ncomplexity=heavy'" \
     ralph_run_worker_through_limit sonnet high PROMPT issue-12 afk worker)" \
  "limit|1|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,pre_head,complexity,"
expect_eq "  the stop message says what to do" "$(grep -c 'Po resecie wklej: ralph-once 12' "$fake_lim/out")" "1"

trace_setup="ralph_limit_trace_write runtime=claude phase=worker session=$SID model=sonnet effort=high label=issue-12 resets_at=$past limit=five_hour branch=epic/45 issue=12"
expect_eq "restart from the ślad -> resumes right away, run ends, ślad gone" \
  "$(limit_case "$trace_setup; printf '%s\n' \"\$DONE_STREAM\" > \$FAKE_Q/1.jsonl" \
     ralph_run_worker_through_limit sonnet high "" issue-12 afk worker "$SID")" "none|1|brak"
expect_eq "  with --resume" "$(sed -n 2,3p "$fake_lim/q/argv.1" | tr '\n' ' ')" "--resume $SID "
expect_eq "restart, but the runtime does not take the session up -> stop, ślad stays" \
  "$(limit_case "$trace_setup; echo 1 > \$FAKE_Q/1.rc" \
     ralph_run_worker_through_limit sonnet high "" issue-12 afk worker "$SID")" \
  "resume-failed|1|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,"
expect_eq "restart before a far reset -> no call, stop, ślad stays" \
  "$(limit_case "${trace_setup/resets_at=$past/resets_at=$far}" \
     ralph_run_worker_through_limit sonnet high "" issue-12 afk worker "$SID")" \
  "limit|0|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,"
expect_eq "a limit that never lifts -> gives up after $RALPH_LIMIT_MAX_WAITS waits" \
  "$(limit_case "for i in 1 2 3 4 5; do limit_stream $past > \$FAKE_Q/\$i.jsonl; done" \
     ralph_run_worker_through_limit sonnet high PROMPT issue-12 afk worker)" \
  "limit|4|runtime,phase,session,model,effort,label,resets_at,limit,branch,"
expect_eq "a normal run leaves another run's ślad alone" \
  "$(limit_case "$trace_setup; printf '%s\n' \"\$DONE_STREAM\" > \$FAKE_Q/1.jsonl" \
     ralph_run_worker_through_limit sonnet high PROMPT issue-13 afk worker)" \
  "none|1|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,"

# Which ślad applies: fake gh answers issue 12's state/labels and its parent (45).
applies_case() {
  local state="$1" labels="$2" arg="$3" branch="${4:-epic/45}"
  limit_case "$trace_setup; git checkout -q -b $branch 2>/dev/null || true
    gh() { case \"\$*\" in
      *'--json state'*) echo $state ;;
      *'--json labels'*) echo $labels ;;
      *'/parent'*) echo 45 ;;
    esac; }
    ralph_limit_trace_applies '$arg' && RALPH_LIMIT_STOP=applies" true
}
expect_eq "ślad applies: issue open + AFK, same branch, epic as the argument" "$(applies_case open true 45)" "applies|0|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,"
expect_eq "ślad applies: the issue itself as the argument" "$(applies_case open true 12 | cut -d'|' -f1)" "applies"
expect_eq "ślad applies: no argument" "$(applies_case open true '' | cut -d'|' -f1)" "applies"
expect_eq "ślad of another issue: not applied, left alone" "$(applies_case open true 77)" "none|0|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,"
expect_eq "  says so in one line" "$(grep -c 'dotyczy issue #12, nie #77 — zostawiam' "$fake_lim/out")" "1"
codex_trace_case() {
  limit_case "${trace_setup/runtime=claude/runtime=codex}
    gh() { echo open; }
    ralph_limit_trace_applies '' && RALPH_LIMIT_STOP=applies" true
}
expect_eq "ślad of the retired codex runtime: not applied, removed" "$(codex_trace_case)" "none|0|brak"
expect_eq "  with one line on screen" "$(grep -c 'Usuwam ślad limitu użycia (issue #12) z runtime' "$fake_lim/out")" "1"
expect_eq "stale ślad (issue closed meanwhile): not applied, removed" "$(applies_case closed false 45)" "none|0|brak"
expect_eq "  with the reason" "$(grep -c 'Usuwam nieaktualny ślad limitu użycia (issue #12): issue jest już zamknięte' "$fake_lim/out")" "1"
expect_eq "stale ślad (another branch): not applied, removed" "$(applies_case open true 45 dev)" "none|0|brak"
expect_eq "GitHub does not answer: not applied, left alone" "$(applies_case '' '' 45 | cut -d'|' -f1,3)" "none|runtime,phase,session,model,effort,label,resets_at,limit,branch,issue,"

# Wznowienie po limicie (ADR 0017) through ralph_resume_from_trace, with the ślad written for real
# and the worker / przegląd stubbed. $1: phase, $2: gate command, $3: complexity recorded in the
# ślad, $4: przegląd stub (ok|fail). Prints "<exit code>|<calls>": worker:<session>,
# review:<session>, gate, ...
resume_seq_case() {
  local r_phase="$1" r_cmd="$2" r_cx="${3:-normal}" r_review="${4:-ok}" rc
  (
    seq_repo "$r_cmd"
    git checkout -q -b epic/45
    if [ "$r_phase" = review ]; then st12=closed; ready12=false; else st12=open; ready12=true; fi
    ralph_limit_trace_write runtime=claude phase="$r_phase" session=$SID model=sonnet effort=high label=issue-12 \
      resets_at=$past limit=five_hour branch=epic/45 issue=12 pre_head=abc123 complexity="$r_cx"
    ralph_run_worker_through_limit() { echo "worker:${7:-}" >> "$SEQ_CALLS"; st12=closed; ready12=false; }
    ralph_heavy_review() {
      echo "review:${4:-}" >> "$SEQ_CALLS"
      if [ "$r_review" = fail ]; then st12=open; RALPH_REVIEW_EXIT=$RALPH_EXIT_REVIEW_RETRY; fi
    }
    ( ralph_resume_from_trace '' ) >/dev/null 2>&1
    rc=$?
    printf '%s|%s' "$rc" "$(paste -sd, "$SEQ_CALLS")"
    rm -rf "$repo" "$SEQ_CALLS" "$SEQ_COMMENTS"
  )
}
expect_eq "resume: worker phase, the worker closes the issue, gate green -> gate runs once, epic NOT labelled" \
  "$(resume_seq_case worker "$GATE_OK")" "0|worker:$SID,gate"
expect_eq "resume: worker phase, gate red -> issue reopened, no przegląd, epic NOT marked" \
  "$(resume_seq_case worker "$GATE_RED" heavy)" "7|worker:$SID,gate,gate,reopen,ready,comment"
expect_eq "resume: worker phase, heavy, gate green -> przegląd follows the gate" \
  "$(resume_seq_case worker "$GATE_OK" heavy)" "0|worker:$SID,gate,review:"
expect_eq "resume: worker phase, no ralph-gate: line -> exit 1, epic NOT marked" \
  "$(resume_seq_case worker '')" "1|worker:$SID"
expect_eq "resume: przegląd phase -> przegląd is not skipped, resumes the ślad's session, gate not rerun" \
  "$(resume_seq_case review "$GATE_RED" heavy)" "0|review:$SID"
expect_eq "resume: przegląd phase, FAIL -> exit 7, epic NOT marked" \
  "$(resume_seq_case review "$GATE_OK" heavy fail)" "7|review:$SID"
expect_eq "resume: no ślad -> returns 1 and runs nothing" \
  "$(
    seq_repo "$GATE_OK"
    git checkout -q -b epic/45
    ralph_run_worker_through_limit() { echo worker >> "$SEQ_CALLS"; }
    ralph_resume_from_trace ''
    echo "$?|$(paste -sd, "$SEQ_CALLS")"
  )" "1|"

# Strażnik / selektor: one-shot calls wait and repeat; the answer is the result text.
capture_case() {
  limit_case "$1; out=\$(ralph_run_model_capture guard PROMPT 2>/dev/null); rc=\$?; echo \"\$out/\$rc\" > \$FAKE_Q/answer" true
  printf '|%s' "$(cat "$fake_lim/q/answer")"
}
ANSWER_STREAM='{"type":"system","subtype":"init","session_id":"s"}
{"type":"result","is_error":false,"num_turns":1,"result":"READY","session_id":"s"}'
expect_eq "model call: the answer is the result text" \
  "$(capture_case "printf '%s\n' \"\$ANSWER_STREAM\" > \$FAKE_Q/1.jsonl")" "none|1|brak|READY/0"
expect_eq "  through stream-json" "$(grep -c -- 'stream-json' "$fake_lim/q/argv.1")" "1"
expect_eq "model call: a limit with the reset passed -> repeated, then answered" \
  "$(capture_case "limit_stream $past > \$FAKE_Q/1.jsonl; printf '%s\n' \"\$ANSWER_STREAM\" > \$FAKE_Q/2.jsonl")" "none|2|brak|READY/0"
expect_eq "model call: a limit too far away -> limit code, no ślad" \
  "$(capture_case "limit_stream $far > \$FAKE_Q/1.jsonl")" "none|1|brak|/$RALPH_EXIT_USAGE_LIMIT"
rm -rf "$fake_lim"

expect_eq "decision: 8 (usage limit) -> stop-usage-limit" "$(dec 8 1 5 false)" "stop-usage-limit"
expect_eq "decision: usage limit is not masked by a ready epic" "$(dec 8 1 5 true)" "stop-usage-limit"

# --- Evidence for the verification (ralph_evidence*): a fixture repo with an epic branch. ---
ev_repo=$(mktemp -d)
(
  cd "$ev_repo" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '# T\n\n## Ralph\n\nralph-base-branch: main\nralph-gate: true\n' > CLAUDE.md
  mkdir -p tests/snapshots app/Models vendor/bin
  printf '<?php\nit("a", function () {\n    expect(1)->toBe(1);\n    expect(2)->toBe(2);\n});\n\ntest("b", function () {\n    expect(3)->toBe(3);\n});\n' > tests/BarTest.php
  printf '<?php\nit("gone", function () { expect(1)->toBe(1); });\n' > tests/FooTest.php
  printf '<?php\nit("ok", function () {\n    $this->assertTrue(true);\n});\n' > tests/KeepTest.php
  printf 'old' > tests/snapshots/home.png
  printf 'old' > tests/snapshots/gone.png
  printf '<?php\nnamespace App\\Models;\nclass Old {}\n' > app/Models/Old.php
  git add -A && git commit -qm base
  git checkout -q -b epic/7
  git rm -q tests/FooTest.php tests/snapshots/gone.png
  printf '<?php\nit("a", function () {\n    expect(1)->toBe(1);\n})->skip();\n\ntodo("later");\n' > tests/BarTest.php
  printf '<?php\nit("ok", function () {\n    $this->assertTrue(true);\n    $this->assertFalse(false);\n});\n' > tests/KeepTest.php
  printf 'new' > tests/snapshots/home.png
  printf 'new' > tests/snapshots/fresh.png
  printf '<?php\nnamespace App\\Models;\nclass User {}\n' > app/Models/User.php
  printf 'x' > README.md
  git add -A && git commit -qm epic
)
ev_diff=$(cd "$ev_repo" && git diff -U0 --no-color main...epic/7)
expect_eq "evidence: deleted test file recognised (and a deleted image is not one)" \
  "$(ralph_evidence_scan deleted-file <<<"$ev_diff")" "tests/FooTest.php"
expect_eq "evidence: removed test declaration recognised, in a kept file only" \
  "$(ralph_evidence_scan removed-test <<<"$ev_diff")" 'tests/BarTest.php: test("b", function () {'
expect_eq "evidence: added skip and todo recognised" \
  "$(ralph_evidence_scan added-skip <<<"$ev_diff")" $'tests/BarTest.php: })->skip();\ntests/BarTest.php: todo("later");'
expect_eq "evidence: assertion count drop only where fewer were added than removed" \
  "$(ralph_evidence_scan assertion-drop <<<"$ev_diff")" "tests/BarTest.php: 2 -> 0"
expect_eq "evidence: screenshot patterns changed, added and deleted" \
  "$(ralph_evidence_scan screenshot <<<"$ev_diff" | sort | paste -sd, -)" \
  "dodany tests/snapshots/fresh.png,usunięty tests/snapshots/gone.png,zmieniony tests/snapshots/home.png"
expect_eq "evidence: a non-test change is no finding" \
  "$(printf 'diff --git a/README.md b/README.md\n--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-it("x", f)\n+skip()\n' | ralph_evidence_report | grep -c 'brak')" "5"
expect_eq "evidence: classes from changed non-test php files (FQCN), tests skipped" \
  "$(cd "$ev_repo" && git checkout -q epic/7 && ralph_epic_changed_files 7 | ralph_evidence_changed_classes | paste -sd, -)" 'App\Models\User'

# Mutations: only with Pest, only on the changed classes.
cat > "$ev_repo/vendor/bin/pest" <<'PEST'
#!/usr/bin/env bash
echo "$*" >> "$PEST_ARGS"
if [ -n "${PEST_BROKEN:-}" ]; then echo "Fatal: no coverage driver"; exit 2; fi
echo "Mutations: 1 survived, 4 tested"; exit 1
PEST
chmod +x "$ev_repo/vendor/bin/pest"
export PEST_ARGS="$ev_repo/pest-args"
ev_out=$(cd "$ev_repo" && ralph_evidence 7 2>&1)
expect_eq "evidence: pest --mutate runs once, on the changed class only" \
  "$(cat "$PEST_ARGS")" '--mutate --class=App\Models\User'
expect_eq "  the section holds the mutation report and the diff findings" \
  "$(grep -c 'Mutations: 1 survived' <<<"$ev_out")|$(grep -c 'tests/FooTest.php' <<<"$ev_out")" "1|1"
: > "$PEST_ARGS"
ev_out=$(cd "$ev_repo" && PEST_BROKEN=1 ralph_evidence 7 2>&1)
expect_eq "evidence: a pest failure -> mutation part skipped with one line, the rest stays" \
  "$(grep -c 'pomijam' <<<"$ev_out")|$(grep -c 'Mutacje' <<<"$ev_out")|$(grep -c 'tests/FooTest.php' <<<"$ev_out")" "1|0|1"
rm "$ev_repo/vendor/bin/pest"; : > "$PEST_ARGS"
ev_out=$(cd "$ev_repo" && ralph_evidence 7 2>&1)
expect_eq "evidence: no Pest -> no mutation part, no pest call, no failure" \
  "$(grep -c 'Mutacje' <<<"$ev_out")|$(wc -c < "$PEST_ARGS" | tr -d ' ')" "0|0"
expect_eq "evidence: epic without a branch -> empty section" "$(cd "$ev_repo" && ralph_evidence 99)" ""
rm -rf "$ev_repo"; unset PEST_ARGS

# --- /odbior skill: structure the artifact page and installer rely on ---
ODB="$SCRIPT_DIR/../../skills/odbior"
expect_eq "odbior: SKILL.md header names Opus and the skill" \
  "$(sed -n '1,/^---$/p;' "$ODB/SKILL.md" | sed -n '2,12p' | grep -c -E '^(name: odbior|model: opus)$')" "2"
expect_eq "odbior: description is English (no Polish diacritics)" \
  "$(grep '^description:' "$ODB/SKILL.md" | grep -c '[ąćęłńóśźż]')" "0"
expect_ok "odbior: page template exists" test -s "$ODB/template.html"
for odb_pat in 'window\.db' 'window\.assets' 'state:\$\{roundId\}' 'notes:\$\{round\.id\}' 'width=device-width'; do
  expect_ok "odbior: template contains $odb_pat" grep -q -E "$odb_pat" "$ODB/template.html"
done
expect_eq "odbior: SKILL.md keeps state when the round exists and prepends new rounds" \
  "$(grep -c -E 'do not touch it|prepend' "$ODB/SKILL.md")" "2"
expect_eq "odbior: act mode covers four paths, incomplete acceptance and gate before commit" \
  "$(grep -c -E 'Small matter|Larger matter|Let.s do it differently|All OK and no notes|Incomplete acceptance first|Red gate → no commit' "$ODB/SKILL.md")" "6"
expect_ok "odbior: SKILL.md writes the round marker the verify round counter recognises" \
  grep -q -F "$RALPH_ODBIOR_MARKER" "$ODB/SKILL.md"
for odb_sec in 'Zamknięcie epicu' 'Uwagi z odbioru'; do
  expect_ok "odbior: ralph-konfiguracja template section '$odb_sec' points at /odbior" \
    bash -c "sed -n '/^### $odb_sec/,/^\(### \|\`\`\`\)/p' \"\$1\" | sed 1d | grep -q '/odbior'" _ "$SCRIPT_DIR/../../skills/ralph-konfiguracja/SKILL.md"
done
expect_eq "odbior: install.sh links it for Claude" \
  "$(grep -c '^CLAUDE_ONLY_SKILLS=(odbior)' "$SCRIPT_DIR/../../install.sh")" "1"

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
