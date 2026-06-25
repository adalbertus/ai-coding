# ai-coding — skille `/zapisz` i `/podsumuj`

Dwa globalne skille Claude Code do wznawiania **jednego wątku pracy na repo**:

- **`/zapisz`** — na granicy fazy zapisuje minimalny wskaźnik pozycji do `./tmp/STATUS.md`
  (gdzie skończyłem + następny krok). Nie przepisuje pracy — ta siedzi w artefaktach (PRD, issues).
- **`/podsumuj`** — na żądanie daje 2–3 zdania „gdzie jestem + następny krok", sam dobierając
  źródło: żywy kontekst (**ciepło**) → `./tmp/STATUS.md` (**zimno**) → ostatni transkrypt sesji
  (za zgodą).

Design: `CONTEXT.md` (słownik) i `docs/adr/0001` (warstwowy fallback).

## Instalacja

```bash
./install.sh
```

Instalator jest **samolokujący** (działa z dowolnego katalogu), **najpierw pyta o zgodę**
i **idempotentny** (ponowne uruchomienie nie psuje poprawnych symlinków). Tworzy:

- `~/.claude/skills/zapisz` → `skills/zapisz`
- `~/.claude/skills/podsumuj` → `skills/podsumuj`

Źródło zostaje w tym repo, a `~/.claude/skills` tylko linkuje — dzięki temu skille działają
we wszystkich repo i zmiany tutaj są od razu widoczne.

## Użycie

W dowolnym repo, w sesji Claude Code:

- **`/zapisz`** — na spokojnej granicy fazy. Nadpisuje jeden `./tmp/STATUS.md`.
- **`/podsumuj`** — gdy wracasz: ciepło (po `claude -r`, transkrypt w kontekście) albo
  zimno (nowy `claude`, pusty kontekst).

Oba wołane są **tylko jawnie** (`disable-model-invocation`) — nie odpalą się same.

### Format `./tmp/STATUS.md`

```markdown
# <tytuł wygenerowany z sesji>
Zapisano: 2026-06-25 15:59

**Ostatni etap:** <co domknięte albo gdzie przerwane>
**Następny krok:** <komenda lub akcja>
**Otwarta kwestia:** <jedno zdanie — tylko jeśli przerwane w pół>
```

`./tmp/` jest poza gitem (zob. `.gitignore`) — STATUS jest lokalny per maszyna; przy jednym
wątku na repo i jednej maszynie to wystarcza.

## Odinstalowanie

```bash
rm ~/.claude/skills/zapisz ~/.claude/skills/podsumuj
```
