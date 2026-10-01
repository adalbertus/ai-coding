#!/usr/bin/env bash
# Shared Ralph helpers. Keep runtime-specific mechanics here so the loop semantics stay in
# once.sh / once-local.sh.

RALPH_RUNTIME=""
RALPH_ISSUE_ARG=""
RALPH_FORCE_MODEL=""
RALPH_LOCK_DIR=""
RALPH_LOCK_OWNED=0

ralph_usage() {
  local launcher="$1"
  case "$launcher" in
    ralph-once-local)
      echo "Użycie: ralph-once-local [claude|codex] [--force-model=sonnet|opus]"
      ;;
    ralph-epic)
      echo "Użycie: ralph-epic [claude|codex] [numer-epicu] [--force-model=sonnet|opus]"
      ;;
    *)
      echo "Użycie: ralph-once [claude|codex] [numer-issue] [--force-model=sonnet|opus]"
      echo "       ralph-once [numer-issue]  # wstecznie kompatybilne: Claude"
      ;;
  esac
  echo "  --force-model=sonnet|opus  jeden model Claude z effort high dla każdego issue,"
  echo "                             zamiast modelu z etykiety complexity:*"
}

ralph_parse_args() {
  local launcher="$1"
  shift

  RALPH_RUNTIME="${RALPH_DEFAULT_RUNTIME:-claude}"
  RALPH_ISSUE_ARG=""
  RALPH_FORCE_MODEL=""

  # --force-model=<model> may stand anywhere; the positional arguments are what is left.
  local rest=() arg force=""
  for arg in "$@"; do
    case "$arg" in
      --force-model=*) force="${arg#--force-model=}" ;;
      *) rest+=("$arg") ;;
    esac
  done
  set -- ${rest[@]+"${rest[@]}"}

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

  case "$force" in
    ""|sonnet|opus) ;;
    *)
      echo "--force-model przyjmuje sonnet albo opus, nie '${force}'." >&2
      ralph_usage "$launcher" >&2
      return 1
      ;;
  esac
  if [ -n "$force" ] && [ "$RALPH_RUNTIME" != claude ]; then
    echo "--force-model działa tylko z runtime'em claude (sonnet i opus to modele Claude)." >&2
    return 1
  fi
  RALPH_FORCE_MODEL="$force"
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

# Body of the EXPLORATION section, rendered per runtime. The two branches are separate prose,
# not one text with holes: "search, then read the matching range" is one tool with two parameters
# under Claude Code and two shell commands under Codex, so the sentences differ in shape, not just
# in nouns. Quoted heredocs — the prose contains backticks and must not be expanded. {…}
# placeholders inside are resolved by ralph_render_prompt after this is spliced in.
ralph_explore_guidance() {
  case "$1" in
    codex)
      cat <<'EOF'
Explore the repo. Note its structure and conventions ({AGENT_CONTRACT_FILE}), and the existing tests that
the `## Ralph` feedback loops run.

**Search before you read.** `cat`-ing a large reference file (a glossary, a big module) into
context can cost tens of thousands of tokens, and every one of them stays in context for the rest
of the run — degrading your own reasoning exactly when the implementation needs it. Reading a file
whole is the easiest way to run this loop out of context. So read in two steps:

1. **Locate the lines** — `rg -n '<pattern>' <path>` (or `grep -rn '<pattern>' <path>` where `rg`
   is not installed). This gives you the file and the line numbers, not the file.
2. **Read only that range** — `sed -n '<start>,<end>p' <file>`, with a window of a few dozen lines
   around the hit. If the range turns out to be too narrow, widen it or search again. Two targeted
   reads still cost a fraction of the whole file.

Use `cat` only on a file you already know is short — `wc -l <file>` when unsure. Never `cat` a
glossary, a contract file, or a directory-wide glob.

This is how to read an instruction like "read `CONTEXT.md` before introducing a new term" in a
repo's {AGENT_CONTRACT_FILE}: **consult** that file for what you need. Do not pull all of it into context.
EOF
      ;;
    *)
      cat <<'EOF'
