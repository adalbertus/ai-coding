#!/usr/bin/env bash
# Ralph preflight guard — "strażnik". Fail-closed gate run before any work: the loop only
# proceeds when the target repo declares a USABLE "## Ralph" section in CLAUDE.md
# (feedback loops + done-criteria). AGENTS.md is never read (ADR 0020). Never guesses how to test — when in doubt, it halts.
#
# Contract (this is the interface both once.sh and once-local.sh rely on):
#   - run from the target repo's cwd;
#   - exit 0  -> READY  (loop may proceed);
#   - exit 8  -> halt on a usage limit too far away to wait for (ADR 0017; reset time printed);
#   - exit !=0 -> halt   (reason + how-to-fix printed to stderr).
#
# The model gate is stubbable for tests via RALPH_GATE_CMD (a command whose stdout is the
# verdict READY/MISSING); when unset, a headless runtime-selected guard call is used. Any error,
# empty output or non-READY verdict halts (fail-closed); error/empty gets its own message
# (runtime did not run) distinct from a MISSING verdict (section incomplete).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

runtime=claude
contract_file="$(ralph_contract_file)"

halt() {
  ralph_say warn "✋ $1" >&2
  echo "   To repo nie ma gotowej sekcji \"## Ralph\" w $contract_file (instrukcje testowania + done-criteria)." >&2
  echo "   Odpal w sesji Claude (Sonnet+): /ralph-konfiguracja" >&2
  exit 1
}

[ -f "$contract_file" ] || halt "Brak pliku $contract_file w tym repo."

# Fast path: cheap grep for the section heading (level 1 or 2).
grep -qE '^#{1,2}[[:space:]]+Ralph([[:space:]]|$)' "$contract_file" \
  || halt "$contract_file nie ma sekcji \"## Ralph\"."

# Extract the section body.
section=$(ralph_contract_section "$contract_file")

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

gate_rc=0
if [ -n "${RALPH_GATE_CMD:-}" ]; then
  verdict=$($RALPH_GATE_CMD 2>/dev/null); gate_rc=$?
else
  echo "Strażnik ($(ralph_selector_model_label)): weryfikuję sekcję ## Ralph... (chwilę trwa)" >&2
  verdict=$(ralph_run_model_capture guard "$gate_prompt"); gate_rc=$?
fi

# A usage limit says nothing about the section either; the wait (or why there was none) is already
# on screen.
if [ "$gate_rc" = "$RALPH_EXIT_USAGE_LIMIT" ]; then
  ralph_say warn "✋ Strażnik nie zweryfikował sekcji \"## Ralph\": limit użycia runtime'u \"$runtime\"." >&2
  exit "$RALPH_EXIT_USAGE_LIMIT"
fi

# A failed or silent model call says nothing about the section: halt (fail-closed) but blame the
# runtime, not the section, so the user checks install/login instead of rewriting a fine contract.
if [ "$gate_rc" != 0 ] || [ -z "$(printf '%s' "$verdict" | tr -d '[:space:]')" ]; then
  ralph_say err "✋ Nie udało się uruchomić runtime'u \"$runtime\" do weryfikacji sekcji \"## Ralph\"." >&2
  echo "   Wywołanie modelu zakończyło się błędem albo zwróciło pustą odpowiedź — to nie jest ocena sekcji." >&2
  echo "   Sprawdź, czy $runtime jest zainstalowany i zalogowany, po czym spróbuj ponownie." >&2
  exit 1
fi

verdict=$(printf '%s' "$verdict" | grep -Eo 'READY|MISSING' | head -1)
[ "$verdict" = "READY" ] || halt "Strażnik ocenił sekcję \"## Ralph\" jako niekompletną."

exit 0
