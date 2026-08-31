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

ralph_model_for_complexity claude heavy
expect_eq "Claude heavy model" "$RALPH_MODEL/$RALPH_EFFORT" "claude-opus-4-8/high"

ralph_model_for_complexity codex trivial
expect_eq "Codex trivial uses config model + low reasoning" "$RALPH_MODEL/$RALPH_EFFORT" "/low"

RALPH_CODEX_MODEL_NORMAL="gpt-test" ralph_model_for_complexity codex normal
expect_eq "Codex normal env model override" "$RALPH_MODEL/$RALPH_EFFORT" "gpt-test/medium"
unset RALPH_CODEX_MODEL_NORMAL

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

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
