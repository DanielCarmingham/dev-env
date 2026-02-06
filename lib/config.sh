#!/bin/bash
# YAML configuration parsing for dev-env plugin
# Parses .claude/dev-env.yaml into shell variables

# Parse YAML file into associative array-style variables
# Supports simple key: value pairs, nested objects, and arrays
parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-CONFIG_}"

    if [ ! -f "$yaml_file" ]; then
        echo "Error: Config file not found: $yaml_file" >&2
        return 1
    fi

    local line key value current_section=""
    local in_array=false array_name="" array_values=""

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Remove inline comments
        line="${line%%#*}"

        # Check indentation level
        local indent="${line%%[! ]*}"
        local indent_level=$((${#indent} / 2))

        # Trim whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty after trim
        [[ -z "$line" ]] && continue

        # Check for array item
        if [[ "$line" =~ ^-[[:space:]]*(.*) ]]; then
            if [ "$in_array" = true ]; then
                local item="${BASH_REMATCH[1]}"
                if [ -n "$array_values" ]; then
                    array_values="${array_values}|${item}"
                else
                    array_values="$item"
                fi
            fi
            continue
        fi

        # End of array
        if [ "$in_array" = true ]; then
            export "${prefix}${array_name}=${array_values}"
            in_array=false
            array_name=""
            array_values=""
        fi

        # Parse key: value
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Build full key with section prefix
            local full_key
            if [ -n "$current_section" ] && [ $indent_level -gt 0 ]; then
                full_key="${current_section}_${key}"
            else
                full_key="$key"
            fi

            # Convert to uppercase for env var style
            full_key=$(echo "$full_key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

            if [ -z "$value" ]; then
                # This is a section header or array start
                if [ $indent_level -eq 0 ]; then
                    current_section="$key"
                    current_section=$(echo "$current_section" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                else
                    # Could be array start - check next line
                    in_array=true
                    array_name="$full_key"
                fi
            else
                # Remove quotes if present
                value=$(echo "$value" | sed "s/^[\"']//;s/[\"']$//")

                # Expand environment variables in value
                value=$(eval echo "$value" 2>/dev/null || echo "$value")

                # Export the variable
                export "${prefix}${full_key}=${value}"
            fi
        fi
    done < "$yaml_file"

    # Handle final array
    if [ "$in_array" = true ] && [ -n "$array_name" ]; then
        export "${prefix}${array_name}=${array_values}"
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

    local value="${!var_name:-$default}"
    echo "$value"
}

# Get array values by key path
get_config_array() {
    local key_path="$1"
    local var_name="DEV_ENV_$(echo "$key_path" | tr '[:lower:]' '[:upper:]' | tr '.' '_' | tr '-' '_')"

    local value="${!var_name:-}"
    if [ -n "$value" ]; then
        echo "$value" | tr '|' '\n'
    fi
}

# Process template string with variable substitution
# Replaces {var} with actual values
process_template() {
    local template="$1"
    local env_name="$2"

    # Get common values
    local db_name=$(get_config "database.prefix")
    db_name="${db_name}${env_name//-/_}"

    local db_host=$(get_config "database.connection.host" "localhost")
    local db_port=$(get_config "database.connection.port" "5432")
    local db_user=$(get_config "database.connection.user" "postgres")
    local db_password=$(get_config "database.connection.password" "postgres")

    # Replace placeholders
    local result="$template"
    result="${result//\{env\}/$env_name}"
    result="${result//\{dbName\}/$db_name}"
    result="${result//\{host\}/$db_host}"
    result="${result//\{port\}/$db_port}"
    result="${result//\{user\}/$db_user}"
    result="${result//\{password\}/$db_password}"

    echo "$result"
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
