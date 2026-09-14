# statusline

A Claude Code status line built as **instrumentation for the current session** — two lines, three matched meters, no noise.

```
◆ Opus 5 1M · ▇ xhigh ·  claude-tools · ⎇ main ⇡2 ⇣ · ±7 · +312 -87 · ⬡ ok · PR#42 ● · 167k · PONYTAIL
CONTEXT ███████▌░░░░  63% ⣀⣀⣰⣶ │   CACHE ███████████▏  93%  38m │    WAIT ██▋░░░░░░░░░  22%  30m
```

**Line 1 — where you are.** Model, context window size, reasoning effort, thinking/fast mode, subagent or worktree, directory, branch with ahead/behind, changed-file count, lines added/removed, codegraph index state, open PR with review state, session tokens.

**Line 2 — three gauges, same width, so you compare them by shape.**

| Gauge | Reads | Trailing | Why you'd look |
|-------|-------|----------|----------------|
| `CONTEXT` | how full the context window is | braille trend — how fast it is filling | when to wrap up or compact |
| `CACHE` | prompt-cache hit ratio — how much of the conversation Claude re-reads from cache instead of re-sending | time until the cached prefix goes cold, or `cold` | high means faster, cheaper turns; a drop means something invalidated the cache |
| `WAIT` | share of session wall time spent waiting on the model rather than on you | session duration | whether the session is model-bound or you-bound |

Meters fill in **eighth-blocks**, so a bar has eight times the resolution of its character count, and the fill is a green→yellow→red gradient (blue→teal→peach for the cache and API gauges, where "high" isn't "bad").

## Scope: this session only

No spend, no 5-hour window, no 7-day window. Those are account-level and Orca already shows them; repeating them here would be noise. Everything on both lines describes the session in front of you.

## Install

```bash
./install.sh          # links into ~/.claude and wires settings.json
./demo.sh             # preview every state without restarting Claude Code
```

Needs Python 3 (stdlib only — no `jq`, no dependencies). Restart Claude Code after installing.

## Configuration

| Variable | Default | Effect |
|----------|---------|--------|
| `SL_WIDTH` | detected, else `110` | Column budget. Claude Code runs the script without a tty, so set this if your terminal is much wider or narrower. |
| `SL_ASCII` | `0` | Pure ASCII — no block glyphs, no icons. Also turns on automatically when the locale isn't UTF-8. |
| `SL_NO_NERD` | `0` | Keep Unicode but drop Nerd Font icons. |
| `NO_COLOR` | unset | Monochrome. |

The layout is responsive: it drops the gauge trailers below ~90 columns, then shrinks the meters, then falls back to bare percentages. Line 1 sheds segments by priority — the model, directory and PONYTAIL badge are the last to go.

### Animation (off by default)

The script can shimmer the meters and pulse the brand mark, but that needs `"refreshInterval": 1` in the `statusLine` block, which re-runs it **every second** (~40 ms of CPU per second). It's off because the cost outweighs it. To try it, add `"refreshInterval": 1` to `statusLine` in `~/.claude/settings.json`.

## Performance

Git state is cached 5 s and the codegraph probe 30 s, both keyed per directory, so switching repos never shows another repo's branch. Every subprocess has a timeout. Typical run is well under 50 ms.

## Credits

- Style and several ideas — the brand diamond, the gradient bar, hiding zero-valued segments — come from [kcchien/claude-code-statusline](https://github.com/kcchien/claude-code-statusline) (MIT).
- Palette is [Catppuccin Mocha](https://github.com/catppuccin/catppuccin).
- Icons need a [Nerd Font](https://www.nerdfonts.com/) (JetBrains Mono Nerd Font here); without one, set `SL_NO_NERD=1`.
- Payload reference: [Claude Code status line docs](https://code.claude.com/docs/en/statusline).
