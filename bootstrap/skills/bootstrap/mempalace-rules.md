## Memory (MemPalace)

A local MemPalace holds memory from past sessions. Session start injects a short
wake-up summary automatically; anything deeper you must fetch yourself.

- **Before answering about past work, decisions, prior bugs, or why something is
  the way it is — search the palace first** (`mempalace_search`, and
  `mempalace_kg_query` for relational/temporal facts). The injected wake-up is a
  summary, not the whole store.
- **Quote what you find verbatim.** Never paraphrase stored content into a claim.
- **If the palace has nothing, say so.** Do not fill the gap with a guess.
- Durable outcomes are saved automatically on Stop / SessionEnd / PreCompact.
  File something mid-session with `mempalace_add_drawer` only when it would
  otherwise be lost. Never file secrets or tokens.
