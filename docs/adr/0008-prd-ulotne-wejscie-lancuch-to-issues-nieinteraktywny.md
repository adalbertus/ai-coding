# PRD jako ulotne wejście — łańcuch `to-issues-ralph` nieinteraktywny

**Kontekst.** Po sesji `/grill-with-docs` zawsze uruchamiałem tę samą sekwencję:
`/to-prd` → `/to-issues-ralph`. Oba skille mają interaktywne checkpointy (`to-prd` krok 2:
„sprawdź z użytkownikiem, które moduły…"; `to-issues` krok 4: „przepytaj użytkownika…
iteruj, aż zaakceptuje"). Przez ~setki sesji **zawsze akceptowałem bez uwag** — checkpointy
były martwym kodem. Do tego `to-prd` publikował PRD jako issue-rodzica z prefiksem `[PRD]`,
którego **nikt nigdy nie czyta**: `ralph/once.sh:77` odfiltrowuje `[PRD]` z puli wybieralnej,
a linie 62–64 wprost odmawiają jego uruchomienia. Opublikowany `[PRD]` był martwym
artefaktem, który zamykałem ręcznie. Cały łańcuch jedzie w jednej sesji, bez `/clear` — nic
nie przekracza granicy zimnego startu.

**Decyzja.** `to-issues-ralph` uruchamia cały łańcuch end-to-end, **nieinteraktywnie**. PRD
jest syntetyzowany jako **ulotny** artefakt, materializowany **w kontekście sesji** (wypisany w
odpowiedzi, nigdy publikowany, nigdy zapisywany do pliku) wyłącznie jako wejście do breakdownu,
które kolejny krok czyta wprost z kontekstu. Interaktywne checkpointy w upstreamowych
`to-prd`/`to-issues` są tłumione **dyrektywami override w momencie wywołania** — nadal
**delegujemy, nie forkujemy**. Escape hatch na tryb interaktywny został usunięty w całości jako
martwy kod.

## Rozważane opcje

- **Pominąć PRD, robić breakdown wprost z kontekstu grilla** — odrzucone: sesje grilla bywają
  długie i zaszumione (odrzucone warianty, dygresje — „zużyte paliwo"). PRD działa jak
  soczewka odszumiająca: kompresuje długi transkrypt do czystej jednostronicowej kartki, i
  dostarcza wyczerpującą listę user stories, której breakdown używa jako checklisty pokrycia.
- **Dalej publikować PRD jako issue-rodzica (status quo)** — odrzucone: martwy artefakt,
  odfiltrowany przez pętlę (`once.sh:77`), zamykany ręcznie.
- **Nowy skill-orkiestrator opakowujący `to-prd` + `to-issues-ralph`** — odrzucone: mutacja
  istniejącego skilla jest prostsza (jedna komenda, jeden SKILL.md w kontekście zamiast dwóch)
  i zgodna z instynktem człowieka.
- **Forknąć/wkleić upstreamowe skille, by usunąć ich prompty** — odrzucone: łamie zasadę
  „deleguj, nie kopiuj" i rozjeżdża się z upstreamem. Dyrektywy override dają ten sam efekt
  bez kopiowania.
- **Zrzucać ulotny PRD do `tmp/PRD.md` zamiast do kontekstu** — odrzucone: w jednej sesji plik
  nic nie oszczędza. Wygenerowanie PRD *to* są tokeny w kontekście niezależnie od zlewu (zapis
  Write niesie całą treść jako payload), a jeśli breakdown odczyta plik, treść wchodzi do
  kontekstu **drugi raz** — plik kosztuje więc równo lub więcej. Zmierzony przykładowy PRD to
  ~3k tokenów (~1,5% okna), przy transkrypcie grilla o rząd wielkości większym — stawka poniżej
  progu, dla którego warto dokładać ruchomy element (plik, gitignore, override na re-read). Plik
  miałby sens tylko przy przekroczeniu granicy kontekstu (breakdown w osobnej sesji, `/clear`
  pośrodku) — a to kłóci się z „jedną nieinteraktywną komendą".

## Konsekwencje

- Jedna komenda po grillu; zero pytań do człowieka na całej ścieżce.
- PRD żyje tylko w kontekście bieżącej sesji; nie trafia do pliku, do gita ani do trackera.
  Po breakdownie jest martwym balastem (kroki weryfikacji i complexity dłubią przy `gh`), ale
  ten koszt jest jednorazowy i marginalny wobec transkryptu grilla już w kontekście.
- Filtr `[PRD]` w `once.sh` staje się nieszkodliwym no-opem (zostaje jako kod defensywny).
- Sekcja `## Parent` w szablonie `to-issues` samoznika (nie ma issue-rodzica).
- Ścieżka interaktywna znika. Jeśli grill był płytki, jakość breakdownu jedzie teraz w całości
  na syntezie PRD bez ludzkiej bramki — świadomie zaakceptowany trade-off.
