# ai-coding — skille Claude Code + współdzielony Ralph

Globalne narzędzia do pracy z Claude Code w **jednym wątku na repo**:

- **Skille `/zapisz` i `/podsumuj`** — wznawianie wątku pracy między sesjami.
- **Współdzielony Ralph** — jedna autonomiczna pętla implementacyjna dla wszystkich repo,
  niezależnie od stacku. Specyfika repo (jak testować, kiedy „gotowe") siedzi w sekcji
  `## Ralph` w CLAUDE.md danego repo, a nie w kopii skryptu.
- **Skille Ralpha** — `/ralph-konfiguracja` (setup repo) i `/to-issues-ralph` (triage zadań).

Design: `CONTEXT.md` (słownik), `docs/adr/0001` (warstwowy fallback `/podsumuj`),
`docs/adr/0002` (współdzielony Ralph: prompty agnostyczne + config w CLAUDE.md).

## Instalacja

```bash
./install.sh
```

Instalator jest **samolokujący** (działa z dowolnego katalogu), **najpierw pyta o zgodę**
i **idempotentny** (ponowne uruchomienie nie psuje poprawnych symlinków). Tworzy:

- skille → `~/.claude/skills`: `zapisz`, `podsumuj`, `ralph-konfiguracja`, `to-issues-ralph`
- launchery → `~/.local/bin`: `ralph-once`, `ralph-once-local`

Źródło zostaje w tym repo, a `~/.claude/skills` i `~/.local/bin` tylko linkują — `realpath`
rozwija symlink, więc skrypty Ralpha znajdują swoje prompty obok siebie. Repo projektowe
**nie** zawiera symlinka, więc po sklonowaniu Ralpha odpalasz globalnym launcherem.

> Launchery wymagają `~/.local/bin` w `PATH`.

## Skille `/zapisz` i `/podsumuj`

- **`/zapisz`** — na granicy fazy zapisuje minimalny wskaźnik pozycji do `./tmp/STATUS.md`
  (gdzie skończyłem + następny krok). Nie przepisuje pracy — ta siedzi w artefaktach (PRD, issues).
- **`/podsumuj`** — na żądanie daje 2–3 zdania „gdzie jestem + następny krok", sam dobierając
  źródło: żywy kontekst (**ciepło**) → `./tmp/STATUS.md` (**zimno**) → ostatni transkrypt sesji
  (za zgodą).

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

## Współdzielony Ralph

Pętla bierze **jedno** zadanie, implementuje je, uruchamia feedback loops i commituje — AFK
(away-from-keyboard), z terminala. Dwa flavoury, jeden zestaw promptów:

- **`ralph-once`** — zadania w GitHub Issues (label `ready-for-agent`). Selektor (Haiku)
  wybiera następne issue, a model worker'a zależy od labelki `complexity:*`
  (`heavy`→Opus, `normal`→Sonnet, `trivial`→Haiku; mapping żyje w `ralph/once.sh`).
- **`ralph-once-local`** — zadania w plikach `issues/*.md`, jeden stały model.

Oba zaczynają od **strażnika** (`ralph/preflight.sh`, fail-closed): repo musi mieć w CLAUDE.md
gotową sekcję `## Ralph`, inaczej pętla halt-uje z instrukcją `/ralph-konfiguracja`.

### Kontrakt `## Ralph` (w CLAUDE.md repo)

Prompty są stack-agnostyczne — całą specyfikę repo delegują do sekcji `## Ralph`:

- **feedback loops** — konkretne komendy do uruchomienia przed commitem (np. `composer test`
  / `npm test`); worker używa dokładnie ich, nie wymyśla własnych.
- **done-criteria** — kiedy zadanie jest skończone; czy część pracy wymaga weryfikacji
  człowieka (UI/urządzenie → `needs-human-test`).
- **commit** (opcjonalnie) — język wiadomości, `main` vs branch/PR, gdzie trafia detal.

Sekcję pisze `/ralph-konfiguracja` — nie pisz jej ręcznie.

### Przepływ

1. **`/ralph-konfiguracja`** — raz na repo, w sesji Claude (Sonnet+). Wykrywa stack, pisze
   `## Ralph` do CLAUDE.md, tworzy labelki pętli na GitHubie.
2. **`/to-issues-ralph`** — z planu/PRD robi issues (vertical slices) + triage `complexity:*`.
3. **`ralph-once`** (albo `ralph-once-local`) w pętli z terminala — implementacja AFK.

**`needs-human-test`** to bezpiecznik: gdy gate nie udowodni poprawności (np. UI na
urządzeniu), worker zostawia issue otwarte z tą labelką i krokami testowymi; nową pracę pętla
bierze dopiero po weryfikacji i zamknięciu przez człowieka.

## Odinstalowanie

```bash
rm ~/.claude/skills/{zapisz,podsumuj,ralph-konfiguracja,to-issues-ralph}
rm ~/.local/bin/{ralph-once,ralph-once-local}
```
