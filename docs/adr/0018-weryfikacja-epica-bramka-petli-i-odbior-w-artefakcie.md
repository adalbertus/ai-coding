# Weryfikacja epica, bramka uruchamiana przez pętlę i odbiór w artefakcie

Rozwija ADR 0012 (epic jako jednostka odbioru) i ADR 0016 (przegląd heavy).

**Kontekst.** Człowiek nie czyta kodu i nie zamierza. Jakość musi więc pilnować automatyka, bo
błąd na produkcji kosztuje go dni. Tymczasem `once.sh` sam nie uruchamia testów: wynik runu
wyprowadza ze stanu issue, więc zielona bramka to deklaracja workera. Testy niezależnie uruchamia
tylko przegląd heavy (ADR 0016), i tylko dla `heavy`. Gdy ostatnie sub-issue się zamknie, skrypt
od razu nakłada `needs-human-test`. Całość epica (bezpieczeństwo, zgodność z tym, co ustalił grill,
architektura) ogląda dopiero człowiek. Dane z `kregi-dk` (epiki E1–E7: 10, 6, 3, 1, 0, 1, 0
poprawek po odbiorze) pokazują, że odbiór łapie coraz mniej, ale wszystko, co łapie, łapie dopiero
człowiek. Do tego odbiór w terminalu nie pamiętał postępu, a sprawdzanie pojedynczych tasków było
uciążliwe.

**Decyzja.** Trzy warstwy, od najtańszej.

1. **Bramka uruchamiana przez pętlę.** Sekcja `## Ralph` repo ma maszynowo czytelną linię
   `ralph-gate: <komenda>`, którą dopisuje `/ralph-konfiguracja`. Strażnik jej wymaga: bez niej
   Ralph staje z komunikatem „uruchom `/ralph-konfiguracja`”. Pętla uruchamia bramkę sama po
   każdym zamkniętym sub-issue:
   - czerwona → issue wraca otwarte z wynikiem bramki, jak przy porażce przeglądu heavy;
   - czerwona, a po jednym powtórzeniu zielona → **niestabilny test**: run zaliczony, pętla
     zakłada `[ISSUE] Niestabilny test: <nazwa>` (`normal`, `ready-for-agent`). Jako sub-issue
     epica, gdy plik testu zmienił się w tym epicu; inaczej bez rodzica. Worker też może powtórzyć
     bramkę raz, ale nie „do zielonego”, i pisze o tym w raporcie.

   Strażnik zapamiętuje werdykt według skrótu sekcji `## Ralph` (w katalogu gita) i pyta model
   tylko po jej zmianie.

2. **Weryfikacja epica** to ostatnia praca epica i jedyna droga do `needs-human-test`.
   `ralph-epic` podejmuje epic, którego wszystkie sub-issues są zamknięte, a który nie przeszedł
   weryfikacji; `ralph-once <epic>` uruchamia ją na takim epicu. Składniki:
   - bramka uruchomiona przez skrypt;
   - **diff testów epica** jako dowód: usunięte testy, dopisane `skip`/`todo`, zniknięte asercje,
     zmienione wzorce zrzutów ekranu. Każdą taką zmianę weryfikator musi uzasadnić PRD-em;
   - `pest --mutate` na klasach zmienionych w epicu (gdy repo ma Pest), jako informacja dla
     weryfikatora, nie twarda bramka;
   - Opus z czterema subagentami tylko do odczytu: bezpieczeństwo; zgodność z PRD i
     `## Jak odebrać`; UX; architektura względem istniejących wzorców, ADR-ów i `CONTEXT.md`.

   **Blokuje:** bezpieczeństwo, odejście od PRD, coś, co nie działa, konkretne znalezisko
   architektury, zmieniony wzorzec zrzutu ekranu, którego PRD nie zapowiada. Blokujące znalezisko
   staje się sub-issue `[ISSUE] Poprawka: …` (`ready-for-agent`, złożoność według rubryki
   `to-issues-ralph`, dla `heavy` z listą przypadków). Pętla jedzie dalej, a po poprawkach
   weryfikacja rusza znowu. Najwyżej dwie rundy, potem `needs-human-test` z tym, co nadal blokuje,
   na początku listy odbioru. **Nie blokuje:** gust UX (idzie do odbioru jako propozycja), większa
   przebudowa (osobne `[ISSUE] Refaktor: …` poza epikiem), ogólna opinia (odpada).

