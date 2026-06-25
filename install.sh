#!/usr/bin/env bash
set -euo pipefail

# Samolokujący: katalog tego skryptu = korzeń repo (działa z dowolnego cwd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILLS=(zapisz podsumuj)

echo "Instalator skilli /zapisz i /podsumuj"
echo "  źródło : $SCRIPT_DIR/skills"
echo "  cel    : $SKILLS_DIR"
echo

read -r -p "Utworzyć symlinki w $SKILLS_DIR? [y/N] " ans
case "${ans:-}" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Przerwano — nic nie zmieniono."; exit 0 ;;
esac

mkdir -p "$SKILLS_DIR"

for name in "${SKILLS[@]}"; do
  src="$SCRIPT_DIR/skills/$name"
  link="$SKILLS_DIR/$name"

  if [ ! -d "$src" ]; then
    echo "✗ $name: brak źródła ($src) — pomijam."
    continue
  fi

  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$src" ]; then
      echo "✓ $name: już zainstalowany (poprawny symlink)."
    else
      echo "✗ $name: symlink wskazuje gdzie indziej ($(readlink "$link")) — zostawiam, usuń ręcznie jeśli chcesz."
    fi
    continue
  fi

  if [ -e "$link" ]; then
    echo "✗ $name: $link już istnieje i nie jest symlinkiem — zostawiam, usuń ręcznie jeśli chcesz."
    continue
  fi

  ln -s "$src" "$link"
  echo "✓ $name: zainstalowany → $src"
done

echo
echo "Gotowe. Sprawdź w Claude Code: /zapisz, /podsumuj."
