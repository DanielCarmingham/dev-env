---
description: Create a new development environment
allowed-tools: Bash(*/dev-env/lib/dev-env.sh*)
argument-hint: <name|issue#> [-o [cmd]]
---

Create a new worktree-based development environment with isolated database, storage, and ports.

**Arguments:**
- `<name>` - Branch name to create (e.g., `my-feature`)
- `<issue#>` - GitHub issue number (e.g., `76`) - fetches issue title to generate branch name

**Options:**
- `-o, --open [cmd]` - Open worktree after creation (default: `open`, or specify `code` for VS Code)

**Examples:**
- `/dev-env:up my-feature` - Create environment with branch 'my-feature'
- `/dev-env:up 76` - Create environment from GitHub issue #76
- `/dev-env:up 76 -o code` - Create and open in VS Code

**Run:**
`!$PLUGIN_DIR/lib/dev-env.sh up $ARGUMENTS`

After creation, tell the user:
1. The worktree path
2. How to run the application
3. The assigned ports
