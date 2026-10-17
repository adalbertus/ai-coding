#!/usr/bin/env bash
# Test strażnika (ralph/preflight.sh). Sprawdza ZEWNĘTRZNY kontrakt — kod wyjścia + komunikat —
# nie wnętrze. Gałąź modelu jest stubowana przez RALPH_GATE_CMD, więc test jest
# deterministyczny i nie wymaga ani sieci, ani zainstalowanego runtime'u.
#
# Uruchom: bash ralph/test/preflight.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/../preflight.sh"

pass=0; fail=0
LAST_OUT=""; LAST_RC=0

# run <contract_content|__NOFILE__> <gate_stub_cmd>
run() {
  local content="$1" stub="${2:-}" runtime="${3:-claude}" file=CLAUDE.md dir
  dir=$(mktemp -d)
  [ "$content" != "__NOFILE__" ] && printf '%s' "$content" > "$dir/$file"
  LAST_OUT=$(cd "$dir" && RALPH_GATE_CMD="$stub" bash "$PREFLIGHT" "$runtime" 2>&1)
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

# expect_not <desc> <substring> — the last output must NOT contain the substring.
expect_not() {
  if printf '%s' "$LAST_OUT" | grep -qF "$2"; then
    echo "✗ $1 (znaleziono: '$2')"; printf '   out: %s\n' "$LAST_OUT"; fail=$((fail+1))
  else
    echo "✓ $1"; pass=$((pass+1))
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

# 6. ## Ralph z treścią + gate zwraca pusto -> fail-closed halt, komunikat o nieudanym uruchomieniu
#    runtime'u (nie o niekompletnej sekcji).
run "$RALPH_SECTION" "true"
expect "treść + gate pusto -> halt: nie udało się uruchomić" 1 "Nie udało się uruchomić"
expect_not "pusty gate nie twierdzi, że sekcja niekompletna" "niekompletn"

# 6b. Runtime kończy się błędem (nawet jeśli coś wypisał) -> ten sam komunikat.
limit_stub=$(mktemp); printf '#!/bin/sh\nexit 8\n' > "$limit_stub"; chmod +x "$limit_stub"
run "$RALPH_SECTION" "$limit_stub"
rm -f "$limit_stub"
expect "gate stopped by a usage limit -> halt with the limit code, not blaming the section" 8 "limit użycia"

run "$RALPH_SECTION" "false"
expect "gate kończy się błędem -> halt: nie udało się uruchomić" 1 "Nie udało się uruchomić"
expect_not "gate z błędem nie twierdzi, że sekcja niekompletna" "niekompletn"
run "$RALPH_SECTION" "bash -c 'echo READY; exit 3'"
expect "gate z błędem i READY na stdout -> nadal halt" 1 "Nie udało się uruchomić"

# 6c. Śmieci na stdout przy kodzie 0 -> werdykt nie-READY, obecny komunikat o sekcji.
run "$RALPH_SECTION" "echo cokolwiek"
expect "gate śmieci (rc 0) -> halt: sekcja niekompletna" 1 "niekompletn"

# 7. Podsekcje ### nie kończą sekcji (treść za ### nadal liczy się jako body) + READY.
run $'## Ralph\n\n### Feedback\n`npm test`\n\n### Done\ngdy zielone\n' "echo READY"
expect "### podsekcje zostają w sekcji -> exit 0" 0

# 8. Sekcja tylko w CLAUDE.md, bez AGENTS.md -> przechodzi, bez wzmianki o AGENTS.md.
run "$RALPH_SECTION" "echo READY"
expect_not "CLAUDE.md bez AGENTS.md: komunikat bez AGENTS.md" "AGENTS.md"

# run2 <claude_content|__NOFILE__> <agents_content|__NOFILE__> <gate_stub>
run2() {
  local claude_md="$1" agents_md="$2" stub="${3:-}" dir
  dir=$(mktemp -d)
  [ "$claude_md" != "__NOFILE__" ] && printf '%s' "$claude_md" > "$dir/CLAUDE.md"
  [ "$agents_md" != "__NOFILE__" ] && printf '%s' "$agents_md" > "$dir/AGENTS.md"
  LAST_OUT=$(cd "$dir" && RALPH_GATE_CMD="$stub" bash "$PREFLIGHT" 2>&1)
  LAST_RC=$?
  rm -rf "$dir"
}

DIFFERENT_SECTION=$'## Ralph\n\nInne komendy: `make check`.\nCommituj prosto na `main`.\n'

# 9. Różne sekcje w CLAUDE.md i AGENTS.md -> przechodzi (liczy się tylko CLAUDE.md).
run2 "$RALPH_SECTION" "$DIFFERENT_SECTION" "echo READY"
expect "różne sekcje w CLAUDE.md i AGENTS.md -> exit 0" 0
expect_not "rozjazd nie jest raportowany" "się różnią"

# 10. Sekcja tylko w AGENTS.md -> halt z odesłaniem do /ralph-konfiguracja, bez $ralph-konfiguracja.
run2 $'# Repo\n\nOpis.\n' "$RALPH_SECTION" "echo READY"
expect "sekcja tylko w AGENTS.md -> halt + /ralph-konfiguracja" 1 "/ralph-konfiguracja"
expect_not "komunikat nie wspomina \$ralph-konfiguracja" '$ralph-konfiguracja'

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
