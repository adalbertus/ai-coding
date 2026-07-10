# Doc-sync związany z aktem zamknięcia — nie osobny krok w issue, nie czysty `## Ralph`

**Kontekst.** Gdy Ralph kończy issue — sam je zamyka (gate zielony) albo oznacza
`needs-human-test` i oddaje człowiekowi — trwała dokumentacja repo (known-gaps, backlog,
czasem CONTEXT) zostaje nieaktualna. Aktualizacja docs nie była częścią „definition of done",
a na ścieżce human-test człowiek przy zamykaniu o niej zapomina. Pytanie brzmiało: gdzie jest
„dom" tej synchronizacji (nazwijmy ją **doc-sync**).

**Decyzja.** doc-sync jest **częścią aktu zamknięcia**: kto zamyka issue, ten najpierw godzi
dokumenty z tym, co realnie weszło. Rozwinięcie:

- **Zbiór dokumentów jest per-repo** — wykrywa go i spisuje `/ralph-konfiguracja`; lista + klasy
  żyją w sekcji `## Ralph` danego repo (jeden dom dla całego kontraktu Ralpha).
- **Dwie klasy.** *Statusowe* (known-gaps, backlog) — zamykający **przepisuje**.
  *Słownikowe/projektowe* (`CONTEXT.md`, `docs/adr/`) — zamykający **tylko zgłasza** potrzebę
  zmiany, nigdy nie przepisuje; słownikiem rządzi faza grill (`/grill-with-docs`), nie pętla.
- **Self-close.** Worker synchronizuje dokumenty statusowe w tym samym commicie — steruje tym
  cienki, domyślnie-bierny krok w `ralph/prompt.md` i `ralph/prompt-local.md`, odpalany
  **tylko** na gałęzi self-close.
- **needs-human-test.** Worker **nie tyka** docs; synchronizacja jest odroczona do potwierdzenia
  człowieka („potwierdzam" / „zamykaj"), obsługiwana **instrukcją w `## Ralph`** honorowaną przez
  zwykłą sesję Claude, która zamyka issue.
- **Nic w treści issue** — `/to-issues-ralph` bez zmian.

**Rozważane opcje.**

- **Krok doc-sync w treści issue (`/to-issues-ralph`)** — odrzucone: *które* dokumenty ruszać to
  właściwość repo, nie zadania; w każdej issue byłby ten sam boilerplate ×N, a zmiana reguły
  znaczyłaby edycję N issues zamiast jednej sekcji `## Ralph`. Proces nie należy do treści zadania.
- **Czysty `## Ralph`, zero w prompt.md** — odrzucone: sekcja THE ISSUE w prompcie jest skrojona
  pod *werdykt* (zamknij / human-test / niedokończone), nie pod *czynność* przed nim; obowiązek
  schowany w prozie czytanej „pod decyzję" wypada. Dodatkowo edycja docs musi wejść **do commita**,
  a done-criteria czytane są w THE ISSUE, które biegnie **po** COMMIT → poprawka po commicie. Cienki
  bierny haczyk (nadzbiór nieszkodliwy, jak gate `needs-human-test` w ADR 0002) rozwiązuje oba.
- **„Pending verification" — worker pisze status przejściowy już przy human-test** — odrzucone na
  rzecz „bind-to-close": tworzy śmieciowy wpis-przejściowy wymagający później drugiej edycji
  (pending → done). Wiązanie z zamknięciem zapisuje raz, w momencie prawdziwym (zamknięcie =
  zweryfikowane).
- **Dedykowany skill `/ralph-domknij` dla ścieżki human-test** — odrzucone na rzecz prozy w
  `## Ralph`: nowa komenda przywraca zależność od pamięci człowieka (trzeba pamiętać, by jej użyć,
  zamiast napisać „zamykaj"); proza honoruje istniejące, naturalne potwierdzenie. Skill
  model-invocable łamałby konwencję „skille tylko jawnie" tego repo i dokładał własne ryzyko.

**Konsekwencje.**

- Reguła trzyma się tylko, gdy zamknięcie idzie **przez agenta**. Klik „Close" w UI GitHuba (albo
  ręczne `mv` do `issues/done/` w wariancie local) omija doc-sync — świadomy trade-off, w praktyce
  pokryty nawykiem zamykania przez sesję.
- `ralph/prompt.md` i `ralph/prompt-local.md` zyskują jeden bierny krok DOC-SYNC — inert, gdy
  `## Ralph` nie deklaruje dokumentów (spójne z filozofią nadzbioru z ADR 0002).
- `/ralph-konfiguracja` dostaje nowy krok: wykryć trwałe dokumenty repo, sklasyfikować (HITL,
  potwierdzane z człowiekiem) i wpisać listę + klasy + regułę zamknięcia do `## Ralph`.
- Słownik (`CONTEXT.md`) i ADR-y zostają pod kontrolą fazy grill — worker i close-out je tylko
  zgłaszają. Nowy termin **doc-sync** w `CONTEXT.md`.
