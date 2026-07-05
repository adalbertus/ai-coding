# Rubryka `complexity`: `heavy` znaczy trudność implementacyjna, nie blast-radius

**Kontekst.** Jedna iteracja workera pętli Ralpha na tierze `heavy` (Opus) kosztuje ~15× tyle
co `normal` (Sonnet). Dotychczasowa rubryka w `to-issues-ralph` nadawała `heavy` m.in. za
blast-radius (migracja na współdzielonej tabeli), więc mechaniczne slice'y — np.
`ADD COLUMN … DEFAULT 0`, w pełni domknięte testem migracji + human-testem — dostawały Opusa
bez żadnej korzyści z jego dodatkowej mocy.

**Decyzja.** `complexity` mierzy jedno: **czy silniejszy model realnie zmienia wynik** —
trudność zrobienia implementacji *dobrze*, nie promień rażenia zrobienia jej *źle* (osie
ortogonalne, tylko pierwsza uzasadnia droższy model). `heavy` rezerwujemy dla jednego
przypadku: korektności implementacyjnej, której zielona bramka nie dowodzi — izolacja
tenanta/autoryzacja oraz subtelna logika (finansowa, daty, algorytmiczna), gdzie
wiarygodnie-błędna implementacja przechodzi przez test, jaki worker sam sobie napisze. Blast-
radius obsługuje bramka + `needs-human-test`, nie droższy model. Osąd projektowy jest
front-loadowany w `/grill-with-docs` → PRD → rozbicie przed pętlą, więc „nieustalony design"
nie eskaluje modelu — doostrzamy acceptance criteria issue (*sharpen before escalate*).
Mapowanie `complexity → model` w `ralph/once.sh` zostaje **bez zmian**; dźwignią jest
dyscyplina etykiet, nie mapowanie.

**Konsekwencje.** Świadomie akceptujemy, że sporadycznie slice o dużym blast-radiusie poleci na
Sonnecie — siatką bezpieczeństwa jest wtedy test + human-test, a nie premia Opusa. W zamian
typowa iteracja pętli jest ~15× tańsza, a `heavy` staje się rzadkim, świadomym wyjątkiem
zamiast domyślnej reakcji na „ryzykowną" tabelę.
