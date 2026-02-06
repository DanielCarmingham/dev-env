#!/bin/bash
# PostgreSQL database adapter for dev-env plugin
# Implements database lifecycle operations for PostgreSQL

# Create a PostgreSQL database
# Usage: db_create <name> <host> <port> <user> <password>
db_create() {
    local name="$1"
    local host="${2:-localhost}"
    local port="${3:-5432}"
    local user="${4:-postgres}"
    local password="${5:-postgres}"

    export PGPASSWORD="$password"

    # Check if database already exists
    if db_exists "$name" "$host" "$port" "$user" "$password"; then
        echo "Error: Database '$name' already exists." >&2
        return 1
    fi

    echo "Creating database '$name'..."
    if psql -h "$host" -p "$port" -U "$user" -d postgres -c "CREATE DATABASE $name;" 2>/dev/null; then
        echo "Database created."
        return 0
    else
        echo "Error: Failed to create database '$name'." >&2
        return 1
    fi
}

# Drop a PostgreSQL database
# Usage: db_drop <name> <host> <port> <user> <password>
db_drop() {
    local name="$1"
    local host="${2:-localhost}"
    local port="${3:-5432}"
    local user="${4:-postgres}"
    local password="${5:-postgres}"

    export PGPASSWORD="$password"

    # Check if database exists
    if ! db_exists "$name" "$host" "$port" "$user" "$password"; then
        echo "Warning: Database '$name' does not exist."
        return 0
    fi

    # Terminate existing connections
    echo "Terminating database connections..."
    psql -h "$host" -p "$port" -U "$user" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$name';" 2>/dev/null

    # Drop database
    echo "Dropping database '$name'..."
    if psql -h "$host" -p "$port" -U "$user" -d postgres -c "DROP DATABASE IF EXISTS $name;" 2>/dev/null; then
        echo "Database dropped."
        return 0
    else
        echo "Warning: Failed to drop database '$name'." >&2
        return 1
    fi
}

# Check if a PostgreSQL database exists
# Usage: db_exists <name> <host> <port> <user> <password>
# Returns: 0 if exists, 1 if not
db_exists() {
    local name="$1"
    local host="${2:-localhost}"
    local port="${3:-5432}"
    local user="${4:-postgres}"
    local password="${5:-postgres}"

    export PGPASSWORD="$password"

    if psql -h "$host" -p "$port" -U "$user" -d postgres -t -c \
        "SELECT 1 FROM pg_database WHERE datname = '$name';" 2>/dev/null | grep -q 1; then
        return 0
    else
        return 1
    fi
}

# Wait for PostgreSQL to be ready
# Usage: db_wait_ready <host> <port> <user> <password> [max_wait]
db_wait_ready() {
    local host="${1:-localhost}"
    local port="${2:-5432}"
    local user="${3:-postgres}"
    local password="${4:-postgres}"
    local max_wait="${5:-30}"

    export PGPASSWORD="$password"

    local waited=0
    while [ $waited -lt $max_wait ]; do
        if psql -h "$host" -p "$port" -U "$user" -d postgres -c "SELECT 1" &>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    echo "Error: PostgreSQL did not become ready in ${max_wait} seconds." >&2
    return 1
}

# Get PostgreSQL connection string
# Usage: db_connection_string <name> <host> <port> <user> <password>
db_connection_string() {
    local name="$1"
    local host="${2:-localhost}"
    local port="${3:-5432}"
    local user="${4:-postgres}"
    local password="${5:-postgres}"

    echo "Host=$host;Port=$port;Database=$name;Username=$user;Password=$password"
}

# Run SQL from a file
# Usage: db_run_sql <name> <host> <port> <user> <password> <sql_file>
db_run_sql() {
    local name="$1"
    local host="${2:-localhost}"
    local port="${3:-5432}"
    local user="${4:-postgres}"
    local password="${5:-postgres}"
    local sql_file="$6"

    export PGPASSWORD="$password"

    if [ ! -f "$sql_file" ]; then
        echo "Error: SQL file not found: $sql_file" >&2
        return 1
    fi

    psql -h "$host" -p "$port" -U "$user" -d "$name" -f "$sql_file"
}
