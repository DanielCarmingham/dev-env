#!/bin/bash
# dev-env: Development environment management with git worktree support
# Main entry point for the dev-env plugin
#
# Usage: dev-env <command> [args]
#
# Commands:
#   ls                      List all environments
#   up <name|issue#> [-o]   Create environment
#   browser <env>            Relaunch browser with remote debugging
#   finish [-p] [-s] <env>  Merge to main and cleanup
#   down [-f] <env>         Remove environment
#   setup                   First-time setup
#   help                    Show full help

set -e

# Resolve script directory for sourcing other modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/core.sh"

# Find project root (directory containing .claude/dev-env.yaml)
find_project_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.claude/dev-env.yaml" ]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    echo "Error: No .claude/dev-env.yaml found in current directory or parents" >&2
    return 1
}

# Load database adapter based on config
load_db_adapter() {
    local db_type=$(get_config "database.type" "postgresql")
    local adapter_file="$SCRIPT_DIR/adapters/db-${db_type}.sh"

    if [ ! -f "$adapter_file" ]; then
        echo "Error: Unknown database type '$db_type'. Adapter not found: $adapter_file" >&2
        return 1
    fi

    source "$adapter_file"
}

# Load migration adapter based on config
load_migrate_adapter() {
    local tool=$(get_config "migrations.tool" "")
    if [ -z "$tool" ]; then
        return 0  # No migrations configured
    fi

    local adapter_file="$SCRIPT_DIR/adapters/migrate-${tool}.sh"

    if [ ! -f "$adapter_file" ]; then
        echo "Error: Unknown migration tool '$tool'. Adapter not found: $adapter_file" >&2
        return 1
    fi

    source "$adapter_file"
}

# Load storage adapter based on config
load_storage_adapter() {
    local storage_type=$(get_config "storage.type" "")
    if [ -z "$storage_type" ]; then
        return 0  # No storage configured
    fi

    local adapter_file="$SCRIPT_DIR/adapters/storage-${storage_type}.sh"

    if [ ! -f "$adapter_file" ]; then
        echo "Error: Unknown storage type '$storage_type'. Adapter not found: $adapter_file" >&2
        return 1
    fi

    source "$adapter_file"
}

# Load browser adapter based on config
load_browser_adapter() {
    local browser_type=$(get_config "browser.type" "")
    if [ -z "$browser_type" ]; then
        return 0  # No browser configured
    fi

    local adapter_file="$SCRIPT_DIR/adapters/browser-${browser_type}.sh"

    if [ ! -f "$adapter_file" ]; then
        echo "Error: Unknown browser type '$browser_type'. Adapter not found: $adapter_file" >&2
        return 1
    fi

    source "$adapter_file"
}

# Process auto-open entries from config
# Runs each pipe-delimited command with the worktree path as argument
run_open_entries() {
    local worktree_path="$1"

    local open_entries=$(get_config "open" "")
    [ -z "$open_entries" ] && return 0

    # Split pipe-delimited entries
    echo "$open_entries" | tr '|' '\n' | while IFS= read -r entry; do
        entry=$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$entry" ] && continue

        echo "Opening with: $entry $worktree_path"
        "$entry" "$worktree_path" 2>/dev/null || echo "  Warning: Failed to run '$entry'" >&2
    done
}

# Launch the configured browser with remote debugging
start_browser() {
    local worktree_path="$1"
    local env_name="$2"

    [ -z "$(get_config 'browser.type')" ] && return 0

    local start_url=$(get_config "browser.startUrl" "")
    if browser_check_conflicts; then
        browser_start "$env_name" "$DEBUG_PORT" "$start_url"
        browser_update_mcp "$worktree_path" "$DEBUG_PORT"
    else
        echo "  Skipping browser launch (close existing instances and use 'dev-env browser' to retry)"
    fi
}

