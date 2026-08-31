#!/usr/bin/env bash
set -euo pipefail

# Samolokujący: katalog tego skryptu = korzeń repo (działa z dowolnego cwd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CODEX_BASE_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS_DIR="$CODEX_BASE_DIR/skills"
BIN_DIR="$HOME/.local/bin"
PLUGIN_MARKETPLACE="$SCRIPT_DIR/.agents/plugins/marketplace.json"

SKILLS=(zapisz podsumuj sesja sesja-konfiguracja ralph-konfiguracja to-issues-ralph)
# launcher:ścieżka-względna-do-skryptu — globalny launcher symlinkuje do skryptu w repo.
# Skrypty samolokują prompty przez realpath, więc działają z dowolnego repo (cwd).
LAUNCHERS=("ralph-once:ralph/once.sh" "ralph-once-local:ralph/once-local.sh")

echo "Instalator: skille Claude/Codex + launchery Ralpha"
echo "  źródło   : $SCRIPT_DIR"
echo "  Claude   : $CLAUDE_SKILLS_DIR"
echo "  Codex    : $CODEX_SKILLS_DIR"
echo "  launchery: $BIN_DIR"
echo

read -r -p "Utworzyć symlinki? [y/N] " ans
case "${ans:-}" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Przerwano — nic nie zmieniono."; exit 0 ;;
esac

# Idempotentne, bezpieczne linkowanie: nigdy nie nadpisuje cudzych plików ani symlinków.
make_link() {
  local src="$1" link="$2" name="$3"

  if [ ! -e "$src" ]; then
    echo "✗ $name: brak źródła ($src) — pomijam."
    return
  fi

  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$src" ]; then
      echo "✓ $name: już zainstalowany (poprawny symlink)."
    else
      echo "✗ $name: symlink wskazuje gdzie indziej ($(readlink "$link")) — zostawiam, usuń ręcznie jeśli chcesz."
    fi
    return
  fi

  if [ -e "$link" ]; then
    echo "✗ $name: $link już istnieje i nie jest symlinkiem — zostawiam, usuń ręcznie jeśli chcesz."
    return
  fi

  ln -s "$src" "$link"
  echo "✓ $name: zainstalowany → $src"
}

# 1. Skille → native skills dirs
echo "Skille Claude:"
mkdir -p "$CLAUDE_SKILLS_DIR"
for name in "${SKILLS[@]}"; do
  make_link "$SCRIPT_DIR/skills/$name" "$CLAUDE_SKILLS_DIR/$name" "$name"
done

echo
echo "Skille Codex:"
mkdir -p "$CODEX_SKILLS_DIR"
for name in "${SKILLS[@]}"; do
  make_link "$SCRIPT_DIR/skills/$name" "$CODEX_SKILLS_DIR/$name" "$name"
done

# 2. Launchery Ralpha → ~/.local/bin
echo
echo "Launchery Ralpha:"
chmod +x "$SCRIPT_DIR"/ralph/once.sh "$SCRIPT_DIR"/ralph/once-local.sh "$SCRIPT_DIR"/ralph/preflight.sh 2>/dev/null || true
mkdir -p "$BIN_DIR"
for entry in "${LAUNCHERS[@]}"; do
  name="${entry%%:*}"; rel="${entry#*:}"
  make_link "$SCRIPT_DIR/$rel" "$BIN_DIR/$name" "$name"
done

echo
echo "Gotowe (to instalujesz RAZ, globalnie — nie trzeba powtarzać per repo)."
echo "  Skille Claude: /zapisz, /podsumuj, /sesja, /sesja-konfiguracja, /ralph-konfiguracja, /to-issues-ralph"
echo "  Skille Codex:  \$zapisz, \$podsumuj, \$sesja, \$sesja-konfiguracja, \$ralph-konfiguracja, \$to-issues-ralph"
echo "  Launchery: ralph-once, ralph-once-local (wymagają $BIN_DIR w PATH)"
if [ -f "$PLUGIN_MARKETPLACE" ]; then
  echo "  Codex plugin: repo-local marketplace gotowy pod $PLUGIN_MARKETPLACE"
  echo "                aby użyć pluginu:"
  echo "                codex plugin marketplace add $SCRIPT_DIR/.agents/plugins"
  echo "                codex plugin add ai-coding --marketplace ai-coding-local"
fi
echo
echo "Następny krok — W KAŻDYM repo, w którym chcesz używać Ralpha:"
echo "  1. odpal w sesji Claude albo Codex: /ralph-konfiguracja lub \$ralph-konfiguracja"
echo "     → zapisze sekcję ## Ralph do CLAUDE.md i AGENTS.md oraz utworzy labelki na GitHubie."
echo "  2. (porządkowo) usuń stary, dedykowany katalog ralph/ z tego repo."
echo "  Bez ## Ralph strażnik jest fail-closed i ralph-once od razu się zatrzyma."
