#!/usr/bin/env bash
# Ralph preflight guard — "strażnik". Fail-closed gate run before any work: the loop only
# proceeds when the target repo declares a USABLE "## Ralph" section in the selected runtime's
# native agent contract file (CLAUDE.md for Claude, AGENTS.md for Codex)
# (feedback loops + done-criteria). Never guesses how to test — when in doubt, it halts.
#
# Contract (this is the interface both once.sh and once-local.sh rely on):
#   - run from the target repo's cwd;
#   - exit 0  -> READY  (loop may proceed);
#   - exit !=0 -> halt   (reason + how-to-fix printed to stderr).
#
# The model gate is stubbable for tests via RALPH_GATE_CMD (a command whose stdout is the
# verdict READY/MISSING); when unset, a headless runtime-selected guard call is used. Any error,
# empty output or non-READY verdict halts (fail-closed).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

runtime="${1:-${RALPH_RUNTIME:-claude}}"
contract_file="$(ralph_contract_file "$runtime")"

halt() {
  echo "✋ $1" >&2
  echo "   To repo nie ma gotowej sekcji \"## Ralph\" w $contract_file (instrukcje testowania + done-criteria)." >&2
  case "$runtime" in
    codex)
      echo "   Odpal w sesji Codex: \$ralph-konfiguracja" >&2
      ;;
    *)
      echo "   Odpal w sesji Claude (Sonnet+): /ralph-konfiguracja" >&2
      ;;
  esac
  exit 1
}

[ -f "$contract_file" ] || halt "Brak pliku $contract_file w tym repo."

# Fast path: cheap grep for the section heading (level 1 or 2).
grep -qE '^#{1,2}[[:space:]]+Ralph([[:space:]]|$)' "$contract_file" \
  || halt "$contract_file nie ma sekcji \"## Ralph\"."

# Extract the section body (shared with the drift gate below).
section=$(ralph_contract_section "$contract_file")

# Deterministic fast-fail: a heading with no real content below it is a placeholder.
body=$(printf '%s\n' "$section" | sed '1d' | tr -d '[:space:]')
[ -n "$body" ] || halt "Sekcja \"## Ralph\" jest pusta (placeholder)."

# Contract drift gate: when the repo carries BOTH contract files and both declare "## Ralph",
# the two sections must say the same thing. They are meant to be written in one pass of
# /ralph-konfiguracja, so a difference means one of them froze — and the runtime you run less
# often then works off stale rules (commit target, doc-sync list). Runs for both runtimes: a gate
# that only fires on the rare run is exactly how such drift survives.
#
# Missing second file, or a second file without the section: no gate. A Claude-only repo with no
# AGENTS.md stays legal, and a missing section halts loudly in that runtime's own preflight above.
other_file="$(ralph_contract_file "$([ "$runtime" = codex ] && echo claude || echo codex)")"

normalize_section() {
  sed -e 's/[[:space:]]*$//' -e '/^$/d'
}

if [ -f "$other_file" ] && grep -qE '^#{1,2}[[:space:]]+Ralph([[:space:]]|$)' "$other_file"; then
  other_section=$(ralph_contract_section "$other_file")
  if ! diff_out=$(diff -u \
    <(printf '%s\n' "$section" | normalize_section) \
    <(printf '%s\n' "$other_section" | normalize_section) 2>/dev/null); then
    echo "✋ Sekcje \"## Ralph\" w $contract_file i $other_file się różnią." >&2
    echo "   Runtime, którego używasz rzadziej, pracowałby na nieaktualnych regułach" >&2
    echo "   (gałąź commitów, lista dokumentów do doc-sync)." >&2
    echo "   Różnica (-$contract_file / +$other_file):" >&2
    printf '%s\n' "$diff_out" | sed -e '1,2d' -e 's/^/   /' >&2
    case "$runtime" in
      codex) echo "   Napraw jednym przebiegiem: \$ralph-konfiguracja" >&2 ;;
      *) echo "   Napraw jednym przebiegiem: /ralph-konfiguracja" >&2 ;;
    esac
    exit 1
  fi
fi

# Model gate: confirm the section actually holds runnable test/done instructions.
gate_prompt="Poniżej sekcja \"## Ralph\" z pliku $contract_file repozytorium. Ma powiedzieć
autonomicznemu agentowi: (1) konkretne komendy feedback-loop do uruchomienia przed commitem
oraz (2) co oznacza ukończenie zadania (done-criteria). Jeśli zawiera konkretne, wykonywalne
instrukcje dla OBU punktów — wypisz dokładnie READY. Jeśli czegoś brakuje, jest ogólnikowe
lub to placeholder — wypisz dokładnie MISSING. Wypisz tylko jedno słowo.

--- sekcja ## Ralph ---
$section"

if [ -n "${RALPH_GATE_CMD:-}" ]; then
  verdict=$($RALPH_GATE_CMD 2>/dev/null)
else
  echo "Strażnik ($(ralph_selector_model_label "$runtime")): weryfikuję sekcję ## Ralph... (chwilę trwa)" >&2
  verdict=$(ralph_run_model_capture "$runtime" guard "$gate_prompt" 2>/dev/null)
fi

verdict=$(printf '%s' "$verdict" | grep -Eo 'READY|MISSING' | head -1)
[ "$verdict" = "READY" ] || halt "Strażnik ocenił sekcję \"## Ralph\" jako niekompletną."

exit 0
