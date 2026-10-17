# ai-coding — skille Claude/Codex + współdzielony Ralph (tylko Claude)

Globalne narzędzia do pracy z agentami kodującymi w **jednym wątku na repo**:

- **Skille `zapisz`, `podsumuj`, `sesja`, `sesja-konfiguracja`** — wyłączone: leżą w `skills/`,
  ale `install.sh` ich nie linkuje (zob. [Wyłączone skille](#wyłączone-skille)).
- **Współdzielony Ralph** — jedna autonomiczna pętla implementacyjna dla wszystkich repo,
  niezależnie od stacku. Specyfika repo (jak testować, kiedy „gotowe") siedzi w sekcji
  `## Ralph` w `CLAUDE.md` repo, a nie w kopii skryptu. Ralph działa wyłącznie w Claude.
- **Skille Ralpha** — `ralph-konfiguracja` (setup repo), `to-issues-ralph` (triage zadań) i `/odbior <nr>`
  (odbiór epicu w artefakcie claude.ai).

Design: `CONTEXT.md` (słownik), `docs/adr/0001` (warstwowy fallback `/podsumuj`),
`docs/adr/0002` (współdzielony Ralph: prompty agnostyczne + config w CLAUDE.md),
`docs/adr/0020` (Codex poza Ralphem: pętla tylko dla Claude, Codex to runtime skilli).

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

- skille Claude → `~/.claude/skills`: `ralph-konfiguracja`, `to-issues-ralph`, `odbior` (tylko Claude)
- skille Codex → `${CODEX_HOME:-~/.codex}/skills`: te same nazwy, wołane w Codexie jako `$...`
- launchery → `~/.local/bin`: `ralph-once`, `ralph-once-local`, `ralph-epic`

Repo-local plugin Codex (`.agents/plugins/marketplace.json` + `.agents/plugins/plugins/ai-coding`)
jest częścią repo, instalator go nie tworzy — tylko wypisuje dwie komendy `codex plugin`, którymi
go włączasz.

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

Repo bez Ralpha potrzebuje tylko sekcji `## Ralph` w swoim `CLAUDE.md` — inaczej
strażnik jest fail-closed i `ralph-once` od razu halt-uje. Sekcję pisze
`/ralph-konfiguracja` (w Claude):

```bash
cd ~/projects/repo-laravel            # repo nr 1 — stack PHP/Laravel, jeszcze bez Ralpha
# w sesji Claude: /ralph-konfiguracja
#   → wykrywa stack (composer test / pint), pisze ## Ralph do CLAUDE.md, tworzy labelki
ralph-once                            # pętla rusza, bo ## Ralph już jest

cd ~/projects/repo-expo               # repo nr 2 — stack RN/Expo, jeszcze bez Ralpha
# w sesji Claude: /ralph-konfiguracja
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
(away-from-keyboard), z terminala. Ralph uruchamia wyłącznie Claude (ADR 0020); Codex jest
tylko runtime'em skilli. Argument `claude` można pominąć:

```bash
ralph-once 224          # Claude jest domyślny
ralph-once claude 224   # to samo, jawnie
ralph-once 12           # 12 to epic ([PRD]) → pierwsze wolne z jego otwartych sub-issues
ralph-once              # selektor + worker
ralph-once-local        # lokalne issues/*.md
ralph-once 224 --force-model=opus  # Opus z effort high zamiast modelu z complexity:*
```

Dwa flavoury, jeden zestaw promptów:

- **`ralph-once`** — zadania w GitHub Issues (label `ready-for-agent`). Selektor (Haiku)
  wybiera następne issue, a model worker'a zależy od labelki `complexity:*`.
- **`ralph-once-local`** — zadania w plikach `issues/*.md`, bez selektora GitHub.

**`--force-model=sonnet|opus`** (wszystkie trzy komendy) pomija etykietę
`complexity:*`: każde issue jedzie na wskazanym modelu z effort high, także sesja HITL. Flaga może
stać w dowolnym miejscu. Strażnik i selektor zostają na Haiku.

**Bramka po zamkniętym issue** (ADR 0018). Po każdym runie, który zamknął issue (AFK, sesja HITL,
wznowiony worker), `ralph-once` sam uruchamia komendę z linii `ralph-gate:` w katalogu głównym repo,
zanim uzna issue za zrobione. Kolejność: bramka → przy zielonej i `complexity:heavy` przegląd heavy
→ werdykt runu (epic nie dostaje już `needs-human-test` po ostatnim sub-issue — robi to weryfikacja
epica, niżej). Na ekranie: start, czas i wynik; pełne wyjście
w `.git/ralph-logs/<czas>-gate-<nr>.log`. Run, który zostawił issue otwarte, bramki nie uruchamia.
- czerwona pierwszy raz — issue wraca otwarte z `ready-for-agent` i komentarzem (marker bramki,
  koniec wyjścia, ścieżka logu), epic nie dostaje `needs-human-test`, run kończy się kodem 7
  i `ralph-epic` jedzie dalej;
- czerwona drugi raz na tym samym issue — issue wraca otwarte, a `ralph-epic` staje (kod 3,
  potrzebny człowiek);
- **niestabilny test:** czerwona bramka jest powtarzana raz (log powtórzenia obok logu czerwonego,
  z sufiksem `-powtorzenie`). Czerwona, a potem zielona to niestabilny test: run zaliczony jak po
  zielonej bramce, a pętla zakłada `[ISSUE] Niestabilny test: <nazwa>` z `complexity:normal`
  i `ready-for-agent`, z końcem wyjścia czerwonego przebiegu i ścieżką jego logu. `<nazwa>` to
  identyfikator testu wyczytany z wyjścia (TAP `not ok`, linia `✗`, `--- FAIL:`, `FAIL:`), inaczej
  opis ogólny. Rodzicem jest epic issue, gdy plik testu widoczny w czerwonym wyjściu zmienił się
  w commitach epicu (`<baza>..epic/<nr>`); inaczej issue powstaje bez rodzica. Czerwona dwa razy
  to czerwona, jak wyżej. Worker może powtórzyć pętlę testów raz, nigdy do zielonego, i opisuje
  każde powtórzenie w raporcie;
- brak linii `ralph-gate:` w chwili runu — błąd (kod 1), nigdy cicha zielona. Wznowiony przegląd
  heavy nie uruchamia bramki ponownie (była zielona, zanim przegląd ruszył).

**`complexity:heavy`** nie oznacza już silniejszego implementera (ADR 0016). Issue implementuje
model `normal` z effort high (Claude: Sonnet). Wyrocznią jest sekcja `## Przypadki do
przetestowania`, którą `to-issues-ralph` pisze przy rozbiciu: worker pisze jeden test na każdy
przypadek. Gdy przebieg AFK zamknie takie issue, `ralph-once` uruchamia **przegląd heavy**:
silniejszy model (Opus) czyta diff, może uruchamiać
testy, nie zmienia kodu i nie dotyka GitHuba. Ocenia tylko, czy testy łapią błędną
implementację przypadków z listy i czy diff nie otwiera przypadku spoza niej. Werdykt:
- `REVIEW: OK` — issue zostaje zamknięte;
- pierwszy `REVIEW: FAIL` — issue wraca otwarte z komentarzem przeglądu, worker dostaje go przy
  poprawce, run kończy się kodem 7 i `ralph-epic` jedzie dalej;
- drugi `REVIEW: FAIL` — issue wraca otwarte, `ralph-epic` staje jak przy porażce AFK;
- brak werdyktu — issue wraca otwarte, run kończy się błędem.

Przegląd zależy tylko od etykiety: działa też z `--force-model`, nie działa po sesji HITL. Po
workerze i po przeglądzie run wypisuje koszt (`Koszt workera: $…`).

Przed wyborem zadania i workerem oba przechodzą przez **strażnika** (`ralph/preflight.sh`,
fail-closed; w `ralph-once` po locku i bramce `needs-human-test`): repo musi mieć gotową sekcję
`## Ralph` w `CLAUDE.md` (`AGENTS.md` jest ignorowany), inaczej pętla halt-uje z instrukcją
konfiguracji `/ralph-konfiguracja`.

Claude jedzie **bez nadzoru**: `claude -p` w **auto mode** (`--permission-mode auto`) ze
strumieniowym wyjściem JSON. Worker kończy się sam po domknięciu issue.
Celem jest AFK bez `dangerously-bypass-*`.

**Co widać na ekranie.** Strumień z workera przechodzi przez renderer (`lib.sh`):

- `› …` — **narracja**: tekst, który model pisze między krokami („Czytam routing…”, „Bramka
  zielona, commituję”). To główna treść ekranu.
- `  ▸ Bash: …`, `  ▸ Edit: …` — kroki, przyciemnione, jedna linia ucięta do szerokości
  terminala (`…`). Pełna komenda jest w zapisie runu.
- `  ✗ …` (czerwone) — krok odrzucony przez CLI (np. zablokowany `sleep`, brak narzędzia).
  Komenda zakończona błędem często nie jest widoczna
  jako błąd, bo model dokleja `| tail` i kod wyjścia jest z `tail` — o wyniku bramki mówi narracja
  i werdykt iteracji.
- Praca w tle (tylko Claude): `⧗` komenda przeniesiona w tle (przekroczony limit czasu Basha)
  albo uruchomiona w tle, `… Czekam na zadania w tle (N)` gdy tura skończyła się przed nimi,
  `↻` gdy zadanie się skończyło i CLI obudziło workera. Nikt tu nie odpytuje: `claude -p` nie
  kończy się, dopóki działa zadanie w tle, i sam wznawia model po jego zakończeniu.
- `⚠ Limit użycia blisko` (pomarańczowe) i `✗ Limit użycia wyczerpany` (czerwone).
- Na końcu `── Raport workera ──` (u przeglądu heavy: `── Raport przeglądu ──`) z podsumowaniem
  modelu, wypisany raz. Przy pracy w tle
  `claude -p` daje kilka wyników (jeden na turę, także odpowiedź na wygasły monitor); raportem
  jest ostatnia tura, w której worker coś robił. Sesja przerwana przez API (np. limit sesji) to
  czerwone `── Worker przerwany ──`.

Po runie skrypt wypisuje werdykt: zielone `✓ Issue #N zamknięte.`, czerwone `✗ … nie zostało
domknięte`, pomarańczowe `⚠`, gdy issue czeka na człowieka (odkryty HITL, nierozwiązana sesja
HITL). Tak samo kolorowane są komunikaty skryptów: czerwone błędy i odmowy, pomarańczowe stopy
czekające na Twoją decyzję (strażnik `✋`, bramka `needs-human-test`, brak wolnych zadań, limit
iteracji, limit użycia `⏸`), zielone sukcesy (epic do odbioru). Kolory są tylko na terminalu; `NO_COLOR` je
wyłącza, a w przekierowaniu do pliku ich nie ma.

**Sesja HITL.** Tryb workera wynika z issue, nie z komendy. Issue z labelką `ready-for-agent`
idzie bez nadzoru (jak wyżej); issue bez niej to HITL i `ralph-once <nr>` otwiera dla niego
sesję **interaktywną** (`claude --permission-mode auto`) z osobnym promptem `ralph/prompt-hitl.md`. Worker zaczyna od tego, jaka decyzja
lub czynność jest potrzebna od Ciebie, z rekomendacją; po Twojej odpowiedzi implementuje i domyka
issue tymi samymi regułami co przebieg AFK (w tym odchylenia w epicu). `ralph-once` bez numeru
nadal bierze wyłącznie AFK.

**Odkryty HITL i oddanie issue pętli.** Jeśli worker AFK w sanity checku stwierdzi, że issue
wymaga decyzji albo czynności człowieka, zdejmuje z niego `ready-for-agent`, komentuje, czego
dokładnie trzeba (z rekomendacją), i kończy run. Issue nie wraca do pętli samo: gdy sprawa jest
rozstrzygnięta, oddajesz je pętli, przywracając labelkę
(`gh issue edit <nr> --add-label ready-for-agent`).

**Logi.** Wszystko ląduje w `.git/ralph-logs/`. Katalog powstaje przy
pierwszym runie i leży poza drzewem roboczym, więc nie zmienia `git status`. Dwa rodzaje plików:

- **Log przebiegu** — `<data>-<godzina>-epic[-<nr>].log` (`ralph-epic`), `…-once[-<nr>].log`
  (`ralph-once`), `…-local-run.log` (`ralph-once-local`). Wszystko, co było na ekranie (decyzje
  strażnika i selektora, gałąź, narracja i kroki workera, werdykty, komunikaty stopu), bez kolorów, z linią startu
  (komenda, katalog, gałąź) i końca (kod wyjścia). Jeden plik na wywołanie: `ralph-once`
  uruchomiony przez `ralph-epic` pisze do logu epicu. Ścieżkę skrypt wypisuje na końcu
  (`Log przebiegu: …`). Sesja HITL idzie na terminal i do logu nie trafia.
- **Zapis runu** — `<data>-<godzina>-issue-<nr>.jsonl` (dla `ralph-once-local` `…-local.jsonl`):
  pełny strumień JSON jednego workera. Jego ścieżka jest w logu przebiegu.

Gdy coś się popsuło, w innej sesji wystarczy „zobacz logi w `.git/ralph-logs/`”: log przebiegu
mówi, co zdecydował skrypt i na czym stanął, zapis runu — co dokładnie robił worker. Na końcu
runu skrypt wypisuje też `claude --resume <id>` — tą komendą wchodzisz
do sesji workera, żeby zobaczyć, co zrobił, albo go dopytać. Ostrzeżenie o brudnym drzewie po runie działa jak wcześniej.

### Lock worktree

Ralph zakłada lock per worktree, nie per issue. Jeśli lock istnieje i PID żyje, interaktywny run
pyta, czy przerwać, czy zakończyć tamten proces; non-interactive zawsze przerywa. Jeśli PID nie
żyje, interaktywny run pyta o usunięcie stale locka, a non-interactive usuwa go i kontynuuje.
Równoległe przebiegi rób przez osobne worktree/branche.

### Kontrakt `## Ralph` (w `CLAUDE.md` repo)

Prompty są stack-agnostyczne — całą specyfikę repo delegują do sekcji `## Ralph`:

- **feedback loops** — konkretne komendy do uruchomienia przed commitem (np. `composer test`
  / `npm test`); worker używa dokładnie ich, nie wymyśla własnych.
- **done-criteria** — kiedy zadanie jest skończone; czy część pracy wymaga weryfikacji
  człowieka (UI/urządzenie → `needs-human-test`).
- **linia bramki** (wymagana) — jedna linia o stałej składni `ralph-gate: <komenda>`, osobno w swojej
  linii: jedna komenda powłoki uruchamiająca całą bramkę (pętle testów połączone `&&`, więc kończy się
  kodem ≠ 0, gdy którakolwiek pada). Strażnik sprawdza jej obecność bez modelu; bez niej Ralph staje
  z odesłaniem do `/ralph-konfiguracja`, który dopisuje linię także do istniejącej sekcji.
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
`[ISSUE] Poprawka: …`); obie sekcje odsyłają do `/odbior`. Linię gałęzi per epic skill wpisuje tylko dla repo z osobną gałęzią
produkcyjną (np. `main` = produkcja, `dev` = praca).

Sekcję pisze `/ralph-konfiguracja` — nie pisz jej ręcznie.

### Przepływ

Jednostką odbioru jest **epic** (rodzic `[PRD]` z natywnymi sub-issues GitHuba), a nie pojedyncze
issue — szczegóły i uzasadnienie w `docs/adr/0012`. Każda praca jest epicem, także jednolinijkowa
zmiana (epic z jednym sub-issue). Terminologia: `CONTEXT.md` (**Epic**, **Odbiór**).

1. **`/ralph-konfiguracja`** — raz na repo. Wykrywa stack, pisze
   `## Ralph` do `CLAUDE.md`, tworzy labelki pętli na GitHubie. Proponuje też (niczego sam nie instaluje) Larastana w repo PHP
   i testy zrzutów ekranu Playwrighta w projekcie z interfejsem webowym — jeśli repo nie ma
   jeszcze takiego narzędzia; po zgodzie zakłada to jako epic w repo aplikacji.
2. **Grill → `/to-issues-ralph` → `/clear` → `/to-issues-ralph <nr>`.**
   `/to-issues-ralph` bez argumentu uzupełnia PRD o ustalenia z grilla, których w nim brakuje
   (bez pytań; to, co jest już w ADR/`CONTEXT.md`, tylko wskazuje), publikuje epic (`[PRD]` ze
   scenariuszem `## Jak odebrać`, label `ready-for-agent`) i kończy, podając numer epica
   i następną komendę. Rozbicia nie robi. Po `/clear` `/to-issues-ralph <nr>` robi samo rozbicie
   w świeżej sesji (PRD z treści epica): sub-issues (vertical slices) z natywnymi relacjami
   „blocked by” i triage `complexity:*`; sub-issue `heavy` dostaje listę przypadków do
   przetestowania. Sub-issues nie mają sekcji ręcznej — scenariusz jest jeden, w epicu.
   Wywołanie z numerem odmawia, gdy to nie `[PRD]` albo epic ma już sub-issues.
   Potem zostaje tylko `ralph-epic <nr>`.
3. **`ralph-once`** (albo `ralph-once-local`) w pętli z terminala — implementacja AFK, jedno
   sub-issue na run.
4. **Weryfikacja epica** — po zamknięciu ostatniego sub-issue pętla sama uruchamia bramkę na całym epicu (patrz niżej).
5. **Odbiór** — pętla staje raz na epic, gdy weryfikacja oznaczy go `needs-human-test`.

**Sub-issues i gate.** Sub-issue epicu worker zamyka sam po zielonym gate (doc-sync w tym samym
commicie), bez względu na done-criteria o weryfikacji ręcznej — ta część przechodzi na odbiór epicu.
Odchylenia od planu idą komentarzem do epicu (brak odchyleń = brak komentarza). Epica do odbioru
nie oznacza już worker ani samo zamknięcie ostatniego sub-issue — robi to **weryfikacja epica**.

**Weryfikacja epica** (ADR 0018, warstwa 2). Epic jest
w jednym z czterech stanów (czysta funkcja `ralph_epic_state`): *niezaplanowany* (bez sub-issues —
nie jest weryfikowany ani oznaczany), *w toku* (są otwarte sub-issues), *do weryfikacji* (≥1
sub-issue, wszystkie zamknięte, bez `needs-human-test`) i *do odbioru* (ma `needs-human-test` —
także epic oznaczony przed tą zmianą, bez markerów; nie jest weryfikowany ponownie). Epic *do
weryfikacji* jest pracą: `ralph-epic` (z numerem i bez; bez numeru bierze taki epic przed epikami z
otwartymi sub-issues) oraz `ralph-once <epic>` uruchamiają weryfikację, a `ralph-epic` robi to w tym
samym przebiegu, w iteracji po zamknięciu ostatniego sub-issue. Weryfikacja liczy się jako iteracja.
Zwykłe `ralph-once` bez numeru epicu nie weryfikuje.

Przebieg: bramka (`ralph-gate:`, na gałęzi `epic/<nr>`, gdy repo ma `ralph-base-branch`; log w
`.git/ralph-logs/<czas>-weryfikacja-<nr>.log`) → dowody → **weryfikator** → komentarz-marker rundy
→ decyzja. Numer rundy to liczba markerów rund weryfikacji od ostatniego markera rundy odbioru
(zostawia go `/odbior`; tu tylko jest rozpoznawany) plus jeden.

*Dowody* (do pliku `…-weryfikacja-<nr>-dowody.md` obok logu i do promptu weryfikatora) z zakresu
commitów epicu (`<baza>...epic/<nr>`): usunięte pliki testów, usunięte testy, dopisane
`skip`/`todo`/`markTestSkipped`, spadek liczby asercji w pliku i zmienione wzorce zrzutów ekranu
(obrazy w katalogach `snapshots`, `screenshots`, `baselines`), a gdy repo ma `vendor/bin/pest` —
wynik `pest --mutate` dla klas zmienionych w epicu. Brak Pest albo błąd mutacji to brak tej części
(jedna linia w logu), nie porażka.

*Weryfikator* (`ralph/prompt-verify.md`): Opus z effortem high, bez narzędzi edycji, uruchamiany przez
wznawianie po limicie z fazą śladu `verify`. Dostaje PRD i `## Jak odebrać` z epicu, komentarze
odchyleń, zakres commitów, dowody, wynik bramki i sekcję `## Ralph`. Odpala czterech subagentów
tylko do odczytu: bezpieczeństwo, zgodność z PRD i `## Jak odebrać`, UX, architektura (wzorce repo,
ADR-y, `CONTEXT.md`); każdą zmianę testów z dowodów musi uzasadnić PRD-em. Nie zmienia kodu i nie
dotyka GitHuba — zwraca raport: tekst dla człowieka i na końcu blok `json` ze znaleziskami
(`blocking` / `proposal` / `refactor`, z uzasadnieniem; dla blokujących tytuł poprawki, złożoność
według rubryki `to-issues-ralph`, kryteria akceptacji, a dla `heavy` lista przypadków) oraz
pozycjami listy odbioru (`not-proven`, `before-after`). Blokuje: bezpieczeństwo, odejście od PRD,
coś, co nie działa, konkretne znalezisko architektury, zmieniony wzorzec zrzutu niezapowiedziany w
PRD. Ogólne opinie odpadają. Koszt weryfikacji (`total_cost_usd`) jest w wyjściu runu i w logu.
Raport bez bloku `json` albo z błędnymi polami to błąd runu (kod 1): nic nie jest zapisywane, epic
zostaje nieoznaczony. Parsowanie (`ralph_report_parse`) i decyzja (`ralph_verify_decision`) to czyste
funkcje.

Decyzja (skrypt, nie model):
- nic nie blokuje (bramka zielona, brak blokujących) → `needs-human-test` i komentarz z listą
  odbioru; kod wyjścia 9;
- runda 1 z czerwoną bramką i/lub blokującymi → sub-issues `[ISSUE] Poprawka: …` pod epicem
  (`ready-for-agent`, `complexity:*` z raportu, dla `heavy` sekcja `## Przypadki do
  przetestowania`; czerwona bramka dostaje własną „Poprawkę: czerwona bramka”), kod 7 —
  `ralph-epic` jedzie dalej, robi poprawki i weryfikuje drugi raz;
- runda 2 (i późniejsze) z czymś nadal blokującym → `needs-human-test`, nierozwiązane na początku
  listy odbioru, żadnych nowych „Poprawek”;
- w każdej rundzie znaleziska `refactor` → osobne `[ISSUE] Refaktor: …` (`ready-for-agent`, bez
  rodzica, nie blokuje; issue o tym samym tytule nie jest zakładane drugi raz), a `proposal` trafia
  tylko do listy odbioru.

*Lista odbioru* (komentarz epicu): nierozwiązane znaleziska (i czerwona bramka) najpierw, kroki
`## Jak odebrać`, czego bramka nie udowadnia, „przed / po” dla zmian wyglądu zapowiedzianych w PRD,
propozycje do decyzji, komenda `cd <worktree> && claude "/odbior <nr>"` (ta sama kończy wyjście
`ralph-epic`) i ID sesji weryfikatora (`claude --resume <id>`), żeby można go było dopytać.

Limit użycia w trakcie weryfikatora działa jak przy workerze (ADR 0017): ślad z fazą `verify`
(plus wynik bramki i numer rundy), czekanie na reset albo kod 8, a następne `ralph-once <epic>`
wznawia tę samą sesję bez ponownej bramki — ślad jest nieważny, gdy epic jest zamknięty albo ma już
`needs-human-test`. Każdy nieudany zapis na GitHubie (marker, etykieta, sub-issue) to błąd (kod 1),
nie ciche pominięcie — bez markera weryfikacja kręciłaby się w kółko.

**`/odbior <nr>`** (Opus, tylko Claude) czyta najnowszą listę odbioru z komentarza epicu i publikuje
artefakt claude.ai z `db` i `assets`: każdy krok z opisem, przyciski OK / do poprawki, komentarz,
wklejenie zrzutu, uwagi ogólne; stan jest trwały między sesjami przeglądarki, per runda i krok.
Jeden artefakt na epic — jego URL leży w komentarzu epicu (marker `ralph-odbior-artefakt`) i jest
używany ponownie; ponowne `/odbior` dla tej samej rundy niczego nie nadpisuje, nowa runda dodaje
sekcję nad starymi. Strona to szablon `skills/odbior/template.html`, treść kroków trafia do bazy
artefaktu.

Przepływ odbioru: lista odbioru (komentarz epicu) → `/odbior <nr>` → artefakt, który przechodzisz
(można w kawałkach, przez kilka dni) → `/odbior <nr>` jeszcze raz. Drugie uruchomienie, gdy
artefakt bieżącej rundy ma już werdykty, czyta je z bazy (werdykty, komentarze, zrzuty, uwagi
ogólne) i działa:

- **drobiazg** — poprawka w tej sesji, w worktree gałęzi epicu; przed każdym commitem bramka
  (`ralph-gate:`), czerwona = bez commita, sprawa idzie jako „Poprawka”;
- **większa sprawa** — sub-issue `[ISSUE] Poprawka: …` (`ready-for-agent`, złożoność wg rubryki
  `to-issues-ralph`, dla `heavy` lista przypadków), marker rundy odbioru
  (`<!-- ralph-odbior: runda -->`) w epicu i zdjęcie `needs-human-test`; pętla robi poprawki i epic
  wraca do weryfikacji (numer rundy liczy się od tego markera);
- **same „OK” i brak uwag** — procedura „Zamknięcie epicu” z `## Ralph` repo;
- **„zróbmy to inaczej”** — propozycja osobnego grilla zamiast poprawki.

Niekompletny odbiór (kroki bez werdyktu): skill wylicza, co zostało, i niczego nie zamyka.

**Odbiór epicu.** `needs-human-test` na epicu to bezpiecznik: dopóki jest, pętla nie zaczyna nowej
pracy. Przechodzisz scenariusz z `## Jak odebrać` i:

- **„zamykaj" / „potwierdzam"** — Claude w sesji robi zamknięcie: doc-sync, merge gałęzi epicu do
  bazy (jeśli jest), usunięcie gałęzi, zamknięcie epicu;
- **uwagi** — drobiazg Claude poprawia od razu w sesji; rzecz większa staje się nowym sub-issue
  `[ISSUE] Poprawka: …` pod epicem, epic traci label, a pętla ją dokańcza.

**Wybór pracy.** W trybie pętli, jeśli istnieje **rozpoczęty epic** (co najmniej jedno zamknięte
sub-issue) z otwartymi sub-issues, selektor dostaje tylko sub-issues najstarszego takiego epicu
(filtr w `lib.sh`, czysta funkcja) — pętla dokańcza epic, zanim weźmie następny. `ralph-once <nr epicu>`
pracuje nad sub-issue wskazanego epicu; epic bez otwartych sub-issues jest weryfikowany (gdy wszystkie
są zamknięte i nie ma `needs-human-test`), a w pozostałych stanach daje komunikat i wyjście bez
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
| 1 | błąd lub odmowa: złe argumenty, brak issue, zajęty lock, strażnik, brudne drzewo, konflikt scalania, przegląd heavy bez werdyktu, brak linii `ralph-gate:` |
| 2 | nic do zrobienia: bramka `needs-human-test`, epic w odbiorze lub niezaplanowany, brak lub zablokowani kandydaci, `NO_TASK` |
| 3 | run AFK zostawił issue otwarte i nadal z `ready-for-agent` (porażka, praca niedokończona; także drugi odrzut przeglądu heavy albo druga czerwona bramka) |
| 4 | run AFK zostawił issue otwarte bez `ready-for-agent` (odkryty HITL) |
| 5 | sesja HITL skończona, issue otwarte i bez `ready-for-agent` (nierozwiązane) |
| 6 | sesja HITL skończona, issue otwarte z przywróconym `ready-for-agent` (wraca do AFK) |
| 7 | przegląd heavy odrzucił issue albo bramka była czerwona pierwszy raz: otwarte ponownie z uwagami, poprawka w następnym runie; także weryfikacja epica z czerwoną bramką albo blokującymi znaleziskami w rundzie 1 (założone „Poprawki”) |
| 8 | limit użycia przerwał run, a reset jest dalej niż 6 h; ślad zostaje do wznowienia (niżej) |
| 9 | weryfikacja epica oddała epic do odbioru (`needs-human-test` i lista odbioru ustawione); `ralph-epic` staje jak przy epicu gotowym do odbioru |

**Wznowienie po limicie użycia** (tylko Claude, ADR 0017). Gdy worker, przegląd heavy albo weryfikator epicu trafi
na wyczerpany limit konta (np. pięciogodzinne okno w nocy), to nie jest porażka. Ralph zapisuje
ślad w `.git/ralph-limit` (issue, faza, sesja, gałąź, godzina resetu), a jeśli reset wypada
w ciągu 6 h, wysyła powiadomienie „czekam do HH:MM”, śpi według zegara ściennego i wznawia tę
samą sesję (`claude -p --resume <id>`) z poleceniem kontynuacji — w tej samej iteracji
`ralph-epic`. Strażnik i selektor po prostu czekają i powtarzają wywołanie. Gdy proces zginie
w trakcie czekania (laptop wyłączony), rano uruchamiasz to samo co wieczorem (`ralph-epic 45`,
`ralph-once 52` albo `ralph-once`): ślad jest ważny, gdy issue jest w stanie z chwili przerwania
(worker: otwarte z `ready-for-agent`; przegląd: zamknięte; weryfikator: epic otwarty i bez `needs-human-test`) i bieżąca gałąź jest ta sama. Wtedy
brudne drzewo nie blokuje, a Ralph wznawia sesję przed bramkami i strażnikiem. Nieważny ślad
znika z jedną linią na ekranie; ślad innego issue zostaje nietknięty, a ślad po wycofanym Codeksie jest usuwany. Gdy Claude
nie podejmie sesji, run kończy się błędem z komunikatem, a ślad zostaje (usuń go, żeby wrócić do
zwykłych reguł).

#### `ralph-epic` — epic od startu do odbioru

`ralph-epic [claude] [nr]` powtarza `ralph-once <epic>` (jedno sub-issue na run, świeży kontekst,
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
| epic w odbiorze (kod 9 po weryfikacji, albo epic już z `needs-human-test`) | „Epic #N gotowy do odbioru” i komenda `cd <worktree> && claude "/odbior N"` | przechodzisz `## Jak odebrać`, mówisz „zamykaj” albo zgłaszasz uwagi |
| AFK nie domknęło issue (3) | numer issue i wskazanie komentarza workera | czytasz komentarz i logi w `.git/ralph-logs/`, poprawiasz przyczynę (albo issue) i uruchamiasz ponownie; pętla nie pomija issue |
| HITL nierozwiązane (5) | numer issue | rozstrzygasz: domykasz albo przywracasz `ready-for-agent`, uruchamiasz ponownie |
| nic do zrobienia (2) | lista otwartych sub-issues (HITL oznaczone) | odblokuj je, dodaj decyzję lub `ready-for-agent`, uruchom ponownie |
| błąd lub odmowa (1) | przyczyna z komunikatów `ralph-once` | naprawiasz (brudne drzewo, konflikt scalania, lock, strażnik) i uruchamiasz ponownie |
| limit iteracji (2) | liczba iteracji i lista otwartych | sprawdzasz, czemu epic nie schodzi, i uruchamiasz ponownie |
| limit użycia (8) | issue, godzina resetu i komenda do wklejenia (ta, którą uruchomiono przebieg, np. `ralph-epic 42`) | po resecie wklejasz tę komendę — wznowi przerwaną sesję; limit z resetem w ciągu 6 h pętla przeczekuje sama |

Sesja HITL rozwiązana (issue domknięte albo z przywróconym `ready-for-agent`) i odkryty HITL
(kod 4) nie zatrzymują pętli — idzie następna iteracja. Limit iteracji to dwukrotność liczby
otwartych sub-issues na starcie (zapas na sesję HITL po odkryciu; dla epicu *do weryfikacji* 3:
weryfikacja, „Poprawka”, weryfikacja); chroni tylko przed pętlą bez końca. Kod: `ralph/epic.sh`; testy: `ralph/test/epic.test.sh` (atrapa `once.sh`, fałszywe `gh`).

**Blokery rozstrzyga skrypt.** Bloker to natywna relacja GitHuba „blocked by” (zakłada ją
`to-issues-ralph`; ręcznie: „Mark as blocked by” w issue). Sekcja „Blocked by” w treści to tylko
opis — skrypt jej nie czyta. Przed selektorem (w pętli i w trybie epicu) `lib.sh` pobiera
kandydatów przez REST API i odrzuca każdego z otwartym blokerem (`issue_dependencies_summary`,
czysta funkcja `ralph_filter_unblocked`). Gdy GitHub nie odpowie, run kończy się błędem — bez
listy blokerów nic nie jest wybierane. Selektor dostaje tylko wolne issues i decyduje wyłącznie
o kolejności; gdy po filtrze nic nie zostaje, pętla wypisuje każdego kandydata z jego otwartymi
blokerami (`#3 ← #7`) i nie wywołuje selektora (`ralph-epic` robi to samo w komunikacie stopu).
Selektora nie ma też przy jednym wolnym kandydacie ani w trybie epicu (tam decyduje numer).

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
