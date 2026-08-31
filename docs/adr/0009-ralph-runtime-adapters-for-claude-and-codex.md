# Ralph multi-runtime — wspólny rdzeń, adaptery Claude i Codex

**Kontekst.** Ralph powstał jako tooling dla Claude Code: skrypty wołały `claude`, prompty
używały składni `/skill`, a kontrakt repo żył w `CLAUDE.md`. Chcę móc projektować i rozbijać
pracę w Claude, a implementację odpalać zamiennie w Claude albo Codex, np.
`ralph-once claude 224`, `ralph-once codex 224`, przy zachowaniu wstecznej zgodności
`ralph-once 224` = Claude.

**Decyzja.** Ralph staje się multi-runtime: semantyka pętli pozostaje wspólna, a różnice
Claude/Codex żyją w cienkich adapterach runtime'u. Wybrany runtime obejmuje wszystkie kroki
modelowe jednego runu — selektor, strażnika i workera. Prompty pozostają wspólne i
agent-agnostyczne; adapter renderuje tylko mechanikę uruchomienia oraz mały słownik runtime'u
(np. składnię invocation skilli). Kontrakt repo jest natywny dla obu agentów: ta sama sekcja
`## Ralph` ma być utrzymywana w plikach czytanych przez dany runtime, w szczególności
`CLAUDE.md` i `AGENTS.md`.

## Rozważane opcje

- **Osobny Ralph per agent** — odrzucone: podwaja skrypty, prompty i dokumentację, więc szybko
  rozjedzie semantykę selekcji, done-criteria i doc-sync.
- **Claude jako orkiestrator, Codex tylko jako worker** — odrzucone: tanie na start, ale
  niejednoznaczne. `ralph-once codex` powinien oznaczać run Codex, nie hybrydę ukrytą w środku.
- **Jeden wspólny rdzeń z adapterami runtime'u (wybrane)** — zachowuje jedną semantykę Ralpha,
  a izoluje niestabilne szczegóły CLI: flagi, model mapping, sandbox/approval i składnię skilli.

## Konsekwencje

- `ralph-once 224` pozostaje kompatybilne i domyślnie używa Claude; jawne runtime'y są
  dostępne jako `ralph-once claude 224` i `ralph-once codex 224`.
- Model mapping jest per runtime. Etykiety `complexity:*` zostają stabilne i nie zawierają nazw
  modeli.
- `ralph-konfiguracja` musi umieć utrzymać kontrakt Ralpha zarówno w `CLAUDE.md`, jak i
  `AGENTS.md`.
- Prompt source nie może zakładać Claude-only składni typu `/tdd`; używa neutralnego szablonu,
  który adapter renderuje dla wybranego runtime'u albo zastępuje plain-textową instrukcją.
