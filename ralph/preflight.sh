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

# Extract the section body: from the Ralph heading up to (not including) the next level-1/2
# heading. "### " subheadings stay inside the section.
section=$(awk '
  /^#{1,2}[[:space:]]+Ralph([[:space:]]|$)/ { f=1; print; next }
  f && /^#{1,2}[[:space:]]/ { exit }
  f { print }
' "$contract_file")

# Deterministic fast-fail: a heading with no real content below it is a placeholder.
body=$(printf '%s\n' "$section" | sed '1d' | tr -d '[:space:]')
[ -n "$body" ] || halt "Sekcja \"## Ralph\" jest pusta (placeholder)."

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
