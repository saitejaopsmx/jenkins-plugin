#!/bin/bash

# Script Name: find-binary.sh
# Description: Extracts a .tar.gz file, searches for binaries matching an optional include regex and an optional exclude extension,
#              and outputs the results in a JSON file. Includes artifactTag based on version.txt or tar filename.
# Usage: ./find-binary.sh "<path_to_tar.gz>" "<include_regex>" "[<exclude_extension_regex>]"

# Ensure the script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash to run."
    exit 1
fi

# Check if at least the tar file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 \"<path_to_tar.gz>\" \"[<include_regex>]\" \"[<exclude_extension_regex>]\""
    echo "Example: $0 \"test.tar.gz\" \"progress\" \"img|gif|png\""
    exit 1
fi

# Assign positional arguments to variables
tar_file="$1"
include_regex="${2:-}"  # Default include to empty (include everything if not provided)
exclude_regex="${3:-}"  # Default exclude to empty (exclude nothing if not provided)

# Check if the tar file exists and is a valid .tar.gz file
if [[ ! -f "$tar_file" || "${tar_file##*.}" != "gz" ]]; then
    echo "Error: '$tar_file' is not a valid .tar.gz file or does not exist."
    exit 1
fi

# cd into a tmp dir
mkdir ssd-tmp
cd ssd-tmp

# Extract the tar.gz file
echo "Extracting '$tar_file'..."
tar -xzf "$tar_file"

# Get the extracted directory name (assumes first directory in tarball)
extracted_dir=$(tar -tf "$tar_file" | head -1 | cut -f1 -d"/")

# Validate if the extracted directory exists
if [[ ! -d "$extracted_dir" ]]; then
    echo "Error: Extracted directory '$extracted_dir' does not exist."
    exit 1
fi

echo "Extracted Directory: $extracted_dir"

# Change to the extracted directory
# cd "$extracted_dir" || { echo "Error: Cannot change to directory '$extracted_dir'."; exit 1; }

# Check for package_manifest.ini and determine ArtifactTag
manifest_path=$(find . -type f -name "package_manifest.ini" | head -n 1 || true)
if [ -f "$manifest_path" ]; then
    # Read package_version from package_manifest.ini
    artifact_tag=$(grep '^package_version=' "$manifest_path" | cut -d'=' -f2 | xargs)
else
    # Extract the base name before the first .tar
    artifact_tag=$(basename "$tar_file" .tar.gz | sed 's/\(.*\)\.tar.*/\1/')
fi

# Inform the user about the search criteria
if [ -z "$include_regex" ]; then
    echo "No include regex provided. Including all files except 'package_manifest.ini'."
else
    echo "Searching for binaries that match include regex: '$include_regex'."
fi

if [ -z "$exclude_regex" ]; then
    echo "No exclude extension regex provided, including all file types."
else
    echo "Excluding extensions matching regex: '$exclude_regex'."
fi

# Build the find command dynamically
find_command="find . -type f -regextype posix-extended"

if [ -z "$include_regex" ]; then
    # If no include regex is provided, include all files except 'version.txt'
    find_command="$find_command ! -name 'package_manifest.ini'"
else
    # Include files based on the include regex
    find_command="$find_command -regex \".*($include_regex).*\" ! -name 'package_manifest.ini'"
fi

# Exclude files based on the exclude regex, if provided
if [ -n "$exclude_regex" ]; then
    find_command="$find_command ! -regex \".*\.($exclude_regex)$\""
fi

# Execute the find command and capture the binary paths
binary_paths=$(eval "$find_command")

# Initialize an empty array for JSON
json_array=()

# Populate the JSON array
while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue
    json_array+=("\"$line\"")
done <<< "$binary_paths"

# Convert the array to a comma-separated string
json_binary_paths=$(IFS=,; echo "${json_array[*]}")

# Prepare the JSON output
json_output=$(cat <<EOF
{
  "artifactTag": "$artifact_tag",
  "binaryFilePaths": [
    $json_binary_paths
  ],
  "filePath": "$(pwd)"
}
EOF
)

cd ..

# Define the output JSON file path (placed one level up from the extracted directory)
# output_json=$WORKSPACE+"/ssd.json"
output_json="${WORKSPACE:-.}/ssd.json"


# Write the JSON output to the file
echo -e "$json_output" > "$output_json"

echo "Binaries list and file path saved to '$output_json'"
