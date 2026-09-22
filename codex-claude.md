# Codex vs Claude — intuicja przy wyborze modeli

Stan porównania: 22 września 2026 r. Notatka na podstawie rozmowy i sprawdzonej w niej dokumentacji producentów.

Do budowania intuicji przydaje się mapowanie: **Luna ↔ Haiku, Terra ↔ Sonnet, Sol ↔ Opus, Astra ↔ Fable**. To porównanie roli modeli w ofercie, nie stwierdzenie, że modele w parze mają identyczne umiejętności ani wynik bezpośrednich testów.

| Codex | Najbliższa rola w Claude | Kiedy po taki model sięgać |
|---|---|---|
| **GPT-5.6 Luna** | **Haiku 4.5** | Małe, dobrze określone zadania, szybkie odpowiedzi, powtarzalna praca. |
| **GPT-5.6 Terra** | **Sonnet 5** | Codzienna implementacja: jasno opisany feature, testy, lokalny refaktor. Balans jakości i kosztu. |
| **GPT-5.6 Sol** | **Opus 5** | Wymagające codzienne programowanie: zmiany przez wiele modułów, nieoczywiste błędy, więcej samodzielnego osądu. |
| **GPT-6 Astra** | **Fable 5.1** | Najtrudniejsze problemy, dużo niepewności, długie zadania wymagające utrzymania spójnego planu. |
| **GPT-5.5** | **Opus 4.8**, orientacyjnie | Poprzednia generacja mocnego modelu. Analogia pokoleniowa, nie pomiar jakości. |