3. **Odbiór w artefakcie.** Weryfikacja zapisuje **listę odbioru** w komentarzu epica: kroki
   `## Jak odebrać`, to, czego bramka nie udowadnia, ekrany „przed / po” dla zmian wyglądu
   zapowiedzianych w PRD, propozycje do decyzji i nierozwiązane znaleziska. Nic, co agent
   sprawdziłby sam. W komentarzu i w terminalu jest gotowa komenda `cd <worktree> && claude "/odbior <nr>"`
   oraz ID sesji weryfikatora. Skill `/odbior` (Opus) publikuje artefakt claude.ai z trwałym
   stanem: OK / do poprawki, komentarz i zrzut przy każdym kroku, uwagi ogólne. Odbiór da się
   przerwać i wrócić po dniach. Ponowne `/odbior` czyta wyniki: drobiazgi poprawia od razu
   (z bramką przed każdym commitem), większe sprawy zakłada jako sub-issue „Poprawka”, a przy
   samych „OK” przechodzi do zamknięcia epica. „Zróbmy to inaczej” to nowy projekt, więc kończy
   się propozycją osobnego grilla. Jeden artefakt na epic; kolejna runda to nowa sekcja.

`/ralph-konfiguracja` proponuje przy okazji Larastana repo PHP, które go nie ma, oraz testy
zrzutów ekranu (Playwright, szerokość telefonu i komputera) projektom z interfejsem webowym.
Same testy powstają w repo aplikacji.

## Rozważane opcje

- **Przegląd Opusa po każdym sub-issue** — odrzucone: to koszt per sub-issue. Architekturę i
  zgodność z PRD widać dopiero na całym epicu, a pilnowanie testów `heavy` ma już przegląd heavy.
- **Bramka jako deklaracja workera (status quo)** — odrzucone: worker sam pilnuje swojej bramki.
  Uruchomienie komendy przez skrypt nic nie kosztuje w tokenach.
- **Powtarzanie bramki do zielonego** — odrzucone: chowa defekt, który później wraca jako błąd na
  produkcji albo fałszywy alarm co noc.
- **Pętla poprawek bez limitu rund** — odrzucone: weryfikator i worker mogą się kręcić wokół
  sporu, który i tak rozstrzyga człowiek.
- **Weryfikator uruchamia aplikację i robi zrzuty** — odłożone: najpierw kod, bramka i diff testów.
  Wygląd pilnują wzorce zrzutów w repo aplikacji.
- **Lokalny HTML z localStorage** zamiast artefaktu — odrzucone: artefakt ma trwały stan czytelny
  dla agenta i przyjmuje zrzuty, a otwiera się w przeglądarce na Macu tak samo przez SSH.
- **Skrypt-opakowanie zamiast skilla `/odbior`** — odrzucone: odbiór to rozmowa z modelem, a skill
  sam ustawia model.
- **Odbiór na Sonnecie** — odrzucone: zamiana luźnych uwag na precyzyjne zadania to ta sama praca
  co breakdown, a ten zostaje na Opusie (ADR 0019).

## Konsekwencje

- `once.sh` dostaje nowy kod wyjścia dla weryfikacji, a `ralph_epic_decision` nowy stan epica.
  Ślad limitu (ADR 0017) zna trzecią fazę: weryfikację.
- Każde repo z Ralphem musi raz uruchomić `/ralph-konfiguracja`, żeby dostać linię `ralph-gate:`.
- Szacowany koszt weryfikacji to $2–5 na epic w cenach API. Do zmierzenia `ralph_run_cost`, zanim
  ktoś obniży modele subagentów.
- Przegląd heavy per sub-issue zostaje, bo pilnuje czego innego: testów względem listy przypadków.
