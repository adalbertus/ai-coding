#!/usr/bin/env bash
# Shared Ralph helpers. Keep runtime-specific mechanics here so the loop semantics stay in
# once.sh / once-local.sh.

RALPH_RUNTIME=""
RALPH_ISSUE_ARG=""
RALPH_LOCK_DIR=""
RALPH_LOCK_OWNED=0

ralph_usage() {
  local launcher="$1"
  case "$launcher" in
    ralph-once-local)
      echo "Użycie: ralph-once-local [claude|codex]"
      ;;
    *)
      echo "Użycie: ralph-once [claude|codex] [numer-issue]"
      echo "       ralph-once [numer-issue]  # wstecznie kompatybilne: Claude"
      ;;
  esac
}

ralph_parse_args() {
  local launcher="$1"
  shift

  RALPH_RUNTIME="${RALPH_DEFAULT_RUNTIME:-claude}"
  RALPH_ISSUE_ARG=""

  if [ "${1:-}" = "claude" ] || [ "${1:-}" = "codex" ]; then
    RALPH_RUNTIME="$1"
    shift
  fi

  case "$launcher" in
    ralph-once-local)
      if [ "$#" -gt 0 ]; then
        ralph_usage "$launcher" >&2
        return 1
      fi
      ;;
    *)
      if [ "$#" -gt 1 ]; then
        ralph_usage "$launcher" >&2
        return 1
      fi
      RALPH_ISSUE_ARG="${1:-}"
      if [ -n "$RALPH_ISSUE_ARG" ] && ! printf '%s' "$RALPH_ISSUE_ARG" | grep -qE '^[0-9]+$'; then
        echo "Argument '${RALPH_ISSUE_ARG}' nie jest runtime'em ani numerem issue." >&2
        ralph_usage "$launcher" >&2
        return 1
      fi
      ;;
  esac
}

ralph_contract_file() {
  case "$1" in
    codex) echo "AGENTS.md" ;;
    *) echo "CLAUDE.md" ;;
  esac
}

ralph_skill_tdd() {
  case "$1" in
    codex) echo '$tdd' ;;
    *) echo '/tdd' ;;
  esac
}

ralph_render_prompt() {
  local runtime="$1" prompt_file="$2" content contract_file skill_tdd
  contract_file="$(ralph_contract_file "$runtime")"
  skill_tdd="$(ralph_skill_tdd "$runtime")"
  content=$(cat "$prompt_file")
  content=${content//\{AGENT_CONTRACT_FILE\}/$contract_file}
  content=${content//\{SKILL_TDD\}/$skill_tdd}
  printf '%s\n' "$content"
}

ralph_require_runtime() {
  local runtime="$1"
  case "$runtime" in
    claude|codex) ;;
    *)
      echo "Nieznany runtime: $runtime (dozwolone: claude, codex)" >&2
      return 1
      ;;
  esac

  if ! command -v "$runtime" >/dev/null 2>&1; then
    echo "Brak komendy '$runtime' w PATH." >&2
    return 1
  fi
}

ralph_selector_model_label() {
  case "$1" in
    codex) echo "Codex config default" ;;
    *) echo "claude-haiku-4-5" ;;
  esac
}

ralph_model_for_complexity() {
  local runtime="$1" complexity="$2"
  RALPH_MODEL=""
  RALPH_EFFORT=""

  case "$runtime:$complexity" in
    claude:heavy)   RALPH_MODEL="claude-opus-4-8"; RALPH_EFFORT="high" ;;
    claude:trivial) RALPH_MODEL="haiku"; RALPH_EFFORT="medium" ;;
    claude:*)       RALPH_MODEL="sonnet"; RALPH_EFFORT="medium" ;;

    codex:heavy)   RALPH_MODEL="${RALPH_CODEX_MODEL_HEAVY:-${RALPH_CODEX_MODEL:-}}"; RALPH_EFFORT="${RALPH_CODEX_EFFORT_HEAVY:-high}" ;;
    codex:trivial) RALPH_MODEL="${RALPH_CODEX_MODEL_TRIVIAL:-${RALPH_CODEX_MODEL:-}}"; RALPH_EFFORT="${RALPH_CODEX_EFFORT_TRIVIAL:-low}" ;;
    codex:*)       RALPH_MODEL="${RALPH_CODEX_MODEL_NORMAL:-${RALPH_CODEX_MODEL:-}}"; RALPH_EFFORT="${RALPH_CODEX_EFFORT_NORMAL:-medium}" ;;
  esac
}

ralph_model_display() {
  local runtime="$1" model="$2" effort="$3"
  case "$runtime" in
    codex)
      if [ -n "$model" ]; then
        echo "$model (reasoning:${effort:-config})"
      else
        echo "Codex config default (reasoning:${effort:-config})"
      fi
      ;;
    *)
      echo "$model (effort:${effort})"
      ;;
  esac
}

ralph_run_model_capture() {
  local runtime="$1" purpose="$2" prompt="$3"

  case "$runtime" in
    claude)
      local model="claude-haiku-4-5-20251001"
      claude -p --model "$model" --effort low "$prompt"
      ;;
    codex)
      codex exec --ephemeral -s read-only -a never -C "$PWD" "$prompt"
      ;;
    *)
      echo "Nieznany runtime: $runtime" >&2
      return 1
      ;;
  esac
}