Taką interpretację wspiera pozycjonowanie w dokumentacji [OpenAI](https://developers.openai.com/api/docs/models) i [Anthropic](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence). Konkretne zastosowania w tabeli są praktyczną interpretacją tych ról.

## Domyślny model a poziom możliwości

**Sol jest bliżej roli Opusa niż Sonneta**, mimo że można używać Sola jako codziennego wyboru w Codexie, a Claude może polecać domyślnie Sonneta. „Domyślny” opisuje wybór produktu, nie wspólny poziom zdolności między firmami. „Default” na przytoczonej w rozmowie liście Claude wskazuje Sonneta, nie dodatkowy model.

## Dobór do zadania

Praktyczny punkt startowy: dobierać poziom przede wszystkim do **ilości decyzji zostawianych agentowi**.

- „Dodaj pole zgodnie z istniejącym wzorcem” → Terra / Sonnet.
- „Dodaj funkcję; ustal, jak poprawnie wpasować ją w architekturę” → Sol / Opus.
- „Nie rozumiemy, dlaczego system czasem gubi dane; znajdź przyczynę i opracuj rozwiązanie” → Astra / Fable.

To propozycja sposobu doboru, nie wynik bezpośrednich testów tych par. Duży, mechaniczny task może potrzebować mniej zdolności niż mały problem z subtelną zależnością.

## Model i reasoning effort

**Model określa możliwości, a effort — ile pracy model ma włożyć w rozwiązanie danego problemu.** Dobry obraz: wybieramy specjalistę, a następnie określamy, czy potrzebujemy szybkiej oceny, czy starannej analizy z rozważeniem alternatyw.

Effort nie jest stałym czasem ani liczbą tokenów. Modele dostosowują rozumowanie do trudności zadania; wyższy poziom zwiększa skłonność do głębszej analizy. Zwykle kosztuje to więcej czasu i tokenów. [Dokumentacja OpenAI](https://developers.openai.com/api/docs/guides/reasoning).

### Jak czytać skalę

Poniższa tabela jest praktyczną wskazówką do wyboru, nie formalną definicją.

| Effort | Intuicja | Przykładowe zastosowanie |
|---|---|---|
| `low` | „Rozwiąż sprawnie, zadanie jest jasno określone” | Mała poprawka, wyjaśnienie fragmentu kodu |
| `medium` | „Przemyśl zwykłe zależności” | Codzienna implementacja według ustalonego planu |
| `high` | „Sprawdź założenia i przypadki brzegowe” | Review, projektowanie interfejsu, trudniejszy bug |
| `xhigh` | „Poświęć więcej pracy na nieoczywiste zależności” | Złożona diagnoza, refaktor przez wiele modułów |
| `max` | „Priorytetem jest jakość rozwiązania trudnego problemu” | Zadania, przy których niższe ustawienia już nie wystarczają |

**`high` nie jest wspólną jednostką między modelami.** Nawet w Claude skala jest kalibrowana osobno dla każdego modelu. Nie można przyjąć, że `Sonnet high = Opus high`, ani tym bardziej `Opus high = Sol high`. `max` również nie gwarantuje najlepszego wyniku: możliwe są malejące korzyści i nadmierne analizowanie. [Dokumentacja Claude Code](https://code.claude.com/docs/en/model-config#choose-an-effort-level).

### Poziomy obsługiwane przez modele

To **poziomy API** — menu konkretnej wersji aplikacji może udostępniać inny podzbiór lub dodatkowe tryby. Stan zgodny z datą tej notatki.

| Model | Obsługiwane poziomy effort |
|---|---|
| GPT-5.6 **Sol, Terra, Luna** | `none`, `low`, `medium`, `high`, `xhigh`, `max`; domyślnie w API `medium` |
| GPT-6 **Astra** | `low`, `medium`, `high`, `xhigh`, `max`; bez `none` |
| **GPT-5.5** | `none`, `low`, `medium`, `high`, `xhigh`; domyślnie w API `medium` |
| Claude **Sonnet 5, Opus 5, Fable 5.1, Opus 4.8** | `low`, `medium`, `high`, `xhigh`, `max`; domyślnie w API `high` |
| Claude **Haiku 4.5** | Brak parametru effort; osobno obsługuje extended thinking z budżetem tokenów |

Źródła: [Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol), [Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra), [Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna), [Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5), [Claude effort](https://platform.claude.com/docs/en/build-with-claude/effort), [Haiku a Sonnet](https://platform.claude.com/docs/en/models/sonnet-5/migration-guide).

OpenAI opisuje effort przede wszystkim jako sterowanie ilością rozumowania. Anthropic opisuje szerszy wpływ, obejmujący również sposób używania narzędzi. Nie należy jednak utożsamiać effort z długością odpowiedzi — dla Opusa 5 dokumentacja wprost zaleca sterować długością przez polecenie w prompcie. [OpenAI](https://developers.openai.com/api/docs/guides/reasoning), [Anthropic](https://platform.claude.com/docs/en/build-with-claude/effort).

### Proponowane ustawienia startowe

| Model | Punkt startowy | Kiedy podnosić |
|---|---|---|
| Luna | `low` / `medium` | Do `high` przy trudniejszym, ale nadal wąskim zadaniu |
| Terra | `medium` | `high`, gdy musi samodzielnie rozstrzygać zależności |
| Sol | `medium` do implementacji, `high` do projektu/review | `xhigh` przy złożonej diagnozie |
| Astra | `high` do trudnych zadań; `medium` do interaktywnej rozmowy | `xhigh` / `max`, gdy dodatkowa analiza ma realną wartość |
| GPT-5.5 | `medium` | `high`, później `xhigh` |
| Sonnet 5 | `high` | `xhigh` przy trudniejszym kodowaniu |
| Opus 5 | `high`; próbować `medium` przy rutynie | `xhigh` przy wymagającej pracy |
| Fable 5.1 | `high` | `xhigh` / `max` dla najtrudniejszych zadań |
| Opus 4.8 | `xhigh` do kodowania, `high` do pozostałych analiz | `max` dopiero przy konkretnej potrzebie |

Część Claude jest zgodna z zaleceniami producenta; ustawienia OpenAI powyżej są propozycją roboczą z rozmowy, nie wynikiem benchmarku tych konfiguracji. [Zalecenia Anthropic](https://platform.claude.com/docs/en/build-with-claude/effort).

Praktyczna reguła eskalacji: **jeśli model dobrze rozumie problem, ale analizuje go zbyt płytko — podnieść effort. Jeśli konsekwentnie źle ujmuje problem — spróbować mocniejszego modelu albo poprawić kontekst.** Nie zakładać, że `Terra max` zastąpi `Sol medium`: dodatkowe rozumowanie nie jest prostym zamiennikiem zdolności modelu.

### Ultra i ultracode

`ultra` w Codexie i `ultracode` w Claude należy traktować osobno od powyższej tabeli API. Codex dokumentuje `ultra` dla wspieranych modeli; Claude `ultracode` łączy `xhigh` z dodatkową organizacją pracy przez aplikację. Nie są to automatycznie równoważne ustawienia. [Codex](https://learn.chatgpt.com/docs/agent-configuration/subagents), [Claude Code](https://code.claude.com/docs/en/model-config).

## Jak wyrobić sobie własną intuicję

Dać Solowi i Opusowi te same trzy zadania z tego samego stanu repo: zwykły feature, trudny bug i dyskusję architektoniczną. Porównywać przede wszystkim **liczbę potrzebnych korekt, przeoczone zależności i jakość końcowego rozwiązania**.

To bardziej miarodajne niż płynność odpowiedzi. Wynik będzie oceną całego zestawu **model + Codex/Claude Code + instrukcje**, czyli tego, z czym faktycznie pracujemy.
