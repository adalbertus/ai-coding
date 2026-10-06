# Blokery z natywnej relacji GitHuba, nie z tekstu treści

Uzupełnia ADR 0013: blokery nadal rozstrzyga skrypt, zmienia się ich źródło.

**Kontekst.** Filtr blokerów brał z sekcji „Blocked by” w treści issue każdą liczbę (także bez
`#`, żeby obsłużyć zapis `12`). W `kregi-dk` (epic #1) `to-issues-ralph` dopisał uzasadnienie
`heavy` na końcu treści, czyli wewnątrz tej sekcji: „heavy: … (przesuwne 7 dni, …)”. Filtr uznał
„7” za bloker, #7 czekało na #3, powstał cykl i pętla stanęła po 4 z 14 sub-issues z komunikatem,
który nie mówił, co blokuje. Przy okazji wyszedł błąd odwrotny: sekcję kończyła każda linia
zaczynająca się od `#`, więc bloker zapisany jako `#12` bez punktora przepadał.

**Decyzja.**

- **Źródłem prawdy jest natywna relacja „blocked by”.** `to-issues-ralph` zakłada ją przez API
  z listy, którą sam wpisał do „Blocked by”. Zadanie jest wolne, gdy
  `issue_dependencies_summary.blocked_by == 0` (licznik obejmuje tylko otwarte blokery). Treść
  issue nie jest czytana maszynowo; sekcja „Blocked by” z szablonu `to-issues` zostaje jako opis.
- **Fail-closed.** Błąd pobrania kandydatów kończy run błędem; brak podsumowania zależności
  odrzuca kandydata. Wcześniej błąd `gh` dawał pustą listę otwartych issues i przepuszczał
  wszystko.
- **Diagnostyka.** Gdy wszystko jest zablokowane, `ralph-once` i `ralph-epic` wypisują
  `#3 ← #7` — cykl widać wprost.
- **Worker nie sprawdza blokerów.** Skrypt robi to sekundy przed startem; podwójna kontrola
  w promptach (`prompt.md`, `prompt-hitl.md`) zniknęła.
- **Uzasadnienie `heavy`** idzie do własnej sekcji `## Complexity` przed `## Blocked by`.

**Odrzucone.**

- **Zaostrzona składnia tekstu** (tylko `#12` i linia z samą liczbą, koniec sekcji na nagłówku)
  — usuwa ten przypadek, ale zostawia klasę błędów: każdy tekst w sekcji może być źle odczytany.
- **Blok metadanych w treści** (`<!-- ralph: {"blocked_by":[…]} -->`) — deterministyczny, ale to
  wciąż tekst, który edycja może zepsuć, i dubluje mechanizm, który GitHub już ma.
- **Fallback na tekst dla starych issues** — utrwala parser; przy wdrożeniu żadne otwarte issue
  Ralpha nie miało blokerów w tekście, więc migracja nie była potrzebna.

**Konsekwencje.** Tryb lokalny (`ralph-once-local`, `issues/*.md`) nadal nie ma deterministycznych
blokerów — jak dotąd; kierunkiem byłby frontmatter `blocked_by:`. Ręcznie dodany bloker trzeba
założyć w UI GitHuba („Mark as blocked by”), wpis w treści nie wystarcza.
