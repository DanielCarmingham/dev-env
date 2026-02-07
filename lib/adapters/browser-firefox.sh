#!/bin/bash
# Firefox browser adapter for dev-env plugin
# Manages Firefox with remote debugging for firefox-devtools MCP integration

CLAUDE_JSON="$HOME/.claude.json"

# Check for existing non-debug Firefox instances
# Firefox doesn't allow remote debugging when other instances are running without it
browser_check_conflicts() {
    if pgrep -x "firefox" > /dev/null 2>&1; then
        if ps aux | grep "[f]irefox" | grep -v -- "-start-debugger-server" | grep -q "Firefox.app"; then
            echo "Error: Firefox is running without remote debugging enabled." >&2
            echo "Firefox does not allow debug instances while non-debug instances are running." >&2
            echo "" >&2
            echo "Please close all Firefox windows and try again, or run:" >&2
            echo "  killall 'firefox'" >&2
            return 1
        fi
    fi
    return 0
}

# Start Firefox with remote debugging
# Args: env_name, debug_port, start_url (optional)
browser_start() {
    local env_name="$1"
    local debug_port="$2"
    local start_url="${3:-}"
    local profile_dir="/tmp/firefox-debug-profile-${env_name}"

    # Create profile directory if it doesn't exist
    mkdir -p "$profile_dir"

    local firefox_args=(
        -remote-debugging-port "$debug_port"
        -profile "$profile_dir"
        --no-first-run
        --no-default-browser-check
        --no-remote
    )

    if [ -n "$start_url" ]; then
        firefox_args+=(-url "$start_url")
    fi

    echo "Starting Firefox (debug port: $debug_port, profile: $env_name)..."
    open -a "Firefox" --args "${firefox_args[@]}"

    echo "  Firefox started with remote debugging on port $debug_port"
    return 0
}

# Stop Firefox instance for a specific environment
# Kills processes matching the environment's profile directory
browser_stop() {
    local env_name="$1"
    local profile_dir="/tmp/firefox-debug-profile-${env_name}"

    # Find and kill Firefox processes using this profile
    if pkill -f "profile ${profile_dir}" 2>/dev/null; then
        echo "  Firefox instance stopped (profile: $env_name)"
        # Clean up the profile directory
        rm -rf "$profile_dir" 2>/dev/null || true
    else
        # No matching process - that's fine, Firefox may have been closed manually
        rm -rf "$profile_dir" 2>/dev/null || true
    fi
    return 0
}

# Update ~/.claude.json with project-scoped firefox-devtools MCP config
# Args: target_dir (worktree path), debug_port
browser_update_mcp() {
    local target_dir="$1"
    local debug_port="$2"

    if [ ! -f "$CLAUDE_JSON" ]; then
        echo "  Warning: ~/.claude.json not found, cannot configure firefox-devtools MCP." >&2
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        echo "  Warning: jq not installed, cannot update ~/.claude.json automatically." >&2
        echo "  Manually set firefox-devtools MCP for port $debug_port for $target_dir" >&2
        return 0
    fi

    jq --arg dir "$target_dir" --arg port "$debug_port" '
        .projects[$dir].mcpServers["firefox-devtools"] = {
            "command": "npx",
            "args": ["@anthropic-ai/firefox-devtools-mcp@latest", "--port", $port]
        }
    ' "$CLAUDE_JSON" > "${CLAUDE_JSON}.tmp" && mv "${CLAUDE_JSON}.tmp" "$CLAUDE_JSON"

    echo "  MCP firefox-devtools configured for port $debug_port"
    echo "  NOTE: Restart Claude Code for MCP config changes to take effect."
    return 0
}

# Remove project-scoped firefox-devtools MCP config from ~/.claude.json
# Args: target_dir (worktree path)
browser_clean_mcp() {
    local target_dir="$1"

    if [ ! -f "$CLAUDE_JSON" ]; then
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        return 0
    fi

    # Remove the firefox-devtools MCP entry for this project
    # If the project has no other MCP servers, clean up the empty objects too
    jq --arg dir "$target_dir" '
        if .projects[$dir].mcpServers["firefox-devtools"] then
            del(.projects[$dir].mcpServers["firefox-devtools"])
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
