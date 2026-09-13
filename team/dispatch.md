<!-- ai-tools:dispatch:start -->
## Agent dispatch (ai-tools)

Route on intent, not on the agent's name — the user rarely says "manual-qa". Spawn the agent without asking, and say which one you dispatched:

- "test this", "check it works", "verify the flow", "does it look right", "QA this", "reproduce the bug" → run the **qa-run** skill (it resolves URL + login, then spawns **manual-qa**). Spawn manual-qa directly only when URL + creds are already known.
- "plan this", "how should we build this", "let's design", "add/implement <feature>" spanning several files or frontend ↔ backend → **architect**. Never hand-write the plan.
- "fix/change this on the frontend", "looks bad on the client", "the screen/form/button is broken", "match the Figma" → **frontend-engineer**.
- "fix/do this in the api / backend", "add an endpoint", "migration", "job", "webhook" → **backend-engineer**.
- "write tests", "cover this", "regression test", and after any feature or fix lands → **automation-qa**.
- After code changes, before merge → **backend-reviewer** / **frontend-reviewer** for the changed tree; **security-reviewer** whenever auth, input, data access, secrets or webhooks are touched.
- A mixed ask runs the chain in order (architect → engineers → automation-qa → reviewers → qa-run); a one-file tweak needs no agent.
- **A ticket is intent too.** When the task comes from a Linear/Jira issue, a PR, a Slack thread or an Orca workspace, classify it by its symptom and the code it will touch, not by its wording: a visual or interaction symptom → frontend-engineer; endpoint, data, job or webhook → backend-engineer; touches both, or scope is unclear → architect first; a bug report with repro steps and a running app → qa-run reproduces it before anyone fixes it. Then the same chain as above.
- **You decide, not the phrasing.** Subagents are pre-authorized: at any point, spawn whichever agent the task needs, in sequence or in parallel, without asking. Name the agent and the reason in one line when you do.
<!-- ai-tools:dispatch:end -->
