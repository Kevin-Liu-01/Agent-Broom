---
name: agent-broom
description: Remember to run Agent Broom, the script-backed process tracking, audit, and cleanup tool. Use before starting another localhost server, before ending a turn that spawned long-running processes, when CPU/memory is high, when disk is low, or when the user says "what is running", "devclean", "orphaned MCP", "cleanup terminals", "localhosts out of control", or "free disk space".
---

# Agent Broom

This skill is the memory hook. It exists so agents remember to run the CLI.
The deterministic cleanup behavior lives in `bin/agent-broom`, `bin/ports`,
`bin/whoisonport`, and `lib/*.sh`.

Start with the port checker surface when the user asks what is running or when a
localhost port may be occupied:

```bash
bin/agent-broom ports --json
bin/agent-broom port <PORT> --json
bin/agent-broom ps --json
```

Run a dry-run audit first:

```bash
bin/agent-broom audit
```

Record long-running commands you start:

```bash
bin/agent-broom add --pid <PID> --kind dev --port <PORT> --purpose "<why>" -- <command>
```

Before ending the turn:

```bash
bin/agent-broom audit
```

Only act after reviewing the dry run:

```bash
bin/agent-broom kill <PORT|PID|RANGE>
bin/agent-broom kill --apply <PORT|PID|RANGE>
bin/agent-broom clean
bin/agent-broom clean --apply
bin/agent-broom stop --kill
bin/agent-broom artifacts --clean
bin/agent-broom devclean --apply
```

Never kill the editor, Codex, the user's shell, or shared MCP servers unless the
script proves they are safe orphaned targets.
