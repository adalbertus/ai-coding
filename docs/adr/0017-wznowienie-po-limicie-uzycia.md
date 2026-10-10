# Wznowienie po limicie użycia

Uzupełnia ADR 0013 (autonomiczny epic): wyjątek od zasady „porażka zatrzymuje, bez pomijania”.

**Kontekst.** `ralph-epic` puszczony na noc regularnie wyczerpuje pięciogodzinne okno konta
Claude. Runtime odmawia wtedy dalszych wywołań, worker kończy się w pół pracy, a `once.sh`, który
wynik runu wyprowadza wyłącznie ze stanu issue, widzi „otwarte, nadal `ready-for-agent`” —
**porażkę AFK** (kod 3). Pętla staje. Rano trzeba było znaleźć martwą sesję, wznowić ją ręcznie
(`claude -r`) i poprosić o kontynuację, bo ponowne `ralph-epic` odmawiało startu na brudnym
drzewie (przy `ralph-base-branch`). Cztery takie noce, za każdym razem trafiony worker w połowie
konkretnego issue. Tymczasem limit użycia nie jest oceną pracy: issue jest tak samo niedokończone
jak chwilę wcześniej, a strumień `claude -p` mówi o nim wprost — zdarzenie limitu ze statusem
`rejected`, godzina resetu, wiadomość z `api_error: usage_limit_reached`.

**Decyzja.** Run Claude przerwany przez **limit użycia** nie jest porażką. Ralph zostawia **ślad**
i wykonuje **wznowienie po limicie**: tę samą sesję, z jej kontekstem, prosi o kontynuację.

- **Wykrywanie ze strumienia, tylko limit użycia.** Inne przerwania (Ctrl+C, awaria, błąd API)
  zachowują się jak dotąd. Tylko runtime Claude; na Codeksie limit pozostaje porażką.
- **Ślad** w katalogu gita worktree (obok locka): issue, faza (worker albo przegląd heavy), sesja,
  gałąź, godzina resetu, model i effort, początek zakresu commitów. Zapisany zanim Ralph zacznie
  czekać, więc przeżywa wyłączenie laptopa.
- **Czekanie w procesie**, gdy reset wypada w ciągu 6 h: powiadomienie „czekam do HH:MM”, sen
  liczony zegarem ściennym (uśpienie maszyny go nie wydłuża), potem `claude -p --resume <id>`
  z poleceniem kontynuacji. Bez `/compact` przed wznowieniem: kontekst mieści się w oknie, compact
  czyta ten sam kontekst (zimny cache i tak jest płacony), a gubi dosłowne odczyty plików.
  Wznowienie odbywa się w tej samej iteracji `ralph-epic`, więc nie zużywa limitu iteracji.
- **Reset dalej niż 6 h** (np. limit tygodniowy): ślad zostaje, `once.sh` kończy się nowym kodem 8
  „limit użycia”, `ralph-epic` staje na pomarańczowo z powiadomieniem.
- **Ponowne uruchomienie** (`ralph-epic <epic>`, `ralph-once [<issue>]`) znajduje ślad i wznawia,
  jeśli ten jest ważny: issue w stanie z chwili przerwania (worker: otwarte z `ready-for-agent`;
  przegląd: zamknięte) i ta sama bieżąca gałąź. Wtedy brudne drzewo nie blokuje — to praca
  przerwanego workera. Nieważny ślad znika z jedną linią na ekranie i obowiązują zwykłe reguły.
  Ślad innego issue albo runtime'u zostaje nietknięty.
- **Nieudane wznowienie** (runtime nie podjął sesji): stop z komunikatem, ślad zostaje.
  Przypadek rzadki, oceni go człowiek.
- **Przegląd heavy** wznawia swoją sesję tak samo. **Strażnik i selektor** nie mają czego
  wznawiać: czekają na reset i powtarzają wywołanie (ich wyjście przechodzi na strumień JSON, żeby
  limit było widać z pola, nie z tekstu).

## Rozważane opcje

- **Tylko czekanie w procesie** — odrzucone: laptop często jest ustawiony na wyłączenie po 2 h,
  więc proces i tak ginie przed resetem.
- **Tylko ślad, bez czekania** — odrzucone: maszyna, która nie śpi, traciłaby resztę nocy.
- **Świeży run issue po resecie** — odrzucone: wyrzuca kontekst workera w połowie pracy, a drzewo
  zostaje z jego niezacommitowanymi zmianami.
- **Autostart po resecie (launchd)** — odrzucone: wyłączony laptop i tak nie wstanie sam, a ręczne
  `ralph-epic` rano wystarcza.
- **Szerszy mechanizm wznawiania po dowolnym przerwaniu** — odrzucone: inne przerwania nie mają
  znanego momentu powrotu ani pewności, że praca nie była zła.

## Konsekwencje

- `once.sh` ma kod wyjścia 8 (limit użycia); `ralph-epic` traktuje go jako stop do ponowienia.
- Ślad pomija bramkę brudnego drzewa — tylko dla tej samej gałęzi i tego samego issue.
- Wznowiona sesja płaci za zimny cache całego kontekstu; to tańsze niż powtórzenie pracy od zera.
