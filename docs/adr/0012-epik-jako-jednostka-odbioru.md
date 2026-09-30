# Epik jako jednostka odbioru; sub-issues zamyka gate

_Rozwinięte przez ADR 0013 (autonomiczny epic)._

Zmienia ADR 0008 (gdzie leży PRD) i ADR 0011 (gdzie leży scenariusz ręczny).

**Kontekst.** W `finanse-rsz-laravel` 153 zamknięte issues przeszły przez `needs-human-test`,
a ~90% z nich kończyło się „zamykaj, wszystko ok". Twarda bramka w `once.sh` zatrzymywała pętlę
po każdym takim issue, więc każda ręczna weryfikacja była przystankiem całej pętli. Przegląd
poprawek po ręcznych testach pokazał, że „test ręczny" robił dwie różne rzeczy: **weryfikację**
(czy działa zgodnie ze specyfikacją — do zautomatyzowania) i **odbiór** (czy to jest to, czego
chcę: układ, kolejność, kolor, „jednak inaczej"). Mniej więcej dwie trzecie wartościowych znalezisk
to był odbiór, którego żaden test nie zastąpi — da się go jednak robić rzadziej.

**Decyzja.** Jednostką odbioru jest **epik**: issue-rodzic `[PRD]` z sub-issues (natywne
sub-issues GitHuba). Każda praca jest epikiem, także jednolinijkowa zmiana (epik + jedno
sub-issue) — tak jak Epic/Issue w Jirze.

- Epik niesie PRD i jedną sekcję `## Jak odebrać`. Sub-issues nie mają sekcji ręcznej.
- Worker zamyka sub-issue po zielonym gate; odchylenia implementacji od planu dopisuje
  komentarzem w epiku (reguła odchyleń z ADR 0011 przenosi się na epik).
- Worker zamykający **ostatnie** sub-issue nakłada `needs-human-test` na epik. Bramka w
  `once.sh` zostaje bez zmian — staje się po prostu przystankiem na epik, nie na issue.
- Uwagi z odbioru: drobiazg poprawia Claude w sesji od razu; rzecz większa staje się nowym
  sub-issue „Poprawka" pod epikiem, a epik traci label, dopóki pętla jej nie zrobi.
- `ralph-once <nr epika>` pracuje nad tym epikiem (jedno sub-issue na run); selektor dokańcza
  rozpoczęty epik, zanim weźmie następny. Tak przeskakuje się na pilny epik (hotfix).
- **Gałąź per epik** jest opcją per repo w `## Ralph`: gałąź odbita od bazy, na starcie każdego
  runu pętla scala do niej bazę (konflikt = stop), po „zamykaj" merge do bazy. Dzięki temu baza
  zawiera tylko epiki odebrane i hotfix może iść na produkcję bez połowy innego epika.
- Issue bez rodzica zachowuje dotychczasowe zachowanie (`needs-human-test` per issue, scenariusz
  od zera) — kompatybilność wsteczna dla issues zakładanych poza `to-issues-ralph`.
- Wariant lokalny (`ralph-once-local`, `issues/`) jest poza zakresem i zostaje bez zmian.

PRD trafia do epiku nie dlatego, że ktoś go czyta — ADR 0008 miał rację, że nikt — tylko dlatego,
że issue-rodzic istnieje teraz z innych powodów (grupowanie, scenariusz odbioru, label), więc PRD
jedzie w nim za darmo.

## Rozważane opcje

- **Zostawić per-issue weryfikację i złagodzić tylko done-criteria repo** — odrzucone jako
  całość: zdejmuje część przystanków, ale odbiór dalej wypada po każdym issue.
- **Stop przy N oczekujących zamiast granicy epika** — odrzucone: N jest arbitralne i nie
  pokrywa się z niczym, co da się sensownie odebrać razem.
- **Przenieść tracker z GitHub Issues do plików albo Jiry/Trello** — odrzucone: darmowy GitHub
  ma sub-issues, a `gh` jest wpleciony w `once.sh`, selektor, prompt i `to-issues-ralph`.
- **Ściśle: pętla odmawia issue bez rodzica** — odrzucone na rzecz fallbacku, dla
  kompatybilności wstecznej.
- **Przełącznik „bez epików" w `ralph-konfiguracja`** — odrzucone: fallback już daje to
  zachowanie, a przełącznik to druga ścieżka w `to-issues-ralph`, której żadne repo nie używa.
- **Epiki na wspólnej gałęzi bazowej bez gałęzi per epik** — dopuszczone tylko dla repo bez
  produkcji (trunk). Tam, gdzie baza idzie na produkcję, pół epika na bazie blokowałoby hotfix.

## Konsekwencje

- Ręczna praca przesuwa się z „po każdym issue" na „po każdym epiku"; jakość scenariusza
  odbioru zależy od `to-issues-ralph`, który pisze go raz, z całym planem w kontekście.
- Filtr `[PRD]` w `once.sh` przestaje być no-opem z ADR 0008 — znów chroni rodzica przed
  wybraniem jako slice, a tryb jawny zamiast odmawiać, przyjmuje numer epika.
- Znaczenie `needs-human-test` się przesuwa: zwykle oznacza epik czekający na odbiór.
- Przy gałęziach per epik pętla przełącza gałęzie w katalogu, z którego lokalnie serwowana jest
  aplikacja; lokalna baza nie przełącza się z kodem. Świadomie bez mechanizmu — repo mają
  pobieranie bazy i seed.
- Automatyczne e2e zmniejsza zakres weryfikacji, nie odbioru; to decyzja per repo (np. Pest 4
  browser w finanse), nie część tego repo.
