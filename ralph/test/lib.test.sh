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

expect_ok "ralph-once codex 224 parses as Codex explicit issue" ralph_parse_args ralph-once codex 224
expect_eq "codex runtime parsed" "$RALPH_RUNTIME" "codex"
expect_eq "codex issue parsed" "$RALPH_ISSUE_ARG" "224"

expect_ok "ralph-once codex parses as Codex selector mode" ralph_parse_args ralph-once codex
expect_eq "codex selector runtime parsed" "$RALPH_RUNTIME" "codex"
expect_eq "codex selector has no issue" "$RALPH_ISSUE_ARG" ""

expect_fail "unknown runtime/issue is rejected" ralph_parse_args ralph-once gpt 224
expect_fail "ralph-once-local rejects issue arg" ralph_parse_args ralph-once-local 224
expect_ok "ralph-once-local accepts codex runtime" ralph_parse_args ralph-once-local codex
expect_eq "local codex runtime parsed" "$RALPH_RUNTIME" "codex"

expect_ok "--force-model before the issue number" ralph_parse_args ralph-once --force-model=opus 224
expect_eq "  forced model parsed" "$RALPH_FORCE_MODEL" "opus"
expect_eq "  issue still parsed" "$RALPH_ISSUE_ARG" "224"
expect_ok "--force-model after runtime and epic" ralph_parse_args ralph-epic claude 12 --force-model=sonnet
expect_eq "  forced model parsed" "$RALPH_FORCE_MODEL/$RALPH_RUNTIME/$RALPH_ISSUE_ARG" "sonnet/claude/12"
expect_ok "ralph-once-local accepts --force-model" ralph_parse_args ralph-once-local --force-model=sonnet
expect_ok "no flag -> no forced model (reset between calls)" ralph_parse_args ralph-once 224
expect_eq "  forced model empty" "$RALPH_FORCE_MODEL" ""
expect_fail "--force-model rejects an unknown model" ralph_parse_args ralph-once --force-model=haiku 224
expect_fail "--force-model rejects the codex runtime" ralph_parse_args ralph-once codex --force-model=opus

expect_eq "Claude contract file" "$(ralph_contract_file claude)" "CLAUDE.md"
expect_eq "Codex contract file" "$(ralph_contract_file codex)" "AGENTS.md"
expect_eq "Claude tdd skill syntax" "$(ralph_skill_tdd claude)" "/tdd"
expect_eq "Codex tdd skill syntax" "$(ralph_skill_tdd codex)" '$tdd'

tmp_prompt=$(mktemp)
printf 'Read {AGENT_CONTRACT_FILE}; use {SKILL_TDD}.\n' > "$tmp_prompt"
expect_eq "render Claude prompt" "$(ralph_render_prompt claude "$tmp_prompt")" "Read CLAUDE.md; use /tdd."
expect_eq "render Codex prompt" "$(ralph_render_prompt codex "$tmp_prompt")" 'Read AGENTS.md; use $tdd.'
rm -f "$tmp_prompt"

# {EXPLORE_GUIDANCE} is spliced in BEFORE the other placeholders, so the {AGENT_CONTRACT_FILE}
# markers carried by the guidance prose itself still get resolved.
tmp_prompt=$(mktemp)
printf '{EXPLORE_GUIDANCE}\n' > "$tmp_prompt"
expect_fail "rendered guidance leaves no unresolved placeholder" \
  grep -q '{[A-Z_]*}' <<<"$(ralph_render_prompt codex "$tmp_prompt")"
rm -f "$tmp_prompt"

# The two branches must be genuinely different prose, each naming the tools its runtime has.
expect_ok "Claude exploration names Read/Grep + Explore subagent" \
  grep -qF 'delegate to the `Explore` subagent' <<<"$(ralph_explore_guidance claude)"
expect_ok "Codex exploration names concrete shell commands" \
  grep -qF "sed -n '<start>,<end>p'" <<<"$(ralph_explore_guidance codex)"
