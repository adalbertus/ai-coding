# Proza promptu per runtime + bramka rozjazdu kontraktu

**Kontekst.** ADR 0009 założył, że adapter runtime'u renderuje „tylko mechanikę uruchomienia oraz
mały słownik runtime'u". Sekcja EXPLORATION promptu była więc jedna dla obu gałęzi, napisana
rzeczownikami Claude Code: „use `Grep`/`Glob`, then `Read` only the matching range
(`offset`/`limit`)", z furtką „delegate to the `Explore` subagent". Worker Codexa nie ma żadnego
z tych narzędzi pod tymi nazwami; dostawał instrukcję, której nie umiał zamienić na komendę,
i spadał na `cat` całego pliku — dokładnie to zachowanie, które protokół eksploracji ma wykluczyć.
Efektem było wypalanie okna kontekstu na starcie runu, czyli awaria tym dotkliwsza, im słabszy
model.

Osobno: `finanse-rsz-laravel` ma sekcję `## Ralph` w obu plikach kontraktu i te sekcje się
rozjechały. `CLAUDE.md` mówi „commituj na `dev`, `main` to produkcja" (ADR-0035 tamtego repo),
`AGENTS.md` zamarzł na wcześniejszym „commit straight to `main`". `ralph-once codex` commitował
więc na gałąź produkcyjną, bez żadnego sygnału, że pracuje na nieaktualnych regułach.

**Decyzja.** Dwie zmiany, wynikające z tej samej obserwacji: różnica runtime'ów nie kończy się
na słowniku.

1. **Adapter renderuje całe akapity, nie tylko rzeczowniki.** Sekcja EXPLORATION jest jednym
   placeholderem `{EXPLORE_GUIDANCE}`, rozwijanym przez `ralph_explore_guidance()` w `ralph/lib.sh`
   w dwie osobne wersje prozy. Gałąź Codexa nazywa komendy wprost (`rg -n` z `grep -rn` jako
   alternatywą, potem `sed -n '<start>,<end>p'`, `wc -l` przy wątpliwości) i wprost zakazuje
   `cat`-owania glosariusza, kontraktu i globa po katalogu. Gałąź Claude'a zostaje znak w znak
   taka, jak była.
2. **Gałąź Codexa nie wspomina subagentów.** Codex je ma, ale koszt subagenta zmierzyliśmy tylko
   u Claude'a (ADR 0005: własna podłoga kontekstu, parafraza zamiast źródła). Dopisanie słabszemu
   modelowi opcji „zdeleguj" daje mu tanie językowo wyjście z zadania, które ma wykonać sam.
   Wraca do rozważenia z pomiarem, nie wcześniej.
3. **Strażnik dostaje bramkę rozjazdu kontraktu.** Gdy repo ma oba pliki kontraktu i oba
   deklarują `## Ralph`, sekcje muszą być identyczne po normalizacji końcowych spacji i pustych
   linii; różnica = halt z diffem i skierowanie do `ralph-konfiguracja`. Bramka odpala się przy
   obu runtime'ach.
4. **Golden file na render promptów dla obu gałęzi** (`ralph/test/golden/`, 4 pliki). Dla
   `claude` to bramka: „to się nie ma prawa zmienić" przestaje być obietnicą w notatce i staje
   się testem, który pada. Dla `codex` to lupa: proza będzie strojona pod pomiary kontekstu
   i każda jej wersja ma być widoczna w historii gita.

## Rozważane opcje

- **Zestaw małych placeholderów** (`{TOOL_SEARCH}`, `{TOOL_READ}`, `{SUBAGENT_CLAUSE}`) —
  odrzucone. Małe dziury działają, gdy obie gałęzie mają tę samą strukturę zdania i różnią się
  rzeczownikami. Tu nie mają: „`Read` z `offset`/`limit`" to jedno narzędzie z dwoma parametrami,
  a `rg` + `sed -n` to dwa kroki z własnym ryzykiem (za wąski zakres). Wspólny szkielet zdania
  wymusiłby kłamstwo po jednej ze stron.
- **Proza neutralna dla obu** („znajdź, potem przeczytaj tylko fragment") — odrzucone. Awaria
  polega na tym, że worker nie umie zamienić instrukcji na komendę; instrukcja neutralna zostawia
  tę samą lukę, tylko grzeczniej sformułowaną. Gałąź Claude'a jest konkretna, więc abstrakcyjna
  gałąź Codexa nie byłaby parytetem, tylko instrukcją słabszą.
- **Osobne pliki fragmentów** (`ralph/fragments/explore-{claude,codex}.md`) — odrzucone.
  Rozsypują jeden prompt na cztery miejsca. Cytowany heredoc w `lib.sh` trzyma wszystkie różnice
  runtime'ów w jednym pliku; czytelność złożonego promptu daje golden file.
- **Porównanie sekcji bajt w bajt** — odrzucone: wywróci się na końcowej spacji i wyszkoli
  w ignorowaniu bramki. Głębsza normalizacja niż whitespace to już parser, niepotrzebny, bo obie
  sekcje mają powstawać z jednego przebiegu `ralph-konfiguracja`.
- **Bramka tylko przy jednym runtime** — odrzucone: rozjazd wychodziłby wtedy wyłącznie
  w przebiegu robionym najrzadziej, czyli dokładnie tak, jak defekt ADR-0035 przeleżał
  w `AGENTS.md`.

## Konsekwencje

- ADR 0009 zostaje zmieniony w jednym punkcie: adapter renderuje prozę, nie tylko słownik.
  Granicą pozostaje **polityka**: done-criteria, priorytety selekcji, doc-sync i reguły repo
  zostają wspólne i nie wolno ich różnicować per runtime, choćby było wygodnie.
- Każda świadoma wspólna poprawka promptu wymaga regeneracji golden file'ów
  (`UPDATE_GOLDEN=1 bash ralph/test/lib.test.sh`). To mechanizm, nie wada: diff w review pokazuje
  wtedy dokładnie, co zobaczy każdy z runtime'ów.
- Repo z jednym plikiem kontraktu zostaje legalne — brak drugiego pliku (albo drugi plik bez
  sekcji `## Ralph`) to brak bramki. W tym drugim przypadku odpalenie tamtego runtime'u i tak
  pada głośno na istniejącej kontroli obecności sekcji.
- Bramka zatrzyma oba runtime'y w repo, które już jest rozjechane. Naprawa treści tam musi
  poprzedzić wdrożenie bramki, inaczej odbiera codzienne `ralph-once` do czasu osobnej sesji.
- `ralph_contract_section()` jest teraz w `lib.sh` (wyjęte z `preflight.sh`), bo bramka woła
  ekstraktor dwa razy.
