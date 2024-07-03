#!/bin/bash

# Variables
OUT_DIR="/zones"
DB_URL="postgresql://postgres:password@db:5432/czds"
USERNAME="${CZDS_USERNAME}"
PASSWORD="${CZDS_PASSWORD}"

# Function to wait for PostgreSQL to be ready
wait_for_db() {
    until psql $DB_URL -c '\q'; do
        >&2 echo "PostgreSQL is unavailable - sleeping"
        sleep 1
    done

    >&2 echo "PostgreSQL is up - executing command"
}

# Wait for the PostgreSQL database to be ready
wait_for_db

# Directory to store the dumps
DUMP_DIR="/zones"
mkdir -p $DUMP_DIR

# Fetch the list of tables
TABLES=$(psql $DB_URL -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public';")

echo "$TABLES"

# Function to dump and compress a single table
dump_and_compress_table() {
    local table_name="$1"
    local file_path="$DUMP_DIR/${table_name}.txt"
    local gz_file_path="${file_path}.gz"

    echo "Dumping table $table_name to $file_path"
    psql $DB_URL -c "\COPY $table_name TO '$file_path' WITH (FORMAT text, DELIMITER ',', HEADER false);"
    gzip "$file_path"

    echo "Compressed $file_path to $gz_file_path"
}

export -f dump_and_compress_table
export DB_URL
export DUMP_DIR

# Dump and compress each table in parallel
echo "$TABLES" | xargs -I {} -P 10 bash -c 'dump_and_compress_table "$@"' _ {}

echo "All tables dumped and compressed successfully."