# Ensure Docker is running
ensure_docker() {
    if ! docker info &>/dev/null; then
        echo "Error: Docker is not running. Please start Docker Desktop." >&2
        return 1
    fi
}

# Ensure infrastructure containers are running
ensure_containers() {
    local project_root="$1"

    ensure_docker

    # Check for docker-compose file
    if [ -f "$project_root/docker-compose.yml" ]; then
        if ! docker ps 2>/dev/null | grep -q postgres; then
            echo "Starting infrastructure containers..."
            docker-compose -f "$project_root/docker-compose.yml" up -d

            # Wait for database to be ready
            local host=$(get_config "database.connection.host" "localhost")
            local port=$(get_config "database.connection.port" "5432")
            local user=$(get_config "database.connection.user" "postgres")
            local password=$(get_config "database.connection.password" "postgres")

            db_wait_ready "$host" "$port" "$user" "$password"
        fi
    fi
}

#
# Commands
#

cmd_help() {
    cat << 'EOF'
Development environment management

Usage: dev-env <command> [args]

Commands:
  ls                       List all environments
  up <name|issue#> [-o]    Create environment
  browser <env>             Relaunch browser with remote debugging
  finish [opts] <env>      Merge to main and cleanup
  down [opts] <env>        Remove environment
  setup                    First-time setup
  help                     Show this help

Arguments:
  <name|issue#>  Branch name ("my-feature") or GitHub issue number ("76")
  <env>          Existing environment - supports partial match

Options:
  up:
    -o, --open [cmd]     Open after creation (default: open)

  down:
    -f, --force          Skip safety checks

  finish:
    -p, --pr             Use PR workflow instead of direct merge
    -s, --squash         Squash commits into single commit

Configuration:
  Create .claude/dev-env.yaml in your project root.
  See templates/ for examples.

Each environment includes:
  - Git worktree (sibling directory with isolated branch)
  - Database (project-specific)
  - Blob storage containers (if configured)
  - Chrome with remote debugging (if configured)
  - Unique development ports
EOF
}

cmd_ls() {
    local project_root=$(find_project_root) || exit 1
    load_config "$project_root"
    list_environments "$project_root"
}

cmd_setup() {
    local project_root=$(find_project_root) || exit 1
    load_config "$project_root"
    load_db_adapter
    load_migrate_adapter

    local project_name=$(get_config "project.name")

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              ${project_name^^} - FIRST-TIME SETUP"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Ensure infrastructure
    ensure_containers "$project_root"
    echo "  ✓ Infrastructure running"
    echo ""

    # Get database settings
    local db_prefix=$(get_config "database.prefix")
    local db_name="${db_prefix}${project_name//-/_}"
    local db_host=$(get_config "database.connection.host" "localhost")
    local db_port=$(get_config "database.connection.port" "5432")
    local db_user=$(get_config "database.connection.user" "postgres")
    local db_password=$(get_config "database.connection.password" "postgres")

    # Check/create database
    echo "Checking database..."
    if db_exists "$db_name" "$db_host" "$db_port" "$db_user" "$db_password"; then
        echo "  ✓ Database '$db_name' already exists"
    else
        db_create "$db_name" "$db_host" "$db_port" "$db_user" "$db_password"
        echo "  ✓ Database created"
    fi
    echo ""

    # Run migrations
    if [ -n "$(get_config 'migrations.tool')" ]; then
        echo "Running migrations..."
        migrate_run "$project_root" ""
        echo "  ✓ Migrations applied"
        echo ""
    fi

    # Execute post-setup hook
    local hook=$(get_config "hooks.post-setup")
    if [ -n "$hook" ]; then
        echo "Running post-setup hook..."
        cd "$project_root"
        execute_hook "post-setup" "$hook"
        echo ""
    fi

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                     SETUP COMPLETE!                                ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
}

