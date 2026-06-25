# Źródło podsumowania — warstwowy fallback zamiast jednego mechanizmu

**Kontekst.** Wracam do pracy na dwa sposoby. **Ciepło:** `claude -r` w środku fazy —
Claude Code przeładowuje transkrypt do kontekstu. **Zimno:** nowy `claude` po domknięciu
fazy (implementacja albo `/improve-codebase-architecture` startują w czystej sesji) —
kontekst pusty. Chcę jednym poleceniem dostać 2–3 zdania „gdzie jestem + następny krok",
w obu sytuacjach.

**Decyzja.** Dwa skille + warstwowe źródło. **`/zapisz`** pisze minimalny wskaźnik pozycji
do `./tmp/STATUS.md` na spokojnej granicy fazy. **`/podsumuj`** streszcza, biorąc źródło
w kolejności:
1. żywy kontekst (ciepło),
2. `./tmp/STATUS.md` (zimno) — ze **strażą świeżości**: jeśli istnieje sesja nowsza niż
   `mtime` STATUS-u, pyta, czy wziąć z niej zamiast z (potencjalnie nieaktualnego) pliku,
3. ostatni transkrypt sesji z dysku — **za zgodą**, gdy nie ma ani kontekstu, ani STATUS-u.

Transkrypt pozostaje nadrzędnym zapisem stanu; STATUS to celowy, czysty skrót na zimny start.

## Rozważane opcje

- **Tylko transkrypt** (żywy + ostatni plik), bez STATUS — odrzucone: na zimno trzeba
  parsować duży, zaszumiony JSONL, a „następny krok" bywa nieobecny, gdy urwę w pół myśli.
- **Tylko trwały STATUS** (`/zapisz`+`/wczytaj`) — odrzucone: plik starzeje się, gdy
  zapomnę `/zapisz`, a przy ciepłych przerwach dubluje transkrypt (antywzorzec „dwa trackery").
- **Hook `SessionStart`/`SessionEnd`** — odrzucone: hooki to skrypty shellowe, nie wywołują
  modelu; nie ma też zdarzenia „bezczynność". Skille są wołane **jawnie**.
- **Warstwowy fallback (wybrane)** — łączy zalety: ciepło zero plików, zimno czysty STATUS
  jeśli jest, inaczej fallback do transkryptu. Straż świeżości łata starzenie się pliku.

## Konsekwencje

- Dwa skille zamiast jednego; `/podsumuj` ma logikę wyboru źródła — czyta
  `$CLAUDE_CODE_SESSION_ID`, odnajduje rodzeństwo sesji repo, porównuje `mtime`.
- Zimny start jest **wspierany** (we wcześniejszej wersji był poza zakresem).
- `/podsumuj` musi czytać tylko **ogon** dużych plików JSONL (bieżąca sesja ~1,1 MB).
- STATUS w `./tmp/` jest lokalny (per maszyna, prawdopodobnie poza gitem) — przy jednym
  wątku na repo to wystarcza.
