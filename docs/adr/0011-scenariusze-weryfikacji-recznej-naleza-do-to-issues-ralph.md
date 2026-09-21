# Scenariusze weryfikacji ręcznej należą do `to-issues-ralph`, nie do workera

**Kontekst.** Ta sama robota była robiona dwa razy. `to-issues-ralph` wpisuje sekcję
`## Jak sprawdzić ręcznie` do body issue w momencie zakładania — mocnym modelem, z całym planem
w kontekście. Potem prompt Ralpha kazał workerowi napisać „concrete, step-by-step manual test
instructions" od zera, jakby tamtej sekcji nie było.

Drugi raz jest droższy i trafia w najsłabsze miejsce: to jedyne w całym runie zadanie
językowo-produktowe, nie mechaniczne, wykonywane przez model wybrany pod implementację (często
słabszy), na końcu runu, przy kontekście już zapchanym implementacją. Efekt to instrukcje gorsze
od tych, które już leżą w issue.

**Decyzja.** Worker **używa istniejącej sekcji weryfikacji ręcznej i dopisuje tylko odchylenia**
— kroki, które przestały pasować, dodatkowe sprawdzenia, których wymagała implementacja, faktyczne
etykiety UI różne od założonych. Gdy nic nie odbiega, ma to powiedzieć wprost. Pisze scenariusz
od zera **wyłącznie wtedy, gdy issue takiej sekcji nie ma**.

Reguła jest wspólna dla obu runtime'ów i obu wariantów pętli (`prompt.md` i `prompt-local.md`).

## Rozważane opcje

- **Zostawić jak jest** — odrzucone: to nie jest redundancja bez kosztu, tylko przepisywanie
  dobrego tekstu na gorszy, w najdroższym momencie runu.
- **Wyciąć pisanie scenariuszy z workera całkowicie** — odrzucone. Dałoby cichą regresję dla
  issues zakładanych ręcznie i dla repo spoza łańcucha `to-issues-ralph`: worker zostawiłby
  `needs-human-test` bez żadnej instrukcji, a człowiek dowiedziałby się o tym dopiero przy
  weryfikacji. Fallback jest konieczny.
- **Kazać `to-issues-ralph` gwarantować sekcję zawsze** — odrzucone: nie kontroluje issues
  zakładanych poza nim, więc gwarancja byłaby pozorna, a worker i tak potrzebuje fallbacku.

## Konsekwencje

- Obowiązek przesuwa się między narzędziami: jakość scenariuszy weryfikacji ręcznej jest teraz
  odpowiedzialnością `to-issues-ralph`, a nie workera. Regresja w tamtym skillu przestaje być
  maskowana przez workera piszącego wszystko od nowa.
- Sekcja `## Ralph` w repo może odjąć workerowi wymóg pisania pełnych scenariuszy; te sekcje
  aktualizuje `ralph-konfiguracja`, nie ręczna edycja.
- Komentarz workera pod issue przestaje być samowystarczalny — człowiek czyta body issue
  i komentarz razem. To świadomy koszt: jedno źródło prawdy zamiast dwóch rozbieżnych.
