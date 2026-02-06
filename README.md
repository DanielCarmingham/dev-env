# dev-env

A Claude Code plugin for worktree-based development environment management with isolated databases, storage, and ports.

## Features

- **Git Worktree Integration**: Each environment gets its own worktree with an isolated branch
- **Isolated Databases**: Separate database per environment
- **Storage Isolation**: Environment-specific blob storage containers
- **Port Management**: Automatic port assignment to avoid conflicts
- **GitHub Integration**: Create environments from issue numbers
- **Lifecycle Hooks**: Customize setup/teardown with shell scripts
- **Extensible**: Adapter pattern for different databases, migration tools, and storage backends

## Installation

Add the marketplace and install the plugin (one-time per machine):

```bash
claude plugin marketplace add DanielCarmingham/dev-env
claude plugin install dev-env@DanielCarmingham-dev-env
```

Or from within Claude Code:

```
/plugin marketplace add DanielCarmingham/dev-env
```

Then install and enable `dev-env` from the `/plugin` manager.

Restart Claude Code after installation for the skills to take effect.

## Quick Start

1. Create a configuration file in your project:

```bash
# Copy the template for your project type
cp ~/.claude/plugins/cache/*/dev-env/*/templates/dotnet.yaml .claude/dev-env.yaml

# Edit to match your project
```

2. Run initial setup:

```bash
/dev-env:setup
```

3. Create a feature environment:

```bash
/dev-env:up my-feature
# or from GitHub issue
/dev-env:up 76
```

## Commands

| Command | Description |
|---------|-------------|
| `/dev-env:ls` | List all environments |
| `/dev-env:up <name\|issue#> [-o [cmd]]` | Create environment |
| `/dev-env:down [-f] <env>` | Remove environment |
| `/dev-env:finish [-p] [-s] <env>` | Merge to main and cleanup |
| `/dev-env:setup` | First-time project setup |

### Options

**up:**
- `-o, --open [cmd]` - Open worktree after creation (default: `open`, or specify `code` for VS Code)

**down:**
- `-f, --force` - Skip safety checks (uncommitted changes, unmerged commits)

**finish:**
- `-p, --pr` - Use PR workflow instead of direct merge
- `-s, --squash` - Squash commits into single commit (default: preserve history)

## Configuration

Create `.claude/dev-env.yaml` in your project root:

```yaml
version: "1.0"

project:
  name: my-project              # Used for directory/database naming

database:
  type: postgresql              # postgresql | mysql | sqlite
  prefix: my_project_           # Database name prefix
  connection:
    host: ${DEV_DB_HOST:-localhost}
    port: ${DEV_DB_PORT:-5432}
    user: ${DEV_DB_USER:-postgres}
    password: ${DEV_DB_PASSWORD:-postgres}

migrations:
  tool: efcore                  # efcore | prisma | django | custom
  efcore:
    projectPath: src/MyProject.Infrastructure
    startupProjectPath: src/MyProject.Web
    context: MyDbContext

storage:                        # Optional blob storage
  type: azurite
  containers:
    - pattern: "{env}-uploads"
    - pattern: "{env}-files"

ports:
  baseHttps: 50000
  baseHttp: 50100
  baseVite: 50200

hooks:                          # Lifecycle hooks (shell commands)
  pre-setup: ""
  post-database: ""
  post-migrate: ""
  post-setup: |
    dotnet run --project src/Web -- --seed-data
  pre-cleanup: ""

copyFiles:                      # Files to copy to worktree
  - src/Web/test-data.csv
```

### copyFiles

Copies files from the main repo into each new worktree. Useful for config files, test data, or secrets that aren't tracked in git.

```yaml
copyFiles:
  # Short form — same relative path in worktree
  - src/Web/test-data.csv

  # from-only — also keeps the same path (equivalent to above)
  - from: src/Web/test-data.csv

  # Explicit destination — when the worktree path should differ
  - from: config/template.json
    to: config/local.json
```

## Environment Variables

Configuration values can reference environment variables:

```yaml
database:
  connection:
    host: ${DEV_DB_HOST:-localhost}
    password: ${DEV_DB_PASSWORD:-secret}
```

You can set these in:
- `.infra.env` file in project root (automatically loaded)
- Shell environment
- CI/CD environment

## Extending

### Database Adapters

Add support for new databases by creating `lib/adapters/db-{type}.sh` implementing:

```bash
db_create(name, host, port, user, password)
db_drop(name, host, port, user, password)
db_exists(name, host, port, user, password)
db_wait_ready(host, port, user, password, max_wait)
```

### Migration Adapters

Add support for new migration tools by creating `lib/adapters/migrate-{tool}.sh` implementing:

```bash
migrate_run(project_root, env_name)
```

### Storage Adapters

Add support for new storage backends by creating `lib/adapters/storage-{type}.sh` implementing:

```bash
storage_create_container(name, connection)
storage_delete_container(name, connection)
```

## Worktree Layout

```
MyProject/                      # Main repository → my_project database
MyProject-feature-123/          # Worktree → my_project_feature_123 database
MyProject-fix-bug-456/          # Worktree → my_project_fix_bug_456 database
```

## Templates

The plugin includes templates for common project types:

- `dotnet.yaml` - .NET + EF Core + PostgreSQL

## License

MIT
