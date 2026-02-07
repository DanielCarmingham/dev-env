#!/bin/bash
# Chrome browser adapter for dev-env plugin
# Manages Chrome with remote debugging for chrome-devtools MCP integration

CLAUDE_JSON="$HOME/.claude.json"

# Check for existing non-debug Chrome instances
# Chrome doesn't allow remote debugging when other instances are running without it
browser_check_conflicts() {
    if pgrep -x "Google Chrome" > /dev/null 2>&1; then
        if ps aux | grep "[G]oogle Chrome" | grep -v -- "--remote-debugging-port" | grep -q "Google Chrome.app"; then
            echo "Error: Chrome is running without remote debugging enabled." >&2
            echo "Chrome does not allow debug instances while non-debug instances are running." >&2
            echo "" >&2
            echo "Please close all Chrome windows and try again, or run:" >&2
            echo "  killall 'Google Chrome'" >&2
            return 1
        fi
    fi
    return 0
}

# Start Chrome with remote debugging
# Args: env_name, debug_port, start_url (optional)
browser_start() {
    local env_name="$1"
    local debug_port="$2"
    local start_url="${3:-}"
    local profile_dir="/tmp/chrome-debug-profile-${env_name}"

    local chrome_args=(
        --remote-debugging-port="$debug_port"
        --user-data-dir="$profile_dir"
        --no-first-run
        --no-default-browser-check
    )

    if [ -n "$start_url" ]; then
        chrome_args+=("$start_url")
    fi

    echo "Starting Chrome (debug port: $debug_port, profile: $env_name)..."
    open -a "Google Chrome" --args "${chrome_args[@]}"

    echo "  Chrome started with remote debugging on port $debug_port"
    return 0
}

# Stop Chrome instance for a specific environment
# Kills processes matching the environment's user-data-dir
browser_stop() {
    local env_name="$1"
    local profile_dir="/tmp/chrome-debug-profile-${env_name}"

    # Find and kill Chrome processes using this profile
    if pkill -f "user-data-dir=${profile_dir}" 2>/dev/null; then
        echo "  Chrome instance stopped (profile: $env_name)"
        # Clean up the profile directory
        rm -rf "$profile_dir" 2>/dev/null || true
    else
        # No matching process - that's fine, Chrome may have been closed manually
        rm -rf "$profile_dir" 2>/dev/null || true
    fi
    return 0
}

# Update ~/.claude.json with project-scoped chrome-devtools MCP config
# Args: target_dir (worktree path), debug_port
browser_update_mcp() {
    local target_dir="$1"
    local debug_port="$2"

    if [ ! -f "$CLAUDE_JSON" ]; then
        echo "  Warning: ~/.claude.json not found, cannot configure chrome-devtools MCP." >&2
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        echo "  Warning: jq not installed, cannot update ~/.claude.json automatically." >&2
        echo "  Manually set chrome-devtools MCP --browser-url to port $debug_port for $target_dir" >&2
        return 0
    fi

    jq --arg dir "$target_dir" --arg port "$debug_port" '
        .projects[$dir].mcpServers["chrome-devtools"] = {
            "command": "npx",
            "args": ["chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:" + $port]
        }
    ' "$CLAUDE_JSON" > "${CLAUDE_JSON}.tmp" && mv "${CLAUDE_JSON}.tmp" "$CLAUDE_JSON"

    echo "  MCP chrome-devtools configured for port $debug_port"
    echo "  NOTE: Restart Claude Code for MCP config changes to take effect."
    return 0
}

# Remove project-scoped chrome-devtools MCP config from ~/.claude.json
# Args: target_dir (worktree path)
browser_clean_mcp() {
    local target_dir="$1"

    if [ ! -f "$CLAUDE_JSON" ]; then
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        return 0
    fi

    # Remove the chrome-devtools MCP entry for this project
    # If the project has no other MCP servers, clean up the empty objects too
    jq --arg dir "$target_dir" '
        if .projects[$dir].mcpServers["chrome-devtools"] then
            del(.projects[$dir].mcpServers["chrome-devtools"])
            | if (.projects[$dir].mcpServers | length) == 0 then
                del(.projects[$dir].mcpServers)
              else . end
            | if (.projects[$dir] | length) == 0 then
                del(.projects[$dir])
              else . end
        else . end
    ' "$CLAUDE_JSON" > "${CLAUDE_JSON}.tmp" && mv "${CLAUDE_JSON}.tmp" "$CLAUDE_JSON"

    return 0
}
