#!/bin/bash
# YAML configuration parsing for dev-env plugin
# Parses .claude/dev-env.yaml into shell variables

# Simple YAML parser that handles nested keys and multi-line blocks
# Converts YAML like:
#   database:
#     connection:
#       host: localhost
# Into: DEV_ENV_DATABASE_CONNECTION_HOST=localhost
#
# Also supports multi-line blocks with | or >
parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-CONFIG_}"

    if [ ! -f "$yaml_file" ]; then
        echo "Error: Config file not found: $yaml_file" >&2
        return 1
    fi

    local key_stack=()
    local prev_indent=0
    local in_multiline=false
    local multiline_key=""
    local multiline_value=""
    local multiline_indent=0

    while IFS= read -r line || [ -n "$line" ]; do
        # Strip carriage returns (Windows line endings)
        line="${line//$'\r'/}"

        # Handle multi-line block continuation
        if [ "$in_multiline" = true ]; then
            # Count leading spaces
            local stripped="${line#"${line%%[![:space:]]*}"}"
            local line_indent=$(( (${#line} - ${#stripped}) / 2 ))

            # Check if we're still in the block (indented more than the key)
            if [ -z "$line" ] || [ $line_indent -gt $multiline_indent ]; then
                # Add to multiline value (preserve the line with its indentation relative to block)
                if [ -n "$multiline_value" ]; then
                    multiline_value="${multiline_value}
${stripped}"
                else
                    multiline_value="$stripped"
                fi
                continue
            else
                # End of multiline block - export it
                eval "export ${prefix}${multiline_key}=\$multiline_value"
                in_multiline=false
                multiline_key=""
                multiline_value=""
                # Fall through to process current line
            fi
        fi

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Remove inline comments (but not # inside quotes)
        line=$(echo "$line" | sed 's/[[:space:]]#.*$//')

        # Count leading spaces for indentation
        local stripped="${line#"${line%%[![:space:]]*}"}"
        local indent=$(( (${#line} - ${#stripped}) / 2 ))

        # Trim whitespace
        line="$stripped"
        [[ -z "$line" ]] && continue

        # Skip array items for now (start with -)
        [[ "$line" =~ ^- ]] && continue

        # Pop stack when dedenting
        while [ $indent -lt $prev_indent ] && [ ${#key_stack[@]} -gt 0 ]; do
            unset 'key_stack[${#key_stack[@]}-1]'
            prev_indent=$((prev_indent - 1))
        done

        # Parse key: value
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_-]*):(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Convert key to uppercase and replace - with _
            key=$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

            # Build full key from stack
            local full_key=""
            for k in "${key_stack[@]}"; do
                full_key="${full_key}${k}_"
            done
            full_key="${full_key}${key}"

            if [ -z "$value" ]; then
                # Section header - push to stack
                key_stack+=("$key")
                prev_indent=$((indent + 1))
            elif [ "$value" = "|" ] || [ "$value" = ">" ]; then
                # Start of multi-line block
                in_multiline=true
                multiline_key="$full_key"
                multiline_value=""
                multiline_indent=$indent
            else
                # Remove quotes
                value=$(echo "$value" | sed "s/^[\"']//;s/[\"']$//")

                # Expand environment variables
                value=$(eval echo "$value" 2>/dev/null || echo "$value")

                # Export
                eval "export ${prefix}${full_key}='${value}'"
            fi
        fi
    done < "$yaml_file"

    # Handle case where file ends while in multiline block
    if [ "$in_multiline" = true ] && [ -n "$multiline_key" ]; then
        eval "export ${prefix}${multiline_key}=\$multiline_value"
    fi
}

# Load configuration from project's .claude/dev-env.yaml
load_config() {
    local project_root="$1"
    local config_file="$project_root/.claude/dev-env.yaml"

    if [ ! -f "$config_file" ]; then
        echo "Error: No dev-env.yaml found at $config_file" >&2
        echo "Create one using: dev-env init" >&2
        return 1
    fi

    parse_yaml "$config_file" "DEV_ENV_"

    # Set defaults for missing values
    : "${DEV_ENV_DATABASE_TYPE:=postgresql}"
    : "${DEV_ENV_DATABASE_PREFIX:=dev_}"
    : "${DEV_ENV_DATABASE_CONNECTION_HOST:=localhost}"
    : "${DEV_ENV_DATABASE_CONNECTION_PORT:=5432}"
    : "${DEV_ENV_DATABASE_CONNECTION_USER:=postgres}"
    : "${DEV_ENV_DATABASE_CONNECTION_PASSWORD:=postgres}"

    : "${DEV_ENV_PORTS_BASEHTTPS:=50000}"
    : "${DEV_ENV_PORTS_BASEHTTP:=50100}"
    : "${DEV_ENV_PORTS_BASEVITE:=50200}"

    # Export defaults
    export DEV_ENV_DATABASE_TYPE DEV_ENV_DATABASE_PREFIX
    export DEV_ENV_DATABASE_CONNECTION_HOST DEV_ENV_DATABASE_CONNECTION_PORT
    export DEV_ENV_DATABASE_CONNECTION_USER DEV_ENV_DATABASE_CONNECTION_PASSWORD
    export DEV_ENV_PORTS_BASEHTTPS DEV_ENV_PORTS_BASEHTTP DEV_ENV_PORTS_BASEVITE

    # Export port bases with simpler names
    export DEV_ENV_BASE_HTTPS="${DEV_ENV_PORTS_BASEHTTPS}"
    export DEV_ENV_BASE_HTTP="${DEV_ENV_PORTS_BASEHTTP}"
    export DEV_ENV_BASE_VITE="${DEV_ENV_PORTS_BASEVITE}"

    return 0
}

# Get a config value by key path (e.g., "database.connection.host")
get_config() {
    local key_path="$1"
    local default="${2:-}"

    # Convert key path to variable name
    local var_name="DEV_ENV_$(echo "$key_path" | tr '[:lower:]' '[:upper:]' | tr '.' '_' | tr '-' '_')"

    # Use eval for indirect variable access (works in both bash and zsh)
    local value
    eval "value=\"\${$var_name:-$default}\""
    echo "$value"
}

# Get array values by key path
get_config_array() {
    local key_path="$1"
    local var_name="DEV_ENV_$(echo "$key_path" | tr '[:lower:]' '[:upper:]' | tr '.' '_' | tr '-' '_')"

    local value
    eval "value=\"\${$var_name:-}\""
    if [ -n "$value" ]; then
        echo "$value" | tr '|' '\n'
    fi
}

# Process template string with variable substitution
process_template() {
    local template="$1"
    local env_name="$2"

    local db_name=$(get_config "database.prefix")
    db_name="${db_name}${env_name//-/_}"

    local db_host=$(get_config "database.connection.host" "localhost")
    local db_port=$(get_config "database.connection.port" "5432")
    local db_user=$(get_config "database.connection.user" "postgres")
    local db_password=$(get_config "database.connection.password" "postgres")

    local result="$template"
    result="${result//\{env\}/$env_name}"
    result="${result//\{dbName\}/$db_name}"
    result="${result//\{host\}/$db_host}"
    result="${result//\{port\}/$db_port}"
    result="${result//\{user\}/$db_user}"
    result="${result//\{password\}/$db_password}"

    echo "$result"
}

# Parse copyFiles array from YAML config
# Returns lines of "from|to" pairs (to defaults to from if omitted)
parse_copy_files() {
    local yaml_file="$1"
    local in_section=false
    local current_from=""

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$'\r'/}"

        # Detect start of copyFiles section
        if [[ "$line" =~ ^copyFiles: ]]; then
            in_section=true
            continue
        fi

        if [ "$in_section" = true ]; then
            # End of section: non-indented, non-empty line that isn't an array item
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]] ]]; then
                # Flush last entry
                if [ -n "$current_from" ]; then
                    echo "${current_from}|${current_from}"
                fi
                break
            fi

            # Array item with "from:" on same line
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*from:[[:space:]]*(.*) ]]; then
                # Flush previous entry that had no "to:"
                if [ -n "$current_from" ]; then
                    echo "${current_from}|${current_from}"
                fi
                current_from="${BASH_REMATCH[1]}"
                current_from=$(echo "$current_from" | sed "s/^[\"']//;s/[\"']$//;s/[[:space:]]*$//")
                continue
            fi

            # "to:" line following a "from:"
            if [[ "$line" =~ ^[[:space:]]+to:[[:space:]]*(.*) ]] && [ -n "$current_from" ]; then
                local to_val="${BASH_REMATCH[1]}"
                to_val=$(echo "$to_val" | sed "s/^[\"']//;s/[\"']$//;s/[[:space:]]*$//")
                if [ -z "$to_val" ]; then
                    to_val="$current_from"
                fi
                echo "${current_from}|${to_val}"
                current_from=""
                continue
            fi

            # Simple string array item: "- path/to/file"
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
                # Flush previous
                if [ -n "$current_from" ]; then
                    echo "${current_from}|${current_from}"
                    current_from=""
                fi
                local val="${BASH_REMATCH[1]}"
                val=$(echo "$val" | sed "s/^[\"']//;s/[\"']$//;s/[[:space:]]*$//")
                echo "${val}|${val}"
                continue
            fi
        fi
    done < "$yaml_file"

    # Flush if file ended while in section
    if [ "$in_section" = true ] && [ -n "$current_from" ]; then
        echo "${current_from}|${current_from}"
    fi
}

# Validate configuration has required fields
validate_config() {
    local errors=()

    if [ -z "$(get_config 'project.name')" ]; then
        errors+=("project.name is required")
    fi

    if [ -z "$(get_config 'database.type')" ]; then
        errors+=("database.type is required")
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        echo "Configuration errors:" >&2
        for error in "${errors[@]}"; do
            echo "  - $error" >&2
        done
        return 1
    fi

    return 0
}
