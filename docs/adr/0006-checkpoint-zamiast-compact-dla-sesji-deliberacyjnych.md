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
| `./tmp/GRILL.md` | to, co **otwarte** (+ odrzucone + słownik) | efemeryczne, kasowane po domknięciu |

Rozdział rozwiązuje konkretną trudność: opór przy „zapisz stan" nie brał się z niedomkniętej
sesji, tylko z próby wpisania **otwartych pytań do dokumentu, który jest zapisem rozstrzygnięć**.
ADR nie ma miejsca na „nie wiemy jeszcze, czy XLS czy XLSX, i od tego zależy wybór biblioteki".
Przy dwóch pojemnikach każda rzecz ma gdzie trafić.

Obsługuje to jeden skill `/grilluj` — punkt wejścia dla startu tematu, checkpointu i wznowienia.
Jest **cienkim wrapperem**: woła `grill-with-docs`, nie powiela go (precedens: `to-issues-ralph`
nad `to-issues`). Przy wznowieniu przekazuje **ramkę** w argumentach, bo `grill-with-docs` bez
niej przechodzi gałęzie od góry i odpytuje rzeczy ustalone.

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
- **Jeden plik stanu na temat** (`grill-<slug>.md`) — odrzucone: jeden grill na repo, zgodnie
  z zasadą przyjętą już dla `./tmp/STATUS.md` („don't pile up files"). Slug wymagałby stabilnego
  odtwarzania między checkpointami i wyboru spośród wielu plików przy wznowieniu.

## Konsekwencje

- `./tmp/GRILL.md` trzyma także **treść**, nie tylko wskaźniki: decyzje rozstrzygnięte, które nie
  przechodzą sita ADR ani nie są terminami, nie mają innego domu. Ta klasa jest liczniejsza niż
  obie trwałe razem.
- Kasowanie pliku po `/to-prd` jest bezpieczne, bo PRD konsumuje właśnie te wpisy.
- `/grilluj` przesłania `/grill-with-docs` jako punkt wejścia. Bezpośrednie wywołanie dalej
  działa, ale bez ramki i bez wznowienia — i bez ostrzeżenia.
- Zakres obejmuje **każdą** sesję deliberacyjną, nie tylko prowadzoną skillem; sesje
  implementacyjne (Ralph) pozostają poza nim.
- Zysk pojawia się dopiero po `/clear` — sam checkpoint nie zmniejsza okna.
- Eksperyment weryfikujący, jeszcze nieprzeprowadzony: sesja grillowania **bez ani jednego
  kompaktu**, porównana z tamtą na 50 pytań. Kosztuje mniej niż jeden kompakt.