cmd_up() {
    local project_root=$(find_project_root) || exit 1
    load_config "$project_root"
    load_db_adapter
    load_migrate_adapter
    load_storage_adapter
    load_browser_adapter

    local open_with=""
    local input=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--open)
                shift
                if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
                    open_with="$1"
                    shift
                else
                    open_with="open"
                fi
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    if [ -z "$input" ]; then
        echo "Usage: dev-env up <name|issue#> [-o [cmd]]" >&2
        exit 1
    fi

    # Ensure infrastructure
    ensure_containers "$project_root"

    # Reject "main" as it's reserved
    local input_lower=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    if [[ "$input_lower" == "main" ]]; then
        echo "Error: 'main' is reserved. Use 'dev-env setup' for the main repo." >&2
        exit 1
    fi

    # Strip leading # from issue numbers
    input="${input#\#}"

    local branch=""

    # Determine if input is a number (GitHub issue) or string (branch name)
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if ! fetch_issue "$input"; then
            exit 1
        fi

        echo ""
        echo "Issue #$ISSUE_NUMBER: $ISSUE_TITLE"

        # Check for existing branch for this issue
        local existing_branch
        existing_branch=$(find_existing_issue_branch "$project_root" "$ISSUE_NUMBER" || true)
        if [ -n "$existing_branch" ]; then
            echo "Using existing branch: $existing_branch"
            branch="$existing_branch"
        else
            branch=$(generate_branch_name_from_issue "$ISSUE_TITLE" "$ISSUE_NUMBER")
            echo "Creating branch: $branch"
        fi
        echo ""
    else
        branch=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr '/' '-')
    fi

    # Environment name is the branch name
    local env_name=$(echo "$branch" | tr '/' '-')
    env_name=$(validate_env_name "$env_name") || exit 1

    # Get config values
    local db_prefix=$(get_config "database.prefix")
    local db_name="${db_prefix}${env_name//-/_}"
    local db_host=$(get_config "database.connection.host" "localhost")
    local db_port=$(get_config "database.connection.port" "5432")
    local db_user=$(get_config "database.connection.user" "postgres")
    local db_password=$(get_config "database.connection.password" "postgres")

    # Calculate ports
    calculate_ports "$project_root" "$env_name"

    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    echo ""
    echo "Creating environment: $env_name"
    echo "  Worktree:   $worktree_path"
    echo "  Database:   $db_name"
    echo "  Ports:      https://localhost:$HTTPS_PORT, http://localhost:$HTTP_PORT"
    echo ""

    # Execute pre-setup hook
    execute_hook "pre-setup" "$(get_config 'hooks.pre-setup')"

    # Create worktree
    echo "Creating git worktree..."
    if ! create_worktree "$project_root" "$env_name" "$branch"; then
        exit 1
    fi
    echo ""

    # Create database
    if ! db_create "$db_name" "$db_host" "$db_port" "$db_user" "$db_password"; then
        echo "Cleaning up worktree..."
        remove_worktree "$project_root" "$env_name"
        exit 1
    fi

    # Execute post-database hook
    execute_hook "post-database" "$(get_config 'hooks.post-database')"

    # Create storage containers
    if [ -n "$(get_config 'storage.type')" ]; then
        echo "Creating storage containers..."
        local storage_conn=$(get_storage_connection_string)
        storage_create_containers_from_config "$env_name" "$storage_conn"
    fi

    # Build project (if configured)
    local build_cmd=$(get_config "build.command")
    if [ -n "$build_cmd" ]; then
        echo "Building project..."
        cd "$worktree_path"
        eval "$build_cmd" || {
            echo "Error: Build failed. Cleaning up..." >&2
            db_drop "$db_name" "$db_host" "$db_port" "$db_user" "$db_password"
            remove_worktree "$project_root" "$env_name"
            exit 1
        }
    fi

    # Run migrations
    if [ -n "$(get_config 'migrations.tool')" ]; then
        echo "Running migrations..."
        cd "$worktree_path"
        DEV_ENV="$env_name" migrate_run "$worktree_path" "$env_name" || {
            echo "Error: Migrations failed. Cleaning up..." >&2
            db_drop "$db_name" "$db_host" "$db_port" "$db_user" "$db_password"
            remove_worktree "$project_root" "$env_name"
            exit 1
        }
    fi

    # Execute post-migrate hook
    execute_hook "post-migrate" "$(get_config 'hooks.post-migrate')"

    # Generate files from templates
    local generate_files=$(get_config_array "generateFiles")
    # This would need more complex YAML parsing - simplified for now

    # Copy files from main repo to worktree
    copy_files_to_worktree "$project_root" "$worktree_path"

    # Execute post-setup hook
    local post_setup=$(get_config "hooks.post-setup")
    if [ -n "$post_setup" ]; then
        echo "Running post-setup hook..."
        cd "$worktree_path"
        DEV_ENV="$env_name" execute_hook "post-setup" "$post_setup"
    fi

    echo ""
    echo "========================================"
    echo "Environment '$env_name' is ready!"
    echo "========================================"
    echo ""
    echo "Worktree: $worktree_path"
    if [ -n "$(get_config 'browser.type')" ]; then
        echo "Debug port: $DEBUG_PORT"
    fi
    echo ""

    # Set terminal title
    set_terminal_title "$env_name"

    # Launch browser with remote debugging (if configured)
    start_browser "$worktree_path" "$env_name"

    # Auto-open configured entries (editors/tools)
    run_open_entries "$worktree_path"

    # Also open if -o flag was passed (in addition to auto-open)
    if [ -n "$open_with" ]; then
        echo "Opening with: $open_with $worktree_path"
        "$open_with" "$worktree_path"
    fi
}

