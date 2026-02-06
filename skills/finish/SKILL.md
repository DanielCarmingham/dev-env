---
description: Merge environment to main and cleanup
allowed-tools: Bash(*/dev-env/lib/dev-env.sh*)
argument-hint: [-p] [-s] <env>
---

Merge a feature branch to main and remove the development environment.

**Arguments:**
- `<env>` - Environment name (supports partial match)

**Options:**
- `-p, --pr` - Use GitHub PR workflow instead of direct merge
- `-s, --squash` - Squash commits into single commit (default: preserve commit history)

**Workflow:**
1. Checks for uncommitted changes
2. Merges branch to main (or creates/merges PR with `-p`)
3. Deletes the feature branch
4. Removes the environment (database, storage, worktree)

**Examples:**
- `/dev-env:finish 86` - Merge preserving commits, cleanup
- `/dev-env:finish -s 86` - Squash merge, cleanup
- `/dev-env:finish -p 86` - Create/check PR, merge when approved

**Run:**
`!$PLUGIN_DIR/lib/dev-env.sh finish $ARGUMENTS`
