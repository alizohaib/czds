#!/bin/bash

# Variables
OUT_DIR="/zones_local"
DB_URL="postgresql://postgres:password@db:5432/czds"
USERNAME="${CZDS_USERNAME}"
PASSWORD="${CZDS_PASSWORD}"

# Download files (-zone "abc,xyz")
czds-dl -out $OUT_DIR -username "$USERNAME" -password "$PASSWORD" -verbose -redownload

parallel --will-cite < /dev/null

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

# Function to process a single file
process_file() {
    echo "Processing $1 in process $$ with temporary table";

    local filename="$1"
    local table_name
    local zone_name
    local file
    
    zone_name=$(echo "$filename" | sed 's/\(.*\)\..*\..*/\1/')
    table_name=$(echo "${zone_name}_temp" )

    # Create the table if it doesn't exist
    psql $DB_URL -c "CREATE TABLE IF NOT EXISTS $zone_name (
        domain VARCHAR,
        first_seen TIMESTAMP,
        last_seen TIMESTAMP,
        UNIQUE (domain)
    );"


    # Create a temporary staging table with a random name
    psql $DB_URL -c "CREATE TABLE $table_name (
        domain VARCHAR,
        first_seen TIMESTAMP,
        last_seen TIMESTAMP
    );"
    
    # Use zcat to decompress and copy data into the staging table
    file=$(echo "/zones_local/${filename}")

    zcat "$file" | awk -v date="$(date '+%Y-%m-%d %H:%M:%S')" '{ sub(/\.$/, "", $1); print $1 "," date "," date }' | sort -u | psql $DB_URL -c "COPY $table_name(domain, first_seen, last_seen) FROM STDIN WITH CSV;"

    # Perform the upsert operation
    psql $DB_URL -c "INSERT INTO $zone_name (domain, first_seen, last_seen)
    SELECT domain, first_seen, last_seen
    FROM $table_name
    ON CONFLICT (domain) 
    DO UPDATE SET last_seen = EXCLUDED.last_seen;"

    # Drop the temporary staging table
    psql $DB_URL -c "DROP TABLE $table_name;"
    echo "Processed $filename in process $$"
}

export -f process_file
export DB_URL

# Process each downloaded .gz file in parallel
ls $OUT_DIR | xargs -n 1 -P 10 -I {} bash -c 'process_file "$@"' _ {}
