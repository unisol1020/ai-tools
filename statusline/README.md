# statusline

A Claude Code status line built as **instrumentation for the current session** — two lines, one meter, no noise.

```
◆ Opus 5 1M · ▇ xhigh ·  claude-tools · ⎇ main ⇡2 ⇣ · ±7 · +312 -87 · ⬡ ok · PR#42 ● · 30m · PONYTAIL

████████████▋░░░░░░░  63% 167k/1M
```

**Line 1 — where you are.** Model, context window size, reasoning effort, thinking/fast mode, subagent or worktree, directory, branch with ahead/behind, changed-file count, lines added/removed, codegraph index state, open PR with review state, elapsed time.

**Line 2 — how full the context window is,** and nothing else: the meter, the percentage, and tokens used against the window size. A blank row separates it from the dense line above.

The meter fills in **eighth-blocks**, so it carries eight times the resolution of its twenty characters, on a green→yellow→red gradient. It stays small on purpose — it sits under a busy line, and a full-width bar swamps it. There is no label, because a bar that colour, in that place, needs no caption.

## Scope: this session only

No spend, no 5-hour window, no 7-day window — those are account-level and Orca already shows them. No prompt-cache or API-wait gauges either: if a number needs a caption to be understood, it isn't glanceable. Everything on both lines describes the session in front of you.

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
| `SL_GAP` | `1` | Blank row between the two lines. Set `0` to reclaim the terminal row. |

The layout is responsive: the meter shrinks to fit the width, and line 1 sheds segments by priority — the model, directory and PONYTAIL badge are the last to go.

### Animation (off by default)

The script can shimmer the meters and pulse the brand mark, but that needs `"refreshInterval": 1` in the `statusLine` block, which re-runs it **every second** (~40 ms of CPU per second). It's off because the cost outweighs it. To try it, add `"refreshInterval": 1` to `statusLine` in `~/.claude/settings.json`.

## Performance

Git state is cached 5 s and the codegraph probe 30 s, both keyed per directory, so switching repos never shows another repo's branch. Every subprocess has a timeout. Typical run is well under 50 ms.

## Credits

- Style and several ideas — the brand diamond, the gradient bar, hiding zero-valued segments — come from [kcchien/claude-code-statusline](https://github.com/kcchien/claude-code-statusline) (MIT).
- Palette is [Catppuccin Mocha](https://github.com/catppuccin/catppuccin).
- Icons need a [Nerd Font](https://www.nerdfonts.com/) (JetBrains Mono Nerd Font here); without one, set `SL_NO_NERD=1`.
- Payload reference: [Claude Code status line docs](https://code.claude.com/docs/en/statusline).
