# Eksploracja przez wyszukiwanie; sprzeczne instrukcje naprawiamy u źródła

**Kontekst.** `ralph-once` w `brewiarz` miewał ~50k tokenów zużytych, zanim napisał pierwszą
linijkę kodu — przy „smart zone" kończącej się gdzieś koło 100k oznaczało to przerywanie pracy
i `/compact`. Pomiar `/context` rozłożył to na części: podłoga zimnego startu to **19,7k**
(system prompt 4,1k + schematy narzędzi 9,2k + memory files 3,2k + opisy skilli 3,2k), z czego
~17k jest nieruszalne; `ralph-once` dokłada do promptu ~2–3k (`prompt.md`, treść issue,
`git log -n 5`). Reszta — **~27k — to był jeden `Read`**: cały `CONTEXT.md` (68 KB polskiego
tekstu ≈ 25k tokenów). Worker czytał go nie dlatego, że issue było nieostre i musiał szukać, ale
dlatego, że `CLAUDE.md` repo dosłownie mu kazał: *„`CONTEXT.md` — read before introducing a new
term"*. Ten sam wzorzec był w `CLAUDE.md` tego repo — problem jest ogólny dla rodziny Ralpha,
a nie lokalny dla `brewiarz`; `ai-coding` go nie odczuwał tylko dlatego, że jego słownik ma
131 linii zamiast 908.

**Decyzja.** Dwie zmiany, obie po stronie `ai-coding`:

- **Protokół eksploracji w `ralph/prompt.md`.** Domyślnie: „umiesz nazwać czego szukasz →
  `Grep`/`Glob`, potem `Read` z `offset`/`limit` na trafieniu". Subagent `Explore` tylko wtedy,
  gdy wzorca wyszukiwania **nie da się** ułożyć, bo potrzebny jest przegląd, a nie fakt.
  Kryterium jest **mechaniczne i ślepe na rozmiar** — model ocenia własny stan wiedzy, a nie
  szacuje wielkość pliku (czego przed `Read` nie umie) ani budżet tokenów (czego nie umie
  zmierzyć). Decyzję podejmuje worker w trakcie działania; człowieka w pętli AFK z definicji nie ma.
- **`/ralph-konfiguracja` może zaproponować zmianę sformułowania poza sekcją `## Ralph`.** Nowy
  krok wykrywa duże pliki referencyjne (>20 KB) i instrukcje wskazujące na nie czasownikiem
  „przeczytaj", po czym **proponuje** przeformułowanie na „konsultuj (grepnij po terminie)".
  Propozycja, nie cicha edycja — skill jest HITL i potwierdza każdy element.

**Rozważane opcje.**

- **Nadpisanie z `## Ralph`** (podsekcja „duże pliki referencyjne", która unieważnia instrukcję
  z innego miejsca tego samego `CLAUDE.md`) — odrzucone: buduje sprzeczność między dwiema
  instrukcjami w jednym pliku, na dodatek tę słabszą wpisując do sekcji o mniejszym autorytecie
  w oczach modelu. Modele sypią się na tym nieprzewidywalnie — raz wygra jedna, raz druga.
  Naprawa źródła usuwa sprzeczność, zamiast nią zarządzać, i działa też poza pętlą Ralpha, w
  zwykłych sesjach interaktywnych.
- **Lista dużych plików per repo w sekcji `## Ralph`** — odrzucone, choć początkowo
  rekomendowane. Duplikuje naprawioną linię w `CLAUDE.md`; nic nie wnosi, bo protokół jest ślepy
  na rozmiar i tak czy tak nie robi `Read` w ciemno; a lista rozmiarów plików to dokument, który
  gnije szybciej niż ktokolwiek go poprawia.
- **Mapa kontekstu w treści issue (`/to-issues-ralph`)** — odrzucone: triage robi się raz dla
  paczki, a issue implementuje się tygodnie później, po innych commitach — nieaktualna lista
  ścieżek jest gorsza niż jej brak, bo worker jej ufa (jest w prompcie, więc ma rangę kontraktu)
  zamiast sprawdzić grepem. Powtarzałaby też per-issue to, co `CLAUDE.md` mówi raz per-repo,
  i szłaby do okna workera bezwarunkowo. `/to-issues-ralph` bez zmian; jego istniejąca reguła
  „sharpen before you escalate" i tak ogranicza eksplorację, nie starzejąc się przy tym.
- **Subagent `Explore` jako domyślna ścieżka** (okno workera jest święte) — odrzucone: subagent
  płaci własną podłogę ~17k na zimnym starcie i oddaje parafrazę zamiast tekstu źródłowego. Przy
  wyszukaniu hasła w słowniku grep jest lepszy na wszystkich trzech osiach naraz — okno, pobór
  z limitu konta, wierność. Asymetria pomyłek też jest po stronie grepa: chybiony grep kosztuje
  jeden grep, zbędna delegacja kosztuje ~17k.

**Konsekwencje.**

- Protokół w `ralph/prompt.md` działa **natychmiast we wszystkich repo** — `once.sh` robi `cat`
  tego pliku przy każdym uruchomieniu, a `ralph-once` na PATH to symlink tutaj. Zero akcji per repo.
- Krok w `/ralph-konfiguracja` wymaga przebiegu skilla w danym repo, ale **tylko tam, gdzie
  realnie istnieje sprzeczność** — plik referencyjny >20 KB ze wskazującą nań instrukcją „read".
  Odpalanie „na wszelki wypadek" to sesja HITL na Sonnecie za zerowy zysk.
- `/ralph-konfiguracja` przestaje być skillem dotykającym wyłącznie własnej sekcji. To świadome
  poszerzenie zakresu i jedyny wyjątek od reguły „skill pisze tylko `## Ralph`" — dlatego wymaga
  potwierdzenia człowieka przy każdym przeformułowaniu.
- Prompt-cache tego nie załatwiał: obniża **koszt** ponownie wysyłanego kontekstu (~0,1× przy
  odczycie), ale nie robi nic dla **jakości** — degradacja uwagi zależy od długości okna, nie od
  tego, czy tokeny przyszły z cache'u. 25k zapchanego okna szkodzi tak samo za 10% ceny.
- Nowy termin **protokół eksploracji** w `CONTEXT.md`.