Explore the repo. Note its structure and conventions ({AGENT_CONTRACT_FILE}), and the existing tests that
the `## Ralph` feedback loops run.

**Search before you read.** A full `Read` of a large reference file (a glossary, a big module)
can cost tens of thousands of tokens, and every one of them stays in context for the rest of the
run — degrading your own reasoning exactly when the implementation needs it. So:

- **If you can name what you are looking for** — a term, a symbol, a function, a path — use
  `Grep`/`Glob`, then `Read` only the matching range (`offset`/`limit`). This is the default, and
  it is not a compromise: it returns the exact source text, just less of it.
- **Only if you cannot formulate a search pattern**, because you need an overview rather than a
  specific fact, delegate to the `Explore` subagent. It reads in its own context and returns
  conclusions. It costs a full extra model run and gives you a paraphrase instead of the source,
  so it earns its keep for open-ended reconnaissance and nothing else.

This is how to read an instruction like "read `CONTEXT.md` before introducing a new term" in a
repo's {AGENT_CONTRACT_FILE}: **consult** that file for what you need. Do not pull all of it into context.
EOF
      ;;
  esac
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
  local runtime="$1" prompt_file="$2" content contract_file skill_tdd explore
  contract_file="$(ralph_contract_file "$runtime")"
  skill_tdd="$(ralph_skill_tdd "$runtime")"
  explore="$(ralph_explore_guidance "$runtime")"
  content=$(cat "$prompt_file")
  # EXPLORE_GUIDANCE first: the spliced-in prose carries {AGENT_CONTRACT_FILE} of its own.
  content=${content//\{EXPLORE_GUIDANCE\}/$explore}
  content=${content//\{AGENT_CONTRACT_FILE\}/$contract_file}
  content=${content//\{SKILL_TDD\}/$skill_tdd}
  printf '%s\n' "$content"
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
    claude:heavy)   RALPH_MODEL="opus"; RALPH_EFFORT="high" ;;
    # Not Haiku: the worker needs auto mode, which Claude Code does not offer on Haiku; without
    # it every Bash call waits for approval and the AFK loop stalls.
    claude:trivial) RALPH_MODEL="sonnet"; RALPH_EFFORT="low" ;;
    claude:*)       RALPH_MODEL="sonnet"; RALPH_EFFORT="medium" ;;

    codex:heavy)   RALPH_MODEL="${RALPH_CODEX_MODEL_HEAVY:-${RALPH_CODEX_MODEL:-}}"; RALPH_EFFORT="${RALPH_CODEX_EFFORT_HEAVY:-high}" ;;
    codex:trivial) RALPH_MODEL="${RALPH_CODEX_MODEL_TRIVIAL:-${RALPH_CODEX_MODEL:-}}"; RALPH_EFFORT="${RALPH_CODEX_EFFORT_TRIVIAL:-low}" ;;
    codex:*)       RALPH_MODEL="${RALPH_CODEX_MODEL_NORMAL:-${RALPH_CODEX_MODEL:-}}"; RALPH_EFFORT="${RALPH_CODEX_EFFORT_NORMAL:-medium}" ;;
  esac

  # --force-model: one Claude model for every tier, always at high effort.
  if [ -n "${RALPH_FORCE_MODEL:-}" ] && [ "$runtime" = claude ]; then
    RALPH_MODEL="$RALPH_FORCE_MODEL"
    RALPH_EFFORT="high"
  fi
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
      codex -a never exec --ephemeral -s read-only -C "$PWD" "$prompt"
      ;;
    *)
      echo "Nieznany runtime: $runtime" >&2
      return 1
      ;;
  esac
}