ralph_run_worker() {
  local runtime="$1" model="$2" effort="$3" prompt="$4"

  case "$runtime" in
    claude)
      claude --permission-mode auto --model "$model" --effort "$effort" "$prompt"
      ;;
    codex)
      local args=(exec --approve-for-me -s workspace-write -a never -C "$PWD")
      [ -n "$model" ] && args+=(-m "$model")
      [ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")
      codex "${args[@]}" "$prompt"
      ;;
    *)
      echo "Nieznany runtime: $runtime" >&2
      return 1
      ;;
  esac
}

ralph_lock_metadata() {
  local issue="${1:-selector}"
  {
    printf 'pid=%s\n' "${BASHPID:-$$}"
    printf 'runtime=%s\n' "$RALPH_RUNTIME"
    printf 'issue=%s\n' "$issue"
    printf 'branch=%s\n' "$(git branch --show-current 2>/dev/null || echo unknown)"
    printf 'cwd=%s\n' "$PWD"
    printf 'started_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  } > "$RALPH_LOCK_DIR/meta"
}

ralph_lock_pid() {
  [ -f "$RALPH_LOCK_DIR/meta" ] || return 1
  sed -n 's/^pid=//p' "$RALPH_LOCK_DIR/meta" | head -1
}

ralph_show_lock() {
  echo "Istniejący lock Ralpha:" >&2
  if [ -f "$RALPH_LOCK_DIR/meta" ]; then
    sed 's/^/  /' "$RALPH_LOCK_DIR/meta" >&2
  else
    echo "  $RALPH_LOCK_DIR" >&2
  fi
}

ralph_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

ralph_prompt_choice() {
  local prompt="$1" default="$2" answer
  if [ ! -t 0 ]; then
    printf '%s\n' "$default"
    return 0
  fi
  read -r -p "$prompt" answer
  printf '%s\n' "${answer:-$default}"
}

ralph_wait_for_pid_exit() {
  local pid="$1" i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    ralph_pid_alive "$pid" || return 0
    sleep 0.2
  done
  return 1
}

ralph_acquire_lock() {
  local issue="${1:-selector}" pid choice

  RALPH_LOCK_DIR=$(git rev-parse --git-path ralph.lock.d 2>/dev/null)
  if [ -z "$RALPH_LOCK_DIR" ]; then
    echo "Nie mogę ustalić ścieżki locka Ralpha; czy to repo git?" >&2
    return 1
  fi

  while ! mkdir "$RALPH_LOCK_DIR" 2>/dev/null; do
    pid="$(ralph_lock_pid || true)"
    ralph_show_lock

    if ralph_pid_alive "$pid"; then
      if [ ! -t 0 ]; then
        echo "Ralph już działa w tym worktree; tryb nieinteraktywny przerywa." >&2
        return 1
      fi

      choice="$(ralph_prompt_choice "Żywy proces $pid. [Enter] przerwij, [k] zabij proces i kontynuuj: " "abort")"
      case "$choice" in
        k|K|kill|KILL)
          echo "Wysyłam SIGTERM do procesu $pid..." >&2
          kill "$pid" 2>/dev/null || true
          if ! ralph_wait_for_pid_exit "$pid"; then
            echo "Proces $pid nadal żyje; przerywam. Zabij go ręcznie albo użyj osobnego worktree." >&2
            return 1
          fi
          rm -rf "$RALPH_LOCK_DIR"
          ;;
        *)
          echo "Przerwano — istniejący Ralph zostaje." >&2
          return 1
          ;;
      esac
    else
      if [ -t 0 ]; then
        echo "Stary lock: proces już nie działa." >&2
        choice="$(ralph_prompt_choice "[Enter] usuń i kontynuuj, [a] przerwij: " "remove")"
        case "$choice" in
          a|A|abort|ABORT)
            echo "Przerwano — stale lock zostaje." >&2
            return 1
            ;;
        esac
      else
        echo "Stary lock bez żywego PID; usuwam i kontynuuję." >&2
      fi
      rm -rf "$RALPH_LOCK_DIR"
    fi
  done

  RALPH_LOCK_OWNED=1
  ralph_lock_metadata "$issue"
}

ralph_release_lock() {
  if [ "$RALPH_LOCK_OWNED" = 1 ] && [ -n "$RALPH_LOCK_DIR" ] && [ -d "$RALPH_LOCK_DIR" ]; then
    rm -rf "$RALPH_LOCK_DIR"
    RALPH_LOCK_OWNED=0
  fi
}

ralph_trap_release_lock() {
  trap ralph_release_lock EXIT
  trap 'ralph_release_lock; exit 130' INT
  trap 'ralph_release_lock; exit 143' TERM
  trap 'ralph_release_lock; exit 129' HUP
}

ralph_warn_dirty_tree() {
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "⚠️  Ralph zostawił niezacommitowane zmiany w drzewie roboczym."
    echo "   Sprawdź (git status) i domknij je, zanim odpalisz kolejny przebieg."
  fi
}
