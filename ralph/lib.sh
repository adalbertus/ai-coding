#!/usr/bin/env bash
# Shared Ralph helpers. Keep runtime-specific mechanics here so the loop semantics stay in
# once.sh / once-local.sh.

RALPH_RUNTIME=""
RALPH_ISSUE_ARG=""
RALPH_FORCE_MODEL=""
# The command to paste after a usage limit: the launcher and number the run was started with.
# ralph-epic exports RALPH_LAUNCH_CMD_OUTER so the once.sh it runs reports the epic command.
RALPH_LAUNCH_CMD=""
RALPH_LOCK_DIR=""
RALPH_LOCK_OWNED=0

ralph_usage() {
  local launcher="$1"
  case "$launcher" in
    ralph-once-local)
      echo "Użycie: ralph-once-local [claude] [--force-model=sonnet|opus]"
      ;;
    ralph-epic)
      echo "Użycie: ralph-epic [claude] [numer-epicu] [--force-model=sonnet|opus]"
      ;;
    *)
      echo "Użycie: ralph-once [claude] [numer-issue] [--force-model=sonnet|opus]"
      echo "       ralph-once [numer-issue]  # claude jest domyślny i można go pominąć"
      ;;
  esac
  echo "  --force-model=sonnet|opus  jeden model Claude z effort high dla każdego issue,"
  echo "                             zamiast modelu z etykiety complexity:*"
}

ralph_parse_args() {
  local launcher="$1"
  shift

  RALPH_RUNTIME=claude
  RALPH_ISSUE_ARG=""
  RALPH_FORCE_MODEL=""
  RALPH_LAUNCH_CMD=""

  # --force-model=<model> may stand anywhere; the positional arguments are what is left.
  local rest=() arg force=""
  for arg in "$@"; do
    case "$arg" in
      --force-model=*) force="${arg#--force-model=}" ;;
      *) rest+=("$arg") ;;
    esac
  done
  set -- ${rest[@]+"${rest[@]}"}

  if [ "${1:-}" = "claude" ]; then
    shift
  elif [ "${1:-}" = "codex" ]; then
    echo "Codex nie uruchamia już Ralpha (ADR 0020). Użyj Claude: pomiń argument albo podaj 'claude'." >&2
    return 1
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
        echo "Argument '${RALPH_ISSUE_ARG}' nie jest ani 'claude', ani numerem issue." >&2
        ralph_usage "$launcher" >&2
        return 1
      fi
      ;;
  esac

  case "$force" in
    ""|sonnet|opus) ;;
    *)
      echo "--force-model przyjmuje sonnet albo opus, nie '${force}'." >&2
      ralph_usage "$launcher" >&2
      return 1
      ;;
  esac
  RALPH_FORCE_MODEL="$force"
  RALPH_LAUNCH_CMD="${RALPH_LAUNCH_CMD_OUTER:-${launcher}${RALPH_ISSUE_ARG:+ $RALPH_ISSUE_ARG}}"
}

# The repo file that carries `## Ralph`. Ralph runs only on Claude, so AGENTS.md is never read.
ralph_contract_file() {
  echo "CLAUDE.md"
}

# Extract the "## Ralph" section body from an agent contract file: from the Ralph heading up to
# (not including) the next level-1/2 heading. "### " subheadings stay inside the section.
ralph_contract_section() {
  awk '
    /^#{1,2}[[:space:]]+Ralph([[:space:]]|$)/ { f=1; print; next }
    f && /^#{1,2}[[:space:]]/ { exit }
    f { print }
  ' "$1"
}

ralph_render_prompt() {
  cat "$1"
}

# --- Screen and run log ---

# Colour is for a human at a terminal: on when stdout is a TTY and NO_COLOR is unset. An
# inherited RALPH_COLOR wins, so a script whose stdout became the run-log pipe (see
# ralph_start_run_log) keeps the decision its parent made at the terminal.
ralph_color_init() {
  if [ -z "${RALPH_COLOR:-}" ]; then
    if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then RALPH_COLOR=1; else RALPH_COLOR=0; fi
  fi
  export RALPH_COLOR
}

# $1: tone — ok (green), warn (orange), err (red), dim; the rest: the message (may span lines).
# Plain text when colour is off.
ralph_say() {
  local tone="$1" code=""
  shift
  case "$tone" in
    ok) code=32 ;;
    warn) code='38;5;208' ;;
    err) code=31 ;;
    dim) code=2 ;;
  esac
  if [ "${RALPH_COLOR:-0}" = 1 ] && [ -n "$code" ]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$*"
  else
    printf '%s\n' "$*"
  fi
}

# Width to clip renderer steps to: RALPH_COLS when set, else the controlling terminal's (stdout
# may be a pipe), else 0 = do not clip.
ralph_term_cols() {
  local cols="${RALPH_COLS:-}"
  [ -n "$cols" ] || cols=$({ stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
  echo "$cols"
}

# Re-runs the calling script ($0, with the arguments after $1) with stdout+stderr teed to
# <git dir>/ralph-logs/<stamp>-$1.log, then exits with its code. The log is for diagnosis after
# the fact, e.g. by an agent in another session: what Ralph decided, with the paths of the
# workers' stream logs, colour stripped, framed by start/end lines with the exit code.
# Returns without doing anything when a log is already being written (a nested script such as
# once.sh under ralph-epic; RALPH_RUN_LOG=off in tests) or outside a git repo.
# Interactive sessions need the terminal, not the pipe: fds 3/4 keep it (RALPH_TERM_FDS=1).
ralph_start_run_log() {
  local label="$1" dir log rc
  shift
  [ -z "${RALPH_RUN_LOG:-}" ] || return 0
  { dir=$(git rev-parse --git-path ralph-logs 2>/dev/null) && mkdir -p "$dir"; } 2>/dev/null || return 0
  ralph_color_init
  log="$dir/$(date +%Y%m%d-%H%M%S)-${label}.log"
  printf '# %s %s\n# start: %s, katalog: %s, gałąź: %s\n' "$(basename "$0")" "$*" \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$PWD" "$(git branch --show-current 2>/dev/null)" > "$log"
  export RALPH_RUN_LOG="$log" RALPH_TERM_FDS=1
  # tee (not a line-based filter) so a prompt without a newline still reaches the screen.
  { "$BASH" "$0" "$@" 2>&1 | tee -a "$log"; rc=${PIPESTATUS[0]}; } 3>&1 4>&2
  sed $'s/\x1b\\[[0-9;]*m//g' "$log" > "$log.tmp" && mv "$log.tmp" "$log"
  printf '# koniec: %s, kod wyjścia: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$rc" >> "$log"
  ralph_say dim "Log przebiegu: $log"
  exit "$rc"
}

ralph_require_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "Brak komendy 'claude' w PATH." >&2
    return 1
  fi
}

ralph_selector_model_label() {
  echo "claude-haiku-4-5"
}

ralph_model_for_complexity() {
  local complexity="$1"
  RALPH_MODEL=""
  RALPH_EFFORT=""

  case "$complexity" in
    # heavy: the normal-tier model at high effort; the stronger model only reviews the result
    # afterwards (ralph_review_model, ADR 0016).
    heavy)   RALPH_MODEL="sonnet"; RALPH_EFFORT="high" ;;
    # Not Haiku: the worker needs auto mode, which Claude Code does not offer on Haiku; without
    # it every Bash call waits for approval and the AFK loop stalls.
    trivial) RALPH_MODEL="sonnet"; RALPH_EFFORT="low" ;;
    *)       RALPH_MODEL="sonnet"; RALPH_EFFORT="medium" ;;
  esac

  # --force-model: one Claude model for every tier, always at high effort.
  if [ -n "${RALPH_FORCE_MODEL:-}" ]; then
    RALPH_MODEL="$RALPH_FORCE_MODEL"
    RALPH_EFFORT="high"
  fi
}

# The model for the przegląd heavy: the strongest tier. Not affected by --force-model — the review
# follows the label alone.
ralph_review_model() {
  RALPH_REVIEW_MODEL="opus"
  RALPH_REVIEW_EFFORT="high"
}

