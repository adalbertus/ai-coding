#!/usr/bin/env bash
# Ralph preflight guard — "strażnik". Fail-closed gate run before any work: the loop only
# proceeds when the target repo declares a USABLE "## Ralph" section in its CLAUDE.md
# (feedback loops + done-criteria). Never guesses how to test — when in doubt, it halts.
#
# Contract (this is the interface both once.sh and once-local.sh rely on):
#   - run from the target repo's cwd;
#   - exit 0  -> READY  (loop may proceed);
#   - exit !=0 -> halt   (reason + how-to-fix printed to stderr).
#
# The model gate is stubbable for tests via RALPH_GATE_CMD (a command whose stdout is the
# verdict READY/MISSING); when unset, a headless Haiku call is used. Any error, empty output
# or non-READY verdict halts (fail-closed).
set -uo pipefail

halt() {
  echo "✋ $1" >&2
  echo "   To repo nie ma gotowej sekcji \"## Ralph\" w CLAUDE.md (instrukcje testowania + done-criteria)." >&2
  echo "   Odpal w sesji Claude (Sonnet+): /ralph-konfiguracja" >&2
  exit 1
}

claude_md="CLAUDE.md"
[ -f "$claude_md" ] || halt "Brak pliku CLAUDE.md w tym repo."

# Fast path: cheap grep for the section heading (level 1 or 2).
grep -qE '^#{1,2}[[:space:]]+Ralph([[:space:]]|$)' "$claude_md" \
  || halt "CLAUDE.md nie ma sekcji \"## Ralph\"."

# Extract the section body: from the Ralph heading up to (not including) the next level-1/2
# heading. "### " subheadings stay inside the section.
section=$(awk '
  /^#{1,2}[[:space:]]+Ralph([[:space:]]|$)/ { f=1; print; next }
  f && /^#{1,2}[[:space:]]/ { exit }
  f { print }
' "$claude_md")

# Deterministic fast-fail: a heading with no real content below it is a placeholder.
body=$(printf '%s\n' "$section" | sed '1d' | tr -d '[:space:]')
[ -n "$body" ] || halt "Sekcja \"## Ralph\" jest pusta (placeholder)."

# Model gate: confirm the section actually holds runnable test/done instructions.
gate_prompt="Poniżej sekcja \"## Ralph\" z pliku CLAUDE.md repozytorium. Ma powiedzieć
autonomicznemu agentowi: (1) konkretne komendy feedback-loop do uruchomienia przed commitem
oraz (2) co oznacza ukończenie zadania (done-criteria). Jeśli zawiera konkretne, wykonywalne
instrukcje dla OBU punktów — wypisz dokładnie READY. Jeśli czegoś brakuje, jest ogólnikowe
lub to placeholder — wypisz dokładnie MISSING. Wypisz tylko jedno słowo.

--- sekcja ## Ralph ---
$section"

if [ -n "${RALPH_GATE_CMD:-}" ]; then
  verdict=$($RALPH_GATE_CMD 2>/dev/null)
else
  echo "Strażnik: weryfikuję sekcję ## Ralph na modelu Haiku... (chwilę trwa)" >&2
  verdict=$(claude -p --model claude-haiku-4-5-20251001 "$gate_prompt" 2>/dev/null)
fi

verdict=$(printf '%s' "$verdict" | grep -Eo 'READY|MISSING' | head -1)
[ "$verdict" = "READY" ] || halt "Strażnik (Haiku) ocenił sekcję \"## Ralph\" jako niekompletną."

exit 0
