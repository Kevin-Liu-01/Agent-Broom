<p align="center">
  <img src="./assets/agent-broom-logo.svg" alt="Agent Broom logo" width="132" height="132">
</p>

<h1 align="center">Agent Broom</h1>

<p align="center">
  A skill that makes agents remember to run a cleanup script.
</p>

Agent Broom is for the boring mess that coding agents leave behind: localhost
servers, test watchers, orphaned MCP processes, browser automation, build
artifacts, and dev caches.

The design is intentionally split:

- **The skill is memory.** It tells the agent when to run cleanup.
- **The script is machinery.** It audits, reports, and only acts after review.

No giant prompt cleanup ritual. No guessing from `ps` after the fact. Run the
script, inspect the dry run, then choose whether to apply anything.

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

Everything risky is dry-run first. `stop` reports what it would stop unless you
pass `--kill`. `artifacts` reports reclaimable build/cache output unless you
pass `--clean`. `devclean` reports safe orphan/deep/optimize/disk targets unless
you pass `--apply`.

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

- recorded agent-owned processes
- localhost listeners that look like dev servers
- test/watch runners such as Vitest and Jest
- frontend/backend dev servers such as Next, Vite, Turbo, Bun, Uvicorn, and Rails
- automation browsers
- protected processes that should not be killed

Agent Broom protects editors, Codex, shells, and shared MCP servers such as
`playwright-mcp` and `chrome-devtools-mcp`.

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
