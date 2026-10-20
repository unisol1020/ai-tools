#!/usr/bin/env bash
# SessionStart: MemPalace's capture hook plus the wake-up text for the repo you are in.
exec bash "$(dirname "${BASH_SOURCE[0]}")/mempalace-hook.sh" session-start
