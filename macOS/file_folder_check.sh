#!/bin/bash

# Example variables (you would already have these set)
file="$file"
folder="$folder"

# Check conditions
if [[ -n "$file" && -n "$folder" ]]; then
    echo "Both file and folder are set"
    # Do task when BOTH are populated
elif [[ -n "$file" && -z "$folder" ]]; then
    echo "File is set, folder is empty"
    # Do task when ONLY file is populated
elif [[ -z "$file" && -n "$folder" ]]; then
    echo "Folder is set, file is empty"
    # Do task when ONLY folder is populated
else
    echo "Both file and folder are empty"
    # Do task when NEITHER is populated
fi
