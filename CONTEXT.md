# ai-coding — słownik projektu

Repo z osobistym toolingiem do pracy z agentami kodującymi, dystrybuowanym symlinkami przez `install.sh`.
Dwa obszary: **wznawianie pracy** (`/zapisz`, `/podsumuj`) i **pętla Ralpha** (autonomiczna,
jednozadaniowa implementacja). Decyzje projektowe: `docs/adr/`.

## Wznawianie pracy (`/zapisz`, `/podsumuj`)

Dwa skille, które pomagają wrócić do **jednego wątku pracy na repo**. `/zapisz` zapisuje na
granicy fazy mały wskaźnik pozycji; `/podsumuj` daje 2–3 zdaniowy readout „gdzie jestem +
następny krok", dobierając źródło warstwowo (żywy kontekst → SESJA → STATUS → ostatni transkrypt).
Zob. `docs/adr/0001`, `docs/adr/0006`.

**Podsumowanie** (summary):
A 2–3 sentence, position-focused readout — where the work stands and the next step. Ends
with a light offer to start the next step ("Ruszamy?"). Source per the layered fallback.
Not a full recap of everything said.
_Avoid_: snapshot, dump, recap, dziennik, log.

**STATUS** (`./tmp/STATUS.md`):
The minimal *position pointer* `/zapisz` writes: a generated title, date+time, last step,
next step, and optionally one "open question" line. Points at the work; does not re-describe
it (the work lives in artifacts — PRD, issues). One file per repo, overwritten each save.
_Avoid_: dziennik, log, snapshot (it is not a running record).

**Ciepłe wznowienie** (warm resume):
Returning via `claude -r`, which reloads the transcript into context. `/podsumuj` then
summarizes the live context directly — no file involved.

**Zimny start** (cold start):
A fresh `claude` (no `-r`), empty context — deliberately opened for the next phase
(implementation, `/improve-codebase-architecture`). `/podsumuj` falls back to STATUS, then
to the last session transcript.

**Straż świeżości** (freshness guard):
On a cold start where STATUS exists *but* a session file is newer than STATUS's `mtime`,
`/podsumuj` flags it ("STATUS z X, jest nowsza sesja — wziąć z niej?") instead of trusting
a possibly stale pointer. Guards the case where `/zapisz` was forgotten after later work.

**Następny krok** (next step):
The single concrete action that resumes the work — ideally a command name (`/to-prd`) or a
manual step ("test na telefonie"). The thing `/podsumuj` ends on; the thing `/zapisz` records.
_Avoid_: TODO, plan, zadania.

**Pipeline**:
The ordered workflow stages for a repo, documented as plain prose in the native agent contract
file (no special config block), e.g. `grill-with-docs → to-prd → to-issues → implementacja →
test manualny`. `podsumuj` reads it to name the next step; absent, the next step is free text.
_Avoid_: workflow (as a synonym), proces.

## Pętla Ralpha

