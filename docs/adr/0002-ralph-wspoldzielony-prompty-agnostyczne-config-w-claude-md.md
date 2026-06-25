# Ralph współdzielony — prompty agnostyczne, konfiguracja w CLAUDE.md

**Kontekst.** Miałem osobne kopie katalogu `ralph/` per stack (Laravel, dialog-app =
RN/Expo). Po porównaniu okazało się, że skrypty (`once.sh`, `select.md`, skill
`to-issues-ralph`) różnią się tylko **nieszkodliwym nadzbiorem** (gate `needs-human-test`
jest bierny, gdy repo nie używa labelki), a **jedyna realna różnica to sposób testowania w
prompcie workera**. Kopie się rozjeżdżały; chcę jednego wspólnego kompletu działającego w
wielu repo.

**Decyzja.** Jeden wspólny komplet skryptów i promptów. Prompty są **agnostyczne wobec
stacka** — trzymają uniwersalny szkielet (TASK / SANITY / EXPLORATION / `/tdd` / COMMIT /
FINAL), a rzeczy per-stack (feedback loops, done-criteria) **delegują do sekcji `## Ralph` w
CLAUDE.md** danego repo (worker i tak wczytuje CLAUDE.md). **Strażnik fail-closed** (`grep`
→ Haiku-gate, w `ralph/preflight.sh`, `source`'owany przez oba skrypty) wstrzymuje pętlę,
gdy repo nie deklaruje sekcji `## Ralph`, i kieruje do `/ralph-konfiguracja`. **Dystrybucja:**
`install.sh` linkuje globalnie launchery `ralph-once` / `ralph-once-local` → `~/.local/bin`
(obok skilli → `~/.claude/skills`); skrypty samolokują prompty przez `$SCRIPT_DIR` (`realpath`
rozwija symlink), a `git` / `gh` / `issues` działają względem cwd.

## Rozważane opcje

**Gdzie żyje to, co per-stack:**
- **Cały prompt per-repo** — odrzucone: uniwersalny szkielet duplikuje się w każdym repo i
  się rozjeżdża.
- **Fragment per-repo** (wspólny szkielet + `ralph/testing.md` w repo, sklejane) — odrzucone:
  dodatkowa mechanika sklejania, katalog `ralph/` mieszany (część symlink, część plik).
- **Config w CLAUDE.md (wybrane)** — spójne z `/zapisz` / `/podsumuj`, worker i tak ma
  CLAUDE.md w kontekście, cały `ralph/` zostaje identyczny → trywialna dystrybucja.

**Jak skrypty trafiają do repo:**
- **Symlink katalogu per-repo** (`repo/ralph → ai-coding/ralph`) — odrzucone: wstawia do repo
  projektowego symlink z **absolutną ścieżką** → dangling po clone w inne miejsce
  (nieprzenośne), a `install.sh` i tak nie zna listy repo.
- **Launchery na PATH (wybrane)** — repo projektowe **bez żadnego symlinku** (tylko
  zacommitowana sekcja `## Ralph` + labelki w GitHub) → przenośne; instalacja raz na maszynę
  samolokującym `install.sh`.

## Konsekwencje

- Każde repo **musi** mieć sekcję `## Ralph` w CLAUDE.md, inaczej pętla się nie rusza
  (fail-closed). `/ralph-konfiguracja` (skill globalny, na modelu sesji = Sonnet+) ją tworzy,
  wykrywając stack, i zakłada labelki w wariancie GitHubowym.
- `once.sh` ma teraz **dwa tanie przebiegi Haiku** przed workerem: strażnik (po `grep`, po
  sprawdzeniu „czy są issues") oraz selektor.
- Skrypty czytają prompty przez `$SCRIPT_DIR`; komendy repo-zależne (`git`/`gh`/`issues`)
  działają na cwd. To jedyna realna zmiana w skryptach.
- `once.sh` / `select.md` / `to-issues-ralph` zunifikowane do nadzbioru z dialog-app — gate i
  backstop `needs-human-test` są bierne, gdy labelka nieużywana.
- `once-local.sh` zostaje **jednomodelowy** (bez selektora i mapy complexity), z tym samym
  strażnikiem przez `preflight.sh`.
- Mózg (CLAUDE.md + labelki) jedzie z repo; silnik instalujesz raz na maszynę. Dangling
  launchery (po przeniesieniu `ai-coding`) naprawia idempotentny `re-run install.sh`.
- Otwarty TODO „po implementacji wypisz testy manualne" wpada teraz w done-criteria sekcji
  `## Ralph` (także dla Laravela), bez osobnej mechaniki.
