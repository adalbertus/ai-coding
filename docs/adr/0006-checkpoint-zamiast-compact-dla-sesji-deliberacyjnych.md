# Checkpoint + `/clear` zamiast `/compact` dla sesji deliberacyjnych

**Kontekst.** Długie sesje `/grill-with-docs` przekraczają 100k i były ratowane odruchowym
`/compact`-em — w jednej sesji 50 pytań i 6 kompaktów, czyli ~600k tokenów wejścia na samo
streszczanie, za zero produktu pracy. Przy koncie PRO wąskim gardłem jest limit konta, nie okno.

Rozpoznana pętla: `/compact` streszcza, więc zachowuje decyzje, ale nie zachowuje przy pełnej
wierności odpowiedzi z niuansami — a po szóstej kompresji tej samej treści nie zostaje z nich
nic. Ginie zwłaszcza to, co **odrzucone**: kompakt streszcza wnioski, nie odstrzelone warianty.
Model wraca więc do gałęzi uznanych za zamknięte i pyta ponownie, co przyspiesza wzrost okna
i wymusza kolejny kompakt. Kompaktowanie jest tu prawdopodobnie **źródłem** powtórzonych pytań,
nie reakcją na nie. (Status: rozumowanie zgodne z danymi, nie zmierzone — transkrypt tamtej
sesji nie został obejrzany.)

Rozróżnienie, bez którego wniosek jest fałszywy: w sesji **implementacyjnej** kontekst to w
~57% odczyty plików — materiał, który musi zostać **dosłowny**. Kompakt zamienia 26 tys. znaków
pliku w zdanie prozy, więc model czyta go ponownie; kompakt jest tam stratą **strukturalnie**,
a lekarstwem jest ubicie przebiegu i start od czystej podłogi. W sesji **deliberacyjnej**
kontekst to w większości propozycje, kontrargumenty i warianty odrzucone po drodze —
czyli zużyte paliwo, definicja dystraktora. Tu czyszczenie podnosi stosunek sygnału do szumu.

**Decyzja.** Dla sesji deliberacyjnych: **zapis stanu na dysk + `/clear`**, nigdy `/compact`.
Stan rozdzielony na dwa pojemniki, bo mają różną trwałość i różny format:

| artefakt | zawartość | trwałość |
|---|---|---|
| `CONTEXT.md` / `docs/adr/` | to, co **rozstrzygnięte** | trwałe, commitowane |
| `./tmp/SESJA.md` | to, co **otwarte** (+ odrzucone + słownik) | efemeryczne, kasowane po domknięciu |

Rozdział rozwiązuje konkretną trudność: opór przy „zapisz stan" nie brał się z niedomkniętej
sesji, tylko z próby wpisania **otwartych pytań do dokumentu, który jest zapisem rozstrzygnięć**.
ADR nie ma miejsca na „nie wiemy jeszcze, czy XLS czy XLSX, i od tego zależy wybór biblioteki".
Przy dwóch pojemnikach każda rzecz ma gdzie trafić.

Obsługuje to jeden skill `/sesja` — punkt wejścia dla startu tematu, checkpointu, wznowienia
i domknięcia. Jest **cienkim wrapperem**: woła `grill-with-docs`, nie powiela go (precedens:
`to-issues-ralph` nad `to-issues`). Przy wznowieniu grilla przekazuje **ramkę** w argumentach,
bo `grill-with-docs` bez niej przechodzi gałęzie od góry i odpytuje rzeczy ustalone.