Autonomiczny, jednozadaniowy loop implementacyjny odpalany z terminala (AFK). Jeden komplet
skryptów i promptów wspólny dla wszystkich repo; to, co per-stack (jak testować, kiedy
„done"), żyje w sekcji `## Ralph` w natywnym kontrakcie agenta repo. Zob. `docs/adr/0002`,
`docs/adr/0009`.

**Pętla Ralpha** (Ralph loop):
An autonomous run that takes exactly ONE task end-to-end — pick → implement → test → commit —
launched from the terminal without supervision (AFK). Two flavours: GitHub-backed (issues) and
local (`issues/*.md`, single fixed model).
_Avoid_: agent, automat, bot.

**Runtime agenta** (agent runtime):
The agent CLI family selected for one Ralph run. The runtime owns every model-backed step in
that run — selector, preflight guard, and worker — so `ralph-once codex` means a Codex run and
`ralph-once claude` means a Claude run. The runtime choice must not change the task semantics.
_Avoid_: using it to mean only the worker, or mixing selector/guard from one runtime with a
worker from another without saying so explicitly. Zob. `docs/adr/0009`.

**Adapter runtime’u** (runtime adapter):
The narrow translation layer between Ralph's shared concepts and a concrete CLI: command flags,
model selection, approval/sandbox mode, and prompt vocabulary. It adapts invocation mechanics;
it does not own task policy, done-criteria, labels, or repo-specific testing rules.
_Avoid_: copying the whole Ralph implementation per agent.

**Worker**:
The model run that actually implements the selected task (explores, uses the runtime's TDD skill
syntax, commits). Distinct from the **selektor** (only picks the next task) and the **strażnik**
(only gates).

**Protokół eksploracji** (exploration protocol):
The rule for how the worker gets facts out of a repo: search first (`Grep`/`Glob`, then `Read`
only the matching range), and delegate to a subagent only when no search pattern can be
formulated because an overview is needed rather than a fact. Deliberately **size-blind** — the
criterion is whether the worker can name what it is looking for, not how big the file is (it
cannot know that before reading). Guards the *smart zone*: context spent on wholesale reads is
context missing from the implementation. Lives in `ralph/prompt.md`, so it applies to every repo
at once. Zob. `docs/adr/0005`.
_Avoid_: „budżet kontekstu" (a token budget the model has no way to measure); a per-repo list of
large files (it rots, and the protocol does not need it).

**Selektor** (selector):
A cheap-model run that, from the open tasks, picks the single next one — it implements nothing.
GitHub flavour only; the local flavour has no selector.

**Strażnik** (preflight guard):
A fail-closed gate run before any work (in `ralph/preflight.sh`): `grep` for the `## Ralph`
section in the selected runtime's native contract file, then a cheap runtime-selected check that
it actually holds runnable instructions. Missing → the loop refuses to start and points to
`ralph-konfiguracja`. Never guesses how to test.
_Avoid_: walidacja, check.

**Lock worktree Ralpha** (Ralph worktree lock):
A script-level, per-worktree lock that prevents two Ralph runs from mutating the same checkout at
the same time. It protects files, not issue numbers: the issue number is metadata for the message,
because two different issues can still edit the same file. If a live PID owns the lock, an
interactive run asks whether to abort or terminate that process; a non-interactive run aborts. If
the PID is gone, an interactive run asks whether to remove the stale lock, while a non-interactive
run removes it and continues.
_Avoid_: per-issue locks like `224.lock`; they do not protect the worktree.

**Kontrakt agenta** (agent contract):
The runtime-native repo instructions that declare the repo's way of working. For Ralph, the
contract is the `## Ralph` section mirrored into the native files the selected runtime reads
(for example `CLAUDE.md` and `AGENTS.md`). The contract contains feedback loops to run before a
commit and done-criteria; it is the ONLY place stack-specific differences live.
_Avoid_: treating `CLAUDE.md` as the conceptual source of truth once multiple runtimes are
supported.

**Sekcja `## Ralph`** (Ralph contract section):
The part of the agent contract where a repo declares its own way of working for Ralph: the
feedback loops to run before a commit (required) and the done-criteria. The shared prompts stay
stack-agnostic and delegate to it.

**Done-criteria** (kryteria ukończenia):
The condition under which a task counts as finished: whether the automated gate can prove it
(→ the worker closes it) or an un-gateable surface remains (→ `needs-human-test`). Declared
per repo in the `## Ralph` section.
_Avoid_: definition of done / DoD.

**doc-sync** (synchronizacja trwałej dokumentacji):
Reconciling a repo's durable docs with what a task actually shipped, done as part of the *act
of closing it* — whoever closes first syncs. Two classes: *statusowe* (known-gaps, backlog) the
closer rewrites; *słownikowe/projektowe* (CONTEXT.md, ADR) the closer only **flags**, never
silently rewrites (the glossary belongs to the grill, not the loop). Self-close → the worker
syncs in the same commit; `needs-human-test` → deferred to the human's close-out confirmation.
Which docs and which class is declared per repo in the `## Ralph` section.
_Avoid_: folding it into the automated gate; the worker rewriting CONTEXT.md / ADRs.

**complexity** (złożoność):
A task's intrinsic difficulty — `trivial` / `normal` / `heavy` — meaning specifically whether a
stronger model would change the *outcome*: the difficulty of getting the implementation right,
not the blast radius of getting it wrong (only the former warrants a pricier model). The
complexity→model mapping lives only in the loop script, so labels stay stable as models change.
_Avoid_: putting a model name in the label; conflating it with blast radius.

**needs-human-test**:
A task already implemented but awaiting a human to verify it (e.g. on a real device). While one
is open, the GitHub loop refuses to start new work. Applied by the worker after implementation,
never at triage.

**AFK / HITL**:
AFK = a task fit to run unsupervised (label `ready-for-agent`); HITL = one needing a human
decision (won't carry the label). The selektor and worker only touch AFK tasks.

**PRD** (product requirements doc):
In this repo, an **ephemeral** synthesis of a finished grill, produced only as input to the
issue breakdown and materialized **in-session** (in context) — never published to the tracker,
never written to a file, and never read again after breakdown. Its value is entirely up-front:
it denoises a long grill session into a clean one-page input and supplies the exhaustive
user-story list the breakdown uses as a coverage checklist. Zob. `docs/adr/0008`.
_Avoid_: treating it as a durable artifact, a published parent issue, a `tmp/` file, or a spec
anyone reads later.

## Sesja deliberacyjna (`/sesja`)

Punkt wejścia do sesji projektowych: start tematu, checkpoint, wznowienie po `/clear`,
domknięcie. Cienki wrapper — samo grillowanie prowadzi cudzy `grill-with-docs`.
Zob. `docs/adr/0006`.

**Sesja deliberacyjna** (deliberative session):
The scope of `/sesja`: any working conversation whose context is mostly **deliberation** —
proposals, counter-arguments, variants killed along the way, i.e. spent fuel. The opposite
pole is an **implementation** run, whose context is verbatim file reads that must survive
intact; there a checkpoint is a loss, not a gain. That axis — deliberation vs implementation —
is the only one that bounds `/sesja`. Whether `grill-with-docs` was involved does not.
_Avoid_: naming this scope „grillowanie" (that is one kind of it, not the whole).

**Grillowanie** (grilling):
The **adversarial** kind of deliberative session, not a particular skill call: structured
interrogation of one's own design. A `grill-with-docs` session and an equally adversarial
unaided argument both count; an ordinary weighing-of-options conversation does not — that is
the wider sesja deliberacyjna. The commonest way to leave the smart zone, which is why
`/sesja` offers a grill as the default entry into a **new** topic.
_Avoid_: using it as a synonym for „wywołanie `grill-with-docs`", or as the name for the scope
of `/sesja`.

**Smart zone**:
The region in which a session still works well. Deliberately **not a number**: a hunch the
human notices, with no metric and no threshold. A run can be healthy at 140k when its context
is clean and unhealthy at 90k when it is thick with failed attempts — the variable is
**purity, not size**. The model cannot detect leaving it (that would be introspection over its
own usage); the human does.
_Avoid_: a token threshold; equating it with window size or with „dużo kontekstu".

**Plik stanu sesji** (`./tmp/SESJA.md`):
The ephemeral container for what is still **open**, complementing `CONTEXT.md`/ADR, which hold
what is **settled**. One per repo (one session at a time), gitignored, ~30 lines — a list, not
prose. Holds: *settled* (pointers into ADR/`CONTEXT.md`, **plus** one-line entries for decisions
too small to file durably), *open* branches in order, *rejected* variants **with reasons**, the
sharpened glossary, and how to resume. Deleted when the topic closes — by then `/to-prd` has
consumed its one-line settled entries as raw material.
_Avoid_: putting open questions into an ADR (an ADR records rulings — that mismatch is what made
„zapisz stan" feel hard); calling it a tracker, dziennik or log.

**Sekcja `## Sesja`** (repo reminder):
The place in a repo's native agent contract file (`CLAUDE.md`, `AGENTS.md`) where the proactivity
rule lives, written by `sesja-konfiguracja`. Needed because `sesja` is explicit-invocation only,
so nothing would otherwise interrupt a drifting deliberation; native contract files are in context
from the first message. Near-identical across repos — this is **distribution**, not configuration,
and the value is that the rule is opt-in per repo and versioned with it. Instructions only: no
rationale, no ADR pointers (the file is re-read on every message, so anything lookup-able is a
standing tax).
_Avoid_: global agent contract files (undistributed, unversioned, and their cross-repo pointers
dangle); phrasing the rule as a measurement of context usage rather than an observation of the
visible dialogue.

**Ramka** (framing):
The argument string `/sesja` builds from `SESJA.md` and passes to `grill-with-docs` when
resuming a **grill** — the „restart prompt", not a separate artifact. Only needed on that
branch; a `Wznowić: rozmowa` resume delegates to nobody, so it frames nobody. Required where
it applies, and not decorative:
`grill-with-docs` says *„interview me relentlessly about **every** aspect… walk down **each**
branch"*, so an unframed resume re-opens settled ground. Always in the **arguments**, never in
the wrapper body — arguments land last and win by recency.
_Avoid_: copying `grill-with-docs`' prompt instead of framing it.

## Przykłady rozmów

**Wznawianie — ciepło** (po wznowieniu sesji, tydzień przerwy, długa skompaktowana sesja):
— `/podsumuj` lub `$podsumuj`
— Wznawiamy grill modelu danych dla importu wyciągów; ustaliliśmy encje i nazwy, otwarta
  została kwestia walut. Przerwane w trakcie `/grill-with-docs`. Następny krok: dokończyć
  grill (waluty), potem `/to-prd`. Ruszamy?

**Wznawianie — zimno** (świeża sesja, jest STATUS najświeższy):
— `/podsumuj` lub `$podsumuj`
— (z `./tmp/STATUS.md`) Domknięte: grill + PRD + issues #1–5 dla importu wyciągów. Bieżąca
  sesja jest czysta. Następny krok: implementacja, zacznij od #1. Ruszamy?

**Ralph — strażnik blokuje** (terminal, repo bez kontraktu):
— `ralph-once codex`
— ✋ Brak sekcji „## Ralph" z instrukcjami testowania. Odpal w sesji Codex: `$ralph-konfiguracja`
— `$ralph-konfiguracja` wykrywa stack, dopisuje `## Ralph` do `CLAUDE.md` i `AGENTS.md`, zakłada
  labelki. Potem `ralph-once codex` rusza: selektor wybiera issue (wg complexity → model),
  worker implementuje, testuje, commituje.