ralph_model_display() {
  echo "$1 (effort:$2)"
}

# A one-shot model call (strażnik, selektor): its answer on stdout, Claude's own stderr
# dropped. Claude streams JSON so a usage limit shows in a field (ADR 0017): the call waits for the
# reset (messages on stderr) and is repeated; a reset too far away -> rc RALPH_EXIT_USAGE_LIMIT.
ralph_run_model_capture() {
  local purpose="$1" prompt="$2"
  local model="claude-haiku-4-5-20251001" out rc hit reset type waits=0
  while :; do
    out=$(claude -p --model "$model" --effort low --output-format stream-json --verbose "$prompt" 2>/dev/null)
    rc=$?
    hit=$(ralph_stream_usage_limit <<<"$out")
    if [ -z "$hit" ]; then
      jq -R 'fromjson? // empty' <<<"$out" 2>/dev/null \
        | jq -s -r '[.[] | select(.type == "result" and .is_error != true) | .result] | last // empty'
      return "$rc"
    fi
    read -r reset type <<<"$hit"
    waits=$((waits + 1))
    if [ "$waits" -gt "$RALPH_LIMIT_MAX_WAITS" ] || ! ralph_wait_for_reset "$reset" "$type" >&2; then
      ralph_say warn "⏸ Limit użycia ($type) — reset: $([ "${reset:-0}" -gt 0 ] && ralph_clock "$reset" || echo "nieznana godzina"), za daleko, żeby czekać. Po resecie wklej: ${RALPH_LAUNCH_CMD:-ralph-once}" >&2
      return "$RALPH_EXIT_USAGE_LIMIT"
    fi
  done
}

