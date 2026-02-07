---
description: Relaunch browser with remote debugging for an environment
allowed-tools: Bash(*/dev-env/lib/dev-env.sh*)
argument-hint: <env>
---

Relaunch the configured browser with remote debugging for an existing development environment.

Use this when Chrome was closed and you need to reopen it with the correct `--remote-debugging-port` and `--user-data-dir` for the chrome-devtools MCP to connect.

**Arguments:**
- `<env>` - Environment name (supports partial match)

**Examples:**
- `/dev-env:browser my-feature` - Relaunch browser for 'my-feature' environment
- `/dev-env:browser 76` - Relaunch using partial match (e.g., matches 'fix-bug-76')

**Run:**
`!$PLUGIN_DIR/lib/dev-env.sh browser $ARGUMENTS`

After launching, tell the user:
1. The debug port Chrome is running on
2. Remind them to restart Claude Code for MCP config changes to take effect