# ADR 0005: a subagent is a cheap linguistic escape hatch whose cost we have only measured on
# Claude. Until measured on Codex, that branch must not offer it.
expect_fail "Codex exploration does not mention subagents" \
  grep -qi 'subagent' <<<"$(ralph_explore_guidance codex)"

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

# Golden files: for the `claude` branch this is a gate — that prose is in daily use and must not
# drift as a side effect of a Codex change. For `codex` it is a magnifying glass: the prose is
# being tuned against context measurements, and every version has to be visible in git history.
# A deliberate change to either means regenerating them: UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh
GOLDEN_DIR="$SCRIPT_DIR/golden"
for prompt_file in prompt prompt-hitl prompt-local; do
  for runtime in claude codex; do
    golden="$GOLDEN_DIR/$prompt_file.$runtime.md"
    rendered=$(ralph_render_prompt "$runtime" "$SCRIPT_DIR/../$prompt_file.md")
    if [ -n "${UPDATE_GOLDEN:-}" ]; then
      printf '%s\n' "$rendered" > "$golden"
      echo "· zregenerowano $prompt_file.$runtime.md"
      continue
    fi
    if [ ! -f "$golden" ]; then
      echo "✗ brak golden file $prompt_file.$runtime.md (UPDATE_GOLDEN=1 żeby wygenerować)"
      fail=$((fail+1))
      continue
    fi
    if diff_out=$(diff -u "$golden" <(printf '%s\n' "$rendered")); then
      echo "✓ golden render: $prompt_file.$runtime.md"
      pass=$((pass+1))
    else
      echo "✗ golden render: $prompt_file.$runtime.md"
      printf '%s\n' "$diff_out" | sed 's/^/   /'
      echo "   Zmiana celowa? UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh"
      fail=$((fail+1))
    fi
  done
done

ralph_model_for_complexity claude heavy
expect_eq "Claude heavy model" "$RALPH_MODEL/$RALPH_EFFORT" "opus/high"

ralph_model_for_complexity claude trivial
expect_eq "Claude trivial stays on a model with auto mode (not Haiku)" "$RALPH_MODEL/$RALPH_EFFORT" "sonnet/low"

ralph_model_for_complexity codex trivial
expect_eq "Codex trivial uses config model + low reasoning" "$RALPH_MODEL/$RALPH_EFFORT" "/low"

RALPH_CODEX_MODEL_NORMAL="gpt-test" ralph_model_for_complexity codex normal
expect_eq "Codex normal env model override" "$RALPH_MODEL/$RALPH_EFFORT" "gpt-test/medium"
unset RALPH_CODEX_MODEL_NORMAL

RALPH_FORCE_MODEL=sonnet ralph_model_for_complexity claude heavy
expect_eq "--force-model=sonnet overrides heavy, at high effort" "$RALPH_MODEL/$RALPH_EFFORT" "sonnet/high"
RALPH_FORCE_MODEL=opus ralph_model_for_complexity claude trivial
expect_eq "--force-model=opus overrides trivial, at high effort" "$RALPH_MODEL/$RALPH_EFFORT" "opus/high"
RALPH_FORCE_MODEL=""

fake_codex_dir=$(mktemp -d)
mkdir "$fake_codex_dir/bin"
cat > "$fake_codex_dir/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEX_ARGV_CAPTURE"
FAKE_CODEX
chmod +x "$fake_codex_dir/bin/codex"

(
  PATH="$fake_codex_dir/bin:$PATH"
  CODEX_ARGV_CAPTURE="$fake_codex_dir/guard.argv"
  export CODEX_ARGV_CAPTURE
  ralph_run_model_capture codex guard "PROMPT" >/dev/null
)
expect_eq "Codex guard passes approval policy before exec" \
  "$(cat "$fake_codex_dir/guard.argv")" \
  $'-a\nnever\nexec\n--ephemeral\n-s\nread-only\n-C\n'"$PWD"$'\nPROMPT'

