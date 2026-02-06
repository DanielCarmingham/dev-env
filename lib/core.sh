#!/bin/bash
# Core utility functions for dev-env plugin
# These functions are generic and work with any project type

#
# Port Management
#

# Get list of HTTPS ports used by existing worktrees
get_used_ports() {
    local project_root="$1"
    local project_name=$(basename "$project_root")
    local prefix="${project_name}-"
    local base_https="${DEV_ENV_BASE_HTTPS:-50000}"

    while IFS= read -r line; do
        local worktree_path=$(echo "$line" | awk '{print $1}')
        local worktree_name=$(basename "$worktree_path")

        if [[ "$worktree_name" == ${prefix}* ]]; then
            local env_name="${worktree_name#$prefix}"
            # Calculate what port this env would use
            if [[ "$env_name" =~ -([0-9]+)$ ]]; then
                echo $((base_https + (${BASH_REMATCH[1]} % 100)))
            else
                local hash=$(echo -n "$env_name" | cksum | cut -d' ' -f1)
                echo $((base_https + (hash % 50) + 50))
            fi
        fi
    done < <(git -C "$project_root" worktree list 2>/dev/null)
}

# Calculate ports for an environment, avoiding collisions
calculate_ports() {
    local project_root="$1"
    local env_name="$2"
    local base_https="${DEV_ENV_BASE_HTTPS:-50000}"
    local base_http="${DEV_ENV_BASE_HTTP:-50100}"
    local base_vite="${DEV_ENV_BASE_VITE:-50200}"

    # Calculate initial port based on name
    local base_port
    if [[ "$env_name" =~ -([0-9]+)$ ]]; then
        base_port=$((${BASH_REMATCH[1]} % 100))
    else
        local hash=$(echo -n "$env_name" | cksum | cut -d' ' -f1)
        base_port=$((hash % 50 + 50))
    fi

    # Get list of used ports
    local used_ports=$(get_used_ports "$project_root")

    # Find next available port (check for collisions)
    local port_offset=$base_port
    while echo "$used_ports" | grep -q "^$((base_https + port_offset))$"; do
        port_offset=$(( (port_offset + 1) % 100 ))
        # Safety: avoid infinite loop if all ports taken
        if [ "$port_offset" -eq "$base_port" ]; then
            echo "Error: No available ports in range ${base_https}-$((base_https + 99))" >&2
            return 1
        fi
    done

    # Export calculated ports
    HTTPS_PORT=$((base_https + port_offset))
    HTTP_PORT=$((base_http + port_offset))
    VITE_PORT=$((base_vite + port_offset))

    export HTTPS_PORT HTTP_PORT VITE_PORT
}

#
# Environment Name Management
#

