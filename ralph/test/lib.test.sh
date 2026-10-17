#!/usr/bin/env bash
# Tests for ralph/lib.sh. Pure shell helpers only; no model, network, or GitHub calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
# Plain, unclipped output whatever terminal the tests run in; colour and clipping are tested
# explicitly.
export RALPH_COLOR=0 RALPH_COLS=0
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
for prompt_file in prompt prompt-hitl prompt-local prompt-review; do
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

# --- ralph_epic_ready_to_mark: pure decision (total sub-issues, open sub-issues, has label) ---
expect_ok "mark: all closed, no label -> mark" ralph_epic_ready_to_mark 3 0 false
expect_fail "mark: label already there -> no" ralph_epic_ready_to_mark 3 0 true
expect_fail "mark: open sub-issues -> no" ralph_epic_ready_to_mark 3 1 false
expect_fail "mark: epic without any sub-issues -> no" ralph_epic_ready_to_mark 0 0 false

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

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
