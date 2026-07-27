# cmux-skill

A single drop-in skill that teaches any AI coding agent how to drive **cmux** — the native macOS terminal for parallel AI agents — through its CLI and Unix-socket JSON-RPC API.

## Install

For agents that read `skills/` directories (Claude Code, Hermes, etc.), copy or symlink `SKILL.md` into your agent's skills folder:

```bash
# Claude Code
mkdir -p ~/.claude/skills/cmux
cp SKILL.md ~/.claude/skills/cmux/SKILL.md

# Hermes
mkdir -p ~/.hermes/skills/cmux
cp SKILL.md ~/.hermes/skills/cmux/SKILL.md
```

Or, project-local:

```bash
mkdir -p .claude/skills/cmux
cp SKILL.md .claude/skills/cmux/SKILL.md
```

Or use the manaflow installer:

```bash
npx skills add manaflow-ai/cmux -g -y
```

## What's in it

- Topology primitives (workspaces / panes / surfaces) and short-ref handles.
- Environment detection (`CMUX_WORKSPACE_ID`, `CMUX_SOCKET_PATH`).
- CLI cheats for creating panes, moving surfaces, sending input.
- Browser automation pattern (open → wait → snapshot → act).
- Notifications, status, progress, sidebar flashes.
- Socket JSON-RPC v2 entry point and access-mode pitfalls.
- The six **non-disruptive automation rules** that prevent agents from stealing the user's focus.

## When the agent should load it

- The user mentions cmux.
- The agent is being asked to control terminal layout from inside an automation loop.
- The agent needs to drive a browser surface on macOS.
- The agent wants to send notifications / flashes to the sidebar.
- The agent is being wired into cmux hooks.

## Requires

- cmux v0.64.0+ (`brew tap manaflow-ai/cmux && brew install --cask cmux`)
- macOS 14.0+

## License

MIT. Same as the parent bundle.