# jq definitions shared by both stream renderers. Expect $color ("1" = ANSI on), $w (terminal
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
          | "\n── Raport workera ──\n" + $r.text
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
# `claude --resume <id>` line. $4 labels the log file (issue-<n>, `local`).
ralph_run_claude_worker() {
  local model="$1" effort="$2" prompt="$3" label="${4:-run}"
  local dir log rc id
  dir=$(git rev-parse --git-path ralph-logs 2>/dev/null) || dir=""
  if [ -n "$dir" ] && mkdir -p "$dir" 2>/dev/null; then
    log="$dir/$(date +%Y%m%d-%H%M%S)-${label}.jsonl"
  else
    log=$(mktemp)
  fi

  claude -p --permission-mode auto --output-format stream-json --verbose \
    --model "$model" --effort "$effort" "$prompt" \
    | tee "$log" | ralph_render_stream
  rc=${PIPESTATUS[0]}

  echo
  ralph_say dim "Zapis runu: $log"
  id=$(ralph_stream_session_id "$log")
  [ -n "$id" ] && ralph_say dim "Wznów sesję: claude --resume $id"
  return "$rc"
}

# stdin: Codex `exec --json` lines -> stdout: what the worker is doing, for a human. A pure
# filter, same look as ralph_render_stream: agent messages are the narration (`› …`), steps are
# dimmed one-liners clipped to the terminal width — command runs `▸ Bash: cmd` (a failed one red,
# `✗ Bash (exit N): cmd`), file changes `▸ Edit: path` (add -> Write), MCP calls and web searches.
# The last agent message of a turn is printed as the report once the turn completes. Everything
# else (thread/turn bookkeeping, reasoning, unknown events, unparseable lines) is skipped. Steps
# are rendered on completion.
ralph_render_codex_stream() {
  jq -n -R --unbuffered -r --arg cwd "$PWD/" --arg color "${RALPH_COLOR:-0}" \
    --argjson w "$(ralph_term_cols)" "$RALPH_RENDER_JQ_DEFS"'
    def flush: if .last != null then .out += [.last | narr] | .last = null else . end;
    foreach (inputs | (fromjson? // empty)) as $e ({last: null, out: []};
      .out = []
      | if $e.type == "item.completed" then
          ($e.item // {}) as $i
          | if $i.type == "agent_message" and ($i.text | type) == "string" then
              flush | .last = $i.text
            elif $i.type == "command_execution" then
              flush
              | .out += [if ($i.exit_code // 0) != 0
                         then "✗ Bash (exit \($i.exit_code)): \(($i.command // "") | line1)" | bad
                         else "▸ Bash: \(($i.command // "") | line1)" | step end]
            elif $i.type == "file_change" then
              flush
              | .out += [($i.changes // [])[]?
                         | "▸ \(if .kind == "add" then "Write" elif .kind == "delete" then "Delete" else "Edit" end): \((.path // "") | line1)"
                         | step]
            elif $i.type == "mcp_tool_call" then
              flush | .out += ["▸ MCP: \($i.server // "")/\($i.tool // "")" | step]
            elif $i.type == "web_search" then
              flush | .out += ["▸ WebSearch: \(($i.query // "") | line1)" | step]
            else . end
        elif $e.type == "turn.completed" and .last != null then
          .out += ["\n── Raport workera ──\n" + .last] | .last = null
        else . end;
      .out[])'
}

# $1: a Codex JSONL log file -> the thread id to hand to `codex resume`.
ralph_codex_thread_id() {
  jq -R -r 'fromjson? | select(.type == "thread.started") | .thread_id' "$1" 2>/dev/null | tail -n 1
}

# Codex worker, unattended: `codex exec --json` with auto-review. Same shape as the Claude
# worker: full JSONL in <git dir>/ralph-logs/, one line per step on screen, a resume line at the
# end. The session is persisted (no --ephemeral) so it can be resumed.
ralph_run_codex_worker() {
  local model="$1" effort="$2" prompt="$3" label="${4:-run}"
  local dir log rc id
  dir=$(git rev-parse --git-path ralph-logs 2>/dev/null) || dir=""
  if [ -n "$dir" ] && mkdir -p "$dir" 2>/dev/null; then
    log="$dir/$(date +%Y%m%d-%H%M%S)-${label}.jsonl"
  else
    log=$(mktemp)
  fi

  local args=(exec --json --approve-for-me -C "$PWD")
  [ -n "$model" ] && args+=(-m "$model")
  [ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")
  # stderr carries Codex's banner and its tool errors (e.g. a tool host that fails to start),
  # which never reach the JSONL: keep it next to the log instead of discarding it.
  local err="${log%.jsonl}.stderr.log"
  codex "${args[@]}" "$prompt" 2>"$err" \
    | tee "$log" | ralph_render_codex_stream
  rc=${PIPESTATUS[0]}

  echo
  ralph_say dim "Zapis runu: $log"
  if grep -q 'ERROR' "$err" 2>/dev/null; then
    ralph_say err "Codex zgłosił błędy (stderr): $err
$(grep 'ERROR' "$err" | sort -u -k2 | head -3 | sed 's/^/  /')"
  fi
  id=$(ralph_codex_thread_id "$log")
  [ -n "$id" ] && ralph_say dim "Wznów sesję: codex resume $id"
  return "$rc"
}

# Codex HITL session: the interactive CLI with auto-review, so the human can interrupt or add
# instructions mid-run.
ralph_run_codex_interactive() {
  local model="$1" effort="$2" prompt="$3"
  local args=(--no-alt-screen --approve-for-me -C "$PWD")
  [ -n "$model" ] && args+=(-m "$model")
  [ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")
  if [ "${RALPH_TERM_FDS:-}" = 1 ]; then
    codex "${args[@]}" "$prompt" >&3 2>&4
  else
    codex "${args[@]}" "$prompt"
  fi
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

# $6: mode, `afk` (default, unattended) or `hitl` (interactive session with a human present).
ralph_run_worker() {
  local runtime="$1" model="$2" effort="$3" prompt="$4" label="${5:-}" mode="${6:-afk}"

  case "$runtime" in
    claude)
      if [ "$mode" = "hitl" ]; then
        ralph_run_claude_interactive "$model" "$effort" "$prompt"
      else
        ralph_run_claude_worker "$model" "$effort" "$prompt" "$label"
      fi
      ;;
    codex)
      if [ "$mode" = "hitl" ]; then
        ralph_run_codex_interactive "$model" "$effort" "$prompt"
      else
        ralph_run_codex_worker "$model" "$effort" "$prompt" "$label"
      fi
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

# stdin: issues array (with `body`); $1: JSON array of numbers of all open issues. Drops every
# issue whose "Blocked by" section (heading line up to the next heading) mentions an open issue,
# as `#12` or bare `12`. No section, or "None - can start immediately" -> passes.
ralph_filter_unblocked() {
  jq -c --argjson open "$1" '
    map(select(
      (.body // "" | split("\n")) as $l
      | (first(range(0; $l | length) | select($l[.] | test("^#+\\s*blocked by"; "i"))) // null) as $s
      | if $s == null then true
        else
          ($l[$s + 1:]) as $rest
          | (first(range(0; $rest | length) | select($rest[.] | test("^#"))) // ($rest | length)) as $e
          | [$rest[:$e][] | match("[0-9]+"; "g") | .string | tonumber]
          | all(.[]; . as $n | $open | index($n) | not)
        end))'
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
# or `stop-<reason>` (ready|afk-failed|hitl|nothing|error|limit). An error is never masked by a
# ready epic; a failed AFK run is never masked by the limit.
ralph_epic_decision() {
  local code="$1" done_runs="$2" limit="$3" ready="$4"
  case "$code" in
    "$RALPH_EXIT_ERROR") echo stop-error; return 0 ;;
    "$RALPH_EXIT_AFK_FAILED") echo stop-afk-failed; return 0 ;;
    "$RALPH_EXIT_HITL_OPEN") echo stop-hitl; return 0 ;;
    "$RALPH_EXIT_DONE"|"$RALPH_EXIT_NOTHING"|"$RALPH_EXIT_DISCOVERED"|"$RALPH_EXIT_HITL_TO_AFK") ;;
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
