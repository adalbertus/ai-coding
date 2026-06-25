# Backlog

## Skille

Dwa skille: **`/zapisz`** (pisze wskaźnik pozycji do `./tmp/STATUS.md`) i **`/podsumuj`**
(streszcza: żywy kontekst → STATUS → ostatnia sesja). Zob. `CONTEXT.md` i `docs/adr/0001`.
Porzucone: `/wczytaj` (zlane w `/podsumuj`) oraz `/zapisz-config` (konfiguracja per-repo —
niepotrzebna).

**Odłożone ulepszenia:**
- **Język jako opcja** — dziś output po polsku na sztywno (jedyny user). Do ruszenia,
  gdyby skille miały być wielojęzyczne.

## Ralph

`ralph/*` (narzędzia autonomicznej pętli z `finanse-rsz-laravel`) — docelowo też w tym
repo, ale per-repo, bo repozytoria mają różne stacki. Osobny wątek w `TODO.md`
(dopisać wypis testów manualnych do `ralph/once` / `/to-issues-ralph`).

## Sprzątanie w innych repo (robi Wojtek)

Po porzuceniu `/zapisz`+`/wczytaj` osierocone zostają ich lokalne kopie:
- `finanse-rsz-laravel`: `.claude/skills/zapisz`, `.claude/skills/wczytaj`
- `dialog-app`: `.claude/skills/zapisz` + hook `SessionStart` w `.claude/settings.local.json`

Do decyzji per repo: usunąć (jeśli `/podsumuj` wystarcza) albo zostawić jako lokalne.
