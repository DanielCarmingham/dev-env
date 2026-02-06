---
description: First-time project setup
allowed-tools: Bash(*/dev-env/lib/dev-env.sh*)
---

Initialize the main development environment for first-time setup.

**What it does:**
1. Starts infrastructure containers (Docker)
2. Creates the main database
3. Runs migrations
4. Executes post-setup hooks (e.g., seeding test users)

**Prerequisites:**
- Docker Desktop running
- `.claude/dev-env.yaml` configuration file

**Run:**
`!$PLUGIN_DIR/lib/dev-env.sh setup`
