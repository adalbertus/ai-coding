# Breakdown `to-issues-ralph` w świeżej sesji

Częściowo odwraca ADR 0008: łańcuch zostaje nieinteraktywny, ale breakdown nie jedzie już w sesji
grilla.

**Kontekst.** ADR 0008 odrzucił breakdown w osobnej sesji. Uznał, że PRD w kontekście nic nie
kosztuje wobec transkryptu grilla. Pomiar z 2026-10-16 (logi sesji, ceny API jako miara zużycia
okna) mówi co innego: to-issues kosztowało $84,7, prawie tyle co wszystkie grille ($86,9).
18 sesji to-issues odczytało z cache 154 mln tokenów, a wygenerowało 1,1 mln. Każdy krok
breakdownu ponownie czytał cały kontekst grilla. W epiku E1 `kregi-dk` to-issues kosztowało
$10,4 przy grillu za $5,7. Jest też powód jakościowy. Worker widzi tylko issue, PRD i repo, nigdy
rozmowy. Breakdown, który korzysta z ustaleń spoza PRD, tworzy issue z wiedzy, której worker nie
dostanie. Długi kontekst gorzej też trzyma szczegóły. ADR 0012 przeniósł PRD do treści epica, więc
nośnik między sesjami już istnieje.

**Decyzja.** `to-issues-ralph` ma dwa wywołania.

- **Bez argumentu, w sesji grilla:** sprawdza, czy wszystko, co grill ustalił, jest w PRD albo
  w dokumentach repo; braki dopisuje do PRD bez pytania. Potem publikuje epic (PRD +
  `## Jak odebrać`) i wypisuje: `/clear`, potem `/to-issues-ralph <nr>`.
- **Z numerem epica, w świeżej sesji:** robi breakdown, blokery, triage złożoności i listy
  przypadków `heavy`, czytając PRD wyłącznie z treści epica.

Świeża sesja jest przy tym testem kompletności PRD: czego nie ma w PRD, nie istnieje dalej
(`CONTEXT.md`, PRD). Breakdown zostaje na Opusie, bo cięcie na zadania i listy przypadków to
miejsce, gdzie mocniejszy model zmienia wynik (logika ADR 0016).

## Rozważane opcje

- **Jedna sesja (status quo ADR 0008)** — odrzucone na zmierzonym koszcie.
- **Breakdown w nocnym łańcuchu** (`ralph-epic` sam rozbija epic bez sub-issues) — odłożone:
  najpierw 2–3 epiki ręcznie w świeżej sesji. Breakdown jest nieinteraktywny, więc przeniesienie
  będzie małe.
- **PRD w pliku `tmp/`** — odrzucone: treść epica już jest nośnikiem, a plik byłby drugim
  źródłem prawdy.
- **Breakdown na Sonnecie** — odrzucone: oszczędność mała wobec ryzyka złego cięcia, które potem
  płaci każdy worker.

## Konsekwencje

- Po grillu są dwie komendy i `/clear` pomiędzy, zamiast jednej.
- Jakość breakdownu zależy w całości od PRD. Krok sprawdzenia braków w sesji grilla jest jedynym
  miejscem, gdzie wiedza z rozmowy może jeszcze trafić do PRD.
