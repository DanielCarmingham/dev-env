#!/bin/bash
# EF Core migration adapter for dev-env plugin
# Implements migration operations for Entity Framework Core

# Run EF Core migrations
# Usage: migrate_run <project_root> <env_name>
# Reads config for project paths and context name
migrate_run() {
    local project_root="$1"
    local env_name="$2"

    # Get migration settings from config
    local project_path=$(get_config "migrations.efcore.projectPath")
    local startup_path=$(get_config "migrations.efcore.startupProjectPath")
    local context=$(get_config "migrations.efcore.context")

    if [ -z "$project_path" ]; then
        echo "Error: migrations.efcore.projectPath not configured" >&2
        return 1
    fi

    if [ -z "$startup_path" ]; then
        echo "Error: migrations.efcore.startupProjectPath not configured" >&2
        return 1
    fi

    echo "Running EF Core migrations..."

    local cmd="dotnet ef database update"
    cmd="$cmd --project \"$project_root/$project_path\""
    cmd="$cmd --startup-project \"$project_root/$startup_path\""

    if [ -n "$context" ]; then
        cmd="$cmd --context $context"
    fi

    # Set DEV_ENV for connection string resolution
    DEV_ENV="$env_name" eval "$cmd"
}

# Add a new migration
# Usage: migrate_add <project_root> <migration_name>
migrate_add() {
    local project_root="$1"
    local migration_name="$2"

    local project_path=$(get_config "migrations.efcore.projectPath")
    local startup_path=$(get_config "migrations.efcore.startupProjectPath")
    local context=$(get_config "migrations.efcore.context")

    if [ -z "$migration_name" ]; then
        echo "Error: Migration name required" >&2
        return 1
    fi

    local cmd="dotnet ef migrations add \"$migration_name\""
    cmd="$cmd --project \"$project_root/$project_path\""
    cmd="$cmd --startup-project \"$project_root/$startup_path\""

    if [ -n "$context" ]; then
        cmd="$cmd --context $context"
    fi

    cd "$project_root"
    eval "$cmd"
}

# Remove the last migration
# Usage: migrate_remove <project_root> [--force]
migrate_remove() {
    local project_root="$1"
    local force="${2:-}"

    local project_path=$(get_config "migrations.efcore.projectPath")
    local startup_path=$(get_config "migrations.efcore.startupProjectPath")
    local context=$(get_config "migrations.efcore.context")

    local cmd="dotnet ef migrations remove"
    cmd="$cmd --project \"$project_root/$project_path\""
    cmd="$cmd --startup-project \"$project_root/$startup_path\""

    if [ -n "$context" ]; then
        cmd="$cmd --context $context"
    fi

    if [ "$force" = "--force" ]; then
        cmd="$cmd --force"
    fi

    cd "$project_root"
    eval "$cmd"
}

# List migrations
# Usage: migrate_list <project_root>
migrate_list() {
    local project_root="$1"

    local project_path=$(get_config "migrations.efcore.projectPath")
    local startup_path=$(get_config "migrations.efcore.startupProjectPath")
    local context=$(get_config "migrations.efcore.context")

    local cmd="dotnet ef migrations list"
    cmd="$cmd --project \"$project_root/$project_path\""
    cmd="$cmd --startup-project \"$project_root/$startup_path\""

    if [ -n "$context" ]; then
        cmd="$cmd --context $context"
    fi

    cd "$project_root"
    eval "$cmd"
}

# Generate SQL script for migrations
# Usage: migrate_script <project_root> [from] [to] [--idempotent]
migrate_script() {
    local project_root="$1"
    shift
    local args="$@"

    local project_path=$(get_config "migrations.efcore.projectPath")
    local startup_path=$(get_config "migrations.efcore.startupProjectPath")
    local context=$(get_config "migrations.efcore.context")

    local cmd="dotnet ef migrations script"
    cmd="$cmd --project \"$project_root/$project_path\""
    cmd="$cmd --startup-project \"$project_root/$startup_path\""

    if [ -n "$context" ]; then
        cmd="$cmd --context $context"
    fi

    if [ -n "$args" ]; then
        cmd="$cmd $args"
    fi

    cd "$project_root"
    eval "$cmd"
}