# Validate environment name
validate_env_name() {
    local name="$1"
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')

    if [ ${#name} -lt 3 ] || [ ${#name} -gt 50 ]; then
        echo "Error: Environment name must be 3-50 characters." >&2
        return 1
    fi

    if ! [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "Error: Environment name must start with a letter and contain only lowercase letters, numbers, and hyphens." >&2
        return 1
    fi

    echo "$name"
}

# Normalize database name from env name (replace - with _)
normalize_db_name() {
    local env_name="$1"
    local prefix="${2:-}"
    echo "${prefix}${env_name//-/_}"
}

#
# Worktree Management
#

# Get worktree path for an environment
get_worktree_path() {
    local project_root="$1"
    local env_name="$2"
    local project_name=$(basename "$project_root")
    echo "$(dirname "$project_root")/${project_name}-${env_name}"
}

# Create a new worktree with optional branch
create_worktree() {
    local project_root="$1"
    local env_name="$2"
    local branch="${3:-}"  # Optional: specific branch to checkout
    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    # Check if worktree path already exists
    if [ -d "$worktree_path" ]; then
        echo "Error: Worktree directory already exists: $worktree_path" >&2
        return 1
    fi

    # If a specific branch was requested, use it
    if [ -n "$branch" ]; then
        if git -C "$project_root" show-ref --verify --quiet "refs/heads/$branch"; then
            echo "  Checking out existing branch: $branch"
            git -C "$project_root" worktree add "$worktree_path" "$branch"
        elif git -C "$project_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            echo "  Checking out remote branch: origin/$branch"
            git -C "$project_root" worktree add -b "$branch" "$worktree_path" "origin/$branch"
        else
            # Branch doesn't exist - create it from current branch
            local base_branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD)
            echo "  Creating new branch: $branch (from $base_branch)"
            git -C "$project_root" worktree add -b "$branch" "$worktree_path" "$base_branch"
        fi
    # Check if branch with env_name already exists
    elif git -C "$project_root" show-ref --verify --quiet "refs/heads/$env_name"; then
        echo "  Using existing branch: $env_name"
        git -C "$project_root" worktree add "$worktree_path" "$env_name"
    else
        # Get the current branch to base the new branch on
        local base_branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD)
        echo "  Creating new branch: $env_name (from $base_branch)"
        git -C "$project_root" worktree add -b "$env_name" "$worktree_path" "$base_branch"
    fi

    if [ $? -ne 0 ]; then
        echo "Error: Failed to create worktree." >&2
        return 1
    fi

    echo "$worktree_path"
}

# Remove a worktree and optionally its branch
remove_worktree() {
    local project_root="$1"
    local env_name="$2"
    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    # Check if worktree exists
    if ! git -C "$project_root" worktree list | grep -q "$worktree_path"; then
        echo "Warning: Worktree not found: $worktree_path"
        return 0
    fi

    echo "Removing worktree..."
    git -C "$project_root" worktree remove "$worktree_path" --force 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Worktree removed."
    else
        echo "Warning: Failed to remove worktree. You may need to remove it manually:" >&2
        echo "  git worktree remove \"$worktree_path\" --force" >&2
    fi

    # Optionally delete the branch if it exists and is not checked out elsewhere
    if git -C "$project_root" show-ref --verify --quiet "refs/heads/$env_name"; then
        # Check if branch is used by any other worktree
        if ! git -C "$project_root" worktree list | grep -q "\[$env_name\]"; then
            echo "Deleting branch: $env_name"
            git -C "$project_root" branch -D "$env_name" 2>/dev/null || true
        fi
    fi
}

# Check if worktree has uncommitted changes or unmerged commits
check_worktree_safety() {
    local project_root="$1"
    local env_name="$2"
    local worktree_path=$(get_worktree_path "$project_root" "$env_name")

    if [ ! -d "$worktree_path" ]; then
        return 0  # Nothing to check
    fi

    local issues=()

    # Check for uncommitted changes (modified, staged, or untracked files)
    if [ -n "$(git -C "$worktree_path" status --porcelain 2>/dev/null)" ]; then
        issues+=("uncommitted changes")
    fi

    # Check for unmerged commits (commits in branch but not in main)
    local main_branch=$(git -C "$project_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    local unmerged_count=$(git -C "$worktree_path" rev-list --count "$main_branch"..HEAD 2>/dev/null || echo "0")
    if [ "$unmerged_count" -gt 0 ]; then
        issues+=("$unmerged_count unmerged commit(s)")
    fi

    if [ ${#issues[@]} -gt 0 ]; then
        echo "Warning: Worktree has ${issues[*]}" >&2
        return 1
    fi

    return 0
}

# Find environment by partial match
# Sets MATCHES array and MATCH_COUNT for caller to inspect
find_env_by_partial() {
    local project_root="$1"
    local search="$2"
    local project_name=$(basename "$project_root")
    local prefix="${project_name}-"

    MATCHES=()
    MATCH_COUNT=0

    local worktree_list
    worktree_list=$(git -C "$project_root" worktree list 2>/dev/null) || true

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local worktree_path=$(echo "$line" | awk '{print $1}')
        local worktree_name=$(basename "$worktree_path")

        if [[ "$worktree_name" == ${prefix}* ]]; then
            local env_name="${worktree_name#$prefix}"
            # Check if search term is contained in env name
            if [[ "$env_name" == *"$search"* ]]; then
                MATCHES+=("$env_name")
                ((MATCH_COUNT++)) || true
            fi
        fi
    done <<< "$worktree_list"

    export MATCHES MATCH_COUNT
}

# List all environments for a project
list_environments() {
    local project_root="$1"
    local project_name=$(basename "$project_root")
    local prefix="${project_name}-"

    local found_any=false
    while IFS= read -r line; do
        local worktree_path=$(echo "$line" | awk '{print $1}')
        local worktree_name=$(basename "$worktree_path")

        if [[ "$worktree_name" == ${prefix}* ]]; then
            found_any=true
            local env_name="${worktree_name#$prefix}"
            echo "$env_name  $worktree_path"
        fi
    done < <(git -C "$project_root" worktree list 2>/dev/null)

    if [ "$found_any" = false ]; then
        echo "(no environments found)"
    fi
}

#
# GitHub Integration
#

# Generate branch name from issue title + number
generate_branch_name_from_issue() {
    local title="$1"
    local number="$2"

    # Lowercase
    local name=$(echo "$title" | tr '[:upper:]' '[:lower:]')

    # Remove parenthetical content (e.g., "(Phase 2)")
    name=$(echo "$name" | sed 's/([^)]*)//g')

    # Remove common stop words
    name=$(echo "$name" | sed -E 's/\b(the|a|an|and|or|to|for|of|in|on|at|by|with|from)\b//g')

    # Keep only alphanumeric and spaces
    name=$(echo "$name" | tr -cd 'a-z0-9 ')

    # Collapse multiple spaces, trim
    name=$(echo "$name" | tr -s ' ' | sed 's/^ *//;s/ *$//')

    # Convert spaces to hyphens
    name=$(echo "$name" | tr ' ' '-')

    # Collapse multiple hyphens
    name=$(echo "$name" | tr -s '-')

    # Truncate to ~40 chars at word boundary
    if [ ${#name} -gt 40 ]; then
        name=$(echo "$name" | cut -c1-40 | sed 's/-[^-]*$//')
    fi

    # Remove trailing hyphen if any
    name=$(echo "$name" | sed 's/-$//')

    # Append issue number
    echo "${name}-${number}"
}

# Fetch issue by number using gh CLI
# Sets global variables: ISSUE_NUMBER, ISSUE_TITLE
fetch_issue() {
    local number="$1"

    # Check prerequisites
    if ! command -v gh &> /dev/null; then
        echo "Error: GitHub CLI (gh) is required for issue lookup." >&2
        echo "Install with: brew install gh" >&2
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for issue lookup." >&2
        echo "Install with: brew install jq" >&2
        return 1
    fi

    if ! gh auth token &> /dev/null; then
        echo "Error: Not authenticated with GitHub CLI." >&2
        echo "Run: gh auth login" >&2
        return 1
    fi

    # Fetch issue
    local issue_json
    issue_json=$(gh issue view "$number" --json number,title,state 2>&1)
    if [ $? -ne 0 ]; then
        echo "Error: Could not fetch issue #$number" >&2
        echo "$issue_json" >&2
        return 1
    fi

    ISSUE_NUMBER=$(echo "$issue_json" | jq -r '.number')
    ISSUE_TITLE=$(echo "$issue_json" | jq -r '.title')
    local state=$(echo "$issue_json" | jq -r '.state')

    if [ "$state" = "CLOSED" ]; then
        echo "Warning: Issue #$ISSUE_NUMBER is closed." >&2
    fi

    export ISSUE_NUMBER ISSUE_TITLE
    return 0
}

# Find existing branch for an issue (branch name ending in -NN)
find_existing_issue_branch() {
    local project_root="$1"
    local issue_number="$2"
    local suffix="-${issue_number}"

    # Check local branches
    local local_branch
    local_branch=$(git -C "$project_root" branch --list "*${suffix}" 2>/dev/null | head -1 | sed 's/^[* ]*//')
    if [ -n "$local_branch" ]; then
        echo "$local_branch"
        return 0
    fi

    # Check remote branches
    local remote_branch
    remote_branch=$(git -C "$project_root" branch -r --list "*${suffix}" 2>/dev/null | head -1 | sed 's/^[* ]*//' | sed 's|^origin/||')
    if [ -n "$remote_branch" ]; then
        echo "$remote_branch"
        return 0
    fi

    return 1
}

#
# Terminal Utilities
#

# Set terminal tab title using OSC escape sequences
set_terminal_title() {
    local title="$1"
    printf '\033]0;%s\007' "$title"

    # If in tmux, also set the tmux window name
    if [ -n "$TMUX" ]; then
        tmux rename-window "$title" 2>/dev/null || true
    fi
}

#
# Hook Execution
#

# Execute a lifecycle hook if defined
execute_hook() {
    local hook_name="$1"
    local hook_cmd="$2"

    if [ -n "$hook_cmd" ]; then
        echo "Running hook: $hook_name"
        eval "$hook_cmd"
        local result=$?
        if [ $result -ne 0 ]; then
            echo "Warning: Hook '$hook_name' failed with exit code $result" >&2
        fi
        return $result
    fi
    return 0
}
