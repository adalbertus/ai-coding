# Ralph jedzie w auto mode, nie w acceptEdits

**Kontekst.** `ralph-once` z założenia jedzie AFK, ale sesja regularnie wisiała na zatwierdzeniu
człowieka. Przyczyna nie była losowa: `--permission-mode acceptEdits` auto-akceptuje **wyłącznie
edycje plików**, więc każde wywołanie `Bash` spoza allowlisty użytkownika nadal pyta. Allowlista
pokrywa read-only (`gh issue view`, `grep`, `ls`), a `prompt.md` kończy każdy bieg dokładnie tym,
czego w niej nie ma: `git commit`, `gh issue close`, `gh issue edit --add-label`, `gh issue comment`
oraz komendami feedback-loopów z `## Ralph`. Stąd wrażenie „bywa różnie" — trywialne issue kończyło
się bez pytania, a każde, które dochodziło do commita, stawało.

`acceptEdits` nie był wyborem trybu „mocniejszego niż domyślny" — był najmocniejszym, jaki wtedy
istniał w cyklu shift+tab (`accept edits` / `plan`). CLI dostało od tego czasu **auto mode**, który
jest dziś **domyślnym** trybem Claude Code: klasyfikator ocenia każde wywołanie narzędzia pod kątem
ryzyka i prompt injection, niskie ryzyko puszcza sam, resztę odrzuca — zwracając odmowę **do modelu**
jako wynik narzędzia (kod `automode-blocked`), a nie prompt do człowieka. Skrypt został przypięty do
starego trybu; ta zmiana nadgania platformę. To rozróżnienie jest tu najważniejsze, bo bez niego
zmiana wygląda na poluzowanie polityki bezpieczeństwa i jest kandydatem do odkręcenia.

**Decyzja.** Oba launchery (`ralph/once.sh`, `ralph/once-local.sh`) odpalają worker'a z
`--permission-mode auto`, zaszytym na sztywno.

Na sztywno, a nie jako pole w `## Ralph` ani zmienna środowiskowa: ADR 0002 postawił granicę
„skrypty i prompty agnostyczne, specyfika repo w CLAUDE.md", a tryb uprawnień nie zależy od stacku —
jest własnością pętli, nie repo. Poza tym każdy przełącznik odtwarza dokładnie tę nieprzewidywalność,
którą zmiana ma usunąć. Ucieczka awaryjna istnieje i nic nie kosztuje: `claude --permission-mode
bypassPermissions` odpalone ręcznie.

Zweryfikowane na CLI 2.1.220, zanim decyzja zapadła: tryb `auto` nie jest blokowany planem konta;
odmowa klasyfikatora nie generuje prompta; sandbox (i jego osobny, fail-closed klasyfikator sieci)
to niezależny opt-in `sandbox.enabled`, więc `git push`, `gh` i instalacje zależności w tę ścieżkę
nie wpadają; wpisy z `permissions.allow` są w auto mode honorowane w runtime i omijają klasyfikator,
więc istniejąca allowlista nadal skraca drogę.

## Rozważane opcje

- **`bypassPermissions`** — odrzucone. Daje mocniejszą gwarancję („dokończy robotę", nie tylko
  „nie zapyta"), ale nie sprawdza **nic**, w tym prompt injection — a ralph wpuszcza do kontekstu
  treść issues z GitHuba i biega po prawdziwych repo bez sandboxa. Wymiana nie jest symetryczna:
  skutki blokady w auto mode są odwracalne (issue zostaje otwarte z komentarzem), skutki błędu przy
  `bypassPermissions` bywają nieodwracalne.
- **Zostawić `acceptEdits` i rozszerzyć allowlistę** (`--allowedTools` albo globalne settings) —
  odrzucone: komendy feedback-loopów są stack-specific, więc allowlista w agnostycznym skrypcie
  łamie ADR 0002, a w globalnych settings rozlewa uprawnienia na wszystkie sesje, nie tylko ralpha.
- **Tryb konfigurowalny per repo** — odrzucone, patrz wyżej.
- **`dontAsk`** — odrzucone: nie pyta, ale odrzuca wszystko spoza allowlisty, więc ralph nie
  zrobiłby commita. Rozwiązuje objaw (wiszenie) kosztem celu (ukończona robota).

## Konsekwencje

- **Głośna awaria zamienia się w cichą.** Zablokowane wywołanie nie zatrzymuje sesji — model idzie
  ścieżką „Not complete" z `prompt.md`, komentuje issue i kończy. Wracasz do terminala, ralph
  „skończył", a nic nie weszło. To świadoma cena za brak wiszenia.
- Najgorszy wariant tej ciszy — blokada na `git commit` — zostawia brudne drzewo, które psuje
  **następny** przebieg. Dlatego oba launchery kończą sprawdzeniem `git status --porcelain`
  i ostrzeżeniem. To ta sama zasada, którą `once.sh` egzekwuje twardym gate'em `needs-human-test`
  („never pile up unverified work"), tylko na poziomie gita zamiast issue.
- Klasyfikator dokłada wywołanie modelu do każdego tool-calla spoza allowlisty — koszt i latencja
  rosną, najbardziej przy `complexity:trivial` na Haiku, gdzie narzut jest największy względem
  samej pracy. Nie mierzone; jeśli zaboli, pierwszym krokiem jest allowlista dla narzędzi
  agnostycznych (`Edit`, `Write`), które omijają klasyfikator.
- Selektor (`once.sh`) i strażnik (`preflight.sh`) zostają bez zmian — to wywołania `claude -p`
  bez narzędzi, uprawnienia ich nie dotyczą.