cmd_down() {
    local project_root=$(find_project_root) || exit 1
    load_config "$project_root"
    load_db_adapter
    load_storage_adapter
    load_browser_adapter

    local force=false
    local input=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                force=true
                shift
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    if [ -z "$input" ]; then
        echo "Usage: dev-env down [-f|--force] <env-name>"
        echo ""
        echo "Available environments:"
        list_environments "$project_root"
        exit 1
    fi

    # Find environment by partial match
    find_env_by_partial "$project_root" "$input"

    if [ "$MATCH_COUNT" -eq 0 ]; then
        echo "Error: No environment matching '$input' found." >&2
        exit 1
    elif [ "$MATCH_COUNT" -gt 1 ]; then
        echo "Error: Multiple environments match '$input':" >&2
        for match in "${MATCHES[@]}"; do
            echo "  $match" >&2
        done
        exit 1
    fi

    local env_name="${MATCHES[0]}"

    if [ "$input" != "$env_name" ]; then
        echo "Matched: $env_name"
    fi

    # Get config values
    local db_prefix=$(get_config "database.prefix")
    local db_name="${db_prefix}${env_name//-/_}"
    local db_host=$(get_config "database.connection.host" "localhost")
    local db_port=$(get_config "database.connection.port" "5432")
    local db_user=$(get_config "database.connection.user" "postgres")
    local db_password=$(get_config "database.connection.password" "postgres")

    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    echo ""
    echo "Removing environment: $env_name"
    echo "  Worktree:   $worktree_path"
    echo "  Database:   $db_name"
    echo ""

    # Safety check
    if [ "$force" = false ]; then
        if ! check_worktree_safety "$project_root" "$env_name"; then
            echo ""
            echo "To force removal, run:"
            echo "  dev-env down --force $env_name"
            exit 1
        fi
    fi

    # Execute pre-cleanup hook
    execute_hook "pre-cleanup" "$(get_config 'hooks.pre-cleanup')"

    # Remove worktree
    remove_worktree "$project_root" "$env_name"
    echo ""

    # Drop database
    db_drop "$db_name" "$db_host" "$db_port" "$db_user" "$db_password"

    # Delete storage containers
    if [ -n "$(get_config 'storage.type')" ]; then
        echo "Deleting storage containers..."
        local storage_conn=$(get_storage_connection_string)
        storage_delete_containers_for_env "$env_name" "$storage_conn"
    fi

    # Stop browser and clean up MCP config
    if [ -n "$(get_config 'browser.type')" ]; then
        echo "Stopping browser..."
        browser_stop "$env_name"
        browser_clean_mcp "$worktree_path"
    fi

    echo ""
    echo "Environment '$env_name' removed."
}

