# Autonomiczny epic: worker bez nadzoru dla AFK, sesja HITL dla człowieka

Rozwija ADR 0012 (epic jako jednostka odbioru) i zmienia ADR 0007 (jak uruchamiany jest worker).

**Kontekst.** ADR 0012 przesunął odbiór z „po każdym issue" na „po każdym epicu", ale pętla nadal
wymagała człowieka co run: worker Claude startował jako interaktywna sesja, która po domknięciu
issue czekała na kolejną wiadomość, aż ktoś wpisał `/exit`. Epic z sześcioma sub-issues to sześć
takich przystanków, więc „puść epic na noc" było niewykonalne. Do tego trzy mechanizmy, od których
zależy zatrzymanie pętli, leżały w modelu: selektor (Haiku bez narzędzi) sam oceniał „Blocked by"
i w teście zwrócił `NO_TASK` przy wolnym issue; worker sam oznaczał epic do odbioru, więc epic,
którego ostatnie sub-issue zamknął człowiek, nigdy nie trafiał do odbioru; worker, który w trakcie
odkrył potrzebę decyzji, zostawiał issue z `ready-for-agent`, więc następny run wybrałby je znowu.

**Decyzja.** Nowa komenda `ralph-epic [nr]` realizuje epic od startu do odbioru: powtarza run
w trybie epicu (jedno sub-issue na run, świeży kontekst i model z `complexity` dla każdego).

- **Tryb workera wynika z issue, nie z komendy.** Issue AFK idzie przez `claude -p` (auto mode
  działa tam tak samo; sprawdzone) i kończy się samo; postęp wypisywany jest na bieżąco, pełny
  zapis ląduje w `.git/ralph-logs/`, a na końcu `claude --resume <id>` do dopytania. Issue HITL
  otwiera **sesję HITL** — interaktywną, bo człowiek jest z definicji obecny; osobny prompt każe
  zacząć od tego, czego potrzeba, z rekomendacją. Dotyczy to także `ralph-once`.
- **Kolejność w epicu:** najpierw wszystkie AFK, które nie są zablokowane; dopiero gdy nie zostało
  żadne, sesja HITL dla niezablokowanego HITL. Po sesji: HITL zamknięte albo z przywróconym
  `ready-for-agent` → dalej AFK; inaczej stop, żeby nie otwierać tej samej sesji w kółko.
- **Stop całego `ralph-epic`**, gdy: epic trafił do odbioru; worker AFK nie domknął issue (bramka
  czerwona / praca niedokończona — na drzewie mogą być śmieci, więc bez pomijania i jechania
  dalej); nie ma nic AFK ani HITL do zrobienia; brudne drzewo lub konflikt scalania bazy; limit
  iteracji (liczba otwartych sub-issues AFK na starcie). Przy stopie i starcie sesji HITL —
  powiadomienie systemowe, gdzie jest dostępne.
- **Bez numeru** `ralph-epic` bierze epic, który wziąłby selektor (rozpoczęty, potem najniższy
  numer), i respektuje bramkę `needs-human-test`; z numerem ją pomija — jak `ralph-once`.
- **Co da się rozstrzygnąć deterministycznie, rozstrzyga skrypt, nie model.** Skrypt odrzuca
  issue z otwartym blokerem przed selektorem (selektorowi zostaje kolejność); skrypt nakłada
  `needs-human-test` na epic, gdy nie ma otwartych sub-issues — niezależnie od tego, kto zamknął
  ostatnie. Worker zostawia sobie tylko to, czego skrypt nie wie: odchylenia od planu (komentarz
  w epicu) i przerobienie odkrytego HITL (zdejmuje `ready-for-agent`, pisze, czego potrzeba).
- **Oba runtime'y.** Codex to zapas na wyczerpane okno tokenów Claude, więc musi umieć to samo
  (`codex exec` dla AFK, obecny tryb interaktywny dla HITL).
- **Nazwa „epic" wszędzie** — w tekstach, komunikatach, gałęzi `epic/<nr>` i w ADR 0012; słowo
  „epik" znika. Zmiana przed pierwszym epicem na produkcji jest darmowa, później byłaby migracją.

## Rozważane opcje

- **Jedna sesja modelu na cały epic** — odrzucone: jeden model dla wszystkich sub-issues (za drogi
  dla drobnych albo za słaby dla trudnych) i kontekst rosnący z każdym issue.
- **Stop przy pierwszym HITL** — odrzucone: jedno pytanie marnowałoby resztę nocy; zależności
  i tak pilnuje „Blocked by".
- **Po porażce AFK pominąć issue i jechać dalej** — odrzucone: porażka jest nieoczekiwana, drzewo
  może być brudne, a ta sama przyczyna zwykle wykłada kolejne issue.
- **`ralph-once` zostaje interaktywny** — odrzucone: jedno issue AFK nie potrzebuje rozmowy,
  a dwie ścieżki uruchamiania to dwie rzeczy do testowania.
- **Blokery nadal ocenia selektor** — odrzucone: fałszywe `NO_TASK` w pętli autonomicznej kończy
  pracę albo przeskakuje do HITL, a parsowanie sekcji „Blocked by" jest trywialne.
- **Tylko Claude, Codex później** — odrzucone: Codex jest zapasem właśnie na moment, w którym
  Claude'a nie ma, więc nie może zostać w tyle.

## Konsekwencje

- W trakcie runu AFK nie da się dopisać instrukcji — zostaje Ctrl+C i `--resume` po fakcie.
- Pierwszy krok z promptu workera znika („ostatnie sub-issue → oznacz epic"); prompt dostaje
  zdejmowanie `ready-for-agent` przy odkrytym HITL, a obok powstaje prompt sesji HITL.
- `once.sh` musi zwracać wynik runu kodem wyjścia (zrobione / nic do zrobienia / issue zostało
  otwarte), bo dziś prawie każde zakończenie to 0.
- `ralph-once-local` dostaje tryb `-p` przy okazji (wspólna funkcja uruchamiania workera); epiców
  i HITL tam nie ma, jak w ADR 0012.
- Do sprawdzenia przy implementacji: czy `codex exec` potrafi automatycznie zatwierdzać wyjścia
  poza sandbox tak jak interaktywne `--approve-for-me`.

## Aktualizacja (2026-09-30, odbiór)

W epicu kolejność też rozstrzyga skrypt, nie selektor: z wolnych sub-issues (po filtrze blokerów
i zasadzie „najpierw AFK”) brane jest to o najniższym numerze. Poza epikiem selektor zostaje, ale
nie jest wołany przy jednym kandydacie. Powód: przy odbiorze Haiku zwrócił `NO_TASK`, mając do
wyboru jedno wolne issue — w `ralph-epic` puszczonym bez nadzoru to stop całej pętli, a numeracja
sub-issues i tak odzwierciedla kolejność planu.
