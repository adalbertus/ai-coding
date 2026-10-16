# Codex poza Ralphem

Zastępuje ADR 0009 (adaptery runtime'u), ADR 0010 (proza per runtime) i część „Oba runtime'y”
ADR 0013.

**Kontekst.** ADR 0009 zrobił z Ralpha pętlę dla dwóch runtime'ów, a ADR 0013 wymagał, żeby Codex
umiał to samo co Claude, bo miał być zapasem na wyczerpane okno. Ceną jest parytet. Każdy prompt
istnieje w dwóch wersjach prozy (ADR 0010), każdy ma golden dla obu runtime'ów, a każdą nową fazę
trzeba zbudować dwa razy. Wznowienie po limicie (ADR 0017) już powstało tylko dla Claude. Kolejne
fazy (weryfikacja epica z subagentami, `/odbior` z artefaktem claude.ai, ADR 0018) opierają się na
możliwościach Claude, których Codex nie ma pod tymi samymi nazwami albo nie ma wcale. Wyczerpane
okno obsługuje dziś ADR 0017 (czekanie na reset i wznowienie), bez zmiany runtime'u.

**Decyzja.** Ralph uruchamia tylko Claude. Z Ralpha znikają adaptery runtime'u, prompty i golden
per runtime, wymóg parytetu oraz `ralph-once codex`. Skille dla Codexa (`$...`, linki w
`~/.codex/skills`, plugin) zostają, bo kosztują niewiele i są używane poza pętlą.

Sekcja `## Ralph` żyje tylko w `CLAUDE.md`. `/ralph-konfiguracja` przestaje ją pisać do
`AGENTS.md` i usuwa ją stamtąd przy najbliższym uruchomieniu, a bramka rozjazdu kontraktu
(ADR 0010) znika. Martwa kopia z czasem rozjechałaby się z prawdziwą i wprowadzała w błąd sesję
Codexa w tym repo.

## Rozważane opcje

- **Zubożona wersja nowych faz dla Codexa** (np. weryfikacja jednym przebiegiem bez subagentów) —
  odrzucone: podwaja pracę przy każdej fazie, a zapas na wyczerpane okno daje już ADR 0017.
- **Usunięcie Codexa z całego repo** — odłożone: skille dla Codexa nic nie blokują, a decyzja
  o samym Codexie jeszcze nie zapadła.

## Konsekwencje

- Gdy okno Claude jest wyczerpane, nie ma czym kontynuować pętli. Ralph czeka na reset albo
  zostawia ślad do wznowienia (ADR 0017).
- Powrót Codexa do pętli oznaczałby odbudowę adapterów i parytetu dla wszystkich faz od ADR 0017.
