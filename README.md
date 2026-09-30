# ai-coding — skille Claude/Codex + współdzielony Ralph

Globalne narzędzia do pracy z agentami kodującymi w **jednym wątku na repo**:

- **Skille `zapisz`, `podsumuj`, `sesja`, `sesja-konfiguracja`** — wyłączone: leżą w `skills/`,
  ale `install.sh` ich nie linkuje (zob. [Wyłączone skille](#wyłączone-skille)).
- **Współdzielony Ralph** — jedna autonomiczna pętla implementacyjna dla wszystkich repo,
  niezależnie od stacku. Specyfika repo (jak testować, kiedy „gotowe") siedzi w sekcji
  `## Ralph` w natywnym pliku agenta (`CLAUDE.md` / `AGENTS.md`), a nie w kopii skryptu.
- **Skille Ralpha** — `ralph-konfiguracja` (setup repo) i `to-issues-ralph` (triage zadań).

Design: `CONTEXT.md` (słownik), `docs/adr/0001` (warstwowy fallback `/podsumuj`),
`docs/adr/0002` (współdzielony Ralph: prompty agnostyczne + config w CLAUDE.md),
`docs/adr/0009` (Claude/Codex przez wspólny rdzeń i adaptery runtime'u).

## Instalacja

Dwa etapy: **raz globalnie** instalujesz to repo, a potem **raz na repo** włączasz w nim Ralpha.

### Etap 1 — raz, globalnie (instalacja `ai-coding`)

```bash
git clone <ai-coding> ~/projects/ai-coding
cd ~/projects/ai-coding
./install.sh
```

Instalator jest **samolokujący** (działa z dowolnego katalogu), **najpierw pyta o zgodę**
i **idempotentny** (ponowne uruchomienie nie psuje poprawnych symlinków). Tworzy:

- skille Claude → `~/.claude/skills`: `ralph-konfiguracja`, `to-issues-ralph`
- skille Codex → `${CODEX_HOME:-~/.codex}/skills`: te same nazwy, wołane w Codexie jako `$...`
- launchery → `~/.local/bin`: `ralph-once`, `ralph-once-local`, `ralph-epic`
- repo-local plugin Codex → `.agents/plugins/marketplace.json` + `.agents/plugins/plugins/ai-coding`

Źródło zostaje w tym repo, a katalogi skills i `~/.local/bin` tylko linkują — `realpath` rozwija
symlink, więc skrypty Ralpha znajdują swoje prompty obok siebie. Repo projektowe **nie** zawiera
symlinka, więc po sklonowaniu Ralpha odpalasz globalnym launcherem. To robisz **tylko raz** —
nie powtarzasz `install.sh` w każdym repo.

> Launchery wymagają `~/.local/bin` w `PATH`.

Opcjonalnie, jeśli chcesz widzieć ai-coding jako plugin Codex:

```bash
codex plugin marketplace add ~/projects/ai-coding/.agents/plugins
codex plugin add ai-coding --marketplace ai-coding-local
```

### Etap 2 — raz na każde repo, w którym chcesz Ralpha

Repo bez Ralpha potrzebuje tylko sekcji `## Ralph` w swoim `CLAUDE.md` i `AGENTS.md` — inaczej
strażnik jest fail-closed i `ralph-once <runtime>` od razu halt-uje. Sekcję pisze
`/ralph-konfiguracja` albo `$ralph-konfiguracja`:

```bash
cd ~/projects/repo-laravel            # repo nr 1 — stack PHP/Laravel, jeszcze bez Ralpha
# w sesji Claude albo Codex: /ralph-konfiguracja lub $ralph-konfiguracja
#   → wykrywa stack (composer test / pint), pisze ## Ralph do CLAUDE.md i AGENTS.md, tworzy labelki
ralph-once                            # pętla rusza, bo ## Ralph już jest
ralph-once codex                      # ta sama pętla przez Codex

cd ~/projects/repo-expo               # repo nr 2 — stack RN/Expo, jeszcze bez Ralpha
# w sesji Claude albo Codex: /ralph-konfiguracja lub $ralph-konfiguracja
#   → wykrywa stack (npm typecheck/lint/test + needs-human-test), pisze ## Ralph, tworzy labelki
ralph-once
```

Ten sam globalny `ralph-once` obsłużył oba repo o różnych stackach — jedyna różnica siedzi
w sekcji `## Ralph` każdego z nich. `install.sh` z Etapu 1 nie był tu powtarzany.

## Wyłączone skille

`zapisz`, `podsumuj`, `sesja` i `sesja-konfiguracja` nie są linkowane przez `install.sh` — przez
miesiąc nie było ani jednego wywołania, a opis każdego zlinkowanego skilla trafia do kontekstu
każdej sesji. Opisy poniżej zostają na wypadek powrotu. Włączenie ręczne (Codex analogicznie
w `~/.codex/skills`):

```bash
ln -s ~/projects/ai-coding/skills/sesja ~/.claude/skills/sesja
```

## Skille `zapisz` i `podsumuj`

- **`/zapisz` / `$zapisz`** — na granicy fazy zapisuje minimalny wskaźnik pozycji do `./tmp/STATUS.md`
  (gdzie skończyłem + następny krok). Nie przepisuje pracy — ta siedzi w artefaktach (PRD, issues).
- **`/podsumuj` / `$podsumuj`** — na żądanie daje 2–3 zdania „gdzie jestem + następny krok", sam dobierając
  źródło: żywy kontekst (**ciepło**) → `./tmp/SESJA.md` → `./tmp/STATUS.md` (**zimno**) →
  ostatni transkrypt sesji, jeśli runtime udostępnia go w przewidywalnym miejscu (za zgodą).
  Niedomknięta sesja bije STATUS — jest nowsza z definicji i konkretniejsza.

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

## Skill `sesja`

Punkt wejścia do sesji projektowych, żeby **nie kompaktować** długiej deliberacji. Kompakt gubi
to, co **odrzucone**, więc sesja wraca do zamkniętych gałęzi i pyta drugi raz o to samo — jedna
sesja zjadła 6 kompaktów po ~100k za zero produktu pracy. Zamiast tego: rozstrzygnięcia lądują
w `CONTEXT.md`/ADR, otwarte w `./tmp/SESJA.md`, a kontekst czyścisz. Zob.
`docs/adr/0006`.

```bash
/sesja <temat>     # start — nowy temat otwiera się grillem
/sesja             # w trakcie → checkpoint, potem /clear
/sesja             # po /clear → wznowienie od następnej otwartej gałęzi
/sesja domknięte   # koniec → kasuje SESJA.md, wskazuje /to-prd

$sesja <temat>     # odpowiednik w Codex
```

Tryb rozpoznaje po tym, **czy w kontekście jest dialog deliberacyjny** — nie po istnieniu pliku.
Zakres wyznacza oś **deliberacja vs implementacja**, nie obecność grilla: zwykła rozmowa
o designie liczy się tak samo, a plik zapamiętuje w polu `Wznowić`, czym była, żeby wznowić ją
tak samo. Grill, gdy jest, prowadzi skill `grill-with-docs`, wołany (nigdy kopiowany). Sesje
implementacyjne (Ralph) są poza zakresem — tam kontekst to dosłowne odczyty plików i czyszczenie
go jest stratą, nie zyskiem.

### Format `./tmp/SESJA.md`

```markdown
# Sesja: <temat>
Zapisano: 2026-08-06 21:15 · Wznowić: grill-with-docs | rozmowa

## Ustalone
- <decyzja w jednej linii> (<powód w kilku słowach>)
- <termin albo decyzja> → ADR 0006 · CONTEXT: ramka

## Otwarte
1. <gałąź> — <część już ustalona, jeśli połowicznie rozstrzygnięta>

## Odrzucone
- <wariant> — <powód>

## Słownik
- <termin> — <znaczenie ustalone w tej sesji>
```

Sekcja **Odrzucone** jest tu najważniejsza: to ona ginie w kompakcie i to przez jej brak wznowiona
sesja z entuzjazmem wraca do wariantu odstrzelonego czterdzieści pytań wcześniej.

### Skill `sesja-konfiguracja` — raz na repo

`/sesja` / `$sesja` działa wszędzie bez konfiguracji, ale nic **nie przypomni** ci o nim: skill jest
wywoływany tylko jawnie, więc rozmowa wyjeżdża ze smart zone niezauważona do momentu, w którym
sam sobie o tym przypomnisz — czyli w najgorszej chwili na przypominanie.
`/sesja-konfiguracja` / `$sesja-konfiguracja` dopisuje do `CLAUDE.md` i `AGENTS.md` repo krótką
sekcję `## Sesja`, przez co model sam przerywa i proponuje checkpoint, gdy zauważy, że wracacie
do sprawy już rozstrzygniętej. Przy okazji sprawdza, czy `./tmp/` jest poza gitem.

Sekcja jest w każdym repo praktycznie taka sama — to **dystrybucja**, nie konfiguracja. Sens jest
w tym, że włączasz ją świadomie tam, gdzie faktycznie deliberujesz, i że siedzi w wersjonowanym
plikach projektu, a nie w globalnych plikach agenta, których `install.sh` nie rozwozi i które
znikają przy przesiadce na inną maszynę.

## Współdzielony Ralph

Pętla bierze **jedno** zadanie, implementuje je, uruchamia feedback loops i commituje — AFK
(away-from-keyboard), z terminala. Runtime wybierasz argumentem:

```bash
ralph-once 224          # domyślnie Claude, wstecznie kompatybilne
ralph-once claude 224   # jawnie Claude
ralph-once codex 224    # jawnie Codex
ralph-once 12           # 12 to epic ([PRD]) → pierwsze wolne z jego otwartych sub-issues
ralph-once              # selektor + worker przez Claude
ralph-once codex        # selektor + worker przez Codex
ralph-once-local codex  # lokalne issues/*.md przez Codex
ralph-once 224 --force-model=opus  # Opus z effort high zamiast modelu z complexity:*
```

Dwa flavoury, jeden zestaw promptów:

- **`ralph-once`** — zadania w GitHub Issues (label `ready-for-agent`). Selektor wybranego
  runtime'u wybiera następne issue, a model worker'a zależy od labelki `complexity:*`.
- **`ralph-once-local`** — zadania w plikach `issues/*.md`, bez selektora GitHub.

**`--force-model=sonnet|opus`** (wszystkie trzy komendy, tylko Claude) pomija etykietę
`complexity:*`: każde issue jedzie na wskazanym modelu z effort high, także sesja HITL. Flaga może
stać w dowolnym miejscu. Strażnik i selektor zostają na Haiku. Z Codeksem run odmawia startu.

Oba zaczynają od **strażnika** (`ralph/preflight.sh`, fail-closed): repo musi mieć gotową sekcję
`## Ralph` w natywnym pliku runtime'u (`CLAUDE.md` dla Claude, `AGENTS.md` dla Codex), inaczej
pętla halt-uje z instrukcją konfiguracji. Gdy repo ma oba pliki i oba deklarują `## Ralph`,
strażnik dodatkowo pilnuje, żeby te sekcje były **identyczne** — rozjazd oznacza, że rzadziej
używany runtime pracuje na nieaktualnych regułach (np. commituje na inną gałąź), więc run pada
z diffem i kieruje do `/ralph-konfiguracja`.

Claude jedzie **bez nadzoru**: `claude -p` w **auto mode** (`--permission-mode auto`) ze
strumieniowym wyjściem JSON. Worker kończy się sam po domknięciu issue. Na ekranie widać jedną
krótką linię na krok (`▸ Bash: bash test.sh`, `▸ Edit: greet.sh`) i na końcu podsumowanie modelu.
Codex też jedzie **bez nadzoru**: `codex exec --json --approve-for-me` (eskalacje sandboxa idą
przez automatyczny review; flaga jest w `codex exec` od wersji 0.159). Na ekranie ta sama jedna
linia na krok (`▸ Bash: …`, `▸ Edit: …`, `▸ Write: …`) i podsumowanie modelu. W obu runtime'ach
celem jest AFK bez `dangerously-bypass-*`.

**Sesja HITL.** Tryb workera wynika z issue, nie z komendy. Issue z labelką `ready-for-agent`
idzie bez nadzoru (jak wyżej); issue bez niej to HITL i `ralph-once <nr>` otwiera dla niego
sesję **interaktywną** (`claude --permission-mode auto` albo `codex --no-alt-screen
--approve-for-me`) z osobnym promptem `ralph/prompt-hitl.md`. Worker zaczyna od tego, jaka decyzja
lub czynność jest potrzebna od Ciebie, z rekomendacją; po Twojej odpowiedzi implementuje i domyka
issue tymi samymi regułami co przebieg AFK (w tym odchylenia w epicu). `ralph-once` bez numeru
nadal bierze wyłącznie AFK.

**Odkryty HITL i oddanie issue pętli.** Jeśli worker AFK w sanity checku stwierdzi, że issue
wymaga decyzji albo czynności człowieka, zdejmuje z niego `ready-for-agent`, komentuje, czego
dokładnie trzeba (z rekomendacją), i kończy run. Issue nie wraca do pętli samo: gdy sprawa jest
rozstrzygnięta, oddajesz je pętli, przywracając labelkę
(`gh issue edit <nr> --add-label ready-for-agent`).

**Zapis runu (Claude i Codex).** Pełny strumień JSON ląduje w `.git/ralph-logs/` (plik
`<data>-<godzina>-issue-<nr>.jsonl`, dla `ralph-once-local` `…-local.jsonl`). Katalog powstaje
przy pierwszym runie i leży poza drzewem roboczym, więc nie zmienia `git status`. Na końcu skrypt
wypisuje `claude --resume <id>` (Codex: `codex resume <id>`) — tą komendą wchodzisz do sesji workera, żeby zobaczyć, co
zrobił, albo go dopytać. Codex pisze błędy narzędzi tylko na stderr, więc obok JSONL leży
`…-issue-<nr>.stderr.log`, a gdy są w nim linie `ERROR`, skrypt wypisuje ścieżkę i pierwsze z nich. Ostrzeżenie o brudnym drzewie po runie działa jak wcześniej.

### Lock worktree

Ralph zakłada lock per worktree, nie per issue. Jeśli lock istnieje i PID żyje, interaktywny run
pyta, czy przerwać, czy zakończyć tamten proces; non-interactive zawsze przerywa. Jeśli PID nie
żyje, interaktywny run pyta o usunięcie stale locka, a non-interactive usuwa go i kontynuuje.
Równoległe Claude+Codex rób przez osobne worktree/branche.

### Kontrakt `## Ralph` (w `CLAUDE.md` / `AGENTS.md` repo)

Prompty są stack-agnostyczne — całą specyfikę repo delegują do sekcji `## Ralph`:

- **feedback loops** — konkretne komendy do uruchomienia przed commitem (np. `composer test`
  / `npm test`); worker używa dokładnie ich, nie wymyśla własnych.
- **done-criteria** — kiedy zadanie jest skończone; czy część pracy wymaga weryfikacji
  człowieka (UI/urządzenie → `needs-human-test`).
- **commit** (opcjonalnie) — język wiadomości, `main` vs branch/PR, gdzie trafia detal.
- **doc-sync** (opcjonalnie) — trwałe dokumenty repo (known-gaps, backlog) i ich klasa; zamykając
  issue worker/człowiek najpierw godzi je z tym, co weszło. Słownik (`CONTEXT.md`) i ADR-y tylko
  się zgłasza, nie przepisuje. Bierny, gdy repo nie ma trwałych dokumentów.
- **gałąź per epic** (opcjonalnie) — jedna linia o stałej składni `ralph-base-branch: <gałąź>`
  (np. `ralph-base-branch: dev`), osobno w swojej linii. Brak linii = trunk. Zła składnia zatrzymuje
  pętlę z komunikatem.

Sekcja zawiera też done-criteria pod epice (sub-issue zamyka gate, resztę sprawdza odbiór epicu),
zamknięcie epicu („zamykaj" / „potwierdzam": doc-sync, merge gałęzi epicu do bazy, usunięcie gałęzi,
zamknięcie) i ścieżkę uwag z odbioru (drobiazg od razu w sesji, rzecz większa jako sub-issue
`[ISSUE] Poprawka: …`). Linię gałęzi per epic skill wpisuje tylko dla repo z osobną gałęzią
produkcyjną (np. `main` = produkcja, `dev` = praca).

Sekcję pisze `/ralph-konfiguracja` — nie pisz jej ręcznie.

### Przepływ

Jednostką odbioru jest **epic** (rodzic `[PRD]` z natywnymi sub-issues GitHuba), a nie pojedyncze
issue — szczegóły i uzasadnienie w `docs/adr/0012`. Każda praca jest epicem, także jednolinijkowa
zmiana (epic z jednym sub-issue). Terminologia: `CONTEXT.md` (**Epic**, **Odbiór**).

1. **`/ralph-konfiguracja` / `$ralph-konfiguracja`** — raz na repo. Wykrywa stack, pisze
   `## Ralph` do `CLAUDE.md` i `AGENTS.md`, tworzy labelki pętli na GitHubie.
2. **`/to-issues-ralph` / `$to-issues-ralph`** — z planu/PRD publikuje epic (`[PRD]` z PRD i
   scenariuszem `## Jak odebrać`, label `ready-for-agent`) oraz sub-issues (vertical slices)
   z triage `complexity:*`. Sub-issues nie mają sekcji ręcznej — scenariusz jest jeden, w epicu.
   Po tym kroku nie musisz nic robić poza uruchomieniem pętli.
3. **`ralph-once`** (albo `ralph-once-local`) w pętli z terminala — implementacja AFK, jedno
   sub-issue na run.
4. **Odbiór** — pętla staje raz na epic, gdy skrypt oznaczy epic (ostatnie sub-issue zamknięte; patrz niżej).

**Sub-issues i gate.** Sub-issue epicu worker zamyka sam po zielonym gate (doc-sync w tym samym
commicie), bez względu na done-criteria o weryfikacji ręcznej — ta część przechodzi na odbiór epicu.
Odchylenia od planu idą komentarzem do epicu (brak odchyleń = brak komentarza). Epic oznacza do odbioru
skrypt, nie worker: przed wyborem issue i po runie workera pętla sprawdza epice, a epic bez
otwartych sub-issues i bez `needs-human-test` dostaje tę etykietę i jeden komentarz — bez względu
na to, kto zamknął ostatnie sub-issue (też ręcznie). `ralph-once <nr epicu>` na takim epicu
oznacza go i nie uruchamia workera.

**Odbiór epicu.** `needs-human-test` na epicu to bezpiecznik: dopóki jest, pętla nie zaczyna nowej
pracy. Przechodzisz scenariusz z `## Jak odebrać` i:

- **„zamykaj" / „potwierdzam"** — Claude w sesji robi zamknięcie: doc-sync, merge gałęzi epicu do
  bazy (jeśli jest), usunięcie gałęzi, zamknięcie epicu;
- **uwagi** — drobiazg Claude poprawia od razu w sesji; rzecz większa staje się nowym sub-issue
  `[ISSUE] Poprawka: …` pod epicem, epic traci label, a pętla ją dokańcza.

**Wybór pracy.** W trybie pętli, jeśli istnieje **rozpoczęty epic** (co najmniej jedno zamknięte
sub-issue) z otwartymi sub-issues, selektor dostaje tylko sub-issues najstarszego takiego epicu
(filtr w `lib.sh`, czysta funkcja) — pętla dokańcza epic, zanim weźmie następny. `ralph-once <nr epicu>`
pracuje nad sub-issue wskazanego epicu; epic bez otwartych sub-issues daje komunikat i wyjście bez
workera. Tak przeskakuje się na pilny epic.

**Kolejność w epicu: AFK, potem HITL** (ADR 0013). `ralph-once <nr epicu>` najpierw bierze
niezablokowane sub-issues z `ready-for-agent`. Dopiero gdy żadnego nie ma, bierze niezablokowane
otwarte sub-issue bez tej etykiety i otwiera dla niego sesję HITL. Zablokowane HITL nie są brane;
gdy nic nie zostaje — wyjście bez workera. Z wolnych bierze to o najniższym numerze, bez selektora:
sub-issues powstają w kolejności planu, a fałszywe `NO_TASK` modelu zatrzymywało `ralph-epic`.
Wybór to czyste funkcje `ralph_epic_stage` i `ralph_pick_first` w `lib.sh`, po filtrze blokerów.

**Kody wyjścia `ralph-once`** (kontrakt w nagłówku `ralph/once.sh`; kod wynika ze stanu issue po
runie, nie z wyniku procesu workera):

| Kod | Znaczenie |
|-----|-----------|
| 0 | issue domknięte |
| 1 | błąd lub odmowa: złe argumenty, brak issue, zajęty lock, strażnik, brudne drzewo, konflikt scalania |
| 2 | nic do zrobienia: bramka `needs-human-test`, epic w odbiorze, brak lub zablokowani kandydaci, `NO_TASK` |
| 3 | run AFK zostawił issue otwarte i nadal z `ready-for-agent` (porażka, praca niedokończona) |
| 4 | run AFK zostawił issue otwarte bez `ready-for-agent` (odkryty HITL) |
| 5 | sesja HITL skończona, issue otwarte i bez `ready-for-agent` (nierozwiązane) |
| 6 | sesja HITL skończona, issue otwarte z przywróconym `ready-for-agent` (wraca do AFK) |

#### `ralph-epic` — epic od startu do odbioru

`ralph-epic [claude|codex] [nr]` powtarza `ralph-once <epic>` (jedno sub-issue na run, świeży kontekst,
model z `complexity` albo z `--force-model`, które przekazuje każdemu runowi), aż epic trafi do odbioru albo pętla musi stanąć. Decyduje wyłącznie na
podstawie kodów wyjścia `ralph-once` (czysta funkcja `ralph_epic_decision` w `lib.sh`), nie
własnego zgadywania.

**Kiedy używać:** gdy epic jest gotowy (sub-issues z `to-issues-ralph`) i chcesz go przepchnąć bez
wołania `ralph-once` za każdym razem. Bez numeru bierze epic tą samą regułą co selektor (rozpoczęty,
potem najniższy numer) i respektuje bramkę `needs-human-test` — odmawia i wymienia epic czekający
na odbiór. Z numerem bramkę pomija, jak `ralph-once`. Przy starcie sesji HITL i przy każdym stopie
wysyła powiadomienie systemowe (`osascript` na macOS; bez niego działa tak samo, tylko bez
powiadomień).

**Kiedy się zatrzyma i co zrobić:**

| Stop | Komunikat | Co robisz |
|------|-----------|-----------|
| epic w odbiorze (kod 0) | „Epic #N gotowy do odbioru” | przechodzisz `## Jak odebrać`, mówisz „zamykaj” albo zgłaszasz uwagi |
| AFK nie domknęło issue (3) | numer issue i wskazanie komentarza workera | czytasz komentarz i log w `.git/ralph-logs/`, poprawiasz przyczynę (albo issue) i uruchamiasz ponownie; pętla nie pomija issue |
| HITL nierozwiązane (5) | numer issue | rozstrzygasz: domykasz albo przywracasz `ready-for-agent`, uruchamiasz ponownie |
| nic do zrobienia (2) | lista otwartych sub-issues (HITL oznaczone) | odblokuj je, dodaj decyzję lub `ready-for-agent`, uruchom ponownie |
| błąd lub odmowa (1) | przyczyna z komunikatów `ralph-once` | naprawiasz (brudne drzewo, konflikt scalania, lock, strażnik) i uruchamiasz ponownie |
| limit iteracji (2) | liczba iteracji i lista otwartych | sprawdzasz, czemu epic nie schodzi, i uruchamiasz ponownie |

Sesja HITL rozwiązana (issue domknięte albo z przywróconym `ready-for-agent`) i odkryty HITL
(kod 4) nie zatrzymują pętli — idzie następna iteracja. Limit iteracji to dwukrotność liczby
otwartych sub-issues na starcie (zapas na sesję HITL po odkryciu); chroni tylko przed pętlą bez
końca. Kod: `ralph/epic.sh`; testy: `ralph/test/epic.test.sh` (atrapa `once.sh`, fałszywe `gh`).

**Blokery rozstrzyga skrypt.** Przed selektorem (w pętli i w trybie epicu) `lib.sh` czyta z sekcji
„Blocked by” każdego kandydata numery issues (`#12` i `12`) i odrzuca kandydata, jeśli którykolwiek
bloker jest otwarty (czysta funkcja `ralph_filter_unblocked`). Selektor dostaje tylko wolne issues
i decyduje wyłącznie o kolejności; gdy po filtrze nic nie zostaje, pętla mówi, że wszystkie
kandydaty są zablokowane, i nie wywołuje selektora. Selektora nie ma też przy jednym wolnym
kandydacie ani w trybie epicu (tam decyduje numer).

**Gałąź per epic** (opcjonalnie, gdy `## Ralph` ma `ralph-base-branch: <baza>`): `ralph-once` przed
workerem odmawia przy brudnym drzewie, a potem dla sub-issue przełącza się na `epic/<nr epicu>`
(pierwszy raz tworzy ją z bazy; jeśli baza poszła do przodu, scala ją do gałęzi epicu — konflikt
przerywa merge, zostawia czyste drzewo i kończy bez workera, kodem 1). Worker commituje na bieżącej
gałęzi, a repo zostaje na niej pod odbiór lokalny. Wszystko lokalnie, bez `fetch`/`push`; merge
epicu do bazy po odbiorze robi „zamykaj". Dzięki temu baza zawiera tylko epice odebrane. Bez tej
linii pętla nie przełącza gałęzi.

**Issue bez rodzica** działa po staremu: worker zamyka je po gate, a gdy done-criteria wymagają
człowieka, zostawia je otwarte z `needs-human-test` i krokami testowymi (sekcja `## Jak sprawdzić
ręcznie` z issue); nową pracę pętla bierze dopiero po zamknięciu przez człowieka. Na gałęzi idzie
ono na bazie.

#### Przykład: hotfix w trakcie epicu

Repo z `ralph-base-branch: dev`. Epic A (#10) jest w toku: zamknięte 1 z 3 sub-issues, repo stoi
na `epic/10`. Wpada pilna poprawka.

1. Robisz `/to-issues-ralph` dla poprawki — powstaje epic B (#20) z jednym sub-issue.
2. `ralph-once 20` — pętla przełącza się na `epic/20` (odbitą z `dev`, bez pracy z epicu A),
   worker robi sub-issue, a skrypt pętli nakłada `needs-human-test` na #20.
3. Odbierasz #20 wg jego `## Jak odebrać` i mówisz „zamykaj" — merge `epic/20` do `dev`, hotfix
   jedzie bez połowy epicu A.
4. Wracasz do pętli (`ralph-once`): selektor widzi rozpoczęty epic A i dokańcza jego sub-issues
   na `epic/10` (baza z hotfixem jest do niej scalana na starcie runu). Po ostatnim — odbiór A.

## Odinstalowanie

```bash
rm ~/.claude/skills/{ralph-konfiguracja,to-issues-ralph}
rm ~/.codex/skills/{ralph-konfiguracja,to-issues-ralph}
rm ~/.local/bin/{ralph-once,ralph-once-local,ralph-epic}
```