(
  PATH="$fake_codex_dir/bin:$PATH"
  CODEX_ARGV_CAPTURE="$fake_codex_dir/worker.argv"
  export CODEX_ARGV_CAPTURE
  ralph_run_worker codex gpt-test low "PROMPT" issue-16 hitl >/dev/null
)
expect_eq "Codex HITL worker starts interactive CLI with auto-review" \
  "$(cat "$fake_codex_dir/worker.argv")" \
  $'--no-alt-screen\n--approve-for-me\n-C\n'"$PWD"$'\n-m\ngpt-test\n-c\nmodel_reasoning_effort="low"\nPROMPT'

rm -rf "$fake_codex_dir"

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
  ralph_run_worker claude sonnet low "PROMPT" issue-13 hitl >/dev/null
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
  ralph_run_worker claude sonnet low "PROMPT" issue-12
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

# --- Codex worker: exec stream renderer + unattended adapter ---
codex_fixture=$(cat <<STREAM
{"type":"thread.started","thread_id":"thread-abc"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"i0","type":"agent_message","text":"Zaczynam."}}
{"type":"item.started","item":{"id":"i1","type":"command_execution","command":"bash test.sh","status":"in_progress"}}
{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"bash test.sh\\necho second","aggregated_output":"ok","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"i2","type":"command_execution","command":"false","aggregated_output":"","exit_code":1,"status":"failed"}}
{"type":"item.completed","item":{"id":"i3","type":"file_change","changes":[{"path":"$PWD/greet.sh","kind":"update"},{"path":"/elsewhere/x.md","kind":"add"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"i4","type":"reasoning","text":"hmm"}}
{"type":"item.completed","item":{"id":"i5","type":"future_thing","foo":1}}
not json at all
{"type":"item.completed","item":{"id":"i6","type":"agent_message","text":"Gotowe: issue zamknięte."}}
{"type":"turn.completed","usage":{"input_tokens":1}}
STREAM
)
expect_eq "codex renderer: narration, command, failed command, file changes, final message; unknown/garbage skipped" \
  "$(ralph_render_codex_stream <<<"$codex_fixture")" \
  $'› Zaczynam.\n  ▸ Bash: bash test.sh\n  ✗ Bash (exit 1): false\n  ▸ Edit: greet.sh\n  ▸ Write: /elsewhere/x.md\n\n── Raport workera ──\nGotowe: issue zamknięte.'
expect_eq "codex renderer: unknown-only stream renders nothing" \
  "$(ralph_render_codex_stream <<<'{"type":"thread.started","thread_id":"t"}')" ""

fake_cx_dir=$(mktemp -d)
mkdir "$fake_cx_dir/bin"
cat > "$fake_cx_dir/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEX_ARGV_CAPTURE"
cat "$CODEX_STREAM_FIXTURE"
FAKE_CODEX
chmod +x "$fake_cx_dir/bin/codex"
printf '%s\n' "$codex_fixture" > "$fake_cx_dir/stream.jsonl"

cx_repo=$(mktemp -d)
cx_out=$(
  cd "$cx_repo" || exit 1
  git init -q
  PATH="$fake_cx_dir/bin:$PATH"
  CODEX_ARGV_CAPTURE="$fake_cx_dir/worker.argv"
  CODEX_STREAM_FIXTURE="$fake_cx_dir/stream.jsonl"
  export CODEX_ARGV_CAPTURE CODEX_STREAM_FIXTURE
  ralph_run_worker codex gpt-test low "PROMPT" issue-16
  echo "status:[$(git status --porcelain)]"
  echo "logs:$(ls "$(git rev-parse --git-path ralph-logs)")"
)
expect_eq "Codex AFK worker runs unattended: exec --json --approve-for-me" \
  "$(cat "$fake_cx_dir/worker.argv")" \
  $'exec\n--json\n--approve-for-me\n-C\n'"$cx_repo"$'\n-m\ngpt-test\n-c\nmodel_reasoning_effort="low"\nPROMPT'
case "$cx_out" in *"codex resume thread-abc"*) r=yes ;; *) r=no ;; esac
expect_eq "Codex AFK worker prints resume line with the thread id" "$r" "yes"
case "$cx_out" in *"▸ Bash: bash test.sh"*) r=yes ;; *) r=no ;; esac
expect_eq "Codex AFK worker shows progress lines on screen" "$r" "yes"
expect_eq "Codex AFK worker log is under ralph-logs, git status stays clean" \
  "$(grep -E '^(status|logs):' <<<"$cx_out" | sed -E 's/[0-9]{8}-[0-9]{6}/STAMP/')" \
  $'status:[]\nlogs:STAMP-issue-16.jsonl'
