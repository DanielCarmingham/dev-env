#!/bin/bash
# Azurite blob storage adapter for dev-env plugin
# Implements storage operations for Azure Blob Storage (via Azurite emulator)

# Default Azurite connection string
DEFAULT_AZURITE_CONN="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"

# Create a blob container
# Usage: storage_create_container <name> [connection_string]
storage_create_container() {
    local name="$1"
    local conn="${2:-$DEFAULT_AZURITE_CONN}"

    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        echo "Note: Azure CLI not found. Container '$name' will be created when the app starts."
        return 0
    fi

    echo "Creating blob container '$name'..."
    if az storage container create --name "$name" --connection-string "$conn" 2>/dev/null; then
        echo "Container created."
        return 0
    else
        echo "Warning: Failed to create container '$name'." >&2
        return 1
    fi
}

# Delete a blob container
# Usage: storage_delete_container <name> [connection_string]
storage_delete_container() {
    local name="$1"
    local conn="${2:-$DEFAULT_AZURITE_CONN}"

    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        echo "Note: Azure CLI not found. Container '$name' may remain in storage."
        return 0
    fi

    echo "Deleting blob container '$name'..."
    if az storage container delete --name "$name" --connection-string "$conn" 2>/dev/null; then
        echo "Container deleted."
        return 0
    else
        echo "Warning: Failed to delete container '$name'." >&2
        return 1
    fi
}

# Check if a blob container exists
# Usage: storage_container_exists <name> [connection_string]
storage_container_exists() {
    local name="$1"
    local conn="${2:-$DEFAULT_AZURITE_CONN}"

    if ! command -v az &> /dev/null; then
        # Can't check, assume it might exist
        return 0
    fi

    if az storage container exists --name "$name" --connection-string "$conn" --query "exists" -o tsv 2>/dev/null | grep -q "true"; then
        return 0
    else
        return 1
    fi
}

# List all blob containers matching a pattern
# Usage: storage_list_containers <pattern> [connection_string]
storage_list_containers() {
    local pattern="$1"
    local conn="${2:-$DEFAULT_AZURITE_CONN}"

    if ! command -v az &> /dev/null; then
        echo "Note: Azure CLI not found."
        return 0
    fi

    az storage container list --connection-string "$conn" --query "[?starts_with(name, '$pattern')].name" -o tsv 2>/dev/null
}

# Create containers from config patterns
# Usage: storage_create_containers_from_config <env_name> [connection_string]
storage_create_containers_from_config() {
    local env_name="$1"
    local conn="${2:-$DEFAULT_AZURITE_CONN}"

    # Get container patterns from config
    local containers=$(get_config_array "storage.containers")

    if [ -z "$containers" ]; then
        return 0
    fi

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue

        # Extract pattern value if it's in "pattern: xxx" format
        if [[ "$pattern" =~ pattern:[[:space:]]*(.+) ]]; then
            pattern="${BASH_REMATCH[1]}"
        fi

        # Replace {env} placeholder
        local container_name="${pattern//\{env\}/$env_name}"
        container_name=$(echo "$container_name" | sed "s/[\"']//g")

        storage_create_container "$container_name" "$conn"
    done <<< "$containers"
}

# Delete containers matching environment
# Usage: storage_delete_containers_for_env <env_name> [connection_string]
storage_delete_containers_for_env() {
    local env_name="$1"
    local conn="${2:-$DEFAULT_AZURITE_CONN}"

    # Get container patterns from config
    local containers=$(get_config_array "storage.containers")

    if [ -z "$containers" ]; then
        return 0
    fi

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue

        # Extract pattern value if it's in "pattern: xxx" format
        if [[ "$pattern" =~ pattern:[[:space:]]*(.+) ]]; then
            pattern="${BASH_REMATCH[1]}"
        fi

        # Replace {env} placeholder
        local container_name="${pattern//\{env\}/$env_name}"
        container_name=$(echo "$container_name" | sed "s/[\"']//g")

        storage_delete_container "$container_name" "$conn"
    done <<< "$containers"
}

# Get Azurite connection string (with fallback to default)
get_storage_connection_string() {
    local conn=$(get_config "storage.connection")
    echo "${conn:-$DEFAULT_AZURITE_CONN}"
}
