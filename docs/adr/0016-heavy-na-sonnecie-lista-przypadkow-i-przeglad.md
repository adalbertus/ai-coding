# `heavy` na Sonnecie: lista przypadków przy rozbiciu i przegląd silniejszym modelem

Częściowo zastępuje ADR 0003: znaczenie `heavy` zostaje, zmienia się jego obsługa.

**Kontekst.** `heavy` oznacza zadanie, w którym wiarygodnie-błędna implementacja przechodzi
testy, jakie worker sam sobie napisze (autoryzacja, izolacja tenanta, daty, pieniądze,
algorytmy). Dotąd odpowiedzią był droższy model: Opus implementował takie zadanie sam, łącznie
z testami. Nikt nie sprawdzał, czy te testy cokolwiek dowodzą — ani u Opusa, ani u Sonneta
uruchamianego przez `--force-model=sonnet`, którego używamy coraz częściej. Przewaga Opusa w tej
klasie zadań to przede wszystkim umiejętność wyliczenia, *co* trzeba przetestować; tę część da
się wykonać wcześniej, raz, i zapisać.

**Decyzja.**

- **Lista przypadków przy rozbiciu.** Dla zadania `heavy` `to-issues-ralph` czyta odpowiedni kod
  i zapisuje w sub-issue sekcję `## Przypadki do przetestowania`: pary „sytuacja → oczekiwany
  wynik”. Zastępuje ona jednozdaniowe `## Complexity`. Lista powstaje zawsze — nie ma wariantu
  „nie da się spisać → Opus”. Zadania `normal` i `trivial` się nie zmieniają.
- **Worker pisze jeden nazwany test na przypadek**; przypadek nietestowalny wymienia
  w komentarzu zamykającym. Wyrocznia jest zewnętrzna, kod testu — workera.
- **Implementuje model `normal` na effort `high`** (Claude: Sonnet). Etykieta dalej mówi
  o trudności zadania, nie o modelu; zmienia się tylko mapowanie w `ralph_model_for_complexity`.
- **Przegląd `heavy`.** Po przebiegu AFK, który zamknął sub-issue `heavy`, a przed oznaczeniem
  epiku do odbioru, `once.sh` uruchamia silniejszy model (adapter runtime'u, model `heavy`).
  Dostaje issue i diff, może czytać pliki i uruchamiać testy, nie zmienia kodu i nie dotyka
  GitHuba. Ocenia wyłącznie poprawność: czy testy naprawdę pokrywają listę i czy diff nie otwiera
  przypadku spoza niej. Pierwsza linia odpowiedzi: `REVIEW: OK` albo `REVIEW: FAIL`.
- **FAIL** otwiera sub-issue ponownie z komentarzem przeglądu, który worker dostaje przy
  poprawce. Drugi FAIL zatrzymuje epik jako porażkę AFK.
- Przegląd zależy tylko od etykiety: działa też przy `--force-model`, nie działa po sesji HITL.
- **Pomiar.** `once.sh` wypisuje i loguje koszt workera i przeglądu z danych, które runtime już
  zwraca (Claude: `total_cost_usd`).

**Odrzucone.**

- **Opus implementuje `heavy` jak dotąd** — droższe, a słabość zostaje: nikt nie rozlicza
  testów z tym, co trzeba było sprawdzić.
- **Gotowy kod testów w issue** — najmocniejsza wyrocznia, ale pisany bez znajomości struktury
  repo często się nie kompiluje albo trafia w złe miejsce.
- **Kontrola tanim modelem** — Haiku sprawdzi, że test o danej nazwie istnieje, nie oceni, czy
  coś dowodzi.
- **Przegląd, który sam dopisuje testy** — wraca do implementacji silniejszym modelem i zaciera,
  kto odpowiada za wynik.
- **Przegląd stylu i architektury** — przy limicie jednej poprawki generowałby fałszywe porażki;
  od tego jest `/code-review` przy odbiorze.
- **Lista przypadków dla wszystkich zadań** — dla `normal` Sonnet daje dobre wyniki, a lista
  wydłuża issues i rozbicie bez zysku.

**Konsekwencje.** Typowe zadanie `heavy` kosztuje przebieg Sonneta na `high` plus krótki
przegląd zamiast pełnego przebiegu Opusa; oszczędność jest kilkukrotna, nie piętnastokrotna,
i ma ją potwierdzić pomiar. Przy FAIL dochodzi poprawka i drugi przegląd. Przypadki, których nie
przewidziała ani lista, ani przegląd, nadal mogą przejść — siatką pozostaje odbiór epiku. Lista
pisana przy rozbiciu może się zestarzeć, jeśli wcześniejsze sub-issues zmienią kod; opisuje
jednak zachowanie, nie pliki, więc ryzyko jest małe.
