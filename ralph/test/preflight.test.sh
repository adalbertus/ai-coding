#!/usr/bin/env bash
# Test strażnika (ralph/preflight.sh). Sprawdza ZEWNĘTRZNY kontrakt — kod wyjścia + komunikat —
# nie wnętrze. Gałąź modelu (Haiku) jest stubowana przez RALPH_GATE_CMD, więc test jest
# deterministyczny i nie wymaga ani sieci, ani zainstalowanego `claude`.
#
# Uruchom: bash ralph/test/preflight.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/../preflight.sh"

pass=0; fail=0
LAST_OUT=""; LAST_RC=0

# run <claude_md_content|__NOFILE__> <gate_stub_cmd>
run() {
  local content="$1" stub="${2:-}" dir
  dir=$(mktemp -d)
  [ "$content" != "__NOFILE__" ] && printf '%s' "$content" > "$dir/CLAUDE.md"
  LAST_OUT=$(cd "$dir" && RALPH_GATE_CMD="$stub" bash "$PREFLIGHT" 2>&1)
  LAST_RC=$?
  rm -rf "$dir"
}

# expect <desc> <want_rc> [want_substring]
expect() {
  local desc="$1" want_rc="$2" want_sub="${3:-}" ok=1
  [ "$LAST_RC" = "$want_rc" ] || ok=0
  if [ -n "$want_sub" ] && ! printf '%s' "$LAST_OUT" | grep -qF "$want_sub"; then ok=0; fi
  if [ "$ok" = 1 ]; then
    echo "✓ $desc"; pass=$((pass+1))
  else
    echo "✗ $desc (rc oczek=$want_rc jest=$LAST_RC; szukano: '$want_sub')"
    printf '   out: %s\n' "$LAST_OUT"; fail=$((fail+1))
  fi
}

RALPH_SECTION=$'## Ralph\n\nFeedback loops przed commitem: `composer test`, `./vendor/bin/pint`.\nDone: zadanie skończone, gdy testy są zielone.\n'

# 1. Brak CLAUDE.md -> halt, kieruje do /ralph-konfiguracja.
run "__NOFILE__"
expect "brak CLAUDE.md -> halt + wskazówka" 1 "/ralph-konfiguracja"

# 2. CLAUDE.md bez sekcji ## Ralph -> halt.
run $'# Moje repo\n\nOpis projektu.\n'
expect "brak sekcji ## Ralph -> halt + wskazówka" 1 "/ralph-konfiguracja"

# 3. ## Ralph obecna, ale pusta (placeholder) -> halt deterministycznie, bez modelu.
run $'## Ralph\n\n## Coś innego\nblabla\n'
expect "pusta sekcja ## Ralph -> halt (placeholder)" 1 "/ralph-konfiguracja"

# 4. ## Ralph z treścią + gate READY -> przejście (exit 0).
run "$RALPH_SECTION" "echo READY"
expect "treść + gate READY -> exit 0" 0

# 5. ## Ralph z treścią + gate MISSING -> halt.
run "$RALPH_SECTION" "echo MISSING"
expect "treść + gate MISSING -> halt" 1 "/ralph-konfiguracja"

# 6. ## Ralph z treścią + gate zwraca śmieci/pusto -> fail-closed halt.
run "$RALPH_SECTION" "true"
expect "treść + gate pusto -> fail-closed halt" 1 "/ralph-konfiguracja"

# 7. Podsekcje ### nie kończą sekcji (treść za ### nadal liczy się jako body) + READY.
run $'## Ralph\n\n### Feedback\n`npm test`\n\n### Done\ngdy zielone\n' "echo READY"
expect "### podsekcje zostają w sekcji -> exit 0" 0

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