cmd_browser() {
    local project_root=$(find_project_root) || exit 1
    load_config "$project_root"
    load_browser_adapter

    if [ -z "$(get_config 'browser.type')" ]; then
        echo "Error: No browser configured in dev-env.yaml" >&2
        echo "Add a 'browser:' section with 'type: chrome' to enable." >&2
        exit 1
    fi

    local input=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    if [ -z "$input" ]; then
        echo "Usage: dev-env browser <env-name>"
        echo ""
        echo "Available environments:"
        list_environments "$project_root"
        exit 1
    fi

    # Find environment by partial match
    find_env_by_partial "$project_root" "$input"

    if [ "$MATCH_COUNT" -eq 0 ]; then
        echo "Error: No environment matching '$input' found." >&2
        exit 1
    elif [ "$MATCH_COUNT" -gt 1 ]; then
        echo "Error: Multiple environments match '$input':" >&2
        for match in "${MATCHES[@]}"; do
            echo "  $match" >&2
        done
        exit 1
    fi

    local env_name="${MATCHES[0]}"
    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    if [ "$input" != "$env_name" ]; then
        echo "Matched: $env_name"
    fi

    # Calculate ports (needed for debug port)
    calculate_ports "$project_root" "$env_name"

    echo ""
    start_browser "$worktree_path" "$env_name"
}

cmd_finish() {
    local project_root=$(find_project_root) || exit 1
    load_config "$project_root"

    local use_pr=false
    local squash=false
    local input=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--pr)
                use_pr=true
                shift
                ;;
            -s|--squash)
                squash=true
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    if [ -z "$input" ]; then
        echo "Usage: dev-env finish [-p] [-s] <env>"
        echo ""
        echo "Available environments:"
        list_environments "$project_root"
        exit 1
    fi

    # Find environment
    find_env_by_partial "$project_root" "$input"

    if [ "$MATCH_COUNT" -eq 0 ]; then
        echo "Error: No environment matching '$input' found." >&2
        exit 1
    elif [ "$MATCH_COUNT" -gt 1 ]; then
        echo "Error: Multiple environments match '$input':" >&2
        for match in "${MATCHES[@]}"; do
            echo "  $match" >&2
        done
        exit 1
    fi

    local env_name="${MATCHES[0]}"
    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    if [ "$input" != "$env_name" ]; then
        echo "Matched: $env_name"
    fi

    # Check worktree exists
    if [ ! -d "$worktree_path" ]; then
        echo "Error: Worktree not found: $worktree_path" >&2
        exit 1
    fi

    cd "$worktree_path"

    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "Error: Uncommitted changes in $env_name" >&2
        echo "Commit or stash your changes first." >&2
        exit 1
    fi

    local branch_name=$(git rev-parse --abbrev-ref HEAD)

    if [ "$use_pr" = false ]; then
        # Direct merge workflow
        echo ""
        if [ "$squash" = true ]; then
            echo "Squash merge: $branch_name → main"
        else
            echo "Merge (with history): $branch_name → main"
        fi
        echo ""

        local commits_ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        if [ "$commits_ahead" = "0" ]; then
            echo "Error: No commits ahead of main" >&2
            exit 1
        fi
        echo "Commits to merge: $commits_ahead"

        # Extract issue number from branch name
        local issue_num=$(echo "$branch_name" | grep -oE '[0-9]+$' | head -1)
        if [ -z "$issue_num" ]; then
            issue_num=$(echo "$branch_name" | grep -oE '([0-9]+)' | tail -1)
        fi

        # Generate commit message
        local commit_msg=""
        if [ -n "$issue_num" ]; then
            commit_msg=$(gh issue view "$issue_num" --json title --jq '.title' 2>/dev/null || echo "")
        fi

        if [ -z "$commit_msg" ]; then
            commit_msg=$(git log origin/main..HEAD --pretty=format:"%s" | head -1)
        fi

        local fixes_line=""
        if [ -n "$issue_num" ]; then
            fixes_line="Fixes #$issue_num"
        fi

        # Switch to main
        echo ""
        echo "Switching to main..."
        cd "$project_root"
        git checkout main
        git pull origin main

        # Merge
        echo ""
        if [ "$squash" = true ]; then
            echo "Squash merging $branch_name..."
            if ! git merge --squash "$branch_name"; then
                echo "Error: Merge failed. Resolve conflicts and try again." >&2
                exit 1
            fi

            if [ -z "$(git diff --cached --name-only)" ]; then
                echo ""
                echo "No changes to commit - branch was already merged."
                echo "To clean up, run: dev-env down --force $env_name"
                exit 0
            fi

            if [ -n "$fixes_line" ]; then
                git commit -m "$(cat <<EOF