rm -rf "$fake_cx_dir" "$cx_repo"

lock_repo=$(mktemp -d)
(
  cd "$lock_repo" || exit 1
  git init -q
  RALPH_RUNTIME=codex
  ralph_acquire_lock 224
  [ -d "$(git rev-parse --git-path ralph.lock.d)" ] || exit 1
  grep -q '^runtime=codex$' "$(git rev-parse --git-path ralph.lock.d)/meta" || exit 1
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
  RALPH_RUNTIME=codex
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
BLK_H=$'## Blocked by\n\n- #9'
S_BLK="[{\"number\":1,\"labels\":$L_HITL,\"body\":\"$(printf '%s' "$BLK_H" | jq -Rs . | sed 's/^"//;s/"$//')\"}]"
expect_eq "stage: blocked HITL dropped by filter -> nothing" \
  "$(ralph_filter_unblocked '[9]' <<<"$S_BLK" | ralph_epic_stage | nums)" ""
expect_eq "pick first: lowest number, whatever the order" \
  "$(ralph_pick_first <<<'[{"number":9},{"number":7},{"number":8}]')" "7"
expect_eq "pick first: empty list -> nothing" "$(ralph_pick_first <<<'[]')" ""
expect_eq "stage: blocked AFK, free HITL -> HITL" \
  "$(jq -c '[.[0] + {labels: [{"name":"ready-for-agent"}]}] + [{"number":7,"labels":[],"body":""}]' <<<"$S_BLK" \
    | ralph_filter_unblocked '[9]' | ralph_epic_stage | nums)" "7"
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

# --- ralph_filter_unblocked: issues with an open blocker are dropped ---
mk() { jq -cn --argjson n "$1" --arg b "$2" '{number: $n, title: "t", body: $b}'; }
blk() { printf '## What\nx\n\n## Blocked by\n\n%s\n\n## Other\nsee #99\n' "$1"; }
unblocked() { printf '%s\n' "$@" | jq -cs '.' | ralph_filter_unblocked "$OPEN" | nums; }
OPEN='[12,30]'
expect_eq "unblocked: #12 open -> rejected" "$(unblocked "$(mk 1 "$(blk '- #12')")")" ""
expect_eq "unblocked: bare 12 open -> rejected" "$(unblocked "$(mk 1 "$(blk '- 12')")")" ""
expect_eq "unblocked: closed blocker -> passes" "$(unblocked "$(mk 1 "$(blk '- #13')")")" "1"
expect_eq "unblocked: None -> passes" "$(unblocked "$(mk 1 "$(blk 'None - can start immediately')")")" "1"
expect_eq "unblocked: no section -> passes" "$(unblocked "$(mk 1 '## What
x #12')")" "1"
expect_eq "unblocked: null body -> passes" "$(unblocked '{"number":1,"title":"t","body":null}')" "1"
expect_eq "unblocked: several, one open -> rejected" "$(unblocked "$(mk 1 "$(blk '- #13
- #12')")")" ""
expect_eq "unblocked: number after the section is ignored" "$(unblocked "$(mk 1 "$(blk '- #13')")")" "1"
expect_eq "unblocked: keeps order of the free ones" "$(unblocked "$(mk 1 "$(blk '- #12')")" "$(mk 2 "$(blk 'None')")" "$(mk 3 "$(blk '- 5')")")" "2,3"
expect_eq "unblocked: no open issues -> all pass" "$(printf '%s' "$(mk 1 "$(blk '- #12')")" | jq -cs . | ralph_filter_unblocked '[]' | nums)" "1"

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

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
