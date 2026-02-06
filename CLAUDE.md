# dev-env Plugin Development

A Claude Code plugin for worktree-based development environment management.

## Structure

```
dev-env/
├── .claude-plugin/
│   └── plugin.json         # Plugin metadata
├── skills/
│   ├── up/SKILL.md         # /dev-env:up command
│   ├── down/SKILL.md       # /dev-env:down command
│   ├── ls/SKILL.md         # /dev-env:ls command
│   ├── finish/SKILL.md     # /dev-env:finish command
│   └── setup/SKILL.md      # /dev-env:setup command
├── lib/
│   ├── dev-env.sh          # Main entry point
│   ├── config.sh           # YAML config parsing
│   ├── core.sh             # Core utilities
│   └── adapters/
│       ├── db-postgresql.sh    # PostgreSQL adapter
│       ├── migrate-efcore.sh   # EF Core migrations
│       └── storage-azurite.sh  # Azurite blob storage
├── templates/
│   └── dotnet.yaml         # .NET project template
├── package.json
└── README.md
```

## Adding a New Database Adapter

1. Create `lib/adapters/db-{type}.sh`
2. Implement required functions:
   - `db_create(name, host, port, user, password)`
   - `db_drop(name, host, port, user, password)`
   - `db_exists(name, host, port, user, password)`
   - `db_wait_ready(host, port, user, password, max_wait)`
3. Update config validation if needed

## Adding a New Migration Adapter

1. Create `lib/adapters/migrate-{tool}.sh`
2. Implement: `migrate_run(project_root, env_name)`
3. Optionally implement: `migrate_add`, `migrate_remove`, `migrate_list`

## Testing

```bash
# Test help
./lib/dev-env.sh help

# Test in a project with .claude/dev-env.yaml
cd /path/to/project
/path/to/dev-env/lib/dev-env.sh ls
```

## Shell Scripts

- Always use LF line endings (not CRLF)
- After editing `.sh` files, verify with `file <script>.sh`
