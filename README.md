# AI Agent Hook Framework

A lightweight, dependency-free Bash framework for sandboxing and monitoring AI coding
agents (like Claude Code) via lifecycle hooks - no `jq`, no runtime, just shell and pure vibes.

Hooks intercept an agent's actions at three points:

- **PreToolUse** - runs *before* a tool executes (e.g. before a Bash command). Can
  **block** the action by exiting `2`.
- **PostToolUse** - runs *after* a tool executes (e.g. after a file edit). Used for
  logging, backups, or validation side effects.
- **Stop** - runs when an agent session ends. Used for reporting or cleanup.

Each hook reads a JSON payload from `stdin` and communicates purely through exit
codes and stderr/stdout - the same contract used by
[Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks).

This repo is being built incrementally: one hook per commit, each backed by its own
test file and validated by CI before the next one is added.

## Why this exists

Giving an AI agent shell access is powerful and a little terrifying. This framework
is a deterministic guardrail layer that sits between the agent and your system -
things like "never let it read `.env`," "block `rm -rf`," or "keep a rolling backup
of everything it edits" - enforced by plain Bash, not by asking the model nicely.

## Status

🚧 Work in progress. Hooks are being added one at a time. See the checklist below.

| Hook | Type | Status |
|---|---|---|
| `pre_secrets_guard.sh` | PreToolUse | ✅ |
| `pre_command_firewall.sh` | PreToolUse | ✅ |
| `pre_rate_limiter.sh` | PreToolUse | ✅ |
| `pre_commit_validator.sh` | PreToolUse | ✅ |
| `post_auto_backup.sh` | PostToolUse | ✅ |
| `post_syntax_checker.sh` | PostToolUse | ⬜ not yet added |
| `post_session_summary.sh` | Stop | ⬜ not yet added |
| `hook_runner.sh` (wiring) | — | ⬜ not yet added |

## Project structure

```
.
├── hook_runner.sh              # Standalone simulator — runs hooks without a live agent
├── hooks_config.txt            # event:tool:script routing table for the runner
├── .claude/
│   ├── settings.json           # Wires hooks into a real Claude Code session (optional)
│   └── hooks/
│       ├── <hook_name>.sh
│       ├── config/              # Per-hook config (patterns, thresholds, allow/deny lists)
│       └── data/                 # Runtime state — backups, logs, counters (gitignored)
├── tests/
│   ├── run_all.sh               # Discovers and runs every test file
│   └── NN_<hook_name>.sh        # One test file per hook
└── .github/workflows/ci.yml     # Lint (shellcheck) + tests on every push
```

## Usage

Simulate a hook event without needing a live AI agent:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"session_id":"s1"}' \
    | ./hook_runner.sh PreToolUse Bash
```

Run a single hook directly:

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":".env"}}' \
    | bash .claude/hooks/pre_secrets_guard.sh && echo ALLOWED || echo BLOCKED
```

Run the full test suite locally:

```bash
bash tests/run_all.sh
```

## Contract

| Exit code | Meaning |
|---|---|
| `0` | Allow / success |
| `2` | **Block** the action (`PreToolUse` only) - reason printed to `stderr` |
| `1` | Warning, non-fatal - action proceeds |
| other | Error - treated as a warning |

## Using this with a real agent

Copy `.claude/` into any project directory. `.claude/settings.json` wires the hooks
into Claude Code automatically — open Claude Code in that directory and run
`/hooks` to confirm they're loaded.

## Contributing

Each hook is added as its own commit with a matching test file under `tests/`.
CI (GitHub Actions) lints every script with `shellcheck` and runs the full test
suite on every push — see badge above once CI is wired up.
