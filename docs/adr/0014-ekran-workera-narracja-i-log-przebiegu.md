# Ekran workera: narracja zamiast komend, jeden raport, log przebiegu

Rozwija ADR 0013 (worker AFK przez `claude -p`, postęp na bieżąco, zapis w `.git/ralph-logs/`).

**Kontekst.** Pierwszy prawdziwy epic (finanse, epic #281, 8 sub-issues, Sonnet) pokazał trzy
problemy z tym, co `ralph-epic` wypisuje:

1. **Ściana komend.** Renderer pokazywał każde wywołanie narzędzia jako pierwszą linię komendy
   i pomijał tekst modelu. Sonnet skleja po kilka komend przez `;` i pisze pliki przez
   `python3 - <<'EOF'`, więc linie zawijały się na 2–3 wiersze, a ucięte heredoki wyglądały jak
   wyciek. Jednocześnie zdania, w których model mówi po ludzku, co robi („Bramka zielona,
   commituję”), szły do kosza. Pole `description` Basha, które dałoby opis kroku, było w 2 ze
   183 wywołań.
2. **Fałszywe raporty.** `composer test` przekraczał 2-minutowy limit Basha, CLI przenosiło go
   w tło, model kończył turę i `claude -p` emitował `result`. Po zakończeniu zadania w tle CLI
   budziło model w nowej turze. Jeden run dawał do 4 wyników, a renderer drukował każdy pod
   nagłówkiem „Raport workera”. Pierwszy („nie commituję, czekam na testy”) wyglądał jak porażka,
   ostatnie były odpowiedziami na wygasłe monitory.
3. **Brak śladu harnessu.** Zapis runu (`*.jsonl`) miał wszystko o workerze, ale decyzje skryptu
   (strażnik, wybór issue, gałąź, kody wyjścia, powód stopu) zostawały tylko w scrollbacku
   terminala. A to ich potrzeba, gdy w innej sesji prosimy o „zobacz logi i napraw”.

**Decyzja.**

- **Narracja jest treścią ekranu, kroki tłem.** Tekst modelu idzie jako `› …`. Kroki są
  przyciemnione, po jednej linii, ucięte do szerokości terminala (`…`). Pełne komendy są w zapisie
  runu. Tak samo dla Codexa (komunikaty agenta jako narracja).
- **Praca w tle jest nazwana, nie ukrywana ani nie zmieniana.** Z wydarzeń `system`
  (`task_started`, `task_updated`, `background_tasks_changed`, `task_notification`) renderer
  wypisuje: przeniesienie w tło `⧗`, czekanie na koniec tury `…`, wznowienie `↻`. Zachowania
  modelu nie zmieniamy promptem. Czy bramka idzie w tle, zależy od projektu (czasu jego testów),
  a współdzielony prompt nie powinien tego rozstrzygać.
- **Jeden raport, na końcu strumienia.** Raportem jest ostatni `result`, którego tura coś robiła
  (`num_turns > 1`). Odpowiedź na wygasłe powiadomienie to jedna tura bez narzędzi i raportem nie
  zostaje. Wynik z `is_error` na końcu (np. limit sesji, 429) to czerwone „Worker przerwany”,
  a brak wyniku to „Worker zakończył się bez raportu”. To heurystyka: tura sprzątająca po
  wygasłym monitorze, która wywoła narzędzie, wygrałaby z właściwym raportem. Godzimy się na to,
  bo cała narracja i tak jest na ekranie, a zapis runu ma wszystkie wyniki.
- **Kolory według tego, czego potrzeba od człowieka.** Czerwony: coś się zepsuło (krok
  odrzucony przez CLI, worker przerwany, issue niedomknięte, błąd skryptu). Pomarańczowy: stop
  czekający na decyzję, nic nie jest zepsute (strażnik `✋`, `needs-human-test`, odkryty HITL,
  limit iteracji, ostrzeżenie o limicie użycia). Zielony: issue zamknięte, epic do odbioru.
  Nowy werdykt po każdym runie `once.sh` (`✓ Issue #N zamknięte.`), bo wcześniej sukces było widać
  tylko po tym, że rusza kolejna iteracja. Kolory tylko na terminalu, `NO_COLOR` je wyłącza.
- **Nie kolorujemy nieudanych komend workera Claude.** Kod wyjścia to prawie zawsze kod `| tail`.
  Parsowanie wyjścia w poszukiwaniu „FAILED” raz pomaluje grepa szukającego tego słowa, a innym
  razem przepuści prawdziwą porażkę. Wiarygodne sygnały to narracja i werdykt iteracji.
- **Log przebiegu obok zapisu runu.** Każde wywołanie `ralph-epic`, `ralph-once`
  i `ralph-once-local` pisze to, co było na ekranie, do `.git/ralph-logs/<stamp>-<etykieta>.log`
  (bez kolorów, z linią startu i końca z kodem wyjścia). Skrypt uruchamia siebie ponownie
  z wyjściem przez `tee`. `ralph-once` pod `ralph-epic` dziedziczy log epicu, więc jest jeden
  plik na wywołanie. Sesja HITL dostaje terminal (fd 3/4 zachowane przed `tee`) i do logu nie
  trafia: interaktywne CLI potrzebuje TTY, a jej transkrypt to sesja runtime'u.
- **Zapis runu zostaje mimo transkryptu sesji.** `~/.claude/projects/…/<session>.jsonl` dubluje
  treść, ale nazywa się identyfikatorem sesji, nie numerem issue, i Claude Code czyści go po
  czasie. Zapis w `.git/ralph-logs/` jest w repo, ma numer issue w nazwie i działa tak samo dla
  Codexa.

**Odrzucone.**

- **Grupowanie kroków w jedną linię** (`· 7 kroków: Bash ×6, Grep`): przy dłuższym czytaniu
  kodu przez kilka minut nic by się nie pojawiało i nie byłoby wiadomo, czy worker żyje.
- **Zakaz pracy w tle w prompcie** (bramka na pierwszym planie z timeoutem 10 min, bez
  `Monitor`): to zależy od projektu, a renderer wystarcza, by przebieg był czytelny.
- **Rotacja logów:** jeden run to około 300 KB w `.git`; na razie bez potrzeby.

## Konsekwencje

- Renderer Claude ma stan: buforuje ostatni tekst (żeby nie wydrukować raportu dwa razy)
  i dostaje sztuczny znacznik końca strumienia (`ralph_eof`), na którym wypisuje raport. Testy
  w `lib.test.sh` sprawdzają to na fixture'ach odtworzonych z logów finanse.
- Uruchamianie siebie ponownie oznacza, że skrypt pod logiem ma stdout w rurze: decyzję
  o kolorach podejmuje rodzic przy terminalu i przekazuje ją w `RALPH_COLOR`. Szerokość
  terminala jest czytana z `/dev/tty`, nie ze stdout.
- Testy uruchamiane w tym repo muszą wyłączać log (`RALPH_RUN_LOG=off`), inaczej piszą do jego
  `.git`. `epic.test.sh` sprawdza log w osobnym, tymczasowym repo.
