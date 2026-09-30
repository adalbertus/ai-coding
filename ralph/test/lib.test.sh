#!/usr/bin/env bash
# Tests for ralph/lib.sh. Pure shell helpers only; no model, network, or GitHub calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
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
expect_eq "renderer: Bash call, Edit/Write paths, final result; unknown/garbage skipped" \
  "$(ralph_render_stream <<<"$stream_fixture")" \
  $'▸ Bash: bash test.sh\n▸ Edit: greet.sh\n▸ Write: /elsewhere/x.md\n\nGotowe: issue zamknięte.'
expect_eq "renderer: unknown-only stream renders nothing" \
  "$(ralph_render_stream <<<'{"type":"system","subtype":"init"}')" ""

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
expect_eq "codex renderer: command, failed command, file changes, final message; unknown/garbage skipped" \
  "$(ralph_render_codex_stream <<<"$codex_fixture")" \
  $'▸ Bash: bash test.sh\n▸ Bash: false ✗ exit 1\n▸ Edit: greet.sh\n▸ Write: /elsewhere/x.md\n\nGotowe: issue zamknięte.'
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

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
