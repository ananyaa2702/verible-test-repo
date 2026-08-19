#!/bin/bash
# gen_build_config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"  # resolves to clean absolute path
OUTPUT="$SCRIPT_DIR/build_config.yaml"

{
    echo "rtl:"
    # Added "  - " to explicitly make it a structural YAML list
    find "$PROJECT_ROOT" \( -path "*/RTL/*.v" -o -path "*/RTL/*.sv" \) -type f | sort | sed "s#^$PROJECT_ROOT/##" | sed 's#\\#/#g' | sed 's/^/  - /'

    echo "tb:"
    find "$PROJECT_ROOT" \( -path "*/TB/*.v" -o -path "*/TB/*.sv" \) -type f | sort | sed "s#^$PROJECT_ROOT/##" | sed 's#\\#/#g' | sed 's/^/  - /'

    echo "simdata:"
    find "$PROJECT_ROOT/flash_memory_files" -type f | sort | sed "s#^$PROJECT_ROOT/##" | sed 's#\\#/#g' | sed 's/^/  - /'
    find "$PROJECT_ROOT/memh_files" -type f | sort | sed "s#^$PROJECT_ROOT/##" | sed 's#\\#/#g' | sed 's/^/  - /'
} > "$OUTPUT"

echo "Generated: $OUTPUT"