---
description: Remove a development environment
allowed-tools: Bash(*/dev-env/lib/dev-env.sh*)
argument-hint: [-f] <env>
---

Remove a worktree environment including its database and storage containers.

**Arguments:**
- `<env>` - Environment name (supports partial match, e.g., `86` matches `fix-bug-86`)

**Options:**
- `-f, --force` - Skip safety checks (uncommitted changes, unmerged commits)

**Examples:**
- `/dev-env:down my-feature` - Remove environment 'my-feature'
- `/dev-env:down 86` - Remove environment matching '86'
- `/dev-env:down -f 86` - Force remove without safety checks

**Run:**
`!$PLUGIN_DIR/lib/dev-env.sh down $ARGUMENTS`