$commit_msg

$fixes_line
EOF
)"
            else
                git commit -m "$commit_msg"
            fi
        else
            echo "Merging $branch_name (preserving commits)..."
            local merge_msg="Merge branch '$branch_name'"
            if [ -n "$fixes_line" ]; then
                merge_msg="$merge_msg

$fixes_line"
            fi
            if ! git merge --no-ff -m "$merge_msg" "$branch_name"; then
                echo "Error: Merge failed." >&2
                exit 1
            fi
        fi

        # Delete branch
        echo ""
        echo "Deleting branch $branch_name..."
        git branch -D "$branch_name" 2>/dev/null || true

        # Cleanup environment
        echo ""
        echo "Cleaning up environment..."
        cmd_down --force "$env_name"

        echo ""
        echo "✓ Feature complete!"
    else
        # PR workflow
        echo "PR workflow - checking/creating PR..."

        if ! command -v gh &> /dev/null; then
            echo "Error: GitHub CLI (gh) is required for PR workflow." >&2
            exit 1
        fi

        local pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null || echo "")

        if [ -z "$pr_number" ]; then
            echo "Creating PR..."
            gh pr create --fill
            echo ""
            echo "PR created. Run 'dev-env finish --pr $env_name' again after approval."
            exit 0
        fi

        local pr_json=$(gh pr view --json state,reviewDecision,mergeable)
        local state=$(echo "$pr_json" | jq -r '.state')

        if [ "$state" = "MERGED" ]; then
            echo "PR already merged. Cleaning up..."
            cd "$project_root"
            cmd_down --force "$env_name"
            exit 0
        fi

        local review=$(echo "$pr_json" | jq -r '.reviewDecision // "PENDING"')
        if [ "$review" != "APPROVED" ]; then
            echo "PR #$pr_number not yet approved (review: $review)"
            gh pr view "$pr_number" --json url --jq '"View at: \(.url)"'
            exit 0
        fi

        echo "Merging PR #$pr_number..."
        gh pr merge "$pr_number" --squash --delete-branch

        echo ""
        echo "Cleaning up environment..."
        cd "$project_root"
        cmd_down --force "$env_name"

        echo ""
        echo "✓ Feature complete!"
    fi
}

#
# Main dispatch
#

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        setup)
            cmd_setup "$@"
            ;;
        up)
            cmd_up "$@"
            ;;
        down)
            cmd_down "$@"
            ;;
        browser)
            cmd_browser "$@"
            ;;
        finish)
            cmd_finish "$@"
            ;;
        ls|list)
            cmd_ls "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
