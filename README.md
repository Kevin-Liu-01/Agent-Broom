<p align="center">
  <img src="./assets/agent-broom-logo.svg" alt="Agent Broom logo" width="132" height="132">
</p>

<h1 align="center">Agent Broom</h1>

<p align="center">
  Ports first. Cleanup second. Safe for agents to call.
</p>

<p align="center">
  <img src="./assets/agent-broom-terminal.png" alt="Agent Broom cleaning up localhost dev servers in a terminal" width="860">
</p>

Agent Broom is for the boring mess that coding agents leave behind: localhost
servers, test watchers, orphaned MCP processes, browser automation, build
artifacts, and dev caches. It starts with the same simple job that made
[port-whisperer](https://github.com/LarsenCundric/port-whisperer) useful:
answer "what is running on my ports?" quickly, then expose safe cleanup actions
that an agent can call.

```bash
agent-broom ports --json
agent-broom port 3000 --json
agent-broom kill 3000-3010        # dry run
agent-broom stop --kill           # only recorded agent-owned process groups
```

The design is intentionally split:

- **The skill is memory.** It tells the agent when to run cleanup.
- **The script is machinery.** It audits, reports, and only acts after review.

No giant prompt cleanup ritual. No guessing from `ps` after the fact. Run the
CLI, inspect the dry run, then choose whether to apply anything.

## Port Checker First

Agent Broom is intentionally useful before you install any agent skill. It can
stand alone as a small CLI for answering "what owns this port?" and "what can I
safely clean up?"

```bash
agent-broom ports
agent-broom ports --all
agent-broom ports --json
agent-broom port 3000 --json
agent-broom ps
agent-broom ps --json
agent-broom kill 3000-3010        # dry run
agent-broom kill --apply 3000     # terminate listener/process group
agent-broom logs 3000 --lines 25
agent-broom clean                 # dry run orphan/zombie dev listeners
agent-broom watch
```

Short aliases are installed too:

```bash
ports
whoisonport 3000
```

`port-whisperer` optimizes for a polished human table. Agent Broom keeps that
shape but adds agent safety: JSON output, dry-run kills by default, a process
ledger, protected MCP/editor rules, artifact cleanup, and repo-scoped stop/prune
commands.

## Why Agents Need This

Agents are good at starting servers and bad at remembering every process they
started. Agent Broom gives them a deterministic loop:

1. Audit ports before work.
2. Record long-running processes when they start.
3. Inspect dry-run cleanup before acting.
4. Stop only owned process groups.
5. Re-audit before ending the task.

That loop is script-backed, not prompt magic.

## Install

Clone the repo:

```bash
git clone https://github.com/Kevin-Liu-01/agent-broom.git
cd agent-broom
```

Run directly:

```bash
bin/agent-broom audit
```

Or add the `bin` directory to your shell path:

```bash
export PATH="$PWD/bin:$PATH"
agent-broom audit
```

## Commands

```bash
agent-broom list
agent-broom audit
agent-broom ports [--all] [--json]
agent-broom port <PORT> [--json]
agent-broom ps [--all] [--json]
agent-broom kill [--apply] [--force] <PORT|PID|RANGE>...
agent-broom logs <PORT|PID> [--lines N] [--follow]
agent-broom clean [--apply] [--json]
agent-broom watch [--interval SEC]
agent-broom add --pid <PID> --kind dev --port <PORT> --purpose "<why>" -- <command>
agent-broom stop
agent-broom stop --kill
agent-broom prune
agent-broom artifacts
agent-broom artifacts --clean
agent-broom devclean
agent-broom devclean --deep
agent-broom devclean --optimize
agent-broom devclean --disk
agent-broom devclean --apply
agent-broom doctor
```

Everything risky is dry-run first. `kill` and `clean` report what they would
terminate unless you pass `--apply`. `stop` reports what it would stop unless
you pass `--kill`. `artifacts` reports reclaimable build/cache output unless
you pass `--clean`. `devclean` reports safe orphan/deep/optimize/disk targets
unless you pass `--apply`.

## What It Tracks

`agent-broom add` records long-running processes in:

```text
~/.cache/agent-processes/ledger.tsv
```

Each entry includes repo root, cwd, PID, PGID, kind, port, purpose, and command.
That means the next agent can see what is running and why before starting yet
another server on `localhost:3000`.

## What It Audits

`agent-broom audit` reports:

- active localhost listeners with project/framework/process context
- recorded agent-owned processes
- localhost listeners that look like dev servers
- test/watch runners such as Vitest and Jest
- frontend/backend dev servers such as Next, Vite, Turbo, Bun, Uvicorn, and Rails
- automation browsers
- protected processes that should not be killed

Agent Broom protects editors, Codex, shells, and shared MCP servers such as
`playwright-mcp` and `chrome-devtools-mcp`.

## Tested Agent Flow

The CLI has been tested as an agent harness:

- start a temporary localhost server;
- record it with `agent-broom add`;
- inspect it with `agent-broom port <port> --json`;
- dry-run `agent-broom stop`;
- apply `agent-broom stop --kill`;
- verify the port is gone.

## Agent JSON Contracts

Use JSON when another agent or script needs deterministic parsing:

```bash
agent-broom ports --json
agent-broom port 3000 --json
agent-broom ps --json
agent-broom clean --json
```

Successful JSON responses use `{ "ok": true, ... }`; missing ports use
`{ "ok": false, "error": { "code": "port_not_found", ... } }`.

## Devclean Mode

`agent-broom devclean` borrows the useful shape of `devclean`: safe orphan
cleanup, explicit deep cleanup, optimize mode, and disk mode.

```bash
agent-broom devclean
agent-broom devclean --deep
agent-broom devclean --optimize
agent-broom devclean --disk
```

It is conservative by default. It does not treat every `crashpad_handler` as a
safe orphan because normal active apps on macOS use those helpers. Crashpad file
cleanup and crash reporter settings live behind `--optimize`, where you can
review the exact targets first.

Thanks to [ImL1s/devclean](https://github.com/ImL1s/devclean) for the excellent
shape of this part of the tool: safe cleanup by default, explicit deep cleanup,
optimize mode, and disk mode. Agent Broom keeps that spirit and adds the agent
memory hook plus process ledger.

## Artifact Cleanup

`agent-broom artifacts` reports rebuildable repo artifacts:

- `.turbo`, `.vite`, `.cache`, `node_modules/.cache`
- `.next`, `dist`, `build`, `out`, `.output`
- `*.tsbuildinfo`, `.eslintcache`
- `coverage`, `test-results`, `playwright-report`

It skips git-tracked paths and nested git repositories.

## Agent Skill

The reusable agent memory hook lives in:

```text
skill/SKILL.md
```

Install or copy that skill into your agent environment if you want the agent to
remember the cleanup loop automatically. The skill should stay small. The script
does the work.

## Safety Model

- Dry-run by default.
- Kill by process group only after ownership is clear.
- Prefer SIGTERM, then SIGKILL only for stragglers.
- Never kill the editor, Codex, the user's shell, or shared MCP servers unless
  the script proves they are safe orphaned targets.
- Delete only known rebuildable artifacts.

## License

MIT
