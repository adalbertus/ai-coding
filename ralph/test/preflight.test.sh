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

# run <contract_content|__NOFILE__> <gate_stub_cmd> [runtime]
run() {
  local content="$1" stub="${2:-}" runtime="${3:-claude}" file dir
  dir=$(mktemp -d)
  case "$runtime" in
    codex) file="AGENTS.md" ;;
    *) file="CLAUDE.md" ;;
  esac
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

# 8. Runtime Codex czyta AGENTS.md i kieruje do $ralph-konfiguracja.
run "__NOFILE__" "" "codex"
expect "codex: brak AGENTS.md -> halt + wskazówka" 1 '$ralph-konfiguracja'

run "$RALPH_SECTION" "echo READY" "codex"
expect "codex: AGENTS.md z treścią + gate READY -> exit 0" 0

# --- Bramka rozjazdu kontraktu (CLAUDE.md vs AGENTS.md) ---------------------------------------

# run2 <claude_content|__NOFILE__> <agents_content|__NOFILE__> <gate_stub> <runtime>
run2() {
  local claude_md="$1" agents_md="$2" stub="${3:-}" runtime="${4:-claude}" dir
  dir=$(mktemp -d)
  [ "$claude_md" != "__NOFILE__" ] && printf '%s' "$claude_md" > "$dir/CLAUDE.md"
  [ "$agents_md" != "__NOFILE__" ] && printf '%s' "$agents_md" > "$dir/AGENTS.md"
  LAST_OUT=$(cd "$dir" && RALPH_GATE_CMD="$stub" bash "$PREFLIGHT" "$runtime" 2>&1)
  LAST_RC=$?
  rm -rf "$dir"
}

DRIFTED_SECTION=$'## Ralph\n\nFeedback loops przed commitem: `composer test`, `./vendor/bin/pint`.\nCommituj prosto na `main`.\nDone: zadanie skończone, gdy testy są zielone.\n'

# 9. Oba pliki z identyczną sekcją -> bramka milczy.
run2 "$RALPH_SECTION" "$RALPH_SECTION" "echo READY" "claude"
expect "identyczne sekcje w obu plikach -> exit 0" 0

# 10. Rozjazd treści -> halt z diffem, niezależnie od runtime'u.
run2 "$RALPH_SECTION" "$DRIFTED_SECTION" "echo READY" "claude"
expect "rozjazd sekcji -> halt (runtime claude)" 1 "się różnią"
expect "rozjazd pokazuje różnicę" 1 "Commituj prosto na"

run2 "$RALPH_SECTION" "$DRIFTED_SECTION" "echo READY" "codex"
expect "rozjazd sekcji -> halt (runtime codex)" 1 "się różnią"

# 11. Różnica tylko w końcowych spacjach i pustych liniach -> to NIE jest rozjazd.
#     Bajt-w-bajt wywróciłoby się tutaj i wyszkoliło w ignorowaniu bramki.
WHITESPACE_VARIANT=$(printf '%s' "$RALPH_SECTION" | sed -e 's/$/   /' -e 's/^$//')
WHITESPACE_VARIANT="$WHITESPACE_VARIANT"$'\n\n'
run2 "$RALPH_SECTION" "$WHITESPACE_VARIANT" "echo READY" "claude"
expect "różnica tylko w whitespace -> exit 0" 0

# 12. Brak drugiego pliku -> brak bramki (repo tylko-Claude zostaje legalne).
run2 "$RALPH_SECTION" "__NOFILE__" "echo READY" "claude"
expect "brak AGENTS.md -> brak bramki, exit 0" 0

# 13. Drugi plik istnieje, ale bez sekcji ## Ralph -> brak bramki; ten runtime i tak padnie
#     głośno na własnym preflightcie, gdy go odpalisz.
run2 "$RALPH_SECTION" $'# Repo\n\nOpis.\n' "echo READY" "claude"
expect "AGENTS.md bez sekcji -> brak bramki, exit 0" 0
run2 "$RALPH_SECTION" $'# Repo\n\nOpis.\n' "echo READY" "codex"
expect "AGENTS.md bez sekcji -> halt w runtime codex" 1 '$ralph-konfiguracja'

echo
echo "Wynik: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
