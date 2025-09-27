#!/bin/bash

# Test script for Duende compiler

echo "Cleaning previous builds..."
dub clean || exit 1

echo "Building Duende compiler..."
dub build --compiler=dmd --force || exit 1
# --compiler=ldc2 --- IGNORE ---
# --compiler=gdc --- IGNORE ---

echo ""
echo "Running integration tests with pytest..."
uv run pytest -v -n 1 || exit 1 # -n is set to 1 to avoid concurrency issues
echo ""

rm test_output.txt
rm -rf test_dir