# jq definitions used by the stream renderer. Expect $color ("1" = ANSI on), $w (terminal
# width, 0 = do not clip) and $cwd (stripped from paths).
RALPH_RENDER_JQ_DEFS='
  def clip: if $w > 0 and length > $w then .[0:$w - 1] + "…" else . end;
  def paint($code): if $color == "1" then "\u001b[" + $code + "m" + . + "\u001b[0m" else . end;
  def line1: tostring | (split("\n")[0] // "") | ltrimstr($cwd);
  def step: ("  " + .) | clip | paint("2");
  def bad: ("  " + .) | clip | paint("31");
  def warn: ("  " + .) | clip | paint("38;5;208");
  def narr: "› " + (tostring | gsub("^\\s+|\\s+$"; "") | gsub("\n"; "\n  "));
'

# stdin: Claude `stream-json` lines -> stdout: what the worker is doing, for a human. A pure
# filter. The model's own text is the narration (`› …`); tool calls are dimmed one-line steps
# (`▸ Tool: detail`, clipped to the terminal width); a tool call the CLI rejected is a red `✗`.
# Background work is spelled out: a task started or moved to the background (`⧗`), waiting for it
# at the end of a turn (`…`), its completion waking the worker (`↻`). Usage-limit warnings are
# orange. `claude -p` emits one `result` per turn and wakes up for every finished background task,
# so the report is printed once, at the end of the stream: the last turn that did work
# (num_turns > 1) — a reply to a stale notification is not the report. A last result with
# is_error (e.g. session limit) is printed red as an interruption instead.
ralph_render_stream() {
  { cat; printf '%s\n' '{"type":"ralph_eof"}'; } |
  jq -n -R --unbuffered -r --arg cwd "$PWD/" --arg color "${RALPH_COLOR:-0}" \
    --arg title "${RALPH_REPORT_TITLE:-Raport workera}" \
    --argjson w "$(ralph_term_cols)" "$RALPH_RENDER_JQ_DEFS"'
    def flush: if .text then .out += [.text | narr] | .text = null else . end;
    def task($id): .tasks[$id] // "";
    def until_time: if (.resetsAt // null) != null then ", reset " + (.resetsAt | strflocaltime("%H:%M")) else "" end;
    def report:
      (.results | last) as $last
      | if $last == null then
          "\n" + ("── Worker zakończył się bez raportu ──" | paint("31"))
        elif $last.err then
          "\n" + ("── Worker przerwany ──\n" + $last.text | paint("31"))
        else
          (([.results[] | select((.err | not) and .turns > 1)] | last) // $last) as $r
          | "\n── " + $title + " ──\n" + $r.text
        end;
    foreach (inputs | (fromjson? // empty)) as $e (
      {text: null, out: [], bg: 0, tasks: {}, bgids: {}, results: [], limit: "allowed"};
      .out = []
      | if $e.type == "assistant" then
          reduce (($e.message.content // [])[]?) as $c (.;
            if $c.type == "text" and (($c.text // "") | test("\\S")) then
              flush | .text = $c.text
            elif $c.type == "tool_use" then
              flush
              | (($c.input // {}) as $i
                 | ($i.description // $i.command // $i.file_path // $i.notebook_path // $i.pattern
                    // $i.path // $i.url // $i.query // $i.reason // "" | line1) as $d
                 | .out += ["▸ \($c.name)" + (if $d == "" then "" else ": \($d)" end) | step])
            else . end)
        elif $e.type == "user" then
          reduce (($e.message.content // [])[]? | select(.type == "tool_result" and .is_error == true)) as $r (.;
            .out += ["✗ " + ($r.content
                             | if type == "array" then map(.text? // "") | join(" ") else tostring end
                             | gsub("</?tool_use_error>"; "") | line1) | bad])
        elif $e.type == "system" then
          if $e.subtype == "task_started" then
            .tasks[$e.task_id] = ($e.description // "" | line1)
            | if $e.is_backgrounded == true then
                .bgids[$e.task_id] = true | .out += ["⧗ W tle: " + task($e.task_id) | step]
              else . end
          elif $e.subtype == "task_updated" and $e.patch.is_backgrounded == true then
            .bgids[$e.task_id] = true
            | .out += ["⧗ Przeniesione w tle (przekroczony limit czasu komendy): " + task($e.task_id) | step]
          elif $e.subtype == "background_tasks_changed" then
            .bg = (($e.tasks // []) | length)
          elif $e.subtype == "task_notification" and .bgids[$e.task_id] then
            if $e.status == "completed" then
              .out += ["↻ Zadanie w tle zakończone: " + task($e.task_id) | step]
            else
              .out += ["↻ Zadanie w tle przerwane (\($e.status)): " + task($e.task_id) | warn]
            end
          else . end
        elif $e.type == "rate_limit_event" then
          ($e.rate_limit_info // {}) as $l
          | if ($l.status // "allowed") == .limit then .
            else
              .limit = ($l.status // "allowed")
              | if .limit == "allowed" then .
                elif .limit == "rejected" then
                  .out += ["✗ Limit użycia wyczerpany (\($l.rateLimitType // "?"))" + ($l | until_time) | bad]
                else
                  .out += ["⚠ Limit użycia blisko (\($l.rateLimitType // "?")"
                           + (if $l.utilization then ": \($l.utilization * 100 | round)%" else "" end)
                           + ")" + ($l | until_time) | warn]
                end
            end
        elif $e.type == "result" then
          .text = null
          | .results += [{text: ($e.result // "" | tostring), err: ($e.is_error == true), turns: ($e.num_turns // 0)}]
          | if .bg > 0 and ($e.is_error != true) then
              .out += [($e.result // "" | tostring | gsub("^\\s+"; "") | split("\n")[0] | narr),
                       ("… Czekam na zadania w tle (\(.bg)); CLI wznowi workera, gdy się skończą." | step)]
            else . end
        elif $e.type == "ralph_eof" then
          flush | .out += [report]
        else . end;
      .out[])'
}

# $1: a stream-json log file -> the session id to hand to `claude --resume`.
ralph_stream_session_id() {
  jq -R -r 'fromjson? | select(.session_id != null) | .session_id' "$1" 2>/dev/null | tail -n 1
}

# Claude worker, unattended: `claude -p` in auto mode with a streamed JSON transcript. The
# full stream lands in <git dir>/ralph-logs/ (outside the work tree, so `git status` stays
# clean); the screen gets one line per step plus the final summary; the run ends with the
# `claude --resume <id>` line. $4 labels the log file (issue-<n>, `local`). $5 = `readonly`
# takes away the file-editing tools (przegląd heavy). $6: a session id to resume instead of
# starting a new one ($3 is then the follow-up message). The log path is left in RALPH_LAST_LOG.
ralph_run_claude_worker() {
  local model="$1" effort="$2" prompt="$3" label="${4:-run}" access="${5:-}" session="${6:-}"
  local dir log rc id deny=() resume=()
  dir=$(git rev-parse --git-path ralph-logs 2>/dev/null) || dir=""
  if [ -n "$dir" ] && mkdir -p "$dir" 2>/dev/null; then
    log="$dir/$(date +%Y%m%d-%H%M%S)-${label}.jsonl"
  else
    log=$(mktemp)
  fi

  RALPH_LAST_LOG="$log"
  # --disallowedTools is variadic: it must be followed by another option, never by the prompt.
  [ "$access" = readonly ] && deny=(--disallowedTools Edit Write NotebookEdit)
  [ -n "$session" ] && resume=(--resume "$session")
  claude -p ${resume[@]+"${resume[@]}"} ${deny[@]+"${deny[@]}"} --permission-mode auto --output-format stream-json --verbose \
    --model "$model" --effort "$effort" "$prompt" \
    | tee "$log" | ralph_render_stream
  rc=${PIPESTATUS[0]}

  echo
  ralph_say dim "Zapis runu: $log"
  id=$(ralph_stream_session_id "$log")
  [ -n "$id" ] && ralph_say dim "Wznów sesję: claude --resume $id"
  return "$rc"
}

# stdin: an issue's label names, one per line -> `afk` (has ready-for-agent: unattended) or
# `hitl` (does not: a human is present, the worker runs interactively).
ralph_worker_mode() {
  if grep -qx 'ready-for-agent'; then echo afk; else echo hitl; fi
}

# Claude HITL session: the interactive CLI in auto mode, so the human can talk to the worker.
# Under a run log stdout is a pipe; the session gets the terminal back (fds 3/4) and stays out
# of the log — its transcript is the runtime's own session.
ralph_run_claude_interactive() {
  local model="$1" effort="$2" prompt="$3"
  if [ "${RALPH_TERM_FDS:-}" = 1 ]; then
    claude --permission-mode auto --model "$model" --effort "$effort" "$prompt" >&3 2>&4
  else
    claude --permission-mode auto --model "$model" --effort "$effort" "$prompt"
  fi
}

# $5: mode, `afk` (default, unattended), `hitl` (interactive session with a human present) or
# `review` (unattended, without file-editing tools: the przegląd heavy).
ralph_run_worker() {
  local model="$1" effort="$2" prompt="$3" label="${4:-}" mode="${5:-afk}" access=""
  [ "$mode" = review ] && access=readonly

  if [ "$mode" = "hitl" ]; then
    ralph_run_claude_interactive "$model" "$effort" "$prompt"
  else
    ralph_run_claude_worker "$model" "$effort" "$prompt" "$label" "$access"
  fi
}

# --- Limit użycia (ADR 0017): a Claude run stopped by an exhausted usage window is resumed, ---
# --- not failed. The ślad lets a later run pick the session up when this process is gone.  ---

# Longest in-process wait for a reset, in seconds; a later reset ends the run, ślad left behind.
RALPH_LIMIT_WAIT_MAX="${RALPH_LIMIT_WAIT_MAX:-21600}"
# Seconds added to the announced reset, so the first call after it is not refused again.
RALPH_LIMIT_MARGIN="${RALPH_LIMIT_MARGIN:-60}"
# Waits for a reset in one process before giving up: guards against a limit that never lifts.
RALPH_LIMIT_MAX_WAITS=3
# What a resumed session is told.
RALPH_RESUME_PROMPT='Your previous turn was cut off by the account usage limit, which has now reset. Continue the task from exactly where you stopped: check the working tree and the issue first, then finish the remaining steps.'

# Pure. $1: a Claude stream-json log (stdin when absent) -> "<resetsAt epoch> <limit type>" when
# the run ended on a usage limit, nothing otherwise. The signal is the runtime's own error as the
# last assistant message (`api_error: usage_limit_reached`); a failed last result after a
# `rejected` rate-limit event counts too. resetsAt is 0 when the stream does not say.
ralph_stream_usage_limit() {
  jq -R 'fromjson? // empty' ${1:+"$1"} 2>/dev/null | jq -s -r '
    ([.[] | select(.type == "rate_limit_event") | .rate_limit_info // {}] | last) as $rl
    | ([.[] | select(.type == "assistant")] | last) as $a
    | ([.[] | select(.type == "result")] | last) as $res
    | if ($a.api_error // "") == "usage_limit_reached" then ($a.api_error_params.rate_limit_info // $rl // {})
      elif ($res.is_error // false) == true and ($rl.status // "") == "rejected" then $rl
      else empty end
    | "\(.resetsAt // 0) \(.rateLimitType // "?")"'
}

# $1: epoch -> "HH:MM" for today, "DD.MM HH:MM" otherwise.
ralph_clock() {
  jq -rn --argjson t "$1" '
    if ($t | strflocaltime("%F")) == (now | strflocaltime("%F")) then $t | strflocaltime("%H:%M")
    else $t | strflocaltime("%d.%m %H:%M") end'
}

# Waits, by the wall clock, until the reset $1 (epoch) plus RALPH_LIMIT_MARGIN; $2: limit type.
# Sleeps in short steps and re-reads the clock, so a machine that slept through the reset goes on
# at once. rc 1 without waiting when the reset is unknown or more than RALPH_LIMIT_WAIT_MAX away.
ralph_wait_for_reset() {
  local reset="${1:-0}" type="$2" target now left
  [ "$reset" -gt 0 ] 2>/dev/null || return 1
  target=$((reset + RALPH_LIMIT_MARGIN))
  now=$(date +%s)
  [ $((target - now)) -le "$RALPH_LIMIT_WAIT_MAX" ] || return 1
  [ "$target" -gt "$now" ] || return 0
  ralph_say warn "⏸ Limit użycia ($type) — czekam na reset do $(ralph_clock "$target"), potem wznawiam."
  ralph_notify "Ralph: limit użycia" "Czekam na reset limitu do $(ralph_clock "$target")."
  while now=$(date +%s); [ "$now" -lt "$target" ]; do
    left=$((target - now))
    [ "$left" -gt 60 ] && left=60
    sleep "$left"
  done
}

# The ślad lives next to the lock: per worktree, outside the work tree.
ralph_limit_trace_path() {
  git rev-parse --git-path ralph-limit 2>/dev/null
}

# Writes the ślad: one key=value line per argument, then the caller's RALPH_LIMIT_CONTEXT lines.
ralph_limit_trace_write() {
  local f
  f=$(ralph_limit_trace_path) || return 1
  { printf '%s\n' "$@"; [ -z "${RALPH_LIMIT_CONTEXT:-}" ] || printf '%s\n' "$RALPH_LIMIT_CONTEXT"; } > "$f"
}

# $1: key -> its value in the ślad; rc 1 when there is no ślad.
ralph_limit_trace_get() {
  local f
  f=$(ralph_limit_trace_path) && [ -f "$f" ] || return 1
  sed -n "s/^$1=//p" "$f" | head -1
}

ralph_limit_trace_clear() {
  local f
  f=$(ralph_limit_trace_path) && rm -f "$f"
}

# Pure. Why a ślad no longer fits, or nothing when it does. $1: phase (worker|review); $2: issue
# state (open|closed); $3: "true" when it has ready-for-agent; $4: branch in the ślad; $5: current
# branch. The issue must be as the interrupted run left it: open and AFK for the worker, closed
# (by the worker) for the przegląd heavy.
ralph_limit_trace_stale() {
  if [ "$4" != "$5" ]; then
    echo "run przerwano na gałęzi $4, a bieżąca to ${5:-(brak)}"
    return 0
  fi
  case "$1" in
    review) [ "$2" = closed ] || echo "przerwany był przegląd heavy, a issue nie jest już zamknięte" ;;
    *)
      if [ "$2" != open ]; then echo "issue jest już zamknięte"
      elif [ "$3" != true ]; then echo "issue nie ma już ready-for-agent"
      fi ;;
  esac
}

# Should this run resume from the ślad? $1: the issue/epic argument (may be empty).
# rc 0 = resume. rc 1 = run as usual: no ślad; a ślad of another issue (left alone); GitHub did
# not answer (left alone); or a stale ślad, including one left by the retired Codex runtime
# (removed, one line on screen).
ralph_limit_trace_applies() {
  local arg="$1" f issue state ready reason
  f=$(ralph_limit_trace_path) && [ -f "$f" ] || return 1
  issue=$(ralph_limit_trace_get issue)
  if [ "$(ralph_limit_trace_get runtime)" != claude ]; then
    ralph_say dim "Usuwam ślad limitu użycia (issue #${issue}) z runtime'u, którego Ralph już nie uruchamia."
    ralph_limit_trace_clear
    return 1
  fi
  if [ -n "$arg" ] && [ "$arg" != "$issue" ] && [ "$arg" != "$(ralph_issue_parent "$issue" 2>/dev/null)" ]; then
    ralph_say dim "Ślad limitu użycia dotyczy issue #${issue}, nie #${arg} — zostawiam go: $f"
    return 1
  fi
  state=$(gh issue view "$issue" --json state --jq '.state | ascii_downcase' 2>/dev/null)
  ready=$(gh issue view "$issue" --json labels --jq 'any(.labels[]; .name == "ready-for-agent")' 2>/dev/null)
  if [ -z "$state" ]; then
    ralph_say warn "Nie udało się sprawdzić issue #${issue} ze śladu limitu użycia (gh) — zostawiam ślad, działam według zwykłych reguł."
    return 1
  fi
  reason=$(ralph_limit_trace_stale "$(ralph_limit_trace_get phase)" "$state" "$ready" \
    "$(ralph_limit_trace_get branch)" "$(git branch --show-current 2>/dev/null)")
  if [ -n "$reason" ]; then
    ralph_say warn "Usuwam nieaktualny ślad limitu użycia (issue #${issue}): ${reason}. Działam według zwykłych reguł."
    ralph_limit_trace_clear
    return 1
  fi
}

# The stop message when a limit cannot be waited out here. $1: resetsAt (0 = unknown), $2: type.
ralph_limit_stop_message() {
  local when="nieznana godzina"
  [ "${1:-0}" -gt 0 ] 2>/dev/null && when=$(ralph_clock "$1")
  ralph_say warn "⏸ Limit użycia ($2) przerwał run; reset: $when — nie czekam na niego w tym procesie.
Ślad zapisany ($(ralph_limit_trace_path)). Po resecie wklej: ${RALPH_LAUNCH_CMD:-ralph-once}
Ralph wznowi przerwaną sesję, a niezacommitowane zmiany w drzewie są wtedy w porządku."
}

# Runs a worker (as ralph_run_worker) and carries the run over a usage limit (ADR 0017): on
# a limit it writes the ślad, waits for the reset when it is close enough and resumes the same
# session, as often as needed up to RALPH_LIMIT_MAX_WAITS. A run that ends on its own removes the
# ślad. $1-$5 as ralph_run_worker; $6: phase recorded in the ślad (worker|review); $7: a session
# to resume (a restart from the ślad), waiting for its reset first. The ślad also gets the
# caller's RALPH_LIMIT_CONTEXT (key=value lines). Sets RALPH_LIMIT_STOP: empty = the run ended on
# its own; `limit` = stopped on a limit it could not wait out; `resume-failed` = the runtime did
# not take the session up. In both the ślad stays and the message is printed. rc: the last run's.
ralph_run_worker_through_limit() {
  local model="$1" effort="$2" prompt="$3" label="$4" mode="${5:-afk}" phase="${6:-worker}" session="${7:-}"
  local rc=0 hit reset type waits=0 access=""
  [ "$mode" = review ] && access=readonly
  RALPH_LIMIT_STOP=""
  if [ -n "$session" ]; then
    reset=$(ralph_limit_trace_get resets_at); type=$(ralph_limit_trace_get limit)
    if ! ralph_wait_for_reset "$reset" "$type"; then
      RALPH_LIMIT_STOP=limit
      ralph_limit_stop_message "$reset" "$type"
      return 1
    fi
  fi
  while :; do
    if [ -n "$session" ]; then
      ralph_say dim "Wznawiam sesję $session po limicie użycia..."
      ralph_run_claude_worker "$model" "$effort" "$RALPH_RESUME_PROMPT" "${label}-wznowienie" "$access" "$session"
      rc=$?
      if [ -z "$(ralph_stream_session_id "$RALPH_LAST_LOG")" ]; then
        RALPH_LIMIT_STOP=resume-failed
        ralph_say err "✗ Nie udało się wznowić sesji $session po limicie użycia (kod $rc): runtime jej nie podjął.
Zapis próby: $RALPH_LAST_LOG
Ślad zostaje ($(ralph_limit_trace_path)): kolejne uruchomienie spróbuje znowu; usuń go, żeby wrócić do zwykłych reguł."
        return "$rc"
      fi
    else
      ralph_run_worker "$model" "$effort" "$prompt" "$label" "$mode"
      rc=$?
    fi
    { [ "$mode" != hitl ] && [ -n "$RALPH_LAST_LOG" ]; } || return "$rc"
    hit=$(ralph_stream_usage_limit "$RALPH_LAST_LOG")
    if [ -z "$hit" ]; then
      # A session here means this call wrote or was handed the ślad; leave anyone else's alone.
      [ -z "$session" ] || ralph_limit_trace_clear
      return "$rc"
    fi
    read -r reset type <<<"$hit"
    session=$(ralph_stream_session_id "$RALPH_LAST_LOG")
    # Nothing to resume without a session: the run counts as it always did.
    [ -n "$session" ] || return "$rc"
    ralph_limit_trace_write "runtime=claude" "phase=$phase" "session=$session" "model=$model" \
      "effort=$effort" "label=$label" "resets_at=$reset" "limit=$type" \
      "branch=$(git branch --show-current 2>/dev/null)"
    waits=$((waits + 1))
    if [ "$waits" -gt "$RALPH_LIMIT_MAX_WAITS" ] || ! ralph_wait_for_reset "$reset" "$type"; then
      RALPH_LIMIT_STOP=limit
      ralph_limit_stop_message "$reset" "$type"
      return "$rc"
    fi
  done
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
        ralph_say err "Ralph już działa w tym worktree; tryb nieinteraktywny przerywa." >&2
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
    ralph_say warn "⚠️  Ralph zostawił niezacommitowane zmiany w drzewie roboczym.
   Sprawdź (git status) i domknij je, zanim odpalisz kolejny przebieg."
  fi
}

# --- Epics (ADR 0012). Pure JSON helpers: no gh calls, so they can be unit-tested. ---
# "epics" JSON is an array of {number, started, open:[sub-issue numbers]}, where `started`
# means at least one sub-issue is already closed.

# stdin: issues array; $1: epics JSON. Adds `parent` (epic number or null) to every issue.
ralph_annotate_parents() {
  jq -c --argjson epics "$1" \
    'map(. as $i | .parent = (first($epics[] | select(.open | index($i.number)) | .number) // null))'
}

# stdin: issues array (with `parent`); $1: epics JSON. If a started epic has candidate
# sub-issues, keep only those of the oldest (lowest number) such epic; otherwise pass through.
ralph_filter_started_epic() {
  jq -c --argjson epics "$1" '
    . as $issues
    | ([$epics[] | select(.started) | .number as $e | select(any($issues[]; .parent == $e)) | $e] | min) as $pick
    | if $pick == null then $issues else [$issues[] | select(.parent == $pick)] end'
}

# stdin: issues array (with `parent`); $1: epic number. Keeps only that epic's sub-issues.
ralph_epic_issues() {
  jq -c --argjson epic "$1" '[.[] | select(.parent == $epic)]'
}

# stdin: issues array (already unblocked, each with `labels: [{name}]`). ADR 0013 order inside an
# epic: AFK (has `ready-for-agent`) first; only when none is left, the HITL ones (no label).
ralph_epic_stage() {
  jq -c '
    def afk: any(.labels[]?; .name == "ready-for-agent");
    ([.[] | select(afk)]) as $a
    | if ($a | length) > 0 then $a else [.[] | select(afk | not)] end'
}

# Pure. stdin: candidate issues (already unblocked and staged). Prints the lowest issue number,
# or nothing. Used instead of the model selector inside an epic (sub-issues are published in
# dependency order, so the lowest free number is the next planned slice) and whenever there is a
# single candidate (ADR 0013, update).
ralph_pick_first() {
  jq -r '[.[].number] | min // empty'
}

# Exit codes of once.sh (documented in its header).
RALPH_EXIT_DONE=0        # issue closed
RALPH_EXIT_ERROR=1       # error or refusal
RALPH_EXIT_NOTHING=2     # nothing to do
RALPH_EXIT_AFK_FAILED=3  # AFK run left the issue open, still ready-for-agent
RALPH_EXIT_DISCOVERED=4  # AFK run left it open without ready-for-agent (discovered HITL)
RALPH_EXIT_HITL_OPEN=5   # HITL session ended, issue open without ready-for-agent
RALPH_EXIT_HITL_TO_AFK=6 # HITL session ended, issue open with ready-for-agent restored
RALPH_EXIT_REVIEW_RETRY=7 # przegląd heavy failed once: issue reopened for one fix
RALPH_EXIT_USAGE_LIMIT=8  # a usage limit stopped the run; ślad left for a resume (ADR 0017)

# $1: exit code of a finished worker run (from ralph_run_outcome); $2: issue number -> the
# one-line verdict, coloured: green done, orange waiting for a human, red failure.
ralph_outcome_message() {
  local code="$1" num="$2"
  case "$code" in
    "$RALPH_EXIT_DONE") ralph_say ok "✓ Issue #${num} zamknięte." ;;
    "$RALPH_EXIT_HITL_TO_AFK") ralph_say ok "✓ Issue #${num} oddane pętli (przywrócone ready-for-agent)." ;;
    "$RALPH_EXIT_AFK_FAILED") ralph_say err "✗ Issue #${num} nie zostało domknięte (nadal ma ready-for-agent)." ;;
    "$RALPH_EXIT_DISCOVERED") ralph_say warn "⚠ Issue #${num} wymaga człowieka: worker zdjął ready-for-agent (odkryty HITL)." ;;
    "$RALPH_EXIT_HITL_OPEN") ralph_say warn "⚠ Sesja HITL skończona, issue #${num} nadal otwarte bez ready-for-agent." ;;
    "$RALPH_EXIT_REVIEW_RETRY") ralph_say warn "⚠ Przegląd odrzucił issue #${num} — otwarte ponownie, poprawka w następnej iteracji." ;;
    *) ralph_say err "✗ Nie udało się odczytać stanu issue #${num} po runie." ;;
  esac
}

# Pure: the exit code for a finished worker run. $1: mode (afk|hitl); $2: issue state
# (open|closed); $3: "true" when the issue has `ready-for-agent`. Anything but a clean
# `closed`/`open` reading is an error.
ralph_run_outcome() {
  local mode="$1" state="$2" label="$3"
  case "$state" in
    closed) echo "$RALPH_EXIT_DONE"; return 0 ;;
    open) ;;
    *) echo "$RALPH_EXIT_ERROR"; return 0 ;;
  esac
  if [ "$mode" = hitl ]; then
    if [ "$label" = true ]; then echo "$RALPH_EXIT_HITL_TO_AFK"; else echo "$RALPH_EXIT_HITL_OPEN"; fi
  else
    if [ "$label" = true ]; then echo "$RALPH_EXIT_AFK_FAILED"; else echo "$RALPH_EXIT_DISCOVERED"; fi
  fi
}

# --- Przegląd heavy (ADR 0016): a stronger model reviews a closed heavy sub-issue. ---

# Marks a failed przegląd's comment; counting them is how a second failure is recognised.
RALPH_REVIEW_FAIL_MARKER='<!-- ralph-przeglad: FAIL -->'

# Pure. stdin: the reviewer's report -> OK, FAIL, or nothing when it gave no verdict. The first
# `REVIEW: OK|FAIL` line counts, so a preamble before it does no harm.
ralph_review_verdict() {
  sed -n -E 's/^[[:space:]*`]*REVIEW:[[:space:]]*(OK|FAIL)([^[:alnum:]].*)?$/\1/p' | head -1
}

# Pure. $1: verdict (OK|FAIL|empty), $2: failed przeglądy of this issue before this one -> ok
# (accept), retry (reopen for one fix), stop (second failure: reopen, stop for a human) or
# error (no verdict: reopen, the run fails rather than accept unreviewed work).
ralph_review_action() {
  case "$1" in
    OK) echo ok ;;
    FAIL) if [ "${2:-0}" -ge 1 ]; then echo stop; else echo retry; fi ;;
    *) echo error ;;
  esac
}

# Pure. $1: a worker's stream log -> its final report text (the last non-error `result`).
ralph_last_report() {
  jq -R 'fromjson? // empty' "$1" 2>/dev/null \
    | jq -s -r '[.[] | select(.type == "result" and .is_error != true) | .result] | last // ""'
}

# Pure. $1: a worker's stream log -> what the run cost, for a human, or nothing when the log
# carries no such data. Claude reports `total_cost_usd` per `result`; it is cumulative for the
# session, and max never double-counts either way.
ralph_run_cost() {
  jq -R 'fromjson? // empty' "$1" 2>/dev/null | jq -s -r '
    [.[] | select(.type == "result") | .total_cost_usd // empty] | max
    | if . == null then "" else "$" + ((. * 100 | round) / 100 | tostring) end'
}

# Failed przeglądy recorded on issue $1 so far; 0 when GitHub cannot answer.
ralph_review_fail_count() {
  gh api --paginate "repos/{owner}/{repo}/issues/$1/comments" 2>/dev/null \
    | jq -s --arg m "$RALPH_REVIEW_FAIL_MARKER" '[add // [] | .[] | select(.body | contains($m))] | length' 2>/dev/null \
    || echo 0
}

# The latest failed przegląd's comment on issue $1 (without the marker), or nothing. The worker
# gets it with the issue: the issue body alone would not tell it what to fix.
ralph_review_notes() {
  gh api --paginate "repos/{owner}/{repo}/issues/$1/comments" 2>/dev/null \
    | jq -s -r --arg m "$RALPH_REVIEW_FAIL_MARKER" \
        '[add // [] | .[] | select(.body | contains($m)) | .body] | last // "" | sub($m; "") | gsub("^\\s+|\\s+$"; "")' 2>/dev/null
}

# Runs the przegląd heavy of closed issue $2 over the commits $3..HEAD, then acts on the verdict.
# $3: the issue as the worker got it, $4: a przegląd session to resume (a restart
# from the ślad, ADR 0017). Leaves in RALPH_REVIEW_EXIT the exit code once.sh should report
# instead of the issue's state, or nothing when the przegląd accepted it. A przegląd stopped by a
# usage limit gives no verdict and touches nothing: the issue stays closed, the ślad remembers it.
ralph_heavy_review() {
  local num="$1" base="$2" issue="$3" session="${4:-}" prompt report verdict prior action cost body
  RALPH_REVIEW_EXIT=""
  ralph_review_model
  prompt=$(ralph_render_prompt "$SCRIPT_DIR/prompt-review.md")
  ralph_say dim "Przegląd heavy issue #${num} na $(ralph_model_display "$RALPH_REVIEW_MODEL" "$RALPH_REVIEW_EFFORT")..."
  RALPH_LAST_LOG=""
  RALPH_REPORT_TITLE="Raport przeglądu" ralph_run_worker_through_limit "$RALPH_REVIEW_MODEL" "$RALPH_REVIEW_EFFORT" \
    "Issue under review: $issue Commit range to review: ${base}..HEAD $prompt" "review-${num}" review review "$session"
  case "$RALPH_LIMIT_STOP" in
    limit) RALPH_REVIEW_EXIT="$RALPH_EXIT_USAGE_LIMIT"; return 0 ;;
    resume-failed) RALPH_REVIEW_EXIT="$RALPH_EXIT_ERROR"; return 0 ;;
  esac
  report=""; [ -n "$RALPH_LAST_LOG" ] && report=$(ralph_last_report "$RALPH_LAST_LOG")
  cost=""; [ -n "$RALPH_LAST_LOG" ] && cost=$(ralph_run_cost "$RALPH_LAST_LOG")
  [ -n "$cost" ] && ralph_say dim "Koszt przeglądu: $cost"
  verdict=$(ralph_review_verdict <<<"$report")
  prior=$(ralph_review_fail_count "$num")
  action=$(ralph_review_action "$verdict" "$prior")
  case "$action" in
    ok)
      ralph_say ok "✓ Przegląd heavy przyjął issue #${num}."
      gh issue comment "$num" --body "Przegląd heavy: OK.

$report" >/dev/null 2>&1
      return 0 ;;
    retry|stop)
      body="${RALPH_REVIEW_FAIL_MARKER}
Przegląd heavy odrzucił implementację (próba $((prior + 1)) z 2).

$report" ;;
    *)
      body="Przegląd heavy nie dał werdyktu (brak linii REVIEW: OK / REVIEW: FAIL) — issue wraca do pętli bez akceptacji. Log: ${RALPH_LAST_LOG:-brak}" ;;
  esac
  gh issue reopen "$num" >/dev/null 2>&1
  gh issue edit "$num" --add-label ready-for-agent >/dev/null 2>&1
  gh issue comment "$num" --body "$body" >/dev/null 2>&1
  case "$action" in
    retry) RALPH_REVIEW_EXIT="$RALPH_EXIT_REVIEW_RETRY" ;;
    stop)  ralph_say err "✗ Przegląd heavy odrzucił issue #${num} drugi raz — zatrzymuję, potrzebny człowiek."
           RALPH_REVIEW_EXIT="$RALPH_EXIT_AFK_FAILED" ;;
    *)     ralph_say err "✗ Przegląd heavy issue #${num} nie dał werdyktu — otwieram issue ponownie."
           RALPH_REVIEW_EXIT="$RALPH_EXIT_ERROR" ;;
  esac
}

# --- Bramka uruchamiana przez pętlę (ADR 0018): the ralph-gate: command, run after a closed issue. ---

# Marks a red bramka's comment; counting them is how a second red on the same issue is recognised.
# Distinct from the przegląd marker, so neither kind of failure counts as the other.
RALPH_GATE_FAIL_MARKER='<!-- ralph-bramka: FAIL -->'

# Pure. $1: the gate command's exit code, $2: red bramki of this issue before this one -> ok
# (green), retry (red: reopen for one fix) or stop (second red: reopen, stop for a human).
ralph_gate_action() {
  if [ "$1" = 0 ]; then echo ok
  elif [ "${2:-0}" -ge 1 ]; then echo stop
  else echo retry
  fi
}

# Pure. $1: a gate log -> its tail, bounded in lines and bytes so a comment stays far below
# GitHub's limit. Bytes cut in the middle of a character are dropped.
ralph_gate_tail() {
  tail -n 80 "$1" | tail -c 8000 | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; }
}

# Red bramki recorded on issue $1 so far; 0 when GitHub cannot answer.
ralph_gate_fail_count() {
  gh api --paginate "repos/{owner}/{repo}/issues/$1/comments" 2>/dev/null \
    | jq -s --arg m "$RALPH_GATE_FAIL_MARKER" '[add // [] | .[] | select(.body | contains($m))] | length' 2>/dev/null \
    || echo 0
}

# Runs the ralph-gate: command of this repo (read from CLAUDE.md in the repo root, run there) after
# the run closed issue $1, and acts on the result. Full output goes to a log in the git dir's
# ralph-logs/; the screen gets the start, the duration and the verdict. Leaves in RALPH_GATE_EXIT
# the exit code once.sh should report, or nothing when the bramka is green. The command's own exit
# code decides: the output goes to a file, not through a pipe that would swallow it. No gate line
# (the strażnik was skipped) is an error, never a silent green.
ralph_gate_check() {
  local num="$1" root cmd dir log start rc prior action body
  RALPH_GATE_EXIT=""
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=.
  cmd=$(ralph_contract_section "$root/$(ralph_contract_file)" 2>/dev/null | ralph_gate_command) || cmd=""
  if [ -z "$cmd" ]; then
    ralph_say err "✗ Brak linii ralph-gate: w sekcji ## Ralph — nie uznaję issue #${num} za zrobione bez bramki. Uruchom /ralph-konfiguracja."
    RALPH_GATE_EXIT="$RALPH_EXIT_ERROR"
    return 0
  fi
  dir="$(git rev-parse --absolute-git-dir 2>/dev/null)/ralph-logs"
  if mkdir -p "$dir" 2>/dev/null; then log="$dir/$(date +%Y%m%d-%H%M%S)-gate-${num}.log"; else log=$(mktemp); fi
  ralph_say dim "Bramka: uruchamiam po issue #${num}: ${cmd}"
  start=$SECONDS
  (cd "$root" && bash -c "$cmd") </dev/null >"$log" 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then
    ralph_say ok "✓ Bramka zielona ($((SECONDS - start)) s). Log: $log"
    return 0
  fi
  ralph_say err "✗ Bramka czerwona (kod ${rc}, $((SECONDS - start)) s). Log: $log"
  prior=$(ralph_gate_fail_count "$num")
  action=$(ralph_gate_action "$rc" "$prior")
  body="${RALPH_GATE_FAIL_MARKER}
Bramka (\`${cmd}\`) jest czerwona po zamknięciu issue (kod ${rc}, próba $((prior + 1)) z 2). Pełne wyjście: ${log}

Koniec wyjścia:

\`\`\`\`
$(ralph_gate_tail "$log")
\`\`\`\`"
  gh issue reopen "$num" >/dev/null 2>&1
  gh issue edit "$num" --add-label ready-for-agent >/dev/null 2>&1
  gh issue comment "$num" --body "$body" >/dev/null 2>&1
  case "$action" in
    retry) ralph_say warn "Issue #${num} otwarte ponownie — poprawka w następnej iteracji."
           RALPH_GATE_EXIT="$RALPH_EXIT_REVIEW_RETRY" ;;
    *)     ralph_say err "✗ Bramka czerwona drugi raz na issue #${num} — zatrzymuję, potrzebny człowiek."
           RALPH_GATE_EXIT="$RALPH_EXIT_AFK_FAILED" ;;
  esac
}

# What the loop checks itself once a run has finished, in order: the bramka after any run that
# closed issue $1 (AFK, HITL, a resumed worker), then — only after a green one, and only for an
# AFK heavy issue — the przegląd heavy. $2: mode, $3: complexity, $4: HEAD before the worker,
# $5: the issue text. Leaves RALPH_GATE_EXIT / RALPH_REVIEW_EXIT (see their functions). An issue
# the run left open is none of its business.
ralph_verify_closed() {
  local num="$1" mode="$2" complexity="$3" pre_head="$4" issue="$5"
  RALPH_GATE_EXIT=""
  RALPH_REVIEW_EXIT=""
  [ "$(gh issue view "$num" --json state --jq '.state | ascii_downcase' 2>/dev/null)" = closed ] || return 0
  ralph_gate_check "$num"
  [ -z "$RALPH_GATE_EXIT" ] || return 0
  # Przegląd heavy (ADR 0016) follows the label alone, --force-model included; a HITL session
  # had a human present.
  if [ "$mode" = afk ] && [ "$complexity" = heavy ] && [ -n "$pre_head" ]; then
    ralph_heavy_review "$num" "$pre_head" "$issue"
  fi
}

# Pure. stdin: issues array as the REST API returns it (with `issue_dependencies_summary`).
# Keeps only free issues: no open blocker in GitHub's native "blocked by" relation. The body
# text — including its "Blocked by" section — is never read. No summary -> dropped (fail-closed).
ralph_filter_unblocked() {
  jq -c 'map(select(.issue_dependencies_summary.blocked_by == 0))'
}

# All open issues (pull requests dropped) via the REST API, which — unlike `gh issue list` —
# carries `issue_dependencies_summary`. rc 1 when GitHub could not answer: callers must not
# mistake that for "no issues", or every blocker would silently vanish.
ralph_open_issues() {
  local out
  out=$(gh api --paginate "repos/{owner}/{repo}/issues?state=open&per_page=100" 2>/dev/null) || return 1
  jq -s -c 'add // [] | map(select(.pull_request | not)
    | {number, title, body, labels, issue_dependencies_summary})' <<<"$out"
}

# Open blockers of issue $1 as "#7, #9"; nothing when it has none; "?" when GitHub could not
# answer (diagnostics only, so it must not abort the caller).
ralph_open_blockers() {
  local out
  out=$(gh api --paginate "repos/{owner}/{repo}/issues/$1/dependencies/blocked_by" 2>/dev/null) \
    || { echo "?"; return 0; }
  jq -s -r 'add // [] | map(select(.state == "open") | "#\(.number)") | join(", ")' <<<"$out"
}

# stdin: issues array. One line per issue: "  #3 ← #7, #9" (its open blockers).
ralph_blocked_report() {
  local n
  for n in $(jq -r '.[].number'); do
    printf '  #%s ← %s\n' "$n" "$(ralph_open_blockers "$n")"
  done
}

# Pure decision: should the loop mark an epic for acceptance? $1: total sub-issues, $2: open
# sub-issues, $3: "true" when the epic already has `needs-human-test`. rc 0 = mark. An epic with
# no sub-issues is not done, it is unplanned.
ralph_epic_ready_to_mark() {
  [ "$1" -gt 0 ] && [ "$2" -eq 0 ] && [ "$3" != true ]
}

# Thin gh layer over ralph_epic_ready_to_mark. $1: epic number. Labels the epic
# `needs-human-test` and comments once; an already labelled epic is left alone. Returns 0 when
# it marked the epic.
ralph_mark_epic_if_ready() {
  local epic="$1" subs total open labeled
  subs=$(gh api --paginate "repos/{owner}/{repo}/issues/${epic}/sub_issues" 2>/dev/null | jq -s -c 'add // []') || return 1
  [ -n "$subs" ] || return 1
  total=$(jq 'length' <<<"$subs")
  open=$(jq '[.[] | select(.state == "open")] | length' <<<"$subs")
  labeled=$(gh issue view "$epic" --json labels --jq 'any(.labels[]; .name == "needs-human-test")' 2>/dev/null) || return 1
  ralph_epic_ready_to_mark "$total" "$open" "$labeled" || return 1
  gh label create needs-human-test --color 5319E7 \
    --description "Implemented; awaiting human verification" >/dev/null 2>&1 || true
  gh issue edit "$epic" --add-label needs-human-test >/dev/null 2>&1 || return 1
  gh issue comment "$epic" --body "Epic gotowy do odbioru: wszystkie sub-issues zamknięte. Scenariusz w sekcji ## Jak odebrać." >/dev/null 2>&1
  ralph_say ok "Epic #${epic}: wszystkie sub-issues zamknięte — oznaczony needs-human-test (do odbioru)."
}

# Runs ralph_mark_epic_if_ready over every open [PRD] issue, whoever closed the last sub-issue.
ralph_mark_ready_epics() {
  local e
  for e in $(gh issue list --state open --limit 200 --json number,title \
      --jq '.[] | select(.title | startswith("[PRD]")) | .number' 2>/dev/null); do
    ralph_mark_epic_if_ready "$e" || true
  done
}

# --- The end of a ralph-once run: what follows the worker, shared by a fresh run and a resumed one. ---

# A run stopped by a usage limit it could not wait out, or whose runtime would not take the
# session up: the ślad stays and nothing below may count the issue as done.
ralph_exit_on_limit_stop() {
  case "${RALPH_LIMIT_STOP:-}" in
    limit) exit "$RALPH_EXIT_USAGE_LIMIT" ;;
    resume-failed) exit "$RALPH_EXIT_ERROR" ;;
  esac
}

ralph_issue_text() {
  gh issue view "$1" --json number,title,body \
    --jq '"## Issue #\(.number): \(.title)\n\n\(.body)\n"' 2>/dev/null
}

# Everything after the worker. $1: issue number, $2: mode, $3: complexity, $4: HEAD before the
# worker, $5: the issue text. Never returns (exits with the run's result).
ralph_after_worker() {
  local num="$1" mode="$2" complexity="$3" pre_head="$4" issue="$5" cost
  ralph_exit_on_limit_stop
  if [ -n "${RALPH_LAST_LOG:-}" ]; then
    cost=$(ralph_run_cost "$RALPH_LAST_LOG")
    [ -n "$cost" ] && ralph_say dim "Koszt workera: $cost"
  fi

  # The bramka (ADR 0018) and, after a green one, the przegląd heavy (ADR 0016): both before the
  # epic can be marked for acceptance or anything counts the issue as done.
  ralph_verify_closed "$num" "$mode" "$complexity" "$pre_head" "$issue"
  ralph_finish_run "$num" "$mode"
}

# The run's verdict. $1: issue number, $2: mode. Never returns.
ralph_finish_run() {
  local num="$1" mode="$2" state has_label outcome
  ralph_exit_on_limit_stop

  # The worker may have closed the last sub-issue of an epic: mark it for acceptance. Not when the
  # bramka could not even run (no gate line): that issue is not verified. Nor after a red bramka
  # or a failed przegląd: that issue is open again, so its epic still has an open sub-issue.
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

# Wznowienie po limicie (ADR 0017). $1: the issue/epic argument (may be empty). Returns 1 when no
# ślad applies (the run goes on as usual); otherwise resumes the interrupted phase and never
# returns. A resumed worker goes through the bramka like any run; a resumed przegląd heavy does
# not run it again (the bramka was green before the przegląd began).
ralph_resume_from_trace() {
  local num phase session pre_head complexity issue
  ralph_limit_trace_applies "$1" || return 1
  num=$(ralph_limit_trace_get issue)
  phase=$(ralph_limit_trace_get phase)
  session=$(ralph_limit_trace_get session)
  pre_head=$(ralph_limit_trace_get pre_head)
  complexity=$(ralph_limit_trace_get complexity)
  RALPH_LIMIT_CONTEXT=$(printf 'issue=%s\npre_head=%s\ncomplexity=%s' "$num" "$pre_head" "$complexity")
  [ -n "${RALPH_ISSUE_FILE:-}" ] && printf '%s\n' "$num" > "$RALPH_ISSUE_FILE"
  ralph_say warn "Wznowienie po limicie: issue #${num} — $([ "$phase" = review ] && echo "przegląd heavy" || echo worker) przerwany przez limit użycia (sesja $session)."
  issue=$(ralph_issue_text "$num")
  if [ "$phase" = review ]; then
    ralph_heavy_review "$num" "$pre_head" "$issue" "$session"
    ralph_finish_run "$num" afk
  fi
  RALPH_LAST_LOG=""
  ralph_run_worker_through_limit "$(ralph_limit_trace_get model)" "$(ralph_limit_trace_get effort)" \
    "" "$(ralph_limit_trace_get label)" afk worker "$session"
  ralph_after_worker "$num" afk "$complexity" "$pre_head" "$issue"
}

# --- ralph-epic: run once.sh over an epic until a stop condition (ADR 0013). ---

# Epic structure: one sub_issues call per open epic -> array of {number, started, open:[...]}.
ralph_epics_json() {
  local epics="[]" e subs
  for e in $(gh issue list --state open --limit 200 --json number,title \
      --jq '.[] | select(.title | startswith("[PRD]")) | .number' 2>/dev/null); do
    subs=$(gh api --paginate "repos/{owner}/{repo}/issues/${e}/sub_issues" 2>/dev/null | jq -s -c 'add // []')
    [ -n "$subs" ] || subs="[]"
    epics=$(jq -c --argjson e "$e" --argjson subs "$subs" \
      '. + [{number: $e, started: any($subs[]; .state == "closed"), open: [$subs[] | select(.state == "open") | .number]}]' \
      <<<"$epics")
  done
  printf '%s\n' "$epics"
}

# Pure. stdin: epics JSON. The epic ralph-epic takes without a number, by the selector's rule:
# the lowest-numbered started epic with open sub-issues, else the lowest-numbered one with any.
# Prints the number, or nothing.
ralph_pick_epic() {
  jq -r '[.[] | select(.open | length > 0)] as $c
    | (([$c[] | select(.started) | .number] | min) // ([$c[].number] | min)) // empty'
}

# Pure. $1: open sub-issues at the start. Every sub-issue takes one run, plus room for a
# discovered HITL (AFK run, then the HITL session) — so twice as many; the cap only guards
# against a loop that never ends.
ralph_epic_iteration_limit() {
  echo $(( $1 * 2 ))
}

# Pure. Decision after one once.sh run. $1: its exit code; $2: runs done so far (this one
# included); $3: limit; $4: "true" when the epic is now awaiting acceptance. Prints `continue`
# or `stop-<reason>` (ready|afk-failed|hitl|nothing|error|limit|usage-limit). An error is never
# masked by a ready epic; a failed AFK run is never masked by the limit.
ralph_epic_decision() {
  local code="$1" done_runs="$2" limit="$3" ready="$4"
  case "$code" in
    "$RALPH_EXIT_ERROR") echo stop-error; return 0 ;;
    "$RALPH_EXIT_USAGE_LIMIT") echo stop-usage-limit; return 0 ;;
    "$RALPH_EXIT_AFK_FAILED") echo stop-afk-failed; return 0 ;;
    "$RALPH_EXIT_HITL_OPEN") echo stop-hitl; return 0 ;;
    "$RALPH_EXIT_DONE"|"$RALPH_EXIT_NOTHING"|"$RALPH_EXIT_DISCOVERED"|"$RALPH_EXIT_HITL_TO_AFK"|"$RALPH_EXIT_REVIEW_RETRY") ;;
    *) echo stop-error; return 0 ;;
  esac
  if [ "$ready" = true ]; then echo stop-ready; return 0; fi
  if [ "$code" = "$RALPH_EXIT_NOTHING" ]; then echo stop-nothing; return 0; fi
  if [ "$done_runs" -ge "$limit" ]; then echo stop-limit; return 0; fi
  echo continue
}

# System notification where available (macOS `osascript`); silently nothing elsewhere.
ralph_notify() {
  command -v osascript >/dev/null 2>&1 || return 0
  local msg="${2//\\/}" title="${1//\\/}"
  osascript -e "display notification \"${msg//\"/\'}\" with title \"${title//\"/\'}\"" >/dev/null 2>&1 || true
}

# --- Epic branch (ADR 0012). Opt-in per repo with one line in the "## Ralph" section. ---
# Syntax (fixed English key whatever the section's language, so bash reads it reliably), alone on
# its own line; a leading list marker and backticks around the value are tolerated:
#     ralph-base-branch: dev
# stdin: the "## Ralph" section. Line absent -> no output, rc 0 (trunk: the loop never switches
# branches). Valid line -> the base branch on stdout, rc 0. Any other line mentioning the key
# (bad syntax, bad branch name, a second declaration) -> message on stderr, rc 1: fail closed
# rather than silently fall back to trunk.
ralph_base_branch() {
  local lines count line value
  lines=$(grep -F 'ralph-base-branch' || true)
  [ -n "$lines" ] || return 0
  count=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
  if [ "$count" != 1 ]; then
    ralph_say err "Sekcja ## Ralph deklaruje ralph-base-branch więcej niż raz — zostaw jedną linię." >&2
    return 1
  fi
  line="$lines"
  if [[ "$line" =~ ^[[:space:]]*([-*][[:space:]]+)?ralph-base-branch:[[:space:]]*\`?([A-Za-z0-9_][A-Za-z0-9._/-]*)\`?[[:space:]]*$ ]] &&
    value="${BASH_REMATCH[2]}" && [[ "$value" != *..* && "$value" != */ && "$value" != *.lock ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  ralph_say err "Zła składnia linii gałęzi bazowej w ## Ralph: '$line'.
Oczekiwano dokładnie: ralph-base-branch: <gałąź> (np. ralph-base-branch: dev)." >&2
  return 1
}

# --- Gate command. One line in the "## Ralph" section runs the whole gate in a single command. ---
# Syntax, alone on its own line; a leading list marker and backticks around the whole command are
# tolerated:
#     ralph-gate: bash a.test.sh && bash b.test.sh
# stdin: the "## Ralph" section (see ralph_contract_section), so a line outside it never counts.
# Prints the command of the first such line. No line or an empty command -> no output, rc 1.
ralph_gate_command() {
  local line value
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([-*][[:space:]]+)?ralph-gate:[[:space:]]*(.*)$ ]]; then
      value="${BASH_REMATCH[2]}"
      value="${value%"${value##*[![:space:]]}"}"
      if [[ "$value" =~ ^\`(.*)\`$ ]]; then value="${BASH_REMATCH[1]}"; fi
      [ -n "$value" ] || return 1
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

# Parent (epic) number of issue $1 via gh; no output when it has none (GitHub answers 404).
# rc 1 when GitHub could not answer at all — callers must not mistake that for "no parent".
ralph_issue_parent() {
  local out
  if out=$(gh api "repos/{owner}/{repo}/issues/$1/parent" --jq .number 2>/dev/null); then
    printf '%s\n' "$out"
    return 0
  fi
  grep -q '"status":"404"' <<<"$out"
}

# With an epic branch configured, uncommitted work (tracked changes or untracked files) would
# travel across a checkout or block a merge: refuse, with a message, rc 1.
ralph_require_clean_tree() {
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    ralph_say err "Drzewo robocze nie jest czyste — nie przełączam gałęzi i nie uruchamiam workera.
Domknij albo odłóż zmiany (git status), potem odpal ponownie." >&2
    return 1
  fi
}

# Put the repo in cwd on the branch the worker should commit to. $1: base branch (from
# ralph_base_branch); $2: epic number, empty for an issue without a parent.
#   - dirty tree (tracked changes or untracked files) -> refuse before touching git;
#   - no epic -> switch to the base;
#   - epic -> switch to epic/<n>, creating it from the base on first use; if the base has moved
#     on, merge it in. A conflicting merge is aborted, leaving a clean tree on epic/<n>.
# Local only: no fetch, no push. rc 0 = ready for the worker; rc 1 = stop (message on stderr).
ralph_prepare_branch() {
  local base="$1" epic="${2:-}" branch

  ralph_require_clean_tree || return 1
  if ! git rev-parse --verify --quiet "refs/heads/$base" >/dev/null; then
    ralph_say err "Nie ma lokalnej gałęzi bazowej '$base' (ralph-base-branch w ## Ralph).
Utwórz ją albo popraw linię; pętla nie pobiera gałęzi z remote." >&2
    return 1
  fi

  if [ -z "$epic" ]; then
    git checkout -q "$base" || return 1
    echo "Issue bez epicu — pracuję na gałęzi bazowej $base."
    return 0
  fi

  branch="epic/$epic"
  if ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    git checkout -q -b "$branch" "$base" || return 1
    echo "Utworzyłem gałąź $branch z $base."
    return 0
  fi

  git checkout -q "$branch" || return 1
  if git merge-base --is-ancestor "$base" "$branch"; then
    echo "Pracuję na gałęzi $branch (baza $base bez nowych commitów)."
    return 0
  fi
  if git merge -q --no-edit "$base" >/dev/null 2>&1; then
    echo "Scaliłem $base do $branch."
    return 0
  fi
  # Abort whatever the failed merge left behind; the tree was clean before it, so this restores it.
  git merge --abort 2>/dev/null || git reset -q --merge 2>/dev/null
  ralph_say err "Konflikt przy scalaniu $base do $branch — merge przerwany, drzewo czyste, worker nie rusza.
Rozwiąż ręcznie: git checkout $branch && git merge $base, potem odpal ponownie." >&2
  return 1
}

ralph_color_init