**Nowelizacja (2026-08-07): granicą jest oś deliberacja/implementacja, nie obecność grilla.**
Skill nazywał się pierwotnie `/grilluj`, a plik stanu `./tmp/GRILL.md` — niezgodnie z zakresem
ustalonym niżej w Konsekwencjach („każda sesja deliberacyjna, nie tylko prowadzona skillem").
Etykieta „grillowanie" trafiła tu dlatego, że tam ta potrzeba boli najczęściej, a nie dlatego,
że zbadano i odrzucono rozmowy bez grilla. Nazwy idą więc za obiektem, który skill **ratuje**
(sesję), a nie za tym, który **kasuje** (kontekst) — stąd odrzucona kandydatura `/kontekst`,
myląca się dodatkowo z `CONTEXT.md`, czyli pojemnikiem na rzeczy rozstrzygnięte. Grill pozostaje
domyślnym wejściem w **nowy** temat (świeży temat najwięcej zyskuje na bezlitosnym odpytywaniu),
ale przestaje definiować zakres; pole `Wznowić: grill-with-docs | rozmowa` niesie tę różnicę
między oknami kontekstu. Przy okazji doostrzono słownik: **grillowanie** to sesja deliberacyjna
o charakterze **przeciwnika**, a nie każda rozmowa o designie.

## Rozważane opcje

- **`/compact` jako rutynowy checkpoint** — odrzucone: niszczy zapis tego, co już odpowiedziane
  i odrzucone, więc napędza pętlę powtórzeń, którą miał łagodzić.
- **Restart samym pierwotnym pytaniem** — odrzucone: nowa sesja wyprowadza wszystko od zera.
  Ale „przejrzyj `CONTEXT.md` i ADR" też nie wystarcza: brakuje listy odrzuconych wariantów,
  której trwałe dokumenty z definicji nie trzymają.
- **Otwarte pytania do ADR** (jeden pojemnik zamiast dwóch) — odrzucone: zły pojemnik, patrz wyżej.
- **Modyfikacja cudzych skilli** (`grill-with-docs`, `/handoff`, `/to-prd`) — odrzucone: konflikty
  przy aktualizacji upstreamu. Wołanie cudzego skilla to nie modyfikacja i jest dozwolone.
- **Próg ostrzegawczy („ostrzeż mnie przy 100k", rekalibracja `WARN/CRIT`)** — odrzucone: model nie
  ma wglądu we własne zużycie, więc wyprodukuje konfabulację; a przesuwanie progu to zamiana
  jednego zgadywania na inne. Moment checkpointu wyznacza **granica decyzji** albo zauważone
  powtórzone pytanie — nie licznik.
- **Autoodpalanie skilla** (zdjęcie `disable-model-invocation`) — odrzucone: skill zapisuje pliki
  i każe zrobić `/clear`, więc uruchomiony samoczynnie w środku myśli jest inwazyjny, a
  autodetekcja trybu trafiłaby wtedy w „checkpoint", kiedy człowiek chciał tylko dokończyć zdanie.
  Spust zostaje u człowieka; przypomnienie idzie osobno (zob. Konsekwencje).
- **Jeden plik stanu na temat** (`grill-<slug>.md`) — odrzucone: jeden grill na repo, zgodnie
  z zasadą przyjętą już dla `./tmp/STATUS.md` („don't pile up files"). Slug wymagałby stabilnego
  odtwarzania między checkpointami i wyboru spośród wielu plików przy wznowieniu.

## Konsekwencje

- `./tmp/SESJA.md` trzyma także **treść**, nie tylko wskaźniki: decyzje rozstrzygnięte, które nie
  przechodzą sita ADR ani nie są terminami, nie mają innego domu. Ta klasa jest liczniejsza niż
  obie trwałe razem.
- Kasowanie pliku po `/to-prd` jest bezpieczne, bo PRD konsumuje właśnie te wpisy.
- `/sesja` przesłania `/grill-with-docs` jako punkt wejścia. Bezpośrednie wywołanie dalej
  działa, ale bez ramki i bez wznowienia — i bez ostrzeżenia.
- **Reguła proaktywności trafia do `CLAUDE.md` każdego repo, sekcją `## Sesja`**, pisaną przez
  `/sesja-konfiguracja` (precedens: `/ralph-konfiguracja` i sekcja `## Ralph`). W ramce
  przekazywanej do `grill-with-docs` obowiązywała tylko wewnątrz grilla, czyli nie tam, gdzie
  brakowało jej najbardziej — w zwykłej rozmowie o designie nic nie przypominało o checkpoincie.
  Reguła musi być sformułowana jako **obserwacja widocznego kontekstu** („wracamy do rzeczy
  uznanej wyżej za zamkniętą"), nigdy jako pomiar własnego zużycia — ten wariant jest odrzucony
  wyżej i tu obowiązuje tak samo. Odrzucony wariant pośredni: **globalny `~/.claude/CLAUDE.md`**
  — nie jest dystrybuowany przez `install.sh`, więc zachowanie znika przy przesiadce na inną
  maszynę, a wersja odsyłająca po uzasadnienie do `docs/adr/` tego repo wskazuje w próżnię
  wszędzie, gdzie repo nie jest sklonowane.
- Sekcja `## Sesja` zawiera **wyłącznie instrukcje** — bez uzasadnień i bez wskaźników do ADR.
  `CLAUDE.md` jest doliczany do każdej wiadomości w repo, więc treść, którą czytelnik może
  znaleźć gdzie indziej, jest tam podatkiem stałym.
- Kontrola, czy `./tmp/` jest poza gitem, przenosi się z pierwszego checkpointu do
  `/sesja-konfiguracja`: checkpoint odpala się, gdy człowiek jest zmęczony sesją, więc pytania
  konfiguracyjne trzeba z niego wyjąć.
- Zakres obejmuje **każdą** sesję deliberacyjną, nie tylko prowadzoną skillem; sesje
  implementacyjne (Ralph) pozostają poza nim.
- Zysk pojawia się dopiero po `/clear` — sam checkpoint nie zmniejsza okna.
- Eksperyment weryfikujący, jeszcze nieprzeprowadzony: sesja grillowania **bez ani jednego
  kompaktu**, porównana z tamtą na 50 pytań. Kosztuje mniej niż jeden kompakt.
